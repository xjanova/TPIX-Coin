/// TPIX Wallet — เทสต์สมุดที่อยู่ (รายการโปรด) + การอัปเกรดฐานข้อมูล
///
/// จุดที่ต้องกันพลาดที่สุดคือ "ผู้ใช้เดิมที่มีฐานข้อมูลเวอร์ชัน 5 อยู่แล้ว"
/// ถ้า migration พัง = เปิดแอปไม่ได้ / ประวัติการโอนหาย
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tpix_wallet/models/contact.dart';
import 'package:tpix_wallet/services/db_service.dart';

int _now() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

Contact _c(String address, String name, {String? note}) => Contact(
      address: address,
      name: name,
      note: note,
      createdAt: _now(),
    );

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    // ฐานข้อมูลใหม่ทุกเทสต์ — ไม่ให้เทสต์ก่อนหน้าทิ้งข้อมูลค้างมาหลอก
    await DbService.close();
    await databaseFactory.deleteDatabase(
      '${await databaseFactory.getDatabasesPath()}/tpix_wallet.db',
    );
  });

  tearDownAll(() async => DbService.close());

  group('รายการโปรด', () {
    test('บันทึกแล้วอ่านกลับมาได้ครบ', () async {
      await DbService.saveContact(_c('0xAbC0000000000000000000000000000000000001', 'น้องเอ', note: 'เพื่อนร่วมงาน'));

      final all = await DbService.getContacts();
      expect(all, hasLength(1));
      expect(all.first.name, 'น้องเอ');
      expect(all.first.note, 'เพื่อนร่วมงาน');
      // ที่อยู่ต้องถูกทำเป็นตัวพิมพ์เล็กเสมอ ไม่งั้นจับคู่กับสิ่งที่ผู้ใช้พิมพ์ไม่ได้
      expect(all.first.address, '0xabc0000000000000000000000000000000000001');
    });

    test('ที่อยู่เดิม = แก้ชื่อของเดิม ไม่ใช่เพิ่มแถวซ้ำ', () async {
      const addr = '0xabc0000000000000000000000000000000000002';
      await DbService.saveContact(_c(addr, 'ชื่อเก่า'));
      await DbService.saveContact(_c(addr, 'ชื่อใหม่'));

      final all = await DbService.getContacts();
      expect(all, hasLength(1));
      expect(all.first.name, 'ชื่อใหม่');
    });

    test('พิมพ์ใหญ่/เล็กต่างกันก็ยังเป็นคนเดียวกัน', () async {
      await DbService.saveContact(_c('0xDEF0000000000000000000000000000000000003', 'ตัวใหญ่'));
      await DbService.saveContact(_c('0xdef0000000000000000000000000000000000003', 'ตัวเล็ก'));

      expect(await DbService.getContacts(), hasLength(1));
      final found = await DbService.findContact('0xDeF0000000000000000000000000000000000003');
      expect(found?.name, 'ตัวเล็ก');
    });

    test('หาที่อยู่ที่ไม่เคยบันทึก → null (ไม่ throw)', () async {
      expect(await DbService.findContact('0x0000000000000000000000000000000000000009'), isNull);
      expect(await DbService.findContact('   '), isNull);
      expect(await DbService.findContact(''), isNull);
    });

    test('ลบแล้วหายจริง', () async {
      final id = await DbService.saveContact(_c('0xabc0000000000000000000000000000000000004', 'ลบทิ้ง'));
      await DbService.deleteContact(id);
      expect(await DbService.getContacts(), isEmpty);
    });

    test('นับการใช้งานแล้วเรียงตัวที่ใช้ล่าสุดขึ้นก่อน', () async {
      const a = '0xaaa0000000000000000000000000000000000001';
      const b = '0xbbb0000000000000000000000000000000000002';
      await DbService.saveContact(_c(a, 'คนแรก'));
      await DbService.saveContact(_c(b, 'คนที่สอง'));

      await DbService.markContactUsed(a);

      final all = await DbService.getContacts();
      expect(all.first.name, 'คนแรก');
      expect(all.first.usedCount, 1);
      expect(all.first.lastUsedAt, isNotNull);
    });

    test('นับการใช้งานที่อยู่ที่ยังไม่ได้บันทึก → ไม่สร้างแถวใหม่', () async {
      await DbService.markContactUsed('0xccc0000000000000000000000000000000000005');
      expect(await DbService.getContacts(), isEmpty);
    });

    test('แก้ชื่อแล้วสถิติการใช้งานเดิมต้องไม่หาย', () async {
      const addr = '0xddd0000000000000000000000000000000000006';
      await DbService.saveContact(_c(addr, 'ก่อนแก้'));
      await DbService.markContactUsed(addr);
      await DbService.markContactUsed(addr);

      await DbService.saveContact(_c(addr, 'หลังแก้'));

      final found = await DbService.findContact(addr);
      expect(found?.name, 'หลังแก้');
      expect(found?.usedCount, 2, reason: 'แก้ชื่อไม่ควรรีเซ็ตจำนวนครั้งที่ใช้');
    });
  });

  group('อัปเกรดฐานข้อมูลของผู้ใช้เดิม (v5 → v6)', () {
    test('ตารางเดิมอยู่ครบ + ได้ตาราง contacts เพิ่ม', () async {
      final path = '${await databaseFactory.getDatabasesPath()}/tpix_wallet.db';
      await databaseFactory.deleteDatabase(path);

      // จำลองเครื่องผู้ใช้ที่ยังเป็น v5: มีทุกตารางยกเว้น contacts
      final old = await databaseFactory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 5,
          onCreate: (db, _) async {
            await db.execute('''
              CREATE TABLE transactions(
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                tx_hash TEXT UNIQUE NOT NULL, from_address TEXT NOT NULL,
                to_address TEXT NOT NULL, value TEXT NOT NULL,
                direction TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'pending',
                block_number INTEGER, timestamp INTEGER,
                created_at TEXT NOT NULL, wallet_slot INTEGER NOT NULL)
            ''');
            await db.insert('transactions', {
              'tx_hash': '0xdeadbeef',
              'from_address': '0x1',
              'to_address': '0x2',
              'value': '1',
              'direction': 'out',
              'status': 'confirmed',
              'created_at': '2026-01-01',
              'wallet_slot': 0,
            });
          },
        ),
      );
      await old.close();

      // เปิดผ่าน DbService = เดินเส้นทาง onUpgrade จริง
      final db = await DbService.database;
      expect(await db.getVersion(), 6);

      // ธุรกรรมเดิมต้องยังอยู่ — migration ห้ามล้างข้อมูลผู้ใช้
      final txs = await db.query('transactions');
      expect(txs, hasLength(1));
      expect(txs.first['tx_hash'], '0xdeadbeef');

      // และใช้สมุดที่อยู่ได้ทันที
      await DbService.saveContact(_c('0xeee0000000000000000000000000000000000007', 'หลังอัปเกรด'));
      expect(await DbService.getContacts(), hasLength(1));
    });
  });

  group('โมเดล Contact', () {
    test('ตัวย่อที่อยู่', () {
      expect(_c('0x1234567890abcdef1234567890abcdef12345678', 'x').shortAddress,
          '0x1234…5678');
    });

    test('ตัวอักษรแรก รองรับไทยและอิโมจิ', () {
      expect(_c('0x1', 'น้องเอ').initial, 'น');
      expect(_c('0x1', '  เอ  ').initial, 'เ');
      expect(_c('0x1', '').initial, '?');
      // อิโมจิเป็น surrogate pair — ถ้าใช้ [0] จะได้ครึ่งตัวที่แสดงไม่ได้
      expect(_c('0x1', '🐶หมา').initial, '🐶');
    });
  });
}
