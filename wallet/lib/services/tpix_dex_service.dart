/// TPIX Wallet — สวอปบนเชน TPIX (4289) ผ่าน TPIX DEX (AMM แบบ Uniswap V2)
///
/// mirror จากแอป TRADE (`mobile-flutter/lib/services/tpix_dex_service.dart`) และเว็บ
/// (`useTpixDex.js`) — กติกาต้องตรงกันทุกแพลตฟอร์ม ไม่งั้นไม้เดียวกันผ่านในแอปหนึ่งแต่โดนบล็อกอีกที่
///
///  - ที่อยู่สัญญา **มาจากทะเบียนบนเซิร์ฟเวอร์** (`/api/v1/dex/config`) เท่านั้น ห้าม hardcode
///    (deploy ใหม่เมื่อไร แอปเก่าที่ฝังที่อยู่ไว้จะชี้ไปสัญญาที่ตายทันที)
///  - fail-closed: ไม่ ready / chain id ไม่ใช่ 4289 / ที่อยู่ผิดรูป = ปิดโหมดนี้ ไม่เดาที่อยู่
///  - ยอด/ราคา/allowance อ่านผ่าน [RpcClient.tpix] (rpc → rpc1 สลับเองเมื่อ Cloudflare บล็อก)
///  - เงินทุกก้อนเป็น BigInt หน่วยเล็กสุด — double ใช้แค่แสดงผล
///  - ค่าธรรมเนียม 0.3% อยู่ในพูล (LP + feeTo) ไม่มีธุรกรรมค่าธรรมเนียมแยกแบบฝั่ง BSC
///  - price impact เพดาน 10% เท่าเว็บ · วัดไม่ได้ = บล็อก (แบบหน้า Swap ของเว็บ)
///  - approve เท่ากับยอดของไม้นี้พอดี ไม่ใช่ไม่จำกัด
///
/// service นี้ไม่แตะกุญแจ — การเซ็น/ส่งเป็นหน้าที่ของ WalletProvider.sendEvmTransaction
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
import 'rpc_client.dart';
import 'swap_service.dart';
import 'token_service.dart';

/// เหตุที่สวอปบนเชน TPIX ไม่ผ่าน — หน้าจอแปลงเป็นข้อความ TH/EN ด้วย `l.t(e.localeKey)`
enum TpixDexError {
  /// เซิร์ฟเวอร์ยังไม่ยืนยันชุดสัญญา DEX (หรือข้อมูลไม่ครบ/ผิดรูป)
  notReady,

  /// ติดต่อเชน TPIX หรือ tpix.online ไม่ได้ (คนละเรื่องกับ "ไม่มีสภาพคล่อง")
  unreachable,

  /// RPC ตอบว่าเป็นเชนอื่น — ไม่ส่งธุรกรรม
  wrongChain,

  noLiquidity,

  /// TPIX ↔ WTPIX คือห่อ/แกะ ไม่ใช่สวอป (router มองเป็นสินทรัพย์เดียวกัน)
  sameAsset,

  amountTooSmall,
  badSlippage,
  impactTooHigh,
  impactUnknown,

  /// อ่าน decimals ของเหรียญจากเชนไม่ได้ / ไม่ตรงกับที่ใช้คิดจำนวน
  tokenUnverified,

  /// ธุรกรรมล้มบนเชน หรือจำลองแล้ว revert (ราคาขยับเกิน slippage)
  reverted,

  /// อนุมัติแล้วแต่ยังไม่ยืนยันบนเชนในเวลาที่รอ
  approvalPending,

  insufficientBalance,
}

class TpixDexException implements Exception {
  const TpixDexException(this.code);

  final TpixDexError code;

  /// คีย์ข้อความใน LocaleProvider (มีทั้ง TH/EN)
  String get localeKey => 'swap.tpix.err.${code.name}';

  @override
  String toString() => 'TpixDexException(${code.name})';
}

/// ที่อยู่ชุดสัญญา DEX ตามทะเบียนบนเซิร์ฟเวอร์ (ตัวพิมพ์เล็กทั้งหมด · ผิดรูป = null)
class TpixDexConfig {
  const TpixDexConfig({
    required this.ready,
    required this.chainId,
    this.wtpix,
    this.usdt,
    this.factory,
    this.router,
  });

  final bool ready;
  final int chainId;
  final String? wtpix;
  final String? usdt;
  final String? factory;
  final String? router;

  static const notReady = TpixDexConfig(ready: false, chainId: 4289);

  /// แปลง `data` ของ /dex/config — ค่าแปลกปลอมทุกชนิดตกเป็น "ไม่พร้อม" ไม่เดา
  factory TpixDexConfig.fromJson(Map<String, dynamic> json) {
    final id = json['chainId'];
    return TpixDexConfig(
      ready: json['ready'] == true,
      chainId: id is int ? id : -1,
      wtpix: TpixDexService.contractAddress(json['WTPIX']),
      usdt: TpixDexService.contractAddress(json['USDT']),
      factory: TpixDexService.contractAddress(json['FACTORY']),
      router: TpixDexService.contractAddress(json['ROUTER']),
    );
  }

