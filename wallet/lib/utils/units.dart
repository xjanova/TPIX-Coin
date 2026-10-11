/// TPIX Wallet — แปลงจำนวนเงินระหว่าง "ข้อความที่ผู้ใช้พิมพ์" กับหน่วยย่อยบนเชน
///
/// ★ ห้ามผ่าน double เด็ดขาด — double เก็บทศนิยมฐานสองได้ไม่ตรง
///   เช่น 0.1.toStringAsFixed(18) = "0.100000000000000006" → ส่งเกินที่ผู้ใช้พิมพ์
///   ของเดิมของหน้าโอนทำแบบนั้นจริง ตอนนี้แปลงจากสตริงตรงเป็น BigInt ทั้งหมด
///
/// Developed by Xman Studio
library;

import 'dart:typed_data';

import 'package:hex/hex.dart';

/// ผลของการแปลงจำนวนที่ผู้ใช้พิมพ์ — แยกเหตุผลที่ไม่ผ่าน เพื่อบอกผู้ใช้ให้ถูกเรื่อง
enum AmountError { empty, invalid, tooManyDecimals, zero }

class ParsedAmount {
  final BigInt? value;
  final AmountError? error;
  const ParsedAmount._(this.value, this.error);
  const ParsedAmount.ok(BigInt v) : this._(v, null);
  const ParsedAmount.fail(AmountError e) : this._(null, e);
  bool get isOk => value != null;
}

class Units {
  Units._();

  /// แปลง "1.5" → 1500000 (decimals=6) แบบไม่เสียความแม่นยำ
  ///
  /// - รับจุดเป็นตัวคั่นทศนิยม และรับ "จุลภาคตัวเดียว" เป็นทศนิยมด้วย
  ///   (คีย์บอร์ดตัวเลขบางภาษาให้แต่ , ) — ถ้ามีทั้ง , และ . ถือว่ากำกวม → ไม่รับ
  /// - ทศนิยมเกินที่เหรียญรองรับ → ไม่ปัดทิ้งเงียบๆ แต่แจ้งผู้ใช้ (ปัดทิ้ง = ส่งไม่ตรงที่ตั้งใจ)
  /// - 0 → error zero (ผู้เรียกตัดสินเองว่าห้ามส่ง 0)
  static ParsedAmount parse(String input, int decimals) {
    var text = input.trim().replaceAll(' ', '');
    if (text.isEmpty) return const ParsedAmount.fail(AmountError.empty);

    final commas = ','.allMatches(text).length;
    if (commas > 0) {
      if (text.contains('.') || commas > 1) {
        return const ParsedAmount.fail(AmountError.invalid);
      }
      text = text.replaceFirst(',', '.');
    }

    final match = RegExp(r'^(\d*)(?:\.(\d*))?$').firstMatch(text);
    if (match == null) return const ParsedAmount.fail(AmountError.invalid);
    final whole = match.group(1) ?? '';
    final frac = match.group(2) ?? '';
    if (whole.isEmpty && frac.isEmpty) {
      return const ParsedAmount.fail(AmountError.invalid);
    }
    if (frac.length > decimals) {
      // ศูนย์ท้ายเกินมาไม่เปลี่ยนค่า ("1.500000" กับ USDT 6 ตำแหน่ง ก็ยังโอเค)
      final extra = frac.substring(decimals);
      if (extra.replaceAll('0', '').isNotEmpty) {
        return const ParsedAmount.fail(AmountError.tooManyDecimals);
      }
    }
    final fracPadded =
        frac.length > decimals ? frac.substring(0, decimals) : frac.padRight(decimals, '0');
    final value = BigInt.parse(whole.isEmpty ? '0' : whole) * BigInt.from(10).pow(decimals) +
        (decimals == 0 ? BigInt.zero : BigInt.parse(fracPadded.isEmpty ? '0' : fracPadded));
    if (value == BigInt.zero) return const ParsedAmount.fail(AmountError.zero);
    return ParsedAmount.ok(value);
  }

  /// แปลงหน่วยย่อย → ข้อความทศนิยมเต็มความแม่นยำ (ตัดศูนย์ท้าย) เช่น 1500000/6 → "1.5"
  /// ใช้กับปุ่ม MAX — ต้องได้ "ทั้งหมด" จริง ไม่ใช่ค่าที่ปัดขึ้นจนเกินยอด
  static String format(BigInt value, int decimals) {
    final negative = value.isNegative;
    final abs = value.abs();
    if (decimals == 0) return '${negative ? '-' : ''}$abs';
    final divisor = BigInt.from(10).pow(decimals);
    final whole = abs ~/ divisor;
    var frac = (abs % divisor).toString().padLeft(decimals, '0');
    frac = frac.replaceFirst(RegExp(r'0+$'), '');
    final body = frac.isEmpty ? '$whole' : '$whole.$frac';
    return negative ? '-$body' : body;
  }

  /// แปลงเป็น double ไว้ "แสดงผล/คำนวณมูลค่าโดยประมาณ" เท่านั้น — ห้ามใช้ส่งเงิน
  static double toDouble(BigInt value, int decimals) =>
      double.tryParse(format(value, decimals)) ?? 0;

  /// gas ที่ประเมินได้ + เผื่อ 20% (ส่วนที่ไม่ได้ใช้คืนกลับเอง)
  /// โอนเหรียญปกติ 21000 พอดีเป๊ะ ไม่ต้องเผื่อ
  static int addGasMargin(int estimated) {
    if (estimated <= 21000) return 21000;
    return estimated + (estimated ~/ 5);
  }

  /// calldata ของ ERC-20 transfer(address to, uint256 amount)
  /// selector 0xa9059cbb = keccak256("transfer(address,uint256)")[0..4]
  static Uint8List encodeErc20Transfer(String to, BigInt amount) {
    if (amount.isNegative) throw ArgumentError('amount must be >= 0');
    final addr = to.toLowerCase().replaceFirst('0x', '');
    if (!RegExp(r'^[0-9a-f]{40}$').hasMatch(addr)) {
      throw ArgumentError('invalid recipient address');
    }
    final amountHex = amount.toRadixString(16);
    if (amountHex.length > 64) throw ArgumentError('amount overflows uint256');
    return Uint8List.fromList(HEX.decode(
      'a9059cbb${addr.padLeft(64, '0')}${amountHex.padLeft(64, '0')}',
    ));
  }
}
