/// TPIX Wallet — Peer Sign Service
///
/// Handles `tpixwallet://sign?...` deep links from peer apps (TPIX Trade,
/// future ecosystem apps) that need a signature from this wallet.
///
/// Flow:
///   1. Peer app opens `tpixwallet://sign?message=<m>&nonce=<n>&callback=<cb>`
///   2. We show a confirmation dialog with the source app + message preview
///   3. User confirms → wallet signs with private key → opens callback URL
///      with `?nonce=<n>&signature=0x...`
///   4. User rejects → opens callback URL with `?nonce=<n>&error=user_rejected`
///
/// Also handles `tpixwallet://sign-tx?...` — peer app ขอให้ "เซ็น + broadcast
/// ธุรกรรม" บนเชน EVM (เช่น TPIX Trade เทรดจริงบน BSC): แสดงรายละเอียด
/// ธุรกรรมให้ตรวจ → ยืนยัน → เซ็นด้วย key ของกระเป๋า → ส่งขึ้นเชน →
/// callback กลับพร้อม `?txhash=0x...`
///
/// Security:
///   - Callback URL must be in allowlist (currently only tpixtrade://)
///   - Wallet must be unlocked (signed in with passcode/biometric) — otherwise reject
///   - Message preview shown to user — they can see what they're signing
///   - Nonce echoed back unmodified — prevents response spoofing
///   - sign-tx: เชนต้องอยู่ในลิสต์ที่รองรับ + to ต้องเป็น address รูปแบบถูกต้อง
///     + แสดงเครือข่าย/ปลายทาง/จำนวน/ขนาด data ให้ผู้ใช้เห็นก่อนยืนยันเสมอ
///
/// Developed by Xman Studio
library;

import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hex/hex.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/locale_provider.dart';
import '../core/theme.dart';
import '../models/chain_config.dart';
import '../providers/wallet_provider.dart';
import 'db_service.dart';

class PeerSignService {
  PeerSignService._();
  static final PeerSignService _instance = PeerSignService._();
  factory PeerSignService() => _instance;

  /// Allowed callback schemes — only let signed callbacks go to peer apps
  /// we trust. Hard-coded prevents an attacker from sending sigs to arbitrary URLs.
  static const _allowedCallbackSchemes = {'tpixtrade'};

  /// Friendly source-app names by scheme — shown in the confirmation dialog.
  static const _sourceAppNames = {
    'tpixtrade': 'TPIX Trade',
  };

  /// Try to handle a deep link; returns true if it was a sign request.
  ///
  /// Handles both:
  ///   - tpixwallet://sign?...        — plain message sign
  ///   - tpixwallet://sign-typed?...  — EIP-712 typed-data sign
  ///
  /// Caller (HomeScreen._handleDeepLink) checks the return value to know
  /// whether this URI was consumed.
  Future<bool> tryHandle(BuildContext context, Uri uri) async {
    if (uri.scheme != 'tpixwallet') return false;
    if (uri.host == 'sign-typed') {
      return _tryHandleTyped(context, uri);
    }
    if (uri.host == 'sign-tx') {
      return _tryHandleTx(context, uri);
    }
    if (uri.host != 'sign') return false;

    final message = uri.queryParameters['message'];
    final nonce = uri.queryParameters['nonce'];
    final callback = uri.queryParameters['callback'];
    final fromHint = uri.queryParameters['from'];

    if (message == null || message.isEmpty ||
        nonce == null || nonce.isEmpty ||
        callback == null || callback.isEmpty) {
      debugPrint('PeerSignService: missing required params');
      return true; // consumed but malformed — ignore silently
    }

    // Validate callback URL — must be a peer app we trust
    final cbUri = Uri.tryParse(callback);
    if (cbUri == null || !_allowedCallbackSchemes.contains(cbUri.scheme)) {
      debugPrint('PeerSignService: callback scheme not allowed');
      return true;
    }

    // Validate nonce format (32 hex chars from Trade)
    if (!RegExp(r'^[a-fA-F0-9]{8,64}$').hasMatch(nonce)) {
      debugPrint('PeerSignService: invalid nonce format');
      return true;
    }

    // Limit message size — prevents giant payloads being shown in dialog
    if (message.length > 2000) {
      debugPrint('PeerSignService: message too large');
      await _sendCallback(cbUri, nonce: nonce, error: 'message_too_large');
      return true;
    }

    if (!context.mounted) return true;

    final sourceName = _sourceAppNames[cbUri.scheme] ?? cbUri.scheme;
    final approved = await _showConfirmDialog(
      context,
      sourceName: sourceName,
      message: message,
      fromHint: fromHint,
    );

    if (!context.mounted) return true;

    final wallet = context.read<WalletProvider>();
    final sourceAppName = _sourceAppNames[cbUri.scheme] ?? cbUri.scheme;

    if (!approved) {
      await _sendCallback(cbUri, nonce: nonce, error: 'user_rejected');
      await _logSign(
        wallet: wallet,
        sourceApp: sourceAppName,
        sourceScheme: cbUri.scheme,
        message: message,
        status: 'rejected',
        nonce: nonce,
      );
      return true;
    }

    // Wallet must be unlocked to sign
    if (!wallet.isUnlocked) {
      await _sendCallback(cbUri, nonce: nonce, error: 'wallet_locked');
      await _logSign(
        wallet: wallet,
        sourceApp: sourceAppName,
        sourceScheme: cbUri.scheme,
        message: message,
        status: 'wallet_locked',
        nonce: nonce,
      );
      return true;
    }

    // Sign + send back
    try {
      final signature = await wallet.signPersonalMessage(message);
      await _sendCallback(cbUri, nonce: nonce, signature: signature);
      await _logSign(
        wallet: wallet,
        sourceApp: sourceAppName,
        sourceScheme: cbUri.scheme,
        message: message,
        status: 'signed',
        nonce: nonce,
      );
    } catch (e) {
      debugPrint('PeerSignService.sign: ${e.runtimeType}');
      await _sendCallback(cbUri, nonce: nonce, error: 'sign_failed');
      await _logSign(
        wallet: wallet,
        sourceApp: sourceAppName,
        sourceScheme: cbUri.scheme,
        message: message,
        status: 'sign_failed',
        nonce: nonce,
      );
    }
    return true;
  }

