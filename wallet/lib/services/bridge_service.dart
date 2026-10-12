/// TPIX Wallet — สะพานข้ามเชน: คุยกับเว็บ (อ่านอย่างเดียว) + เตรียมธุรกรรมบนเชน
///
/// สะพานจริงที่เว็บใช้อยู่ (ThaiXTrade: /bridge + app/Services/Bridge/*) มี 2 ตัว:
///   1. USDT — ฝาก: transfer(vault, จำนวน) ของ USDT จริงบน ETH/BSC/Polygon/Arbitrum/OP/Avalanche
///             → เซิร์ฟเวอร์ mint USDT_TPIX ให้ที่อยู่เดียวกันบนเชน 4289
///             ถอน: USDT_TPIX.bridgeBurn(จำนวน, เชนปลายทาง, ที่อยู่) บนเชน 4289 → เซิร์ฟเวอร์จ่าย USDT จริง
///   2. TPIX ⇄ wTPIX (BSC) — ไป BSC: vault.lock() แนบ TPIX บนเชน 4289 (ผู้รับ = ที่อยู่เดียวกัน)
///             กลับ TPIX: wTPIX.burn(จำนวน) บน BSC (ผู้รับ = ที่อยู่เดียวกันบนเชน 4289)
///
/// แอป "ไม่แจ้ง" เซิร์ฟเวอร์ว่าโอนแล้ว — ตัวสแกนของเซิร์ฟเวอร์อ่านจากเชนเอง แอปแค่ถามสถานะด้วย tx hash
/// (สะพานรุ่นเก่าที่โอนเข้ากระเป๋าค่าธรรมเนียมแล้วยิง /bridge/fee, /bridge/initiate ถูกถอดจากเซิร์ฟเวอร์แล้ว)
///
/// ด่านความปลอดภัย (fail-closed):
///   - ฟอร์มเปิดเมื่อเว็บบอก enabled และที่อยู่สัญญาทุกตัวที่ต้องใช้ครบ + ถูกรูป (ไม่ใช่ศูนย์, EIP-55)
///   - chain id ต้องเป็นเชนที่แอปตรึงไว้ ([BridgeChains]) — RPC ใช้ของแอปเอง ไม่ใช้ RPC ที่เว็บส่งมา
///   - ก่อนเซ็นทุกครั้ง ([BridgeTx.prepare]): RPC ต้องตอบ chain id ตรง · ทศนิยมโทเค็นบนเชนต้องตรงกับเว็บ
///     · ยอดเหรียญพอ · eth_estimateGas ผ่าน (สัญญาจะ revert = บอกก่อนถาม PIN) · เหรียญหลักพอจ่ายแก๊ส
///
/// Developed by Xman Studio
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:web3dart/crypto.dart' show bytesToHex;
import 'package:web3dart/web3dart.dart';

import '../models/chain_config.dart';
import '../utils/units.dart';
import 'bridge_rules.dart';
import 'rpc_client.dart';
import 'token_list_service.dart';

// ════════════════════════════════════════════════════════════════
//  ข้อผิดพลาด
// ════════════════════════════════════════════════════════════════

/// ติดต่อเว็บไม่ได้ / ตอบผิดรูป (เน็ตหลุด, timeout, 5xx, หน้า HTML ของ Cloudflare)
class BridgeUnavailableException implements Exception {
  const BridgeUnavailableException();

  @override
  String toString() => 'Bridge server unavailable';
}

/// เว็บจำกัดความถี่ (429) — หยุดถามรอบนี้ ลองใหม่รอบหน้า
class BridgeRateLimitedException implements Exception {
  const BridgeRateLimitedException();

  @override
  String toString() => 'Bridge server rate limited';
}

// ════════════════════════════════════════════════════════════════
//  เชนที่แอปเซ็นธุรกรรมของสะพานได้
// ════════════════════════════════════════════════════════════════

/// ข้อมูลเชนที่ตรึงไว้ในแอป — ต้องรู้ RPC + สัญลักษณ์เหรียญหลัก (ไว้บอกค่าแก๊ส) เอง
class BridgeChainProfile {
  final int chainId;
  final String name;
  final String nativeSymbol;
  final List<String> rpcUrls;
  final String explorer;

  const BridgeChainProfile({
    required this.chainId,
    required this.name,
    required this.nativeSymbol,
    required this.rpcUrls,
    required this.explorer,
  });

