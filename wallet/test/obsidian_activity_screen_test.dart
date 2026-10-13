/// TPIX Wallet — หน้า "กิจกรรม" ธีม Obsidian + แถบเมนูของหน้าแท็บ
///
/// ล็อกไว้:
///   1. แถวมาจากประวัติจริง ชื่อของอีกฝั่งใช้ชื่อกระเป๋าตัวเอง · ตัวกรองซ่อนแถวที่ไม่ตรง
///   2. หน้าว่างมีปุ่มสแกนย้อนหลัง (สแกน 200 บล็อก) ไม่ใช่หน้าโล่ง
///   3. กดแท็บอื่นบนแถบเมนู = ปิดหน้าพร้อมคืนแท็บให้หน้าแรกพาไปต่อ · กดแท็บตัวเอง = ไม่ปิด
///   4. ธีมอื่นยังเป็นหน้าเดิม (ไม่มีแถบเมนู Obsidian)
///
/// Developed by Xman Studio
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tpix_wallet/core/locale_provider.dart';
import 'package:tpix_wallet/core/themes/theme_bundle.dart';
import 'package:tpix_wallet/models/tx_record.dart';
import 'package:tpix_wallet/models/wallet_info.dart';
import 'package:tpix_wallet/providers/wallet_provider.dart';
import 'package:tpix_wallet/screens/obsidian_tabs.dart';
import 'package:tpix_wallet/screens/tx_history_screen.dart';
import 'package:tpix_wallet/widgets/obsidian/obsidian.dart';

import 'support/test_theme.dart';

const _me = '0xD2eAB07809921fcB36c7AB72D7B5D8D2C12A67d7';
const _savings = '0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed';
const _stranger = '0x8f3C5e1d2b4a69788c7d6e5f4a3b2c1d0e9fC2d5';

class _FakeWallet extends WalletProvider {
  _FakeWallet(this._tx);
  final List<TxRecord> _tx;
  int scans = 0;
  int? lastScanBlocks;

  @override
  List<TxRecord> get txHistory => _tx;
  @override
  bool get isScanning => false;
  @override
  String? get address => _me;
  @override
  List<WalletInfo> get wallets => [
        WalletInfo(slot: 1, name: 'Main', address: _me),
        WalletInfo(slot: 2, name: 'Savings', address: _savings),
      ];
  @override
  Future<void> loadTxHistory() async {}
  @override
  Future<void> scanTransactions({int blockCount = 50}) async {
    scans++;
    lastScanBlocks = blockCount;
  }
}

final _e18 = BigInt.from(10).pow(18);
final _now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

List<TxRecord> _history() => [
      TxRecord(
          txHash: '0x${'a1' * 32}',
          fromAddress: _me,
          toAddress: _savings,
          value: (BigInt.from(1500) * _e18).toString(),
          direction: 'sent',
          status: 'confirmed',
          timestamp: _now - 60),
      TxRecord(
          txHash: '0x${'a2' * 32}',
          fromAddress: _stranger,
          toAddress: _me,
          value: (BigInt.from(250) * _e18).toString(),
          direction: 'received',
          status: 'confirmed',
          timestamp: _now - 120),
    ];

Widget _app(WalletProvider wallet, {ThemeId theme = ThemeId.obsidian, Widget? home}) => MultiProvider(
      providers: [
        ChangeNotifierProvider<WalletProvider>.value(value: wallet),
        ChangeNotifierProvider(create: (_) => LocaleProvider()),
      ],
      child: MaterialApp(
        theme: testTheme(themeId: theme),
        // แถบเมนู/การ์ดมีแอนิเมชันวนตลอด — ปิดไว้ให้ pumpAndSettle จบได้
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: home ?? const TxHistoryScreen(),
      ),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  final l = LocaleProvider();

  testWidgets('แถวจากประวัติจริง + ชื่อกระเป๋าตัวเอง + ตัวกรอง "รับ"', (tester) async {
    await tester.pumpWidget(_app(_FakeWallet(_history())));
    await tester.pumpAndSettle();

    expect(find.byType(NotchedNavBar), findsOneWidget);
    expect(find.text('ส่งให้ Savings'), findsOneWidget, reason: 'ที่อยู่ที่เป็นกระเป๋าตัวเองต้องโชว์ชื่อ');
    expect(find.text('รับจาก 0x8f3C…C2d5'), findsOneWidget);
    expect(find.text('−1,500 TPIX'), findsOneWidget);
    expect(find.text('+250 TPIX'), findsOneWidget);

    await tester.tap(find.text(l.t('obs.act.f.receive')));
    await tester.pumpAndSettle();
    expect(find.text('ส่งให้ Savings'), findsNothing);
    expect(find.text('รับจาก 0x8f3C…C2d5'), findsOneWidget);
  });

  testWidgets('หน้าว่าง → ปุ่มสแกนย้อนหลัง 200 บล็อก', (tester) async {
    final wallet = _FakeWallet(const []);
    await tester.pumpWidget(_app(wallet));
    await tester.pumpAndSettle();
    expect(find.text(l.t('tx.empty')), findsOneWidget);
    final before = wallet.scans;
    await tester.tap(find.text(l.t('tx.scan')));
    await tester.pump();
    expect(wallet.scans, before + 1);
    expect(wallet.lastScanBlocks, 200);
  });

  testWidgets('แถบเมนู: แท็บอื่น = ปิดหน้าพร้อมคืนแท็บ · แท็บตัวเอง = อยู่ต่อ', (tester) async {
    Object? result = 'none';
    await tester.pumpWidget(_app(
      _FakeWallet(_history()),
      home: Builder(
        builder: (context) => Center(
          child: TextButton(
            onPressed: () async {
              result = await Navigator.push<Object?>(
                  context, MaterialPageRoute<Object?>(builder: (_) => const TxHistoryScreen()));
            },
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // แท็บของหน้าตัวเอง → ไม่ปิด
    await tester.tap(find.descendant(of: find.byType(NotchedNavBar), matching: find.text(l.t('nav.activity'))));
    await tester.pumpAndSettle();
    expect(find.byType(TxHistoryScreen), findsOneWidget);
    expect(result, 'none');

    await tester.tap(find.descendant(of: find.byType(NotchedNavBar), matching: find.text(l.t('nav.settings'))));
    await tester.pumpAndSettle();
    expect(find.byType(TxHistoryScreen), findsNothing);
    expect(result, ObsidianTab.settings);
  });

  testWidgets('ปุ่มสแกนบนหน้าแท็บ → คืน ObsidianTab.scan ให้หน้าแรกเปิดแผ่นสแกน', (tester) async {
    Object? result;
    await tester.pumpWidget(_app(
      _FakeWallet(_history()),
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            result = await Navigator.push<Object?>(
                context, MaterialPageRoute<Object?>(builder: (_) => const TxHistoryScreen()));
          },
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(NotchedNavBar.scanButtonKey));
    await tester.pumpAndSettle();
    expect(result, ObsidianTab.scan);
  });

  testWidgets('ธีมอื่นยังเป็นหน้าเดิม — ไม่มีแถบเมนู Obsidian', (tester) async {
    await tester.pumpWidget(_app(_FakeWallet(_history()), theme: ThemeId.liquid));
    await tester.pumpAndSettle();
    expect(find.byType(NotchedNavBar), findsNothing);
    expect(find.text(l.t('tx.title')), findsOneWidget);
  });
}
