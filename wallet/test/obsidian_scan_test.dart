/// TPIX Wallet — เทสต์หน้าสแกนธีม Obsidian
///
/// ล็อกพฤติกรรม:
///   1. แปลงมุมโค้ดจากภาพกล้อง → ตำแหน่งกรอบบนจอ ถูกต้อง (คณิตเดียวกับ mobile_scanner)
///      ข้อมูลเพี้ยน → ย่อกลางช่องเล็ง ไม่ throw (แอนิเมชันห้ามทำให้สแกนพัง)
///   2. Obsidian: ค่าที่สแกนได้ส่งให้ผู้เรียก "หลัง" กรอบดีดจบ (ค่าเดิมเป๊ะ) และส่งครั้งเดียว
///   3. ปิดหน้าระหว่างกรอบดีด = ไม่ส่งค่า (ไม่เปิดหน้าส่งทับหน้าที่ปิดไปแล้ว)
///   4. ปิดภาพเคลื่อนไหว = ส่งทันทีเหมือนเดิม
///   5. แท็บ "QR รับเงิน" โชว์เฉพาะตอนสแกนจ่าย
///
/// Developed by Xman Studio
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import 'package:tpix_wallet/core/locale_provider.dart';
import 'package:tpix_wallet/core/themes/theme_bundle.dart';
import 'package:tpix_wallet/widgets/obsidian/scan_viewfinder.dart';
import 'package:tpix_wallet/widgets/qr_scanner_screen.dart';

import 'support/test_theme.dart';

const _addr = '0x8b3f2e9d1c4a7b6e5f0d3c2b1a9e8d7c6b5aa91c';

