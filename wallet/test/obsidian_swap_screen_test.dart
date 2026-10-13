/// TPIX Wallet — หน้าแลกเหรียญธีม Obsidian (widget)
///
/// ของใหม่ที่ต้องไม่พัง:
///   - แก้จำนวน → ราคาของจำนวนเก่าถูกล้างทันที ปุ่มแลกปิดจนกว่าราคาของจำนวนใหม่มาถึง
///     (กันกล่องยืนยันโชว์ "ได้รับขั้นต่ำ" ที่คำนวณจากจำนวนเก่า)
///   - ราคาอัปเดตเองทุก 15 วิ แต่หยุดนิ่งระหว่างกล่องยืนยันเปิดอยู่ (ราคาต้องไม่เปลี่ยนใต้มือผู้ใช้)
///   - ตั้งค่าราคาขยับ: รับค่าเหมือนกล่องเดิม (มากกว่า 0 ถึง 50%) · เกิน 5% เตือน
///   - ธีมอื่นทำงานเหมือนเดิมทุกอย่าง (ไม่มีตัวจับเวลาขอราคาเอง)
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
import 'package:tpix_wallet/screens/swap_screen.dart';
import 'package:tpix_wallet/widgets/obsidian/obsidian.dart';

import 'support/test_theme.dart';

final _e18 = BigInt.from(10).pow(18);
String _w(BigInt v) => v.toRadixString(16).padLeft(64, '0');

/// RPC ของ BSC ปลอม: ยอด 1.25 BNB · getAmountsOut ให้อัตราที่ขยับขึ้นทีละนิดทุกครั้งที่ถาม
class _FakeBsc {
  int quotes = 0;

  http.Client client() => MockClient((req) async {
        if (req.method != 'POST') return http.Response('not found', 404);
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        Object? result;
        switch (body['method']) {
          case 'eth_getBalance':
            result = '0x${(BigInt.from(125) * _e18 ~/ BigInt.from(100)).toRadixString(16)}';
          case 'eth_gasPrice':
            result = '0x3b9aca00';
          case 'eth_call':
            final data = ((body['params'] as List).first as Map)['data'] as String;
            if (data.startsWith('0xd06ca61f')) {
              quotes++;
              final amountIn = BigInt.parse(data.substring(10, 74), radix: 16);
              final out = amountIn * BigInt.from(5850 + quotes) ~/ BigInt.from(10);
              result = '0x${_w(BigInt.from(32))}${_w(BigInt.two)}${_w(amountIn)}${_w(out)}';
            } else {
              result = '0x${_w(BigInt.zero)}';
            }
          default:
            result = '0x0';
        }
        return http.Response(jsonEncode({'jsonrpc': '2.0', 'id': body['id'], 'result': result}), 200);
      });
}

Widget _harness(WalletProvider wallet, ThemeId theme) => MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: wallet),
        ChangeNotifierProvider(create: (_) => LocaleProvider()),
      ],
      child: MaterialApp(theme: testTheme(themeId: theme), home: const SwapScreen()),
    );

Future<void> _pumpFor(WidgetTester tester, Duration total, {Duration step = const Duration(milliseconds: 250)}) async {
  var t = Duration.zero;
  while (t < total) {
    await tester.pump(step);
    t += step;
  }
}

ObsidianButton _cta(WidgetTester tester) => tester.widget<ObsidianButton>(find.byKey(const ValueKey('obs-swap-cta')));

