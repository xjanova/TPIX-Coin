import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

/// Centralized fee configuration fetched from tpix.online
/// Controls swap and bridge fees, fee wallet addresses, and limits
class FeeConfig {
  final SwapFeeConfig swap;
  final BridgeFeeConfig bridge;
  final DateTime fetchedAt;

  const FeeConfig({
    required this.swap,
    required this.bridge,
    required this.fetchedAt,
  });

  factory FeeConfig.fromJson(Map<String, dynamic> json) {
    return FeeConfig(
      swap: SwapFeeConfig.fromJson(json['swap'] as Map<String, dynamic>? ?? {}),
      bridge: BridgeFeeConfig.fromJson(json['bridge'] as Map<String, dynamic>? ?? {}),
      fetchedAt: DateTime.now(),
    );
  }

  /// Default fallback config when API is unreachable
  /// Note: feePercent is 0 in fallback because we have no valid feeWallet
  factory FeeConfig.fallback() => FeeConfig(
        swap: SwapFeeConfig.fallback(),
        bridge: BridgeFeeConfig.fallback(),
        fetchedAt: DateTime.now(),
      );
}

/// Validates Ethereum address format: 0x + 40 hex chars
bool _isValidAddress(String? address) {
  if (address == null || address.isEmpty) return false;
  return RegExp(r'^0x[0-9a-fA-F]{40}$').hasMatch(address);
}

/// Swap fee configuration from tpix.online
class SwapFeeConfig {
  final double feePercent; // platform fee (e.g. 0.3%)
  final String feeWallet; // wallet address to receive fees
  final bool enabled;

  const SwapFeeConfig({
    required this.feePercent,
    required this.feeWallet,
    required this.enabled,
  });

  factory SwapFeeConfig.fromJson(Map<String, dynamic> json) {
    final wallet = json['feeWallet'] as String? ?? '';
    // Only charge fee if we have a valid wallet to send it to
    final validWallet = _isValidAddress(wallet);
    return SwapFeeConfig(
      feePercent: validWallet ? ((json['feePercent'] as num?)?.toDouble() ?? 0.3) : 0,
      feeWallet: validWallet ? wallet : '',
      enabled: json['enabled'] as bool? ?? true,
    );
  }

  /// Fallback: no fee (no valid wallet to collect it)
  factory SwapFeeConfig.fallback() => const SwapFeeConfig(
        feePercent: 0,
        feeWallet: '',
        enabled: true,
      );

  /// Calculate fee amount from input amount (BigInt for precision)
  BigInt calculateFee(BigInt amountIn) {
    if (feePercent <= 0 || feeWallet.isEmpty) return BigInt.zero;
    // fee = amountIn * feePercent / 100
    // Use integer math: feeBasisPoints = feePercent * 10000, then / 1000000
    final feeBasis = (feePercent * 10000).round(); // e.g. 0.3% → 3000
    return amountIn * BigInt.from(feeBasis) ~/ BigInt.from(1000000);
  }

  /// Amount after fee deduction
  BigInt amountAfterFee(BigInt amountIn) {
    return amountIn - calculateFee(amountIn);
  }
}

/// Bridge fee configuration from tpix.online
class BridgeFeeConfig {
  final double feePercent; // bridge fee (e.g. 0.1%)
  final String feeWallet; // wallet address to send bridge funds to
  final double minAmount;
  final double maxAmount;
  final int estimatedMinutes;
  final bool enabled;

  const BridgeFeeConfig({
    required this.feePercent,
    required this.feeWallet,
    required this.minAmount,
    required this.maxAmount,
    required this.estimatedMinutes,
    required this.enabled,
  });

  factory BridgeFeeConfig.fromJson(Map<String, dynamic> json) {
    final wallet = json['feeWallet'] as String? ?? '';
    final validWallet = _isValidAddress(wallet);
    return BridgeFeeConfig(
      feePercent: validWallet ? ((json['feePercent'] as num?)?.toDouble() ?? 0.1) : 0,
      feeWallet: validWallet ? wallet : '',
      minAmount: (json['minAmount'] as num?)?.toDouble() ?? 100,
      maxAmount: (json['maxAmount'] as num?)?.toDouble() ?? 1000000,
      estimatedMinutes: json['estimatedMinutes'] as int? ?? 10,
      enabled: json['enabled'] as bool? ?? true,
    );
  }