  /// เชน TPIX ไม่มีค่าแก๊ส
  bool get gasless => chainId == bridgeTpixChainId;
}

class BridgeChains {
  BridgeChains._();

  /// เชนนอก [ChainConfig.all] ที่สะพาน USDT รับฝาก — RPC ฟรีชุดเดียวกับที่เซิร์ฟเวอร์สะพานใช้
  /// (ตรวจสดด้วย eth_chainId เมื่อ 2026-10-12) · ไม่เพิ่มเข้า ChainConfig.all เพราะจะไปโผล่
  /// ในหน้าสวอป/WalletConnect/ยอดหน้าแรกด้วย
  static const List<BridgeChainProfile> _extra = [
    BridgeChainProfile(
      chainId: 42161,
      name: 'Arbitrum One',
      nativeSymbol: 'ETH',
      rpcUrls: [
        'https://arb1.arbitrum.io/rpc',
        'https://arbitrum-one-rpc.publicnode.com',
        'https://arbitrum.drpc.org',
      ],
      explorer: 'https://arbiscan.io',
    ),
    BridgeChainProfile(
      chainId: 10,
      name: 'OP Mainnet',
      nativeSymbol: 'ETH',
      rpcUrls: [
        'https://optimism-rpc.publicnode.com',
        'https://mainnet.optimism.io',
        'https://optimism.drpc.org',
      ],
      explorer: 'https://optimistic.etherscan.io',
    ),
    BridgeChainProfile(
      chainId: 43114,
      name: 'Avalanche C-Chain',
      nativeSymbol: 'AVAX',
      rpcUrls: [
        'https://avalanche-c-chain-rpc.publicnode.com',
        'https://api.avax.network/ext/bc/C/rpc',
        'https://avalanche.drpc.org',
      ],
      explorer: 'https://snowtrace.io',
    ),
  ];

  /// เชนที่ใช้กับสะพาน (USDT: 1, 56, 137, 42161, 10, 43114 · TPIX: 4289 · wTPIX: 56)
  static final Map<int, BridgeChainProfile> profiles = {
    for (final c in [ChainConfig.tpix, ChainConfig.ethereum, ChainConfig.bsc, ChainConfig.polygon])
      c.chainId: BridgeChainProfile(
        chainId: c.chainId,
        name: c.name,
        nativeSymbol: c.symbol,
        rpcUrls: c.rpcUrls,
        explorer: c.explorerUrl,
      ),
    for (final p in _extra) p.chainId: p,
  };

  /// เชน BSC ที่สะพาน wTPIX ยอมรับ — testnet (97) ไม่รองรับในแอป
  static const int wtpixBscChainId = 56;

  static BridgeChainProfile? of(int chainId) => profiles[chainId];

  static final Map<int, RpcClient> _extraClients = {};

  /// RPC ของเชนนั้น — เชนที่อยู่ใน ChainConfig ใช้ client กลางตัวเดียวกับที่ sendEvmTransaction ใช้
  /// (ตรวจ chain id แล้วส่งบน client เดียวกัน)
  static RpcClient rpc(int chainId) {
    for (final c in ChainConfig.all) {
      if (c.chainId == chainId) return RpcClient.forChain(c);
    }
    final profile = profiles[chainId];
    if (profile == null) throw const BridgeCheckException('bridge.errChainUnsupported');
    return _extraClients.putIfAbsent(chainId, () => RpcClient(profile.rpcUrls));
  }

  /// URL ที่ส่งให้ sendEvmTransaction — เชนใน ChainConfig ถูกจับคู่ด้วย chain id อยู่แล้ว
  /// เชนนอกลิสต์ใช้ตัวที่เพิ่งตอบ chain id ถูก (activeUrl หลังตรวจ)
  static String sendRpcUrl(int chainId) {
    for (final c in ChainConfig.all) {
      if (c.chainId == chainId) return c.rpcUrl;
    }
    return rpc(chainId).activeUrl;
  }

  /// เทสต์ใช้แทน client จริงของเชนนอก ChainConfig (null = ล้าง)
  @visibleForTesting
  static void overrideExtraRpc(int chainId, RpcClient? client) {
    if (client == null) {
      _extraClients.remove(chainId);
    } else {
      _extraClients[chainId] = client;
    }
  }
}

