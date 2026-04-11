/// ERC-20 token information for custom token tracking
class TokenInfo {
  final String contractAddress;
  final String name;
  final String symbol;
  final int decimals;
  final int walletSlot;
  final int chainId; // Chain this token belongs to (default 4289 = TPIX)
  final String? logoUrl;
  final DateTime addedAt;

  TokenInfo({
    required this.contractAddress,
    required this.name,
    required this.symbol,
    this.decimals = 18,
    required this.walletSlot,
    this.chainId = 4289,
    this.logoUrl,
    DateTime? addedAt,
  }) : addedAt = addedAt ?? DateTime.now();

  String get shortAddress =>
      '${contractAddress.substring(0, 6)}...${contractAddress.substring(contractAddress.length - 4)}';

  Map<String, dynamic> toJson() => {
    'contractAddress': contractAddress,
    'name': name,
    'symbol': symbol,
    'decimals': decimals,
    'walletSlot': walletSlot,
    'chainId': chainId,
    'logoUrl': logoUrl,
    'addedAt': addedAt.toIso8601String(),
  };

  factory TokenInfo.fromJson(Map<String, dynamic> json) => TokenInfo(
    contractAddress: json['contractAddress'] as String? ?? json['contract_address'] as String,
    name: json['name'] as String,
    symbol: json['symbol'] as String,
    decimals: json['decimals'] as int? ?? 18,
    walletSlot: json['walletSlot'] as int? ?? json['wallet_slot'] as int? ?? 0,
    chainId: json['chainId'] as int? ?? json['chain_id'] as int? ?? 4289,
    logoUrl: json['logoUrl'] as String? ?? json['logo_url'] as String?,
    addedAt: json['addedAt'] != null
        ? DateTime.tryParse(json['addedAt'] as String)
        : json['added_at'] != null
            ? DateTime.tryParse(json['added_at'] as String)
            : null,
  );
}
