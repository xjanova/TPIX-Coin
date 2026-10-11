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
/// พารามิเตอร์ `address=0x…` (ทุก host: sign / sign-typed / sign-tx) = กระเป๋าที่ TRADE ผูกไว้
///   ตรงกับใบที่เปิดอยู่ → เซ็น · ตรงกับใบอื่นในแอป → ถามผู้ใช้ก่อนสลับ
///   ไม่มีในแอป → `error=address_not_found` · รูปแบบผิด → `error=invalid_address`
///   ไม่ส่งมา (TRADE รุ่นเก่า) → เซ็นด้วยใบที่เปิดอยู่ โดยหน้ายืนยันโชว์ที่อยู่เต็มเด่นๆ
///   sign-tx: `from` ใน JSON ของ tx ต้องตรงกับ `address` (ไม่ตรง = invalid_address)
///   `from=trade` ของ URL = ชื่อแอปต้นทาง ไม่ใช่ที่อยู่ · callback สำเร็จแนบ `address` ของผู้เซ็นกลับไป
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
import '../core/themes/tokens.dart';
import 'package:flutter/material.dart';
import 'package:hex/hex.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/locale_provider.dart';
import '../core/theme.dart';
import '../models/chain_config.dart';
import '../models/wallet_info.dart';
import '../providers/wallet_provider.dart';
import 'bug_reporter.dart';
import 'db_service.dart';
import 'wallet_service.dart';

/// ผลการจับคู่ "ที่อยู่ที่แอปต้นทางขอให้เซ็น" กับกระเป๋าในแอป
enum SignerMatchKind {
  /// คำขอไม่ได้ระบุที่อยู่ (TPIX TRADE รุ่นเก่า) → ใช้ใบที่เปิดอยู่ + โชว์ที่อยู่เด่นๆ
  noAddress,

  /// ตรงกับใบที่เปิดอยู่
  active,

  /// ตรงกับอีกใบในแอป → ต้องถามผู้ใช้ก่อนสลับ
  otherWallet,

  /// ไม่ตรงกับใบไหนในแอปเลย → ปฏิเสธ
  notFound,
}

