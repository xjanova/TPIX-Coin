/// TPIX Wallet — อ่านคำขอชำระเงินแบบ EIP-681 (`ethereum:` URI) จาก QR / ลิงก์
///
/// ร้าน (Thaiprompt, XMAN Studio) ออกใบเสนอราคาเป็น TPIX ที่ "ยอดเป๊ะทุก wei" —
/// ทศนิยม 8 ตำแหน่งท้ายคือรหัสจับคู่การชำระ ยอดคลาดแม้ 1 wei ร้านก็ไม่รับ
/// ร้านโชว์ QR / ลิงก์แบบ `ethereum:<0xที่อยู่>@4289?value=<wei>`
///
/// รูปที่รองรับ
///   - โอนเหรียญหลัก: `ethereum:[pay-]<0xที่อยู่>[@chainId][?value=<wei>][&amount=<ทศนิยม>]`
///   - โอนโทเค็น ERC-20: `ethereum:[pay-]<0xโทเค็น>[@chainId]/transfer?address=<0xผู้รับ>&uint256=<หน่วยย่อย>`
///
/// ★ ห้ามผ่าน double เด็ดขาด — `value` เขียนแบบวิทยาศาสตร์ได้ (เช่น 1.5e18)
///   แปลงด้วย BigInt ล้วน ผลต้องเป็นจำนวนเต็มพอดี ไม่ปัด ไม่ตัดทิ้ง ไม่อย่างนั้น = ไม่รับ
///
/// Developed by Xman Studio
library;

import '../services/wallet_service.dart';

/// เหตุผลที่อ่านไม่ผ่าน — [notEip681] = ไม่ใช่ `ethereum:` เลย (ผู้เรียกลองอ่านเป็นที่อยู่ล้วนต่อได้)
enum Eip681Error {
  notEip681,
  badAddress,
  badChainId,
  unsupportedFunction,
  badParam,
  badAmount,
  conflictingAmount,
}

/// คำขอชำระเงินที่อ่านได้
class PaymentRequest {
  /// ที่อยู่ผู้รับเงิน (ตัวพิมพ์ตามที่ร้านเขียนมา ผ่านการตรวจ checksum แล้ว)
  final String recipient;

  /// สัญญาโทเค็น ERC-20 — null = เหรียญหลักของเชน (TPIX บน 4289)
  final String? tokenAddress;

  /// chain id จาก `@<id>` — null = URI ไม่ได้ระบุ
  final int? chainId;

  /// ยอดหน่วยย่อยที่ระบุแน่นอนแล้ว (`value=` ของเหรียญหลักเป็น wei, `uint256=` ของโทเค็น)
  /// หรือ `amount=` ของเหรียญหลักที่แปลงเป็น wei (18 ตำแหน่ง) แล้ว
  final BigInt? rawAmount;

  /// `amount=` (ทศนิยม) ของโทเค็น — ต้องรู้ทศนิยมของโทเค็นก่อนถึงแปลงได้ ใช้ [amountIn]
  final String? decimalAmount;

  const PaymentRequest({
    required this.recipient,
    this.tokenAddress,
    this.chainId,
    this.rawAmount,
    this.decimalAmount,
  });

  bool get isToken => tokenAddress != null;
  bool get hasAmount => rawAmount != null || decimalAmount != null;

  /// ยอดหน่วยย่อยของเหรียญที่มี [decimals] ตำแหน่ง — null = ไม่มียอด หรือยอดแปลงไม่ลงตัว
  /// (เช่น amount=1.5 กับโทเค็น 0 ตำแหน่ง) ผู้เรียกต้องเช็ค [hasAmount] แยกเอง
  BigInt? amountIn(int decimals) {
    if (rawAmount != null) return rawAmount;
    final d = decimalAmount;
    return d == null ? null : Eip681.parseScaled(d, decimals);
  }
}

/// ผลการอ่าน — [request] ไม่ null เมื่อผ่าน
class Eip681Result {
  final PaymentRequest? request;
  final Eip681Error? error;
  const Eip681Result.ok(PaymentRequest this.request) : error = null;
  const Eip681Result.fail(Eip681Error this.error) : request = null;
  bool get isOk => request != null;
}

class Eip681 {
  Eip681._();

