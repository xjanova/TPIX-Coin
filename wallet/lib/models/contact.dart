/// TPIX Wallet — รายการโปรด (สมุดที่อยู่)
///
/// เก็บ "ที่อยู่นี้คือใคร" ไว้ให้ผู้ใช้ไม่ต้องจำเลข 0x… เอง
///
/// จงใจเก็บรวมทุกกระเป๋า (ไม่แยกตาม wallet_slot) เพราะสมุดที่อยู่พูดถึง
/// "ผู้รับ" ไม่ใช่ "ผู้ส่ง" — คนคนเดิมก็ยังคนเดิมไม่ว่าจะส่งจากกระเป๋าไหน
///
/// Developed by Xman Studio
class Contact {
  final int? id;

  /// ที่อยู่ปลายทาง เก็บเป็นตัวพิมพ์เล็กเสมอ (ใช้เป็นกุญแจกันซ้ำ)
  /// ที่อยู่ EVM ไม่สนตัวพิมพ์ใหญ่เล็กอยู่แล้ว
  final String address;

  /// ชื่อที่ผู้ใช้ตั้ง เช่น "น้องเอ", "กระเป๋าตัวเอง (BSC)"
  final String name;

  /// โน้ตสั้นๆ (ไม่บังคับ)
  final String? note;

  /// ใช้ส่งไปแล้วกี่ครั้ง — ใช้เรียงตัวที่ใช้บ่อยขึ้นก่อน
  final int usedCount;

  /// ใช้ล่าสุดเมื่อไร (unix seconds)
  final int? lastUsedAt;

  final int createdAt;

  const Contact({
    this.id,
    required this.address,
    required this.name,
    this.note,
    this.usedCount = 0,
    this.lastUsedAt,
    required this.createdAt,
  });

  /// ตัวย่อไว้โชว์ในที่แคบ เช่น 0x1234…abcd
  String get shortAddress => address.length > 12
      ? '${address.substring(0, 6)}…${address.substring(address.length - 4)}'
      : address;

  /// ตัวอักษรแรกของชื่อ ไว้ทำวงกลม avatar
  /// ใช้ runes ไม่ใช่ [0] เพราะอิโมจิเป็น surrogate pair — ตัดครึ่งแล้วได้ตัวประหลาด
  String get initial {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '?';
    return String.fromCharCode(trimmed.runes.first);
  }

  Contact copyWith({
    int? id,
    String? address,
    String? name,
    String? note,
    int? usedCount,
    int? lastUsedAt,
    int? createdAt,
  }) {
    return Contact(
      id: id ?? this.id,
      address: address ?? this.address,
      name: name ?? this.name,
      note: note ?? this.note,
      usedCount: usedCount ?? this.usedCount,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, Object?> toRow() => {
        'address': address.toLowerCase(),
        'name': name,
        'note': note,
        'used_count': usedCount,
        'last_used_at': lastUsedAt,
        'created_at': createdAt,
      };

  factory Contact.fromRow(Map<String, Object?> row) => Contact(
        id: row['id'] as int?,
        address: (row['address'] as String).toLowerCase(),
        name: row['name'] as String,
        note: row['note'] as String?,
        usedCount: (row['used_count'] as int?) ?? 0,
        lastUsedAt: row['last_used_at'] as int?,
        createdAt: (row['created_at'] as int?) ?? 0,
      );
}
