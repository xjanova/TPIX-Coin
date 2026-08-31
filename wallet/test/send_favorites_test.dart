/// TPIX Wallet — เทสต์รายการโปรดในหน้าโอน
/// ผู้ใช้ขอ: "เพิ่มรายการโปรดที่อยู่ในการโอน บันทึกได้ว่าใคร"
///
/// ⚠️ ข้อควรรู้: ใน testWidgets เวลาเป็นเวลาปลอม (FakeAsync)
/// งาน I/O จริงอย่าง sqlite จะไม่มีวันเสร็จถ้าเรียกตรงๆ ในตัวเทสต์
/// → เตรียมข้อมูลใน setUp (นอกเขตเวลาปลอม) และห่อ pumpWidget ด้วย runAsync
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tpix_wallet/core/locale_provider.dart';
import 'package:tpix_wallet/models/contact.dart';
import 'package:tpix_wallet/providers/wallet_provider.dart';
import 'package:tpix_wallet/screens/send_screen.dart';
import 'package:tpix_wallet/services/db_service.dart';

import 'support/test_theme.dart';

const _alice = '0xaaaa000000000000000000000000000000001111';
const _bob = '0xbbbb000000000000000000000000000000002222';

Widget _harness({String? initialAddress}) => MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => WalletProvider()),
        ChangeNotifierProvider(create: (_) => LocaleProvider()),
      ],
      child: MaterialApp(
        theme: testTheme(),
        home: SendScreen(initialAddress: initialAddress),
      ),
    );

/// เปิดหน้าโอนแล้วรอให้โหลดรายการโปรดจากฐานข้อมูลเสร็จจริง
Future<void> _open(WidgetTester tester, {String? initialAddress}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  await tester.runAsync(() async {
    await tester.pumpWidget(_harness(initialAddress: initialAddress));
    // ปล่อยให้คิวรี sqlite จริงเดินจนจบ
    await Future<void>.delayed(const Duration(milliseconds: 300));
  });
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

Future<void> _resetDb() async {
  await DbService.close();
  await databaseFactory.deleteDatabase(
    '${await databaseFactory.getDatabasesPath()}/tpix_wallet.db',
  );
}

/// ดาวในช่องที่อยู่เท่านั้น — ปุ่ม "รายการโปรด" ด้านบนก็ใช้ไอคอนดาวเหมือนกัน
/// ถ้าไม่จำกัดขอบเขต เทสต์จะไปเจอดาวของปุ่มนั้นแทน
Finder _starInField(IconData icon) => find.descendant(
      of: find.byType(TextField).first,
      matching: find.byIcon(icon),
    );

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  tearDownAll(() async => DbService.close());

  group('มีรายการโปรดอยู่แล้ว', () {
    setUp(() async {
      await _resetDb();
      await DbService.saveContact(
          const Contact(address: _alice, name: 'น้องเอ', createdAt: 1));
      await DbService.saveContact(
          const Contact(address: _bob, name: 'พี่บี', createdAt: 2));
    });

    testWidgets('โชว์เป็นชิปทางลัดให้กดทีเดียวติด', (tester) async {
      await _open(tester);
      expect(find.text('น้องเอ'), findsWidgets);
      expect(find.text('พี่บี'), findsWidgets);
    });

    testWidgets('กดชิป → เติมที่อยู่ลงช่องผู้รับ + ดาวเปลี่ยนเป็นทึบ',
        (tester) async {
      await _open(tester);

      expect(_starInField(Icons.star_border_rounded), findsOneWidget,
          reason: 'ยังไม่ได้เลือกใคร ดาวต้องเป็นโครง');

      await tester.tap(find.text('พี่บี').first);
      await tester.pump();

      final field = tester.widget<TextField>(find.byType(TextField).first);
      expect(field.controller?.text, _bob);
      expect(_starInField(Icons.star_rounded), findsOneWidget,
          reason: 'ที่อยู่ที่บันทึกชื่อไว้แล้ว ดาวต้องทึบ');
    });

    testWidgets('เปิดจากการสแกน QR ของคนที่บันทึกไว้ → ขึ้นชื่อให้เลย',
        (tester) async {
      // QR อาจส่งที่อยู่มาเป็นตัวพิมพ์ใหญ่ (checksum) — ต้องยังจับคู่ได้
      await _open(tester,
          initialAddress: '0xAAAA000000000000000000000000000000001111');

      expect(find.text('น้องเอ'), findsWidgets,
          reason: 'ตรงกับรายการโปรดแล้วต้องโชว์ชื่อ ไม่ใช่เลข 0x… ล้วน');
      expect(_starInField(Icons.star_rounded), findsOneWidget);
    });

    testWidgets('ที่อยู่ที่ยังไม่เคยบันทึก → ดาวยังเป็นโครง', (tester) async {
      await _open(tester,
          initialAddress: '0xcccc000000000000000000000000000000003333');

      expect(_starInField(Icons.star_border_rounded), findsOneWidget);
      expect(_starInField(Icons.star_rounded), findsNothing);
    });
  });

  group('ยังไม่มีรายการโปรด', () {
    setUp(_resetDb);

    testWidgets('ไม่มีแถวชิปมากินที่บนหน้าจอ', (tester) async {
      await _open(tester);
      expect(find.byType(ListView), findsNothing);
      expect(_starInField(Icons.star_border_rounded), findsOneWidget);
    });
  });
}
