/// TPIX Wallet — ธีม XP Silver
///
/// 🔴 ไม่เรียก XpSilverTheme().buildLight()/buildDark() ที่นี่ ด้วยเหตุผลเดียว
/// กับที่เขียนไว้ใน test/support/test_theme.dart — แค่ "สร้าง" TextStyle ของ
/// GoogleFonts ก็สั่งดาวน์โหลดฟอนต์แล้ว แล้วเทสต์จะล้มด้วยเรื่องที่ไม่เกี่ยวกัน
/// (เจอจริงตอนทำธีมนี้: golden test ที่เรนเดอร์ ThemeData ตัวจริงล้มด้วย
///  "allowRuntimeFetching is false but font NotoSans-SemiBold was not found")
///
/// จึงทดสอบสัญญาที่พังแล้วผู้ใช้เดือดร้อนจริงแทน: ธีมถูกลงทะเบียน เรียกด้วย
/// คีย์ที่บันทึกไว้ได้ และคีย์ต้องไม่เปลี่ยน ไม่งั้นคนที่เลือกธีมนี้ไว้จะถูก
/// เด้งกลับไปธีมคลาสสิกเงียบ ๆ ตอนเปิดแอปครั้งถัดไป
///
/// Developed by Xman Studio
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:tpix_wallet/core/theme_provider.dart';
import 'package:tpix_wallet/core/themes/theme_bundle.dart';
import 'package:tpix_wallet/core/themes/xp_silver_theme.dart';

void main() {
  group('ธีม XP Silver', () {
    test('อยู่ใน registry และเรียกด้วย id ได้', () {
      final ids = ThemeProvider.registry.map((t) => t.id).toList();
      expect(ids, contains(ThemeId.xpSilver));

      final provider = ThemeProvider();
      final bundle = provider.bundleFor(ThemeId.xpSilver);
      expect(bundle.id, ThemeId.xpSilver);
      expect(bundle, isA<XpSilverTheme>());
    });

    test('คีย์ที่ใช้บันทึกต้องเป็น xp_silver และห้ามเปลี่ยน', () {
      // คีย์นี้ถูกเขียนลง SharedPreferences ถ้าเปลี่ยนทีหลัง เครื่องที่เลือก
      // ธีมนี้ไว้จะอ่านไม่เจอแล้วตกกลับไป classic โดยไม่มีใครรู้ว่าทำไม
      expect(ThemeId.xpSilver.key, 'xp_silver');
      expect(ThemeId.fromKey('xp_silver'), ThemeId.xpSilver);
    });

    test('มีชื่อและคำโปรยครบทั้งสองภาษา สำหรับหน้าเลือกธีม', () {
      final bundle = XpSilverTheme();

      for (final text in [
        bundle.nameTh,
        bundle.nameEn,
        bundle.taglineTh,
        bundle.taglineEn,
      ]) {
        expect(text.trim(), isNotEmpty);
      }
    });

    test('รองรับโหมดสว่าง — เป็นโหมดหลักของธีมนี้', () {
      // XP Silver เกิดมาเป็นธีมสว่าง ถ้าเผลอตั้ง supportsLight=false
      // ผู้ใช้จะเลือกได้แต่โหมดมืดซึ่งเป็นตัวรอง ไม่ใช่ตัวที่ตั้งใจทำ
      expect(XpSilverTheme().supportsLight, isTrue);
    });
  });
}
