import 'chain_config.dart';

/// รายการโทเค็นที่ผ่านการอนุมัติ (มาตรฐาน Uniswap Token List)
/// จาก https://tpix.online/tokenlist.json — เฉพาะ TPIX Chain (4289)
///
/// ทุกค่าในนี้ผ่านการตรวจแล้ว (ดู TokenListService.parse) — สร้างตรงๆ
/// ได้เฉพาะในเทสต์หรือจากข้อมูลที่ตรวจแล้วเท่านั้น
class TokenListEntry {
  final int chainId;

  /// ที่อยู่ตามที่รายการประกาศ (อาจเป็นแบบ checksum) — ใช้ [key] เวลาเทียบ
  final String address;
  final String name;
  final String symbol;
  final int decimals;

  /// https เท่านั้น — null = ไม่มีโลโก้ (หรือโลโก้ใช้ไม่ได้)
  final String? logoUri;

  const TokenListEntry({
    required this.chainId,
    required this.address,
    required this.name,
    required this.symbol,
    required this.decimals,
    this.logoUri,
  });

  String get key => address.toLowerCase();

  String get shortAddress =>
      '${address.substring(0, 6)}...${address.substring(address.length - 4)}';

  TokenDef toTokenDef() => TokenDef(
        address: address,
        name: name,
        symbol: symbol,
        decimals: decimals,
        logoUrl: logoUri,
      );

  Map<String, dynamic> toJson() => {
        'chainId': chainId,
        'address': address,
        'name': name,
        'symbol': symbol,
        'decimals': decimals,
        if (logoUri != null) 'logoURI': logoUri,
      };
}

class TokenListVersion {
  final int major;
  final int minor;
  final int patch;

  const TokenListVersion(this.major, this.minor, this.patch);

  @override
  String toString() => '$major.$minor.$patch';

  Map<String, int> toJson() => {'major': major, 'minor': minor, 'patch': patch};
}

class TokenList {
  final String name;
  final String? timestamp;
  final TokenListVersion? version;
  final List<TokenListEntry> tokens;
  final Map<String, TokenListEntry> _byAddress;

  TokenList({
    required this.name,
    required List<TokenListEntry> tokens,
    this.timestamp,
    this.version,
  })  : tokens = List.unmodifiable(tokens),
        _byAddress = {for (final t in tokens) t.key: t};

  bool get isEmpty => tokens.isEmpty;

  /// หาโทเค็นตามที่อยู่สัญญา (ไม่สนตัวพิมพ์)
  TokenListEntry? byAddress(String address) => _byAddress[address.toLowerCase()];

  bool contains(String address) => _byAddress.containsKey(address.toLowerCase());

  Map<String, dynamic> toJson() => {
        'name': name,
        if (timestamp != null) 'timestamp': timestamp,
        if (version != null) 'version': version!.toJson(),
        'tokens': [for (final t in tokens) t.toJson()],
      };
}
