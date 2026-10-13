/// TPIX Wallet — เทสต์หน้ารับเงินธีม Obsidian + ตัวจับเงินเข้า
///
/// ล็อกพฤติกรรม:
///   1. ตัวจับเงินเข้าไม่เด้งหลอก: ยอดแรก / สลับกระเป๋า / ยอดหายชั่วคราว / ยอดลด ไม่นับ
///   2. QR เป็นที่อยู่จริง (สแกนได้) · ยังไม่มีกระเป๋า = ไม่วาด QR
///   3. คำเตือน Chain ID เปลี่ยนตามชิปที่เลือก
///   4. ยอด TPIX เพิ่มระหว่างเปิดหน้า → แถบ "ได้รับเงินแล้ว" ขึ้นพร้อมจำนวนที่ถูกต้อง
///   5. ธีมอื่นยังได้หน้าเดิม
///
/// Developed by Xman Studio
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:tpix_wallet/core/locale_provider.dart';
import 'package:tpix_wallet/core/themes/theme_bundle.dart';
import 'package:tpix_wallet/models/token_info.dart';
import 'package:tpix_wallet/providers/wallet_provider.dart';
import 'package:tpix_wallet/screens/receive_obsidian.dart';
import 'package:tpix_wallet/screens/receive_screen.dart';
import 'package:tpix_wallet/utils/balance_watch.dart';
import 'package:tpix_wallet/widgets/obsidian/receive_art.dart';

import 'support/test_theme.dart';

const _me = '0xd2ea4b1c9f3e7a8b5d6c0f2a1e9b8c7d4f3a67d7';

class _Wallet extends WalletProvider {
  _Wallet({this.addr = _me});
  final String? addr;
  BigInt? wei = BigInt.parse('1000000000000000000000'); // 1,000 TPIX

  @override
  String? get address => addr;
  @override
  BigInt? get balanceWei => wei;
  @override
  int get activeChainId => 4289;
  @override
  Map<int, BigInt> get chainBalances => const {};
  @override
  List<TokenInfo> get activeTokens => const [];

  void credit(BigInt v) {
    wei = (wei ?? BigInt.zero) + v;
    notifyListeners();
  }
}

Widget _app(WalletProvider w, {ThemeId theme = ThemeId.obsidian}) => MultiProvider(
      providers: [
        ChangeNotifierProvider<WalletProvider>.value(value: w),
        ChangeNotifierProvider(create: (_) => LocaleProvider()),
      ],
      child: MaterialApp(theme: testTheme(themeId: theme), home: const ReceiveScreen()),
    );

