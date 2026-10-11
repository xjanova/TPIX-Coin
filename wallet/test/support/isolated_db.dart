/// ฐานข้อมูลแยกต่อไฟล์เทสต์
///
/// `flutter test` รันหลายไฟล์พร้อมกัน (คนละ isolate) แต่ DbService เปิดไฟล์ชื่อเดียวกัน
/// (`tpix_wallet.db`) ในโฟลเดอร์เดียวกัน → ไฟล์หนึ่งลบฐานข้อมูลทิ้งใน setUp
/// ระหว่างที่อีกไฟล์กำลังใช้อยู่ = เทสต์ล้มแบบสุ่มๆ ที่ไม่เกี่ยวกับโค้ดเลย
/// ให้แต่ละไฟล์ชี้โฟลเดอร์ฐานข้อมูลของตัวเองแทน
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> useIsolatedTestDb(String name) async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  final dir = Directory(p.join(Directory.systemTemp.path, 'tpix_wallet_test_$name'));
  await dir.create(recursive: true);
  await databaseFactory.setDatabasesPath(dir.path);
}
