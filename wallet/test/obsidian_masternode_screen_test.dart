/// TPIX Wallet — หน้ามาสเตอร์โหนดธีม Obsidian (ด่านความปลอดภัยต้องอยู่ครบหลังเปลี่ยนหน้าตา)
///
/// ล็อกไว้:
///   1. กองรางวัลว่าง = ไม่มีตัวเลข APR บนจอ (โชว์ "รอเติมพูล") + บอกว่ายังไม่มีรางวัลจ่ายจริง
///   2. กองมีเงิน = โชว์เพดาน APR จากสัญญา
///   3. สมัคร/สเตคโหนดใหม่ทำที่เว็บเท่านั้น — ปุ่มหลักพาไปเว็บ ไม่มีปุ่มสเตค/แผ่นสเตคในแอป
///   4. ปิดรับลงทะเบียน / ยอดไม่พอ = บอกเหตุผล แต่ยังไม่มีทางสเตคในแอป
///   5. Validator = ปุ่มพาไปเว็บ (KYC)
///   6. มีโหนดอยู่แล้ว = ยังรับรางวัล / ถอนสเตคในแอปได้
///   7. สัญญาโค้ดไม่รู้จัก / ยังไม่เปิด / ติดต่อไม่ได้ = ไม่มีปุ่มสเตค
///
/// Developed by Xman Studio
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tpix_wallet/core/locale_provider.dart';
import 'package:tpix_wallet/core/themes/theme_bundle.dart';
import 'package:tpix_wallet/providers/wallet_provider.dart';
import 'package:tpix_wallet/screens/masternode_screen.dart';
import 'package:tpix_wallet/services/masternode_service.dart';
import 'package:tpix_wallet/services/price_service.dart';
import 'package:tpix_wallet/services/rpc_client.dart';

import 'support/test_theme.dart';

const _me = '0xd2eab07809921fcb36c7ab72d7b5d8d2c12a67d7';
const _registry = '0x00000000000000000000000000000000000000aa';
final _liveCode = File('test/support/node_registry_v2_026f5f9.hex').readAsStringSync().trim();
final _e18 = BigInt.from(10).pow(18);
BigInt _t(int n) => BigInt.from(n) * _e18;

String _word(BigInt v) => v.toRadixString(16).padLeft(64, '0');
http.Response _ok(Object? r) => http.Response(jsonEncode({'jsonrpc': '2.0', 'id': 1, 'result': r}), 200);

final _emptyNode = '0x${'0' * 62}20${'0' * 64 * 10}${'0' * 61}1a0${'0' * 64 * 2}${'0' * 64}';

/// โหนด Sentinel ที่ active อยู่ · พ้นล็อกแล้ว (unlockAt 2026-01-07) · endpoint "203.0.113.10:8545"
const _activeNode =
    '0x0000000000000000000000000000000000000000000000000000000000000020'
    '0000000000000000000000001234567890abcdef1234567890abcdef12345678'
    '0000000000000000000000000000000000000000000000000000000000000001'
    '0000000000000000000000000000000000000000000000000000000000000001'
    '00000000000000000000000000000000000000000000152d02c7e14af6800000'
    '0000000000000000000000000000000000000000000000000000000068e77800'
    '00000000000000000000000000000000000000000000000000000000695e1f00'
    '0000000000000000000000000000000000000000000000000000000068e779f4'
    '000000000000000000000000000000000000000000000000ad78ebc5ac620000'
    '000000000000000000000000000000000000000000000000000000000000267a'
    'abababababababababababababababababababababababababababababababab'
    '00000000000000000000000000000000000000000000000000000000000001a0'
    '0000000000000000000000000000000000000000000000000000000000000000'
    '0000000000000000000000000000000000000000000000000000000000000000'
    '0000000000000000000000000000000000000000000000000000000000000011'
    '3230332e302e3131332e31303a38353435000000000000000000000000000000';

