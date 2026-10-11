import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/chain_config.dart';
import '../models/token_info.dart';
import '../utils/units.dart';
import 'db_service.dart';
import 'rpc_client.dart';
import 'token_list_service.dart';

/// ผลการดึงยอดโทเค็นหลายตัว — แยก "ดึงได้" กับ "ดึงไม่ได้" ออกจากกัน
/// ตัวที่ดึงไม่ได้ต้องคงยอดเดิมไว้ (ห้ามกลายเป็น 0)
class TokenBalanceResult {
  /// ที่อยู่สัญญา (ตัวเล็ก) → ยอดหน่วยย่อย
  final Map<String, BigInt> balances;

  /// ที่อยู่สัญญา (ตัวเล็ก) ที่รอบนี้ดึงไม่สำเร็จ
  final Set<String> failed;

  const TokenBalanceResult(this.balances, this.failed);
}

/// Service for querying ERC-20 token contracts (TPIX Chain เป็นหลัก)
class TokenService {
  // ERC-20 function signatures (first 4 bytes of keccak256 hash)
  static const _nameSelector = '0x06fdde03';       // name()
  static const _symbolSelector = '0x95d89b41';     // symbol()
  static const _decimalsSelector = '0x313ce567';   // decimals()
  static const _balanceOfSelector = '0x70a08231';  // balanceOf(address)
  static const _totalSupplySelector = '0x18160ddd'; // totalSupply()

  /// รายการคู่เทรดของ TPIX DEX — แหล่งความจริงว่าบน TPIX Chain มีโทเค็นอะไรบ้าง
  static const dexPairsUrl = 'https://tpix.online/api/v1/dex/pairs';

  static const _zeroAddress = '0x0000000000000000000000000000000000000000';

  /// เทสต์เปลี่ยนเป็น MockClient ได้
  @visibleForTesting
  static http.Client Function() clientFactory = http.Client.new;

  static RpcClient _rpcFor(int chainId) =>
      RpcClient.forChain(ChainConfig.byId(chainId));

  /// Fetch token info from a smart contract address on TPIX Chain
  /// Returns null if address is not a valid ERC-20 contract
  /// throws [RpcUnavailableException] เมื่อติดต่อเชนไม่ได้ (คนละเรื่องกับ "ไม่ใช่โทเค็น")
  static Future<TokenInfo?> fetchTokenInfo(String contractAddress, int walletSlot) async {
    final addr = contractAddress.toLowerCase();
    if (!RegExp(r'^0x[0-9a-fA-F]{40}$').hasMatch(addr)) return null;
    final rpc = _rpcFor(4289);

    Future<String?> call(String data) async {
      try {
        return await rpc.ethCall(addr, data);
      } on RpcException {
        return null; // revert = ไม่มีฟังก์ชันนี้ = ไม่ใช่ ERC-20
      }
    }

    // Query name, symbol, decimals in parallel
    final results = await Future.wait([
      call(_nameSelector),
      call(_symbolSelector),
      call(_decimalsSelector),
    ]);

    // ชื่อ/สัญลักษณ์บนสัญญาใครก็ตั้งได้ — ตัดอักขระซ่อน/สลับทิศ และความยาวผิดปกติ
    // (ยังเป็นค่าจากสัญญา แค่แสดงผลได้อย่างปลอดภัย)
    final name = TokenListService.sanitizeOnChainText(_decodeString(results[0]), 64);
    final symbol = TokenListService.sanitizeOnChainText(_decodeString(results[1]), 32);
    final decimals = _decodeUint(results[2]);

    if (name == null || symbol == null) return null;
    // ทศนิยมเกิน 36 = ข้อมูลเพี้ยน (ERC-20 จริงไม่มีใครใช้) ป้องกันการคำนวณระเบิด
    if (decimals != null && (decimals < 0 || decimals > 36)) return null;

    return TokenInfo(
      contractAddress: addr,
      name: name,
      symbol: symbol,
      decimals: decimals ?? 18,
      walletSlot: walletSlot,
    );
  }

