/// TPIX Wallet — เทสต์หน้าเพิ่มโทเค็น: ยืนยันแล้ว / ไม่ยืนยัน / ของปลอม / เพิ่มทีเดียวจากรายการ
/// + วงกลมโลโก้ (โหลดอยู่/โหลดไม่ได้/ไม่มีลิงก์ → ตัวอักษรแรก ขนาดเท่าเดิม)
///
/// ไม่มีเน็ตจริง: รายการโทเค็นใส่ตรงๆ, RPC เป็น MockClient, รูปเป็น ImageProvider ปลอม
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
import 'package:tpix_wallet/models/chain_config.dart';
import 'package:tpix_wallet/models/token_list.dart';
import 'package:tpix_wallet/providers/wallet_provider.dart';
import 'package:tpix_wallet/screens/add_token_screen.dart';
import 'package:tpix_wallet/services/db_service.dart';
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
]);

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
            if (data.startsWith('0x06fdde03')) return ok(_abiString(c.name));
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

Widget _harness() => MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => WalletProvider()),
        ChangeNotifierProvider(create: (_) => LocaleProvider()),
      ],
      child: MaterialApp(
        navigatorKey: _navKey,
        theme: testTheme(),
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

Future<void> _open(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.runAsync(() async {
    await tester.pumpWidget(_harness());
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
    _mockChain({
      _idtc: const _Contract('IDTC Token', 'IDTC', 18),
      _random: const _Contract('My Cool Token', 'MCT', 18),
      _fakeUsdt: const _Contract('Tether USD', 'USDT', 6),
      ChainConfig.tpixUsdtAddress.toLowerCase(): const _Contract('Tether USD', 'USDT', 6),
    });
  });

  tearDown(() {
    RpcClient.overrideForChain(4289, null);
    TokenListService.resetForTest();
    TokenService.clientFactory = http.Client.new;
    TokenAvatar.imageProviderFor = originalProvider;
  });

  tearDownAll(() async => DbService.close());

  group('รายการ "โทเค็นบน TPIX Chain"', () {
    testWidgets('โชว์ IDTC จากรายการ + USDT ในตัวแอป พร้อมติ๊กยืนยัน', (tester) async {
      await _open(tester);
      expect(find.text(l.t('token.listTitle')), findsOneWidget);
      expect(find.text('IDTC'), findsOneWidget);
      expect(find.text('USDT'), findsOneWidget);
      // หัวข้อ 1 + แถวละ 1
      expect(find.byIcon(Icons.verified), findsNWidgets(3));
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

    testWidgets('รายการยังไม่ขึ้นเว็บ (404) → บอกว่าตรวจกับรายการไม่ได้', (tester) async {
      TokenListService.setForTest(null);
      await _open(tester);
      await _searchFor(tester, _random);
      expect(find.text(l.t('token.unverifiedTitle')), findsOneWidget);
      expect(find.text(l.t('token.listUnavailable')), findsOneWidget);
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
      'token.inputHint',
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