// ════════════════════════════════════════════════════════════════
//  ข้อมูลจากเว็บ — ตรวจทุกช่องก่อนใช้
// ════════════════════════════════════════════════════════════════

String? _addr(Object? v) => isValidEvmAddress(v) ? (v as String).trim() : null;

int _int(Object? v, [int fallback = 0]) {
  if (v is int) return v;
  if (v is String && RegExp(r'^\d{1,12}$').hasMatch(v)) return int.parse(v);
  return fallback;
}

/// เลข chain id ที่เป็นบวก — อย่างอื่น = null
int? _chainId(Object? v) {
  final i = _int(v, -1);
  return i > 0 ? i : null;
}

String? _label(Object? v, [int max = 40]) =>
    v is String ? TokenListService.sanitizeOnChainText(v, max) : null;

Map<String, dynamic> _map(Object? v) =>
    v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

/// ทศนิยมของโทเค็นที่รับได้ (กันค่าแปลกๆ ทำให้คำนวณหน่วยพัง)
bool _decimalsOk(int d) => d >= 0 && d <= 36;

/// หนึ่งเชนของสะพาน USDT
class UsdtBridgeChain {
  final int chainId;
  final String name;
  final String nativeSymbol;
  final bool serverEnabled;

  /// สัญญา USDT บนเชนนี้ — null = เว็บส่งมาผิดรูป (เชนนี้ใช้ไม่ได้)
  final String? usdtAddress;
  final int usdtDecimals;
  final String usdtSymbol;
  final String? explorer;

  /// ค่าธรรมเนียมถอน (USDT) — ข้อความจากเว็บ
  final String withdrawFee;
  final int etaMinutes;

  const UsdtBridgeChain({
    required this.chainId,
    required this.name,
    required this.nativeSymbol,
    required this.serverEnabled,
    required this.usdtAddress,
    required this.usdtDecimals,
    required this.usdtSymbol,
    required this.explorer,
    required this.withdrawFee,
    required this.etaMinutes,
  });

  factory UsdtBridgeChain.fromServer(Map<String, dynamic> j) {
    final fee = j['withdraw_fee'];
    final feeText = fee is String || fee is num ? fee.toString() : '';
    return UsdtBridgeChain(
      chainId: _int(j['chain_id']),
      name: _label(j['name']) ?? '—',
      nativeSymbol: _label(j['native'], 10) ?? '',
      serverEnabled: j['enabled'] == true,
      usdtAddress: _addr(j['usdt_address']),
      usdtDecimals: _int(j['usdt_decimals'], -1),
      usdtSymbol: _label(j['usdt_symbol'], 12) ?? 'USDT',
      explorer: safeHttpsUrl(j['explorer']),
      // ค่าธรรมเนียมอ่านไม่ออก = ถอนไปเชนนี้ไม่ได้ (ไม่เดาว่าเป็น 0)
      withdrawFee: parseAmountToUnits(feeText, usdtTpixDecimals) != null ? feeText : '',
      etaMinutes: _int(j['eta_minutes'], 10),
    );
  }

  bool get _contractOk => usdtAddress != null && _decimalsOk(usdtDecimals) && chainId > 0;

  /// แอปมีข้อมูลเชนนี้ (RPC ที่ตรึงไว้) ให้เซ็นธุรกรรมฝากได้
  bool get appSupported => BridgeChains.of(chainId) != null && chainId != bridgeTpixChainId;

  /// ฝากจากแอปได้: เว็บเปิดเชนนี้ + สัญญาถูกรูป + แอปรู้จักเชน
  bool get depositable => serverEnabled && _contractOk && appSupported;

  /// ถอนไปเชนนี้ได้: เว็บเปิดเชนนี้ + ค่าธรรมเนียมอ่านออก (แอปไม่ต้องเซ็นอะไรบนเชนปลายทาง)
  bool get withdrawable => serverEnabled && chainId > 0 && chainId != bridgeTpixChainId && withdrawFee.isNotEmpty;
}

/// /api/v1/bridge/info (สะพาน USDT)
class UsdtBridgeInfo {
  final bool enabled;
  final bool installed;
  final String? vaultAddress;
  final int tpixChainId;
  final String? usdtTpix;
  final int usdtTpixDecimalsFromServer;
  final String? tpixExplorer;
  final List<UsdtBridgeChain> chains;
  final Map<String, dynamic> limits;