  /// ยอดโทเค็น (หน่วยย่อย) ของกระเป๋า
  ///
  /// ★ ดึงไม่ได้ = null (ห้ามคืน 0) — ของเดิมคืน 0 ทุกครั้งที่ RPC สะดุด
  ///   และกับโทเค็นที่สัญญาหายไปหลัง re-genesis ก็โชว์ 0 ไปตลอดกาลแบบเงียบๆ
  static Future<BigInt?> getTokenBalance(
    String contractAddress,
    String walletAddress, {
    int chainId = 4289,
  }) async {
    try {
      // balanceOf(address) — pad address to 32 bytes
      final paddedAddr = walletAddress.toLowerCase().replaceFirst('0x', '').padLeft(64, '0');
      final result = await _rpcFor(chainId)
          .ethCall(contractAddress.toLowerCase(), '$_balanceOfSelector$paddedAddr');
      if (result == null || result == '0x') return null; // ไม่มีสัญญา/ไม่ใช่ ERC-20
      return RpcClient.parseQuantity(result.length > 66 ? result.substring(0, 66) : result);
    } catch (_) {
      return null;
    }
  }

  /// ยอดแบบทศนิยม (แสดงผล) — null เมื่อดึงไม่ได้
  static Future<double?> getFormattedBalance(String contractAddress, String walletAddress, int decimals) async {
    final raw = await getTokenBalance(contractAddress, walletAddress);
    return raw == null ? null : Units.toDouble(raw, decimals);
  }

  /// ดึงยอดของโทเค็นทุกตัวที่ให้มา (ขนานกัน) — ตัวที่ล้มอยู่ใน [TokenBalanceResult.failed]
  static Future<TokenBalanceResult> getBalances(
    List<TokenInfo> tokens,
    String walletAddress,
  ) async {
    final entries = await Future.wait(tokens.map((t) async => MapEntry(
          t.contractAddress.toLowerCase(),
          await getTokenBalance(t.contractAddress, walletAddress, chainId: t.chainId),
        )));
    final balances = <String, BigInt>{};
    final failed = <String>{};
    for (final e in entries) {
      final v = e.value;
      if (v == null) {
        failed.add(e.key);
      } else {
        balances[e.key] = v;
      }
    }
    return TokenBalanceResult(balances, failed);
  }

  /// bytecode ว่าง = ที่อยู่นี้ไม่มีสัญญา
  static bool isEmptyCode(String code) {
    final c = code.trim().toLowerCase();
    return c.isEmpty || c == '0x' || c == '0x0';
  }

  /// ตรวจว่าสัญญาของโทเค็นบน TPIX Chain ยังมีอยู่ไหม (เช่นเพิ่มไว้ก่อน re-genesis)
  ///
  /// - missing: eth_getCode "ตอบสำเร็จ" และได้ "0x" = ไม่มีสัญญาที่ที่อยู่นั้นแล้วจริงๆ
  /// - present: มี bytecode
  /// - ตัวที่ RPC ล้ม ไม่อยู่ในทั้งสองชุด = "ไม่รู้" → ผู้เรียกคงสถานะเดิมไว้
  ///   (ห้ามติดป้ายว่าสัญญาหาย หรือปลดป้าย เพียงเพราะเน็ตหลุด)
  static Future<({Set<String> missing, Set<String> present})> checkContracts(
    List<TokenInfo> tokens,
  ) async {
    final missing = <String>{};
    final present = <String>{};
    final candidates = tokens.where((t) => t.chainId == 4289).toList();
    if (candidates.isEmpty) return (missing: missing, present: present);
    final rpc = _rpcFor(4289);
    await Future.wait(candidates.map((t) async {
      try {
        final code = await rpc.getCode(t.contractAddress);
        (isEmptyCode(code) ? missing : present).add(t.contractAddress.toLowerCase());
      } catch (_) {
        // ไม่รู้ = ไม่ตัดสิน
      }
    }));
    return (missing: missing, present: present);
  }

  /// Verify if a contract is a valid ERC-20 by checking totalSupply
  static Future<bool> isErc20Contract(String contractAddress) async {
    try {
      final result = await _rpcFor(4289).ethCall(contractAddress.toLowerCase(), _totalSupplySelector);
      return result != null && result != '0x' && result.length > 2;
    } catch (_) {
      return false;
    }
  }

  // ================================================================
  // โทเค็นบน TPIX Chain (จาก TPIX DEX)
  // ================================================================