  /// สวอปบนเชน TPIX ได้จริงไหม — ครบทุกข้อถึงเปิด (กติกาเดียวกับ SwapNetworkRules ของแอป TRADE)
  ///
  /// chain id ต้องตรงกับเชนที่แอปอ่าน RPC อยู่ ไม่งั้นราคาอ่านจากเชนหนึ่งแต่ธุรกรรมไปอีกเชน
  bool get usable =>
      ready &&
      chainId == ChainConfig.tpix.chainId &&
      router != null &&
      wtpix != null &&
      router != wtpix;
}

/// ทุกอย่างที่หน้าจอต้องรู้ก่อนเปิดโหมด TPIX Chain
class TpixDexMarket {
  const TpixDexMarket(this.config, this.tokens);

  final TpixDexConfig config;

  /// TPIX เนทีฟอยู่ตัวแรกเสมอ — decimals ของทุกเหรียญยืนยันกับเชนแล้ว
  final List<TokenDef> tokens;

  bool get available => config.usable && tokens.length >= 2;
}

/// ผล quote จาก router จริง — ทุกจำนวนเป็นหน่วยเล็กสุด ใช้ส่งธุรกรรมได้ตรง ๆ
class TpixDexQuote {
  TpixDexQuote({
    required this.from,
    required this.to,
    required this.amountIn,
    required this.amountOut,
    required this.path,
    required this.router,
    this.refIn,
    this.refOut,
    this.reserveIn,
    this.reserveOut,
    DateTime? at,
  }) : at = at ?? DateTime.now();

  final TokenDef from;
  final TokenDef to;
  final BigInt amountIn;
  final BigInt amountOut;

  /// เส้นทางของ router (ตัวพิมพ์เล็ก) — TPIX เนทีฟวิ่งเป็น WTPIX
  final List<String> path;
  final String router;

  /// อัตราอ้างอิง "ราคากลาง" (reserve ของพูล หรือ quote ก้อนจิ๋ว) — null = วัด impact ไม่ได้
  final BigInt? refIn;
  final BigInt? refOut;

  /// reserve ของพูลฮอปเดียว — ใช้บอก "สั่งได้สูงสุดเท่าไร" ตอนไม้ใหญ่เกินเพดาน
  final BigInt? reserveIn;
  final BigInt? reserveOut;

  final DateTime at;

  bool get impactKnown => refIn != null && refOut != null;

  /// price impact เป็น basis points (100 = 1%) — null = วัดไม่ได้
  int? get impactBps => impactKnown
      ? TpixDexMath.impactBps(
          amountIn: amountIn, amountOut: amountOut, refIn: refIn!, refOut: refOut!)
      : null;

  /// เกินเพดาน 10% (เทียบแบบเศษส่วนจำนวนเต็ม ไม่ปัดเศษ)
  bool get exceedsImpactLimit =>
      impactKnown &&
      TpixDexMath.exceedsImpact(
          amountIn: amountIn, amountOut: amountOut, refIn: refIn!, refOut: refOut!);

  /// ส่งได้ไหมตามกติกาเว็บ: รู้ impact + ไม่เกินเพดาน + ได้ออกมากกว่า 0
  bool get sendable => impactKnown && !exceedsImpactLimit && amountOut > BigInt.zero;

  /// จ่ายเข้าได้มากสุดเท่าไร (หน่วยเล็กสุดของ [from]) โดยไม่ดันราคาเกินเพดาน — null = ไม่รู้ reserve
  BigInt? get maxAmountInUnderLimit =>
      reserveIn == null ? null : TpixDexMath.maxAmountInForImpact(reserveIn: reserveIn!);

  bool get viaWtpix => path.length > 2;

  /// ยอดขั้นต่ำที่ยอมรับ — ผูกกับราคาที่ผู้ใช้เห็นใน quote นี้ (แบบเว็บ)
  BigInt minOut(double slippagePct) => TpixDexMath.minOut(amountOut, slippagePct);

  /// ค่าธรรมเนียมที่พูลกิน (แสดงผลเท่านั้น ไม่มีธุรกรรมแยก)
  BigInt get poolFee => TpixDexMath.poolFee(amountIn);
}

/// ธุรกรรมสวอปที่พร้อมเซ็น
class TpixSwapTx {
  const TpixSwapTx({required this.to, required this.data, required this.minOut, this.value});

  /// router
  final String to;
  final Uint8List data;

  /// TPIX เนทีฟที่แนบไป (เฉพาะจ่ายด้วย TPIX) — null = 0
  final BigInt? value;
  final BigInt minOut;
}

/// คณิตของพูลและหน่วยเงิน — ฟังก์ชันล้วน BigInt ทดสอบได้โดยไม่แตะเชน
class TpixDexMath {
  TpixDexMath._();

  /// ค่าธรรมเนียมของพูล UniV2 0.3% = 30 bps — เข้าพูลทั้งก้อน ไม่ได้หักเพิ่มจากผู้ใช้
  static const int poolFeeBps = 30;

  /// เพดาน price impact ต่อไม้ — **ต้องเท่ากับเว็บ** (Trade.vue: `priceImpact > 10` = ไม่ส่ง)
  static const int maxImpactBps = 1000;

  /// slippage สูงสุด 50% — มากกว่านี้ minOut แทบเป็น 0 โดน sandwich ได้ทั้งไม้
  static const int maxSlippageBps = 5000;

