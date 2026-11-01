/// TPIX Wallet — เทสต์หน้าเพิ่มโทเค็น: ยืนยันแล้ว / ไม่ยืนยัน / ของปลอม / เพิ่มทีเดียวจากรายการ
/// + รายการจาก explorer (verify/scam/ล่ม/แคช/ลองใหม่/ชื่อซ้ำ/กดซ้ำ)
/// + วงกลมโลโก้ (โหลดอยู่/โหลดไม่ได้/ไม่มีลิงก์ → ตัวอักษรแรก ขนาดเท่าเดิม)
///
/// ไม่มีเน็ตจริง: รายการโทเค็นใส่ตรงๆ, explorer และ RPC เป็น MockClient, รูปเป็น ImageProvider ปลอม
/// sqlite เป็น I/O จริง → สลับ runAsync กับ pump (ดู [_drain])
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tpix_wallet/core/locale_provider.dart';
import 'package:tpix_wallet/core/themes/theme_bundle.dart';
import 'package:tpix_wallet/models/chain_config.dart';
import 'package:tpix_wallet/models/token_list.dart';
import 'package:tpix_wallet/providers/wallet_provider.dart';
import 'package:tpix_wallet/screens/add_token_screen.dart';
import 'package:tpix_wallet/services/db_service.dart';
import 'package:tpix_wallet/services/explorer_token_service.dart';
import 'package:tpix_wallet/services/rpc_client.dart';
import 'package:tpix_wallet/services/token_list_service.dart';
import 'package:tpix_wallet/services/token_service.dart';
import 'package:tpix_wallet/widgets/tpix_coin_logo.dart';

import 'support/isolated_db.dart';
import 'support/test_theme.dart';

const _idtc = '0x5fbdb2315678afecb367f032d93f642f64180aa3';
const _idtcLogo = 'https://tpix.online/storage/tokens/idtc.png';
const _random = '0x1234567890123456789012345678901234567890';
const _fakeUsdt = '0x9999999999999999999999999999999999999999';

/// อยู่บน explorer อย่างเดียว (ไม่อยู่ใน tokenlist.json) — แบบ TPIX-LP / WTPIX จริง
const _lp = '0x3684e0ebd1bd7ef7b7783e695639badcd04bc4f0';
const _lpLogo = 'https://explorer.test/lp.png';

/// อยู่ในหน้า /tokens แต่ไม่ผ่านกฎ
const _unverified = '0x1111111111111111111111111111111111111111';
const _scam = '0x2222222222222222222222222222222222222222';

/// อยู่ใน tokenlist.json แต่ไม่อยู่บน explorer → ห้ามขึ้นรายการ
const _listOnly = '0x3333333333333333333333333333333333333333';

/// สองตัวชื่อเดียวกันบน explorer (verify ทั้งคู่ ไม่มีตัวไหนอนุมัติ)
const _fooA = '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _fooB = '0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

/// กระเป๋าที่ยังไม่ได้ปลดล็อกในเทสต์ = ช่อง -1
const _slot = -1;

final _list = TokenList(name: 'TPIX Token List', tokens: const [
  TokenListEntry(
    chainId: 4289,
    address: _idtc,
    name: 'IDTC Token',
    symbol: 'IDTC',
    decimals: 18,
    logoUri: _idtcLogo,
  ),
  TokenListEntry(
    chainId: 4289,
    address: _listOnly,
    name: 'List Only Coin',
    symbol: 'LISTONLY',
    decimals: 18,
  ),
]);

class _Coin {
  final String address;
  final String name;
  final String symbol;
  final bool verified;
  final bool scam;
  final String? icon;
  const _Coin(this.address, this.name, this.symbol, {this.verified = true, this.scam = false, this.icon});
}

/// เหรียญบนหน้า /tokens ของ explorer ปลอม (ค่าเริ่มต้น — เทสต์เปลี่ยนได้)
const _defaultCoins = [
  _Coin(_idtc, 'IDTC Token', 'IDTC', icon: 'https://explorer.test/idtc.png'),
  _Coin('0x0A4Ee87551eF041f3EecFBBfdcfFC1B46a4878f1', 'Tether USD (TPIX bridged)', 'USDT'),
  _Coin(_lp, 'TPIX LP Token', 'TPIX-LP', icon: _lpLogo),
  _Coin(_unverified, 'Unverified Coin', 'UNV', verified: false),
  _Coin(_scam, 'Scam Coin', 'SCAM', scam: true),
];

List<_Coin> _coins = _defaultCoins;
bool _explorerDown = false;
Completer<void>? _explorerGate;
int _explorerRequests = 0;
DateTime _now = DateTime(2026, 11, 1, 12);