  /// Handle tpixwallet://sign-typed — EIP-712 typed-data sign request
  ///
  /// Decodes the `typed` param as JSON, shows a structured preview,
  /// signs the JSON string as personal_sign (simplified — matches the
  /// approach in WalletConnectService._handleSignTypedData).
  Future<bool> _tryHandleTyped(BuildContext context, Uri uri) async {
    final typedJson = uri.queryParameters['typed'];
    final nonce = uri.queryParameters['nonce'];
    final callback = uri.queryParameters['callback'];

    if (typedJson == null || nonce == null || callback == null) {
      debugPrint('PeerSignService.typed: missing params');
      return true;
    }

    final cbUri = Uri.tryParse(callback);
    if (cbUri == null || !_allowedCallbackSchemes.contains(cbUri.scheme)) {
      debugPrint('PeerSignService.typed: callback scheme not allowed');
      return true;
    }
    if (!RegExp(r'^[a-fA-F0-9]{8,64}$').hasMatch(nonce)) {
      debugPrint('PeerSignService.typed: invalid nonce');
      return true;
    }
    if (typedJson.length > 4000) {
      await _sendCallback(cbUri, nonce: nonce, error: 'message_too_large');
      return true;
    }

    // Parse + validate EIP-712 structure
    Map<String, dynamic>? typedData;
    try {
      final decoded = jsonDecode(typedJson);
      if (decoded is Map<String, dynamic>) typedData = decoded;
    } catch (_) {}
    if (typedData == null || typedData['primaryType'] == null) {
      await _sendCallback(cbUri, nonce: nonce, error: 'invalid_typed_data');
      return true;
    }

    if (!context.mounted) return true;

    final sourceName = _sourceAppNames[cbUri.scheme] ?? cbUri.scheme;
    final approved = await _showTypedConfirmDialog(
      context,
      sourceName: sourceName,
      typedData: typedData,
    );

    if (!context.mounted) return true;

    final wallet = context.read<WalletProvider>();

    if (!approved) {
      await _sendCallback(cbUri, nonce: nonce, error: 'user_rejected');
      await _logSign(
        wallet: wallet,
        sourceApp: sourceName,
        sourceScheme: cbUri.scheme,
        message: typedJson,
        status: 'rejected',
        nonce: nonce,
      );
      return true;
    }

    if (!wallet.isUnlocked) {
      await _sendCallback(cbUri, nonce: nonce, error: 'wallet_locked');
      await _logSign(
        wallet: wallet,
        sourceApp: sourceName,
        sourceScheme: cbUri.scheme,
        message: typedJson,
        status: 'wallet_locked',
        nonce: nonce,
      );
      return true;
    }

    try {
      // Simplified EIP-712: sign JSON as personal_sign
      // (matches WalletConnectService approach — full struct hashing TBD)
      final signature = await wallet.signPersonalMessage(typedJson);
      await _sendCallback(cbUri, nonce: nonce, signature: signature);
      await _logSign(
        wallet: wallet,
        sourceApp: sourceName,
        sourceScheme: cbUri.scheme,
        message: typedJson,
        status: 'signed',
        nonce: nonce,
      );
    } catch (e) {
      debugPrint('PeerSignService.typed sign: ${e.runtimeType}');
      await _sendCallback(cbUri, nonce: nonce, error: 'sign_failed');
      await _logSign(
        wallet: wallet,
        sourceApp: sourceName,
        sourceScheme: cbUri.scheme,
        message: typedJson,
        status: 'sign_failed',
        nonce: nonce,
      );
    }
    return true;
  }

