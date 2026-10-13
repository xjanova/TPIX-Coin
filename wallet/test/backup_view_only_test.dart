/// TPIX Wallet — หน้าวลีกู้คืนแบบ "ดูอย่างเดียว" (เปิดจากหน้าตั้งค่า)
///
/// ล็อกบั๊กเดิม: เข้าไปดูวลีจากตั้งค่าแล้วกดปุ่มล่าง → ถูกพาไปตั้ง PIN ใหม่ + บันทึกกระเป๋าซ้ำ
/// (โทเค็นสแกนนิ้วที่ผูกกับ PIN เดิมเลยใช้ไม่ได้) — ต้องแค่ปิดกลับหน้าเดิม
/// ส่วนขั้นตอนสร้างกระเป๋าใหม่ (viewOnly = false) ยังต้องไปหน้าตั้ง PIN ตามเดิม
///
/// Developed by Xman Studio
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tpix_wallet/core/locale_provider.dart';
import 'package:tpix_wallet/core/theme_provider.dart';
import 'package:tpix_wallet/core/themes/theme_bundle.dart';
import 'package:tpix_wallet/providers/wallet_provider.dart';
import 'package:tpix_wallet/screens/backup_screen.dart';
import 'package:tpix_wallet/screens/pin_screen.dart';

import 'support/test_theme.dart';

const _phrase =
    'abandon ability able about above absent absorb abstract absurd abuse access accident';

Widget _app(ThemeId theme, {required bool viewOnly}) => MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => WalletProvider()),
        ChangeNotifierProvider(create: (_) => LocaleProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ],
      child: MaterialApp(
        theme: testTheme(themeId: theme),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => BackupScreen(mnemonic: _phrase, viewOnly: viewOnly)),
                ),
                child: const Text('open-backup'),
              ),
            ),
          ),
        ),
      ),
    );

/// ปุ่มล่างของหน้าวลี — ข้อความตามภาษาปัจจุบัน
Finder _bottomButton(WidgetTester tester, String key) {
  final l = Provider.of<LocaleProvider>(tester.element(find.byType(BackupScreen)), listen: false);
  return find.text(l.t(key));
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final theme in [ThemeId.obsidian, ThemeId.classic]) {
    testWidgets('[${theme.key}] ดูวลีจากตั้งค่า → ปุ่ม "เสร็จสิ้น" ปิดกลับ ไม่พาไปตั้ง PIN ใหม่', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(_app(theme, viewOnly: true));
      await tester.tap(find.text('open-backup'));
      await tester.pumpAndSettle();

      final done = _bottomButton(tester, 'backup.done');
      await tester.ensureVisible(done);
      await tester.tap(done);
      await tester.pumpAndSettle();

      expect(find.byType(BackupScreen), findsNothing);
      expect(find.byType(PinScreen), findsNothing);
      expect(find.text('open-backup'), findsOneWidget);
    });

    testWidgets('[${theme.key}] ขั้นตอนสร้างกระเป๋าใหม่ → ยังไปหน้าตั้ง PIN ตามเดิม', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(_app(theme, viewOnly: false));
      await tester.tap(find.text('open-backup'));
      await tester.pumpAndSettle();

      final next = _bottomButton(tester, 'backup.continue');
      await tester.ensureVisible(next);
      await tester.tap(next);
      await tester.pumpAndSettle();

      expect(find.byType(PinScreen), findsOneWidget);
    });
  }
}
