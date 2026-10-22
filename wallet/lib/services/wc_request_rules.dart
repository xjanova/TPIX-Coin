/// TPIX Wallet — กติกาของคำขอ WalletConnect (pure — ไม่แตะ SDK / กุญแจ / UI)
///
/// - อ่าน params ของ personal_sign / eth_sign (ทั้ง [ข้อความ, ที่อยู่] และแบบสลับ)
///   ข้อความ 0x-hex = ไบต์ดิบ — ห้ามถอด UTF-8 แล้วเข้ารหัสกลับ (ไบต์ที่ไม่ใช่ UTF-8 จะเพี้ยน ลายเซ็นผิด)
/// - คำขอที่ตอบเองได้โดยไม่ต้องถามผู้ใช้: เปลี่ยน/เพิ่มเชน, เมธอดที่ไม่รองรับ, params เสีย,
///   และเว็บขอให้ "กระเป๋าอื่น" เซ็น (wallet_changed — ห้ามเซ็นด้วยใบที่เปิดอยู่แทน)
/// - ที่มาของเว็บจาก WalletConnect Verify (กันเว็บปลอม)
///
/// Developed by Xman Studio
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:reown_walletkit/reown_walletkit.dart' show Validation, VerifyContext;
import 'package:web3dart/crypto.dart' show bytesToHex, hexToBytes;

import '../models/chain_config.dart';
import '../utils/units.dart';

final _addressShape = RegExp(r'^0x[0-9a-fA-F]{40}$');
final _hexBytes = RegExp(r'^0x(?:[0-9a-fA-F]{2})*$');

/// 0x1234…abcd — โชว์ที่อยู่แบบสั้นในข้อความเตือน
String wcShortAddress(String address) =>
    address.length <= 12 ? address : '${address.substring(0, 6)}…${address.substring(address.length - 4)}';

// ================================================================
//  personal_sign / eth_sign
// ================================================================

class WcSignParams {
  /// ไบต์ที่จะเซ็นจริง (prefix ของ EIP-191 ใส่ตอนเซ็น)
  final Uint8List message;

  /// ที่อยู่ที่เว็บขอให้เซ็น — null = ไม่ได้ระบุ
  final String? address;

  const WcSignParams(this.message, this.address);

  /// ethers v6 ส่ง [0x<UTF-8 hex>, <ที่อยู่ตัวเล็ก>] · บางเว็บส่ง [ที่อยู่, ข้อความ] (ลำดับของ eth_sign)
  /// null = อ่านไม่ออก (ไม่ใช่ list ของ string / ตัวที่เป็นที่อยู่ผิดรูป) → ตอบ invalid params
  static WcSignParams? parse(String method, dynamic params) {
    if (params is! List || params.isEmpty) return null;
    final first = params[0];
    if (first is! String) return null;
    if (params.length == 1) return WcSignParams(messageBytes(first), null);

    final second = params[1];
    if (second is! String) return null;
    final firstIsAddress = _addressShape.hasMatch(first);
    final secondIsAddress = _addressShape.hasMatch(second);
    final bool messageFirst;
    if (secondIsAddress && !firstIsAddress) {
      messageFirst = true;
    } else if (firstIsAddress && !secondIsAddress) {
      messageFirst = false; // สลับลำดับมา
    } else if (firstIsAddress && secondIsAddress) {
      // ข้อความหน้าตาเหมือนที่อยู่ (เช่น เซ็นที่อยู่) → ยึดลำดับมาตรฐานของเมธอด
      messageFirst = method != 'eth_sign';
    } else {
      return null; // ไม่มีตัวไหนเป็นที่อยู่เลย
    }
    return WcSignParams(messageBytes(messageFirst ? first : second), messageFirst ? second : first);
  }

  /// ข้อความ 0x-hex (ความยาวคู่) = ไบต์ดิบ · อย่างอื่น = ไบต์ UTF-8 ของตัวอักษรตามที่เห็น
  static Uint8List messageBytes(String message) {
    if (_hexBytes.hasMatch(message)) return Uint8List.fromList(hexToBytes(message.substring(2)));
    return Uint8List.fromList(utf8.encode(message));
  }