/// explorer ปลอม: /api/v2/tokens หน้าเดียว + /api/v2/addresses/{ที่อยู่}
void _serveExplorer() {
  ExplorerTokenService.clock = () => _now;
  ExplorerTokenService.clientFactory = () => MockClient((req) async {
        _explorerRequests++;
        if (_explorerGate != null) await _explorerGate!.future;
        if (_explorerDown) return http.Response('Bad Gateway', 502);
        if (req.url.path == '/api/v2/tokens') {
          return http.Response(
            jsonEncode({
              'items': [
                for (final c in _coins)
                  {'address': c.address, 'name': c.name, 'symbol': c.symbol, 'type': 'ERC-20', 'icon_url': c.icon},
              ],
              'next_page_params': null,
            }),
            200,
          );
        }
        final key = req.url.pathSegments.last.toLowerCase();
        final c = _coins.where((c) => c.address.toLowerCase() == key).firstOrNull;
        if (c == null) return http.Response('{"message":"Not found"}', 404);
        return http.Response(
          jsonEncode({'hash': c.address, 'is_verified': c.verified, 'is_scam': c.scam, 'is_contract': true}),
          200,
        );
      });
}

/// จำลองเปิดแอปใหม่: หน่วยความจำหาย แคชในเครื่อง (SharedPreferences) ยังอยู่
void _restartExplorer() {
  ExplorerTokenService.resetForTest();
  _serveExplorer();
}

/// จำนวนครั้งที่อ่าน name() ต่อสัญญา (ตัวเล็ก) — นับว่ากดซ้ำแล้วยิงซ้ำไหม
final _nameCalls = <String, int>{};

class _Contract {
  final String name;
  final String symbol;
  final int decimals;
  const _Contract(this.name, this.symbol, this.decimals);
}

String _word(int v) => v.toRadixString(16).padLeft(64, '0');

String _abiString(String s) {
  final bytes = utf8.encode(s);
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '0x${_word(32)}${_word(bytes.length)}${hex.padRight(64, '0')}';
}

/// RPC ปลอมของ TPIX Chain: name()/symbol()/decimals()/balanceOf() ตามสัญญาที่กำหนด
/// ที่อยู่ที่ไม่รู้จัก = revert (ไม่ใช่ ERC-20)
void _mockChain(Map<String, _Contract> contracts, {Future<void>? gate}) {
  RpcClient.overrideForChain(
    4289,
    RpcClient(
      ['https://rpc.test'],
      httpClient: MockClient((req) async {
        if (gate != null) await gate;
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        final params = body['params'] as List;
        http.Response ok(Object? result) => http.Response(
            jsonEncode({'jsonrpc': '2.0', 'id': body['id'], 'result': result}), 200);
        switch (body['method']) {
          case 'eth_getCode':
            return ok('0x6080');
          case 'eth_call':
            final call = params.first as Map;
            final c = contracts[(call['to'] as String).toLowerCase()];
            final data = call['data'] as String;
            if (c == null) {
              return http.Response(
                jsonEncode({
                  'jsonrpc': '2.0',
                  'id': body['id'],
                  'error': {'code': -32000, 'message': 'execution reverted'},
                }),
                200,
              );
            }
            if (data.startsWith('0x06fdde03')) {
              final to = (call['to'] as String).toLowerCase();
              _nameCalls[to] = (_nameCalls[to] ?? 0) + 1;
              return ok(_abiString(c.name));
            }
            if (data.startsWith('0x95d89b41')) return ok(_abiString(c.symbol));
            if (data.startsWith('0x313ce567')) return ok('0x${_word(c.decimals)}');
            return ok('0x${_word(0)}'); // balanceOf
          default:
            return ok('0x0');
        }
      }),
    ),
  );
}

/// รูปที่โหลดไม่ได้ / รูปที่ไม่มีวันโหลดเสร็จ
class _FailingImage extends ImageProvider<_FailingImage> {
  const _FailingImage();
  @override
  Future<_FailingImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);
  @override
  ImageStreamCompleter loadImage(_FailingImage key, ImageDecoderCallback decode) =>
      OneFrameImageStreamCompleter(Future<ImageInfo>.error(StateError('offline')));
}

class _PendingImage extends ImageProvider<_PendingImage> {
  final Completer<ImageInfo> completer = Completer<ImageInfo>();
  _PendingImage();
  @override
  Future<_PendingImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);
  @override
  ImageStreamCompleter loadImage(_PendingImage key, ImageDecoderCallback decode) =>
      OneFrameImageStreamCompleter(completer.future);
}

final _navKey = GlobalKey<NavigatorState>();

Widget _harness({ThemeId theme = ThemeId.liquid}) => MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => WalletProvider()),
        ChangeNotifierProvider(create: (_) => LocaleProvider()),
      ],
      child: MaterialApp(
        navigatorKey: _navKey,
        theme: testTheme(themeId: theme),
        home: const Scaffold(body: Text('HOME')),
      ),
    );

/// ปล่อยงาน I/O จริง (sqlite) กับงานในเวลาปลอม (setState/HTTP ปลอม) เดินสลับกันจนนิ่ง
Future<void> _drain(WidgetTester tester, {int rounds = 12}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 25)));
    await tester.pump(const Duration(milliseconds: 16));
  }
}

