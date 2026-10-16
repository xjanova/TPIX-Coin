/// TPIX Wallet — เทสต์หน้าส่งเมื่อเปิดจากคำขอชำระเงินของร้าน (EIP-681)
///
///   1. เติมผู้รับ + ยอดเป๊ะทุกหลัก (ไม่ปัด) แล้วล็อกช่องยอด · ปุ่ม % ใช้ไม่ได้
///   2. "แก้ยอดเอง" ปลดล็อก · "ใช้ยอดของร้าน" คืนยอดเดิมแล้วล็อกกลับ
///   3. เปลี่ยนผู้รับไปจากที่ร้านขอ = เลิกใช้คำขอ (ปลดล็อก ซ่อนแถบ)
///   4. คำขอบนเชนอื่น → เตือน ไม่เติมอะไรเลย
///   5. ธีมเดิม (ไม่ใช่ Obsidian) ล็อกเหมือนกัน
///
/// Developed by Xman Studio
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tpix_wallet/core/locale_provider.dart';
import 'package:tpix_wallet/core/themes/theme_bundle.dart';
import 'package:tpix_wallet/providers/wallet_provider.dart';
import 'package:tpix_wallet/screens/send_screen.dart';
import 'package:tpix_wallet/services/db_service.dart';
import 'package:tpix_wallet/utils/eip681.dart';

import 'support/isolated_db.dart';
import 'support/test_theme.dart';

const _shop = '0x0A4Ee87551eF041f3EecFBBfdcfFC1B46a4878f1';
const _other = '0xaaaa000000000000000000000000000000001111';

class _Wallet extends WalletProvider {
  @override
  String? get address => '0xd2ea4b1c9f3e7a8b5d6c0f2a1e9b8c7d4f3a67d7';
  @override
  BigInt? get balanceWei => BigInt.parse('1234567890123456789012');
  @override
  double? get tpixPrice => 0.1;
}

final _l = LocaleProvider();

PaymentRequest _req(String uri) => Eip681.parse(uri).request!;

Future<void> _open(WidgetTester tester, PaymentRequest request, {ThemeId theme = ThemeId.obsidian}) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.runAsync(() async {
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<WalletProvider>(create: (_) => _Wallet()),
        ChangeNotifierProvider(create: (_) => LocaleProvider()),
      ],
      child: MaterialApp(theme: testTheme(themeId: theme), home: SendScreen(initialRequest: request)),
    ));
    await Future<void>.delayed(const Duration(milliseconds: 300));
  });
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

TextField _amountField(WidgetTester t, {bool obsidian = true}) =>
    t.widget<TextField>(find.byType(TextField).at(obsidian ? 0 : 1));
TextField _addressField(WidgetTester t, {bool obsidian = true}) =>
    t.widget<TextField>(find.byType(TextField).at(obsidian ? 1 : 0));