  /// ข้อความไว้โชว์ผู้ใช้ — ถอด UTF-8 ได้ครบและไม่มีตัวควบคุมแปลก ๆ = ข้อความ, ไม่งั้นโชว์ hex ตามจริง
  String get displayText {
    try {
      final text = utf8.decode(message);
      final hasControl = text.runes.any((r) => (r < 0x20 && r != 0x09 && r != 0x0a && r != 0x0d) || r == 0x7f);
      return hasControl ? bytesToHex(message, include0x: true) : text;
    } on FormatException {
      return bytesToHex(message, include0x: true);
    }
  }
}

// ================================================================
//  ที่อยู่ที่เว็บขอ vs กระเป๋าที่เปิดอยู่
// ================================================================

class WcRequestRules {
  WcRequestRules._();

  /// เมธอดที่ให้ผู้ใช้กดยืนยันได้จริง (ที่เหลือที่ลงทะเบียนไว้ตอบปฏิเสธเอง)
  static const userMethods = {
    'personal_sign',
    'eth_sign',
    'eth_sendTransaction',
    'eth_signTypedData',
    'eth_signTypedData_v4',
  };

  /// EIP-1193: provider disconnected from the requested account — เว็บเช็กคำว่า wallet_changed
  static const walletChangedCode = 4100;

  /// ไม่ใส่ที่อยู่ของกระเป๋าที่เปิดอยู่ลงไป — ห้ามเผยกระเป๋าใบอื่นของผู้ใช้ให้เว็บรู้
  static const walletChangedMessage = 'wallet_changed: the active wallet is not the requested account';

  static const unrecognizedChainCode = 4902;

  /// ที่อยู่ที่เว็บระบุในคำขอ — address null = ไม่ได้ระบุ, invalid = ระบุมาแต่ผิดรูป/อ่านไม่ออก
  static ({String? address, bool invalid}) requestedAddress(String method, dynamic params) {
    switch (method) {
      case 'personal_sign':
      case 'eth_sign':
        final parsed = WcSignParams.parse(method, params);
        return parsed == null ? (address: null, invalid: true) : (address: parsed.address, invalid: false);
      case 'eth_sendTransaction':
        if (params is! List || params.isEmpty || params[0] is! Map) return (address: null, invalid: true);
        final from = (params[0] as Map)['from'];
        if (from == null) return (address: null, invalid: false);
        if (from is! String || !_addressShape.hasMatch(from)) return (address: null, invalid: true);
        return (address: from, invalid: false);
      case 'eth_signTypedData':
      case 'eth_signTypedData_v4':
        // มาตรฐาน [ที่อยู่, typedData] — เว็บรุ่นเก่าบางตัวสลับ
        if (params is! List) return (address: null, invalid: false);
        for (final p in params.take(2)) {
          if (p is String && _addressShape.hasMatch(p)) return (address: p, invalid: false);
        }
        return (address: null, invalid: false);
      default:
        return (address: null, invalid: false);
    }
  }

  /// เว็บขอให้กระเป๋าอื่นเซ็น → คืนที่อยู่ที่เว็บรอ (ไม่สนตัวพิมพ์) · null = ผ่าน / เว็บไม่ได้ระบุ
  static String? walletChangedExpected({required String? requested, required String? active}) {
    if (requested == null) return null;
    if (active == null || requested.toLowerCase() != active.toLowerCase()) return requested;
    return null;
  }

  /// ตัดสินคำขอที่เพิ่งเข้ามา: ตอบเอง หรือเข้าคิวให้ผู้ใช้ยืนยัน
  static WcIntake decideIntake({
    required String method,
    required dynamic params,
    required Set<int> supportedChainIds,
    required String? activeAddress,
  }) {
    final chainAnswer = chainAutoAnswer(method, params, supportedChainIds);
    if (chainAnswer != null) return chainAnswer;
    if (!userMethods.contains(method)) {
      return const WcAutoReject(code: 4200, message: 'Unsupported method');
    }
    final requested = requestedAddress(method, params);
    if (requested.invalid) return const WcAutoReject(code: -32602, message: 'Invalid params');
    final expected = walletChangedExpected(requested: requested.address, active: activeAddress);
    if (expected != null) {
      return WcAutoReject(code: walletChangedCode, message: walletChangedMessage, walletExpected: expected);
    }
    return const WcAskUser();
  }

