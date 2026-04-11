import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:reown_walletkit/reown_walletkit.dart';
import 'package:tpix_wallet/models/chain_config.dart';
import 'package:tpix_wallet/providers/wallet_provider.dart';

/// WalletConnect v2 service — manages dApp connections for TPIX Wallet.
///
/// Flow:
/// 1. dApp shows QR code / deep link
/// 2. User scans → [pair] creates pairing
/// 3. dApp sends SessionProposal → [onSessionProposal] fires
/// 4. User approves → wallet responds with approved namespaces
/// 5. dApp sends requests (personal_sign, eth_sendTransaction) → [onSessionRequest] fires
/// 6. Wallet signs and responds
class WalletConnectService extends ChangeNotifier {
  // ================================================================
  //  Constants
  // ================================================================

  /// Register at https://cloud.reown.com to get your project ID.
  /// Replace this placeholder before release.
  static const String _projectId = '52dc35105b74ddd9ade472de308b02d5';

  static const PairingMetadata _metadata = PairingMetadata(
    name: 'TPIX Wallet',
    description: 'Official wallet for TPIX Chain — gasless, fast, secure.',
    url: 'https://tpix.online',
    icons: ['https://tpix.online/tpixlogo.webp'],
    redirect: Redirect(
      native: 'tpixwallet://',
      universal: 'https://tpix.online/wallet',
    ),
  );

  /// Supported EVM chains: TPIX (4289), BSC (56), Polygon (137), ETH (1)
  static final List<String> _supportedChains =
      ChainConfig.all.map((c) => 'eip155:${c.chainId}').toList();

  static const List<String> _supportedMethods = [
    'personal_sign',
    'eth_sign',
    'eth_signTransaction',
    'eth_sendTransaction',
    'eth_signTypedData',
    'eth_signTypedData_v4',
    'wallet_switchEthereumChain',
    'wallet_addEthereumChain',
  ];

  static const List<String> _supportedEvents = [
    'chainChanged',
    'accountsChanged',
  ];

  // ================================================================
  //  State
  // ================================================================

  ReownWalletKit? _walletKit;
  WalletProvider? _walletProvider;

  bool _initialized = false;
  bool get initialized => _initialized;

  /// Current pending session proposal (shown in approval dialog)
  SessionProposalEvent? _pendingProposal;
  SessionProposalEvent? get pendingProposal => _pendingProposal;

  /// Current pending session request (sign / sendTx)
  SessionRequestEvent? _pendingRequest;
  SessionRequestEvent? get pendingRequest => _pendingRequest;

  /// Active sessions
  List<SessionData> get sessions =>
      _walletKit?.sessions.getAll() ?? [];

  /// Whether there's a pending approval to show
  bool get hasPendingProposal => _pendingProposal != null;
  bool get hasPendingRequest => _pendingRequest != null;

  /// Callback when a session proposal arrives (UI should show approval dialog)
  void Function(SessionProposalEvent)? onProposalReceived;

  /// Callback when a sign/tx request arrives (UI should show signing dialog)
  void Function(SessionRequestEvent)? onRequestReceived;

  // ================================================================
  //  Init
  // ================================================================

  /// Initialize WalletConnect SDK. Call once after wallet is unlocked.
  Future<void> init(WalletProvider walletProvider) async {
    if (_initialized) return;
    _walletProvider = walletProvider;

    try {
      _walletKit = await ReownWalletKit.createInstance(
        projectId: _projectId,
        metadata: _metadata,
      );

      // Register supported namespaces
      _registerEventHandlers();

      _initialized = true;
      notifyListeners();
      debugPrint('[WC] WalletConnect initialized');
    } catch (e) {
      debugPrint('[WC] Init failed: $e');
    }
  }

  void _registerEventHandlers() {
    final kit = _walletKit;
    if (kit == null) return;

    // Session proposal — dApp wants to connect
    kit.onSessionProposal.subscribe(_handleSessionProposal);

    // Session request — dApp wants wallet to do something
    kit.onSessionRequest.subscribe(_handleSessionRequest);

    // Session delete — dApp disconnected
    kit.onSessionDelete.subscribe((_) {
      notifyListeners();
    });

    // Register request handlers for each method
    for (final method in _supportedMethods) {
      kit.registerRequestHandler(
        chainId: 'eip155:4289',
        method: method,
      );
    }
  }

  // ================================================================
  //  Pairing (QR scan / deep link)
  // ================================================================

  /// Parse a WalletConnect URI and initiate pairing.
  /// Called when user scans QR code or opens wc: deep link.
  Future<void> pair(String uri) async {
    if (_walletKit == null) {
      throw Exception('WalletConnect not initialized');
    }

    try {
      final parsedUri = Uri.parse(uri);
      await _walletKit!.pair(uri: parsedUri);
      debugPrint('[WC] Pairing initiated');
    } catch (e) {
      debugPrint('[WC] Pairing failed: $e');
      rethrow;
    }
  }

  // ================================================================
  //  Session Proposal
  // ================================================================