void main() {
  group('ScanGeometry.snapFor', () {
    const view = Size(390, 844);

    test('ภาพกล้องขนาด 2 เท่าของจอ (cover) → กลาง/ขนาดตรง', () {
      // โค้ด 150px กลางจอ (195, 400) ในพิกัดจอ → ภาพกล้อง x2
      final corners = [
        const Offset(120, 325),
        const Offset(270, 325),
        const Offset(270, 475),
        const Offset(120, 475),
      ].map((o) => o * 2).toList();
      final s = ScanGeometry.snapFor(corners: corners, imageSize: const Size(780, 1688), view: view);
      expect(s.center.dx, closeTo(195, 0.01));
      expect(s.center.dy, closeTo(400, 0.01));
      expect(s.scale, closeTo((150 + 28) / ScanGeometry.windowSize, 1e-9));
      expect(s.angle, closeTo(0, 1e-9));
    });

    test('ภาพกล้องกว้างกว่าจอ → หักส่วนที่ล้นออกด้านข้าง', () {
      // ภาพ 1000x844 บนจอ 390x844 (cover: อัตรา 1 → ล้นซ้ายขวาข้างละ 305)
      final corners = [const Offset(445, 300), const Offset(555, 300), const Offset(555, 410), const Offset(445, 410)];
      final s = ScanGeometry.snapFor(corners: corners, imageSize: const Size(1000, 844), view: view);
      expect(s.center.dx, closeTo(195, 0.01));
      expect(s.center.dy, closeTo(355, 0.01));
    });

    test('โค้ดเอียง → มุมเอียงตาม และพับให้อยู่ใน ±45°', () {
      const a = 10 * math.pi / 180;
      Offset r(Offset p) => Offset(p.dx * math.cos(a) - p.dy * math.sin(a), p.dx * math.sin(a) + p.dy * math.cos(a));
      const c = Offset(195, 357);
      final base = [const Offset(-60, -60), const Offset(60, -60), const Offset(60, 60), const Offset(-60, 60)];
      final s = ScanGeometry.snapFor(corners: [for (final p in base) c + r(p)], imageSize: view, view: view);
      expect(s.angle, closeTo(a, 1e-6));

      // โค้ดกลับหัว (ลำดับมุมหมุนไป 180°) → กรอบสมมาตร ไม่ต้องหมุนครึ่งรอบ
      final flipped = [for (final p in base) c + r(Offset(-p.dx, -p.dy))];
      final f = ScanGeometry.snapFor(corners: flipped, imageSize: view, view: view);
      expect(f.angle, closeTo(a, 1e-6));
    });

    test('ข้อมูลไม่พอ/เพี้ยน → กลางช่องเล็ง ย่อ 0.8 ไม่ throw', () {
      final window = ScanGeometry.windowFor(view);
      final none = ScanGeometry.snapFor(corners: const [], imageSize: const Size(780, 1688), view: view);
      expect(none, ScanSnap(center: window.center, scale: 0.8, angle: 0));
      final noSize = ScanGeometry.snapFor(
          corners: const [Offset(0, 0), Offset(10, 0), Offset(10, 10), Offset(0, 10)], imageSize: Size.zero, view: view);
      expect(noSize.center, window.center);
      final tiny = ScanGeometry.snapFor(
          corners: const [Offset(100, 100), Offset(104, 100), Offset(104, 104), Offset(100, 104)],
          imageSize: view,
          view: view);
      expect(tiny.scale, 0.8, reason: 'โค้ดเล็กผิดปกติ = ข้อมูลน่าสงสัย');
      final outside = ScanGeometry.snapFor(
          corners: const [Offset(900, 900), Offset(1000, 900), Offset(1000, 1000), Offset(900, 1000)],
          imageSize: view,
          view: view);
      expect(outside.center, window.center);
    });

    test('โค้ดชิดขอบจอ → กรอบไม่หลุดจอ', () {
      final s = ScanGeometry.snapFor(
          corners: const [Offset(0, 0), Offset(120, 0), Offset(120, 120), Offset(0, 120)], imageSize: view, view: view);
      final half = ScanGeometry.windowSize * s.scale / 2;
      expect(s.center.dx, greaterThanOrEqualTo(half - 1e-9));
      expect(s.center.dy, greaterThanOrEqualTo(half - 1e-9));
    });
  });

  group('QRScannerScreen (Obsidian)', () {
    late void Function(BarcodeCapture) detect;

    setUp(() {
      QRScannerScreen.debugPreviewBuilder = (context, onDetect) {
        detect = onDetect;
        return const ColoredBox(color: Colors.black);
      };
    });
    tearDown(() => QRScannerScreen.debugPreviewBuilder = null);

    Widget app(Widget home, {ThemeId theme = ThemeId.obsidian, bool reduceMotion = false}) =>
        ChangeNotifierProvider(
          create: (_) => LocaleProvider(),
          child: MaterialApp(
            theme: testTheme(themeId: theme),
            builder: (ctx, c) => MediaQuery(
              data: MediaQuery.of(ctx).copyWith(disableAnimations: reduceMotion),
              child: c!,
            ),
            home: home,
          ),
        );

    BarcodeCapture capture() => const BarcodeCapture(
          barcodes: [
            Barcode(rawValue: _addr, corners: [Offset(120, 300), Offset(270, 300), Offset(270, 450), Offset(120, 450)]),
          ],
          size: Size(390, 844),
        );

    testWidgets('ส่งค่าเดิมหลังกรอบดีดจบ ครั้งเดียว', (tester) async {
      final got = <String>[];
      await tester.pumpWidget(app(QRScannerScreen(onScanned: got.add, onShowMyQr: () {})));
      await tester.pump();
      expect(find.text(LocaleProvider().t('obs.scan.myQr')), findsOneWidget);

      detect(capture());
      detect(capture()); // เฟรมซ้ำ
      await tester.pump(const Duration(milliseconds: 100));
      expect(got, isEmpty, reason: 'ยังอยู่ระหว่างกรอบดีด');
      expect(find.text(LocaleProvider().t('obs.scan.found')), findsOneWidget);

      await tester.pump(QRScannerScreen.lockHold);
      expect(got, [_addr]);
      await tester.pump(const Duration(seconds: 2));
      expect(got, [_addr]);
    });

    testWidgets('ปิดหน้าระหว่างกรอบดีด → ไม่ส่งค่า', (tester) async {
      final got = <String>[];
      final nav = GlobalKey<NavigatorState>();
      await tester.pumpWidget(ChangeNotifierProvider(
        create: (_) => LocaleProvider(),
        child: MaterialApp(
          navigatorKey: nav,
          theme: testTheme(themeId: ThemeId.obsidian),
          home: const Scaffold(),
        ),
      ));
      nav.currentState!.push(MaterialPageRoute(builder: (_) => QRScannerScreen(onScanned: got.add)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      detect(capture());
      await tester.pump(const Duration(milliseconds: 100));
      nav.currentState!.pop();
      await tester.pump(const Duration(seconds: 2));
      expect(got, isEmpty);
    });

    testWidgets('ปิดภาพเคลื่อนไหว → ส่งทันที', (tester) async {
      final got = <String>[];
      await tester.pumpWidget(app(QRScannerScreen(onScanned: got.add), reduceMotion: true));
      await tester.pump();
      expect(find.text(LocaleProvider().t('obs.scan.myQr')), findsNothing, reason: 'ไม่ใช่สแกนจ่าย = ไม่มีแท็บ');
      detect(capture());
      expect(got, [_addr]);
    });
  });
}