/// เชนปลอม — minStake ตาม tier id (Guardian=0, Sentinel=1, Light=2, Validator=3) ไม่ใช่ตัวเลขของ mock
RpcClient _chain({required BigInt pool, bool paused = false, bool hasNode = false}) {
  const mins = [123456, 23456, 3456, 7654321];
  return RpcClient(['https://rpc.test'], httpClient: MockClient((req) async {
    final body = jsonDecode(req.body) as Map<String, dynamic>;
    final method = body['method'] as String;
    if (method == 'eth_getCode') return _ok(_liveCode);
    if (method != 'eth_call') return _ok('0x0');
    final data = ((body['params'] as List).first as Map)['data'] as String;
    switch (data.substring(0, 10)) {
      case '0x7ed85ff3': // getTierInfo
        final id = int.parse(data.substring(data.length - 2), radix: 16);
        return _ok('0x${_word(_t(mins[id]))}${_word(BigInt.from(id == 2 ? 0 : 50))}${_word(BigInt.from(3))}'
            '${_word(BigInt.from(30))}${_word(BigInt.from(id == 2 ? 0 : 500))}${_word(BigInt.from(2500))}');
      case '0xf8bc005d': // tierAprCapBps
        return _ok('0x${_word(BigInt.from(1234))}');
      case '0x9abbbd3b': // registrationPaused
        return _ok('0x${_word(paused ? BigInt.one : BigInt.zero)}');
      case '0x582115fb': // getNodeInfo
        return _ok(hasNode ? _activeNode : _emptyNode);
      case '0xf40f0f52': // pendingReward
      case '0x9a78ea4a': // claimableNow
        return _ok('0x${_word(hasNode ? _t(5) : BigInt.zero)}');
      case '0xd0377094': // availableRewardFunds
        return _ok('0x${_word(pool)}');
    }
    return http.Response(jsonEncode({'jsonrpc': '2.0', 'id': 1, 'error': {'code': 3, 'message': 'revert'}}), 200);
  }));
}

http.Client _config({String address = _registry}) => MockClient((_) async => http.Response(
    jsonEncode({
      'success': true,
      'data': {'registry_address': address, 'registry_live': true, 'registration_paused': false, 'chain_id': 4289},
    }),
    200));

class _FakeWallet extends WalletProvider {
  _FakeWallet(this.bal);
  final BigInt? bal;
  @override
  String? get address => _me;
  @override
  BigInt? get balanceWei => bal;
  @override
  Future<void> refreshBalance() async {}
}

Widget _app(WalletProvider w) => MultiProvider(
      providers: [
        ChangeNotifierProvider<WalletProvider>.value(value: w),
        ChangeNotifierProvider(create: (_) => LocaleProvider()),
      ],
      child: MaterialApp(
        theme: testTheme(themeId: ThemeId.obsidian),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: const MasterNodeScreen(),
      ),
    );

Future<void> _open(WidgetTester tester,
    {required BigInt pool, bool paused = false, bool hasNode = false, BigInt? balance}) async {
  MasterNodeService.clientFactory = () => _config();
  RpcClient.overrideForChain(4289, _chain(pool: pool, paused: paused, hasNode: hasNode));
  // จอสูงพอให้ทั้งหน้าถูกสร้าง (ListView สร้างเฉพาะที่ใกล้จอ)
  tester.view.physicalSize = const Size(1170, 3600);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_app(_FakeWallet(balance ?? _t(5000))));
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
  await tester.pumpAndSettle();
}

