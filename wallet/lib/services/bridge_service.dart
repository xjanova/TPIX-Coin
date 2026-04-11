import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/chain_config.dart';
import 'fee_service.dart';

/// Bridge record for tracking cross-chain transfers
class BridgeRecord {
  final String bridgeId;
  final int sourceChainId;
  final int destChainId;
  final String tokenSymbol;
  final String amount;
  final String status; // pending, source_confirmed, processing, completed, failed
  final String? sourceTxHash;
  final String? destTxHash;
  final DateTime createdAt;

  BridgeRecord({
    required this.bridgeId,
    required this.sourceChainId,
    required this.destChainId,
    required this.tokenSymbol,
    required this.amount,
    required this.status,
    this.sourceTxHash,
    this.destTxHash,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  String get statusDisplay {
    switch (status) {
      case 'pending':
        return 'Pending';
      case 'source_confirmed':
        return 'Confirmed on Source';
      case 'processing':
        return 'Processing';
      case 'completed':
        return 'Completed';
      case 'failed':
        return 'Failed';
      default:
        return status;
    }
  }
}

/// Bridge service for cross-chain transfers
/// Uses TPIX Bridge API (centralized relay for MVP)
/// Fee configuration sourced from tpix.online via FeeService
class BridgeService {
  static const _apiBase = 'https://tpix.online/api/v1/bridge';

  /// Get supported bridge routes (fees loaded dynamically from tpix.online)
  static Future<List<BridgeRoute>> getRoutes() async {
    final feeConfig = await FeeService.getBridgeFee();
    return [
      BridgeRoute(
        sourceChain: ChainConfig.tpix,
        destChain: ChainConfig.bsc,
        tokenSymbol: 'TPIX',
        feePercent: feeConfig.feePercent,
        feeWallet: feeConfig.feeWallet,
        minAmount: feeConfig.minAmount,
        maxAmount: feeConfig.maxAmount,
      ),
      BridgeRoute(
        sourceChain: ChainConfig.bsc,
        destChain: ChainConfig.tpix,
        tokenSymbol: 'WTPIX',
        feePercent: feeConfig.feePercent,
        feeWallet: feeConfig.feeWallet,
        minAmount: feeConfig.minAmount,
        maxAmount: feeConfig.maxAmount,
      ),
    ];
  }

  /// Get bridge routes synchronously (uses cached fee, call getRoutes() first)
  static List<BridgeRoute> get routesCached {
    final feeConfig = FeeService.bridgeFee;
    return [
      BridgeRoute(
        sourceChain: ChainConfig.tpix,
        destChain: ChainConfig.bsc,
        tokenSymbol: 'TPIX',
        feePercent: feeConfig.feePercent,
        feeWallet: feeConfig.feeWallet,
        minAmount: feeConfig.minAmount,
        maxAmount: feeConfig.maxAmount,
      ),
      BridgeRoute(
        sourceChain: ChainConfig.bsc,
        destChain: ChainConfig.tpix,
        tokenSymbol: 'WTPIX',
        feePercent: feeConfig.feePercent,
        feeWallet: feeConfig.feeWallet,
        minAmount: feeConfig.minAmount,
        maxAmount: feeConfig.maxAmount,
      ),
    ];
  }

  /// Get bridge fee estimate — uses FeeService config from tpix.online
  /// Always uses the same feeWallet as FeeService to prevent mismatch
  static Future<BridgeFee?> getFee({
    required int sourceChainId,
    required int destChainId,
    required String token,
    required double amount,
  }) async {
    final feeConfig = await FeeService.getBridgeFee();

    // Try bridge-specific API for real-time fee override
    try {
      final client = http.Client();
      try {
        final response = await client.get(
          Uri.parse('$_apiBase/fee?source=$sourceChainId&dest=$destChainId&token=$token&amount=$amount'),
        ).timeout(const Duration(seconds: 10));
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          // Validate API-returned fee wallet; reject invalid addresses
          final apiWallet = data['feeWallet'] as String? ?? '';
          final wallet = FeeService.isValidFeeWallet(apiWallet)
              ? apiWallet
              : feeConfig.feeWallet;
          final percent = (data['feePercent'] as num?)?.toDouble() ?? feeConfig.feePercent;
          final fee = (data['fee'] as num?)?.toDouble() ?? amount * percent / 100;
          return BridgeFee(
            feeAmount: fee,
            feePercent: percent,
            feeWallet: wallet,
            estimatedTime: data['estimatedMinutes'] as int? ?? feeConfig.estimatedMinutes,
            receiveAmount: (data['receive'] as num?)?.toDouble() ?? (amount - fee),
          );
        }
      } finally {
        client.close();
      }
    } catch (_) {
      // Use FeeService config as fallback
    }

    // Fallback: calculate from FeeService config
    final feeAmount = feeConfig.calculateFee(amount);
    return BridgeFee(
      feeAmount: feeAmount,
      feePercent: feeConfig.feePercent,
      feeWallet: feeConfig.feeWallet,
      estimatedTime: feeConfig.estimatedMinutes,
      receiveAmount: amount - feeAmount,
    );
  }

  /// Map chain IDs to direction string expected by Laravel API
  static String directionFromChainIds(int sourceChainId) {
    return sourceChainId == 4289 ? 'tpix_to_bsc' : 'bsc_to_tpix';
  }

  /// Check bridge status
  /// Response matches Laravel BridgeApiController.status()
  static Future<BridgeRecord?> getStatus(String bridgeId) async {
    try {
      final client = http.Client();
      try {
        final response = await client.get(
          Uri.parse('$_apiBase/status/$bridgeId'),
        ).timeout(const Duration(seconds: 10));

        if (response.statusCode == 200) {
          final body = jsonDecode(response.body);
          final data = body['data'] as Map<String, dynamic>?;
          if (data == null) return null;

          // Map direction back to chain IDs
          final direction = data['direction'] as String? ?? 'tpix_to_bsc';
          final isTpixToBsc = direction == 'tpix_to_bsc';

          return BridgeRecord(
            bridgeId: bridgeId,
            sourceChainId: isTpixToBsc ? 4289 : 56,
            destChainId: isTpixToBsc ? 56 : 4289,
            tokenSymbol: isTpixToBsc ? 'TPIX' : 'WTPIX',
            amount: data['amount']?.toString() ?? '0',
            status: data['status'] as String? ?? 'pending',
            sourceTxHash: data['source_tx_hash'] as String?,
            destTxHash: data['target_tx_hash'] as String?,
          );
        }
      } finally {
        client.close();
      }
    } catch (_) {}
    return null;
  }
}

/// A supported bridge route (fee config from tpix.online)
class BridgeRoute {
  final ChainConfig sourceChain;
  final ChainConfig destChain;
  final String tokenSymbol;
  final double feePercent; // from tpix.online API
  final String feeWallet; // wallet address from tpix.online API
  final double minAmount;
  final double maxAmount;

  const BridgeRoute({
    required this.sourceChain,
    required this.destChain,
    required this.tokenSymbol,
    required this.feePercent,
    required this.feeWallet,
    required this.minAmount,
    required this.maxAmount,
  });
}

/// Bridge fee estimate (from tpix.online)
class BridgeFee {
  final double feeAmount;
  final double feePercent;
  final String feeWallet; // wallet address receiving the fee
  final int estimatedTime; // minutes
  final double receiveAmount;

  const BridgeFee({
    required this.feeAmount,
    required this.feePercent,
    required this.feeWallet,
    required this.estimatedTime,
    required this.receiveAmount,
  });
}
