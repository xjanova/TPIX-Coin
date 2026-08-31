// เทสต์กันของเดิมกลับมา: ปุ่มสแกนกลางบนแถบเมนูล่างต้อง "กดติดทั้งใบ"
//
// บั๊กที่เคยเกิด: แถบเมนูถูกกำหนดความสูงตายตัว 110px แต่ปุ่มสแกนที่ยกนูน
// ต้องการ 142px → ยอดปุ่มโผล่พ้นกรอบพ่อ Flutter เลยไม่ hit-test ให้
// ผู้ใช้เห็นปุ่มเต็มใบแต่กดตรงยอดแล้วเงียบ
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tpix_wallet/widgets/liquid_nav_bar.dart';

import 'support/test_theme.dart';

Widget _harness(VoidCallback onScan, {double textScale = 1.0}) {
  return MaterialApp(
    theme: testTheme(),
    builder: (ctx, child) => MediaQuery(
      data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: Scaffold(
      extendBody: true,
      body: const SizedBox.expand(),
      bottomNavigationBar: LiquidNavBar(
        currentIndex: 0,
        scanLabel: 'สแกน',
        onScanTap: onScan,
        items: List.generate(
          4,
          (i) => LiquidNavItem(
            icon: Icons.home_outlined,
            activeIcon: Icons.home_rounded,
            label: 'x$i',
            onTap: () {},
          ),
        ),
      ),
    ),
  );
}

void main() {
  for (final scale in [1.0, 1.3]) {
    testWidgets('ปุ่มสแกนกดติดทั้งใบ (ตัวอักษร x$scale)', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      var taps = 0;
      await tester.pumpWidget(_harness(() => taps++, textScale: scale));
      await tester.pump(const Duration(milliseconds: 100));

      final bar = tester.getRect(find.byType(LiquidNavBar));
      final icon = tester.getRect(find.byIcon(Icons.qr_code_scanner_rounded));

      // 1) ปุ่มต้องอยู่ในกรอบแถบทั้งใบ ไม่ล้นออกไปข้างบน
      expect(icon.top, greaterThanOrEqualTo(bar.top),
          reason: 'ไอคอนสแกนล้นพ้นกรอบแถบ ${bar.top - icon.top}px → ส่วนที่ล้นกดไม่ติด');

      // 2) กดกลางไอคอน
      await tester.tapAt(icon.center);
      await tester.pump();
      expect(taps, 1, reason: 'กดกลางปุ่มแล้วไม่ยิง onScanTap');

      // 3) กดยอดวงกลม (สูงกว่ากลางไอคอน 28px) — จุดที่เคยตาย
      await tester.tapAt(icon.center - const Offset(0, 28));
      await tester.pump();
      expect(taps, 2, reason: 'ยอดปุ่มสแกนยังกดไม่ติด (เขตตายเดิม)');

      // 4) กดขอบข้างของปุ่ม (ช่องว่างในกล่อง ไม่ใช่พิกเซลที่มีสี)
      await tester.tapAt(icon.center + const Offset(26, 0));
      await tester.pump();
      expect(taps, 3, reason: 'ขอบข้างปุ่มกดไม่ติด — ต้องตั้ง HitTestBehavior.opaque');
    });
  }

  testWidgets('4 ช่องเมนูข้างๆ ยังกดได้ตามเดิม', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final hits = <int>[];
    await tester.pumpWidget(MaterialApp(
      theme: testTheme(),
      home: Scaffold(
        extendBody: true,
        body: const SizedBox.expand(),
        bottomNavigationBar: LiquidNavBar(
          currentIndex: 0,
          scanLabel: 'สแกน',
          onScanTap: () {},
          items: List.generate(
            4,
            (i) => LiquidNavItem(
              icon: Icons.home_outlined,
              activeIcon: Icons.home_rounded,
              label: 'x$i',
              onTap: () => hits.add(i),
            ),
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 100));

    for (var i = 0; i < 4; i++) {
      await tester.tap(find.text('x$i'));
      await tester.pump();
    }
    expect(hits, [0, 1, 2, 3]);
  });
}