/// [_drain] จนกว่าจะเจอ [finder] (ไม่เกิน [maxRounds] รอบ) — งานที่มี I/O จริงหลายช่วงติดกัน
Future<void> _drainUntil(WidgetTester tester, Finder finder, {int maxRounds = 80}) async {
  for (var i = 0; i < maxRounds && finder.evaluate().isEmpty; i++) {
    await _drain(tester, rounds: 1);
  }
}

Future<void> _open(WidgetTester tester, {ThemeId theme = ThemeId.liquid}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.runAsync(() async {
    await tester.pumpWidget(_harness(theme: theme));
  });
  unawaited(_navKey.currentState!
      .push(MaterialPageRoute<void>(builder: (_) => const AddTokenScreen())));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400)); // ทรานซิชันเปิดหน้า
  await _drain(tester, rounds: 4);
}

Future<void> _searchFor(WidgetTester tester, String address) async {
  await tester.enterText(find.byType(TextField), address);
  await tester.pump();
  await tester.tap(find.text(LocaleProvider().t('token.search')));
  await tester.pump();
  await _drain(tester);
}

Future<List<String>> _savedAddresses(WidgetTester tester) async {
  final tokens = await tester.runAsync(() => DbService.getTokensForSlot(_slot));
  return tokens!.map((t) => t.contractAddress).toList();
}

