import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

/// Wallet authentication service for tpix.online protected endpoints
///
/// Implements EIP-191 challenge-sign-verify flow required by
/// VerifyWalletOwnership middleware on Laravel backend.
///
/// Flow: connect → requestChallenge → signMessage → verifySignature
/// Session lasts 4 hours on server; cached locally with 3.5hr TTL.
///
/// Thread-safe: uses Completer to prevent duplicate concurrent verifications.
class WalletAuthService {
  static const _apiBase = 'https://tpix.online/api/v1';
  static const _sessionTtl = Duration(hours: 3, minutes: 30);

  // Cached verification state
  static String? _verifiedAddress;
  static DateTime? _verifiedAt;

  // Prevent concurrent verification attempts (server invalidates old nonces)
  static Completer<void>? _verifyingCompleter;

  /// Check if wallet has a valid verified session
  static bool isVerified(String walletAddress) {
    if (_verifiedAddress == null || _verifiedAt == null) return false;
    if (_verifiedAddress!.toLowerCase() != walletAddress.toLowerCase()) {
      return false;
    }
    return DateTime.now().difference(_verifiedAt!) < _sessionTtl;
  }

  /// Ensure wallet is verified before calling protected endpoints.
  /// Runs the full challenge-sign-verify flow if session is expired or missing.
  ///
  /// [signFn] takes a message string and returns the 0x-prefixed EIP-191 signature.
  /// Typically: `walletProvider.signPersonalMessage`
  ///
  /// Thread-safe: concurrent callers share the same in-flight verification.
  static Future<void> ensureVerified({
    required String walletAddress,
    required Future<String> Function(String message) signFn,
    int chainId = 4289,
  }) async {
    if (isVerified(walletAddress)) return;

    // If another verification is in-flight, wait for it
    if (_verifyingCompleter != null) {
      await _verifyingCompleter!.future;
      // After awaiting, check if we're now verified
      if (isVerified(walletAddress)) return;
    }

    // Start new verification with Completer to prevent duplicates
    _verifyingCompleter = Completer<void>();

    try {
      final addr = walletAddress.toLowerCase();

      // Step 1: Connect wallet (register/detect user)
      await _connectWallet(addr, chainId);

      // Step 2: Get challenge nonce
      final challenge = await _requestChallenge(addr);
      if (challenge == null) {
        throw Exception('Failed to get verification challenge');
      }

      final message = challenge['message'] as String;
      final nonce = challenge['nonce'] as String;

      // Step 3: Sign the challenge message with wallet's private key (EIP-191)
      final signature = await signFn(message);

      // Step 4: Submit signature for server-side ecrecover verification
      final verified = await _verifySignature(
        walletAddress: addr,
        signature: signature,
        nonce: nonce,
        chainId: chainId,
      );

      if (!verified) {
        throw Exception('Wallet verification failed');
      }

      // Cache verified state locally
      _verifiedAddress = addr;
      _verifiedAt = DateTime.now();

      _verifyingCompleter!.complete();
    } catch (e) {
      _verifyingCompleter!.completeError(e);
      rethrow;
    } finally {
      _verifyingCompleter = null;
    }
  }

