/// TPIX Wallet — Liquid Theme (ลิควิด)
/// น่ารัก สดใส เจลลี่ใส — มินต์ + ลาเวนเดอร์ + พีช, มุมโค้งมนมาก,
/// เงานุ่มแบบ 3D soft-body, ฟอนต์ Quicksand ทรงกลมอ่านง่าย
///
/// Developed by Xman Studio

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'theme_bundle.dart';
import 'widgets/liquid_blobs_background.dart';

class LiquidTheme extends ThemeBundle {
  // ── Brand (ใช้ร่วมทั้ง light/dark เพื่อให้ "ตัวตน" ของธีมคงที่) ──
  static const Color _mint = Color(0xFF2DD4BF); // มินต์ — สีหลัก
  static const Color _lavender = Color(0xFFA78BFA); // ลาเวนเดอร์ — สีรอง
  static const Color _peach = Color(0xFFFF9E7D); // พีช — สีอุ่น
  static const Color _success = Color(0xFF34D399);
  static const Color _danger = Color(0xFFFB7185); // โรสอ่อน — เตือนแบบไม่ดุ

  // ── Light palette (โหมดหลักของธีมนี้ — สว่างสดใส) ──
  static const Color _bgLight = Color(0xFFF3FBFF);
  static const Color _cardLight = Color(0xFFFFFFFF);
  static const Color _surfaceLight = Color(0xFFEAF6FF);
  static const Color _borderLight = Color(0xFFD8EDF7);
  static const Color _textPrimaryLight = Color(0xFF16394D);
  static const Color _textSecondaryLight = Color(0xFF5C7F92);
  static const Color _textMutedLight = Color(0xFF9BB8C6);

  // ── Dark palette ("candy night" — ยังสดใสอยู่ ไม่ใช่ดำทึบ) ──
  static const Color _bgDark = Color(0xFF141733);
  static const Color _cardDark = Color(0xFF212545);
  static const Color _surfaceDark = Color(0xFF2A2F55);
  static const Color _borderDark = Color(0xFF373D6B);
  static const Color _textPrimaryDark = Color(0xFFF6F8FF);
  static const Color _textSecondaryDark = Color(0xFFBAC2EC);
  static const Color _textMutedDark = Color(0xFF7C86BC);

  @override
  ThemeId get id => ThemeId.liquid;

  @override
  String get nameTh => 'ลิควิด';

  @override
  String get nameEn => 'Liquid';

  @override
  String get taglineTh => 'เจลลี่ใส น่ารัก สดใส';

  @override
  String get taglineEn => 'Jelly glass · Cute · Bright';

  @override
  IconData get icon => Icons.bubble_chart_rounded;

  // Quicksand — ทรงกลมมน อ่านง่าย ให้อารมณ์นุ่มนวลตรงกับธีม
  TextStyle _heading(Color color) => GoogleFonts.quicksand(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        color: color,
      );

  TextStyle _mono(Color color) => GoogleFonts.firaCode(fontSize: 14, color: color);

  TextTheme _textTheme(Color primary, Color secondary, Color muted) =>
      GoogleFonts.quicksandTextTheme(
        TextTheme(
          headlineLarge: TextStyle(fontSize: 32, fontWeight: FontWeight.w700, color: primary),
          headlineMedium: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: primary),
          headlineSmall: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: primary),
          titleLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: primary),
          titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: primary),
          bodyLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: secondary),
          bodyMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: secondary),
          bodySmall: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: muted),
        ),
      );

  @override
  ThemeData buildLight() {
    final ext = TpixThemeExtension(
      themeId: id,
      brandPrimary: _mint,
      brandSecondary: _lavender,
      brandWarm: _peach,
      success: _success,
      danger: _danger,
      bg: _bgLight,
      card: _cardLight,
      surface: _surfaceLight,
      border: _borderLight,
      textPrimary: _textPrimaryLight,
      textSecondary: _textSecondaryLight,
      textMuted: _textMutedLight,
      // การ์ดโปร่งกว่าคลาสสิกเล็กน้อย ให้เห็น blob ด้านหลังลางๆ = ฟีล "ลิควิด"
      glassColor: Colors.white.withValues(alpha: 0.78),
      glassBorder: Colors.white.withValues(alpha: 0.95),
      glassHighlight: Colors.white,
      brandGradient: const LinearGradient(
        colors: [_mint, _lavender],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      balanceGradient: const LinearGradient(
        colors: [Color(0xFF5EEAD4), Color(0xFF7DD3FC), Color(0xFFC4B5FD)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        stops: [0.0, 0.5, 1.0],
      ),
      screenGradient: const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFEBF9FF), Color(0xFFFFF2F8)],
      ),
      cardRadius: 28, // โค้งมนมาก = ฟีลหยดน้ำ
      useGlow: true,
      glowIntensity: 0.30, // เรืองแสงนุ่มๆ ไม่ใช่นีออนจ้า
      headingStyle: _heading(_textPrimaryLight),
      monoStyle: _mono(_textSecondaryLight),
      useScanlines: false,
      useGrid: false,
    );

    return ThemeData(
      brightness: Brightness.light,
      scaffoldBackgroundColor: Colors.transparent, // ให้ blob ด้านหลังโชว์
      primaryColor: _mint,
      colorScheme: const ColorScheme.light(
        primary: _mint,
        secondary: _lavender,
        tertiary: _peach,
        surface: _cardLight,
        error: _danger,
      ),
      textTheme: _textTheme(_textPrimaryLight, _textSecondaryLight, _textMutedLight),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      extensions: [ext],
    );
  }

  @override
  ThemeData buildDark() {
    final ext = TpixThemeExtension(
      themeId: id,
      brandPrimary: _mint,
      brandSecondary: _lavender,
      brandWarm: _peach,
      success: _success,
      danger: _danger,
      bg: _bgDark,
      card: _cardDark,
      surface: _surfaceDark,
      border: _borderDark,
      textPrimary: _textPrimaryDark,
      textSecondary: _textSecondaryDark,
      textMuted: _textMutedDark,
      glassColor: Colors.white.withValues(alpha: 0.09),
      glassBorder: Colors.white.withValues(alpha: 0.16),
      glassHighlight: Colors.white.withValues(alpha: 0.20),
      brandGradient: const LinearGradient(
        colors: [_mint, _lavender],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      balanceGradient: const LinearGradient(
        colors: [Color(0xFF1E5F6E), Color(0xFF2F3A72), Color(0xFF4B3A73)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        stops: [0.0, 0.55, 1.0],
      ),
      screenGradient: const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF1B1F45), Color(0xFF141733)],
      ),
      cardRadius: 28,
      useGlow: true,
      glowIntensity: 0.40,
      headingStyle: _heading(_textPrimaryDark),
      monoStyle: _mono(_textSecondaryDark),
      useScanlines: false,
      useGrid: false,
    );

    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: Colors.transparent,
      primaryColor: _mint,
      colorScheme: const ColorScheme.dark(
        primary: _mint,
        secondary: _lavender,
        tertiary: _peach,
        surface: _cardDark,
        error: _danger,
      ),
      textTheme: _textTheme(_textPrimaryDark, _textSecondaryDark, _textMutedDark),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      extensions: [ext],
    );
  }

  @override
  Widget wrapApp(BuildContext context, Widget child) {
    // blob ลอยอยู่หลังทุกหน้าจอ — เป็นลายเซ็นของธีมทั้ง light/dark
    return LiquidBlobsBackground(child: child);
  }
}
