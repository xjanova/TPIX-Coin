/// TPIX Wallet — ข้อความของหน้ากิจกรรม / ตั้งค่า / มาสเตอร์โหนด ธีม Obsidian ต้องมีครบทั้งไทยและอังกฤษ
///
/// คีย์ที่ประกอบจากชื่อ enum (ตัวกรอง / แท็กระดับ / เหตุผลปุ่ม) สร้างจาก enum ตัวจริง
/// — เพิ่มค่าใหม่ใน enum แล้วลืมใส่คำแปล = เทสต์นี้ล้ม (ไม่ใช่ผู้ใช้เห็นชื่อคีย์ดิบบนจอ)
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tpix_wallet/services/masternode_service.dart';
import 'package:tpix_wallet/utils/activity_feed.dart';

void main() {
  test('คีย์ obs.act / obs.set / obs.mn ที่หน้าใช้ มีทั้ง th และ en', () {
    final locale = File('lib/core/locale_provider.dart').readAsStringSync();
    final files = [
      'lib/screens/tx_history_obsidian.dart',
      'lib/screens/settings_obsidian.dart',
      'lib/screens/masternode_obsidian.dart',
    ];
    final keys = <String>{
      for (final f in files)
        ...RegExp(r"'(obs\.(?:act|set|mn)\.[A-Za-z.]+)'")
            .allMatches(File(f).readAsStringSync())
            .map((m) => m.group(1)!),
      for (final f in ActivityFilter.values) 'obs.act.f.${f.name}',
      for (final t in MnTier.values) 'obs.mn.tag.${t.name}',
      // ป้ายปุ่มหลักเมื่อกระเป๋านี้มีโหนดอยู่แล้ว (registerBlock) — นอกนั้นปุ่มพาไปเว็บ
      for (final b in const [
        MnBlock.hasNode,
        MnBlock.claimFirst,
        MnBlock.restakeWaitsForPool,
      ])
        'obs.mn.cta.${b.name}',
    };
    expect(keys.length, greaterThan(40));
    final missing = <String>[];
    for (final k in keys) {
      final n = RegExp("'${RegExp.escape(k)}':").allMatches(locale).length;
      if (n != 2) missing.add('$k (พบ $n ครั้ง ต้องมี th + en = 2)');
    }
    expect(missing, isEmpty, reason: missing.join('\n'));
  });
}
