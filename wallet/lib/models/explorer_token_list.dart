/// เหรียญบน TPIX Chain ที่ผ่านกฎของ explorer (https://explorer.tpix.online/tokens):
/// อยู่ใน /api/v2/tokens + สัญญายืนยันซอร์สโค้ดแล้ว (is_verified) + ไม่ถูกทำเครื่องหมาย scam
///
/// ทุกค่าในนี้ผ่านการตรวจแล้ว (ดู ExplorerTokenService) — สร้างตรงๆ ได้เฉพาะในเทสต์
/// หรือจากข้อมูลที่ตรวจแล้วเท่านั้น
///
/// "ยืนยันซอร์สโค้ด" แปลว่าโค้ดที่เผยแพร่ตรงกับสัญญาบนเชน ไม่ได้แปลว่าเหรียญปลอดภัย
/// (บน explorer นี้ใครจ่ายค่าบริการก็ยืนยันได้) — ชื่อ/สัญลักษณ์ใช้แสดงผลเท่านั้น
/// ทศนิยมไม่เก็บ: ตอนเพิ่มเข้ากระเป๋าอ่านจากสัญญาเสมอ (TokenService.fetchTokenInfo)
class ExplorerToken {
  /// ที่อยู่ตามที่ explorer ส่งมา (checksum) — ใช้ [key] เวลาเทียบ
  final String address;
  final String name;
  final String symbol;

  /// https เท่านั้น — null = ไม่มีโลโก้ (หรือโลโก้ใช้ไม่ได้)
  final String? logoUri;

  /// เวลาที่ตรวจ verify ผ่านล่าสุด — เกินอายุ (ExplorerTokenService.maxAge) = ไม่ใช้
  final DateTime checkedAt;

  const ExplorerToken({
    required this.address,
    required this.name,
    required this.symbol,
    required this.checkedAt,
    this.logoUri,
  });

  String get key => address.toLowerCase();

  ExplorerToken copyWith({DateTime? checkedAt}) => ExplorerToken(
        address: address,
        name: name,
        symbol: symbol,
        logoUri: logoUri,
        checkedAt: checkedAt ?? this.checkedAt,
      );

  Map<String, dynamic> toJson() => {
        'address': address,
        'name': name,
        'symbol': symbol,
        if (logoUri != null) 'logo': logoUri,
        'checkedAt': checkedAt.millisecondsSinceEpoch,
      };
}

class ExplorerTokenList {
  /// ลำดับตามที่ explorer เรียง (ผู้ถือมากก่อน)
  final List<ExplorerToken> tokens;
  final Map<String, ExplorerToken> _byAddress;

  ExplorerTokenList(List<ExplorerToken> tokens)
      : tokens = List.unmodifiable(tokens),
        _byAddress = {for (final t in tokens) t.key: t};

  bool get isEmpty => tokens.isEmpty;

  /// หาเหรียญตามที่อยู่สัญญา (ไม่สนตัวพิมพ์)
  ExplorerToken? byAddress(String address) => _byAddress[address.toLowerCase()];

  bool contains(String address) => _byAddress.containsKey(address.toLowerCase());

  /// เฉพาะตัวที่ตรวจผ่านไม่เก่ากว่า [maxAge] ก่อน [now] — เวลาในอนาคต (นาฬิกาเครื่องถูกย้อน) = ไม่นับ
  ExplorerTokenList within(DateTime now, Duration maxAge) => ExplorerTokenList([
        for (final t in tokens)
          if (!now.difference(t.checkedAt).isNegative && now.difference(t.checkedAt) < maxAge) t,
      ]);

  List<Map<String, dynamic>> toJson() => [for (final t in tokens) t.toJson()];
}
