/// TPIX Wallet — จับ "เงินเข้า" จากยอดที่ระบบรีเฟรชอยู่แล้ว (ไม่ยิงเน็ตเพิ่มเอง)
///
/// หน้ารับเงินธีม Obsidian ใช้เล่นเหรียญพุ่ง + แถบเงินเข้า ระหว่างเปิดหน้าค้างไว้
/// แหล่งข้อมูลคือ WalletProvider ที่รีเฟรชยอด TPIX + โทเค็นทุก 15 วิอยู่แล้ว
///
/// 🔴 กติกาที่ต้องรักษา (ไม่งั้นเด้ง "ได้รับเงิน" หลอก):
///   1. ค่าแรกที่เห็นของแต่ละยอด = จุดเริ่ม ไม่ใช่เงินเข้า (null → มีค่า คือเพิ่งโหลดเสร็จ)
///   2. สลับกระเป๋า = ล้างทั้งหมดแล้วเริ่มนับใหม่ (ยอดกระเป๋าใหม่ไม่ใช่เงินเข้า)
///   3. ยอดดึงไม่ได้ชั่วคราว (null) = คงค่าเดิมไว้ ไม่ลบ — กลับมาแล้วค่อยเทียบต่อ
///   4. ยอดลด (ส่งออกจากที่อื่น) ไม่นับ
///   5. เทียบเป็น BigInt หน่วยย่อยเท่านั้น (ห้าม double)
///
/// Developed by Xman Studio
library;

/// ยอดหนึ่งตัวที่เพิ่มขึ้น
class BalanceIncrease {
  final String key;
  final BigInt delta;

  const BalanceIncrease(this.key, this.delta);

  @override
  bool operator ==(Object other) => other is BalanceIncrease && other.key == key && other.delta == delta;

  @override
  int get hashCode => Object.hash(key, delta);

  @override
  String toString() => 'BalanceIncrease($key, +$delta)';
}

class BalanceIncreaseDetector {
  String? _owner;
  final Map<String, BigInt> _last = {};

  /// ป้อนยอดชุดล่าสุดของกระเป๋า [owner] — คืนรายการที่เพิ่มขึ้นจากครั้งก่อน
  ///
  /// [snapshot]: คีย์ใดก็ได้ที่คงที่ (เช่น `native:4289`, `token:0x…`) → ยอดหน่วยย่อย
  /// (null = ยังไม่รู้ยอด)
  List<BalanceIncrease> update(String? owner, Map<String, BigInt?> snapshot) {
    final who = owner?.toLowerCase();
    if (who == null) {
      _owner = null;
      _last.clear();
      return const [];
    }
    if (who != _owner) {
      // กระเป๋าใหม่ (หรือครั้งแรก) → จำเป็นจุดเริ่มอย่างเดียว
      _owner = who;
      _last.clear();
      snapshot.forEach((k, v) {
        if (v != null) _last[k] = v;
      });
      return const [];
    }

    final out = <BalanceIncrease>[];
    // คีย์ที่หายไปจากชุดใหม่ (เช่น ลบโทเค็นออก) → เลิกติดตาม
    _last.removeWhere((k, _) => !snapshot.containsKey(k));
    snapshot.forEach((k, v) {
      if (v == null) return; // ดึงไม่ได้ชั่วคราว — คงค่าเดิม
      final prev = _last[k];
      if (prev != null && v > prev) out.add(BalanceIncrease(k, v - prev));
      _last[k] = v;
    });
    return out;
  }
}

/// ใส่จุลภาคคั่นหลักพันให้ "สตริงจำนวน" แบบไม่ผ่าน double (แสดงผลเท่านั้น)
///
/// "1500.25" → "1,500.25" · "0.000001" → "0.000001" · "-" / ว่าง → คืนเดิม
/// 🔴 ห้ามเอาผลนี้ใส่กลับในช่องกรอก — Units.parse อ่าน "1,500" เป็น 1.5 (จุลภาคตัวเดียว = ทศนิยม)
String groupDigits(String amount) {
  final m = RegExp(r'^(\d+)(\.\d+)?$').firstMatch(amount);
  if (m == null) return amount;
  final intPart = m.group(1)!;
  final frac = m.group(2) ?? '';
  final buf = StringBuffer();
  for (var i = 0; i < intPart.length; i++) {
    if (i > 0 && (intPart.length - i) % 3 == 0) buf.write(',');
    buf.write(intPart[i]);
  }
  return '$buf$frac';
}