  static final BigInt _bps = BigInt.from(10000);

  /// UniV2 getAmountOut: หัก 0.3% จากฝั่งที่จ่ายเข้าแล้วคิด x·y=k
  static BigInt amountOutFor(BigInt amountIn, BigInt reserveIn, BigInt reserveOut) {
    if (amountIn <= BigInt.zero || reserveIn <= BigInt.zero || reserveOut <= BigInt.zero) {
      return BigInt.zero;
    }
    final inWithFee = amountIn * BigInt.from(997);
    return (inWithFee * reserveOut) ~/ (reserveIn * BigInt.from(1000) + inWithFee);
  }

  /// price impact (bps) แบบเดียวกับเว็บ: 1 − (ราคาที่ได้จริง ÷ ราคากลาง) — รวมค่าธรรมเนียมพูลไว้ด้วย
  ///
  /// ปัดขึ้นเป็น bps (อัตราที่ได้ปัดลง) — แสดงผลไม่ต่ำกว่าความจริง
  static int impactBps({
    required BigInt amountIn,
    required BigInt amountOut,
    required BigInt refIn,
    required BigInt refOut,
  }) {
    if (amountIn <= BigInt.zero || refIn <= BigInt.zero || refOut <= BigInt.zero) return 0;
    final ratio = (amountOut * refIn * _bps) ~/ (amountIn * refOut);
    // ได้ดีกว่าราคากลาง (ปัดเศษของ quote ก้อนจิ๋ว) = ไม่กระทบราคา — ไม่แปลง BigInt ใหญ่เป็น int
    if (ratio >= _bps) return 0;
    return 10000 - ratio.toInt();
  }

  /// impact เกิน [limitBps] ไหม — เทียบเศษส่วนตรง ๆ: out/in < (1 − L)·refOut/refIn
  static bool exceedsImpact({
    required BigInt amountIn,
    required BigInt amountOut,
    required BigInt refIn,
    required BigInt refOut,
    int limitBps = maxImpactBps,
  }) {
    if (amountIn <= BigInt.zero || refIn <= BigInt.zero || refOut <= BigInt.zero) return true;
    return amountOut * refIn * _bps < BigInt.from(10000 - limitBps) * amountIn * refOut;
  }

  /// slippage (%) → bps แบบเว็บ (`Math.round(slippagePct * 100)`) — นอกช่วง 0.01–50% = ไม่รับ
  static int slippageBps(double slippagePct) {
    if (!slippagePct.isFinite) throw const TpixDexException(TpixDexError.badSlippage);
    final bps = (slippagePct * 100).round();
    if (bps < 1 || bps > maxSlippageBps) {
      throw const TpixDexException(TpixDexError.badSlippage);
    }
    return bps;
  }

  /// minOut = quote × (1 − slippage) — คิดเป็น bps แบบ BigInt เหมือนเว็บ
  static BigInt minOut(BigInt amountOut, double slippagePct) =>
      amountOut * BigInt.from(10000 - slippageBps(slippagePct)) ~/ _bps;

  /// ค่าธรรมเนียมพูลของยอดจ่ายเข้า (แสดงผล)
  static BigInt poolFee(BigInt amountIn) => amountIn * BigInt.from(poolFeeBps) ~/ _bps;

  /// จ่ายเข้าได้มากสุดเท่าไร โดย impact ไม่เกิน [limitBps]
  ///
  /// แก้สมการ impact = 1 − 997·R / (1000·R + 997·x) ≤ L → x ≤ R·(997 − 1000·(1−L)) / (997·(1−L))
  /// หักเผื่อ [safetyBps] (0.5%) — พูลขยับได้ระหว่างกดเติมกับกดส่ง
  static BigInt maxAmountInForImpact({
    required BigInt reserveIn,
    int limitBps = maxImpactBps,
    int safetyBps = 50,
  }) {
    if (reserveIn <= BigInt.zero || limitBps <= 0) return BigInt.zero;
    final keep = BigInt.from(10000 - limitBps);
    final numer = BigInt.from(997 * 10000) - BigInt.from(1000) * keep;
    if (numer <= BigInt.zero) return BigInt.zero;
    final raw = reserveIn * numer ~/ (BigInt.from(997) * keep);
    return raw * BigInt.from(10000 - safetyBps) ~/ _bps;
  }

  /// แสดงจำนวนแบบตัดทศนิยม (ปัดลงเสมอ — ปัดขึ้นแล้วผู้ใช้กดตามจะเกินยอด)
  static String display(BigInt value, int decimals, {int maxFraction = 6}) {
    final full = Units.format(value, decimals);
    final dot = full.indexOf('.');
    if (dot < 0 || full.length - dot - 1 <= maxFraction) return full;
    final cut = full.substring(0, dot + 1 + maxFraction).replaceFirst(RegExp(r'\.?0+$'), '');
    return cut.isEmpty ? '0' : cut;
  }
}

class TpixDexService {
  TpixDexService._();

  /// ทะเบียนที่อยู่สัญญา DEX (เซิร์ฟเวอร์ตรวจแล้วว่ามีโค้ดอยู่บนเชนจริง)
  static const configUrl = 'https://tpix.online/api/v1/dex/config';

