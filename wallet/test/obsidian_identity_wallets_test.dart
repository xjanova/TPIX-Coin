/// TPIX Wallet — หน้าตัวตน / ประวัติการเซ็น / แผ่นรายการกระเป๋า ธีม Obsidian
///
/// ล็อกไว้:
///   1. ตัวตน: ครบ 3 ขั้น + ปุ่มทดสอบกู้คืนโผล่เฉพาะเมื่อปกป้องแล้ว ≥ 2 อย่าง (เงื่อนไขเดิม)
///   2. ลบพิกัดต้องยืนยันก่อน · ยกเลิก = พิกัดยังอยู่
///   3. แผ่นกระเป๋า: ลบกระเป๋าผ่านเมนู = กล่องยืนยันก่อน ไม่ลบทันที
///   4. ประวัติการเซ็นอ่านไม่ได้ = หน้าว่าง ไม่ใช่วงหมุนค้าง
///
/// Developed by Xman Studio
library;

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tpix_wallet/core/locale_provider.dart';
import 'package:tpix_wallet/core/themes/theme_bundle.dart';
import 'package:tpix_wallet/models/wallet_info.dart';
import 'package:tpix_wallet/providers/wallet_provider.dart';
import 'package:tpix_wallet/screens/identity_screen.dart';
import 'package:tpix_wallet/screens/sign_history_screen.dart';
import 'package:tpix_wallet/screens/wallet_list_sheet.dart';

import 'support/test_theme.dart';

const _a = '0xD2eAB07809921fcB36c7AB72D7B5D8D2C12A67d7';
const _b = '0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed';

class _FakeWallet extends WalletProvider {
  int deleted = 0;
  @override
  List<WalletInfo> get wallets => [
        WalletInfo(slot: 1, name: 'Main Wallet', address: _a),
        WalletInfo(slot: 2, name: 'Savings', address: _b),
      ];
  @override
  int get walletCount => 2;
  @override
  int get activeSlot => 1;
  @override
  Future<void> deleteWalletBySlot(int slot) async => deleted++;
}

Widget _app(Widget home, {WalletProvider? wallet}) => MultiProvider(
      providers: [
        ChangeNotifierProvider<WalletProvider>.value(value: wallet ?? _FakeWallet()),
        ChangeNotifierProvider(create: (_) => LocaleProvider()),
      ],
      child: MaterialApp(
        theme: testTheme(themeId: ThemeId.obsidian),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: home,
      ),
    );

void main() {
  final l = LocaleProvider();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('ตัวตน: ปกป้อง 1 อย่าง → ครบ 3 ขั้น แต่ยังไม่มีปุ่มทดสอบกู้คืน', (tester) async {
    FlutterSecureStorage.setMockInitialValues({'tpix_identity_questions': '[]'});
    await tester.pumpWidget(_app(const IdentityScreen()));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text(l.t('identity.questions')), findsOneWidget);
    expect(find.text(l.t('identity.location')), findsOneWidget);
    expect(find.text(l.t('identity.recoveryPin')), findsOneWidget);
    expect(find.text(l.t('identity.testRecovery')), findsNothing);
  });

  testWidgets('ตัวตน: ลบพิกัด = ต้องยืนยัน · ยกเลิกแล้วพิกัดยังอยู่', (tester) async {
    FlutterSecureStorage.setMockInitialValues({
      'tpix_identity_questions': '[]',
      'tpix_identity_locations': '[{"h":"x","label":"บ้าน","registeredAt":"2026-10-01T10:00:00Z"}]',
    });
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(const IdentityScreen()));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text(l.t('identity.testRecovery')), findsOneWidget, reason: 'ปกป้องแล้ว 2 อย่าง');
    expect(find.text('บ้าน'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Remove บ้าน'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Remove Location?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('บ้าน'), findsOneWidget);
  });

  testWidgets('แผ่นกระเป๋า: ลบผ่านเมนู = กล่องยืนยันก่อน', (tester) async {
    final wallet = _FakeWallet();
    await tester.pumpWidget(_app(
      Builder(
        builder: (context) => TextButton(onPressed: () => WalletListSheet.show(context), child: const Text('open')),
      ),
      wallet: wallet,
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Savings'), findsOneWidget);
    expect(find.text(l.t('wallets.active')), findsOneWidget);

    await tester.tap(find.byIcon(Icons.more_vert_rounded).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text(l.t('wallets.delete')));
    await tester.pumpAndSettle();
    expect(find.text(l.t('wallets.deleteConfirm')), findsOneWidget);
    expect(wallet.deleted, 0);
    await tester.tap(find.text(l.t('wallets.cancel')));
    await tester.pumpAndSettle();
    expect(wallet.deleted, 0);
  });

  testWidgets('ประวัติการเซ็น: อ่านฐานข้อมูลไม่ได้ → หน้าว่าง ไม่ใช่วงหมุนค้าง', (tester) async {
    await tester.pumpWidget(_app(const SignHistoryScreen()));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('ยังไม่มีประวัติการเซ็น'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