void main() {
  setUpAll(() async {
    await useIsolatedTestDb('send_payment_request');
    // เสียงกด (SynthService) ขอโฟลเดอร์ชั่วคราวผ่าน plugin ที่เทสต์ไม่มี → ให้รอไปเรื่อย ๆ = ไม่เล่นเสียง
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) => Completer<Object?>().future,
    );
  });
  tearDownAll(() async => DbService.close());

  setUp(() async {
    await DbService.close();
    await databaseFactory.deleteDatabase('${await databaseFactory.getDatabasesPath()}/tpix_wallet.db');
  });

  testWidgets('เติมผู้รับ + ยอดเป๊ะทุกหลัก แล้วล็อกช่องยอด', (tester) async {
    await _open(tester, _req('ethereum:$_shop@4289?value=150000000123456781'));
    expect(_addressField(tester).controller!.text, _shop);
    expect(_amountField(tester).controller!.text, '0.150000000123456781');
    expect(_amountField(tester).readOnly, isTrue);
    expect(find.text(_l.t('pay.requestTitle')), findsOneWidget);
    expect(find.text(_l.t('pay.requestLocked')), findsOneWidget);

    // ปุ่ม % ห้ามทับยอดของร้าน
    await tester.tap(find.text('25%'));
    await tester.pump();
    expect(_amountField(tester).controller!.text, '0.150000000123456781');
  });

  testWidgets('ยอดแบบวิทยาศาสตร์ — 1.5e18 = 1.5 TPIX', (tester) async {
    await _open(tester, _req('ethereum:$_shop@4289?value=1.5e18'));
    expect(_amountField(tester).controller!.text, '1.5');
  });

  testWidgets('แก้ยอดเอง → ปลดล็อก · ใช้ยอดของร้าน → คืนยอดแล้วล็อกกลับ', (tester) async {
    await _open(tester, _req('ethereum:$_shop@4289?value=150000000123456781'));
    await tester.ensureVisible(find.text(_l.t('pay.unlock')));
    await tester.tap(find.text(_l.t('pay.unlock')));
    await tester.pump();
    expect(_amountField(tester).readOnly, isFalse);
    expect(find.text(_l.t('pay.requestUnlocked')), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '0.15');
    await tester.pump();
    await tester.ensureVisible(find.text(_l.t('pay.restore')));
    await tester.tap(find.text(_l.t('pay.restore')));
    await tester.pump();
    expect(_amountField(tester).controller!.text, '0.150000000123456781');
    expect(_amountField(tester).readOnly, isTrue);
  });

  testWidgets('เปลี่ยนผู้รับไปจากที่ร้านขอ → เลิกใช้คำขอ ปลดล็อก ซ่อนแถบ', (tester) async {
    await _open(tester, _req('ethereum:$_shop@4289?value=150000000123456781'));
    await tester.enterText(find.byType(TextField).last, _other);
    await tester.pump();
    expect(_amountField(tester).readOnly, isFalse);
    expect(find.text(_l.t('pay.requestTitle')), findsNothing);
  });

  testWidgets('คำขอบน BSC → เตือน ไม่เติมอะไรเลย', (tester) async {
    await _open(tester, _req('ethereum:$_shop@56?value=1'));
    expect(_addressField(tester).controller!.text, isEmpty);
    expect(_amountField(tester).controller!.text, isEmpty);
    expect(find.textContaining('BNB'), findsWidgets);
    expect(find.text(_l.t('pay.requestTitle')), findsNothing);
  });

  testWidgets('คำขอที่ไม่มียอด → เติมผู้รับอย่างเดียว ไม่ล็อก', (tester) async {
    await _open(tester, _req('ethereum:$_shop@4289'));
    expect(_addressField(tester).controller!.text, _shop);
    expect(_amountField(tester).readOnly, isFalse);
    expect(find.text(_l.t('pay.requestTitle')), findsNothing);
  });

  testWidgets('ธีมเดิมล็อกช่องยอดเหมือนกัน', (tester) async {
    await _open(tester, _req('ethereum:$_shop@4289?value=150000000123456781'), theme: ThemeId.liquid);
    expect(_addressField(tester, obsidian: false).controller!.text, _shop);
    expect(_amountField(tester, obsidian: false).controller!.text, '0.150000000123456781');
    expect(_amountField(tester, obsidian: false).readOnly, isTrue);
    expect(find.text(_l.t('pay.requestTitle')), findsOneWidget);
  });

  test('คีย์ pay.* ที่หน้าส่ง/หน้าแรกใช้ มีทั้ง th และ en', () {
    final locale = File('lib/core/locale_provider.dart').readAsStringSync();
    final keys = <String>{
      for (final f in const ['lib/screens/send_screen.dart', 'lib/screens/send_obsidian.dart'])
        ...RegExp(r"'(pay\.[A-Za-z]+)'").allMatches(File(f).readAsStringSync()).map((m) => m.group(1)!),
    };
    expect(keys.length, greaterThanOrEqualTo(10));
    final missing = [
      for (final k in keys)
        if (RegExp("'${RegExp.escape(k)}':").allMatches(locale).length != 2) k,
    ];
    expect(missing, isEmpty);
  });
}