  /// wallet_switchEthereumChain / wallet_addEthereumChain — ตอบเองไม่ต้องมีการ์ดยืนยัน
  /// null = เมธอดอื่น
  static WcIntake? chainAutoAnswer(String method, dynamic params, Set<int> supportedChainIds) {
    final isSwitch = method == 'wallet_switchEthereumChain';
    if (!isSwitch && method != 'wallet_addEthereumChain') return null;
    final raw = params is List && params.isNotEmpty && params[0] is Map ? (params[0] as Map)['chainId'] : null;
    final chainId = parseChainId(raw);
    if (chainId == null) return const WcAutoReject(code: -32602, message: 'Invalid params');
    if (!supportedChainIds.contains(chainId)) {
      return WcAutoReject(
        code: unrecognizedChainCode,
        message: 'Unrecognized chain ID "0x${chainId.toRadixString(16)}"',
      );
    }
    // เพิ่มเชนที่มีอยู่แล้ว = สำเร็จเฉย ๆ · สลับเชน = สำเร็จ + แจ้ง chainChanged
    return WcAutoOk(chainChanged: isSwitch ? chainId : null);
  }

  /// chainId ของ EIP-3326/3085 เป็น 0x-hex — รับเลขฐานสิบด้วยเผื่อเว็บส่งผิดสเปก
  static int? parseChainId(dynamic raw) {
    int? id;
    if (raw is int) {
      id = raw;
    } else if (raw is String) {
      final s = raw.trim();
      id = s.toLowerCase().startsWith('0x') ? int.tryParse(s.substring(2), radix: 16) : int.tryParse(s);
    }
    return id != null && id > 0 ? id : null;
  }
}

/// ผลการตัดสินคำขอที่เข้ามา
sealed class WcIntake {
  const WcIntake();
}

/// ตอบสำเร็จเอง (result = null) — [chainChanged] = เชนที่ต้องแจ้งเว็บว่าสลับแล้ว
final class WcAutoOk extends WcIntake {
  final int? chainChanged;
  const WcAutoOk({this.chainChanged});
}

/// ปฏิเสธเอง — [walletExpected] != null = เว็บรอกระเป๋าใบนั้น (ต้องบอกผู้ใช้ในแอปด้วย)
final class WcAutoReject extends WcIntake {
  final int code;
  final String message;
  final String? walletExpected;
  const WcAutoReject({required this.code, required this.message, this.walletExpected});
}

/// เข้าคิวให้ผู้ใช้ตรวจแล้วกดยืนยัน/ปฏิเสธ
final class WcAskUser extends WcIntake {
  const WcAskUser();
}

// ================================================================
//  ที่มาของเว็บ (WalletConnect Verify)
// ================================================================

enum WcOriginLevel {
  /// Verify ยืนยันโดเมนแล้ว และตรงกับที่เว็บอ้าง
  verified,

  /// ตรวจไม่ได้ (เว็บไม่ได้ลงทะเบียน Verify / เน็ตล่ม) — โน้ตกลาง ๆ
  unknown,

  /// ที่มาจริงไม่ตรงกับโดเมนที่เว็บอ้าง
  mismatch,

  /// Verify บอกว่าไม่ผ่าน
  invalid,

  /// Verify บอกว่าเป็นเว็บหลอกลวง — ปุ่มหลักต้องเป็น "ปฏิเสธ"
  scam,
}

class WcOrigin {
  final WcOriginLevel level;

  /// โดเมนที่คำขอมาจากจริง (ตาม Verify) — ว่าง = อ่านไม่ได้
  final String host;

  /// โดเมนที่เว็บอ้างใน metadata
  final String claimedHost;

  const WcOrigin(this.level, {required this.host, required this.claimedHost});

  bool get isDanger =>
      level == WcOriginLevel.mismatch || level == WcOriginLevel.invalid || level == WcOriginLevel.scam;

  /// โดเมนที่ควรโชว์บนการ์ด (ที่มาจริงก่อน — ไม่มีค่อยใช้ที่เว็บอ้าง)
  String get displayHost => host.isNotEmpty ? host : claimedHost;

