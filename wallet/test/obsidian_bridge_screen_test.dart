/// TPIX Wallet — หน้าสะพานธีม Obsidian (widget)
///
/// หน้าตาใหม่ต้องรักษากฎเดิมทุกข้อของ bridge_screen_test.dart:
///   - สะพานปิด / ตั้งค่าไม่ครบ → ไม่มีช่องกรอก ไม่มีปุ่มส่ง (fail-closed) + บอกเหตุผล
///   - โหลดไม่ได้ → ข้อความ + ปุ่มลองใหม่ที่โหลดใหม่จริง
///   - ปุ่มส่งกดได้เมื่อจำนวนผ่าน + ติ๊กยอมรับเท่านั้น · แตะเบิ้ล = ตรวจครั้งเดียว · ยกเลิกในกล่องยืนยัน = ไม่ส่ง
///   - ที่อยู่ปลายทางผิด checksum → บอกทันที กดถอนไม่ได้
/// และของใหม่:
///   - รายการที่ติดตามโชว์เป็นขั้นตอนจากสถานะจริง (จำนวนบล็อก) · ลบต้องยืนยันก่อน
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tpix_wallet/core/locale_provider.dart';
import 'package:tpix_wallet/core/themes/theme_bundle.dart';
import 'package:tpix_wallet/providers/wallet_provider.dart';
import 'package:tpix_wallet/screens/bridge_screen.dart';
import 'package:tpix_wallet/services/bridge_service.dart';
import 'package:tpix_wallet/services/rpc_client.dart';
import 'package:tpix_wallet/widgets/obsidian/obsidian.dart';

import 'support/fake_rpc.dart';
import 'support/test_theme.dart';

const _vault = '0xf46131c82819d7621163f482b3fe88a228a7807c';
const _bscUsdt = '0x55d398326f99059fF775485246999027B3197955';
final _e18 = BigInt.from(10).pow(18);

Map<String, dynamic> _usdtInfo({bool enabled = true, bool installed = true, String vault = _vault}) => {
      'enabled': enabled,
      'installed': installed,
      'vault_address': vault,
      'tpix': {'chain_id': 4289, 'usdt_tpix': '0x0a4ee87551ef041f3eecfbbfdcffc1b46a4878f1', 'usdt_decimals': 6, 'explorer': 'https://explorer.tpix.online'},
      'chains': [
        {'chain_id': 56, 'name': 'BNB Smart Chain', 'native': 'BNB', 'enabled': true, 'usdt_address': _bscUsdt, 'usdt_decimals': 18, 'usdt_symbol': 'USDT', 'explorer': 'https://bscscan.com', 'withdraw_fee': '0.3', 'eta_minutes': 2},
      ],
      'limits': {'min_deposit': '1', 'max_deposit_per_tx': '1000', 'max_deposit_per_address_daily': '2000', 'min_withdraw': '2', 'max_withdraw_per_tx': '1000'},
    };

Map<String, dynamic> _wtpixInfo() => {
      'asset': 'tpix',
      'enabled': false,
      'installed': false,
      'tpix': {'chain_id': 4289, 'vault_address': null, 'explorer': 'https://explorer.tpix.online', 'eta_minutes': 3},
      'bsc': {'chain_id': 56, 'name': 'BNB Smart Chain', 'wtpix_address': null, 'minter_address': null, 'explorer': 'https://bscscan.com', 'eta_minutes': 2},
      'token': {'symbol': 'wTPIX', 'decimals': 18},
      'limits': {'min_lock': '10', 'lock_fee': '1'},
      'vault': {},
      'minter': {},
    };

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: const {'content-type': 'application/json; charset=utf-8'});

class _FakeSite {
  Map<String, dynamic> usdt = _usdtInfo();
  bool down = false;
  int infoCalls = 0;

  http.Client client() => MockClient((req) async {
        if (req.url.path.endsWith('/info')) {
          infoCalls++;
          if (down) return http.Response('<!DOCTYPE html><html>Cloudflare</html>', 200);
          return _json({'success': true, 'data': req.url.queryParameters['asset'] == 'tpix' ? _wtpixInfo() : usdt});
        }
        if (req.url.path.contains('/history/')) {
          return _json({'success': true, 'data': {'deposits': [], 'withdrawals': [], 'transfers': []}});
        }
        return _json({'success': false}, 404);
      });
}