class SignerMatch {
  final SignerMatchKind kind;
  final WalletInfo? wallet; // มีค่าเมื่อ kind == otherWallet
  const SignerMatch(this.kind, {this.wallet});
}

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

    // กระเป๋าที่จะเซ็นต้องเป็นใบที่ TRADE ผูกไว้ (ถ้า TRADE ระบุ address มา)
    final signer = await _resolveSigner(
      context,
      cbUri: cbUri,
      nonce: nonce,
      requested: requestedAddress(uri.queryParameters),
      sourceName: sourceName,
      logMessage: message,
    );
    if (signer == null || !context.mounted) return true;

    final approved = await _showConfirmDialog(
      context,
      sourceName: sourceName,
      message: message,
      signerAddress: signer.address,
      signerName: signer.name,
      addressVerified: signer.verified,
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

    // กระเป๋าถูกสลับระหว่างหน้ายืนยันเปิดอยู่ → ห้ามเซ็นด้วยใบที่ผู้ใช้ไม่ได้เห็น
    if (!_stillSameSigner(wallet, signer.address)) {
      await _sendCallback(cbUri, nonce: nonce, error: 'wallet_changed');
      await _logSign(
        wallet: wallet,
        sourceApp: sourceAppName,
        sourceScheme: cbUri.scheme,
        message: message,
        status: 'wallet_changed',
        nonce: nonce,
      );
      return true;
    }

    // Sign + send back
    try {
      final signature = await wallet.signPersonalMessage(message);
      await _sendCallback(cbUri, nonce: nonce, signature: signature, address: signer.address);
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

    final signer = await _resolveSigner(
      context,
      cbUri: cbUri,
      nonce: nonce,
      requested: requestedAddress(uri.queryParameters),
      sourceName: sourceName,
      logMessage: typedJson,
    );
    if (signer == null || !context.mounted) return true;

    final approved = await _showTypedConfirmDialog(
      context,
      sourceName: sourceName,
      typedData: typedData,
      signerAddress: signer.address,
      signerName: signer.name,
      addressVerified: signer.verified,
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

    if (!_stillSameSigner(wallet, signer.address)) {
      await _sendCallback(cbUri, nonce: nonce, error: 'wallet_changed');
      await _logSign(
        wallet: wallet,
        sourceApp: sourceName,
        sourceScheme: cbUri.scheme,
        message: typedJson,
        status: 'wallet_changed',
        nonce: nonce,
      );
      return true;
    }

    try {
      // Simplified EIP-712: sign JSON as personal_sign
      // (matches WalletConnectService approach — full struct hashing TBD)
      final signature = await wallet.signPersonalMessage(typedJson);
      await _sendCallback(cbUri, nonce: nonce, signature: signature, address: signer.address);
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
    final logMessage = jsonEncode({
      'type': 'sign-tx',
      'chainId': chainId,
      'to': to,
      'value': value.toString(),
      'dataBytes': data?.length ?? 0,
      if (summary != null) 'summary': summary,
    });

    // ธุรกรรม = เงินออกจริง → ต้องออกจากกระเป๋าใบที่ TRADE ผูกไว้เท่านั้น
    final signer = await _resolveSigner(
      context,
      cbUri: cbUri,
      nonce: nonce,
      requested: requestedAddress(uri.queryParameters, tx: tx),
      sourceName: sourceName,
      logMessage: logMessage,
    );
    if (signer == null || !context.mounted) return true;

    final approved = await _showConfirmDialog(
      context,
      sourceName: sourceName,
      message: lines.join('\n'),
      signerAddress: signer.address,
      signerName: signer.name,
      addressVerified: signer.verified,
    );

    if (!context.mounted) return true;

    final wallet = context.read<WalletProvider>();

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

    if (!_stillSameSigner(wallet, signer.address)) {
      await _sendCallback(cbUri, nonce: nonce, error: 'wallet_changed');
      await _logSign(
        wallet: wallet,
        sourceApp: sourceName,
        sourceScheme: cbUri.scheme,
        message: logMessage,
        status: 'wallet_changed',
        nonce: nonce,
      );
      return true;
    }

    // ── เซ็น + broadcast (gas ประเมินจากโหนด + เผื่อ 20% — path เดียวกับหน้า swap
    //    ของกระเป๋าเอง; RPC หลักใช้ไม่ได้ก็สลับไปตัวสำรองของเชนนั้น) ──
    // expectedFrom: ถ้ากระเป๋าถูกสลับระหว่างนี้ WalletService ยกเลิกเอง
    try {
      final txHash = await wallet.sendEvmTransaction(
        rpcUrl: chain.rpcUrl,
        chainId: chainId,
        toAddress: to,
        value: value > BigInt.zero ? value : null,
        data: data,
        expectedFrom: signer.address,
      );
      await _sendCallback(cbUri, nonce: nonce, txHash: txHash, address: signer.address);
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
      final code = e is WalletChangedException ? 'wallet_changed' : 'tx_failed';
      await _sendCallback(cbUri, nonce: nonce, error: code);
      await _logSign(
        wallet: wallet,
        sourceApp: sourceName,
        sourceScheme: cbUri.scheme,
        message: logMessage,
        status: code,
        nonce: nonce,
      );
    }
    return true;
  }

  // ================================================================
  // กระเป๋าที่ต้องใช้เซ็น — ต้องเป็นใบที่ TPIX TRADE ผูกไว้
  // ================================================================
  //
  // ★ ของเดิมเซ็นด้วย "กระเป๋าที่เปิดอยู่" เสมอ ถ้าผู้ใช้สลับไปอีกใบหลังเชื่อมกับ TRADE
  //   ลายเซ็น/ธุรกรรมจะออกจากกระเป๋าผิดใบ (sign-tx = เงินออกผิดกระเป๋าจริง)
  //
  // โปรโตคอล (ตกลงกับฝั่ง TPIX TRADE แล้ว): ส่งที่อยู่ที่ผูกไว้มาเป็นพารามิเตอร์ `address=0x…`
  //   ทั้ง sign / sign-typed / sign-tx — เทียบแบบไม่สนตัวพิมพ์
  //   sign-tx: `from` ใน JSON ของ tx ต้องตรงกับ `address` ด้วย (ถ้ามีทั้งคู่)
  //   พารามิเตอร์ `from` ของ URL คือชื่อแอปต้นทาง (`from=trade`) — ไม่ใช้เป็นที่อยู่เด็ดขาด
  // ไม่มีที่อยู่มา (TRADE รุ่นเก่า) → ยังเซ็นได้ แต่หน้ายืนยันโชว์กระเป๋าที่จะเซ็นชัดๆ

  /// ดึงที่อยู่ที่คำขอระบุมา — คืน `invalid: true` ถ้ารูปแบบผิดหรือระบุมาหลายที่แล้วไม่ตรงกัน
  @visibleForTesting
  static ({String? address, bool invalid}) requestedAddress(
    Map<String, String> query, {
    Map<String, dynamic>? tx,
  }) {
    final candidates = <String>[];
    final explicit = query['address'];
    if (explicit != null) {
      // ส่งมาแต่ว่างเปล่า = รูปแบบผิด (ไม่ใช่ "ไม่ได้ระบุ") → ปฏิเสธ
      if (explicit.trim().isEmpty) return (address: null, invalid: true);
      candidates.add(explicit.trim());
    }
    // ★ ไม่อ่าน `from` ของ URL — นั่นคือชื่อแอปต้นทาง (from=trade) ไม่ใช่ที่อยู่
    final txFrom = tx?['from'];
    if (txFrom != null) {
      if (txFrom is! String) return (address: null, invalid: true);
      if (txFrom.isNotEmpty) candidates.add(txFrom.trim());
    }
    if (candidates.isEmpty) return (address: null, invalid: false);
    for (final c in candidates) {
      if (!WalletService.isValidAddress(c)) return (address: null, invalid: true);
    }
    final first = candidates.first.toLowerCase();
    if (candidates.any((c) => c.toLowerCase() != first)) {
      return (address: null, invalid: true); // ระบุมาหลายที่แต่ไม่ตรงกัน = ไม่เชื่อ
    }
    return (address: candidates.first, invalid: false);
  }

  /// จับคู่ที่อยู่ที่คำขอระบุ กับกระเป๋าในแอป (pure — เทสต์ได้)
  @visibleForTesting
  static SignerMatch matchSigner({
    required String? requested,
    required String? activeAddress,
    required List<WalletInfo> wallets,
  }) {
    if (requested == null) return const SignerMatch(SignerMatchKind.noAddress);
    final want = requested.toLowerCase();
    if (activeAddress != null && activeAddress.toLowerCase() == want) {
      return const SignerMatch(SignerMatchKind.active);
    }
    for (final w in wallets) {
      if (w.address.toLowerCase() == want) {
        return SignerMatch(SignerMatchKind.otherWallet, wallet: w);
      }
    }
    return const SignerMatch(SignerMatchKind.notFound);
  }

  /// ตัดสินว่าจะเซ็นด้วยกระเป๋าใบไหน — คืน null = ตอบปฏิเสธกลับไปแล้ว (ผู้เรียกจบได้เลย)
  ///
  /// - ระบุมาแล้วตรงกับใบที่เปิดอยู่ → ไปต่อ
  /// - ตรงกับอีกใบในแอป → ถามผู้ใช้ว่าจะสลับไปใบนั้นไหม (ไม่สลับเองเงียบๆ)
  /// - ไม่ตรงกับใบไหนเลย / รูปแบบผิด → ปฏิเสธพร้อมรหัส error ชัดเจน
  /// - ไม่ได้ระบุ (TRADE รุ่นเก่า) → ไปต่อด้วยใบที่เปิดอยู่ (หน้ายืนยันโชว์ที่อยู่เด่นๆ)
  Future<({String address, String? name, bool verified})?> _resolveSigner(
    BuildContext context, {
    required Uri cbUri,
    required String nonce,
    required ({String? address, bool invalid}) requested,
    required String sourceName,
    required String logMessage,
  }) async {
    final wallet = context.read<WalletProvider>();
    final isThai = context.read<LocaleProvider>().isThai;

    // ล็อกอยู่ = ยังไม่รู้รายชื่อกระเป๋า → ปล่อยให้ขั้นถัดไปตอบ wallet_locked ตามเดิม
    if (!wallet.isUnlocked || wallet.address == null) {
      return (address: wallet.address ?? '', name: null, verified: false);
    }

    Future<void> reject(String code) async {
      await _sendCallback(cbUri, nonce: nonce, error: code);
      await _logSign(
        wallet: wallet,
        sourceApp: sourceName,
        sourceScheme: cbUri.scheme,
        message: logMessage,
        status: code,
        nonce: nonce,
      );
    }

    if (requested.invalid) {
      await reject('invalid_address');
      return null;
    }

    final match = matchSigner(
      requested: requested.address,
      activeAddress: wallet.address,
      wallets: wallet.wallets,
    );

    switch (match.kind) {
      case SignerMatchKind.noAddress:
        return (address: wallet.address!, name: wallet.activeWallet?.name, verified: false);
      case SignerMatchKind.active:
        return (address: wallet.address!, name: wallet.activeWallet?.name, verified: true);
      case SignerMatchKind.notFound:
        if (context.mounted) {
          await _showInfoSheet(
            context,
            icon: Icons.person_off_rounded,
            title: isThai ? 'ไม่พบกระเป๋าที่ $sourceName เชื่อมไว้' : 'Linked wallet not found',
            body: isThai
                ? '$sourceName ขอให้เซ็นด้วยกระเป๋า\n${requested.address}\nแต่กระเป๋านี้ไม่ได้อยู่ในแอป TPIX Wallet เครื่องนี้ — ปฏิเสธคำขอแล้ว\n\nเชื่อม $sourceName ใหม่จากกระเป๋าที่ต้องการใช้'
                : '$sourceName asked to sign with\n${requested.address}\nbut that wallet is not in this TPIX Wallet app — the request was rejected.\n\nReconnect $sourceName from the wallet you want to use.',
          );
        }
        await reject('address_not_found');
        return null;
      case SignerMatchKind.otherWallet:
        final target = match.wallet!;
        if (!context.mounted) return null;
        final ok = await _askSwitchWallet(context, target: target, sourceName: sourceName, isThai: isThai);
        if (!context.mounted) return null;
        if (!ok) {
          await reject('user_rejected');
          return null;
        }
        await wallet.switchWallet(target.slot);
        if (wallet.address?.toLowerCase() != target.address.toLowerCase()) {
          await reject('switch_failed');
          return null;
        }
        return (address: wallet.address!, name: wallet.activeWallet?.name, verified: true);
    }
  }

  /// ถามผู้ใช้ก่อนสลับกระเป๋า — โชว์ชื่อ + ที่อยู่เต็มของใบปลายทาง
  Future<bool> _askSwitchWallet(
    BuildContext context, {
    required WalletInfo target,
    required String sourceName,
    required bool isThai,
  }) async {
    final c = AppColors.of(context);
    final result = await showModalBottomSheet<bool>(
      context: context,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(TpixRadius.lg)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.swap_horiz_rounded, color: AppTheme.warm),
                const SizedBox(width: TpixGap.md),
                Expanded(
                  child: Text(
                    isThai ? 'สลับกระเป๋าเพื่อเซ็น?' : 'Switch wallet to sign?',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.text),
                  ),
                ),
              ],
            ),
            const SizedBox(height: TpixGap.md),
            Text(
              isThai
                  ? '$sourceName เชื่อมไว้กับกระเป๋าใบนี้ ซึ่งไม่ใช่ใบที่เปิดอยู่ตอนนี้:'
                  : '$sourceName is linked to this wallet, which is not the one currently open:',
              style: TextStyle(fontSize: 13, color: c.textSec),
            ),
            const SizedBox(height: TpixGap.md),
            _addressBox(c, name: target.name, address: target.address),
            const SizedBox(height: TpixGap.xl),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(sheetCtx, false),
                    child: Text(isThai ? 'ปฏิเสธ' : 'Reject', style: TextStyle(color: c.textSec)),
                  ),
                ),
                const SizedBox(width: TpixGap.md),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(sheetCtx, true),
                    style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accent),
                    child: Text(
                      isThai ? 'สลับไปใบนี้' : 'Switch',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    return result == true;
  }

  Future<void> _showInfoSheet(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String body,
  }) async {
    final c = AppColors.of(context);
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(TpixRadius.lg)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, color: AppTheme.danger),
                const SizedBox(width: TpixGap.md),
                Expanded(
                  child: Text(title,
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.text)),
                ),
              ],
            ),
            const SizedBox(height: TpixGap.md),
            SelectableText(body, style: TextStyle(fontSize: 13, height: 1.5, color: c.textSec)),
            const SizedBox(height: TpixGap.xl),
            ElevatedButton(
              onPressed: () => Navigator.pop(sheetCtx),
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
              child: const Text('OK', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _addressBox(AppColors c, {String? name, required String address}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(TpixRadius.sm),
        border: Border.all(color: AppTheme.accent.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (name != null && name.isNotEmpty)
            Text(name, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.text)),
          SelectableText(
            address,
            style: TextStyle(fontSize: 12, fontFamily: 'monospace', color: c.textSec),
          ),
        ],
      ),
    );
  }

  /// ก่อนเซ็นจริง: กระเป๋าที่เปิดอยู่ต้องยังเป็นใบที่ผู้ใช้เห็นในหน้ายืนยัน
  /// (ระหว่างหน้ายืนยันเปิดอยู่ ผู้ใช้อาจสลับกระเป๋าจากที่อื่น)
  static bool _stillSameSigner(WalletProvider wallet, String shownAddress) =>
      wallet.address != null &&
      wallet.address!.toLowerCase() == shownAddress.toLowerCase();

  /// Pretty-print EIP-712 typed-data for the confirmation dialog
  Future<bool> _showTypedConfirmDialog(
    BuildContext context, {
    required String sourceName,
    required Map<String, dynamic> typedData,
    required String signerAddress,
    String? signerName,
    bool addressVerified = false,
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
        signerAddress: signerAddress,
        signerName: signerName,
        addressVerified: addressVerified,
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
  ///
  /// สำเร็จ → แนบ `address` = กระเป๋าที่เซ็นจริง ให้ TRADE ตรวจซ้ำได้ว่าตรงกับที่ผูกไว้
  Future<void> _sendCallback(
    Uri callback, {
    required String nonce,
    String? signature,
    String? txHash,
    String? error,
    String? address,
  }) async {
    final params = <String, String>{
      'nonce': nonce,
      if (signature != null) 'signature': signature,
      if (txHash != null) 'txhash': txHash,
      if (error != null) 'error': error,
      if (address != null && error == null) 'address': address,
    };
    // Reuse callback's host (e.g., 'sign-result') and append our params
    final outUri = callback.replace(queryParameters: {
      ...callback.queryParameters,
      ...params,
    });
    final outcome = signature != null ? 'signature' : (txHash != null ? 'txhash' : 'error=$error');
    BugReporter.I.breadcrumb('peer callback → ${callback.scheme}://${callback.host} $outcome');
    try {
      final opened = await launchUrl(outUri, mode: LaunchMode.externalApplication);
      if (!opened) {
        BugReporter.I.report(
          title: 'ส่งผลกลับ ${callback.scheme} ไม่ได้ (launchUrl=false)',
          description: 'เซ็น/ปฏิเสธเสร็จแล้วแต่เปิดแอปปลายทางไม่ได้ ผลลัพธ์: $outcome',
        );
      }
    } catch (e) {
      debugPrint('PeerSignService.sendCallback: ${e.runtimeType}');
      BugReporter.I.report(
        title: 'ส่งผลกลับ ${callback.scheme} ล้มเหลว: ${e.runtimeType}',
        description: 'launchUrl โยน ${e.runtimeType} ผลลัพธ์: $outcome',
      );
    }
  }

  /// Bottom sheet asking user to confirm/reject the signature
  Future<bool> _showConfirmDialog(
    BuildContext context, {
    required String sourceName,
    required String message,
    required String signerAddress,
    String? signerName,
    bool addressVerified = false,
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
        signerAddress: signerAddress,
        signerName: signerName,
        addressVerified: addressVerified,
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

  /// กระเป๋าที่จะใช้เซ็น — โชว์เด่นๆ ทุกครั้ง
  final String signerAddress;
  final String? signerName;

  /// TRADE ระบุที่อยู่มาและตรงกับใบนี้ (false = TRADE รุ่นเก่าไม่ได้ระบุ → เตือนให้ตรวจเอง)
  final bool addressVerified;

  const _SignConfirmSheet({
    required this.sourceName,
    required this.message,
    required this.preview,
    required this.isThai,
    required this.bgColor,
    required this.textColor,
    required this.textSecondary,
    required this.signerAddress,
    this.signerName,
    this.addressVerified = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.8,
      ),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(TpixRadius.lg)),
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
          const SizedBox(height: TpixGap.xl),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(TpixRadius.sm),
                ),
                child: const Icon(Icons.draw_rounded,
                    color: AppTheme.accent, size: 20),
              ),
              const SizedBox(width: TpixGap.md),
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
          const SizedBox(height: TpixGap.md),
          Text(
            isThai
                ? 'ตรวจข้อความก่อนเซ็น — อย่าเซ็นถ้าไม่แน่ใจ'
                : 'Review the message before signing — do not sign if unsure',
            style: TextStyle(fontSize: 12, color: textSecondary),
          ),
          const SizedBox(height: TpixGap.md),
          // ── กระเป๋าที่จะเซ็น (ที่อยู่เต็ม ไม่ย่อ) ──
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: (addressVerified ? AppTheme.success : AppTheme.warm)
                  .withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(TpixRadius.sm),
              border: Border.all(
                color: (addressVerified ? AppTheme.success : AppTheme.warm)
                    .withValues(alpha: 0.35),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      addressVerified
                          ? Icons.verified_user_rounded
                          : Icons.account_balance_wallet_rounded,
                      size: 16,
                      color: addressVerified ? AppTheme.success : AppTheme.warm,
                    ),
                    const SizedBox(width: TpixGap.sm),
                    Expanded(
                      child: Text(
                        isThai
                            ? 'เซ็นด้วยกระเป๋า${signerName != null && signerName!.isNotEmpty ? ' "$signerName"' : ''}'
                            : 'Signing with wallet${signerName != null && signerName!.isNotEmpty ? ' "$signerName"' : ''}',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: textColor),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: TpixGap.xs),
                SelectableText(
                  signerAddress,
                  style: TextStyle(
                      fontSize: 13, fontFamily: 'monospace', color: textColor),
                ),
                if (!addressVerified) ...[
                  const SizedBox(height: TpixGap.xs),
                  Text(
                    isThai
                        ? '$sourceName ไม่ได้ระบุกระเป๋ามา — ตรวจให้แน่ใจว่าตรงกับกระเป๋าที่เชื่อมไว้'
                        : '$sourceName did not say which wallet — make sure this is the linked one',
                    style: const TextStyle(fontSize: 11, color: AppTheme.warm),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: TpixGap.lg),
          Flexible(
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: textSecondary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(TpixRadius.sm),
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
          const SizedBox(height: TpixGap.xl),
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(TpixRadius.sm),
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
              const SizedBox(width: TpixGap.md),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accent,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(TpixRadius.sm),
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