void main() {
  final l = LocaleProvider(); // ภาษาเริ่มต้น = ไทย
  late ImageProvider Function(String) originalProvider;

  setUpAll(() async {
    await useIsolatedTestDb('add_token_screen');
    originalProvider = TokenAvatar.imageProviderFor;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await DbService.close();
    await databaseFactory.deleteDatabase(
      '${await databaseFactory.getDatabasesPath()}/tpix_wallet.db',
    );
    TokenListService.resetForTest();
    TokenListService.setForTest(_list);
    TokenService.resetCache();
    // คู่เทรด DEX ล่ม → ใช้ค่าในตัวแอป (USDT) — ไม่มีเน็ตจริงในเทสต์
    TokenService.clientFactory = () => MockClient((_) async => http.Response('down', 503));
    TokenAvatar.imageProviderFor = (_) => const _FailingImage();
    _coins = _defaultCoins;
    _explorerDown = false;
    _explorerGate = null;
    _explorerRequests = 0;
    _now = DateTime(2026, 11, 1, 12);
    _nameCalls.clear();
    _restartExplorer();
    _mockChain({
      _idtc: const _Contract('IDTC Token', 'IDTC', 18),
      _random: const _Contract('My Cool Token', 'MCT', 18),
      _fakeUsdt: const _Contract('Tether USD', 'USDT', 6),
      ChainConfig.tpixUsdtAddress.toLowerCase(): const _Contract('Tether USD', 'USDT', 6),
      _lp: const _Contract('TPIX LP Token', 'TPIX-LP', 18),
      _fooA: const _Contract('Foo Coin', 'FOO', 18),
      _fooB: const _Contract('Foo Coin', 'F00', 18),
    });
  });

  tearDown(() {
    RpcClient.overrideForChain(4289, null);
    ExplorerTokenService.resetForTest();
    TokenListService.resetForTest();
    TokenService.clientFactory = http.Client.new;
    TokenAvatar.imageProviderFor = originalProvider;
  });

  tearDownAll(() async => DbService.close());

  group('รายการ "โทเค็นบน TPIX Chain"', () {
    testWidgets('มาจาก explorer เท่านั้น: ผ่าน verify ขึ้น · ไม่ verify / scam / อยู่แค่ใน tokenlist ไม่ขึ้น',
        (tester) async {
      await _open(tester);
      expect(find.text(l.t('token.listTitle')), findsOneWidget);
      expect(find.text('IDTC'), findsOneWidget);
      expect(find.text('USDT'), findsOneWidget);
      expect(find.text('TPIX-LP'), findsOneWidget);
      expect(find.text('UNV'), findsNothing);
      expect(find.text('SCAM'), findsNothing);
      expect(find.text('LISTONLY'), findsNothing, reason: 'tokenlist.json ไม่ใช่แหล่งรายการแล้ว');
      // ยืนยันแล้ว (อนุมัติ): หัวข้อ 1 + IDTC + USDT · ยืนยันซอร์สโค้ด: TPIX-LP
      expect(find.byIcon(Icons.verified), findsNWidgets(3));
      expect(find.byIcon(Icons.task_alt_rounded), findsOneWidget);
      // ที่อยู่สัญญาโชว์ทุกแถว
      expect(find.textContaining('0x3684...c4f0'), findsOneWidget);
    });

    testWidgets('explorer ล่มและไม่มีแคช → บอกเป็นข้อความ + ลองใหม่ (ไม่ใช่รายการว่าง) → ลองใหม่ได้รายการ',
        (tester) async {
      _explorerDown = true;
      await _open(tester);
      expect(find.text(l.t('token.explorerUnavailable')), findsOneWidget);
      expect(find.byKey(const ValueKey('explorer-retry')), findsOneWidget);
      expect(find.text('IDTC'), findsNothing);
      expect(find.text('USDT'), findsNothing, reason: 'ไม่ถอยไปใช้ค่าในตัวแอป — fail closed');

      _explorerDown = false;
      _now = _now.add(const Duration(seconds: 6));
      await tester.tap(find.byKey(const ValueKey('explorer-retry')));
      await tester.pump();
      await _drain(tester);
      expect(find.text(l.t('token.explorerUnavailable')), findsNothing);
      expect(find.text('IDTC'), findsOneWidget);
      expect(find.text('TPIX-LP'), findsOneWidget);
    });

    testWidgets('explorer ล่มแต่มีแคชที่เคยผ่าน → ใช้แคช + บอกว่าอาจไม่ล่าสุด', (tester) async {
      await tester.runAsync(() => ExplorerTokenService.load());
      _restartExplorer(); // เปิดแอปใหม่ 2 ชม.ต่อมา explorer ล่ม
      _now = _now.add(const Duration(hours: 2));
      _explorerDown = true;
      await _open(tester);
      expect(find.text('TPIX-LP'), findsOneWidget);
      expect(find.text('UNV'), findsNothing);
      expect(find.text(l.t('token.explorerStale')), findsOneWidget);
      expect(find.text(l.t('token.explorerUnavailable')), findsNothing);
    });

    testWidgets('เปิดหน้าซ้ำภายใน 1 ชม. ไม่ยิง explorer ซ้ำ', (tester) async {
      await _open(tester);
      final first = _explorerRequests;
      expect(first, greaterThan(0));
      _navKey.currentState!.pop();
      await tester.pump(const Duration(milliseconds: 400));
      unawaited(_navKey.currentState!.push(MaterialPageRoute<void>(builder: (_) => const AddTokenScreen())));
      await tester.pump(const Duration(milliseconds: 400));
      await _drain(tester, rounds: 4);
      expect(find.text('TPIX-LP'), findsOneWidget);
      expect(_explorerRequests, first);
    });

    testWidgets('ออกจากหน้าระหว่างโหลด explorer → ไม่พัง', (tester) async {
      _explorerGate = Completer<void>();
      await _open(tester);
      expect(find.text(l.t('token.explorerLoading')), findsOneWidget);
      _navKey.currentState!.pop();
      await tester.pump(const Duration(milliseconds: 400));
      _explorerGate!.complete();
      await _drain(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('HOME'), findsOneWidget);
      expect(ExplorerTokenService.current!.contains(_lp), isTrue, reason: 'โหลดต่อจนแคชเสร็จ');
    });

    testWidgets('อยู่บน explorer อย่างเดียว: แตะ + → เพิ่มทันที (ข้อมูลจากสัญญา + โลโก้ explorer)', (tester) async {
      await _open(tester);
      await tester.tap(find.byKey(const ValueKey('quick-add-$_lp')));
      await tester.pump();
      await _drain(tester);
      final saved = await tester.runAsync(() => DbService.getTokensForSlot(_slot));
      final lp = saved!.singleWhere((t) => t.contractAddress == _lp);
      expect(lp.symbol, 'TPIX-LP');
      expect(lp.decimals, 18, reason: 'ทศนิยมจากสัญญา');
      expect(lp.logoUrl, _lpLogo);
    });

    testWidgets('กดเพิ่มซ้ำรัวๆ → อ่านสัญญาครั้งเดียว ได้แถวเดียว · แถวเป็น "เพิ่มแล้ว" ไม่มีปุ่มให้กดซ้ำ',
        (tester) async {
      await _open(tester);
      final plus = find.byKey(const ValueKey('quick-add-$_lp'));
      await tester.tap(plus);
      await tester.tap(plus, warnIfMissed: false); // ยังไม่ทันวาดใหม่ — ตัวกันกดซ้ำต้องกันไว้
      await tester.pump();
      expect(plus, findsNothing, reason: 'ระหว่างเพิ่ม ปุ่มกลายเป็นตัวหมุน');
      await _drain(tester);

      expect(_nameCalls[_lp], 1);
      final saved = await tester.runAsync(() => DbService.getTokensForSlot(_slot));
      expect(saved!.where((t) => t.contractAddress == _lp), hasLength(1));
      expect(plus, findsNothing);
      final row = find.ancestor(of: find.text('TPIX-LP'), matching: find.byType(InkWell));
      expect(find.descendant(of: row, matching: find.text(l.t('token.addedShort'))), findsOneWidget);

      // ค้นด้วยที่อยู่อีกรอบ → บอกว่าเพิ่มแล้ว ไม่เพิ่มซ้ำ
      await _searchFor(tester, _lp);
      expect(find.text(l.t('token.alreadyAdded')), findsOneWidget);
      final again = await tester.runAsync(() => DbService.getTokensForSlot(_slot));
      expect(again!.where((t) => t.contractAddress == _lp), hasLength(1));
    });

    testWidgets('ชื่อซ้ำบน explorer → ขึ้นทั้งคู่พร้อมที่อยู่ + ไอคอนเตือน · แตะ + = หน้าตรวจละเอียด ไม่เพิ่มเอง',
        (tester) async {
      _coins = const [
        _Coin(_fooA, 'Foo Coin', 'FOO'),
        _Coin(_fooB, 'Foo Coin', 'F00'),
        _Coin(_lp, 'TPIX LP Token', 'TPIX-LP'),
      ];
      await _open(tester);
      expect(find.textContaining('0xaaaa...aaaa'), findsOneWidget);
      expect(find.textContaining('0xbbbb...bbbb'), findsOneWidget);
      expect(find.byIcon(Icons.gpp_maybe_rounded), findsNWidgets(2));

      await tester.tap(find.byKey(const ValueKey('quick-add-$_fooA')));
      await tester.pump();
      // อ่านสัญญา 2 รอบ + sqlite จริง 2 รอบ (เพิ่มทีเดียว → หน้าตรวจละเอียด) — รอจนเห็นผล
      await _drainUntil(tester, find.text(l.t('token.lookalikeTitle')));
      expect(find.text(l.t('token.lookalikeTitle')), findsOneWidget);
      expect(find.textContaining(_fooB), findsOneWidget, reason: 'บอกที่อยู่ของอีกตัวให้เทียบ');
      expect(find.text(l.t('token.twinNote')), findsOneWidget);
      expect(await _savedAddresses(tester), isNot(contains(_fooA)));
    });

    testWidgets('ช่องที่อยู่ (monospace) มีฟอนต์ไทยสำรอง — hint ภาษาไทยไม่เป็นกล่อง', (tester) async {
      await _open(tester);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.decoration!.hintText, l.t('token.inputHint'));
      expect(field.decoration!.hintStyle!.fontFamilyFallback, contains('Noto Sans Thai'));
      expect(field.style!.fontFamilyFallback, contains('Noto Sans Thai'));
      // hint รับฟอนต์ monospace มาจาก style ของช่อง → ฟอนต์สำรองต้องติดไปด้วยหลังรวมสไตล์
      final hint = tester.widget<Text>(find.text(l.t('token.inputHint')));
      expect(hint.style?.fontFamilyFallback, contains('Noto Sans Thai'));
    });

    testWidgets('พิมพ์ชื่อ → กรองรายการ (ไม่ขึ้นว่าที่อยู่ผิด)', (tester) async {
      await _open(tester);
      await tester.enterText(find.byType(TextField), 'idt');
      await tester.pump();
      expect(find.text('IDTC'), findsOneWidget);
      expect(find.text('USDT'), findsNothing);

      await tester.tap(find.text(l.t('token.search')));
      await tester.pump();
      expect(find.text(l.t('token.invalidAddress')), findsNothing);
      expect(find.text('IDTC'), findsOneWidget);
    });

    testWidgets('แตะ + → อ่านสัญญาแล้วเพิ่มทันที (ข้อมูลจากสัญญา + โลโก้จากรายการ)',
        (tester) async {
      await _open(tester);
      final row = find.ancestor(of: find.text('IDTC'), matching: find.byType(InkWell));
      await tester.tap(find.descendant(of: row, matching: find.byIcon(Icons.add_circle_outline)));
      await tester.pump();
      await _drain(tester);

      final saved = await tester.runAsync(() => DbService.getTokensForSlot(_slot));
      final idtc = saved!.singleWhere((t) => t.contractAddress == _idtc);
      expect(idtc.symbol, 'IDTC');
      expect(idtc.decimals, 18);
      expect(idtc.logoUrl, _idtcLogo);

      await _drain(tester);
      expect(
        find.descendant(of: row, matching: find.text(l.t('token.addedShort'))),
        findsOneWidget,
        reason: 'แถวเปลี่ยนเป็น "เพิ่มแล้ว" และยังอยู่หน้าเดิม เพิ่มตัวอื่นต่อได้',
      );
    });
  });

  group('ค้นหาด้วยที่อยู่สัญญา', () {
    testWidgets('อยู่ในรายการ → ป้าย "ยืนยันแล้ว" ไม่มีคำเตือน', (tester) async {
      await _open(tester);
      await _searchFor(tester, _idtc);
      expect(find.text(l.t('token.verified')), findsOneWidget);
      expect(find.text(l.t('token.unverifiedTitle')), findsNothing);
      expect(find.text(l.t('token.lookalikeTitle')), findsNothing);
      expect(find.text(l.t('token.mismatchTitle')), findsNothing);
    });

    testWidgets('ระหว่างอ่านสัญญา โชว์ข้อมูลจากรายการไปก่อน (ยังกดเพิ่มไม่ได้)', (tester) async {
      final gate = Completer<void>();
      _mockChain({_idtc: const _Contract('IDTC Token', 'IDTC', 18)}, gate: gate.future);
      await _open(tester);
      await _searchFor(tester, _idtc);

      expect(find.text(l.t('token.checkingContract')), findsOneWidget);
      expect(find.text('IDTC Token'), findsOneWidget);
      expect(find.text(l.t('token.verified')), findsOneWidget);
      expect(find.text(l.t('token.add')), findsNothing);

      gate.complete();
      await _drain(tester);
      expect(find.text(l.t('token.checkingContract')), findsNothing);
      expect(find.text(l.t('token.add')), findsOneWidget);
    });

    testWidgets('บนสัญญาไม่ตรงกับรายการ → ใช้ข้อมูลจากสัญญา + เตือน', (tester) async {
      _mockChain({_idtc: const _Contract('IDTC Token', 'IDT2', 8)});
      await _open(tester);
      await _searchFor(tester, _idtc);

      expect(find.text(l.t('token.mismatchTitle')), findsOneWidget);
      expect(find.text('IDT2'), findsOneWidget, reason: 'สัญลักษณ์จากสัญญาชนะ');
      expect(find.textContaining('"IDTC"'), findsOneWidget);
      expect(find.textContaining('"IDT2"'), findsOneWidget);
      expect(find.textContaining('"18"'), findsOneWidget);
      expect(find.textContaining('"8"'), findsOneWidget);
    });

    testWidgets('ไม่อยู่ในรายการ → เตือน แต่ยังเพิ่มได้ (ไม่ต้องยืนยันซ้ำ)', (tester) async {
      await _open(tester);
      await _searchFor(tester, _random);

      expect(find.text(l.t('token.unverifiedTitle')), findsOneWidget);
      expect(find.text(l.t('token.verified')), findsNothing);
      expect(find.text(l.t('token.listUnavailable')), findsNothing);

      await tester.tap(find.text(l.t('token.add')));
      await tester.pump();
      await _drain(tester);
      expect(await _savedAddresses(tester), contains(_random));
      expect(find.text('HOME'), findsOneWidget, reason: 'เพิ่มแล้วกลับหน้าก่อนหน้า');
    });

    testWidgets('USDT ปลอม → เตือนของปลอม + ยืนยันอีกชั้น (ยกเลิก = ไม่เพิ่ม)', (tester) async {
      await _open(tester);
      await _searchFor(tester, _fakeUsdt);

      expect(find.text(l.t('token.lookalikeTitle')), findsOneWidget);
      expect(find.textContaining(ChainConfig.tpixUsdtAddress), findsOneWidget,
          reason: 'บอกที่อยู่ของตัวจริงให้เทียบ');

      await tester.tap(find.text(l.t('token.add')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300)); // เปิดกล่องยืนยัน
      expect(find.text(l.t('token.lookalikeConfirmTitle')), findsOneWidget);
      await tester.tap(find.text(l.t('common.cancel')));
      await tester.pump();
      await _drain(tester);
      expect(await _savedAddresses(tester), isNot(contains(_fakeUsdt)));
      expect(find.text(l.t('token.lookalikeTitle')), findsOneWidget, reason: 'ยังอยู่หน้าเดิม');

      await tester.tap(find.text(l.t('token.add')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text(l.t('token.addAnyway')));
      await tester.pump();
      await _drain(tester);
      expect(await _savedAddresses(tester), contains(_fakeUsdt));
    });

    testWidgets('อยู่บน explorer อย่างเดียว → ป้าย "ยืนยันซอร์สโค้ด" + คำเตือน (ไม่ใช่ "ยืนยันแล้ว")', (tester) async {
      await _open(tester);
      await _searchFor(tester, _lp);
      expect(find.text(l.t('token.sourceVerified')), findsOneWidget);
      expect(find.text(l.t('token.sourceVerifiedTitle')), findsOneWidget);
      expect(find.text(l.t('token.verified')), findsNothing);
      expect(find.text(l.t('token.unverifiedTitle')), findsNothing);
      expect(find.text(l.t('token.add')), findsOneWidget);
    });

    testWidgets('ไม่ผ่านกฎ explorer (ไม่ verify) → คำเตือน "ไม่ยืนยัน" เหมือนเดิม', (tester) async {
      _mockChain({_unverified: const _Contract('Unverified Coin', 'UNV', 18)});
      await _open(tester);
      await _searchFor(tester, _unverified);
      expect(find.text(l.t('token.unverifiedTitle')), findsOneWidget);
      expect(find.text(l.t('token.sourceVerified')), findsNothing);
    });

    testWidgets('รายการยังไม่ขึ้นเว็บ (404) → บอกว่าตรวจกับรายการไม่ได้', (tester) async {
      TokenListService.setForTest(null);
      await _open(tester);
      await _searchFor(tester, _random);
      expect(find.text(l.t('token.unverifiedTitle')), findsOneWidget);
      expect(find.text(l.t('token.listUnavailable')), findsOneWidget);
    });
  });

  // ── ธีม Obsidian: หน้าตาใหม่ กฎเดิมทุกข้อ ──
  group('ธีม Obsidian', () {
    const obs = ThemeId.obsidian;

    testWidgets('รายการที่ยืนยันแล้ว + ช่องที่อยู่มีฟอนต์ไทยสำรอง', (tester) async {
      await _open(tester, theme: obs);
      expect(find.text(l.t('token.listTitle')), findsOneWidget);
      expect(find.text('IDTC'), findsOneWidget);
      expect(find.text('USDT'), findsOneWidget);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.decoration!.hintText, l.t('token.inputHint'));
      expect(field.style!.fontFamilyFallback, contains('Noto Sans Thai'));
      expect(field.decoration!.hintStyle!.fontFamilyFallback, contains('Noto Sans Thai'));
    });

    testWidgets('แตะ + → อ่านสัญญาแล้วเพิ่มทันที → แถวเป็น "เพิ่มแล้ว"', (tester) async {
      await _open(tester, theme: obs);
      await tester.tap(find.byKey(const ValueKey('obs-quick-add-$_idtc')));
      await tester.pump();
      await _drain(tester);

      final saved = await tester.runAsync(() => DbService.getTokensForSlot(_slot));
      final idtc = saved!.singleWhere((t) => t.contractAddress == _idtc);
      expect(idtc.logoUrl, _idtcLogo);
      await _drain(tester);
      expect(find.text(l.t('token.addedShort')), findsOneWidget);
    });

    testWidgets('อยู่ในรายการ → ป้าย "ยืนยันแล้ว" ไม่มีคำเตือน', (tester) async {
      await _open(tester, theme: obs);
      await _searchFor(tester, _idtc);
      expect(find.text(l.t('token.verified')), findsOneWidget);
      expect(find.text(l.t('token.unverifiedTitle')), findsNothing);
      expect(find.text(l.t('token.lookalikeTitle')), findsNothing);
    });

    testWidgets('USDT ปลอม → เตือน + ยืนยันอีกชั้น (ยกเลิก = ไม่เพิ่ม · เพิ่มต่อ = เพิ่ม)', (tester) async {
      await _open(tester, theme: obs);
      // คำเตือนของปลอมยาว — จอสูงขึ้นให้ปุ่มเพิ่มอยู่ในจอ
      tester.view.physicalSize = const Size(1080, 4800);
      await tester.pump();
      await _searchFor(tester, _fakeUsdt);
      expect(find.text(l.t('token.lookalikeTitle')), findsOneWidget);
      expect(find.textContaining(ChainConfig.tpixUsdtAddress), findsOneWidget);

      await tester.tap(find.text(l.t('token.add')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text(l.t('token.lookalikeConfirmTitle')), findsOneWidget);
      await tester.tap(find.text(l.t('common.cancel')));
      await tester.pump();
      await _drain(tester);
      expect(await _savedAddresses(tester), isNot(contains(_fakeUsdt)));

      await tester.tap(find.text(l.t('token.add')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text(l.t('token.addAnyway')));
      await tester.pump();
      await _drain(tester);
      expect(await _savedAddresses(tester), contains(_fakeUsdt));
    });

    testWidgets('รายการจาก explorer: ไม่ verify / scam ไม่ขึ้น · ล่ม+ไม่มีแคช → ข้อความ + ลองใหม่', (tester) async {
      _explorerDown = true;
      await _open(tester, theme: obs);
      expect(find.text(l.t('token.explorerUnavailable')), findsOneWidget);
      expect(find.byKey(const ValueKey('explorer-retry')), findsOneWidget);

      _explorerDown = false;
      _now = _now.add(const Duration(seconds: 6));
      await tester.tap(find.byKey(const ValueKey('explorer-retry')));
      await tester.pump();
      await _drain(tester);
      expect(find.text('TPIX-LP'), findsOneWidget);
      expect(find.text('UNV'), findsNothing);
      expect(find.text('SCAM'), findsNothing);
      expect(find.text('LISTONLY'), findsNothing);
    });

    testWidgets('กดเพิ่มซ้ำรัวๆ → ได้แถวเดียว', (tester) async {
      await _open(tester, theme: obs);
      final plus = find.byKey(const ValueKey('obs-quick-add-$_lp'));
      await tester.tap(plus);
      await tester.tap(plus, warnIfMissed: false);
      await tester.pump();
      await _drain(tester);
      expect(_nameCalls[_lp], 1);
      final saved = await tester.runAsync(() => DbService.getTokensForSlot(_slot));
      expect(saved!.where((t) => t.contractAddress == _lp), hasLength(1));
      expect(plus, findsNothing);
    });

    testWidgets('อยู่บน explorer อย่างเดียว → ป้าย "ยืนยันซอร์สโค้ด" + คำเตือน', (tester) async {
      await _open(tester, theme: obs);
      await _searchFor(tester, _lp);
      expect(find.text(l.t('token.sourceVerified')), findsOneWidget);
      expect(find.text(l.t('token.sourceVerifiedTitle')), findsOneWidget);
      expect(find.text(l.t('token.verified')), findsNothing);
    });

    testWidgets('ไม่ใช่ที่อยู่ → ข้อความผิด (ไม่ใช่ Exception ดิบ)', (tester) async {
      await _open(tester, theme: obs);
      await _searchFor(tester, '0x123');
      expect(find.text(l.t('token.invalidAddress')), findsOneWidget);
      expect(find.textContaining('Exception'), findsNothing);
    });
  });

  group('TokenAvatar', () {
    Widget avatar(String? url) => MaterialApp(
          home: Center(
            child: TokenAvatar(symbol: 'idtc', logoUrl: url, size: 36, color: Colors.teal),
          ),
        );

    testWidgets('ไม่มีลิงก์ / ไม่ใช่ https → ตัวอักษรแรก ไม่โหลดรูป', (tester) async {
      var requested = 0;
      TokenAvatar.imageProviderFor = (_) {
        requested++;
        return const _FailingImage();
      };
      for (final url in [null, 'http://tpix.online/a.png', 'ipfs://x']) {
        await tester.pumpWidget(avatar(url));
        expect(find.text('I'), findsOneWidget);
        expect(tester.getSize(find.byType(TokenAvatar)), const Size(36, 36));
      }
      expect(requested, 0);
    });

    testWidgets('กำลังโหลด → ตัวอักษรแรก ขนาดเท่ากัน (ไม่กระตุก)', (tester) async {
      TokenAvatar.imageProviderFor = (_) => _PendingImage();
      await tester.pumpWidget(avatar(_idtcLogo));
      await tester.pump();
      expect(find.text('I'), findsOneWidget);
      expect(tester.getSize(find.byType(TokenAvatar)), const Size(36, 36));
    });

    testWidgets('โหลดไม่ได้ → ตัวอักษรแรก ขนาดเท่ากัน', (tester) async {
      TokenAvatar.imageProviderFor = (_) => const _FailingImage();
      await tester.pumpWidget(avatar(_idtcLogo));
      await tester.pump();
      await tester.pump();
      expect(find.text('I'), findsOneWidget);
      expect(tester.getSize(find.byType(TokenAvatar)), const Size(36, 36));
    });

    testWidgets('โหลดได้ → แสดงรูป (ไม่มีตัวอักษร)', (tester) async {
      // PNG 1x1
      final png = base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==');
      TokenAvatar.imageProviderFor = (_) => MemoryImage(png);
      await tester.runAsync(() async {
        await tester.pumpWidget(avatar(_idtcLogo));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump();
      expect(find.text('I'), findsNothing);
      expect(find.byType(RawImage), findsOneWidget);
      expect(tester.getSize(find.byType(TokenAvatar)), const Size(36, 36));
    });
  });

  test('ข้อความใหม่มีครบทั้งไทยและอังกฤษ', () async {
    const keys = [
      'token.verified', 'token.verifiedHint', 'token.lookalikeShort',
      'token.checkingContract', 'token.unverifiedTitle', 'token.unverifiedBody',
      'token.listUnavailable', 'token.lookalikeTitle', 'token.lookalikeBody',
      'token.lookalikeReal', 'token.lookalikeNative', 'token.lookalikeConfirmTitle',
      'token.lookalikeConfirmBody', 'token.addAnyway', 'token.mismatchTitle',
      'token.mismatchBody', 'token.mismatchRow', 'token.fieldName', 'token.fieldSymbol', 'token.listTitle',
      'token.listSubtitle', 'token.listNoMatch', 'token.listMore', 'token.addedShort',
      'token.inputHint', 'token.sourceVerified', 'token.sourceVerifiedHint', 'token.sourceVerifiedTitle',
      'token.sourceVerifiedBody', 'token.explorerTwin', 'token.twinNote', 'token.explorerLoading',
      'token.explorerUnavailable', 'token.explorerEmpty', 'token.explorerStale', 'token.retry',
      'token.walletChanged',
    ];
    bool hasThai(String s) => s.runes.any((r) => r >= 0x0E00 && r <= 0x0E7F);
    final th = LocaleProvider();
    for (final k in keys) {
      expect(hasThai(th.t(k)), isTrue, reason: 'ไม่มีภาษาไทย: $k');
    }
    final en = LocaleProvider();
    await en.setLocale('en');
    for (final k in keys) {
      final v = en.t(k);
      expect(v, isNot(k), reason: 'ไม่มีภาษาอังกฤษ: $k');
      expect(hasThai(v), isFalse, reason: 'ภาษาอังกฤษมีอักษรไทย: $k');
    }
  });
}