  const UsdtBridgeInfo({
    required this.enabled,
    required this.installed,
    required this.vaultAddress,
    required this.tpixChainId,
    required this.usdtTpix,
    required this.usdtTpixDecimalsFromServer,
    required this.tpixExplorer,
    required this.chains,
    required this.limits,
  });

  factory UsdtBridgeInfo.fromServer(Map<String, dynamic> d) {
    final tpix = _map(d['tpix']);
    final chains = <UsdtBridgeChain>[];
    for (final c in (d['chains'] is List ? d['chains'] as List : const [])) {
      if (c is Map) chains.add(UsdtBridgeChain.fromServer(Map<String, dynamic>.from(c)));
    }
    return UsdtBridgeInfo(
      enabled: d['enabled'] == true,
      installed: d['installed'] == true,
      vaultAddress: _addr(d['vault_address']),
      tpixChainId: _int(tpix['chain_id']),
      usdtTpix: _addr(tpix['usdt_tpix']),
      usdtTpixDecimalsFromServer: _int(tpix['usdt_decimals'], -1),
      tpixExplorer: safeHttpsUrl(tpix['explorer']),
      chains: chains.take(20).toList(),
      limits: _map(d['limits']),
    );
  }

  /// ที่อยู่สัญญา + เชนตรงกับที่แอปรู้จัก (ไม่ครบ/ผิด = ไม่เปิดฟอร์ม แม้เว็บบอกเปิด)
  bool get configOk =>
      vaultAddress != null &&
      usdtTpix != null &&
      tpixChainId == bridgeTpixChainId &&
      usdtTpixDecimalsFromServer == usdtTpixDecimals;

  /// เปิดให้กรอกฟอร์ม (fail-closed)
  bool get open => enabled && configOk;

  UsdtBridgeChain? chain(int chainId) {
    for (final c in chains) {
      if (c.chainId == chainId) return c;
    }
    return null;
  }

  String chainName(int chainId) =>
      chainId == bridgeTpixChainId ? 'TPIX Chain' : (chain(chainId)?.name ?? BridgeChains.of(chainId)?.name ?? '#$chainId');

  String? explorerFor(int chainId) => chainId == bridgeTpixChainId
      ? (tpixExplorer ?? ChainConfig.tpix.explorerUrl)
      : (chain(chainId)?.explorer ?? BridgeChains.of(chainId)?.explorer);
}

/// /api/v1/bridge/info?asset=tpix (สะพาน TPIX ⇄ wTPIX)
class WtpixBridgeInfo {
  final bool enabled;
  final bool installed;
  final int tpixChainId;
  final String? vaultAddress;
  final String? tpixExplorer;
  final int tpixEtaMinutes;
  final int bscChainId;
  final String bscName;
  final String? wtpixAddress;
  final String? minterAddress;
  final String? bscExplorer;
  final int bscEtaMinutes;
  final String tokenSymbol;
  final int tokenDecimals;

  /// data ทั้งก้อน (limits / vault / minter) — ส่งให้ [checkWtpixAmount] ตรงๆ แบบเว็บ
  final Map<String, dynamic> raw;

  const WtpixBridgeInfo({
    required this.enabled,
    required this.installed,
    required this.tpixChainId,
    required this.vaultAddress,
    required this.tpixExplorer,
    required this.tpixEtaMinutes,
    required this.bscChainId,
    required this.bscName,
    required this.wtpixAddress,
    required this.minterAddress,
    required this.bscExplorer,
    required this.bscEtaMinutes,
    required this.tokenSymbol,
    required this.tokenDecimals,
    required this.raw,
  });

  factory WtpixBridgeInfo.fromServer(Map<String, dynamic> d) {
    final tpix = _map(d['tpix']);
    final bsc = _map(d['bsc']);
    final token = _map(d['token']);
    return WtpixBridgeInfo(
      enabled: d['enabled'] == true,
      installed: d['installed'] == true,
      tpixChainId: _int(tpix['chain_id']),
      vaultAddress: _addr(tpix['vault_address']),
      tpixExplorer: safeHttpsUrl(tpix['explorer']),
      tpixEtaMinutes: _int(tpix['eta_minutes'], 3),
      bscChainId: _int(bsc['chain_id']),
      bscName: _label(bsc['name']) ?? 'BNB Smart Chain',
      wtpixAddress: _addr(bsc['wtpix_address']),
      minterAddress: _addr(bsc['minter_address']),
      bscExplorer: safeHttpsUrl(bsc['explorer']),
      bscEtaMinutes: _int(bsc['eta_minutes'], 2),
      tokenSymbol: _label(token['symbol'], 12) ?? 'wTPIX',
      tokenDecimals: _int(token['decimals'], -1),
      raw: {
        'limits': _map(d['limits']),
        'vault': _map(d['vault']),
        'minter': _map(d['minter']),
      },
    );
  }