  void _handleSessionProposal(SessionProposalEvent? event) {
    if (event == null) return;
    _pendingProposal = event;
    notifyListeners();
    onProposalReceived?.call(event);
  }

  /// Approve the current session proposal.
  Future<void> approveProposal() async {
    final proposal = _pendingProposal;
    if (proposal == null || _walletKit == null || _walletProvider == null) return;

    final address = _walletProvider!.address;
    if (address == null) return;

    try {
      // Build approved namespaces — approve all supported chains with wallet address
      final accounts = ChainConfig.all
          .map((c) => 'eip155:${c.chainId}:$address')
          .toList();

      final approvedNamespaces = {
        'eip155': Namespace(
          chains: _supportedChains,
          accounts: accounts,
          methods: _supportedMethods,
          events: _supportedEvents,
        ),
      };

      await _walletKit!.approveSession(
        id: proposal.id,
        namespaces: approvedNamespaces,
      );

      debugPrint('[WC] Session approved');
    } catch (e) {
      debugPrint('[WC] Approve failed: $e');
    } finally {
      _pendingProposal = null;
      notifyListeners();
    }
  }

  /// Reject the current session proposal.
  Future<void> rejectProposal() async {
    final proposal = _pendingProposal;
    if (proposal == null || _walletKit == null) return;

    try {
      await _walletKit!.rejectSession(
        id: proposal.id,
        reason: Errors.getSdkError(Errors.USER_REJECTED).toSignError(),
      );
    } catch (e) {
      debugPrint('[WC] Reject failed: $e');
    } finally {
      _pendingProposal = null;
      notifyListeners();
    }
  }

  // ================================================================
  //  Session Requests (sign / send)
  // ================================================================

  void _handleSessionRequest(SessionRequestEvent? event) {
    if (event == null) return;
    _pendingRequest = event;
    notifyListeners();
    onRequestReceived?.call(event);
  }

  /// Approve and execute the current session request.
  Future<void> approveRequest() async {
    final request = _pendingRequest;
    if (request == null || _walletKit == null || _walletProvider == null) return;

    try {
      final method = request.method;
      final params = request.params;
      String result;

      switch (method) {
        case 'personal_sign':
          result = await _handlePersonalSign(params);
          break;
        case 'eth_sign':
          result = await _handlePersonalSign(params);
          break;
        case 'eth_sendTransaction':
          result = await _handleSendTransaction(params, request.chainId);
          break;
        case 'eth_signTypedData':
        case 'eth_signTypedData_v4':
          result = await _handleSignTypedData(params);
          break;
        default:
          throw Exception('Unsupported method: $method');
      }

      await _walletKit!.respondSessionRequest(
        topic: request.topic,
        response: JsonRpcResponse(
          id: request.id,
          result: result,
        ),
      );

      debugPrint('[WC] Request approved: $method');
    } catch (e) {
      await _walletKit!.respondSessionRequest(
        topic: request.topic,
        response: JsonRpcResponse(
          id: request.id,
          error: JsonRpcError(code: -32000, message: e.toString()),
        ),
      );
      debugPrint('[WC] Request failed: $e');
    } finally {
      _pendingRequest = null;
      notifyListeners();
    }
  }

  /// Reject the current session request.
  Future<void> rejectRequest() async {
    final request = _pendingRequest;
    if (request == null || _walletKit == null) return;

    try {
      await _walletKit!.respondSessionRequest(
        topic: request.topic,
        response: JsonRpcResponse(
          id: request.id,
          error: JsonRpcError(
            code: 4001,
            message: 'User rejected the request',
          ),
        ),
      );
    } catch (e) {
      debugPrint('[WC] Reject request failed: $e');
    } finally {
      _pendingRequest = null;
      notifyListeners();
    }
  }

  // ================================================================
  //  Method Handlers
  // ================================================================

  /// personal_sign: params = [message_hex, address]
  Future<String> _handlePersonalSign(dynamic params) async {
    if (_walletProvider == null) throw Exception('Wallet not available');

    final List<dynamic> paramList = params is List ? params : [params];
    // personal_sign: first param is the message (hex), second is address
    String message;
    if (paramList.isNotEmpty) {
      final raw = paramList[0].toString();
      if (raw.startsWith('0x')) {
        // Hex-encoded message — decode to string
        final bytes = _hexToBytes(raw.substring(2));
        message = utf8.decode(bytes, allowMalformed: true);
      } else {
        message = raw;
      }
    } else {
      throw Exception('No message to sign');
    }

    return _walletProvider!.signPersonalMessage(message);
  }