  /// Handle tpixwallet://sign-tx — เซ็น + broadcast ธุรกรรม EVM ให้ peer app
  ///
  /// tx param เป็น JSON:
  /// `{"chainId":56,"to":"0x..","value":"0x..","data":"0x..","summary":"Buy BTC"}`
  /// สำเร็จ → callback `?nonce=..&txhash=0x..`
  /// ผิดพลาด → callback `?nonce=..&error=<code>`
  Future<bool> _tryHandleTx(BuildContext context, Uri uri) async {
    final txJson = uri.queryParameters['tx'];
    final nonce = uri.queryParameters['nonce'];
    final callback = uri.queryParameters['callback'];

    if (txJson == null || nonce == null || callback == null) {
      debugPrint('PeerSignService.tx: missing params');
      return true;
    }

    final cbUri = Uri.tryParse(callback);
    if (cbUri == null || !_allowedCallbackSchemes.contains(cbUri.scheme)) {
      debugPrint('PeerSignService.tx: callback scheme not allowed');
      return true;
    }
    if (!RegExp(r'^[a-fA-F0-9]{8,64}$').hasMatch(nonce)) {
      debugPrint('PeerSignService.tx: invalid nonce');
      return true;
    }
    if (txJson.length > 8000) {
      await _sendCallback(cbUri, nonce: nonce, error: 'message_too_large');
      return true;
    }

    // ── Parse + validate โครงสร้างธุรกรรม (ข้อมูลจากภายนอก = ไม่เชื่อจนกว่าตรวจ) ──
    Map<String, dynamic>? tx;
    try {
      final decoded = jsonDecode(txJson);
      if (decoded is Map<String, dynamic>) tx = decoded;
    } catch (_) {}
    final chainId = tx?['chainId'];
    final to = tx?['to'];
    if (tx == null ||
        chainId is! int ||
        to is! String ||
        !RegExp(r'^0x[a-fA-F0-9]{40}$').hasMatch(to)) {
      await _sendCallback(cbUri, nonce: nonce, error: 'invalid_tx');
      return true;
    }

    // เชนต้องอยู่ในลิสต์ที่กระเป๋ารองรับ (มี RPC ของตัวเอง)
    ChainConfig? chain;
    for (final c in ChainConfig.all) {
      if (c.chainId == chainId) {
        chain = c;
        break;
      }
    }
    if (chain == null) {
      await _sendCallback(cbUri, nonce: nonce, error: 'unsupported_chain');
      return true;
    }

    // value (wei hex) — optional
    BigInt value = BigInt.zero;
    final valueHex = tx['value'];
    if (valueHex is String && valueHex.isNotEmpty) {
      final cleaned = valueHex.startsWith('0x') ? valueHex.substring(2) : valueHex;
      if (!RegExp(r'^[a-fA-F0-9]{1,64}$').hasMatch(cleaned)) {
        await _sendCallback(cbUri, nonce: nonce, error: 'invalid_tx');
        return true;
      }
      value = BigInt.parse(cleaned, radix: 16);
    }

    // data (calldata hex) — optional
    Uint8List? data;
    final dataHex = tx['data'];
    if (dataHex is String && dataHex.isNotEmpty) {
      final cleaned = dataHex.startsWith('0x') ? dataHex.substring(2) : dataHex;
      if (cleaned.length.isOdd ||
          cleaned.length > 6000 ||
          !RegExp(r'^[a-fA-F0-9]*$').hasMatch(cleaned)) {
        await _sendCallback(cbUri, nonce: nonce, error: 'invalid_tx');
        return true;
      }
      data = Uint8List.fromList(HEX.decode(cleaned));
    }

    final summary = tx['summary'] is String
        ? (tx['summary'] as String).substring(
            0, (tx['summary'] as String).length.clamp(0, 200))
        : null;

    if (!context.mounted) return true;

    // ── Preview ให้ผู้ใช้ตรวจก่อนยืนยัน ──
    final isThai = context.read<LocaleProvider>().isThai;
    // แสดงจำนวนแบบ 4 ตำแหน่ง: wei ~/ 1e14 → หน่วย 1e-4 → หารต่อด้วย 10000
    final valueText = value > BigInt.zero
        ? '${(value ~/ BigInt.from(10).pow(14)).toInt() / 10000} ${chain.symbol}'
        : '0 ${chain.symbol}';
    final lines = <String>[
      if (summary != null && summary.isNotEmpty) ...[
        '═ ${isThai ? 'รายการ' : 'Action'} ═',
        '  $summary',
        '',
      ],
      '═ ${isThai ? 'ธุรกรรม' : 'Transaction'} ═',
      '  ${isThai ? 'เครือข่าย' : 'Network'}: ${chain.name} ($chainId)',
      '  ${isThai ? 'ปลายทาง' : 'To'}: $to',
      '  ${isThai ? 'จำนวน' : 'Value'}: $valueText',
      if (data != null)
        '  Data: ${data.length} bytes (0x${HEX.encode(data.take(4).toList())}…)',
      '',
      isThai
          ? '⚠ ยืนยันแล้วธุรกรรมจะถูกส่งขึ้นเชนจริงทันที'
          : '⚠ On confirm this transaction is broadcast on-chain immediately',
    ];

    final sourceName = _sourceAppNames[cbUri.scheme] ?? cbUri.scheme;
    final approved = await _showConfirmDialog(
      context,
      sourceName: sourceName,
      message: lines.join('\n'),
    );

    if (!context.mounted) return true;

    final wallet = context.read<WalletProvider>();
    final logMessage = jsonEncode({
      'type': 'sign-tx',
      'chainId': chainId,
      'to': to,
      'value': value.toString(),
      'dataBytes': data?.length ?? 0,
      if (summary != null) 'summary': summary,
    });

    if (!approved) {
      await _sendCallback(cbUri, nonce: nonce, error: 'user_rejected');
      await _logSign(
        wallet: wallet,
        sourceApp: sourceName,
        sourceScheme: cbUri.scheme,
        message: logMessage,
        status: 'rejected',
        nonce: nonce,
      );
      return true;
    }

    if (!wallet.isUnlocked) {
      await _sendCallback(cbUri, nonce: nonce, error: 'wallet_locked');
      await _logSign(
        wallet: wallet,
        sourceApp: sourceName,
        sourceScheme: cbUri.scheme,
        message: logMessage,
        status: 'wallet_locked',
        nonce: nonce,
      );
      return true;
    }

    // ── เซ็น + broadcast (gas ประเมินอัตโนมัติโดย web3dart — path เดียว
    //    กับหน้า swap ของกระเป๋าเอง) ──
    try {
      final txHash = await wallet.sendEvmTransaction(
        rpcUrl: chain.rpcUrl,
        chainId: chainId,
        toAddress: to,
        value: value > BigInt.zero ? value : null,
        data: data,
      );
      await _sendCallback(cbUri, nonce: nonce, txHash: txHash);
      await _logSign(
        wallet: wallet,
        sourceApp: sourceName,
        sourceScheme: cbUri.scheme,
        message: logMessage,
        status: 'tx_sent',
        nonce: nonce,
      );
    } catch (e) {
      debugPrint('PeerSignService.tx send: ${e.runtimeType}');
      await _sendCallback(cbUri, nonce: nonce, error: 'tx_failed');
      await _logSign(
        wallet: wallet,
        sourceApp: sourceName,
        sourceScheme: cbUri.scheme,
        message: logMessage,
        status: 'tx_failed',
        nonce: nonce,
      );
    }
    return true;
  }

