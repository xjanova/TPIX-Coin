/// Wallet metadata stored in secure storage
class WalletInfo {
  final int slot;
  final String name;
  final String address;
  final bool isHD;
  final String createdAt;

  WalletInfo({
    required this.slot,
    required this.name,
    required this.address,
    this.isHD = true,
    String? createdAt,
  }) : createdAt = createdAt ?? DateTime.now().toIso8601String();

  Map<String, dynamic> toJson() => {
        'slot': slot,
        'name': name,
        'address': address,
        'isHD': isHD,
        'createdAt': createdAt,
      };

  factory WalletInfo.fromJson(Map<String, dynamic> json) => WalletInfo(
        slot: json['slot'] as int,
        name: json['name'] as String,
        address: json['address'] as String,
        isHD: json['isHD'] as bool? ?? true,
        createdAt: json['createdAt'] as String?,
      );
}