  static List<TokenDef>? _dexTokensCache;
  static DateTime? _dexTokensAt;
  static const _dexTokensTtl = Duration(minutes: 10);

  /// แปลงผลของ /api/v1/dex/pairs เป็นรายการโทเค็น (pure — เทสต์ได้)
  ///
  /// เอาเฉพาะฝั่ง quote ของคู่ที่ base เป็น TPIX native (ที่อยู่ 0x000…0)
  /// บนเชน 4289 และเปิดใช้งานอยู่ — วันนี้คือ USDT ตัวเดียว
  /// ข้อมูลผิดรูปแบบ → ข้ามทิ้ง ไม่เดา
  @visibleForTesting
  static List<TokenDef> parseDexPairs(String body) {
    final dynamic decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      return const [];
    }
    if (decoded is! Map || decoded['success'] != true) return const [];
    final data = decoded['data'];
    if (data is! List) return const [];

    final seen = <String>{};
    final out = <TokenDef>[];
    for (final pair in data) {
      if (pair is! Map) continue;
      if (pair['chain_id'] != 4289) continue;
      if (pair['is_active'] == false) continue;
      final base = pair['base_address'];
      if (base is! String || base.toLowerCase() != _zeroAddress) continue;

      final address = pair['quote_address'];
      final symbol = pair['quote_asset'];
      final decimals = pair['quote_decimals'];
      if (address is! String || !RegExp(r'^0x[0-9a-fA-F]{40}$').hasMatch(address)) continue;
      if (address.toLowerCase() == _zeroAddress) continue;
      if (symbol is! String || symbol.isEmpty || symbol.length > 16) continue;
      if (decimals is! int || decimals < 0 || decimals > 36) continue;
      if (!seen.add(address.toLowerCase())) continue;

      final logo = pair['quote_logo'];
      out.add(TokenDef(
        address: address,
        // API ไม่ส่งชื่อเต็มมา — ใช้ชื่อในตัวแอปถ้ารู้จัก ไม่งั้นใช้สัญลักษณ์ (ไม่เดาชื่อ)
        name: _builtInName(address) ?? symbol,
        symbol: symbol,
        decimals: decimals,
        logoUrl: logo is String && logo.startsWith('https://') ? logo : null,
      ));
    }
    return out;
  }

  static String? _builtInName(String address) {
    for (final t in ChainConfig.tpix.knownTokens) {
      if (t.address.toLowerCase() == address.toLowerCase()) return t.name;
    }
    return null;
  }

  /// โทเค็นมาตรฐานของ TPIX Chain = ที่ DEX ประกาศ ∪ ค่าเริ่มต้นในตัวแอป
  ///
  /// API ใช้ไม่ได้ → ใช้ค่าเริ่มต้นในตัวแอปอย่างเดียว (USDT_TPIX)
  /// ซ้ำกัน → ข้อมูลจาก API ชนะ (โลโก้/ทศนิยมล่าสุดจากเซิร์ฟเวอร์)
  static Future<List<TokenDef>> tpixChainTokens({bool forceRefresh = false}) async {
    final now = DateTime.now();
    if (!forceRefresh &&
        _dexTokensCache != null &&
        _dexTokensAt != null &&
        now.difference(_dexTokensAt!) < _dexTokensTtl) {
      return _mergeWithBuiltIn(_dexTokensCache!);
    }

    final client = clientFactory();
    try {
      final res = await client.get(Uri.parse(dexPairsUrl), headers: const {
        'Accept': 'application/json',
        'User-Agent': 'TPIX-Wallet (Flutter)',
      }).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        _dexTokensCache = parseDexPairs(res.body);
        _dexTokensAt = now;
      }
    } catch (e) {
      debugPrint('TokenService.tpixChainTokens: ${e.runtimeType}');
    } finally {
      client.close();
    }
    return _mergeWithBuiltIn(_dexTokensCache ?? const []);
  }

  static List<TokenDef> _mergeWithBuiltIn(List<TokenDef> fromApi) {
    final byAddr = <String, TokenDef>{
      for (final t in ChainConfig.tpix.knownTokens) t.address.toLowerCase(): t,
    };
    for (final t in fromApi) {
      byAddr[t.address.toLowerCase()] = t;
    }
    return byAddr.values.toList();
  }

  /// ล้างแคช (เทสต์)
  @visibleForTesting
  static void resetCache() {
    _dexTokensCache = null;
    _dexTokensAt = null;
  }

  /// เพิ่มโทเค็นมาตรฐานของ TPIX Chain ให้กระเป๋าช่องนี้ "ครั้งเดียว"
  ///
  /// จดไว้ว่าเคยเพิ่มอะไรให้แล้ว — ถ้าผู้ใช้ลบทิ้งเอง ครั้งหน้าต้องไม่โผล่กลับมาอีก
  /// (ผู้ใช้ยังเพิ่มเองได้จากหน้าเพิ่มโทเค็น)
  /// คืนรายการโทเค็นมาตรฐานที่ใช้ (ผู้เรียกเอาโลโก้ไปใช้ต่อได้ ไม่ต้องยิง API ซ้ำ)
  static Future<List<TokenDef>> ensureDefaultTokens(int walletSlot) async {
    final defaults = await tpixChainTokens();
    if (walletSlot <= 0 || defaults.isEmpty) return defaults;

    final prefs = await SharedPreferences.getInstance();
    final key = 'auto_tokens_4289_slot_$walletSlot';
    final done = (prefs.getStringList(key) ?? const <String>[]).toSet();
    var changed = false;

    for (final d in defaults) {
      final addr = d.address.toLowerCase();
      if (done.contains(addr)) continue;
      if (!await DbService.tokenExists(addr, walletSlot)) {
        await DbService.addToken(TokenInfo(
          contractAddress: addr,
          name: d.name,
          symbol: d.symbol,
          decimals: d.decimals,
          walletSlot: walletSlot,
          logoUrl: d.logoUrl,
        ));
      }
      done.add(addr);
      changed = true;
    }
    if (changed) await prefs.setStringList(key, done.toList());
    return defaults;
  }

  /// Get list of known/popular tokens for any chain.
  static List<Map<String, String>> knownTokensForChain(int chainId) {
    final chain = ChainConfig.byId(chainId);
    return chain.knownTokens.map((t) => {
      'address': t.address,
      'name': t.name,
      'symbol': t.symbol,
    }).toList();
  }

  // ================================================================
  // ABI decoding
  // ================================================================

  /// Decode ABI-encoded string return value
  static String? _decodeString(String? hex) {
    if (hex == null || hex.length < 130) {
      return _decodeBytes32(hex); // บางโทเค็นคืน bytes32 แทน string
    }
    try {
      final raw = hex.replaceFirst('0x', '');
      // ABI string: bytes32 offset, bytes32 length, then data
      // offset is at 0..63, length at 64..127, data starts at 128
      final lengthHex = raw.substring(64, 128);
      final length = int.parse(lengthHex, radix: 16);
      if (length == 0 || length > 256) return null;

      final dataHex = raw.substring(128, 128 + length * 2);
      final bytes = <int>[];
      for (var i = 0; i < dataHex.length; i += 2) {
        bytes.add(int.parse(dataHex.substring(i, i + 2), radix: 16));
      }
      return utf8.decode(bytes, allowMalformed: true).trim();
    } catch (_) {
      return _decodeBytes32(hex);
    }
  }

  static String? _decodeBytes32(String? hex) {
    if (hex == null || hex.length < 66) return null;
    try {
      final raw = hex.replaceFirst('0x', '');
      final bytes = <int>[];
      for (var i = 0; i < raw.length && i < 64; i += 2) {
        final b = int.parse(raw.substring(i, i + 2), radix: 16);
        if (b == 0) break;
        bytes.add(b);
      }
      final s = utf8.decode(bytes, allowMalformed: true).trim();
      return s.isNotEmpty ? s : null;
    } catch (_) {
      return null;
    }
  }

  /// Decode ABI-encoded uint256 return value
  static int? _decodeUint(String? hex) {
    if (hex == null || hex.length < 66) return null;
    try {
      final raw = hex.replaceFirst('0x', '');
      return int.parse(raw.substring(0, 64), radix: 16);
    } catch (_) {
      return null;
    }
  }
}
