/// TPIX Wallet — เทสต์หน้ามาสเตอร์โหนด (สถานะที่ไม่มีปุ่มเขียน)
///
/// ต้องไม่มีทางกดสเตคได้เมื่อ: เว็บยังไม่ประกาศสัญญา / ติดต่อเว็บไม่ได้
/// และกรณีติดต่อไม่ได้ต้องมีปุ่มลองใหม่ ไม่ใช่หน้าว่างหรือ Exception ดิบ
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tpix_wallet/core/locale_provider.dart';
import 'package:tpix_wallet/providers/wallet_provider.dart';
import 'package:tpix_wallet/screens/masternode_screen.dart';
import 'package:tpix_wallet/services/masternode_service.dart';
import 'package:tpix_wallet/services/price_service.dart';

import 'support/test_theme.dart';

Widget _harness() => MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => WalletProvider()),
        ChangeNotifierProvider(create: (_) => LocaleProvider()),
      ],
      child: MaterialApp(theme: testTheme(), home: const MasterNodeScreen()),
    );

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // หน้านี้สั่งรีเฟรชยอด (+ราคา) — ห้ามยิงเน็ตจริงในเทสต์
    PriceService.clientFactory = () => MockClient((_) async => http.Response('', 503));
  });

  tearDown(() {
    MasterNodeService.clientFactory = http.Client.new;
    PriceService.clientFactory = http.Client.new;
    PriceService.reset();
  });

  testWidgets('เว็บยังไม่มีสัญญา → การ์ด "ยังไม่เปิด" ไม่มีปุ่มสเตค', (tester) async {
    MasterNodeService.clientFactory =
        () => MockClient((_) async => http.Response('Not Found', 404));
    await tester.pumpWidget(_harness());
    await tester.pump(); // post-frame → เริ่มโหลด
    await tester.pump(const Duration(milliseconds: 50));

    final l = LocaleProvider();
    expect(find.text(l.t('mn.notDeployedTitle')), findsOneWidget);
    expect(find.text(l.t('mn.openWebsite')), findsOneWidget);
    expect(find.text(l.t('mn.stakeButton')), findsNothing);
  });

  testWidgets('ติดต่อเว็บไม่ได้ → ข้อความเครือข่าย + ปุ่มลองใหม่ (ลองแล้วโหลดใหม่จริง)',
      (tester) async {
    var calls = 0;
    MasterNodeService.clientFactory = () => MockClient((_) async {
          calls++;
          return http.Response('<!DOCTYPE html><html></html>', 200);
        });
    await tester.pumpWidget(_harness());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final l = LocaleProvider();
    expect(find.text(l.t('mn.errNetwork')), findsOneWidget);
    expect(find.text(l.t('mn.stakeButton')), findsNothing);
    expect(calls, 1);

    await tester.tap(find.text(l.t('mn.retry')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(calls, 2);
    expect(find.text(l.t('mn.errNetwork')), findsOneWidget);
  });
}