  /// ยาวเกินนี้ไม่ใช่คำขอชำระเงินจริง (กัน QR/ลิงก์ยักษ์มากิน CPU)
  static const maxLength = 2048;

  /// ตัวเลขยาวเกินนี้ไม่รับ (ยอด uint256 เต็มก็แค่ 78 หลัก)
  static const _maxNumberLength = 100;

  static final _uint256Max = (BigInt.one << 256) - BigInt.one;
  static final _addressRe = RegExp(r'^0x[0-9a-fA-F]{40}');
  static final _chainRe = RegExp(r'^@(\d{1,10})');
  static final _functionRe = RegExp(r'^/([A-Za-z_][A-Za-z0-9_]*)');
  static final _numberRe = RegExp(r'^\+?(\d*)(?:\.(\d*))?(?:[eE]([+-]?\d{1,3}))?$');

  /// อ่าน `ethereum:` URI — ข้อความที่ไม่ขึ้นต้นด้วย `ethereum:` ได้ [Eip681Error.notEip681]
  static Eip681Result parse(String raw) {
    final s = raw.trim();
    const scheme = 'ethereum:';
    if (s.length < scheme.length || s.substring(0, scheme.length).toLowerCase() != scheme) {
      return const Eip681Result.fail(Eip681Error.notEip681);
    }
    if (s.length > maxLength) return const Eip681Result.fail(Eip681Error.badParam);

    var rest = s.substring(scheme.length);
    if (rest.startsWith('pay-')) rest = rest.substring(4);

    // ── ที่อยู่ปลายทาง (รับเฉพาะ 0x — ชื่อ ENS ไม่รองรับบน TPIX Chain) ──
    final addrMatch = _addressRe.firstMatch(rest);
    if (addrMatch == null) return const Eip681Result.fail(Eip681Error.badAddress);
    final target = addrMatch.group(0)!;
    rest = rest.substring(target.length);
    if (rest.isNotEmpty && !'@/?'.contains(rest[0])) {
      return const Eip681Result.fail(Eip681Error.badAddress); // ที่อยู่ยาวเกิน 40 หลัก
    }
    if (!WalletService.isValidAddress(target)) {
      return const Eip681Result.fail(Eip681Error.badAddress); // checksum ไม่ตรง
    }

    // ── @chainId (ฐานสิบ) ──
    int? chainId;
    if (rest.startsWith('@')) {
      final m = _chainRe.firstMatch(rest);
      if (m == null) return const Eip681Result.fail(Eip681Error.badChainId);
      chainId = int.parse(m.group(1)!);
      rest = rest.substring(m.group(0)!.length);
      if (chainId <= 0 || (rest.isNotEmpty && !'/?'.contains(rest[0]))) {
        return const Eip681Result.fail(Eip681Error.badChainId);
      }
    }

    // ── /function (รองรับแค่ transfer ของ ERC-20) ──
    String? function;
    if (rest.startsWith('/')) {
      final m = _functionRe.firstMatch(rest);
      if (m == null) return const Eip681Result.fail(Eip681Error.badParam);
      function = m.group(1)!;
      rest = rest.substring(m.group(0)!.length);
      if (function != 'transfer') {
        return const Eip681Result.fail(Eip681Error.unsupportedFunction);
      }
    }

    // ── ?query ──
    final params = <String, String>{};
    if (rest.isNotEmpty) {
      if (!rest.startsWith('?')) return const Eip681Result.fail(Eip681Error.badParam);
      for (final part in rest.substring(1).split('&')) {
        if (part.isEmpty) continue;
        final eq = part.indexOf('=');
        if (eq <= 0) return const Eip681Result.fail(Eip681Error.badParam);
        final String key;
        final String value;
        try {
          // decodeComponent (ไม่ใช่ decodeQueryComponent) — "+" ใน 1.5e+18 ต้องยังเป็น "+"
          key = Uri.decodeComponent(part.substring(0, eq));
          value = Uri.decodeComponent(part.substring(eq + 1));
        } on ArgumentError {
          return const Eip681Result.fail(Eip681Error.badParam);
        }
        // คีย์ซ้ำ = กำกวม (เช่น value สองค่า) ไม่เดาว่าตัวไหนถูก
        if (params.containsKey(key)) return const Eip681Result.fail(Eip681Error.badParam);
        params[key] = value;
      }
    }

    if (function == null) {
      // ── โอนเหรียญหลัก ──
      BigInt? wei;
      if (params['value'] case final v?) {
        wei = parseScaled(v, 0);
        if (wei == null) return const Eip681Result.fail(Eip681Error.badAmount);
      }
      if (params['amount'] case final a?) {
        final fromAmount = parseScaled(a, 18);
        if (fromAmount == null) return const Eip681Result.fail(Eip681Error.badAmount);
        if (wei != null && wei != fromAmount) {
          return const Eip681Result.fail(Eip681Error.conflictingAmount);
        }
        wei = fromAmount;
      }
      return Eip681Result.ok(PaymentRequest(recipient: target, chainId: chainId, rawAmount: wei));
    }

    // ── ERC-20 transfer(address,uint256) ──
    final to = params['address'];
    if (to == null || !RegExp(r'^0x[0-9a-fA-F]{40}$').hasMatch(to) || !WalletService.isValidAddress(to)) {
      return const Eip681Result.fail(Eip681Error.badParam);
    }
    // แนบเหรียญหลักไปกับการโอนโทเค็น = คำขอแปลก ไม่รับ
    if (params['value'] case final v?) {
      if (parseScaled(v, 0) != BigInt.zero) return const Eip681Result.fail(Eip681Error.badParam);
    }
    BigInt? units;
    if (params['uint256'] case final u?) {
      units = parseScaled(u, 0);
      if (units == null) return const Eip681Result.fail(Eip681Error.badAmount);
    }
    String? decimalAmount;
    if (params['amount'] case final a?) {
      // ยังไม่รู้ทศนิยมของโทเค็น — ตรวจแค่รูปแบบตัวเลขไว้ก่อน
      if (!_isNumber(a)) return const Eip681Result.fail(Eip681Error.badAmount);
      // มีทั้ง uint256 และ amount — เทียบกันไม่ได้จนกว่าจะรู้ทศนิยม → กำกวม ไม่รับ
      if (units != null) return const Eip681Result.fail(Eip681Error.conflictingAmount);
      decimalAmount = a;
    }
    return Eip681Result.ok(PaymentRequest(
      recipient: to,
      tokenAddress: target,
      chainId: chainId,
      rawAmount: units,
      decimalAmount: decimalAmount,
    ));
  }

