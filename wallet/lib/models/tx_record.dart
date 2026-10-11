import '../utils/units.dart';

/// Local transaction record
class TxRecord {
  final String txHash;
  final String fromAddress;
  final String toAddress;
  final String value; // หน่วยย่อยของเหรียญนั้น (wei ของ TPIX หรือ หน่วยย่อยของโทเค็น)
  final String direction; // 'sent' or 'received'
  final String status; // 'pending', 'confirmed', 'failed'
  final int? blockNumber;
  final int? timestamp; // unix seconds
  final String createdAt;

  /// ธุรกรรมโทเค็น ERC-20: ที่อยู่สัญญา / สัญลักษณ์ / ทศนิยม
  /// null = เหรียญ native (TPIX บน TPIX Chain) — แถวเก่าก่อนมีคอลัมน์นี้เป็น null หมด
  /// ธุรกรรมข้ามเชน (BSC ฯลฯ) ใส่ symbol/decimals ของเชนนั้น แต่ tokenAddress เป็น null
  final String? tokenAddress;
  final String? tokenSymbol;
  final int? tokenDecimals;

  TxRecord({
    required this.txHash,
    required this.fromAddress,
    required this.toAddress,
    required this.value,
    required this.direction,
    this.status = 'pending',
    this.blockNumber,
    this.timestamp,
    String? createdAt,
    this.tokenAddress,
    this.tokenSymbol,
    this.tokenDecimals,
  }) : createdAt = createdAt ?? DateTime.now().toIso8601String();

  /// สัญลักษณ์ที่ต้องแสดง (ค่าเริ่มต้น TPIX)
  String get symbol => tokenSymbol ?? 'TPIX';

  /// ทศนิยมของเหรียญนี้ (ค่าเริ่มต้น 18 ของ TPIX)
  int get decimals => tokenDecimals ?? 18;

  /// เหรียญ TPIX ตัวจริง (ใช้ตัดสินว่าจะโชว์โลโก้เหรียญ TPIX หรือไม่)
  bool get isTpix => tokenAddress == null && symbol == 'TPIX';

  /// จำนวนสำหรับแสดงผล (ตามทศนิยมของเหรียญนั้น — ไม่ใช่หาร 1e18 ทุกตัว)
  double get amount {
    try {
      return Units.toDouble(BigInt.parse(value), decimals);
    } catch (_) {
      return 0;
    }
  }

  /// ชื่อเดิม — คงไว้ให้โค้ดเก่า (คิดตามทศนิยมของเหรียญจริงแล้ว)
  double get valueInTPIX => amount;

  String get shortFrom => _short(fromAddress, 6, 4);
  String get shortTo => _short(toAddress, 6, 4);
  String get shortHash => _short(txHash, 10, 6);

  static String _short(String s, int head, int tail) =>
      s.length <= head + tail ? s : '${s.substring(0, head)}...${s.substring(s.length - tail)}';

  Map<String, dynamic> toJson() => {
        'txHash': txHash,
        'fromAddress': fromAddress,
        'toAddress': toAddress,
        'value': value,
        'direction': direction,
        'status': status,
        'blockNumber': blockNumber,
        'timestamp': timestamp,
        'createdAt': createdAt,
        if (tokenAddress != null) 'tokenAddress': tokenAddress,
        if (tokenSymbol != null) 'tokenSymbol': tokenSymbol,
        if (tokenDecimals != null) 'tokenDecimals': tokenDecimals,
      };

  factory TxRecord.fromJson(Map<String, dynamic> json) => TxRecord(
        txHash: json['txHash'] as String,
        fromAddress: json['fromAddress'] as String,
        toAddress: json['toAddress'] as String,
        value: json['value'] as String,
        direction: json['direction'] as String,
        status: json['status'] as String? ?? 'confirmed',
        blockNumber: json['blockNumber'] as int?,
        timestamp: json['timestamp'] as int?,
        createdAt: json['createdAt'] as String?,
        tokenAddress: json['tokenAddress'] as String?,
        tokenSymbol: json['tokenSymbol'] as String?,
        tokenDecimals: json['tokenDecimals'] as int?,
      );
}
