/// TPIX Wallet — หน้าโอนต้องไม่ยอมโอนเข้าสัญญาสเตคมาสเตอร์โหนดตรงๆ
///
/// NodeRegistryV2.receive() นับ TPIX ที่โอนเข้าเฉยๆ เป็นเงินบริจาคเข้ากองรางวัล
/// ไม่ใช่การสเตค และขอคืนไม่ได้ — ผู้ใช้ที่คิดว่า "โอนเข้าสัญญา = สเตค" ต้องโดนหยุดก่อนถาม PIN
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:tpix_wallet/core/locale_provider.dart';
import 'package:tpix_wallet/providers/wallet_provider.dart';
import 'package:tpix_wallet/screens/send_screen.dart';
import 'package:tpix_wallet/services/db_service.dart';
import 'package:tpix_wallet/services/masternode_service.dart';
import 'package:tpix_wallet/services/rpc_client.dart';
import 'package:tpix_wallet/services/wallet_service.dart';

import 'support/isolated_db.dart';
import 'support/test_theme.dart';

/// ที่อยู่ NodeRegistryV2 ที่ deploy จริง (checksum ตามที่เว็บ/explorer แสดง)
const _registry = '0x9c3662972921705FeFa9E9bF0d91190d7B514A2B';
const _someone = '0xcccc000000000000000000000000000000003333';

/// เชนปลอม: eth_getCode ตอบตาม [code] (null = error แบบ polygon-edge ของกระเป๋าธรรมดา)
RpcClient _chain({String? code, List<String>? asked}) => RpcClient(
      ['https://rpc.test'],
      timeout: const Duration(seconds: 2),
      httpClient: MockClient((req) async {
        final body = jsonDecode(req.body) as Map;
        if (body['method'] == 'eth_getCode') asked?.add((body['params'] as List).first as String);
        if (code == null) {
          return http.Response(
              jsonEncode({
                'jsonrpc': '2.0',
                'id': 1,
                'error': {'code': -32600, 'message': 'unable to fetch code'},
              }),
              200);
        }
        return http.Response(jsonEncode({'jsonrpc': '2.0', 'id': 1, 'result': code}), 200);
      }),
    );

Widget _harness(String address) => MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => WalletProvider()),
        ChangeNotifierProvider(create: (_) => LocaleProvider()),
      ],
      child: MaterialApp(theme: testTheme(), home: SendScreen(initialAddress: address)),
    );

Future<void> _openAndSend(WidgetTester tester, String address) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.runAsync(() async {
    await tester.pumpWidget(_harness(address));
    // ปล่อยให้คิวรีรายการโปรด (sqlite จริง) เดินจนจบ
    await Future<void>.delayed(const Duration(milliseconds: 300));
  });
  await tester.pump();
  // หัวข้อหน้าก็เขียน "ส่ง TPIX" — เลือกเฉพาะปุ่ม
  await tester.tap(find.widgetWithText(ElevatedButton, LocaleProvider().t('send.button')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  setUpAll(() => useIsolatedTestDb('send_registry_guard'));
  tearDownAll(() async => DbService.close());

  tearDown(() {
    RpcClient.overrideForChain(4289, null);
    MasterNodeService.resetVerifiedRegistries();
  });

  final l = LocaleProvider();

  test('ที่อยู่สัญญาที่ deploy จริงเป็นที่อยู่ checksum ที่ถูกต้อง (หน้าโอนรับรูปแบบนี้)', () {
    expect(WalletService.isValidAddress(_registry), isTrue);
  });

  testWidgets('โอนไปที่อยู่สัญญาสเตค → บล็อกพร้อมเหตุผล ไม่ยิง RPC ไม่ถาม PIN', (tester) async {
    final asked = <String>[];
    RpcClient.overrideForChain(4289, _chain(code: '0x6080', asked: asked));
    await _openAndSend(tester, _registry);

    expect(find.text(l.t('send.errRegistry')), findsOneWidget);
    expect(asked, isEmpty, reason: 'ที่อยู่ที่รู้จักแล้วต้องบล็อกได้แม้ออฟไลน์');
  });

  testWidgets('ที่อยู่ใหม่ที่โค้ดเป็น NodeRegistryV2 (redeploy) → บล็อกเหมือนกัน', (tester) async {
    // ไฟล์เดียวกับเทสต์ masternode_service_test — eth_getCode จริงของสัญญาที่ deploy แล้ว
    final liveCode =
        File('test/support/node_registry_v2_026f5f9.hex').readAsStringSync().trim();
    RpcClient.overrideForChain(4289, _chain(code: liveCode));
    await _openAndSend(tester, _someone);

    expect(find.text(l.t('send.errRegistry')), findsOneWidget);
  });

  testWidgets('กระเป๋าธรรมดา → ไม่โดนบล็อก (ไปต่อจนถึงเช็กจำนวน)', (tester) async {
    RpcClient.overrideForChain(4289, _chain());
    await _openAndSend(tester, _someone);

    expect(find.text(l.t('send.errRegistry')), findsNothing);
    expect(find.text(l.t('send.invalidAmount')), findsOneWidget);
  });
}