  /// คู่เทรดของ DEX — แหล่งความจริงว่าบนเชน TPIX มีเหรียญอะไรให้สวอป
  static const pairsUrl = TokenService.dexPairsUrl;

  static const _zero = '0x0000000000000000000000000000000000000000';
  static final _addressRe = RegExp(r'^0x[0-9a-fA-F]{40}$');
  static final _symbolRe = RegExp(r'^[A-Z0-9]{1,16}$');

  static const _cacheTtl = Duration(seconds: 60);
  static const _httpTimeout = Duration(seconds: 10);

  /// เทสต์ใช้แทน http.Client จริง
  @visibleForTesting
  static http.Client Function() clientFactory = http.Client.new;

  static TpixDexConfig? _config;
  static DateTime? _configAt;
  static Future<TpixDexConfig>? _configInFlight;

  static List<TokenDef>? _tokens;
  static DateTime? _tokensAt;

  /// decimals ที่อ่านจากเชนแล้ว — คงที่ตลอดอายุสัญญา
  static final Map<String, int> _decimals = {};

  /// ที่อยู่พูล + token0 ต่อคู่ — คงที่ (คู่หนึ่งมีพูลได้ตัวเดียว)
  static final Map<String, ({String pair, String token0})> _pairs = {};

  /// ล้างแคชทั้งหมด (เทสต์)
  @visibleForTesting
  static void resetCache() {
    _config = null;
    _configAt = null;
    _configInFlight = null;
    _tokens = null;
    _tokensAt = null;
    _decimals.clear();
    _pairs.clear();
  }

  /// คอนฟิกล่าสุดที่โหลดได้ (null = ยังไม่เคยโหลดสำเร็จ)
  static TpixDexConfig? get lastConfig => _config;

  // ── ที่อยู่ ──

  /// ที่อยู่สัญญารูปแบบถูก → ตัวพิมพ์เล็ก · ว่าง/ผิดรูป/ศูนย์ → null
  static String? contractAddress(Object? raw) {
    if (raw is! String) return null;
    final a = raw.trim();
    if (!_addressRe.hasMatch(a)) return null;
    final lower = a.toLowerCase();
    return lower == _zero ? null : lower;
  }

  static bool isNative(String address) {
    final a = address.trim().toLowerCase();
    return a.isEmpty || a == _zero || a == '0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee';
  }

  // ── คอนฟิก ──

  /// โหลดทะเบียน DEX (แคช 60 วิ · รวมคำขอที่ซ้อนกัน)
  ///
  /// เซิร์ฟเวอร์ตอบ = ใช้ค่านั้น (รวมกรณี "ไม่พร้อม") · ติดต่อไม่ได้ = ใช้ค่าล่าสุดที่เคยได้
  /// ไม่เคยได้เลย → [TpixDexError.unreachable]
  static Future<TpixDexConfig> loadConfig({bool force = false}) {
    final fresh = _configAt != null && DateTime.now().difference(_configAt!) < _cacheTtl;
    if (!force && fresh && _config != null) return Future.value(_config!);
    final inFlight = _configInFlight;
    if (inFlight != null) return inFlight;

    final future = _fetchConfig().then((cfg) {
      if (cfg != null) {
        _config = cfg;
        _configAt = DateTime.now();
        return cfg;
      }
      final last = _config;
      if (last != null) return last;
      throw const TpixDexException(TpixDexError.unreachable);
    }).whenComplete(() => _configInFlight = null);
    _configInFlight = future;
    return future;
  }

  static Future<TpixDexConfig?> _fetchConfig() async {
    final body = await _getJson(configUrl);
    if (body == null || body['success'] != true || body['data'] is! Map) return null;
    return TpixDexConfig.fromJson(Map<String, dynamic>.from(body['data'] as Map));
  }

  static Future<TpixDexConfig> _requireUsable() async {
    final cfg = await loadConfig();
    if (!cfg.usable) throw const TpixDexException(TpixDexError.notReady);
    return cfg;
  }

