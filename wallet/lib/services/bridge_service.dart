import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/chain_config.dart';

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
class BridgeService {
  static const _apiBase = 'https://tpix.online/api/bridge';

  /// Get supported bridge routes
  static List<BridgeRoute> get routes => [
        BridgeRoute(
          sourceChain: ChainConfig.tpix,
          destChain: ChainConfig.bsc,
          tokenSymbol: 'TPIX',
          fee: 0.1, // 0.1%
          minAmount: 100,
          maxAmount: 1000000,
        ),
        BridgeRoute(
          sourceChain: ChainConfig.bsc,
          destChain: ChainConfig.tpix,
          tokenSymbol: 'WTPIX',
          fee: 0.1,
          minAmount: 100,
          maxAmount: 1000000,
        ),
      ];

  /// Get bridge fee estimate
  static Future<BridgeFee?> getFee({
    required int sourceChainId,
    required int destChainId,
    required String token,
    required double amount,
  }) async {
    try {
      final client = http.Client();
      try {
        final response = await client.get(
          Uri.parse('$_apiBase/fee?source=$sourceChainId&dest=$destChainId&token=$token&amount=$amount'),
        ).timeout(const Duration(seconds: 10));
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          return BridgeFee(
            feeAmount: (data['fee'] as num?)?.toDouble() ?? amount * 0.001,
            estimatedTime: data['estimatedMinutes'] as int? ?? 10,
            receiveAmount: (data['receive'] as num?)?.toDouble() ?? amount * 0.999,
          );
        }
      } finally {
        client.close();
      }
    } catch (_) {
      // Offline estimate
    }
    // Fallback: 0.1% fee, 10 min estimate
    return BridgeFee(
      feeAmount: amount * 0.001,
      estimatedTime: 10,
      receiveAmount: amount * 0.999,
    );
  }

  /// Initiate bridge transfer
  static Future<String?> initiateBridge({
    required int sourceChainId,
    required int destChainId,
    required String token,
    required double amount,
    required String senderAddress,
    required String recipientAddress,
    required String sourceTxHash,
  }) async {
    try {
      final client = http.Client();
      try {
        final response = await client.post(
          Uri.parse('$_apiBase/initiate'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'sourceChainId': sourceChainId,
            'destChainId': destChainId,
            'token': token,
            'amount': amount,
            'sender': senderAddress,
            'recipient': recipientAddress,
            'sourceTxHash': sourceTxHash,
          }),
        ).timeout(const Duration(seconds: 15));
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          return data['bridgeId'] as String?;
        }
      } finally {
        client.close();
      }
    } catch (_) {}
    return null;
  }

  /// Check bridge status
  static Future<BridgeRecord?> getStatus(String bridgeId) async {
    try {
      final client = http.Client();
      try {
        final response = await client.get(
          Uri.parse('$_apiBase/status/$bridgeId'),
        ).timeout(const Duration(seconds: 10));
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          return BridgeRecord(
            bridgeId: bridgeId,
            sourceChainId: data['sourceChainId'] as int,
            destChainId: data['destChainId'] as int,
            tokenSymbol: data['token'] as String,
            amount: data['amount'].toString(),
            status: data['status'] as String,
            sourceTxHash: data['sourceTxHash'] as String?,
            destTxHash: data['destTxHash'] as String?,
          );
        }
      } finally {
        client.close();
      }
    } catch (_) {}
    return null;
  }
}

/// A supported bridge route
class BridgeRoute {
  final ChainConfig sourceChain;
  final ChainConfig destChain;
  final String tokenSymbol;
  final double fee; // percentage
  final double minAmount;
  final double maxAmount;

  const BridgeRoute({
    required this.sourceChain,
    required this.destChain,
    required this.tokenSymbol,
    required this.fee,
    required this.minAmount,
    required this.maxAmount,
  });
}

/// Bridge fee estimate
class BridgeFee {
  final double feeAmount;
  final int estimatedTime; // minutes
  final double receiveAmount;

  const BridgeFee({
    required this.feeAmount,
    required this.estimatedTime,
    required this.receiveAmount,
  });
}