  Map<String, dynamic> get limits => raw['limits'] as Map<String, dynamic>;
  Map<String, dynamic> get vault => raw['vault'] as Map<String, dynamic>;
  Map<String, dynamic> get minter => raw['minter'] as Map<String, dynamic>;

  bool get configOk =>
      tpixChainId == bridgeTpixChainId &&
      bscChainId == BridgeChains.wtpixBscChainId &&
      vaultAddress != null &&
      wtpixAddress != null &&
      minterAddress != null &&
      tokenDecimals == tpixDecimals;

  /// เปิดให้กรอกฟอร์ม (fail-closed) — คลังถูก pause เว็บตั้ง enabled=false ให้อยู่แล้ว
  bool get open => enabled && configOk;

  String? explorerFor(int chainId) => chainId == bridgeTpixChainId
      ? (tpixExplorer ?? ChainConfig.tpix.explorerUrl)
      : (bscExplorer ?? ChainConfig.bsc.explorerUrl);
}

/// หนึ่งแถวในประวัติสะพานของกระเป๋า
class BridgeHistoryRow {
  /// USDT: deposit/withdraw · wTPIX: to_bsc/to_tpix
  final String kind;
  final String state;
  final String? amount;

  /// ฝาก: เชนต้นทาง · ถอน: เชนปลายทาง
  final int? chainId;
  final String? txHash;

  const BridgeHistoryRow({
    required this.kind,
    required this.state,
    this.amount,
    this.chainId,
    this.txHash,
  });
}

final _statePattern = RegExp(r'^[a-z_]{1,40}$');
final _amountTextPattern = RegExp(r'^\d{1,30}(\.\d{1,18})?$');

String _state(Object? v) => v is String && _statePattern.hasMatch(v) ? v : 'unknown';
String? _amount(Object? v) => v is String && _amountTextPattern.hasMatch(v) ? v : null;
String? _hash(Object? v) => v is String && isTxHash(v) ? v.toLowerCase() : null;

// ════════════════════════════════════════════════════════════════
//  API (อ่านอย่างเดียว)
// ════════════════════════════════════════════════════════════════

class BridgeService {
  BridgeService._();

  static const String apiBase = 'https://tpix.online/api/v1/bridge';

  /// หน้า Proof of Reserves บนเว็บ (เปิดในเบราว์เซอร์)
  static const String reservesUrl = 'https://tpix.online/bridge/reserves';

  /// เทสต์ใช้แทน http.Client จริง
  static http.Client Function() clientFactory = http.Client.new;

  static const _timeout = Duration(seconds: 12);

