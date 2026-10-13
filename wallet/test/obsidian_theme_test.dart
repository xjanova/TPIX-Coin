/// TPIX Wallet — ธีม Obsidian: สัญญาที่ถ้าพังแล้วผู้ใช้เดือดร้อนจริง
///
/// 🔴 ไม่เรียก ObsidianTheme().buildDark() ที่นี่ (เหตุผลเดียวกับ test/support/test_theme.dart
///    — แค่สร้าง TextStyle ของ GoogleFonts ก็สั่งโหลดฟอนต์ผ่านเน็ตแล้ว)
///
/// ที่ล็อกไว้:
///   1. คีย์ 'obsidian' ห้ามเปลี่ยน (ถูกเขียนลง SharedPreferences)
///   2. เครื่องใหม่ได้ Obsidian
///   3. ย้ายคนที่อยู่บน classic (ค่าเริ่มต้นเดิม) มา Obsidian "ครั้งเดียว"
///      — ถ้าย้ายทุกครั้งที่เปิดแอป คนที่กลับไปเลือก classic เองจะโดนดึงกลับตลอด
///   4. คนที่เลือกธีมอื่นไว้เอง ต้องไม่โดนย้าย
///
/// Developed by Xman Studio
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tpix_wallet/core/theme_provider.dart';
import 'package:tpix_wallet/core/themes/obsidian_theme.dart';
import 'package:tpix_wallet/core/themes/theme_bundle.dart';

const _themeKey = 'app_theme_id_v2';

Future<ThemeProvider> _boot(Map<String, Object> prefs) async {
  SharedPreferences.setMockInitialValues(prefs);
  final p = ThemeProvider();
  await p.init();
  return p;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ธีม Obsidian — สัญญา', () {
    test('อยู่ใน registry เป็นตัวแรก และเรียกด้วย id ได้', () {
      expect(ThemeProvider.registry.first, isA<ObsidianTheme>());
      expect(ThemeProvider().bundleFor(ThemeId.obsidian), isA<ObsidianTheme>());
    });

    test('คีย์ที่บันทึกต้องเป็น obsidian และห้ามเปลี่ยน', () {
      expect(ThemeId.obsidian.key, 'obsidian');
      expect(ThemeId.fromKey('obsidian'), ThemeId.obsidian);
    });

    test('มืดอย่างเดียว — หน้าเลือกธีมต้องซ่อนสวิตช์สว่าง/มืด', () {
      expect(ObsidianTheme().supportsLight, isFalse);
    });

    test('มีชื่อ/คำโปรยครบทั้งสองภาษา', () {
      final b = ObsidianTheme();
      for (final t in [b.nameTh, b.nameEn, b.taglineTh, b.taglineEn]) {
        expect(t.trim(), isNotEmpty);
      }
    });
  });

  group('ค่าเริ่มต้น + ย้ายผู้ใช้เดิม', () {
    test('เครื่องใหม่ (ไม่เคยบันทึกธีม) → Obsidian และบันทึกธงไว้', () async {
      final p = await _boot({});
      expect(p.id, ThemeId.obsidian);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(_themeKey), 'obsidian');
      expect(prefs.getBool(ThemeProvider.obsidianMigrationKey), isTrue);
    });

    test('ผู้ใช้เดิมที่อยู่บน classic → ย้ายมา Obsidian ครั้งเดียว', () async {
      final p = await _boot({_themeKey: 'classic'});
      expect(p.id, ThemeId.obsidian);
    });

    test('ย้ายแล้วกลับไปเลือก classic เอง → เปิดแอปรอบถัดไปยังเป็น classic', () async {
      final first = await _boot({_themeKey: 'classic'});
      expect(first.id, ThemeId.obsidian);
      await first.setTheme(ThemeId.classic);

      // เปิดแอปใหม่ — ค่าใน SharedPreferences ชุดเดิม (ไม่ mock ใหม่)
      final again = ThemeProvider();
      await again.init();
      expect(again.id, ThemeId.classic);
    });

    test('ผู้ใช้ที่เลือกธีมอื่นไว้เอง ไม่โดนย้าย', () async {
      for (final id in [ThemeId.liquid, ThemeId.synthwave, ThemeId.terminal, ThemeId.xpSilver]) {
        final p = await _boot({_themeKey: id.key});
        expect(p.id, id, reason: '${id.key} ต้องคงเดิม');
      }
    });

    test('ธงย้ายตั้งแล้ว + classic ที่บันทึกไว้ → คง classic', () async {
      final p = await _boot({_themeKey: 'classic', ThemeProvider.obsidianMigrationKey: true});
      expect(p.id, ThemeId.classic);
    });
  });
}
