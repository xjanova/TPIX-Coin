/// TPIX Wallet — วิดเจ็ตธีม Obsidian
///
/// ล็อกพฤติกรรมที่ผู้ใช้เห็นทันทีถ้าพัง:
///   1. ปุ่มสแกนกดติดทั้งใบ รวม 13px ที่โผล่พ้นขอบแถบ (บั๊กเดิมของ LiquidNavBar)
///   2. เมนู 4 ช่องกดได้ และปุ่มสแกนไม่แย่งการแตะของเมนูข้าง ๆ
///   3. ชิปเลือกเชน/การปัดบัตร "ขอ" เปลี่ยนเชนผ่าน callback เท่านั้น
///      (สำรับไม่สลับเองจนกว่าเชนจริงจะเปลี่ยน) และกดชิปที่เลือกอยู่แล้วไม่ยิงซ้ำ
///   4. เปิด "ลดภาพเคลื่อนไหว" แล้วไม่มีแอนิเมชันค้าง (pumpAndSettle จบได้)
///
/// ใช้ testTheme (ไม่มี ObsidianStyle) → ไม่แตะ GoogleFonts / ไม่ต่อเน็ต
///
/// Developed by Xman Studio
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tpix_wallet/core/themes/theme_bundle.dart';
import 'package:tpix_wallet/widgets/obsidian/obsidian.dart';

import 'support/test_theme.dart';

ChainCardData _card(ObsidianChainArt art) => ChainCardData(
      art: art,
      chainName: art.shortLabel,
      balanceLabel: 'ยอดบนเชนนี้',
      amount: '1.00',
      unit: art.shortLabel,
      address: '0xD2eA…67d7',
      gasText: 'gas',
    );

Widget _app(Widget child, {bool reduceMotion = false, double textScale = 1}) => MaterialApp(
      theme: testTheme(themeId: ThemeId.obsidian),
      builder: (ctx, c) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(
          disableAnimations: reduceMotion,
          textScaler: TextScaler.linear(textScale),
        ),
        child: c!,
      ),
      home: child,
    );

Widget _navHarness({required VoidCallback onScan, required void Function(int) onItem}) => Scaffold(
      extendBody: true,
      body: const SizedBox.expand(),
      bottomNavigationBar: NotchedNavBar(
        currentIndex: 0,
        scanLabel: 'สแกน',
        onScanTap: onScan,
        items: [
          for (var i = 0; i < 4; i++)
            NotchedNavItem(asset: ObsidianIcons.home, label: 'm$i', onTap: () => onItem(i)),
        ],
      ),
    );