  static Future<Map<String, dynamic>> _get(String path, {Map<String, String>? query}) async {
    final client = clientFactory();
    try {
      var uri = Uri.parse('$apiBase$path');
      if (query != null) uri = uri.replace(queryParameters: query);
      final res = await client.get(uri, headers: const {
        'Accept': 'application/json',
        // ไม่มี User-Agent = Cloudflare หน้า tpix.online ตอบหน้า HTML บล็อก
        'User-Agent': 'TPIX-Wallet (Flutter)',
      }).timeout(_timeout);
      if (res.statusCode == 429) throw const BridgeRateLimitedException();
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw const BridgeUnavailableException();
      }
      final dynamic body;
      try {
        body = jsonDecode(res.body);
      } on FormatException {
        throw const BridgeUnavailableException();
      }
      if (body is! Map || body['success'] != true || body['data'] is! Map) {
        throw const BridgeUnavailableException();
      }
      return Map<String, dynamic>.from(body['data'] as Map);
    } on BridgeUnavailableException {
      rethrow;
    } on BridgeRateLimitedException {
      rethrow;
    } catch (e) {
      // ไม่พิมพ์ข้อความเต็ม — อาจมี URL/รายละเอียดภายใน
      debugPrint('BridgeService$path: ${e.runtimeType}');
      throw const BridgeUnavailableException();
    } finally {
      client.close();
    }
  }

  static Future<UsdtBridgeInfo> fetchUsdtInfo() async =>
      UsdtBridgeInfo.fromServer(await _get('/info'));

  static Future<WtpixBridgeInfo> fetchWtpixInfo() async =>
      WtpixBridgeInfo.fromServer(await _get('/info', query: const {'asset': 'tpix'}));

  /// สถานะของธุรกรรมต้นทาง (ฝาก USDT / ล็อก TPIX / เผา wTPIX)
  static Future<BridgeStatusView> fetchStatus({
    required bool wtpix,
    required int chainId,
    required String txHash,
  }) async {
    if (!isTxHash(txHash) || chainId <= 0) throw const BridgeUnavailableException();
    final data = await _get('/status/$chainId/${txHash.trim().toLowerCase()}',
        query: wtpix ? const {'asset': 'tpix'} : null);
    return BridgeStatusView.fromServer(data);
  }

  /// สถานะการถอน USDT (burn บนเชน 4289)
  static Future<BridgeStatusView> fetchWithdrawal(String txHash) async {
    if (!isTxHash(txHash)) throw const BridgeUnavailableException();
    return BridgeStatusView.fromServer(await _get('/withdrawals/${txHash.trim().toLowerCase()}'));
  }

  /// ประวัติสะพาน USDT ของกระเป๋า (ฝาก + ถอน ล่าสุด)
  static Future<List<BridgeHistoryRow>> fetchUsdtHistory(String wallet) async {
    if (!isValidEvmAddress(wallet)) return const [];
    final d = await _get('/history/${wallet.trim().toLowerCase()}');
    return [
      for (final r in (d['deposits'] is List ? d['deposits'] as List : const []))
        if (r is Map)
          BridgeHistoryRow(
            kind: usdtDeposit,
            state: usdtDepositRowState(_state(r['status'])),
            amount: _amount(r['amount']),
            chainId: _chainId(r['source_chain_id']),
            txHash: _hash(r['tx_hash']),
          ),
      for (final r in (d['withdrawals'] is List ? d['withdrawals'] as List : const []))
        if (r is Map)
          BridgeHistoryRow(
            kind: usdtWithdraw,
            state: usdtWithdrawalRowState(_state(r['status'])),
            amount: _amount(r['amount']),
            chainId: _chainId(r['target_chain_id']),
            txHash: _hash(r['tx_hash']),
          ),
    ].take(50).toList();
  }

  /// ประวัติสะพาน wTPIX ของกระเป๋า
  static Future<List<BridgeHistoryRow>> fetchWtpixHistory(String wallet) async {
    if (!isValidEvmAddress(wallet)) return const [];
    final d = await _get('/history/${wallet.trim().toLowerCase()}', query: const {'asset': 'tpix'});
    return [
      for (final r in (d['transfers'] is List ? d['transfers'] as List : const []))
        if (r is Map && (r['direction'] == wtpixToBsc || r['direction'] == wtpixToTpix))
          BridgeHistoryRow(
            kind: r['direction'] as String,
            state: _state(r['state']),
            amount: _amount(r['amount']),
            chainId: _chainId(r['source_chain_id']),
            txHash: _hash(r['tx_hash']),
          ),
    ].take(50).toList();
  }
}

// ════════════════════════════════════════════════════════════════
//  ธุรกรรมบนเชน
// ════════════════════════════════════════════════════════════════

/// ธุรกรรมที่ผ่านด่านตรวจแล้ว พร้อมให้ผู้ใช้ยืนยัน + เซ็น
class BridgeTxPlan {
  final int chainId;
  final String rpcUrl;
  final String from;
  final String to;
  final BigInt value;
  final Uint8List data;
  final int gasLimit;
  final BigInt gasPrice;
  final String nativeSymbol;

  const BridgeTxPlan({
    required this.chainId,
    required this.rpcUrl,
    required this.from,
    required this.to,
    required this.value,
    required this.data,
    required this.gasLimit,
    required this.gasPrice,
    required this.nativeSymbol,
  });

  /// ค่าแก๊สสูงสุดที่อาจจ่าย (หน่วยเล็กสุดของเหรียญหลัก) — เชน TPIX = 0
  BigInt get maxFee => gasPrice * BigInt.from(gasLimit);
}