Widget _harness(WalletProvider wallet) => MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: wallet),
        ChangeNotifierProvider(create: (_) => LocaleProvider()),
      ],
      child: MaterialApp(theme: testTheme(themeId: ThemeId.obsidian), home: const BridgeScreen()),
    );

/// จอสูงมากพอให้ฟอร์ม + ปุ่มติดขอบล่างอยู่ในจอทั้งหมด
void _tallScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 7000);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

ObsidianButton _button(WidgetTester tester, String key) => tester.widget<ObsidianButton>(find.byKey(ValueKey(key)));

void main() {
  late _FakeSite site;
  late FakeRpc bsc;
  late FakeRpc tpix;
  final l = LocaleProvider();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    site = _FakeSite();
    BridgeService.clientFactory = site.client;
    bsc = FakeRpc({
      'eth_chainId': (_) => '0x38',
      'eth_call': FakeRpc.ethCall({
        selDecimals: (to, data) => abiUint(BigInt.from(18)),
        selBalanceOf: (to, data) => abiUint(BigInt.from(100) * _e18),
      }),
      'eth_estimateGas': (_) => '0xc350',
      'eth_gasPrice': (_) => hexQty(BigInt.from(1000000000)),
      'eth_getBalance': (_) => hexQty(_e18),
    });
    tpix = FakeRpc({
      'eth_chainId': (_) => '0x10c1',
      'eth_call': FakeRpc.ethCall({selBalanceOf: (to, data) => abiUint(BigInt.from(50000000))}),
      'eth_getBalance': (_) => hexQty(BigInt.from(1000) * _e18),
    });
    RpcClient.overrideForChain(56, bsc.client);
    RpcClient.overrideForChain(4289, tpix.client);
  });

  tearDown(() {
    BridgeService.clientFactory = http.Client.new;
    RpcClient.overrideForChain(56, null);
    RpcClient.overrideForChain(4289, null);
  });

  Future<WalletProvider> unlockedWallet() async {
    final wallet = WalletProvider();
    await wallet.importFromPrivateKey('0x${'4c' * 32}');
    return wallet;
  }

  testWidgets('สะพานยังไม่เปิด (ค่าจริงตอนนี้) → การ์ดสถานะ ไม่มีช่องกรอก ไม่มีปุ่มส่ง', (tester) async {
    site.usdt = _usdtInfo(enabled: false, installed: false);
    await tester.pumpWidget(_harness(WalletProvider()));
    await _settle(tester);

    expect(find.byKey(const ValueKey('usdt-closed')), findsOneWidget);
    expect(find.text(l.t('bridge.notReady')), findsOneWidget);
    expect(find.text(l.t('bridge.notReadyBody')), findsOneWidget);
    expect(find.text(l.t('obs.bridge.closedPill')), findsOneWidget);
    expect(find.byType(TextField), findsNothing, reason: 'ไม่มีช่องกรอกจำนวน');
    expect(find.byKey(const ValueKey('usdt-deposit-button')), findsNothing);
    expect(find.byKey(const ValueKey('usdt-withdraw-button')), findsNothing);
    expect(find.byType(ObsidianRouteCard), findsOneWidget, reason: 'เส้นทางตัวอย่าง (จุดแสงหยุดนิ่ง)');
    expect(tester.widget<ObsidianRouteCard>(find.byType(ObsidianRouteCard)).flowing, isFalse);
  });

  testWidgets('หยุดชั่วคราว (ติดตั้งแล้ว) → ป้าย "หยุดชั่วคราว" + เหตุผล', (tester) async {
    site.usdt = _usdtInfo(enabled: false, installed: true);
    await tester.pumpWidget(_harness(WalletProvider()));
    await _settle(tester);
    expect(find.text(l.t('obs.bridge.pausedPill')), findsOneWidget);
    expect(find.text(l.t('bridge.pausedBody')), findsOneWidget);
  });

  testWidgets('เว็บบอกเปิด แต่ vault เป็นศูนย์ → ปิดไว้ (fail-closed) พร้อมเหตุผล', (tester) async {
    site.usdt = _usdtInfo(vault: '0x0000000000000000000000000000000000000000');
    await tester.pumpWidget(_harness(WalletProvider()));
    await _settle(tester);

    expect(find.byKey(const ValueKey('usdt-closed')), findsOneWidget);
    expect(find.text(l.t('bridge.misconfiguredBody')), findsOneWidget);
    expect(find.text(l.t('obs.bridge.lockedPill')), findsOneWidget);
    expect(find.byKey(const ValueKey('usdt-deposit-button')), findsNothing);
  });

  testWidgets('โหลดไม่ได้ → ข้อความ + ปุ่มลองใหม่ที่โหลดใหม่จริง', (tester) async {
    site.down = true;
    await tester.pumpWidget(_harness(WalletProvider()));
    await _settle(tester);

    expect(find.text(l.t('bridge.loadFailed')), findsOneWidget);
    expect(find.textContaining('Exception'), findsNothing);
    expect(site.infoCalls, 1);

    site.down = false;
    await tester.tap(find.text(l.t('bridge.retry')));
    await _settle(tester);
    expect(site.infoCalls, 2);
    expect(find.byKey(const ValueKey('usdt-deposit-button')), findsOneWidget);
  });

  testWidgets('สลับไปสะพาน wTPIX ที่ยังไม่เปิด → การ์ดสถานะของ wTPIX ไม่มีปุ่มล็อก', (tester) async {
    await tester.pumpWidget(_harness(WalletProvider()));
    await _settle(tester);
    await tester.tap(find.text(l.t('bridge.wtpix.assetTpix')));
    await _settle(tester);

    expect(find.byKey(const ValueKey('wtpix-closed')), findsOneWidget);
    expect(find.text(l.t('bridge.wtpix.notReady')), findsOneWidget);
    expect(find.byKey(const ValueKey('wtpix-lock-button')), findsNothing);
  });

  testWidgets('ฝาก: กดได้เมื่อจำนวนผ่าน + ติ๊กยอมรับ → แตะเบิ้ลตรวจครั้งเดียว → กล่องยืนยัน vault เต็ม → ยกเลิก = ไม่ส่ง',
      (tester) async {
    _tallScreen(tester);
    final wallet = await unlockedWallet();
    await tester.pumpWidget(_harness(wallet));
    await _settle(tester);

    expect(_button(tester, 'usdt-deposit-button').onPressed, isNull, reason: 'ยังไม่กรอกจำนวน');
    final amount = find.descendant(of: find.byKey(const ValueKey('usdt-deposit-amount')), matching: find.byType(TextField));

    await tester.enterText(amount, '0.5');
    await tester.pump();
    expect(find.textContaining(l.t('bridge.errBelowMin').replaceAll('{min}', '1')), findsOneWidget);

    await tester.enterText(amount, '25');
    await tester.pump();
    expect(_button(tester, 'usdt-deposit-button').onPressed, isNull, reason: 'ยังไม่ติ๊กยอมรับ');
    expect(_button(tester, 'usdt-deposit-button').label, contains('25'), reason: 'ป้ายปุ่มบอกจำนวนที่จะฝาก');

    await tester.tap(find.byKey(const ValueKey('usdt-ack')));
    await tester.pump();
    expect(_button(tester, 'usdt-deposit-button').onPressed, isNotNull);

    // แตะเบิ้ล (ก่อนจอวาดใหม่) → เริ่มตรวจแค่รอบเดียว
    await tester.tap(find.byKey(const ValueKey('usdt-deposit-button')));
    await tester.tap(find.byKey(const ValueKey('usdt-deposit-button')), warnIfMissed: false);
    await _settle(tester);
    await tester.pump(const Duration(milliseconds: 500));
    expect(bsc.calls.where((c) => c == 'eth_chainId'), hasLength(1), reason: 'กดเบิ้ล = ตรวจ/ส่งครั้งเดียว');

    expect(find.text(l.t('bridge.confirmDepositTitle')), findsOneWidget);
    expect(find.text(_vault), findsWidgets);
    // ในกล่องยืนยัน (การ์ดจำนวนด้านหลังก็โชว์ยอดที่จะได้รับ 25 USDT เช่นกัน)
    expect(find.descendant(of: find.byType(ObsidianSheetFrame), matching: find.text('25 USDT')), findsOneWidget);
    expect(find.byKey(const ValueKey('bridge-confirm')), findsOneWidget);

    await tester.tap(find.text(l.t('send.cancel')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text(l.t('bridge.confirmDepositTitle')), findsNothing);
    expect(bsc.calls, isNot(contains('eth_sendRawTransaction')));
    expect(tpix.calls, isNot(contains('eth_sendRawTransaction')));
    expect(_button(tester, 'usdt-deposit-button').onPressed, isNotNull, reason: 'ยกเลิกแล้วกดใหม่ได้');
  });

  testWidgets('ถอน: ที่อยู่ปลายทางผิด checksum → บอกทันที กดถอนไม่ได้', (tester) async {
    _tallScreen(tester);
    final wallet = await unlockedWallet();
    await tester.pumpWidget(_harness(wallet));
    await _settle(tester);
    await tester.tap(find.text(l.t('bridge.tabWithdraw')));
    await _settle(tester);

    final target = find.descendant(of: find.byKey(const ValueKey('usdt-target-address')), matching: find.byType(TextField));
    expect(tester.widget<TextField>(target).controller!.text.toLowerCase(), wallet.address!.toLowerCase(),
        reason: 'ค่าเริ่มต้น = ที่อยู่ของกระเป๋านี้');

    await tester.enterText(
        find.descendant(of: find.byKey(const ValueKey('usdt-withdraw-amount')), matching: find.byType(TextField)), '10');
    await tester.enterText(target, '0xF46131C82819d7621163F482b3fe88a228A7807c');
    await tester.pump();

    expect(find.text(l.t('bridge.errAddressInvalid')), findsOneWidget);
    expect(_button(tester, 'usdt-withdraw-button').onPressed, isNull);
  });

  testWidgets('รายการที่ติดตาม: ขั้นตอนจากสถานะจริง + ลบต้องยืนยัน (ยกเลิก = ยังอยู่)', (tester) async {
    _tallScreen(tester);
    final wallet = await unlockedWallet();
    final hash = '0x9a4e${'7c' * 28}b21c';
    SharedPreferences.setMockInitialValues({
      'bridge_tracked_usdt_v1': jsonEncode([
        {
          'kind': 'deposit',
          'chainId': 56,
          'txHash': hash,
          'owner': wallet.address!.toLowerCase(),
          'addedAt': 1,
          'status': {'state': 'confirming', 'amount': '250', 'confirmations': 11},
        },
      ]),
    });
    await tester.pumpWidget(_harness(wallet));
    await _settle(tester);

    expect(find.textContaining('${l.t('obs.bridge.latest')} · 250 USDT'), findsOneWidget);
    expect(find.text(l.t('obs.bridge.step.sendUsdt').replaceAll('{chain}', 'BNB Chain')), findsOneWidget);
    expect(find.text(l.t('bridge.confirmations').replaceAll('{n}', '11')), findsOneWidget);
    expect(find.text(l.t('obs.bridge.step.mintUsdt')), findsOneWidget);
    final tracker = tester.widget<ObsidianStepTracker>(find.byType(ObsidianStepTracker));
    expect(tracker.steps.map((s) => s.state),
        [ObsidianStepState.done, ObsidianStepState.active, ObsidianStepState.idle]);

    final card = find.byKey(ValueKey('tracked-deposit:56:$hash'));
    await tester.tap(find.descendant(of: card, matching: find.byIcon(Icons.close_rounded)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text(l.t('bridge.removeTitle')), findsOneWidget);
    await tester.tap(find.text(l.t('send.cancel')).last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(card, findsOneWidget, reason: 'ยกเลิก = ไม่ลบ');

    await tester.tap(find.descendant(of: card, matching: find.byIcon(Icons.close_rounded)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text(l.t('bridge.remove')).last);
    await _settle(tester);
    expect(card, findsNothing);
  });
}