  /// Fallback: no fee (no valid wallet to collect it)
  factory BridgeFeeConfig.fallback() => const BridgeFeeConfig(
        feePercent: 0,
        feeWallet: '',
        minAmount: 100,
        maxAmount: 1000000,
        estimatedMinutes: 10,
        enabled: true,
      );

  /// Calculate fee for a given amount
  double calculateFee(double amount) {
    if (feePercent <= 0 || feeWallet.isEmpty) return 0;
    return amount * feePercent / 100;
  }

  /// Amount user receives after fee
  double receiveAmount(double amount) {
    return amount - calculateFee(amount);
  }
}

/// Service to fetch fee configuration from tpix.online API
/// Caches config with 5-minute TTL for performance
/// Uses Completer to prevent duplicate concurrent requests
class FeeService {
  static const _apiBase = 'https://tpix.online/api/v1';
  static const _cacheDuration = Duration(minutes: 5);

  static FeeConfig? _cachedConfig;
  static Completer<FeeConfig>? _inflightRequest;

  /// Get current fee configuration (cached or fresh)
  /// Thread-safe: concurrent callers share the same in-flight request
  static Future<FeeConfig> getConfig({bool forceRefresh = false}) async {
    // Return cached if valid
    if (!forceRefresh &&
        _cachedConfig != null &&
        DateTime.now().difference(_cachedConfig!.fetchedAt) < _cacheDuration) {
      return _cachedConfig!;
    }

    // If another request is in-flight, wait for it
    if (_inflightRequest != null) {
      return _inflightRequest!.future;
    }

    // Start new request with Completer
    _inflightRequest = Completer<FeeConfig>();

    try {
      final config = await _fetchFromApi();
      _cachedConfig = config;
      _inflightRequest!.complete(config);
      return config;
    } catch (_) {
      // Fallback: use cached if available, otherwise defaults
      final fallback = _cachedConfig ?? FeeConfig.fallback();
      _inflightRequest!.complete(fallback);
      return fallback;
    } finally {
      _inflightRequest = null;
    }
  }

  /// Fetch fee config from tpix.online API
  static Future<FeeConfig> _fetchFromApi() async {
    final client = http.Client();
    try {
      final response = await client
          .get(Uri.parse('$_apiBase/fees'))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return FeeConfig.fromJson(data as Map<String, dynamic>);
      }
    } finally {
      client.close();
    }
    // Non-200 response → use fallback
    return _cachedConfig ?? FeeConfig.fallback();
  }

  /// Get swap fee config (convenience)
  static Future<SwapFeeConfig> getSwapFee() async {
    final config = await getConfig();
    return config.swap;
  }

  /// Get bridge fee config (convenience)
  static Future<BridgeFeeConfig> getBridgeFee() async {
    final config = await getConfig();
    return config.bridge;
  }

  /// Cached swap fee (sync, for UI display after initial fetch)
  static SwapFeeConfig get swapFee =>
      _cachedConfig?.swap ?? SwapFeeConfig.fallback();

  /// Cached bridge fee (sync, for UI display after initial fetch)
  static BridgeFeeConfig get bridgeFee =>
      _cachedConfig?.bridge ?? BridgeFeeConfig.fallback();

  /// Short fee wallet display (0x1234...5678)
  static String shortWallet(String address) {
    if (address.length < 12) return address;
    return '${address.substring(0, 6)}...${address.substring(address.length - 4)}';
  }

  /// Check if a fee wallet address is valid
  static bool isValidFeeWallet(String address) => _isValidAddress(address);

  /// Clear cache (for testing or force refresh)
  static void clearCache() {
    _cachedConfig = null;
    _inflightRequest = null;
  }
}