  static bool _isNumber(String input) {
    final s = input.trim();
    if (s.isEmpty || s.length > _maxNumberLength) return false;
    final m = _numberRe.firstMatch(s);
    return m != null && '${m.group(1) ?? ''}${m.group(2) ?? ''}'.isNotEmpty;
  }

  /// แปลงตัวเลขตามไวยากรณ์ EIP-681 (`123`, `1.5`, `1.5e18`, `15E+17`) × 10^[scale]
  /// ให้เป็นจำนวนเต็มแบบไม่เสียความแม่นยำ
  ///
  /// null = รูปแบบผิด / ติดลบ / ผลไม่ใช่จำนวนเต็มพอดี / เกิน uint256
  static BigInt? parseScaled(String input, int scale) {
    final s = input.trim();
    if (s.isEmpty || s.length > _maxNumberLength) return null;
    final m = _numberRe.firstMatch(s);
    if (m == null) return null;
    final whole = m.group(1) ?? '';
    final frac = m.group(2) ?? '';
    if (whole.isEmpty && frac.isEmpty) return null;
    final exp = int.parse(m.group(3) ?? '0');

    final mantissa = BigInt.parse('$whole$frac'.isEmpty ? '0' : '$whole$frac');
    if (mantissa == BigInt.zero) return BigInt.zero;
    final shift = exp - frac.length + scale;
    BigInt result;
    if (shift >= 0) {
      // 10^80 ก็เกิน uint256 แล้ว — ไม่ต้องคูณเลขยักษ์ให้เปลือง
      if (shift > 80) return null;
      result = mantissa * BigInt.from(10).pow(shift);
    } else {
      final divisor = BigInt.from(10).pow(-shift);
      if (mantissa % divisor != BigInt.zero) return null; // มีเศษ = ไม่ใช่จำนวนเต็มพอดี
      result = mantissa ~/ divisor;
    }
    return result > _uint256Max ? null : result;
  }
}
