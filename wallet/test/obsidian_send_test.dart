/// TPIX Wallet — เทสต์หน้าส่งธีม Obsidian
///
/// หน้าตาใหม่ ตรรกะเดิม — ล็อกว่าด่านเดิมยังทำงานผ่านหน้าใหม่:
///   1. ชิป % คำนวณแบบ BigInt (สูงสุด = ยอดเต็มทุกหลัก ไม่ปัดขึ้นเกินยอด)
///   2. ที่อยู่ถูก = เส้นยืนยัน + ชื่อรายการโปรด · ผิด = เตือนเฉพาะเมื่อพิมพ์ครบ/มีตัวที่ไม่ใช่ฐาน 16
///   3. โอนเข้าสัญญาสเตคมาสเตอร์โหนด → บล็อกก่อนถาม PIN (ด่านเดิม)
///   4. ช่องจำนวนไม่ใส่จุลภาคหลักพันเอง (Units.parse อ่าน "1,500" เป็น 1.5)
///   5. ธีมอื่นยังใช้หน้าเดิม
///
/// Developed by Xman Studio
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:tpix_wallet/core/locale_provider.dart';
import 'package:tpix_wallet/core/themes/theme_bundle.dart';
import 'package:tpix_wallet/models/contact.dart';
import 'package:tpix_wallet/providers/wallet_provider.dart';
import 'package:tpix_wallet/screens/send_screen.dart';
import 'package:tpix_wallet/services/db_service.dart';
import 'package:tpix_wallet/services/masternode_service.dart';
import 'package:tpix_wallet/services/rpc_client.dart';
import 'package:tpix_wallet/widgets/obsidian/obsidian.dart';
import 'package:tpix_wallet/widgets/tx_auth.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/isolated_db.dart';
import 'support/test_theme.dart';

const _alice = '0xaaaa000000000000000000000000000000001111';
const _registry = '0x9c3662972921705FeFa9E9bF0d91190d7B514A2B';

/// ยอด 1,234.567890123456789012 TPIX — เลขไม่กลม ไว้จับการปัดเศษ
final _balance = BigInt.parse('1234567890123456789012');

class _Wallet extends WalletProvider {
  @override
  String? get address => '0xd2ea4b1c9f3e7a8b5d6c0f2a1e9b8c7d4f3a67d7';
  @override
  BigInt? get balanceWei => _balance;
  @override
  double? get tpixPrice => 0.1;
}

final _l = LocaleProvider();

Widget _app({String? address, ThemeId theme = ThemeId.obsidian}) => MultiProvider(
      providers: [
        ChangeNotifierProvider<WalletProvider>(create: (_) => _Wallet()),
        ChangeNotifierProvider(create: (_) => LocaleProvider()),
      ],
      child: MaterialApp(theme: testTheme(themeId: theme), home: SendScreen(initialAddress: address)),
    );

Future<void> _open(WidgetTester tester, {String? address, ThemeId theme = ThemeId.obsidian}) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.runAsync(() async {
    await tester.pumpWidget(_app(address: address, theme: theme));
    await Future<void>.delayed(const Duration(milliseconds: 300));
  });
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

TextField _amountField(WidgetTester t) => t.widget<TextField>(find.byType(TextField).first);

RpcClient _plainChain() => RpcClient(
      ['https://rpc.test'],
      timeout: const Duration(seconds: 2),
      httpClient: MockClient((req) async => http.Response(
          jsonEncode({
            'jsonrpc': '2.0',
            'id': 1,
            'error': {'code': -32600, 'message': 'unable to fetch code'},
          }),
          200)),
    );

void main() {
  setUpAll(() => useIsolatedTestDb('obsidian_send'));
  tearDownAll(() async => DbService.close());

  setUp(() async {
    await DbService.close();
    await databaseFactory.deleteDatabase('${await databaseFactory.getDatabasesPath()}/tpix_wallet.db');
    await DbService.saveContact(const Contact(address: _alice, name: 'น้องเอ', createdAt: 1));
  });

  tearDown(() {
    RpcClient.overrideForChain(4289, null);
    MasterNodeService.resetVerifiedRegistries();
  });

  testWidgets('ชิป % คิดแบบ BigInt — สูงสุด = ยอดเต็มทุกหลัก', (tester) async {
    await _open(tester);
    expect(find.text(_l.t('obs.send.review')), findsOneWidget);

    await tester.tap(find.text('25%'));
    await tester.pump();
    expect(_amountField(tester).controller!.text, '308.641972530864197253');

    await tester.tap(find.text(_l.t('obs.send.max')));
    await tester.pump();
    expect(_amountField(tester).controller!.text, '1234.567890123456789012');
    expect(_amountField(tester).controller!.text.contains(','), isFalse,
        reason: 'ช่องกรอกห้ามมีจุลภาคหลักพัน (Units.parse จะอ่านเป็นทศนิยม)');
  });

  testWidgets('ที่อยู่ในรายการโปรด → เส้นยืนยันพร้อมชื่อ · ชิปทางลัดใส่ที่อยู่ได้', (tester) async {
    await _open(tester);
    expect(find.textContaining(_l.t('obs.send.valid')), findsNothing);

    await tester.tap(find.text('น้องเอ'));
    await tester.pump();
    expect(
      find.text(_l.t('obs.send.validMatch').replaceAll('{name}', 'น้องเอ')),
      findsOneWidget,
    );
  });

  testWidgets('ที่อยู่ผิด — เตือนเมื่อพิมพ์ครบหรือมีตัวแปลก ไม่เตือนระหว่างพิมพ์', (tester) async {
    await _open(tester);
    final addressField = find.byType(TextField).last;

    await tester.enterText(addressField, '0x12ab');
    await tester.pump();
    expect(find.text(_l.t('send.invalidAddress')), findsNothing);

    await tester.enterText(addressField, '0x12zz');
    await tester.pump();
    expect(find.text(_l.t('send.invalidAddress')), findsOneWidget);

    // checksum ผิด (ตัวพิมพ์ผสมผิด) ครบ 42 ตัว
    await tester.enterText(addressField, '0x9C3662972921705FeFa9E9bF0d91190d7B514A2B');
    await tester.pump();
    expect(find.text(_l.t('send.invalidAddress')), findsOneWidget);
  });

  testWidgets('โอนเข้าสัญญาสเตค → บล็อกก่อนถาม PIN (ด่านเดิม)', (tester) async {
    RpcClient.overrideForChain(4289, _plainChain());
    await _open(tester, address: _registry);
    await tester.enterText(find.byType(TextField).first, '10');
    await tester.tap(find.text(_l.t('obs.send.review')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text(_l.t('send.errRegistry')), findsOneWidget);
    expect(find.byType(ObsidianPinVerifyPage), findsNothing);
  });

  testWidgets('จำนวนเกินยอด → แจ้งยอดไม่พอ ไม่ถาม PIN', (tester) async {
    RpcClient.overrideForChain(4289, _plainChain());
    await _open(tester, address: _alice);
    await tester.enterText(find.byType(TextField).first, '1234.567890123456789013');
    await tester.tap(find.text(_l.t('obs.send.review')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text(_l.t('send.insufficientBalance')), findsOneWidget);
    expect(find.byType(ObsidianPinVerifyPage), findsNothing);
  });

  testWidgets('ธีมอื่นยังใช้หน้าเดิม', (tester) async {
    await _open(tester, theme: ThemeId.liquid);
    expect(find.text(_l.t('obs.send.review')), findsNothing);
    expect(find.byType(ObsidianButton), findsNothing);
    expect(find.text(_l.t('send.button')), findsWidgets);
  });
}