/// ERC-20 ที่ธุรกรรมจะหักออกจากกระเป๋า — ใช้ตรวจทศนิยม + ยอดก่อนเซ็น
typedef BridgeSpend = ({String token, BigInt amount, int decimals});

class BridgeTx {
  BridgeTx._();

  // ── ABI (เฉพาะฟังก์ชันที่สะพานใช้ — ตรวจกับสัญญาใน TPIX-Coin/contracts แล้ว) ──
  //   USDT_TPIX.bridgeBurn(uint256 amount, uint256 targetChainId, string targetAddress)
  //   TPIXBridgeVault.lock() payable — ผู้รับบน BSC = ผู้ล็อก
  //   wTPIX (ERC20Burnable).burn(uint256) — ไม่ต้อง approve · ผู้รับบนเชน TPIX = ผู้เผา
  static const _abiJson = '''
[
 {"type":"function","name":"bridgeBurn","stateMutability":"nonpayable","inputs":[{"name":"amount","type":"uint256"},{"name":"targetChainId","type":"uint256"},{"name":"targetAddress","type":"string"}],"outputs":[]},
 {"type":"function","name":"lock","stateMutability":"payable","inputs":[],"outputs":[]},
 {"type":"function","name":"burn","stateMutability":"nonpayable","inputs":[{"name":"amount","type":"uint256"}],"outputs":[]},
 {"type":"function","name":"balanceOf","stateMutability":"view","inputs":[{"name":"owner","type":"address"}],"outputs":[{"name":"","type":"uint256"}]},
 {"type":"function","name":"decimals","stateMutability":"view","inputs":[],"outputs":[{"name":"","type":"uint8"}]}
]
''';

  static final ContractAbi _abi = ContractAbi.fromJson(_abiJson, 'TPIXBridge');

  static ContractFunction _fn(String name) => _abi.functions.firstWhere((f) => f.name == name);

  /// ERC-20 transfer(vault, จำนวน) — ตัวเข้ารหัสเดียวกับหน้าโอนโทเค็น
  static Uint8List encodeTransfer(String to, BigInt amount) => Units.encodeErc20Transfer(to, amount);

  static Uint8List encodeBridgeBurn(BigInt amount, int targetChainId, String targetAddress) =>
      _fn('bridgeBurn').encodeCall([amount, BigInt.from(targetChainId), targetAddress]);

  static Uint8List encodeLock() => _fn('lock').encodeCall(const []);

  static Uint8List encodeBurn(BigInt amount) => _fn('burn').encodeCall([amount]);

  static String _hex(Uint8List data) => bytesToHex(data, include0x: true);

  /// ยอดโทเค็น — อ่านไม่ได้/ผลผิดรูป = throw (ห้ามถือเป็น 0)
  static Future<BigInt> tokenBalance(RpcClient rpc, String token, String owner) async {
    final out = await rpc.ethCall(
        token, _hex(_fn('balanceOf').encodeCall([EthereumAddress.fromHex(owner)])));
    return _decodeUint('balanceOf', out);
  }

  static Future<int> tokenDecimals(RpcClient rpc, String token) async {
    final out = await rpc.ethCall(token, _hex(_fn('decimals').encodeCall(const [])));
    return _decodeUint('decimals', out).toInt();
  }

  static BigInt _decodeUint(String fn, String? out) {
    if (out == null || out.length < 66) throw const FormatException('empty eth_call result');
    final values = _fn(fn).decodeReturnValues(out);
    final v = values.isEmpty ? null : values.first;
    if (v is! BigInt) throw const FormatException('unexpected eth_call result');
    return v;
  }

  /// RPC ต้องเป็นเชนที่จะเซ็นจริง — ไม่ตรง = ไม่ส่ง (กัน RPC ชี้ผิดเชน แล้วยอด/nonce/แก๊สผิดทั้งหมด)
  static Future<void> verifyChainId(RpcClient rpc, int expected) async {
    final BigInt id;
    try {
      id = RpcClient.parseQuantity(await rpc.call('eth_chainId'));
    } on FormatException {
      throw const BridgeCheckException('bridge.errWrongChain');
    }
    if (id != BigInt.from(expected)) throw const BridgeCheckException('bridge.errWrongChain');
  }