  static Future<Map<String, dynamic>?> _getJson(String url) async {
    final client = clientFactory();
    try {
      final res = await client.get(Uri.parse(url), headers: const {
        'Accept': 'application/json',
        // ไม่มี User-Agent = Cloudflare หน้า tpix.online ตอบหน้า HTML บล็อก
        'User-Agent': 'TPIX-Wallet (Flutter)',
      }).timeout(_httpTimeout);
      if (res.statusCode != 200) return null;
      final dynamic decoded = jsonDecode(res.body);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (e) {
      // ไม่พิมพ์ข้อความเต็ม — อาจมี URL/รายละเอียดภายใน
      debugPrint('TpixDexService GET: ${e.runtimeType}');
      return null;
    } finally {
      client.close();
    }
  }

  // ── รายการเหรียญ ──

  /// แปลงผลของ /dex/pairs เป็นรายการเหรียญที่สวอปได้ (pure — เทสต์ได้)
  ///
  /// กติกาเดียวกับ SwapNetworkRules.buildTpixTokens ของแอป TRADE:
  ///  - เฉพาะคู่บนเชนของทะเบียนที่เปิดใช้งาน
  ///  - "TPIX" ต้องเป็นเนทีฟ · "USDT" ต้องเป็นที่อยู่ USDT ของทะเบียน
  ///  - WTPIX ไม่อยู่ในรายการ (ห่อ/แกะไม่ใช่สวอป — router จัดการ WTPIX ให้เอง)
  ///  - ชื่อซ้ำคนละที่อยู่ = ผู้ใช้แยกไม่ออกว่าตัวไหนของจริง → ตัดทิ้งทั้งหมด
  ///  - ข้อมูลผิดรูปแบบ → ข้ามคู่นั้น ไม่เดา
  /// คืน TPIX เนทีฟเป็นตัวแรกเสมอ · body ไม่ใช่คำตอบของ API (เช่นหน้า HTML ของ Cloudflare) = null
  @visibleForTesting
  static List<TokenDef>? parseTokens(String body, TpixDexConfig cfg) {
    if (!cfg.usable) return const [];
    final dynamic decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      return null;
    }
    final data = decoded is Map && decoded['success'] == true ? decoded['data'] : null;
    if (data is! List) return null;

    final byAddress = <String, TokenDef>{};
    for (final pair in data) {
      if (pair is! Map) continue;
      if (pair['chain_id'] != cfg.chainId || pair['is_active'] == false) continue;
      final base = _leg(pair['base_asset'], pair['base_address'], pair['base_decimals'],
          pair['base_logo'], cfg);
      final quote = _leg(pair['quote_asset'], pair['quote_address'], pair['quote_decimals'],
          pair['quote_logo'], cfg);
      // ขาใดขาหนึ่งไม่ผ่าน = คู่นี้ไม่น่าเชื่อ ทิ้งทั้งคู่
      if (base == null || quote == null || base.address == quote.address) continue;
      for (final t in [base, quote]) {
        if (!t.isNative) byAddress.putIfAbsent(t.address, () => t);
      }
    }

    final count = <String, int>{'TPIX': 1};
    for (final t in byAddress.values) {
      count[t.symbol] = (count[t.symbol] ?? 0) + 1;
    }
    final tokens = byAddress.values.where((t) => count[t.symbol] == 1).toList()
      ..sort((a, b) {
        final ra = a.address == cfg.usdt ? 0 : 1;
        final rb = b.address == cfg.usdt ? 0 : 1;
        return ra != rb ? ra.compareTo(rb) : a.symbol.compareTo(b.symbol);
      });
    return [ChainConfig.tpix.nativeToken, ...tokens];
  }

  /// ขาหนึ่งของคู่ → TokenDef (ที่อยู่ตัวพิมพ์เล็ก) · ไม่ผ่านกติกา = null
  static TokenDef? _leg(Object? asset, Object? address, Object? decimals, Object? logo,
      TpixDexConfig cfg) {
    if (asset is! String) return null;
    final symbol = asset.trim().toUpperCase();
    if (!_symbolRe.hasMatch(symbol)) return null;
    if (decimals is! int || decimals < 0 || decimals > 36) return null;

    final rawAddr = address is String ? address.trim() : '';
    final native = rawAddr.isEmpty || isNative(rawAddr);
    if (symbol == 'TPIX') return native ? ChainConfig.tpix.nativeToken : null;
    if (native) return null; // เหรียญอื่นต้องเป็นสัญญาจริง
    final addr = contractAddress(rawAddr);
    if (addr == null || addr == cfg.wtpix || symbol == 'WTPIX') return null;
    if (symbol == 'USDT' && addr != cfg.usdt) return null; // USDT ปลอมชื่อเดียวกัน

    return TokenDef(
      address: addr,
      name: _builtInName(addr) ?? symbol,
      symbol: symbol,
      decimals: decimals,
      logoUrl: logo is String && logo.startsWith('https://') && logo.length <= 512 ? logo : null,
    );
  }

  static String? _builtInName(String address) {
    for (final t in ChainConfig.tpix.knownTokens) {
      if (t.address.toLowerCase() == address) return t.name;
    }
    return null;
  }

  /// เปิดโหมด TPIX Chain ได้ไหม + เหรียญที่เลือกได้ (decimals ยืนยันกับเชนแล้วทุกตัว)
  ///
  /// throws [TpixDexException] unreachable เมื่อเซิร์ฟเวอร์/เชนติดต่อไม่ได้
  /// ทะเบียนไม่พร้อม → คืน market ที่ `available == false` (ไม่ throw)
  static Future<TpixDexMarket> loadMarket({bool force = false}) async {
    final cfg = await loadConfig(force: force);
    if (!cfg.usable) return TpixDexMarket(cfg, const []);

    final fresh = _tokensAt != null && DateTime.now().difference(_tokensAt!) < _cacheTtl;
    var tokens = (!force && fresh) ? _tokens : null;
    if (tokens == null) {
      final client = clientFactory();
      String? body;
      try {
        final res = await client.get(Uri.parse(pairsUrl), headers: const {
          'Accept': 'application/json',
          'User-Agent': 'TPIX-Wallet (Flutter)',
        }).timeout(_httpTimeout);
        if (res.statusCode == 200) body = res.body;
      } catch (e) {
        debugPrint('TpixDexService pairs: ${e.runtimeType}');
      } finally {
        client.close();
      }
      tokens = body != null ? parseTokens(body, cfg) : null;
      if (tokens != null) {
        _tokens = tokens;
        _tokensAt = DateTime.now();
      } else {
        // โหลดคู่ไม่ได้ → TPIX + USDT จากทะเบียน (ที่อยู่มาจากเซิร์ฟเวอร์ ไม่ใช่ค่าฝังในแอป)
        tokens = _tokens ??
            [
              ChainConfig.tpix.nativeToken,
              if (cfg.usdt != null)
                TokenDef(address: cfg.usdt!, name: 'Tether USD', symbol: 'USDT', decimals: 6),
            ];
      }
    }

    // decimals จากเซิร์ฟเวอร์เป็นแค่ค่าตั้งต้น — ถ้าคลาดจากเชน ยอดจะเพี้ยนทั้งไม้
    final verified = await Future.wait(tokens.map(_withChainDecimals));
    return TpixDexMarket(cfg, verified.whereType<TokenDef>().toList(growable: false));
  }

