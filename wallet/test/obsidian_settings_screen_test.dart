/// TPIX Wallet — หน้าตั้งค่าธีม Obsidian
///
/// ล็อกไว้:
///   1. ทุกปุ่มของหน้าเดิมยังอยู่ครบ (ภาษา ธีม สำรองวลี ตัวตน ประวัติเซ็น ล็อก WalletConnect
///      เครือข่าย รายงานปัญหา ตรวจอัปเดต ลบข้อมูล)
///   2. ลบข้อมูลทั้งหมด = มีกล่องยืนยันก่อน · กดยกเลิก = ไม่ลบอะไร
///   3. กระเป๋าที่นำเข้าด้วยคีย์ (ไม่มีวลี) กดสำรอง = บอกเหตุผล ไม่เปิดช่อง PIN
///   4. ไม่มีป้าย "สำรองแล้ว" (แอปไม่รู้ว่าผู้ใช้สำรองจริงหรือยัง)
///   5. แผ่นเลือกภาษาเปลี่ยนภาษาได้จริง
///
/// Developed by Xman Studio
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tpix_wallet/core/locale_provider.dart';
import 'package:tpix_wallet/core/theme_provider.dart';
import 'package:tpix_wallet/core/themes/theme_bundle.dart';
import 'package:tpix_wallet/models/wallet_info.dart';
import 'package:tpix_wallet/providers/update_provider.dart';
import 'package:tpix_wallet/providers/wallet_provider.dart';
import 'package:tpix_wallet/screens/settings_screen.dart';
import 'package:tpix_wallet/services/walletconnect_service.dart';
import 'package:tpix_wallet/widgets/obsidian/obsidian.dart';

import 'support/test_theme.dart';

const _me = '0xD2eAB07809921fcB36c7AB72D7B5D8D2C12A67d7';

class _FakeWallet extends WalletProvider {
  _FakeWallet({this.phrase});
  final String? phrase;
  int deletes = 0;

  @override
  String? get address => _me;
  @override
  String? get mnemonic => phrase;
  @override
  List<WalletInfo> get wallets => [WalletInfo(slot: 1, name: 'Main Wallet', address: _me)];
  @override
  WalletInfo? get activeWallet => wallets.first;
  @override
  Future<void> deleteWallet() async => deletes++;
}

Widget _app(WalletProvider wallet, LocaleProvider locale) => MultiProvider(
      providers: [
        ChangeNotifierProvider<WalletProvider>.value(value: wallet),
        ChangeNotifierProvider.value(value: locale),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => WalletConnectService()),
        ChangeNotifierProvider(create: (_) => UpdateProvider()),
      ],
      child: MaterialApp(
        theme: testTheme(themeId: ThemeId.obsidian),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: const SettingsScreen(),
      ),
    );

Future<void> _scrollTo(WidgetTester tester, Finder f) async {
  await tester.scrollUntilVisible(f, 120, scrollable: find.byType(Scrollable).first);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
        appName: 'TPIX Wallet', packageName: 'x', version: '1.13.38', buildNumber: '65', buildSignature: '');
  });

  testWidgets('ทุกปุ่มของหน้าเดิมยังอยู่ + แถบเมนูล่าง + ไม่มีป้าย "สำรองแล้ว"', (tester) async {
    final l = LocaleProvider();
    await tester.pumpWidget(_app(_FakeWallet(phrase: 'a b c'), l));
    await tester.pumpAndSettle();

    expect(find.byType(NotchedNavBar), findsOneWidget);
    for (final key in [
      'settings.language',
      'settings.theme',
      'obs.set.backup',
      'identity.title',
      'obs.set.signHistory',
      'obs.set.lockNow',
      'obs.set.wc',
      'obs.set.network',
      'obs.set.report',
      'obs.set.checkUpdate',
      'obs.set.deleteAll',
    ]) {
      await _scrollTo(tester, find.text(l.t(key)));
      expect(find.text(l.t(key)), findsOneWidget, reason: key);
    }
    expect(find.text('สำรองแล้ว'), findsNothing);
    expect(find.text('v1.13.38'), findsOneWidget);
  });

  testWidgets('ลบข้อมูลทั้งหมด → กล่องยืนยันก่อน · ยกเลิก = ไม่ลบ', (tester) async {
    final l = LocaleProvider();
    final wallet = _FakeWallet(phrase: 'a b c');
    await tester.pumpWidget(_app(wallet, l));
    await tester.pumpAndSettle();
    await _scrollTo(tester, find.text(l.t('obs.set.deleteAll')));
    await tester.tap(find.text(l.t('obs.set.deleteAll')));
    await tester.pumpAndSettle();
    expect(find.text(l.t('settings.deleteConfirm')), findsOneWidget);
    expect(wallet.deletes, 0);
    await tester.tap(find.text(l.t('wallets.cancel')));
    await tester.pumpAndSettle();
    expect(wallet.deletes, 0);
  });

  testWidgets('นำเข้าด้วยคีย์ (ไม่มีวลี) → กดสำรองได้เหตุผล ไม่เปิดช่อง PIN', (tester) async {
    final l = LocaleProvider();
    await tester.pumpWidget(_app(_FakeWallet(), l));
    await tester.pumpAndSettle();
    expect(find.text(l.t('obs.set.importedKey')), findsOneWidget);
    await tester.tap(find.text(l.t('obs.set.backup')));
    await tester.pump();
    expect(find.text(l.t('settings.noMnemonic')), findsOneWidget);
    expect(find.text(l.t('settings.enterPin')), findsNothing);
  });

  testWidgets('แผ่นเลือกภาษา → เปลี่ยนเป็นอังกฤษได้จริง', (tester) async {
    final l = LocaleProvider();
    await tester.pumpWidget(_app(_FakeWallet(phrase: 'a'), l));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l.t('settings.language')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    expect(l.locale, 'en');
    expect(find.text('Settings'), findsWidgets); // หัวหน้า + แท็บเมนูล่าง
  });
}
