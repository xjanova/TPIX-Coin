/// TPIX Wallet — เทสต์หน้าสวอปโหมด TPIX Chain (widget)
///
/// สิ่งที่ห้ามพัง:
///   - เปิดจากเชน TPIX → อยู่แท็บ TPIX Chain · มีเหรียญ TPIX/USDT · ราคา + ผลกระทบต่อราคาจาก router จริง
///   - กล่องยืนยันบอกค่าพูล 0.3% (ไม่มีธุรกรรมแยก) · ค่าแก๊ส 0 · เครือข่าย TPIX Chain · ยกเลิก = ไม่ส่ง
///   - ทะเบียนไม่พร้อม / ติดต่อไม่ได้ → ไม่มีฟอร์ม ไม่มีปุ่มส่ง (fail-closed) + เหตุผล + ปุ่มลองใหม่/ไป BSC
///   - impact เกิน 10% → ปุ่มบล็อก + บอกยอดสูงสุดที่สั่งได้ · แตะแล้วไม่มีกล่องยืนยัน
///   - ข้อความตามภาษาแอป (ไม่มี "Exception" ดิบ)
library;

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tpix_wallet/core/locale_provider.dart';
import 'package:tpix_wallet/providers/wallet_provider.dart';
import 'package:tpix_wallet/screens/swap_screen.dart';
import 'package:tpix_wallet/services/rpc_client.dart';
import 'package:tpix_wallet/services/tpix_dex_service.dart';
import 'package:tpix_wallet/services/wallet_auth_service.dart';

import 'support/fake_dex.dart';
import 'support/test_theme.dart';

Widget _harness(WalletProvider wallet, LocaleProvider locale) => MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: wallet),
        ChangeNotifierProvider.value(value: locale),
      ],
      child: MaterialApp(theme: testTheme(), home: const SwapScreen()),
    );

/// จอสูงพอให้ฟอร์มทั้งหน้าอยู่ในจอ (ไม่ต้องเลื่อนหาปุ่ม)
void _tallScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 4000);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// พิมพ์จำนวนแล้วรอพ้นช่วงหน่วง (500 ms) จนราคากลับมา
Future<void> _typeAmount(WidgetTester tester, String amount) async {
  await tester.enterText(find.byKey(const ValueKey('swap-amount')), amount);
  await tester.pump(const Duration(milliseconds: 600));
  await _settle(tester);
}

String _buttonText(WidgetTester tester) => tester
    .widget<Text>(find.descendant(of: find.byKey(const ValueKey('tpix-swap-button')), matching: find.byType(Text)))
    .data!;