  /// เหรียญพร้อม decimals ตามเชน · ไม่ใช่สัญญา ERC-20 = null (ตัดทิ้ง) · เชนติดต่อไม่ได้ = throw
  static Future<TokenDef?> _withChainDecimals(TokenDef t) async {
    if (t.isNative) return t;
    try {
      final d = await tokenDecimals(t.address);
      return d == t.decimals
          ? t
          : TokenDef(
              address: t.address, name: t.name, symbol: t.symbol, decimals: d, logoUrl: t.logoUrl);
    } on TpixDexException catch (e) {
      if (e.code == TpixDexError.unreachable) rethrow;
      return null;
    }
  }

  // ── อ่านเชน ──

  static final ContractAbi _abi = ContractAbi.fromJson(_abiJson, 'TPIXDEX');

  static ContractFunction _fn(String name) => _abi.functions.firstWhere((f) => f.name == name);

  static String _hex(Uint8List data) => bytesToHex(data, include0x: true);

  /// eth_call บนเชน TPIX · revert/ผลผิดรูป = null · ติดต่อไม่ได้ = throw unreachable
  static Future<List<dynamic>?> _call(String to, String fn, List<dynamic> params) async {
    try {
      final out = await RpcClient.tpix.ethCall(to, _hex(_fn(fn).encodeCall(params)));
      if (out == null || out.length < 66) return null;
      return _fn(fn).decodeReturnValues(out);
    } on RpcUnavailableException {
      throw const TpixDexException(TpixDexError.unreachable);
    } on RpcException catch (e) {
      debugPrint('TpixDexService $fn reverted: ${e.code}');
      return null;
    } catch (e) {
      debugPrint('TpixDexService $fn: ${e.runtimeType}');
      return null;
    }
  }

  /// decimals ของเหรียญจากเชน (แคช) — อ่านไม่ได้/นอกช่วง = tokenUnverified
  static Future<int> tokenDecimals(String token) async {
    final key = token.toLowerCase();
    final cached = _decimals[key];
    if (cached != null) return cached;
    final out = await _call(key, 'decimals', const []);
    final v = out == null || out.isEmpty ? null : out.first;
    if (v is! BigInt || v < BigInt.zero || v > BigInt.from(36)) {
      throw const TpixDexException(TpixDexError.tokenUnverified);
    }
    return _decimals[key] = v.toInt();
  }

  /// ยอดคงเหลือบนเชน TPIX — **null เมื่ออ่านไม่ได้** (ห้ามแปลเป็น 0 — ผู้ใช้จะเห็นเงินหาย)
  static Future<BigInt?> balanceOf(TokenDef token, String owner) async {
    try {
      if (token.isNative) return await RpcClient.tpix.getBalance(owner);
      final out = await _call(token.address, 'balanceOf', [EthereumAddress.fromHex(owner)]);
      final v = out == null || out.isEmpty ? null : out.first;
      return v is BigInt ? v : null;
    } catch (e) {
      debugPrint('TpixDexService balanceOf: ${e.runtimeType}');
      return null;
    }
  }

  /// allowance ของ [owner] ที่ให้ router · อ่านไม่ได้ = 0 (บังคับ approve ปลอดภัยกว่าเดาว่าพอ)
  /// ติดต่อเชนไม่ได้ = throw unreachable (ส่งธุรกรรมก็ไม่ถึงเหมือนกัน)
  static Future<BigInt> allowance(String token, String owner) async {
    final cfg = await _requireUsable();
    final out = await _call(token, 'allowance',
        [EthereumAddress.fromHex(owner), EthereumAddress.fromHex(cfg.router!)]);
    final v = out == null || out.isEmpty ? null : out.first;
    return v is BigInt ? v : BigInt.zero;
  }

  /// RPC ต้องเป็นเชน 4289 จริงก่อนเซ็น — ไม่ตรง = ไม่ส่ง
  static Future<void> verifyChain() async {
    final BigInt id;
    try {
      id = RpcClient.parseQuantity(await RpcClient.tpix.call('eth_chainId'));
    } on RpcUnavailableException {
      throw const TpixDexException(TpixDexError.unreachable);
    } catch (_) {
      throw const TpixDexException(TpixDexError.wrongChain);
    }
    if (id != BigInt.from(ChainConfig.tpix.chainId)) {
      throw const TpixDexException(TpixDexError.wrongChain);
    }
  }

  // ── เส้นทาง ──

