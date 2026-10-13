/// TPIX Wallet — Theme Provider
/// เก็บ + persist theme ที่ user เลือก (obsidian / classic / liquid / synthwave / terminal / xp_silver)
/// — เลียน pattern จาก LocaleProvider
///
/// Developed by Xman Studio

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'themes/theme_bundle.dart';
import 'themes/classic_theme.dart';
import 'themes/obsidian_theme.dart';
import 'themes/liquid_theme.dart';
import 'themes/synthwave_theme.dart';
import 'themes/terminal_theme.dart';
import 'themes/xp_silver_theme.dart';

class ThemeProvider extends ChangeNotifier {
  static const String _key = 'app_theme_id_v2';

  /// ธงย้ายผู้ใช้ "ธีมเริ่มต้นเดิม" (classic) ไป Obsidian — ทำครั้งเดียวต่อเครื่อง
  /// ตั้งแล้วไม่ลบ: คนที่ย้ายแล้วแต่กลับไปเลือก classic เองจะได้ classic ตลอดไป
  @visibleForTesting
  static const String obsidianMigrationKey = 'app_theme_obsidian_migrated_v1';

  // Registry ของทุกธีม — เพิ่มธีมใหม่ที่นี่ (ลำดับนี้ = ลำดับในหน้าเลือกธีม)
  static final List<ThemeBundle> registry = [
    ObsidianTheme(),
    ClassicTheme(),
    LiquidTheme(),
    SynthwaveTheme(),
    TerminalTheme(),
    XpSilverTheme(),
  ];

  ThemeId _id = ThemeId.defaultId;
  ThemeId get id => _id;

  ThemeBundle get current => registry.firstWhere(
        (t) => t.id == _id,
        orElse: () => registry.first,
      );

  /// คืน ThemeBundle ตาม id (ใช้สำหรับ picker preview)
  ThemeBundle bundleFor(ThemeId id) =>
      registry.firstWhere((t) => t.id == id, orElse: () => registry.first);

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_key);

    if (prefs.getBool(obsidianMigrationKey) != true) {
      // ย้ายครั้งเดียว: ใครยังอยู่บนค่าเริ่มต้นเดิม (classic หรือไม่เคยเลือกเลย)
      // → ไป Obsidian ซึ่งเป็นหน้าตาหลักชุดใหม่ ส่วนคนที่เลือกธีมอื่นไว้เอง คงไว้ตามเดิม
      if (stored == null || stored == ThemeId.classic.key) {
        _id = ThemeId.obsidian;
        await prefs.setString(_key, ThemeId.obsidian.key);
      } else {
        _id = ThemeId.fromKey(stored);
      }
      await prefs.setBool(obsidianMigrationKey, true);
    } else {
      _id = ThemeId.fromKey(stored);
    }
    notifyListeners();
  }

  Future<void> setTheme(ThemeId id) async {
    if (_id == id) return;
    _id = id;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, id.key);
    notifyListeners();
  }
}