  static WcOrigin check(VerifyContext? context, String metadataUrl) {
    final claimed = _hostOf(metadataUrl);
    final origin = _hostOf(context?.origin);
    WcOrigin of(WcOriginLevel level) => WcOrigin(level, host: origin, claimedHost: claimed);

    if (context?.validation == Validation.SCAM || context?.isScam == true) return of(WcOriginLevel.scam);
    if (context?.validation == Validation.INVALID) return of(WcOriginLevel.invalid);
    // เว็บไม่บอกที่อยู่ของตัวเอง (หรืออ่านไม่ได้) = ไม่รู้ว่าเป็นเว็บไหน ถือว่าไม่ผ่าน
    if (claimed.isEmpty) return of(WcOriginLevel.invalid);
    // อ้างโดเมนหนึ่งแต่มาจากอีกโดเมน = น่าสงสัยเสมอ ต่อให้ Verify ไม่ได้ฟันธง
    if (origin.isNotEmpty && origin != claimed) return of(WcOriginLevel.mismatch);
    if (context?.validation == Validation.VALID && origin.isNotEmpty) return of(WcOriginLevel.verified);
    return of(WcOriginLevel.unknown);
  }

  /// "https://tpix.online/x" → "tpix.online" · ไม่มี scheme (link mode ส่งมาแบบนี้) ก็อ่านได้
  static String _hostOf(String? raw) {
    final s = (raw ?? '').trim();
    if (s.isEmpty) return '';
    var uri = Uri.tryParse(s);
    if (uri != null && uri.host.isEmpty && !s.contains('://')) uri = Uri.tryParse('https://$s');
    return (uri?.host ?? '').toLowerCase();
  }
}

// ================================================================
//  สิ่งที่โชว์บนการ์ดคำขอ
// ================================================================

enum WcRequestKind { signMessage, sendTransaction, signTypedData, other }

class WcRequestView {
  final WcRequestKind kind;
  final String method;

  /// ข้อความที่จะเซ็น / typed data / params ดิบ (สำหรับ sendTransaction ใช้ [to] + [value] แทน)
  final String body;
  final String? to;

  /// มูลค่าเป็นหน่วยเหรียญหลักของเชน (เช่น "0.5 BNB") — null = อ่านไม่ออก
  final String? value;

  /// ชื่อเชนของคำขอ — null = เชนที่แอปไม่รู้จัก
  final String? chainName;

  const WcRequestView({
    required this.kind,
    required this.method,
    required this.body,
    this.to,
    this.value,
    this.chainName,
  });

  static WcRequestView build({required String method, required dynamic params, required String chainId}) {
    final id = int.tryParse(chainId.split(':').last);
    final chain = id == null ? null : _chainOrNull(id);
    switch (method) {
      case 'personal_sign':
      case 'eth_sign':
        final parsed = WcSignParams.parse(method, params);
        return WcRequestView(
          kind: WcRequestKind.signMessage,
          method: method,
          body: parsed?.displayText ?? '',
          chainName: chain?.name,
        );
      case 'eth_sendTransaction':
        final tx = params is List && params.isNotEmpty && params[0] is Map ? params[0] as Map : const {};
        final wei = _quantity(tx['value'] ?? '0x0');
        return WcRequestView(
          kind: WcRequestKind.sendTransaction,
          method: method,
          body: '',
          to: tx['to']?.toString(),
          value: wei == null ? null : '${Units.format(wei, chain?.decimals ?? 18)} ${chain?.symbol ?? ''}'.trim(),
          chainName: chain?.name,
        );
      case 'eth_signTypedData':
      case 'eth_signTypedData_v4':
        final data = params is List && params.length > 1 ? params[1] : params;
        return WcRequestView(
          kind: WcRequestKind.signTypedData,
          method: method,
          body: data is String ? data : jsonEncode(data),
          chainName: chain?.name,
        );
      default:
        return WcRequestView(kind: WcRequestKind.other, method: method, body: jsonEncode(params), chainName: chain?.name);
    }
  }

  static ChainConfig? _chainOrNull(int id) {
    for (final c in ChainConfig.all) {
      if (c.chainId == id) return c;
    }
    return null;
  }

  static BigInt? _quantity(dynamic raw) {
    if (raw is int) return BigInt.from(raw);
    if (raw is! String) return null;
    final s = raw.trim().toLowerCase();
    if (s.startsWith('0x')) return s.length == 2 ? BigInt.zero : BigInt.tryParse(s.substring(2), radix: 16);
    return BigInt.tryParse(s);
  }
}