void main() {
  group('NotchedNavBar', () {
    for (final scale in [1.0, 1.3]) {
      testWidgets('ปุ่มสแกนกดติดทั้งใบ รวมส่วนที่โผล่พ้นแถบ (ตัวอักษร x$scale)', (tester) async {
        tester.view.physicalSize = const Size(1170, 2532);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);

        var taps = 0;
        await tester.pumpWidget(_app(_navHarness(onScan: () => taps++, onItem: (_) {}), textScale: scale));
        await tester.pump(const Duration(milliseconds: 100));

        final bar = tester.getRect(find.byType(NotchedNavBar));
        final orb = tester.getRect(find.byKey(NotchedNavBar.scanButtonKey));

        // กรอบของแถบต้องครอบปุ่มทั้งใบ ไม่งั้นส่วนที่ล้นกดไม่ติด
        expect(orb.top, greaterThanOrEqualTo(bar.top), reason: 'ปุ่มสแกนล้นกรอบแถบ ${bar.top - orb.top}px');
        // ปุ่มจมลงในแถบ: โผล่พ้นขอบบนของตัวแถบ 13px (20% ของ 66)
        expect(orb.height, closeTo(66, 0.01));

        await tester.tapAt(orb.center);
        await tester.pump();
        expect(taps, 1, reason: 'กดกลางปุ่มไม่ติด');

        // ยอดปุ่ม — จุดที่อยู่เหนือขอบแถบกระจก
        await tester.tapAt(Offset(orb.center.dx, orb.top + 4));
        await tester.pump();
        expect(taps, 2, reason: 'ยอดปุ่มที่โผล่พ้นแถบกดไม่ติด');

        // ขอบข้างปุ่ม
        await tester.tapAt(orb.center + const Offset(28, 0));
        await tester.pump();
        expect(taps, 3, reason: 'ขอบข้างปุ่มกดไม่ติด');
      });
    }

    testWidgets('เมนู 4 ช่องกดได้ตามลำดับ และไม่ไปยิงปุ่มสแกน', (tester) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      final hits = <int>[];
      var scans = 0;
      await tester.pumpWidget(_app(_navHarness(onScan: () => scans++, onItem: hits.add)));
      await tester.pump(const Duration(milliseconds: 100));

      for (var i = 0; i < 4; i++) {
        await tester.tap(find.text('m$i'));
        await tester.pump();
      }
      expect(hits, [0, 1, 2, 3]);
      expect(scans, 0);
    });

    testWidgets('รูปแถบ: รอยเว้าลึกถึง y=60 ที่กึ่งกลาง และอยู่กลางเสมอเมื่อจอกว้างขึ้น', (tester) async {
      for (final w in [358.0, 398.0]) {
        final p = NotchedNavBar.barPath(w);
        // ใต้รอยเว้า (กลาง, y=50) อยู่นอกแถบ · ก้นรอยเว้าลงไป (y=70) อยู่ในแถบ
        expect(p.contains(Offset(w / 2, 50)), isFalse);
        expect(p.contains(Offset(w / 2, 70)), isTrue);
        expect(p.contains(const Offset(60, 40)), isTrue);
      }
    });

    testWidgets('ลดภาพเคลื่อนไหว → ไม่มีแอนิเมชันค้าง', (tester) async {
      await tester.pumpWidget(_app(_navHarness(onScan: () {}, onItem: (_) {}), reduceMotion: true));
      await tester.pumpAndSettle();
      expect(find.byType(NotchedNavBar), findsOneWidget);
    });
  });

  group('ChainChips + ChainCardDeck', () {
    testWidgets('กดชิป = ขอเปลี่ยนเชน · ชิปที่เลือกอยู่แล้วไม่ยิงซ้ำ', (tester) async {
      final picks = <int>[];
      await tester.pumpWidget(_app(Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: ChainChips(chains: ObsidianChainArt.all, activeIndex: 0, onSelect: picks.add),
        ),
      )));
      await tester.pump();

      await tester.tap(find.text('TPIX'));
      await tester.tap(find.text('BNB'));
      await tester.tap(find.text('ETH'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(picks, [1, 3]);
    });

    testWidgets('ปัดบัตรซ้าย = ขอใบถัดไป · สำรับพลิกตามเมื่อเชนจริงเปลี่ยน', (tester) async {
      final picks = <int>[];
      var active = 0;
      late StateSetter set;
      await tester.pumpWidget(_app(Scaffold(
        body: StatefulBuilder(builder: (ctx, s) {
          set = s;
          return Padding(
            padding: const EdgeInsets.all(24),
            child: ChainCardDeck(
              cards: [for (final a in ObsidianChainArt.all) _card(a)],
              activeIndex: active,
              onSelect: picks.add,
            ),
          );
        }),
      )));
      await tester.pump();

      await tester.fling(find.byType(ChainCardDeck), const Offset(-200, 0), 1200);
      await tester.pump();
      expect(picks, [1]);

      // หน้าแรกสลับเชนจริงแล้ว → สำรับพลิก แล้วนิ่งได้ (ไม่มีแอนิเมชันค้าง)
      set(() => active = 1);
      await tester.pump();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.fling(find.byType(ChainCardDeck), const Offset(200, 0), 1200);
      await tester.pump();
      expect(picks, [1, 0]);
    });

    testWidgets('ยอดยาวมากไม่ล้นบัตร', (tester) async {
      await tester.pumpWidget(_app(Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: ChainCardDeck(
            cards: [
              for (final a in ObsidianChainArt.all)
                ChainCardData(
                  art: a,
                  chainName: 'BNB Smart Chain with a very very long name',
                  balanceLabel: 'ยอดบนเชนนี้',
                  amount: '123,456,789,012.123456',
                  unit: 'TPIX',
                  subline: '≈ \$12,345,678.90 · ▲ 12.34% วันนี้',
                  address: '0xD2eA…67d7',
                  gasText: 'ค่าแก๊สจ่ายเป็น BNB',
                ),
            ],
            activeIndex: 2,
            onSelect: (_) {},
          ),
        ),
      )));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });
}