  /// eth_sendTransaction: params = [{ to, value, data, gas, gasPrice }]
  Future<String> _handleSendTransaction(dynamic params, String chainId) async {
    if (_walletProvider == null) throw Exception('Wallet not available');

    final List<dynamic> paramList = params is List ? params : [params];
    if (paramList.isEmpty) throw Exception('No transaction data');

    final tx = paramList[0] as Map<String, dynamic>;
    final to = tx['to'] as String;
    final valueHex = tx['value'] as String? ?? '0x0';
    final dataHex = tx['data'] as String?;
    final gasHex = tx['gas'] as String?;
    final gasPriceHex = tx['gasPrice'] as String?;

    // Parse chain ID from WC namespace (eip155:4289 → 4289)
    final chainIdNum = int.parse(chainId.split(':').last);
    final chain = ChainConfig.byId(chainIdNum);

    final value = BigInt.parse(
      valueHex.startsWith('0x') ? valueHex.substring(2) : valueHex,
      radix: 16,
    );

    Uint8List? data;
    if (dataHex != null && dataHex != '0x' && dataHex.length > 2) {
      data = _hexToBytes(dataHex.startsWith('0x') ? dataHex.substring(2) : dataHex);
    }

    int? maxGas;
    if (gasHex != null) {
      maxGas = int.parse(
        gasHex.startsWith('0x') ? gasHex.substring(2) : gasHex,
        radix: 16,
      );
    }

    BigInt? gasPrice;
    if (chain.isGasless) {
      gasPrice = BigInt.zero;
    } else if (gasPriceHex != null) {
      gasPrice = BigInt.parse(
        gasPriceHex.startsWith('0x') ? gasPriceHex.substring(2) : gasPriceHex,
        radix: 16,
      );
    }

    return _walletProvider!.sendEvmTransaction(
      rpcUrl: chain.rpcUrl,
      chainId: chainIdNum,
      toAddress: to,
      value: value,
      data: data,
      maxGas: maxGas,
      gasPrice: gasPrice,
    );
  }

  /// eth_signTypedData: params = [address, typed_data_json]
  Future<String> _handleSignTypedData(dynamic params) async {
    // For typed data, we sign the raw JSON as personal message (simplified)
    // Full EIP-712 implementation would require encoding the struct
    final List<dynamic> paramList = params is List ? params : [params];
    if (paramList.length < 2) throw Exception('Invalid signTypedData params');

    final typedDataStr = paramList[1].toString();
    return _walletProvider!.signPersonalMessage(typedDataStr);
  }

  // ================================================================
  //  Session Management
  // ================================================================

  /// Disconnect a specific session.
  Future<void> disconnectSession(String topic) async {
    if (_walletKit == null) return;

    try {
      await _walletKit!.disconnectSession(
        topic: topic,
        reason: Errors.getSdkError(Errors.USER_DISCONNECTED).toSignError(),
      );
      notifyListeners();
      debugPrint('[WC] Session disconnected: $topic');
    } catch (e) {
      debugPrint('[WC] Disconnect failed: $e');
    }
  }

  /// Disconnect all sessions.
  Future<void> disconnectAll() async {
    for (final session in sessions) {
      await disconnectSession(session.topic);
    }
  }

  /// Get human-readable info about a session's peer dApp.
  Map<String, String> getPeerInfo(SessionData session) {
    final peer = session.peer.metadata;
    return {
      'name': peer.name,
      'url': peer.url,
      'icon': peer.icons.isNotEmpty ? peer.icons.first : '',
      'description': peer.description,
    };
  }

  // ================================================================
  //  Helpers
  // ================================================================

  /// Get display info for a pending request.
  Map<String, String> getRequestDisplayInfo() {
    final request = _pendingRequest;
    if (request == null) return {};

    final method = request.method;
    String title;
    String description;

    switch (method) {
      case 'personal_sign':
      case 'eth_sign':
        title = 'Sign Message';
        final params = request.params as List?;
        if (params != null && params.isNotEmpty) {
          final raw = params[0].toString();
          if (raw.startsWith('0x')) {
            final bytes = _hexToBytes(raw.substring(2));
            description = utf8.decode(bytes, allowMalformed: true);
          } else {
            description = raw;
          }
        } else {
          description = '';
        }
        break;
      case 'eth_sendTransaction':
        title = 'Send Transaction';
        final params = request.params as List?;
        if (params != null && params.isNotEmpty) {
          final tx = params[0] as Map<String, dynamic>;
          final to = tx['to'] ?? '';
          final valueHex = tx['value'] ?? '0x0';
          final value = BigInt.parse(
            valueHex.toString().startsWith('0x')
                ? valueHex.toString().substring(2)
                : valueHex.toString(),
            radix: 16,
          );
          final ethValue = value / BigInt.from(10).pow(18);
          description = 'To: $to\nValue: $ethValue';
        } else {
          description = '';
        }
        break;
      default:
        title = method;
        description = jsonEncode(request.params);
    }

    return {
      'title': title,
      'description': description,
      'method': method,
      'chainId': request.chainId,
    };
  }

  Uint8List _hexToBytes(String hex) {
    final result = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < result.length; i++) {
      result[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return result;
  }

  // ================================================================
  //  Cleanup
  // ================================================================

  @override
  void dispose() {
    _walletKit?.onSessionProposal.unsubscribeAll();
    _walletKit?.onSessionRequest.unsubscribeAll();
    _walletKit?.onSessionDelete.unsubscribeAll();
    super.dispose();
  }
}
