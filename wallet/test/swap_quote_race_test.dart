/// TPIX Wallet — หน้าแลกเหรียญ: ราคา/ยอดต้องเป็นของอินพุตปัจจุบันเสมอ (widget)
///
/// บั๊กที่เทสต์นี้ปิด (ธีมทั่วไปที่ไม่ใช่ Obsidian — ทางเดิน _fetchQuote/_loadBalance ใช้ร่วมกับ Obsidian):
///   - แก้จำนวนแล้วกดแลกภายใน 0.5 วิ (ช่วง debounce) → กล่องยืนยันโชว์ "รับขั้นต่ำ"
///     ที่คิดจากราคาของจำนวนเก่า และ amountOutMin ในธุรกรรมก็คิดจากราคานั้น (กันราคาขยับผิด)
///   - ราคาของจำนวนเก่าตอบกลับช้ากว่าของจำนวนใหม่ → ทับราคาใหม่
///   - ยอดของเชนเก่าตอบกลับช้ากว่าของเชนใหม่ → ทับยอดใหม่
///   - ระหว่างอนุมัติ/แลก ยังสลับเชน/เหรียญ/ทิศ/จำนวนได้ (ธุรกรรมที่รอผลอ้างอิงเชนเดิม)
///
/// ไม่มีเน็ตจริง: RPC ทุกเชนเป็น MockClient แยกตาม host · sqlite (ประวัติธุรกรรม) เป็น I/O จริง
/// → สลับ runAsync กับ pump (ดู [_drain])
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tpix_wallet/core/locale_provider.dart';
import 'package:tpix_wallet/core/themes/theme_bundle.dart';
import 'package:tpix_wallet/models/chain_config.dart';
import 'package:tpix_wallet/providers/wallet_provider.dart';
import 'package:tpix_wallet/screens/swap_screen.dart';
import 'package:tpix_wallet/services/db_service.dart';
import 'package:tpix_wallet/services/rpc_client.dart';
import 'package:tpix_wallet/services/swap_service.dart';

import 'support/isolated_db.dart';
import 'support/test_theme.dart';

final _e18 = BigInt.from(10).pow(18);
String _w(BigInt v) => v.toRadixString(16).padLeft(64, '0');
String _hex(BigInt v) => '0x${v.toRadixString(16)}';

final _bscHost = Uri.parse(ChainConfig.bsc.rpcUrl).host;
final _polygonHost = Uri.parse(ChainConfig.polygon.rpcUrl).host;

/// อัตราคงที่: 1 เหรียญต้นทาง = 585 เหรียญปลายทาง (ทศนิยม 18 ทั้งคู่)
const _rate = 585;

/// "รับขั้นต่ำ" ที่กล่องยืนยันโชว์ (ราคาขยับเริ่มต้น 1%)
String _minText(String amount) {
  final quote = SwapService.parseAmount(amount, 18) * BigInt.from(_rate);
  final min = SwapService.applySlippage(quote, 1.0);
  return '${SwapService.formatAmount(min, 18).toStringAsFixed(6)} USDT';
}

/// RPC ปลอมทุกเชน (แยกตาม host) — หน่วงคำตอบได้ เพื่อจำลองเน็ตช้า/ตอบสลับลำดับ
class _FakeChains {
  int quotes = 0;

  /// หน่วงคำตอบ getAmountsOut ตามจำนวนที่ขอ
  Duration Function(BigInt amountIn) quoteDelay = (_) => Duration.zero;

  /// หน่วงคำตอบ eth_getBalance ตาม host
  final Map<String, Duration> balanceDelay = {};

  final Map<String, BigInt> nativeBalance = {
    _bscHost: BigInt.from(10) * _e18,
    _polygonHost: BigInt.from(7) * _e18,
  };
  BigInt tokenBalance = BigInt.from(1000) * _e18;
  BigInt allowance = BigInt.zero;

  /// หน่วงคำตอบ allowance (eth_call)
  Duration allowanceDelay = Duration.zero;

  /// ธุรกรรมที่ถูกส่ง (hex ที่เซ็นแล้ว)
  final List<String> rawTxs = [];

  /// host ที่ถูกถามสถานะธุรกรรม ตามลำดับ
  final List<String> receiptHosts = [];

  late final http.Client client = MockClient(_handle);

