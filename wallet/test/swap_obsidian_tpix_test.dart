/// TPIX Wallet — เทสต์แท็บ TPIX Chain บนหน้าแลกธีม Obsidian (ธีมเริ่มต้นของแอป)
///
/// สิ่งที่ห้ามพัง (ชุดเดียวกับ swap_screen_tpix_test.dart แต่บนหน้าตา Obsidian):
///   - เปิดจากเชน TPIX → แท็บ TPIX Chain · TPIX → USDT · ราคา/ผลกระทบจาก router จริง
///   - แผ่นยืนยันบอกค่าพูล 0.3% · ค่าแก๊ส 0 · เครือข่าย TPIX Chain · ยกเลิก = ไม่ส่ง
///   - ทะเบียนไม่พร้อม → ไม่มีฟอร์ม ไม่มีปุ่มส่ง (fail-closed) + เหตุผล + ไป BSC ได้
///   - impact เกิน 10% → ปุ่มปิด + บอกยอดสูงสุดที่สั่งได้ · แตะแล้วไม่มีแผ่นยืนยัน
///   - ภาษาอังกฤษไม่มีภาษาไทยโผล่ · จ่าย USDT ต้องอนุมัติก่อน (อนุมัติเฉพาะจำนวนนี้)
library;

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tpix_wallet/core/locale_provider.dart';
import 'package:tpix_wallet/core/themes/theme_bundle.dart';
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
      child: MaterialApp(theme: testTheme(themeId: ThemeId.obsidian), home: const SwapScreen()),
    );

/// จอสูงพอให้ฟอร์มและปุ่มด้านล่างอยู่ในจอ (ไม่งั้น tap พลาดเป้าแล้วเทสต์ผ่านแบบหลอก ๆ)
void _tallScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 4400);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
}

/// หน้านี้มีตัวนับถอยหลังทุก 1 วิ → pumpAndSettle ไม่มีวันนิ่ง ใช้ pump เป็นช่วงแทน
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// พิมพ์จำนวนแล้วรอพ้นช่วงหน่วง (500 ms) จนราคากลับมา
Future<void> _typeAmount(WidgetTester tester, String amount) async {
  await tester.enterText(find.byKey(const ValueKey('obs-swap-amount')), amount);
  await tester.pump(const Duration(milliseconds: 600));
  await _settle(tester);
}

final _cta = find.byKey(const ValueKey('obs-swap-cta'));

String _ctaText(WidgetTester tester) =>
    tester.widget<Text>(find.descendant(of: _cta, matching: find.byType(Text)).first).data!;

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

  testWidgets('เปิดจากเชน TPIX → แท็บ TPIX · ราคา/ผลกระทบจาก router · แผ่นยืนยันครบ · ยกเลิก = ไม่ส่ง',
      (tester) async {
    _tallScreen(tester);
    final wallet = await unlockedWallet();
    await tester.pumpWidget(_harness(wallet, l));
    await _settle(tester);

    expect(find.byKey(const ValueKey('obs-swap-amount')), findsOneWidget);
    expect(find.text('TPIX'), findsWidgets);
    expect(find.text('USDT'), findsWidgets);
    expect(_ctaText(tester), l.t('swap.enterAmount'));

    await _typeAmount(tester, '1000');
    expect(tester.widget<Text>(find.byKey(const ValueKey('obs-swap-amount-out'))).data, '99.600698');
    expect(find.descendant(of: find.byKey(const ValueKey('tpix-impact')), matching: find.text('0.40%')), findsOneWidget);
    expect(find.text(l.t('swap.tpix.poolFeeValue')), findsOneWidget);
    expect(find.text(l.t('swap.tpix.gasFeeValue')), findsOneWidget);
    expect(find.text('TPIX Chain'), findsWidgets);
    expect(_ctaText(tester), l.t('obs.swap.cta').replaceAll('{from}', 'TPIX').replaceAll('{to}', 'USDT'));

    await tester.tap(_cta);
    await _settle(tester);
    expect(find.text(l.t('swap.confirmTitle')), findsOneWidget);
    expect(find.text('1000 TPIX'), findsOneWidget);
    expect(find.text('99.600698 USDT'), findsOneWidget);
    expect(find.text('TPIX → USDT'), findsOneWidget);

    await tester.tap(find.text(l.t('send.cancel')).last);
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
    expect(find.byKey(const ValueKey('obs-swap-amount')), findsNothing);
    expect(_cta, findsNothing);
    expect(chain.calls, isEmpty, reason: 'ทะเบียนไม่พร้อม = ไม่แตะเชน');

    await tester.tap(find.byKey(const ValueKey('tpix-use-bsc')));
    await _settle(tester);
    expect(find.byKey(const ValueKey('tpix-swap-closed')), findsNothing);
    expect(find.byKey(const ValueKey('obs-swap-amount')), findsOneWidget);
    expect(find.text('BNB'), findsWidgets);
  });

  testWidgets('impact เกิน 10% → ปุ่มปิด + ยอดสูงสุดที่สั่งได้ · แตะแล้วไม่มีแผ่นยืนยัน', (tester) async {
    _tallScreen(tester);
    chain.nativeBalance = BigInt.from(300000) * e18;
    final wallet = await unlockedWallet();
    await tester.pumpWidget(_harness(wallet, l));
    await _settle(tester);

    await _typeAmount(tester, '200000');
    expect(_ctaText(tester), l.t('swap.tpix.impactTooHighButton'));
    expect(find.byKey(const ValueKey('tpix-max-hint')), findsOneWidget);

    await tester.tap(_cta);
    await _settle(tester);
    expect(find.text(l.t('swap.confirmTitle')), findsNothing);
    expect(chain.calls, isNot(contains('eth_sendRawTransaction')));
  });

  testWidgets('MAX ใช้ยอดเต็มแบบตรงตัว (เชน TPIX ไม่มีค่าแก๊ส)', (tester) async {
    _tallScreen(tester);
    chain.nativeBalance = BigInt.parse('1234567890123456789'); // 1.234567890123456789 TPIX
    final wallet = await unlockedWallet();
    await tester.pumpWidget(_harness(wallet, l));
    await _settle(tester);

    await tester.tap(find.byKey(const ValueKey('obs-swap-max')));
    await tester.pump(const Duration(milliseconds: 600));
    await _settle(tester);
    final field = tester.widget<TextField>(find.byKey(const ValueKey('obs-swap-amount')));
    expect(field.controller!.text, '1.234567890123456789');
  });

  testWidgets('ภาษาอังกฤษ: ไม่มีภาษาไทยโผล่ + จ่าย USDT ต้องอนุมัติก่อน', (tester) async {
    _tallScreen(tester);
    await l.setLocale('en');
    chain.tokenBalances[dexUsdt] = BigInt.from(50) * e6;
    final wallet = await unlockedWallet();
    await tester.pumpWidget(_harness(wallet, l));
    await _settle(tester);

    await tester.tap(find.byKey(const ValueKey('obs-swap-flip')));
    await _settle(tester);
    await _typeAmount(tester, '25');
    expect(_ctaText(tester), l.t('obs.swap.approveCta').replaceAll('{symbol}', 'USDT'));
    expect(find.text(l.t('swap.tpix.approveNote')), findsOneWidget);
    expect(find.textContaining(RegExp(r'[฀-๿]')), findsNothing);
  });
}