void main() {
  final l = LocaleProvider();
  late _FakeBsc bsc;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    bsc = _FakeBsc();
  });

  Future<WalletProvider> unlockedWallet() async {
    final wallet = WalletProvider();
    await wallet.importFromPrivateKey('0x${'4c' * 32}');
    return wallet;
  }

  testWidgets('แก้จำนวน → ราคาเก่าถูกล้างทันที ปุ่มแลกปิดจนกว่าราคาของจำนวนใหม่มาถึง', (tester) async {
    final wallet = await unlockedWallet();
    await http.runWithClient(() async {
      await tester.pumpWidget(_harness(wallet, ThemeId.obsidian));
      await _pumpFor(tester, const Duration(milliseconds: 500));

      await tester.enterText(find.byKey(const ValueKey('obs-swap-amount')), '1');
      await _pumpFor(tester, const Duration(milliseconds: 900));
      expect(bsc.quotes, 1);
      expect(_cta(tester).onPressed, isNotNull);
      expect(find.text('585.1'), findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey('obs-swap-amount')), '1.2');
      await tester.pump();
      expect(_cta(tester).onPressed, isNull, reason: 'ราคาที่มีอยู่เป็นของจำนวนเก่า');
      expect(find.text('585.1'), findsNothing);

      await _pumpFor(tester, const Duration(milliseconds: 900));
      expect(bsc.quotes, 2);
      expect(_cta(tester).onPressed, isNotNull);
    }, bsc.client);
  });

  testWidgets('ราคาอัปเดตเองทุก 15 วิ และหยุดนิ่งระหว่างกล่องยืนยันเปิดอยู่', (tester) async {
    final wallet = await unlockedWallet();
    await http.runWithClient(() async {
      await tester.pumpWidget(_harness(wallet, ThemeId.obsidian));
      await _pumpFor(tester, const Duration(milliseconds: 500));
      await tester.enterText(find.byKey(const ValueKey('obs-swap-amount')), '1');
      await _pumpFor(tester, const Duration(milliseconds: 900));
      expect(bsc.quotes, 1);
      expect(find.text(l.t('obs.swap.refreshIn').replaceAll('{s}', '15')), findsOneWidget);

      await _pumpFor(tester, const Duration(seconds: 15));
      expect(bsc.quotes, 2, reason: 'ครบ 15 วิ ขอราคาใหม่เอง');
      expect(find.text('585.2'), findsOneWidget, reason: 'ตัวเลขใหม่ขึ้นแทนโดยไม่ต้องแตะอะไร');

      // เปิดกล่องยืนยัน → นับถอยหลังหยุด ไม่มีการขอราคาใหม่
      await tester.tap(find.byKey(const ValueKey('obs-swap-cta')));
      await _pumpFor(tester, const Duration(milliseconds: 600));
      expect(find.text(l.t('swap.confirmTitle')), findsOneWidget);
      await _pumpFor(tester, const Duration(seconds: 30), step: const Duration(seconds: 1));
      expect(bsc.quotes, 2, reason: 'ราคาในกล่องยืนยันต้องไม่เปลี่ยนใต้มือ');

      await tester.tap(find.text(l.t('send.cancel')).last);
      await _pumpFor(tester, const Duration(milliseconds: 600));
      await _pumpFor(tester, const Duration(seconds: 16), step: const Duration(seconds: 1));
      expect(bsc.quotes, 3, reason: 'ปิดกล่องแล้วนับต่อ');
    }, bsc.client);
  });

  testWidgets('ตั้งค่าราคาขยับ: เกิน 50% กดตั้งไม่ได้ · เกิน 5% เตือน', (tester) async {
    final wallet = await unlockedWallet();
    await http.runWithClient(() async {
      await tester.pumpWidget(_harness(wallet, ThemeId.obsidian));
      await _pumpFor(tester, const Duration(milliseconds: 500));
      await tester.tap(find.byWidgetPredicate((w) => w is ObsidianHeaderTile && w.label == l.t('obs.swap.settings')));
      await _pumpFor(tester, const Duration(milliseconds: 600));

      ObsidianButton set() => tester.widget<ObsidianButton>(find.byKey(const ValueKey('obs-slippage-set')));
      expect(set().onPressed, isNotNull, reason: 'ค่าปัจจุบัน 1% ใช้ได้');

      final custom = find.descendant(of: find.byType(ObsidianSheetFrame), matching: find.byType(TextField));
      await tester.enterText(custom, '60');
      await tester.pump();
      expect(find.text(l.t('obs.swap.slippageInvalid')), findsOneWidget);
      expect(set().onPressed, isNull);

      await tester.enterText(custom, '7');
      await tester.pump();
      expect(find.text(l.t('obs.swap.slippageHigh')), findsOneWidget);
      expect(set().onPressed, isNotNull);
    }, bsc.client);
  });

  testWidgets('ธีมอื่น: หน้าเดิม ไม่มีตัวจับเวลาขอราคาเอง', (tester) async {
    final wallet = await unlockedWallet();
    await http.runWithClient(() async {
      await tester.pumpWidget(_harness(wallet, ThemeId.liquid));
      await _pumpFor(tester, const Duration(milliseconds: 500));
      expect(find.byType(ObsidianSwapOrb), findsNothing);

      await tester.enterText(find.byType(TextField).first, '1');
      await _pumpFor(tester, const Duration(milliseconds: 900));
      expect(bsc.quotes, 1);
      await _pumpFor(tester, const Duration(seconds: 20), step: const Duration(seconds: 1));
      expect(bsc.quotes, 1);
    }, bsc.client);
  });
}
