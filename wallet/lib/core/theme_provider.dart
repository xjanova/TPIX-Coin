/// TPIX Wallet — Theme Provider
/// เก็บ + persist theme ที่ user เลือก (classic / synthwave / terminal)
/// — เลียน pattern จาก LocaleProvider
///
/// Developed by Xman Studio

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'themes/theme_bundle.dart';
import 'themes/classic_theme.dart';
import 'themes/synthwave_theme.dart';
import 'themes/terminal_theme.dart';

class ThemeProvider extends ChangeNotifier {
  static const String _key = 'app_theme_id_v2';

  // Registry ของทุกธีม — เพิ่มธีมใหม่ที่นี่
  static final List<ThemeBundle> registry = [
    ClassicTheme(),
    SynthwaveTheme(),
    TerminalTheme(),
  ];

  ThemeId _id = ThemeId.classic;
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
    _id = ThemeId.fromKey(prefs.getString(_key));
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