  /// เส้นทางตรง — TPIX เนทีฟใช้ WTPIX แทน · สองฝั่งเป็นสินทรัพย์เดียวกัน = sameAsset
  @visibleForTesting
  static List<String> directPath(TpixDexConfig cfg, String from, String to) {
    final a = isNative(from) ? cfg.wtpix! : from.toLowerCase();
    final b = isNative(to) ? cfg.wtpix! : to.toLowerCase();
    if (a == b) throw const TpixDexException(TpixDexError.sameAsset);
    return [a, b];
  }

  // ── Quote ──

  /// ขอ quote จริงจาก router — จ่าย [amountIn] (หน่วยเล็กสุดของ [from]) แบบ exact-in
  ///
  /// token ↔ token ที่ไม่มีคู่ตรง → ลองวิ่งผ่าน WTPIX · revert = noLiquidity
  /// price impact: reserve ของพูล (ฮอปเดียว) → quote ก้อนจิ๋ว 1/1000 → วัดไม่ได้ (บล็อกตอนส่ง)
  static Future<TpixDexQuote> quote({
    required TokenDef from,
    required TokenDef to,
    required BigInt amountIn,
  }) async {
    final cfg = await _requireUsable();
    if (amountIn <= BigInt.zero) throw const TpixDexException(TpixDexError.amountTooSmall);
    // จำนวนคิดด้วย decimals ของ TokenDef — ต้องตรงกับเชน ไม่งั้นยอดผิดทั้งไม้
    for (final t in [from, to]) {
      if (!t.isNative && await tokenDecimals(t.address) != t.decimals) {
        throw const TpixDexException(TpixDexError.tokenUnverified);
      }
    }

    final router = cfg.router!;
    final direct = directPath(cfg, from.address, to.address);
    var path = direct;
    var amounts = await _amountsOut(router, amountIn, path);
    if (amounts == null && !from.isNative && !to.isNative) {
      path = [direct.first, cfg.wtpix!, direct.last];
      amounts = await _amountsOut(router, amountIn, path);
    }
    if (amounts == null || amounts.isEmpty || amounts.last <= BigInt.zero) {
      throw const TpixDexException(TpixDexError.noLiquidity);
    }
    final out = amounts.last;

    BigInt? refIn, refOut, reserveIn, reserveOut;
    if (path.length == 2) {
      final r = await _reserves(cfg, path[0], path[1]);
      if (r != null && r.reserveIn > BigInt.zero && r.reserveOut > BigInt.zero) {
        refIn = reserveIn = r.reserveIn;
        refOut = reserveOut = r.reserveOut;
      }
    }
    // อ่าน reserve ไม่ได้ / วิ่ง 2 ฮอป → ราคากลางจาก quote ก้อนจิ๋ว (ห้ามถือว่า impact = 0)
    if (refIn == null) {
      final probe = amountIn ~/ BigInt.from(1000);
      if (probe > BigInt.zero) {
        final p = await _amountsOut(router, probe, path);
        if (p != null && p.isNotEmpty && p.last > BigInt.zero) {
          refIn = probe;
          refOut = p.last;
        }
      }
    }

    return TpixDexQuote(
      from: from,
      to: to,
      amountIn: amountIn,
      amountOut: out,
      path: List.unmodifiable(path),
      router: router,
      refIn: refIn,
      refOut: refOut,
      reserveIn: reserveIn,
      reserveOut: reserveOut,
    );
  }

  static Future<List<BigInt>?> _amountsOut(String router, BigInt amount, List<String> path) async {
    final out = await _call(
        router, 'getAmountsOut', [amount, path.map(EthereumAddress.fromHex).toList()]);
    final v = out == null || out.isEmpty ? null : out.first;
    if (v is! List || v.length != path.length) return null;
    final amounts = v.whereType<BigInt>().toList();
    return amounts.length == path.length ? amounts : null;
  }

  /// reserve ของพูล a/b เรียงตามทิศที่ถาม — null = ไม่มีพูลหรืออ่านไม่ได้
  static Future<({BigInt reserveIn, BigInt reserveOut})?> _reserves(
      TpixDexConfig cfg, String a, String b) async {
    final factory = cfg.factory;
    if (factory == null) return null;
    final key = a.compareTo(b) < 0 ? '$a|$b' : '$b|$a';
    try {
      var info = _pairs[key];
      if (info == null) {
        final p = await _call(
            factory, 'getPair', [EthereumAddress.fromHex(a), EthereumAddress.fromHex(b)]);
        final pair = p == null || p.isEmpty ? null : p.first;
        if (pair is! EthereumAddress || isNative(pair.hex)) return null;
        final t0 = await _call(pair.hex, 'token0', const []);
        final token0 = t0 == null || t0.isEmpty ? null : t0.first;
        if (token0 is! EthereumAddress) return null;
        info = (pair: pair.hex.toLowerCase(), token0: token0.hex.toLowerCase());
        _pairs[key] = info;
      }
      final r = await _call(info.pair, 'getReserves', const []);
      if (r == null || r.length < 2 || r[0] is! BigInt || r[1] is! BigInt) return null;
      final r0 = r[0] as BigInt;
      final r1 = r[1] as BigInt;
      final inIs0 = info.token0 == a;
      return (reserveIn: inIs0 ? r0 : r1, reserveOut: inIs0 ? r1 : r0);
    } on TpixDexException {
      return null; // ราคากลางสำรองยังมี (quote ก้อนจิ๋ว)
    }
  }

