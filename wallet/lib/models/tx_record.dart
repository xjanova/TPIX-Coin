/// Local transaction record
class TxRecord {
  final String txHash;
  final String fromAddress;
  final String toAddress;
  final String value; // in wei
  final String direction; // 'sent' or 'received'
  final String status; // 'pending', 'confirmed', 'failed'
  final int? blockNumber;
  final int? timestamp; // unix seconds
  final String createdAt;

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
  }) : createdAt = createdAt ?? DateTime.now().toIso8601String();

  /// Value in TPIX (ether units)
  double get valueInTPIX {
    try {
      final wei = BigInt.parse(value);
      final whole = wei ~/ BigInt.from(10).pow(18);
      final frac = wei % BigInt.from(10).pow(18);
      return double.parse('$whole.${frac.toString().padLeft(18, '0').substring(0, 6)}');
    } catch (_) {
      return 0;
    }
  }

  String get shortFrom => '${fromAddress.substring(0, 6)}...${fromAddress.substring(fromAddress.length - 4)}';
  String get shortTo => '${toAddress.substring(0, 6)}...${toAddress.substring(toAddress.length - 4)}';
  String get shortHash => '${txHash.substring(0, 10)}...${txHash.substring(txHash.length - 6)}';

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
      );
}