void main() {
  late FakeDexSite site;
  late FakeDexChain chain;
  late LocaleProvider l;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    TpixDexService.resetCache();
    site = FakeDexSite();
    chain = FakeDexChain();
    TpixDexService.clientFactory = site.client;
    WalletAuthService.clientFactory = site.client;
    RpcClient.overrideForChain(4289, chain.rpc.client);
    l = LocaleProvider(); // ภาษาเริ่มต้นของแอป (ไทย)
  });

  tearDown(() {
    TpixDexService.clientFactory = http.Client.new;
    WalletAuthService.clientFactory = http.Client.new;
    RpcClient.overrideForChain(4289, null);
  });

  Future<WalletProvider> unlockedWallet() async {
    final wallet = WalletProvider();
    await wallet.importFromPrivateKey('0x${'4c' * 32}');
    return wallet;
  }

  testWidgets('เปิดจากเชน TPIX → แท็บ TPIX Chain · TPIX → USDT · ราคา/ผลกระทบจาก router · ยกเลิก = ไม่ส่ง',
      (tester) async {
    _tallScreen(tester);
    final wallet = await unlockedWallet();
    await tester.pumpWidget(_harness(wallet, l));
    await _settle(tester);

    expect(find.byKey(const ValueKey('swap-chain-4289')), findsOneWidget);
    expect(find.byKey(const ValueKey('swap-chain-56')), findsOneWidget);
    expect(find.byKey(const ValueKey('swap-amount')), findsOneWidget);
    expect(find.text('TPIX'), findsWidgets);
    expect(find.text('USDT'), findsOneWidget);
    expect(_buttonText(tester), l.t('swap.enterAmount'));

    await _typeAmount(tester, '1000');
    expect(tester.widget<Text>(find.byKey(const ValueKey('swap-amount-out'))).data, '99.600698');
    expect(tester.widget<Text>(find.byKey(const ValueKey('tpix-impact'))).data, '0.40%');
    expect(find.text(l.t('swap.tpix.poolFeeValue')), findsOneWidget);
    expect(find.text(l.t('swap.tpix.gasFeeValue')), findsOneWidget);
    expect(find.text('TPIX → USDT'), findsOneWidget);
    expect(_buttonText(tester), l.t('swap.button'));

    await tester.tap(find.byKey(const ValueKey('tpix-swap-button')));
    await _settle(tester);
    expect(find.text(l.t('swap.confirmTitle')), findsOneWidget);
    expect(find.text('1000 TPIX'), findsOneWidget);
    expect(find.text('99.600698 USDT'), findsWidgets);
    expect(find.text('TPIX Chain'), findsWidgets);

    await tester.tap(find.text(l.t('send.cancel')));
    await _settle(tester);
    expect(find.text(l.t('swap.confirmTitle')), findsNothing);
    expect(chain.calls, isNot(contains('eth_sendRawTransaction')));
  });

  testWidgets('ทะเบียนไม่พร้อม → ไม่มีฟอร์ม ไม่มีปุ่มส่ง + เหตุผล · ไป BSC ได้ในแตะเดียว', (tester) async {
    _tallScreen(tester);
    site.config = dexConfig(ready: false);
    final wallet = await unlockedWallet();
    await tester.pumpWidget(_harness(wallet, l));
    await _settle(tester);

    expect(find.byKey(const ValueKey('tpix-swap-closed')), findsOneWidget);
    expect(find.text(l.t('swap.tpix.unavailable')), findsOneWidget);
    expect(find.text(l.t('swap.tpix.unavailableBody')), findsOneWidget);
    expect(find.byKey(const ValueKey('swap-amount')), findsNothing);
    expect(find.byKey(const ValueKey('tpix-swap-button')), findsNothing);
    expect(chain.calls, isEmpty, reason: 'ทะเบียนไม่พร้อม = ไม่แตะเชน');

    await tester.tap(find.byKey(const ValueKey('tpix-use-bsc')));
    await _settle(tester);
    expect(find.byKey(const ValueKey('tpix-swap-closed')), findsNothing);
    expect(find.byKey(const ValueKey('swap-amount')), findsOneWidget);
    expect(find.text('BNB'), findsWidgets);
  });

  testWidgets('ติดต่อเว็บไม่ได้ (Cloudflare ตอบ HTML) → ข้อความ + ลองใหม่ที่โหลดใหม่จริง', (tester) async {
    _tallScreen(tester);
    site.down = true;
    final wallet = await unlockedWallet();
    await tester.pumpWidget(_harness(wallet, l));
    await _settle(tester);

    expect(find.text(l.t('swap.tpix.unreachable')), findsOneWidget);
    expect(find.textContaining('Exception'), findsNothing);

    site.down = false;
    await tester.tap(find.byKey(const ValueKey('tpix-retry')));
    await _settle(tester);
    expect(find.byKey(const ValueKey('tpix-swap-closed')), findsNothing);
    expect(find.byKey(const ValueKey('swap-amount')), findsOneWidget);
  });

  testWidgets('impact เกิน 10% → ปุ่มบล็อก + ยอดสูงสุดที่สั่งได้ · แตะแล้วไม่มีกล่องยืนยัน', (tester) async {
    _tallScreen(tester);
    chain.nativeBalance = BigInt.from(300000) * e18;
    final wallet = await unlockedWallet();
    await tester.pumpWidget(_harness(wallet, l));
    await _settle(tester);

    await _typeAmount(tester, '200000');
    expect(_buttonText(tester), l.t('swap.tpix.impactTooHighButton'));
    expect(find.byKey(const ValueKey('tpix-max-hint')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('tpix-swap-button')));
    await _settle(tester);
    expect(find.text(l.t('swap.confirmTitle')), findsNothing);
    expect(chain.calls, isNot(contains('eth_sendRawTransaction')));
  });

  testWidgets('ภาษาอังกฤษ: ไม่มีภาษาไทยโผล่ในโหมด TPIX + จ่าย USDT ต้องอนุมัติก่อน', (tester) async {
    _tallScreen(tester);
    await l.setLocale('en');
    chain.tokenBalances[dexUsdt] = BigInt.from(50) * e6;
    final wallet = await unlockedWallet();
    await tester.pumpWidget(_harness(wallet, l));
    await _settle(tester);

    await tester.tap(find.byKey(const ValueKey('swap-flip')));
    await _settle(tester);
    await _typeAmount(tester, '25');
    expect(_buttonText(tester), '${l.t('swap.approve')} USDT');
    expect(find.text(l.t('swap.tpix.approveNote')), findsOneWidget);
    expect(find.textContaining(RegExp(r'[฀-๿]')), findsNothing);
  });
}
