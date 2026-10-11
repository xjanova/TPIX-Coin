import 'package:web3dart/web3dart.dart' show EthereumAddress;

import '../models/chain_config.dart';
import '../models/token_info.dart';
import '../models/token_list.dart';
import 'token_list_service.dart';

/// ความน่าเชื่อถือของโทเค็นบน TPIX Chain
enum TokenTrust {
  /// อยู่ในรายการที่แอดมินอนุมัติ (tokenlist.json) หรือค่าในตัวแอป
  verified,

  /// ไม่อยู่ในรายการ — ใครก็สร้างโทเค็นชื่ออะไรก็ได้ ให้ผู้ใช้ระวัง
  unverified,

  /// ไม่อยู่ในรายการ แต่ชื่อ/สัญลักษณ์เหมือนตัวที่ยืนยันแล้ว = น่าจะเป็นของปลอม
  lookalike,
}

/// ช่องข้อมูลที่ "บนสัญญา" กับ "ในรายการ" ไม่ตรงกัน
enum TokenMetaField { name, symbol, decimals }

class TokenTrustResult {
  final TokenTrust trust;

  /// ข้อมูลตัวที่ยืนยันแล้วของที่อยู่นี้ (verified เท่านั้น)
  final TokenDef? listed;

  /// ช่องที่บนสัญญาไม่ตรงกับ [listed] — บนสัญญาชนะเสมอ แต่ต้องเตือน
  final Set<TokenMetaField> mismatches;

  /// ตัวที่ยืนยันแล้วซึ่งชื่อ/สัญลักษณ์ซ้ำ (lookalike เท่านั้น)
  final List<TokenDef> lookalikes;

  /// ตรวจกับรายการจากเซิร์ฟเวอร์ได้ไหม (false = เทียบได้แค่ค่าในตัวแอป)
  final bool listAvailable;

  const TokenTrustResult({
    required this.trust,
    required this.listAvailable,
    this.listed,
    this.mismatches = const {},
    this.lookalikes = const [],
  });

  bool get isVerified => trust == TokenTrust.verified;
}

/// ตัดสินว่าโทเค็นยืนยันแล้ว/ไม่ยืนยัน/เลียนแบบ + เลือกโลโก้ (pure — เทสต์ได้)
class TokenTrustService {
  static const _tpixChainId = TokenListService.chainId;

  /// เหรียญหลักของเชน — ERC-20 ที่ตั้งชื่อว่า "TPIX" คือของปลอมแน่นอน
  static const nativeTpix = TokenDef(
    address: TokenDef.nativeAddress,
    name: 'TPIX',
    symbol: 'TPIX',
    decimals: 18,
  );

  /// ตัวที่ยืนยันแล้วทั้งหมด: รายการจากเซิร์ฟเวอร์ ∪ ค่าในตัวแอป (ที่อยู่ซ้ำ → รายการชนะ)
  static List<TokenDef> verifiedTokens(TokenList? list) {
    final byAddr = <String, TokenDef>{
      for (final t in ChainConfig.tpix.knownTokens) t.address.toLowerCase(): t,
    };
    for (final e in list?.tokens ?? const <TokenListEntry>[]) {
      byAddr[e.key] = e.toTokenDef();
    }
    return byAddr.values.toList();
  }

  /// ข้อมูลที่ยืนยันแล้วของที่อยู่นี้ (null = ไม่อยู่ในรายการ)
  static TokenDef? verifiedFor(String address, TokenList? list) {
    final key = address.toLowerCase();
    final listed = list?.byAddress(key);
    if (listed != null) return listed.toTokenDef();
    for (final t in ChainConfig.tpix.knownTokens) {
      if (t.address.toLowerCase() == key) return t;
    }
    return null;
  }

  /// จัดประเภทโทเค็นบน TPIX Chain จากข้อมูลที่อ่านจากสัญญา
  static TokenTrustResult classify({
    required String address,
    required String name,
    required String symbol,
    required int decimals,
    TokenList? list,
  }) {
    final listAvailable = list != null;
    final listed = verifiedFor(address, list);
    if (listed != null) {
      return TokenTrustResult(
        trust: TokenTrust.verified,
        listAvailable: listAvailable,
        listed: listed,
        mismatches: {
          if (_norm(listed.name) != _norm(name)) TokenMetaField.name,
          if (_norm(listed.symbol) != _norm(symbol)) TokenMetaField.symbol,
          if (listed.decimals != decimals) TokenMetaField.decimals,
        },
      );
    }

    final index = _skeletonIndex(list);
    final lookalikes = <TokenDef>{
      for (final s in {skeleton(name), skeleton(symbol)})
        if (s.isNotEmpty) ...?index[s],
    }.toList();
    return TokenTrustResult(
      trust: lookalikes.isEmpty ? TokenTrust.unverified : TokenTrust.lookalike,
      listAvailable: listAvailable,
      lookalikes: lookalikes,
    );
  }

  /// ประเภทของโทเค็นที่บันทึกไว้แล้ว (ใช้ติดป้ายในรายการโทเค็น)
  static TokenTrust trustOf(TokenInfo token, TokenList? list) {
    if (token.chainId != _tpixChainId) return TokenTrust.unverified;
    return classify(
      address: token.contractAddress,
      name: token.name,
      symbol: token.symbol,
      decimals: token.decimals,
      list: list,
    ).trust;
  }

