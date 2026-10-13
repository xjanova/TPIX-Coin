/// TPIX Wallet — ตัวจัดรูปตัวเลขของหน้าธีม Obsidian (ฟังก์ชันล้วน มีเทสต์)
///
/// ทุกตัวไม่ขึ้นกับภาษาเครื่อง (ไม่ใช้ toString ของ double ตรง ๆ กับยอดเงิน)
/// และ "ไม่รู้ = null" — ห้ามเดาราคา/มูลค่า
///
/// Developed by Xman Studio
library;

import 'package:intl/intl.dart';

import '../../utils/units.dart';

final _big = NumberFormat('#,##0.00', 'en_US');
final _mid = NumberFormat('#,##0.####', 'en_US');
final _usd = NumberFormat.currency(locale: 'en_US', symbol: '\$', decimalDigits: 2);

/// ยอดสำหรับแสดงผล: ≥1,000 → 2 ตำแหน่ง · ≥1 → ไม่เกิน 4 ตำแหน่ง · <1 → 4 หลักนัยสำคัญ
String obsidianAmountText(double v) {
  if (v.isNaN || v.isInfinite) return '—';
  if (v == 0) return '0';
  final a = v.abs();
  final sign = v < 0 ? '-' : '';
  if (a >= 1000) return '$sign${_big.format(a)}';
  if (a >= 1) return '$sign${_mid.format(a)}';
  if (a < 0.000001) return '$sign<0.000001';
  // 4 หลักนัยสำคัญ แล้วตัดศูนย์ท้าย (0.09920 → 0.0992)
  var s = a.toStringAsPrecision(4);
  if (s.contains('e')) return '$sign${a.toStringAsFixed(8)}'.replaceFirst(RegExp(r'0+$'), '');
  if (s.contains('.')) s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  return '$sign$s';
}

final _stable = NumberFormat('#,##0.00##', 'en_US');

/// ยอดเหรียญดอลลาร์ (USDT/USDC) — อย่างน้อย 2 ตำแหน่ง ไม่เกิน 4 (1,250.00 · 0.1234)
String obsidianStableText(double v) {
  if (v.isNaN || v.isInfinite) return '—';
  if (v > 0 && v < 0.0001) return '<0.0001';
  return _stable.format(v);
}

/// มูลค่าดอลลาร์สำหรับแสดงผล
String obsidianUsdText(double v) => '≈ ${_usd.format(v)}';

/// สัญลักษณ์ของเหรียญที่ผูกกับดอลลาร์ (ใช้ประมาณมูลค่าเท่านั้น)
const Set<String> obsidianStableSymbols = {'USDT', 'USDC', 'BUSD', 'DAI', 'FDUSD', 'USDC.E', 'USDT.E'};

bool obsidianIsStable(String symbol) => obsidianStableSymbols.contains(symbol.toUpperCase());

/// มูลค่าดอลลาร์โดยประมาณของ [amount] เหรียญ [symbol]
///
/// รู้ได้แค่ 2 กรณี: เหรียญดอลลาร์ (≈1:1) และ TPIX ที่มีราคาจริงจาก [tpixPrice]
/// อย่างอื่น = null (ผู้เรียกอาจประมาณจากใบเสนอราคาเองถ้าอีกฝั่งเป็นเหรียญดอลลาร์)
///
/// ★ ใช้ได้เฉพาะรายการเหรียญที่คัดมาแล้ว (สัญญาตัวจริง) — เหรียญปลอมชื่อ USDT ห้ามผ่านมาถึงนี่
double? obsidianUsdValue({required String symbol, required double amount, double? tpixPrice}) {
  if (amount.isNaN || amount.isInfinite || amount < 0) return null;
  if (obsidianIsStable(symbol)) return amount;
  if (symbol.toUpperCase() == 'TPIX' && tpixPrice != null && tpixPrice > 0) return amount * tpixPrice;
  return null;
}

/// มูลค่าดอลลาร์ของสองฝั่งการแลก — อีกฝั่งเป็นเหรียญดอลลาร์ = ใช้ยอดฝั่งนั้นประมาณ
({double? pay, double? receive}) obsidianSwapUsd({
  required String paySymbol,
  required double? payAmount,
  required String receiveSymbol,
  required double? receiveAmount,
  double? tpixPrice,
}) {
  double? of(String s, double? a) => a == null ? null : obsidianUsdValue(symbol: s, amount: a, tpixPrice: tpixPrice);
  final pay = of(paySymbol, payAmount);
  final receive = of(receiveSymbol, receiveAmount);
  return (
    pay: pay ?? (obsidianIsStable(receiveSymbol) ? receiveAmount : null),
    receive: receive ?? (obsidianIsStable(paySymbol) ? payAmount : null),
  );
}

/// [percent]% ของยอด (ปัดลงเสมอ — ไม่มีทางเกินยอดจริง) เป็นข้อความสำหรับช่องกรอก
/// ตัดทศนิยมเหลือไม่เกิน [maxDecimals] ตำแหน่ง
String obsidianFractionText(BigInt balance, int percent, int decimals, {int maxDecimals = 8}) {
  if (balance <= BigInt.zero || percent <= 0) return '0';
  var units = balance * BigInt.from(percent.clamp(0, 100)) ~/ BigInt.from(100);
  if (decimals > maxDecimals) {
    final step = BigInt.from(10).pow(decimals - maxDecimals);
    units -= units % step;
  }
  return Units.format(units, decimals);
}