  /// ด่านก่อนเซ็น — ผ่านหมดแล้วค่อยให้ผู้ใช้ยืนยัน/ใส่ PIN (ยังไม่มีอะไรถูกเซ็นหรือส่ง)
  ///
  /// [spend] = ERC-20 ที่จะถูกหัก (ตรวจทศนิยมบนเชนตรงกับเว็บ + ยอดพอ)
  /// [value] = เหรียญหลักที่แนบไป (ล็อก TPIX) — ตรวจยอดพอเช่นกัน
  static Future<BridgeTxPlan> prepare({
    required int chainId,
    required String from,
    required String to,
    required Uint8List data,
    BigInt? value,
    BridgeSpend? spend,
  }) async {
    final profile = BridgeChains.of(chainId);
    if (profile == null) throw const BridgeCheckException('bridge.errChainUnsupported');
    if (!isValidEvmAddress(from) || !isValidEvmAddress(to)) {
      throw const BridgeCheckException('bridge.errNotConfigured');
    }
    final rpc = BridgeChains.rpc(chainId);
    final sendValue = value ?? BigInt.zero;

    try {
      await verifyChainId(rpc, chainId);

      if (spend != null) {
        final int onChainDecimals;
        try {
          onChainDecimals = await tokenDecimals(rpc, spend.token);
        } on FormatException {
          // ที่อยู่นี้ตอบ decimals() ไม่ได้ = ไม่ใช่โทเค็นที่เว็บบอก
          throw const BridgeCheckException('bridge.errTokenMismatch');
        }
        if (onChainDecimals != spend.decimals) {
          // เว็บบอกทศนิยมไม่ตรงกับสัญญาจริง = ห้ามเดา (ส่งผิดหลักได้เป็นพันเท่า)
          throw const BridgeCheckException('bridge.errTokenMismatch');
        }
        if (await tokenBalance(rpc, spend.token, from) < spend.amount) {
          throw const BridgeCheckException('bridge.errInsufficient');
        }
      }
      if (sendValue > BigInt.zero && await rpc.getBalance(from) < sendValue) {
        throw const BridgeCheckException('bridge.errInsufficient');
      }

      // จำลองบนเชนก่อน — สัญญาจะปฏิเสธ (หยุดอยู่/เกินเพดาน) ก็บอกเลย ไม่ต้องให้ใส่ PIN ไปเจอ revert
      final estimated = RpcClient.parseQuantity(await rpc.call('eth_estimateGas', [
        {
          'from': from,
          'to': to,
          if (sendValue > BigInt.zero) 'value': '0x${sendValue.toRadixString(16)}',
          'data': _hex(data),
        }
      ])).toInt();
      final gas = Units.addGasMargin(estimated);

      final price = profile.gasless ? BigInt.zero : await rpc.getGasPrice();
      if (price > BigInt.zero) {
        final need = sendValue + price * BigInt.from(gas);
        if (await rpc.getBalance(from) < need) {
          throw BridgeCheckException('bridge.errGasNeed', {
            'amount': _shortNative(price * BigInt.from(gas)),
            'symbol': profile.nativeSymbol,
          });
        }
      }

      return BridgeTxPlan(
        chainId: chainId,
        rpcUrl: BridgeChains.sendRpcUrl(chainId),
        from: from,
        to: to,
        value: sendValue,
        data: data,
        gasLimit: gas,
        gasPrice: price,
        nativeSymbol: profile.nativeSymbol,
      );
    } on RpcException catch (e) {
      // estimateGas revert / โหนดปฏิเสธ — ยังไม่มีอะไรถูกส่ง
      final key = bridgeErrorKey(e);
      throw BridgeCheckException(key == 'bridge.errTxFailed' ? 'bridge.errWouldRevert' : key);
    } on FormatException {
      throw const BridgeCheckException('bridge.errNetwork');
    }
  }

  /// ค่าแก๊สแบบย่อ (ไว้โชว์) — ปัดขึ้นที่ทศนิยม 6 ตำแหน่ง ไม่ให้ดูน้อยกว่าจริง
  static String _shortNative(BigInt wei) {
    final unit = BigInt.from(10).pow(12); // 1e-6 ของเหรียญ 18 ทศนิยม
    final rounded = ((wei + unit - BigInt.one) ~/ unit) * unit;
    return Units.format(rounded, 18);
  }

  /// ค่าแก๊สสูงสุดของแผน (ไว้โชว์ในกล่องยืนยัน)
  static String feeText(BridgeTxPlan plan) => _shortNative(plan.maxFee);
}