  static String _norm(String s) => s.trim().toLowerCase();

  // โครงชื่อของตัวที่ยืนยันแล้ว → ตัวนั้น (คำนวณครั้งเดียวต่อรายการ — หน้าโฮมเรียกทุกครั้งที่วาด)
  static TokenList? _indexedList;
  static bool _indexBuilt = false;
  static Map<String, List<TokenDef>> _index = const {};

  static Map<String, List<TokenDef>> _skeletonIndex(TokenList? list) {
    if (_indexBuilt && identical(list, _indexedList)) return _index;
    final index = <String, List<TokenDef>>{};
    for (final ref in [nativeTpix, ...verifiedTokens(list)]) {
      for (final s in {skeleton(ref.name), skeleton(ref.symbol)}) {
        if (s.isNotEmpty) (index[s] ??= []).add(ref);
      }
    }
    _indexedList = list;
    _indexBuilt = true;
    return _index = index;
  }

  /// ตัวอักษรหน้าตาเหมือนอักษรละติน (ซีริลลิก/กรีก/สัญลักษณ์) → ตัวละติน
  static const _confusables = <int, String>{
    // ซีริลลิก (ตัวเล็ก — เทียบหลัง toLowerCase)
    0x0430: 'a', 0x0432: 'b', 0x0435: 'e', 0x043A: 'k', 0x043C: 'm',
    0x043D: 'h', 0x043E: 'o', 0x0440: 'p', 0x0441: 'c', 0x0442: 't',
    0x0443: 'y', 0x0445: 'x', 0x0455: 's', 0x0456: 'l', 0x0458: 'j',
    0x0501: 'd', 0x04BB: 'h',
    // กรีก
    0x03B1: 'a', 0x03B2: 'b', 0x03B5: 'e', 0x03B9: 'l', 0x03BA: 'k',
    0x03BD: 'v', 0x03BF: 'o', 0x03C1: 'p', 0x03C4: 't', 0x03C5: 'u',
    0x03C7: 'x',
    // ตัวเลข/สัญลักษณ์ที่ใช้แทนตัวอักษร
    0x30: 'o', // 0
    0x31: 'l', // 1
    0x69: 'l', // i (ให้ i/l/1 เป็นตัวเดียวกัน)
    0x24: 's', // $
    0x20AE: 't', // ₮ (USD₮)
  };

  /// ช่องว่าง/เครื่องหมายคั่น/อักขระซ่อน — ตัดทิ้งก่อนเทียบ
  static final _ignorable = RegExp(
    r'[\s\-_.\u00B7\u2022\u00AD\u200B-\u200F\u202A-\u202E\u2060-\u2064\u2066-\u2069\uFEFF]',
  );

  /// "โครง" ของชื่อสำหรับจับของเลียนแบบ — "USDT", "usdt", "U S D T", "USDТ" (T ซีริลลิก),
  /// "ＵＳＤＴ" (เต็มความกว้าง), "U$DT" ได้ค่าเดียวกันหมด
  static String skeleton(String input) {
    final s = input.toLowerCase().replaceAll(_ignorable, '');
    final out = StringBuffer();
    for (var r in s.runes) {
      if (r >= 0xFF01 && r <= 0xFF5E) {
        r -= 0xFEE0; // อักษรเต็มความกว้าง → ASCII
        if (r >= 0x41 && r <= 0x5A) r += 0x20;
      }
      out.write(_confusables[r] ?? String.fromCharCode(r));
    }
    return out.toString();
  }

  // ================================================================
  // โลโก้
  // ================================================================

  /// โลโก้ของโทเค็น ตามลำดับ: ที่บันทึกไว้กับโทเค็น → รายการที่ยืนยันแล้ว →
  /// คู่เทรด DEX → ค่าในตัวแอป (+ Trust Wallet CDN ของเชนอื่น) · https เท่านั้น
  static String? resolveLogo(
    TokenInfo token, {
    TokenList? list,
    Map<String, String> dexLogos = const {},
  }) {
    final key = token.contractAddress.toLowerCase();
    final onTpix = token.chainId == _tpixChainId;
    for (final url in [
      token.logoUrl,
      if (onTpix) list?.byAddress(key)?.logoUri,
      if (onTpix) dexLogos[key],
      ..._builtInLogos(token.chainId, key),
    ]) {
      if (isHttpsUrl(url)) return url;
    }
    return null;
  }

  static Iterable<String?> _builtInLogos(int chainId, String key) sync* {
    final chain = ChainConfig.all.where((c) => c.chainId == chainId).firstOrNull;
    if (chain == null) return;
    for (final t in chain.knownTokens) {
      if (t.address.toLowerCase() == key) yield t.logoUrl;
    }
    // Trust Wallet ใช้ที่อยู่แบบ checksum ในพาธ — ที่อยู่ในฐานข้อมูลเป็นตัวเล็ก
    if (chain.trustWalletSlug != null) {
      try {
        yield chain.tokenLogoUrl(EthereumAddress.fromHex(key).hexEip55);
      } catch (_) {}
    }
  }

  static bool isHttpsUrl(String? url) =>
      url != null && url.startsWith('https://') && url.length > 'https://'.length;
}