  // ── ธุรกรรม ──

  /// calldata approve router **เท่ากับยอดของไม้นี้พอดี** (ไม่ใช่ไม่จำกัด)
  ///
  /// approve 2^256−1 ทิ้งไว้ = ถ้า router/กุญแจฝั่งไหนมีปัญหาวันหน้า ยอดทั้งกระเป๋าของเหรียญนั้น
  /// เปิดให้ดึงได้ทันที — ยอมเซ็นเพิ่มทีละไม้ปลอดภัยกว่า (แก๊สบนเชน TPIX เป็น 0 อยู่แล้ว)
  static Uint8List approveCalldata(String router, BigInt amount) {
    if (amount <= BigInt.zero) throw const TpixDexException(TpixDexError.amountTooSmall);
    return SwapService.buildApproveData(router, amount);
  }

  /// สร้างธุรกรรมสวอปจาก [quote] ที่ผู้ใช้กดยืนยัน — ด่านสุดท้ายก่อนแตะเงิน
  ///
  /// minOut ผูกกับ quote นี้ (ราคาที่ผู้ใช้เห็น) ไม่ใช่ราคาใหม่ตอนส่ง — กติกาเดียวกับเว็บ
  static TpixSwapTx buildSwapTx({
    required TpixDexQuote quote,
    required double slippagePct,
    required String recipient,
    DateTime? now,
  }) {
    if (!quote.impactKnown) throw const TpixDexException(TpixDexError.impactUnknown);
    if (quote.exceedsImpactLimit) throw const TpixDexException(TpixDexError.impactTooHigh);
    final minOut = quote.minOut(slippagePct);
    if (minOut <= BigInt.zero) throw const TpixDexException(TpixDexError.badSlippage);

    final deadline =
        BigInt.from((now ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000 + 1200); // 20 นาที
    final path = quote.path.map(EthereumAddress.fromHex).toList();
    final to = EthereumAddress.fromHex(recipient);

    if (quote.from.isNative) {
      return TpixSwapTx(
        to: quote.router,
        data: _fn('swapExactETHForTokens').encodeCall([minOut, path, to, deadline]),
        value: quote.amountIn,
        minOut: minOut,
      );
    }
    final fn = quote.to.isNative ? 'swapExactTokensForETH' : 'swapExactTokensForTokens';
    return TpixSwapTx(
      to: quote.router,
      data: _fn(fn).encodeCall([quote.amountIn, minOut, path, to, deadline]),
      minOut: minOut,
    );
  }
}

// ABI เฉพาะที่ใช้ — ตรวจกับ TPIXDEXRouter02 / TPIXDEXFactory / TPIXDEXPair ใน contracts/src/dex/amm แล้ว
const String _abiJson = '''
[
 {"type":"function","name":"decimals","stateMutability":"view","inputs":[],"outputs":[{"name":"","type":"uint8"}]},
 {"type":"function","name":"balanceOf","stateMutability":"view","inputs":[{"name":"owner","type":"address"}],"outputs":[{"name":"","type":"uint256"}]},
 {"type":"function","name":"allowance","stateMutability":"view","inputs":[{"name":"owner","type":"address"},{"name":"spender","type":"address"}],"outputs":[{"name":"","type":"uint256"}]},
 {"type":"function","name":"getAmountsOut","stateMutability":"view","inputs":[{"name":"amountIn","type":"uint256"},{"name":"path","type":"address[]"}],"outputs":[{"name":"amounts","type":"uint256[]"}]},
 {"type":"function","name":"swapExactETHForTokens","stateMutability":"payable","inputs":[{"name":"amountOutMin","type":"uint256"},{"name":"path","type":"address[]"},{"name":"to","type":"address"},{"name":"deadline","type":"uint256"}],"outputs":[{"name":"amounts","type":"uint256[]"}]},
 {"type":"function","name":"swapExactTokensForETH","stateMutability":"nonpayable","inputs":[{"name":"amountIn","type":"uint256"},{"name":"amountOutMin","type":"uint256"},{"name":"path","type":"address[]"},{"name":"to","type":"address"},{"name":"deadline","type":"uint256"}],"outputs":[{"name":"amounts","type":"uint256[]"}]},
 {"type":"function","name":"swapExactTokensForTokens","stateMutability":"nonpayable","inputs":[{"name":"amountIn","type":"uint256"},{"name":"amountOutMin","type":"uint256"},{"name":"path","type":"address[]"},{"name":"to","type":"address"},{"name":"deadline","type":"uint256"}],"outputs":[{"name":"amounts","type":"uint256[]"}]},
 {"type":"function","name":"getPair","stateMutability":"view","inputs":[{"name":"","type":"address"},{"name":"","type":"address"}],"outputs":[{"name":"","type":"address"}]},
 {"type":"function","name":"token0","stateMutability":"view","inputs":[],"outputs":[{"name":"","type":"address"}]},
 {"type":"function","name":"getReserves","stateMutability":"view","inputs":[],"outputs":[{"name":"_reserve0","type":"uint112"},{"name":"_reserve1","type":"uint112"},{"name":"_blockTimestampLast","type":"uint32"}]}
]
''';