void main() {
  final l = LocaleProvider();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PriceService.clientFactory = () => MockClient((_) async => http.Response('', 503));
  });

  tearDown(() {
    MasterNodeService.clientFactory = http.Client.new;
    MasterNodeService.resetVerifiedRegistries();
    RpcClient.overrideForChain(4289, null);
    PriceService.clientFactory = http.Client.new;
    PriceService.reset();
  });

  testWidgets('กองว่าง → ไม่มีตัวเลข APR · บอกว่ายังไม่มีรางวัลจ่ายจริง', (tester) async {
    await _open(tester, pool: BigInt.zero);
    expect(find.text(l.t('obs.mn.aprWaitPool')), findsOneWidget);
    expect(find.textContaining('12.34%'), findsNothing);
    expect(find.text(l.t('obs.mn.poolEmpty')), findsOneWidget);
  });

  testWidgets('กองมีเงิน → เพดาน APR จากสัญญา · ปุ่มหลักพาไปเว็บ ไม่มีปุ่มสเตค', (tester) async {
    await _open(tester, pool: _t(1000));
    expect(find.text('12.34%'), findsOneWidget);
    expect(find.text(l.t('obs.mn.ctaWeb')), findsOneWidget);
    expect(find.text(l.t('mn.webOnlyTitle')), findsOneWidget);
    expect(find.textContaining('Stake '), findsNothing);
  });

  testWidgets('แตะปุ่มหลัก → ไม่เปิดแผ่นสเตคในแอป', (tester) async {
    await _open(tester, pool: _t(1000), balance: _t(5000));
    await tester.tap(find.text(l.t('obs.mn.ctaWeb')));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('ยอดไม่พอ → บอกเหตุผล · ปุ่มหลักยังพาไปเว็บ', (tester) async {
    await _open(tester, pool: _t(1000), balance: _t(100));
    expect(find.textContaining('3,456'), findsWidgets);
    expect(find.text(l.t('obs.mn.ctaWeb')), findsOneWidget);
    expect(find.textContaining('Stake '), findsNothing);
  });

  testWidgets('ปิดรับลงทะเบียน → แถบเตือน · ไม่มีปุ่มสเตค', (tester) async {
    await _open(tester, pool: _t(1000), paused: true);
    expect(find.text(l.t('mn.block.paused')), findsWidgets);
    expect(find.textContaining('Stake '), findsNothing);
  });

  testWidgets('Validator → ปุ่มสมัครผ่านเว็บ (KYC) ไม่มีปุ่มสเตค', (tester) async {
    await _open(tester, pool: _t(1000));
    await tester.tap(find.text('Validator'));
    await tester.pumpAndSettle();
    expect(find.text(l.t('obs.mn.ctaKyc')), findsOneWidget);
    expect(find.textContaining('Stake '), findsNothing);
  });

  testWidgets('มีโหนดอยู่แล้ว → รับรางวัล / ถอนสเตคในแอปได้ · สมัครเพิ่มไม่ได้', (tester) async {
    await _open(tester, pool: _t(1000), hasNode: true);
    expect(find.text(l.t('mn.myNode')), findsOneWidget);
    expect(find.text(l.t('mn.claim')), findsWidgets);
    expect(find.text(l.t('mn.unstake')), findsOneWidget);
    expect(find.text(l.t('obs.mn.cta.hasNode')), findsWidgets);
    expect(find.text(l.t('obs.mn.ctaWeb')), findsNothing);

    await tester.tap(find.text(l.t('mn.unstake')));
    await tester.pumpAndSettle();
    final sheet = find.byType(BottomSheet);
    expect(find.descendant(of: sheet, matching: find.text(l.t('mn.confirmUnstakeTitle'))), findsOneWidget);
    expect(find.descendant(of: sheet, matching: find.text(_registry)), findsOneWidget);
  });

  testWidgets('สัญญาโค้ดไม่รู้จัก → ให้อัปเดตแอป ไม่มีปุ่มสเตค/เว็บ', (tester) async {
    MasterNodeService.clientFactory = () => _config(address: '0x00000000000000000000000000000000000000bb');
    RpcClient.overrideForChain(
      4289,
      RpcClient(['https://rpc.test'], httpClient: MockClient((_) async => _ok('0x6080604052'))),
    );
    await tester.pumpWidget(_app(_FakeWallet(_t(5000))));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text(l.t('mn.unknownCodeTitle')), findsOneWidget);
    expect(find.text(l.t('mn.updateApp')), findsOneWidget);
    expect(find.textContaining('Stake'), findsNothing);
    expect(find.text(l.t('mn.openWebsite')), findsNothing);
  });

  testWidgets('ยังไม่เปิด / ติดต่อไม่ได้ → ไม่มีปุ่มสเตค · ลองใหม่โหลดจริง', (tester) async {
    MasterNodeService.clientFactory = () => MockClient((_) async => http.Response('Not Found', 404));
    await tester.pumpWidget(_app(_FakeWallet(_t(5000))));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text(l.t('mn.notDeployedTitle')), findsOneWidget);
    expect(find.textContaining('Stake'), findsNothing);

    var calls = 0;
    MasterNodeService.clientFactory = () => MockClient((_) async {
          calls++;
          return http.Response('<!DOCTYPE html>', 200);
        });
    await tester.tap(find.text(l.t('mn.retry')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(calls, 1);
    expect(find.text(l.t('mn.errNetwork')), findsOneWidget);
  });
}