  /// Pretty-print EIP-712 typed-data for the confirmation dialog
  Future<bool> _showTypedConfirmDialog(
    BuildContext context, {
    required String sourceName,
    required Map<String, dynamic> typedData,
  }) async {
    final primaryType = typedData['primaryType'] as String? ?? '?';
    final message = typedData['message'];
    final domain = typedData['domain'];

    final lines = <String>[];
    if (domain is Map) {
      lines.add('═ Domain ═');
      domain.forEach((k, v) => lines.add('  $k: $v'));
    }
    lines.add('');
    lines.add('═ $primaryType ═');
    if (message is Map) {
      message.forEach((k, v) => lines.add('  $k: $v'));
    }

    final l = context.read<LocaleProvider>();
    final c = AppColors.of(context);
    final isThai = l.isThai;

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SignConfirmSheet(
        sourceName: sourceName,
        message: jsonEncode(typedData),
        preview: lines.join('\n'),
        isThai: isThai,
        bgColor: c.surface,
        textColor: c.text,
        textSecondary: c.textSec,
      ),
    );
    return result == true;
  }

  /// Write a row to the local sign history log. Best-effort — failures are
  /// silently ignored because we shouldn't fail a sign over a logging glitch.
  Future<void> _logSign({
    required WalletProvider wallet,
    required String sourceApp,
    required String sourceScheme,
    required String message,
    required String status,
    String? nonce,
  }) async {
    try {
      final hash = sha256.convert(utf8.encode(message)).toString();
      await DbService.logSign(
        sourceApp: sourceApp,
        sourceScheme: sourceScheme,
        message: message,
        messageHash: hash,
        status: status,
        walletSlot: wallet.activeSlot,
        nonce: nonce,
      );
      // Keep log small — prune periodically
      await DbService.pruneSignHistory(wallet.activeSlot);
    } catch (e) {
      debugPrint('PeerSignService.logSign: ${e.runtimeType}');
    }
  }

  /// Open the callback URL — wallet→peer app handoff
  Future<void> _sendCallback(
    Uri callback, {
    required String nonce,
    String? signature,
    String? txHash,
    String? error,
  }) async {
    final params = <String, String>{
      'nonce': nonce,
      if (signature != null) 'signature': signature,
      if (txHash != null) 'txhash': txHash,
      if (error != null) 'error': error,
    };
    // Reuse callback's host (e.g., 'sign-result') and append our params
    final outUri = callback.replace(queryParameters: {
      ...callback.queryParameters,
      ...params,
    });
    try {
      await launchUrl(outUri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('PeerSignService.sendCallback: ${e.runtimeType}');
    }
  }

  /// Bottom sheet asking user to confirm/reject the signature
  Future<bool> _showConfirmDialog(
    BuildContext context, {
    required String sourceName,
    required String message,
    String? fromHint,
  }) async {
    final l = context.read<LocaleProvider>();
    final c = AppColors.of(context);
    final isThai = l.isThai;

    // Try to detect if message is a structured login challenge — show prettier preview
    final preview = _safePreview(message);

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => _SignConfirmSheet(
        sourceName: sourceName,
        message: message,
        preview: preview,
        isThai: isThai,
        bgColor: c.surface,
        textColor: c.text,
        textSecondary: c.textSec,
      ),
    );
    return result == true;
  }

  /// Attempt to JSON-decode message and pretty-print it; falls back to raw.
  /// Sign challenges are typically:
  ///   "Sign in to TPIX Trade\nNonce: abc123\nIssued: 2026-04-17T..."
  String _safePreview(String message) {
    try {
      final decoded = jsonDecode(message);
      if (decoded is Map) {
        return decoded.entries
            .map((e) => '${e.key}: ${e.value}')
            .join('\n');
      }
    } catch (_) {/* not JSON, that's fine */}
    return message;
  }
}

