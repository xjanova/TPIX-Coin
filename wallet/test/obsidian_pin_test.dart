/// TPIX Wallet — เทสต์ PIN / ยืนยันธุรกรรม ธีม Obsidian
///
/// ล็อกพฤติกรรมด้านความปลอดภัย (หน้าตาเปลี่ยน ด่านต้องเหมือนเดิม):
///   1. คืน true เฉพาะ PIN ถูกเท่านั้น · ปิดหน้า = false
///   2. PIN ผิด → ไม่ปิดหน้า บอก "PIN ไม่ถูกต้อง" ล้างจุด ให้ลองใหม่ (ทุกครั้งผ่าน wallet.unlock ที่นับครั้งผิด)
///   3. ล็อกชั่วคราวอยู่ → ไม่เรียก unlock เลย (ไม่เปิดช่องเดา PIN) และบอกเวลารอ
///   4. authorizeTransaction: Obsidian เปิดหน้าเต็มจอ · ธีมอื่นยังเป็นกล่องเดิม
///   5. ระหว่างตรวจ แป้นไม่รับการกด (ไม่ตรวจซ้อน)
///
/// Developed by Xman Studio
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:tpix_wallet/core/locale_provider.dart';
import 'package:tpix_wallet/core/themes/theme_bundle.dart';
import 'package:tpix_wallet/providers/wallet_provider.dart';
import 'package:tpix_wallet/screens/pin_screen.dart';
import 'package:tpix_wallet/widgets/obsidian/pin_pad.dart';
import 'package:tpix_wallet/widgets/tx_auth.dart';

import 'support/test_theme.dart';

class _Wallet extends WalletProvider {
  final attempts = <String>[];

  /// null = ตอบทันที · ไม่ null = ค้างจนกว่าจะ complete (ไว้ดูสถานะกำลังตรวจ)
  Completer<bool>? gate;

  @override
  Future<bool> unlock(String pin) {
    attempts.add(pin);
    return gate?.future ?? Future.value(pin == '123456');
  }
}

final _l = LocaleProvider();

Widget _host(_Wallet w, {ThemeId theme = ThemeId.obsidian, required void Function(BuildContext) onOpen}) =>
    MultiProvider(
      providers: [
        ChangeNotifierProvider<WalletProvider>.value(value: w),
        ChangeNotifierProvider(create: (_) => LocaleProvider()),
      ],
      child: MaterialApp(
        theme: testTheme(themeId: theme),
        home: Builder(
          builder: (ctx) => Scaffold(
            body: Center(child: TextButton(onPressed: () => onOpen(ctx), child: const Text('open'))),
          ),
        ),
      ),
    );