void main() {
  group('BalanceIncreaseDetector', () {
    test('ยอดแรก = จุดเริ่ม ไม่ใช่เงินเข้า', () {
      final d = BalanceIncreaseDetector();
      expect(d.update('0xA', {'n': BigInt.from(5)}), isEmpty);
      expect(d.update('0xA', {'n': BigInt.from(8)}), [BalanceIncrease('n', BigInt.from(3))]);
    });

    test('null → มีค่า (เพิ่งโหลดยอดเสร็จ) ไม่นับเป็นเงินเข้า', () {
      final d = BalanceIncreaseDetector();
      d.update('0xA', {'n': null});
      expect(d.update('0xA', {'n': BigInt.from(100)}), isEmpty);
    });

    test('สลับกระเป๋า = เริ่มนับใหม่ (ไม่เด้งเงินเข้าหลอก)', () {
      final d = BalanceIncreaseDetector();
      d.update('0xA', {'n': BigInt.from(1)});
      expect(d.update('0xB', {'n': BigInt.from(999)}), isEmpty);
      expect(d.update('0xb', {'n': BigInt.from(1000)}), [BalanceIncrease('n', BigInt.one)],
          reason: 'ที่อยู่ตัวพิมพ์ต่างกันคือกระเป๋าเดียวกัน');
    });

    test('ยอดดึงไม่ได้ชั่วคราวคงค่าเดิม แล้วเทียบต่อได้', () {
      final d = BalanceIncreaseDetector();
      d.update('0xA', {'n': BigInt.from(10)});
      expect(d.update('0xA', {'n': null}), isEmpty);
      expect(d.update('0xA', {'n': BigInt.from(15)}), [BalanceIncrease('n', BigInt.from(5))]);
    });

    test('ยอดลด (ส่งออก) ไม่นับ และใช้ยอดใหม่เป็นฐาน', () {
      final d = BalanceIncreaseDetector();
      d.update('0xA', {'n': BigInt.from(10)});
      expect(d.update('0xA', {'n': BigInt.from(4)}), isEmpty);
      expect(d.update('0xA', {'n': BigInt.from(6)}), [BalanceIncrease('n', BigInt.two)]);
    });

    test('โทเค็นที่เพิ่งเพิ่มเข้ามาไม่ใช่เงินเข้า · ไม่มีกระเป๋า = ล้าง', () {
      final d = BalanceIncreaseDetector();
      d.update('0xA', {'n': BigInt.one});
      expect(d.update('0xA', {'n': BigInt.one, 't': BigInt.from(50)}), isEmpty);
      expect(d.update(null, {'n': BigInt.from(9)}), isEmpty);
      expect(d.update('0xA', {'n': BigInt.from(9)}), isEmpty);
    });

    test('ไม่ผ่าน double — ยอดหน่วยย่อยใหญ่ ๆ ยังเทียบแม่น', () {
      final d = BalanceIncreaseDetector();
      final big = BigInt.parse('123456789012345678901234567890');
      d.update('0xA', {'n': big});
      expect(d.update('0xA', {'n': big + BigInt.one}), [BalanceIncrease('n', BigInt.one)]);
    });
  });

  group('groupDigits', () {
    test('คั่นหลักพันเฉพาะส่วนจำนวนเต็ม', () {
      expect(groupDigits('1500'), '1,500');
      expect(groupDigits('1234567.891011'), '1,234,567.891011');
      expect(groupDigits('999'), '999');
      expect(groupDigits('0.000001'), '0.000001');
    });
    test('ข้อความที่ไม่ใช่ตัวเลขคืนเดิม', () {
      expect(groupDigits('—'), '—');
      expect(groupDigits(''), '');
      expect(groupDigits('1,500'), '1,500');
    });
  });

  group('ReceivePalette', () {
    test('สีตามเชน (ไม่รู้จัก = TPIX)', () {
      expect(ReceivePalette.of(56).c1, const Color(0xFFF3BA2F));
      expect(ReceivePalette.of(137).c1, const Color(0xFF8247E5));
      expect(ReceivePalette.of(1).c1, const Color(0xFF627EEA));
      expect(ReceivePalette.of(999), ReceivePalette.tpix);
    });
  });

  group('หน้ารับเงิน Obsidian', () {
    testWidgets('QR เป็นที่อยู่จริง + คำเตือนเปลี่ยนตามชิป', (tester) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_app(_Wallet()));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(ObsidianReceiveView), findsOneWidget);
      final qr = tester.widget<QrImageView>(find.byType(QrImageView));
      expect(qr.errorCorrectionLevel, QrErrorCorrectLevel.H);
      expect(find.textContaining('(Chain ID 4289)'), findsOneWidget);

      await tester.tap(find.text('BNB'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.textContaining('(Chain ID 56)'), findsOneWidget);
      expect(find.textContaining('(Chain ID 4289)'), findsNothing);
      expect(find.byType(QrImageView), findsOneWidget);
    });

    testWidgets('ยังไม่มีกระเป๋า → ไม่วาด QR', (tester) async {
      await tester.pumpWidget(_app(_Wallet(addr: null)));
      await tester.pump();
      expect(find.byType(QrImageView), findsNothing);
      expect(find.text(LocaleProvider().t('receive.noWallet')), findsOneWidget);
    });

    testWidgets('ยอด TPIX เพิ่มระหว่างเปิดหน้า → แถบเงินเข้าพร้อมจำนวนจริง แล้วหายเอง', (tester) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      final w = _Wallet();
      await tester.pumpWidget(_app(w));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(IncomingToast), findsNothing, reason: 'ยอดตอนเปิดหน้าไม่ใช่เงินเข้า');

      w.credit(BigInt.parse('250500000000000000000')); // +250.5 TPIX
      await tester.pump();
      expect(find.byType(IncomingToast), findsOneWidget);

      // ตัวเลขนับขึ้นจบที่จำนวนจริง
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('+250.5 TPIX'), findsOneWidget);

      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      expect(find.byType(IncomingToast), findsNothing);
    });

    testWidgets('ธีมอื่นยังใช้หน้าเดิม', (tester) async {
      await tester.pumpWidget(_app(_Wallet(), theme: ThemeId.liquid));
      await tester.pump();
      expect(find.byType(ObsidianReceiveView), findsNothing);
      expect(find.text(LocaleProvider().t('receive.warning')), findsOneWidget);
    });
  });
}