  Future<http.Response> _handle(http.Request req) async {
    if (req.method != 'POST') return http.Response('not found', 404);
    final host = req.url.host;
    final body = jsonDecode(req.body) as Map<String, dynamic>;
    final params = (body['params'] as List?) ?? const [];
    Object? result;
    switch (body['method']) {
      case 'eth_chainId':
        result = host == _polygonHost ? '0x89' : '0x38';
      case 'eth_getBalance':
        final delay = balanceDelay[host];
        if (delay != null) await Future<void>.delayed(delay);
        result = _hex(nativeBalance[host] ?? BigInt.zero);
      case 'eth_gasPrice':
        result = '0x3b9aca00';
      case 'eth_getTransactionCount':
        result = '0x0';
      case 'eth_sendRawTransaction':
        rawTxs.add((params.first as String).toLowerCase());
        result = '0x${'ab' * 32}';
      case 'eth_getTransactionReceipt':
        receiptHosts.add(host);
        result = null; // ยังไม่ขุด — ค้างสถานะ "กำลังแลก/อนุมัติ" ไว้ให้ตรวจ
      case 'eth_call':
        final data = ((params.first as Map)['data'] as String).toLowerCase();
        if (data.startsWith('0xd06ca61f')) {
          quotes++;
          final amountIn = BigInt.parse(data.substring(10, 74), radix: 16);
          final delay = quoteDelay(amountIn);
          if (delay > Duration.zero) await Future<void>.delayed(delay);
          result = '0x${_w(BigInt.from(32))}${_w(BigInt.two)}${_w(amountIn)}${_w(amountIn * BigInt.from(_rate))}';
        } else if (data.startsWith('0x70a08231')) {
          result = '0x${_w(tokenBalance)}';
        } else if (data.startsWith('0xdd62ed3e')) {
          if (allowanceDelay > Duration.zero) await Future<void>.delayed(allowanceDelay);
          result = '0x${_w(allowance)}';
        } else {
          result = '0x${_w(BigInt.zero)}';
        }
      default:
        result = '0x0';
    }
    return http.Response(jsonEncode({'jsonrpc': '2.0', 'id': body['id'], 'result': result}), 200);
  }
}

Widget _harness(WalletProvider wallet, ThemeId theme) => MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: wallet),
        ChangeNotifierProvider(create: (_) => LocaleProvider()),
      ],
      child: MaterialApp(theme: testTheme(themeId: theme), home: const SwapScreen()),
    );

/// จอสูงพอให้ปุ่มแลกด้านล่างอยู่ในจอ (ไม่งั้น tap พลาดเป้าแล้วเทสต์ผ่านแบบหลอก ๆ)
void _tallScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 5000);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
}

Future<void> _pumpFor(WidgetTester tester, Duration total, {Duration step = const Duration(milliseconds: 100)}) async {
  var t = Duration.zero;
  while (t < total) {
    await tester.pump(step);
    t += step;
  }
}

/// ปล่อยงาน I/O จริง (sqlite บันทึกประวัติธุรกรรม) กับงานในเวลาปลอมเดินสลับกันจนนิ่ง
Future<void> _drain(WidgetTester tester, {int rounds = 12}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 25)));
    await tester.pump(const Duration(milliseconds: 16));
  }
}

/// ข้อความบนปุ่มหลักด้านล่างของหน้าเดิม — ภาษาไทยหัวหน้า (swap.title) กับปุ่ม (swap.button)
/// เป็นคำเดียวกัน "แลกเปลี่ยน" → เอาตัวสุดท้ายในต้นไม้ (ปุ่มอยู่ล่างสุด)
Finder _legacyCta(String label) => find.text(label).last;

/// ปุ่มหลักของหน้าเดิม (GestureDetector ที่ห่อข้อความปุ่ม)
GestureDetector _legacyButton(WidgetTester tester, String label) => tester.widget<GestureDetector>(
      find.ancestor(of: _legacyCta(label), matching: find.byType(GestureDetector)).first,
    );

TextField _amountField(WidgetTester tester) => tester.widget<TextField>(find.byType(TextField).first);