Future<void> _type(WidgetTester t, String digits) async {
  for (final d in digits.split('')) {
    await t.tap(find.descendant(of: find.byType(ObsidianKeypad), matching: find.text(d)));
    await t.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  group('authorizeTransaction (Obsidian)', () {
    testWidgets('PIN ผิด → อยู่หน้าเดิม ลองใหม่ได้ · PIN ถูก → true', (tester) async {
      final w = _Wallet();
      bool? result;
      await tester.pumpWidget(_host(w, onOpen: (ctx) async {
        result = await authorizeTransaction(ctx, reason: 'r', summary: const TxAuthSummary(title: 'ส่ง 5 TPIX'));
      }));
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(ObsidianPinVerifyPage), findsOneWidget);
      expect(find.text('ส่ง 5 TPIX'), findsOneWidget);
      expect(find.byType(ObsidianKeypad), findsOneWidget);
      // ไม่ได้เปิดสแกนนิ้ว → ไม่มีปุ่มสแกนนิ้ว
      expect(find.bySemanticsLabel(_l.t('obs.pin.bio')), findsNothing);

      await _type(tester, '111111');
      await tester.pump(const Duration(milliseconds: 100));
      expect(w.attempts, ['111111']);
      expect(find.byType(ObsidianPinVerifyPage), findsOneWidget, reason: 'PIN ผิดต้องไม่ปิดหน้าเงียบ ๆ');
      expect(find.text(_l.t('pin.wrong')), findsOneWidget);
      expect(tester.widget<ObsidianPinDots>(find.byType(ObsidianPinDots)).count, 0);
      expect(result, isNull);

      await _type(tester, '123456');
      await tester.pump(const Duration(milliseconds: 600));
      expect(w.attempts, ['111111', '123456']);
      expect(result, isTrue);
      expect(find.byType(ObsidianPinVerifyPage), findsNothing);
    });

    testWidgets('ปิดหน้า → false และไม่เคยเรียก unlock', (tester) async {
      final w = _Wallet();
      bool? result;
      await tester.pumpWidget(_host(w, onOpen: (ctx) async {
        result = await authorizeTransaction(ctx, reason: 'r');
      }));
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.bySemanticsLabel(_l.t('send.cancel')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(result, isFalse);
      expect(w.attempts, isEmpty);
    });

    testWidgets('ล็อกชั่วคราวอยู่ → ไม่เรียก unlock และบอกเวลารอ', (tester) async {
      final until = DateTime.now().add(const Duration(minutes: 5)).millisecondsSinceEpoch;
      FlutterSecureStorage.setMockInitialValues({'tpix_pin_lock_until': '$until'});
      final w = _Wallet();
      bool? result;
      await tester.pumpWidget(_host(w, onOpen: (ctx) async {
        result = await authorizeTransaction(ctx, reason: 'r');
      }));
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await _type(tester, '123456');
      await tester.pump(const Duration(milliseconds: 100));
      expect(w.attempts, isEmpty, reason: 'ระหว่างล็อกห้ามตรวจ PIN');
      expect(find.textContaining(_l.t('pin.locked').split('{s}').first), findsOneWidget);
      expect(result, isNull);
    });

    testWidgets('ระหว่างตรวจ แป้นไม่รับการกด (ไม่ตรวจซ้อน)', (tester) async {
      final w = _Wallet()..gate = Completer<bool>();
      await tester.pumpWidget(_host(w, onOpen: (ctx) => authorizeTransaction(ctx, reason: 'r')));
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await _type(tester, '123456');
      expect(tester.widget<ObsidianPinDots>(find.byType(ObsidianPinDots)).mode, PinDotsMode.busy);
      await _type(tester, '99');
      expect(w.attempts, ['123456']);
      w.gate!.complete(true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byType(ObsidianPinVerifyPage), findsNothing);
    });

    testWidgets('กดปิดระหว่างตรวจ แล้ว PIN ถูกทีหลัง → ไม่ปิดหน้าข้างใต้ทิ้ง', (tester) async {
      final w = _Wallet()..gate = Completer<bool>();
      bool? result;
      await tester.pumpWidget(_host(w, onOpen: (ctx) async {
        result = await authorizeTransaction(ctx, reason: 'r');
      }));
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await _type(tester, '123456');
      await tester.tap(find.bySemanticsLabel(_l.t('send.cancel')));
      await tester.pump();
      w.gate!.complete(true); // ตรวจเสร็จตอนหน้ากำลังเลื่อนปิด
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(result, isFalse);
      expect(find.text('open'), findsOneWidget, reason: 'หน้าเดิมข้างใต้ต้องยังอยู่');
    });

    testWidgets('ธีมอื่นยังเป็นกล่อง PIN เดิม', (tester) async {
      final w = _Wallet();
      await tester.pumpWidget(_host(w, theme: ThemeId.liquid, onOpen: (ctx) => authorizeTransaction(ctx, reason: 'r')));
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(PinVerifyDialog), findsOneWidget);
      expect(find.byType(ObsidianPinVerifyPage), findsNothing);
    });
  });

  group('PinScreen (Obsidian)', () {
    testWidgets('แป้นกระจก + จุดเติมตามที่กด + ลบได้', (tester) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<WalletProvider>.value(value: _Wallet()),
          ChangeNotifierProvider(create: (_) => LocaleProvider()),
        ],
        child: MaterialApp(theme: testTheme(themeId: ThemeId.obsidian), home: const PinScreen(isSetup: true)),
      ));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byType(ObsidianKeypad), findsOneWidget);
      expect(find.text(_l.t('pin.setup')), findsOneWidget);

      await _type(tester, '123');
      expect(tester.widget<ObsidianPinDots>(find.byType(ObsidianPinDots)).count, 3);
      await tester.tap(find.bySemanticsLabel(_l.t('obs.pin.delete')));
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.widget<ObsidianPinDots>(find.byType(ObsidianPinDots)).count, 2);

      // ครบ 6 หลักแรก → ไปขั้นยืนยัน PIN (ตรรกะเดิม)
      await _type(tester, '3456');
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text(_l.t('pin.confirm')), findsOneWidget);
      expect(tester.widget<ObsidianPinDots>(find.byType(ObsidianPinDots)).count, 0);
    });
  });
}