class _SignConfirmSheet extends StatelessWidget {
  final String sourceName;
  final String message;
  final String preview;
  final bool isThai;
  final Color bgColor;
  final Color textColor;
  final Color textSecondary;

  const _SignConfirmSheet({
    required this.sourceName,
    required this.message,
    required this.preview,
    required this.isThai,
    required this.bgColor,
    required this.textColor,
    required this.textSecondary,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.8,
      ),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        top: 16,
        left: 24,
        right: 24,
        bottom: 24 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Handle bar
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: textSecondary.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.draw_rounded,
                    color: AppTheme.accent, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  isThai
                      ? '$sourceName ขอลายเซ็น'
                      : '$sourceName requests signature',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: textColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            isThai
                ? 'ตรวจข้อความก่อนเซ็น — อย่าเซ็นถ้าไม่แน่ใจ'
                : 'Review the message before signing — do not sign if unsure',
            style: TextStyle(fontSize: 12, color: textSecondary),
          ),
          const SizedBox(height: 16),
          Flexible(
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: textSecondary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: textSecondary.withValues(alpha: 0.15)),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  preview,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.5,
                    color: textColor,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                          color: textSecondary.withValues(alpha: 0.3)),
                    ),
                  ),
                  child: Text(
                    isThai ? 'ปฏิเสธ' : 'Reject',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: textSecondary),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accent,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    isThai ? 'เซ็นชื่อ' : 'Sign',
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