void main() {
  final l = LocaleProvider();
  late _FakeChains chains;

  setUpAll(() async {
    await useIsolatedTestDb('swap_quote_race');
    // เสียงกด/ส่ง (SynthService) ขอโฟลเดอร์ชั่วคราวผ่าน plugin ที่เทสต์ไม่มี → ให้รอไปเรื่อย ๆ = ไม่เล่นเสียง
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) => Completer<Object?>().future,
    );
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    chains = _FakeChains();
    // ธุรกรรม (เซ็น/ส่ง/ถามสถานะ) วิ่งผ่าน RpcClient — ชี้ไปที่ RPC ปลอมตัวเดียวกัน
    RpcClient.overrideForChain(56, RpcClient([ChainConfig.bsc.rpcUrl], httpClient: chains.client));
    RpcClient.overrideForChain(137, RpcClient([ChainConfig.polygon.rpcUrl], httpClient: chains.client));
  });

  tearDown(() {
    RpcClient.overrideForChain(56, null);
    RpcClient.overrideForChain(137, null);
  });

  tearDownAll(() async => DbService.close());

  Future<WalletProvider> unlockedWallet() async {
    final wallet = WalletProvider();
    await wallet.importFromPrivateKey('0x${'4c' * 32}');
    return wallet;
  }

  testWidgets('แก้จำนวนแล้วกดแลกภายใน debounce → ปุ่มปิด ไม่มีกล่องยืนยันจากราคาของจำนวนเก่า', (tester) async {
    _tallScreen(tester);
    final wallet = await unlockedWallet();
    await http.runWithClient(() async {
      await tester.pumpWidget(_harness(wallet, ThemeId.liquid));
      await _pumpFor(tester, const Duration(milliseconds: 500));

      await tester.enterText(find.byType(TextField).first, '1');
      await _pumpFor(tester, const Duration(milliseconds: 900));
      expect(chains.quotes, 1);
      expect(find.text('585.000000'), findsOneWidget);
      expect(_legacyButton(tester, l.t('swap.button')).onTap, isNotNull);

      // แก้เป็น 0.5 แล้วกดแลกทันที — ยังไม่ครบ 0.5 วิ ราคาของ 0.5 ยังไม่มา
      await tester.enterText(find.byType(TextField).first, '0.5');
      await tester.pump();
      expect(find.text('585.000000'), findsNothing, reason: 'ราคาที่มีอยู่เป็นของจำนวนเก่า ต้องล้างทันที');
      expect(find.text(_minText('1')), findsNothing, reason: 'รับขั้นต่ำของจำนวนเก่าห้ามโชว์');
      expect(_legacyButton(tester, l.t('swap.button')).onTap, isNull, reason: 'ปุ่มปิดจนกว่าราคาของจำนวนใหม่มา');

      await tester.tap(_legacyCta(l.t('swap.button')));
      await _pumpFor(tester, const Duration(milliseconds: 300));
      expect(find.byType(AlertDialog), findsNothing, reason: 'กดในช่วง debounce ต้องไม่เปิดกล่องยืนยัน');

      // ราคาของ 0.5 มาแล้ว → กดได้ และกล่องยืนยันคิดจากราคาของ 0.5
      await _pumpFor(tester, const Duration(milliseconds: 600));
      expect(chains.quotes, 2);
      expect(find.text('292.500000'), findsOneWidget);
      await tester.tap(_legacyCta(l.t('swap.button')));
      await _pumpFor(tester, const Duration(milliseconds: 300));
      final dialog = find.byType(AlertDialog);
      expect(dialog, findsOneWidget);
      expect(find.descendant(of: dialog, matching: find.text(_minText('0.5'))), findsOneWidget);
      expect(find.text(_minText('1')), findsNothing);

      await tester.tap(find.descendant(of: dialog, matching: find.text(l.t('send.cancel'))));
      await _pumpFor(tester, const Duration(milliseconds: 300));
    }, () => chains.client);
  });

  for (final theme in [ThemeId.liquid, ThemeId.obsidian]) {
    testWidgets('ราคาของจำนวนเก่าตอบกลับช้ากว่าจำนวนใหม่ → ถูกทิ้ง ไม่ทับราคาใหม่ (${theme.name})', (tester) async {
      _tallScreen(tester);
      final wallet = await unlockedWallet();
      // ถาม 1 → ช้า 3 วิ · ถาม 2 → ตอบทันที (เน็ตตอบสลับลำดับ)
      chains.quoteDelay = (amountIn) => amountIn == _e18 ? const Duration(seconds: 3) : Duration.zero;
      final isObs = theme == ThemeId.obsidian;
      final amount = isObs ? find.byKey(const ValueKey('obs-swap-amount')) : find.byType(TextField).first;
      final cta = isObs ? find.byKey(const ValueKey('obs-swap-cta')) : _legacyCta(l.t('swap.button'));

      await http.runWithClient(() async {
        await tester.pumpWidget(_harness(wallet, theme));
        await _pumpFor(tester, const Duration(milliseconds: 500));

        await tester.enterText(amount, '1');
        await _pumpFor(tester, const Duration(milliseconds: 700)); // ขอราคาของ 1 แล้ว (ยังไม่ตอบ)
        await tester.enterText(amount, '2');
        await _pumpFor(tester, const Duration(milliseconds: 800)); // ราคาของ 2 มาแล้ว
        expect(chains.quotes, 2);

        await _pumpFor(tester, const Duration(seconds: 3)); // ราคาของ 1 เพิ่งมาถึง
        if (!isObs) {
          expect(find.text('1170.000000'), findsOneWidget, reason: 'ตัวเลขยังเป็นของจำนวน 2');
          expect(find.text('585.000000'), findsNothing);
        }

        await tester.tap(cta);
        await _pumpFor(tester, const Duration(milliseconds: 600));
        expect(find.text(_minText('2')), findsWidgets, reason: 'กล่องยืนยันคิดจากราคาของจำนวน 2');
        expect(find.text(_minText('1')), findsNothing, reason: 'ราคาของจำนวน 1 ที่มาช้าต้องถูกทิ้ง');
      }, () => chains.client);
    });
  }

  testWidgets('ยอดของเชนเก่าตอบกลับช้ากว่าเชนใหม่ → ถูกทิ้ง ไม่ทับยอดของเชนใหม่', (tester) async {
    _tallScreen(tester);
    final wallet = await unlockedWallet();
    chains.balanceDelay[_bscHost] = const Duration(seconds: 3);
    await http.runWithClient(() async {
      await tester.pumpWidget(_harness(wallet, ThemeId.liquid));
      await _pumpFor(tester, const Duration(milliseconds: 200)); // ยอด BSC ยังไม่มา

      await tester.tap(find.text(ChainConfig.polygon.shortName).first);
      await _pumpFor(tester, const Duration(milliseconds: 300));
      expect(find.text('${l.t('swap.balance')}: 7.0000'), findsOneWidget);

      await _pumpFor(tester, const Duration(seconds: 3)); // ยอด BSC (10 BNB) เพิ่งมาถึง
      expect(find.text('${l.t('swap.balance')}: 7.0000'), findsOneWidget, reason: 'ยังเป็นยอด POL ของเชนที่เลือกอยู่');
      expect(find.text('${l.t('swap.balance')}: 10.0000'), findsNothing);
    }, () => chains.client);
  });

  testWidgets('ระหว่างแลก: สลับเชน/เหรียญ/ทิศ/จำนวน/ราคาขยับไม่ได้ · amountOutMin = ยอดในกล่องยืนยัน', (tester) async {
    _tallScreen(tester);
    final wallet = await unlockedWallet();
    await http.runWithClient(() async {
      await tester.pumpWidget(_harness(wallet, ThemeId.liquid));
      await _pumpFor(tester, const Duration(milliseconds: 500));
      await tester.enterText(find.byType(TextField).first, '1');
      await _pumpFor(tester, const Duration(milliseconds: 900));

      await tester.tap(_legacyCta(l.t('swap.button')));
      await _pumpFor(tester, const Duration(milliseconds: 300));
      final dialog = find.byType(AlertDialog);
      expect(find.descendant(of: dialog, matching: find.text(_minText('1'))), findsOneWidget);
      await tester.tap(find.descendant(of: dialog, matching: find.text(l.t('swap.button'))));
      await _pumpFor(tester, const Duration(milliseconds: 300));
      await _drain(tester);

      // ธุรกรรมที่ส่งจริงใช้ amountOutMin เท่ากับ "รับขั้นต่ำ" ที่ผู้ใช้เห็น
      expect(chains.rawTxs, hasLength(1));
      final minOut = SwapService.applySlippage(_e18 * BigInt.from(_rate), 1.0);
      expect(chains.rawTxs.single, contains('7ff36ab5${_w(minOut)}'));
      expect(find.text(l.t('swap.swapping')), findsOneWidget);

      // ล็อกทุกอย่างที่ธุรกรรมอ้างอิงอยู่
      expect(_amountField(tester).enabled, isFalse);
      await tester.tap(find.text(ChainConfig.polygon.shortName).first);
      await tester.tap(find.byIcon(Icons.swap_vert_rounded));
      await tester.tap(find.text('MAX'));
      await tester.tap(find.text('3.0%'));
      await tester.tap(find.text('BNB'));
      await _pumpFor(tester, const Duration(milliseconds: 500));
      expect(find.byType(BottomSheet), findsNothing, reason: 'แผ่นเลือกเหรียญต้องไม่เปิด');
      expect(_amountField(tester).controller!.text, '1');
      expect(find.text('BNB'), findsOneWidget, reason: 'ยังจ่าย BNB บน BSC');
      expect(find.text('1%'), findsOneWidget, reason: 'ราคาขยับไม่เปลี่ยน');

      // รอจนครบรอบเช็กสถานะ (ยังไม่ขุด → โชว์ tx ให้ติดตามเอง) — ทุกครั้งถามเชนเดิม
      await _pumpFor(tester, const Duration(seconds: 61), step: const Duration(seconds: 1));
      await _drain(tester, rounds: 4);
      expect(chains.receiptHosts, isNotEmpty);
      expect(chains.receiptHosts.toSet(), {_bscHost}, reason: 'สลับเชนกลางทางไม่ได้ → ถามสถานะที่ BSC ตลอด');
      expect(find.text(l.t('swap.success')), findsOneWidget);
    }, () => chains.client);
  });

  testWidgets('ระหว่างอนุมัติ: สลับเชน/เหรียญ/ทิศ/จำนวนไม่ได้ · ปุ่มอนุมัติรอ allowance โหลดเสร็จก่อน', (tester) async {
    _tallScreen(tester);
    final wallet = await unlockedWallet();
    await http.runWithClient(() async {
      await tester.pumpWidget(_harness(wallet, ThemeId.liquid));
      await _pumpFor(tester, const Duration(milliseconds: 500));

      // สลับทิศ → จ่าย USDT (ERC-20) ที่ยังไม่อนุมัติ
      await tester.tap(find.byIcon(Icons.swap_vert_rounded));
      await _pumpFor(tester, const Duration(milliseconds: 500));
      await tester.enterText(find.byType(TextField).first, '10');
      await _pumpFor(tester, const Duration(milliseconds: 900));
      final approveLabel = '${l.t('swap.approve')} USDT';
      expect(_legacyButton(tester, approveLabel).onTap, isNotNull);

      await tester.tap(_legacyCta(approveLabel));
      await _pumpFor(tester, const Duration(milliseconds: 300));
      await _drain(tester);
      expect(chains.rawTxs, hasLength(1), reason: 'ส่งธุรกรรมอนุมัติแล้ว');
      expect(find.text(l.t('swap.approving')), findsOneWidget);

      expect(_amountField(tester).enabled, isFalse);
      await tester.tap(find.text(ChainConfig.polygon.shortName).first);
      await tester.tap(find.byIcon(Icons.swap_vert_rounded));
      await tester.tap(find.text('MAX'));
      await tester.tap(find.text('USDT').first);
      await _pumpFor(tester, const Duration(milliseconds: 500));
      expect(find.byType(BottomSheet), findsNothing);
      expect(_amountField(tester).controller!.text, '10');
      expect(find.text(l.t('swap.approving')), findsOneWidget, reason: 'ยังอนุมัติ USDT บน BSC อยู่');

      // ครบ 30 วิยังไม่ขุด → แจ้งล้มเหลว ปลดล็อก
      await _pumpFor(tester, const Duration(seconds: 31), step: const Duration(seconds: 1));
      expect(chains.receiptHosts.toSet(), {_bscHost});
      expect(_amountField(tester).enabled, isTrue);
      await _pumpFor(tester, const Duration(seconds: 5), step: const Duration(seconds: 1)); // snackbar หาย
    }, () => chains.client);
  });

  testWidgets('สลับเหรียญจ่าย → ปุ่มอนุมัติปิดจนกว่า allowance ของเหรียญใหม่โหลดเสร็จ (ไม่ชวนอนุมัติซ้ำ)', (tester) async {
    _tallScreen(tester);
    final wallet = await unlockedWallet();
    chains.allowance = BigInt.from(2).pow(255); // เคยอนุมัติไว้แล้ว — อนุมัติซ้ำ = เสียค่าแก๊สฟรี
    await http.runWithClient(() async {
      await tester.pumpWidget(_harness(wallet, ThemeId.liquid));
      await _pumpFor(tester, const Duration(milliseconds: 500));

      chains.allowanceDelay = const Duration(seconds: 3);
      await tester.tap(find.byIcon(Icons.swap_vert_rounded)); // จ่าย USDT
      await tester.pump();
      await tester.enterText(find.byType(TextField).first, '10');
      await _pumpFor(tester, const Duration(milliseconds: 900));

      // allowance ของ USDT ยังไม่มา (ค่าเริ่ม 0) → ป้ายเป็น "อนุมัติ" แต่ห้ามกดได้
      final approveLabel = '${l.t('swap.approve')} USDT';
      expect(find.text(approveLabel), findsOneWidget);
      expect(_legacyButton(tester, approveLabel).onTap, isNull, reason: 'ยังไม่รู้ allowance จริง');

      await _pumpFor(tester, const Duration(seconds: 3));
      expect(find.text(approveLabel), findsNothing, reason: 'allowance พอแล้ว ไม่ต้องอนุมัติ');
      expect(_legacyButton(tester, l.t('swap.button')).onTap, isNotNull);
    }, () => chains.client);
  });
}