  /// POST /api/v1/wallet/connect — register wallet with backend
  static Future<void> _connectWallet(String address, int chainId) async {
    final client = http.Client();
    try {
      await client.post(
        Uri.parse('$_apiBase/wallet/connect'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'wallet_address': address,
          'chain_id': chainId,
          'wallet_type': 'tpix_wallet',
        }),
      ).timeout(const Duration(seconds: 10));
    } finally {
      client.close();
    }
  }

  /// POST /api/v1/wallet/sign — get challenge message + nonce
  static Future<Map<String, dynamic>?> _requestChallenge(
    String address,
  ) async {
    final client = http.Client();
    try {
      final response = await client.post(
        Uri.parse('$_apiBase/wallet/sign'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'wallet_address': address}),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        final data = body['data'] as Map<String, dynamic>?;
        if (data != null &&
            data['message'] != null &&
            data['nonce'] != null) {
          return data;
        }
      }
    } finally {
      client.close();
    }
    return null;
  }

  /// POST /api/v1/wallet/verify-signature — prove wallet ownership
  static Future<bool> _verifySignature({
    required String walletAddress,
    required String signature,
    required String nonce,
    required int chainId,
  }) async {
    final client = http.Client();
    try {
      final response = await client.post(
        Uri.parse('$_apiBase/wallet/verify-signature'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'wallet_address': walletAddress,
          'signature': signature,
          'nonce': nonce,
          'chain_id': chainId,
        }),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        return body['verified'] == true || body['success'] == true;
      }
    } finally {
      client.close();
    }
    return false;
  }

  /// Make a POST request to a protected endpoint.
  /// On 403, clears local cache and re-verifies once (handles IP change / session expiry).
  static Future<http.Response?> _protectedPost({
    required String url,
    required Map<String, dynamic> body,
    required String walletAddress,
    required Future<String> Function(String message) signFn,
    required int chainId,
  }) async {
    await ensureVerified(
      walletAddress: walletAddress,
      signFn: signFn,
      chainId: chainId,
    );

    http.Response response;

    var client = http.Client();
    try {
      response = await client.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 15));
    } finally {
      client.close();
    }

    // If server returns 403, re-verify once and retry
    if (response.statusCode == 403) {
      clearSession();
      await ensureVerified(
        walletAddress: walletAddress,
        signFn: signFn,
        chainId: chainId,
      );

      client = http.Client();
      try {
        response = await client.post(
          Uri.parse(url),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        ).timeout(const Duration(seconds: 15));
      } finally {
        client.close();
      }
    }

    return response;
  }

  // ================================================================
  //  Protected API Calls (require VerifyWalletOwnership)
  // ================================================================

  /// Record a completed swap transaction on the backend.
  /// POST /api/v1/swap/execute
  ///
  /// Best-effort: failures are silently ignored so the user's
  /// on-chain swap is not affected by backend recording issues.
  static Future<void> recordSwap({
    required String walletAddress,
    required String fromToken,
    required String toToken,
    required double fromAmount,
    required double toAmount,
    required double feeAmount,
    required String txHash,
    required int chainId,
    required Future<String> Function(String message) signFn,
  }) async {
    try {
      await _protectedPost(
        url: '$_apiBase/swap/execute',
        body: {
          'wallet_address': walletAddress.toLowerCase(),
          'from_token': fromToken,
          'to_token': toToken,
          'from_amount': fromAmount,
          'to_amount': toAmount,
          'fee_amount': feeAmount,
          'tx_hash': txHash,
          'chain_id': chainId,
        },
        walletAddress: walletAddress,
        signFn: signFn,
        chainId: chainId,
      );
    } catch (_) {
      // Best-effort recording — the on-chain swap already succeeded
    }
  }

  /// Initiate a bridge transfer on the backend.
  /// POST /api/v1/bridge/initiate
  ///
  /// Returns the bridge ID from backend, or null on failure.
  /// Caller MUST handle null — means the bridge wasn't registered.
  static Future<String?> initiateBridge({
    required String walletAddress,
    required double amount,
    required String direction,
    required String sourceTxHash,
    required int chainId,
    required Future<String> Function(String message) signFn,
  }) async {
    final response = await _protectedPost(
      url: '$_apiBase/bridge/initiate',
      body: {
        'wallet_address': walletAddress.toLowerCase(),
        'amount': amount,
        'direction': direction,
        'tx_hash': sourceTxHash,
      },
      walletAddress: walletAddress,
      signFn: signFn,
      chainId: chainId,
    );

    if (response != null &&
        (response.statusCode == 200 || response.statusCode == 201)) {
      final body = jsonDecode(response.body);
      final data = body['data'] as Map<String, dynamic>?;
      if (data != null) {
        return data['id']?.toString();
      }
    }
    return null;
  }

  /// Clear cached verification session.
  /// Call on wallet switch, lock, or disconnect.
  static void clearSession() {
    _verifiedAddress = null;
    _verifiedAt = null;
  }
}
