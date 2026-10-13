/// TPIX Wallet — ตัวจัดรูปตัวเลขของหน้าธีม Obsidian (ฟังก์ชันล้วน)
///
/// สิ่งที่ห้ามพัง:
///   - ไม่ขึ้นกับภาษาเครื่อง · ไม่โชว์ 1e-7 / NaN
///   - มูลค่าดอลลาร์ "ไม่รู้ = null" (ห้ามเดาราคาเหรียญที่ไม่ใช่เหรียญดอลลาร์)
///   - ปุ่ม 25% / 50% ปัดลงเสมอ — ไม่มีทางเกินยอดจริง (กันยอดไม่พอตอนส่ง)
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:tpix_wallet/widgets/obsidian/obsidian_format.dart';

final _e18 = BigInt.from(10).pow(18);

void main() {
  group('obsidianAmountText', () {
    test('ยอดใหญ่ 2 ตำแหน่ง มีจุลภาค', () {
      expect(obsidianAmountText(12450.25), '12,450.25');
      expect(obsidianAmountText(1000), '1,000.00');
    });

    test('ยอดกลาง ไม่เกิน 4 ตำแหน่ง ตัดศูนย์ท้าย', () {
      expect(obsidianAmountText(585.4), '585.4');
      expect(obsidianAmountText(1.23456), '1.2346');
      expect(obsidianAmountText(1), '1');
    });

    test('ยอดเล็ก 4 หลักนัยสำคัญ ไม่เป็นเลขยกกำลัง', () {
      expect(obsidianAmountText(0.0992), '0.0992');
      expect(obsidianAmountText(0.000123456), '0.0001235');
      expect(obsidianAmountText(0.0000001), '<0.000001');
      expect(obsidianAmountText(0), '0');
    });

    test('ค่าผิดปกติ = ขีด', () {
      expect(obsidianAmountText(double.nan), '—');
      expect(obsidianAmountText(double.infinity), '—');
    });
  });

  test('obsidianStableText: อย่างน้อย 2 ตำแหน่ง ไม่เกิน 4', () {
    expect(obsidianStableText(1250), '1,250.00');
    expect(obsidianStableText(420.5), '420.50');
    expect(obsidianStableText(0.123456), '0.1235');
    expect(obsidianStableText(0.00001), '<0.0001');
  });

  group('มูลค่าดอลลาร์ (ไม่รู้ = null)', () {
    test('เหรียญดอลลาร์ ≈ 1:1 · TPIX ใช้ราคาจริง · อื่น ๆ ไม่รู้', () {
      expect(obsidianUsdValue(symbol: 'USDT', amount: 12.5), 12.5);
      expect(obsidianUsdValue(symbol: 'usdc', amount: 3), 3);
      expect(obsidianUsdValue(symbol: 'TPIX', amount: 1000, tpixPrice: 0.1), closeTo(100, 1e-9));
      expect(obsidianUsdValue(symbol: 'TPIX', amount: 1000), isNull, reason: 'ไม่มีราคา = ไม่รู้');
      expect(obsidianUsdValue(symbol: 'BNB', amount: 1), isNull);
      expect(obsidianUsdValue(symbol: 'USDT', amount: double.nan), isNull);
    });

    test('อีกฝั่งเป็นเหรียญดอลลาร์ → ประมาณจากยอดฝั่งนั้น', () {
      final r = obsidianSwapUsd(paySymbol: 'BNB', payAmount: 1, receiveSymbol: 'USDT', receiveAmount: 585.4);
      expect(r.pay, 585.4);
      expect(r.receive, 585.4);

      final back = obsidianSwapUsd(paySymbol: 'USDT', payAmount: 100, receiveSymbol: 'BNB', receiveAmount: 0.17);
      expect(back.pay, 100);
      expect(back.receive, 100);
    });

    test('ไม่มีเหรียญดอลลาร์ทั้งสองฝั่ง → ไม่โชว์มูลค่า', () {
      final r = obsidianSwapUsd(paySymbol: 'BNB', payAmount: 1, receiveSymbol: 'ETH', receiveAmount: 0.2);
      expect(r.pay, isNull);
      expect(r.receive, isNull);
    });

    test('ยังไม่มีราคา (ยอดรับ null) → ฝั่งจ่ายไม่เดาจากอะไร', () {
      final r = obsidianSwapUsd(paySymbol: 'BNB', payAmount: 1, receiveSymbol: 'USDT', receiveAmount: null);
      expect(r.pay, isNull);
      expect(r.receive, isNull);
    });
  });

  group('obsidianFractionText (25% / 50%)', () {
    test('ปัดลงเหลือไม่เกิน 8 ตำแหน่ง — ไม่เกินยอดจริงเสมอ', () {
      // 1.000000000000000001 BNB → 25% = 0.25000000000000000025 → 0.25
      final bal = _e18 + BigInt.one;
      expect(obsidianFractionText(bal, 25, 18), '0.25');
      // ยอดที่หารไม่ลงตัว: 1 wei × 50% = 0
      expect(obsidianFractionText(BigInt.one, 50, 18), '0');
      // 0.123456789 × 50% = 0.0617283945 → 0.06172839 (ปัดลง)
      expect(obsidianFractionText(BigInt.parse('123456789000000000'), 50, 18), '0.06172839');
    });

    test('เหรียญทศนิยมน้อย (USDT 6) ไม่ตัดเกินจำเป็น', () {
      expect(obsidianFractionText(BigInt.from(1250500000), 50, 6), '625.25');
    });

    test('ยอดศูนย์/ติดลบ/เปอร์เซ็นต์ผิด = 0', () {
      expect(obsidianFractionText(BigInt.zero, 50, 18), '0');
      expect(obsidianFractionText(BigInt.from(-5), 50, 18), '0');
      expect(obsidianFractionText(_e18, 0, 18), '0');
    });
  });
}
