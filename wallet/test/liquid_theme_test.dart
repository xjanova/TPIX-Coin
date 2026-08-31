/// TPIX Wallet — Liquid theme + bottom nav tests
///
/// หมายเหตุ: ไม่แตะ LiquidTheme().buildLight/Dark() ในเทสโดยตรง เพราะธีมใช้
/// google_fonts ซึ่งพยายามโหลดฟอนต์ผ่านเน็ต → โยน exception ใน sandbox ของเทส
/// จึงทดสอบ "สัญญา" ที่สำคัญแทน: ธีมถูกลงทะเบียน + แถบเมนูเรนเดอร์ครบ
/// (โดยประกอบ TpixThemeExtension เองแบบไม่พึ่งฟอนต์ออนไลน์)
///
/// Developed by Xman Studio
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_theme.dart';
import 'package:tpix_wallet/core/theme_provider.dart';
import 'package:tpix_wallet/core/themes/theme_bundle.dart';
import 'package:tpix_wallet/widgets/liquid_nav_bar.dart';

Widget _navHarness({required ThemeData theme, required VoidCallback onScan}) {
  return MaterialApp(
    theme: theme,
    home: Scaffold(
      bottomNavigationBar: LiquidNavBar(
        currentIndex: 0,
        scanLabel: 'สแกน',
        onScanTap: onScan,
        items: [
          LiquidNavItem(
              icon: Icons.home_outlined,
              activeIcon: Icons.home_rounded,
              label: 'หน้าหลัก',
              onTap: () {}),
          LiquidNavItem(
              icon: Icons.receipt_long_outlined,
              activeIcon: Icons.receipt_long_rounded,
              label: 'ประวัติ',
              onTap: () {}),
          LiquidNavItem(
              icon: Icons.swap_horiz_outlined,
              activeIcon: Icons.swap_horiz_rounded,
              label: 'แลก',
              onTap: () {}),
          LiquidNavItem(
              icon: Icons.settings_outlined,
              activeIcon: Icons.settings_rounded,
              label: 'ตั้งค่า',
              onTap: () {}),
        ],
      ),
      body: const SizedBox.expand(),
    ),
  );
}

void main() {
  group('Liquid theme registration', () {
    test('ธีมลิควิดอยู่ใน registry และเรียกด้วย id ได้', () {
      final ids = ThemeProvider.registry.map((t) => t.id).toList();
      expect(ids, contains(ThemeId.liquid));

      final provider = ThemeProvider();
      final bundle = provider.bundleFor(ThemeId.liquid);
      expect(bundle.id, ThemeId.liquid);
      expect(bundle.nameTh, isNotEmpty);
      expect(bundle.nameEn, isNotEmpty);
      // ธีมนี้ต้องรองรับโหมดสว่าง (จุดขายคือ "สดใส")
      expect(bundle.supportsLight, isTrue);
    });

    test('คีย์ liquid ที่บันทึกไว้ อ่านกลับมาได้ถูกตัว', () {
      expect(ThemeId.fromKey('liquid'), ThemeId.liquid);
      // คีย์แปลกปลอม → ตกกลับไปคลาสสิก ไม่ throw
      expect(ThemeId.fromKey('ไม่มีธีมนี้'), ThemeId.classic);
      expect(ThemeId.fromKey(null), ThemeId.classic);
    });

    test('ทุกธีมใน registry มี id ไม่ซ้ำกัน', () {
      final ids = ThemeProvider.registry.map((t) => t.id).toList();
      expect(ids.toSet().length, ids.length);
    });
  });

  group('LiquidNavBar', () {
    testWidgets('แสดงครบ 4 เมนู + ป้ายปุ่มสแกน', (tester) async {
      await tester.pumpWidget(_navHarness(theme: testTheme(), onScan: () {}));
      await tester.pump();

      expect(find.text('หน้าหลัก'), findsOneWidget);
      expect(find.text('ประวัติ'), findsOneWidget);
      expect(find.text('แลก'), findsOneWidget);
      expect(find.text('ตั้งค่า'), findsOneWidget);
      expect(find.text('สแกน'), findsOneWidget);
      // ไอคอนปุ่มกลาง
      expect(find.byKey(LiquidNavBar.scanButtonKey), findsOneWidget);
    });

    testWidgets('กดปุ่มสแกนตรงกลางแล้วยิง callback', (tester) async {
      var tapped = 0;
      await tester.pumpWidget(
        _navHarness(theme: testTheme(), onScan: () => tapped++),
      );
      await tester.pump();

      await tester.tap(find.byKey(LiquidNavBar.scanButtonKey));
      await tester.pump();

      expect(tapped, 1);
    });

    testWidgets('เมนูที่ active ใช้ไอคอนแบบทึบ (บอกตำแหน่งผู้ใช้)',
        (tester) async {
      await tester.pumpWidget(_navHarness(theme: testTheme(), onScan: () {}));
      await tester.pump();

      // index 0 active → home_rounded ไม่ใช่ home_outlined
      expect(find.byIcon(Icons.home_rounded), findsOneWidget);
      expect(find.byIcon(Icons.home_outlined), findsNothing);
      expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
    });

    testWidgets('เรนเดอร์ได้ทั้งโหมดสว่างและมืดโดยไม่ overflow',
        (tester) async {
      for (final dark in [false, true]) {
        await tester.pumpWidget(
          _navHarness(theme: testTheme(dark: dark), onScan: () {}),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
      }
    });
  });
}
