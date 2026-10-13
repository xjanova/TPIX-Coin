/// TPIX Wallet — หน้าเชื่อมต่อ dApp (WalletConnect)
///
/// สิ่งที่ห้ามพัง:
///   - จับคู่ไม่สำเร็จ (QR หมดอายุ / ตัวเชื่อมยังไม่พร้อม) → ข้อความที่อ่านรู้เรื่อง ไม่ใช่ Exception ดิบ
///     (ทุกธีม — เดิมโชว์ e.toString())
///   - ธีม Obsidian: ยังไม่มีการเชื่อมต่อ → ข้อความว่าง + ปุ่มสแกนพร้อมใช้
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:tpix_wallet/core/locale_provider.dart';
import 'package:tpix_wallet/core/themes/theme_bundle.dart';
import 'package:tpix_wallet/screens/dapp_connect_screen.dart';
import 'package:tpix_wallet/services/walletconnect_service.dart';
import 'package:tpix_wallet/widgets/obsidian/obsidian.dart';

import 'support/test_theme.dart';

Widget _harness(ThemeId theme, {String? uri}) => MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LocaleProvider()),
        // ยังไม่ได้ init → pair() โยน Exception('WalletConnect not initialized')
        ChangeNotifierProvider(create: (_) => WalletConnectService()),
      ],
      child: MaterialApp(theme: testTheme(themeId: theme), home: DAppConnectScreen(initialUri: uri)),
    );

void main() {
  final l = LocaleProvider();

  for (final theme in [ThemeId.liquid, ThemeId.obsidian]) {
    testWidgets('จับคู่ไม่สำเร็จ → ข้อความภาษาคน ไม่ใช่ Exception ดิบ (${theme.key})', (tester) async {
      await tester.pumpWidget(_harness(theme, uri: 'wc:expired@2?relay-protocol=irn'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text(l.t('wc.pairFailed')), findsOneWidget);
      expect(find.textContaining('Exception'), findsNothing);
      expect(find.textContaining('not initialized'), findsNothing);
    });
  }

  testWidgets('Obsidian: ยังไม่มีการเชื่อมต่อ → ข้อความว่าง + ปุ่มสแกนกดได้', (tester) async {
    await tester.pumpWidget(_harness(ThemeId.obsidian));
    await tester.pump();

    expect(find.text(l.t('wc.noSessions')), findsOneWidget);
    expect(find.text(l.t('obs.wc.heroTitle')), findsOneWidget);
    final scan = tester.widget<ObsidianButton>(find.byKey(const ValueKey('obs-wc-scan')));
    expect(scan.onPressed, isNotNull);
    expect(scan.loading, isFalse);
  });
}
