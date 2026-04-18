/// TPIX Wallet — Classic Theme
/// ธีมเดิมของแอพ — Glass morphism, cyan+purple, Space Grotesk
///
/// Developed by Xman Studio

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'theme_bundle.dart';

class ClassicTheme extends ThemeBundle {
  // Brand
  static const Color _primary = Color(0xFF06B6D4);   // Cyan
  static const Color _accent = Color(0xFF8B5CF6);    // Purple
  static const Color _warm = Color(0xFFF59E0B);      // Amber
  static const Color _success = Color(0xFF00C853);
  static const Color _danger = Color(0xFFFF1744);

  // Dark palette
  static const Color _bgDark = Color(0xFF0A0E17);
  static const Color _cardDark = Color(0xFF111827);
  static const Color _surfaceDark = Color(0xFF1A2035);
  static const Color _borderDark = Color(0xFF1E293B);
  static const Color _textPrimaryDark = Color(0xFFFFFFFF);
  static const Color _textSecondaryDark = Color(0xFF94A3B8);
  static const Color _textMutedDark = Color(0xFF475569);

  // Light palette
  static const Color _bgLight = Color(0xFFF5F7FA);
  static const Color _cardLight = Color(0xFFFFFFFF);
  static const Color _surfaceLight = Color(0xFFF0F2F5);
  static const Color _borderLight = Color(0xFFE2E8F0);
  static const Color _textPrimaryLight = Color(0xFF0F172A);
  static const Color _textSecondaryLight = Color(0xFF475569);
  static const Color _textMutedLight = Color(0xFF94A3B8);

  @override
  ThemeId get id => ThemeId.classic;

  @override
  String get nameTh => 'คลาสสิก';

  @override
  String get nameEn => 'Classic';

  @override
  String get taglineTh => 'กระจกฝ้า ฟ้า-ม่วง สง่างาม';

  @override
  String get taglineEn => 'Glass · Cyan & Purple · Refined';

  @override
  IconData get icon => Icons.diamond_outlined;

  TextStyle _heading(Color color) =>
      GoogleFonts.spaceGrotesk(fontSize: 24, fontWeight: FontWeight.w700, color: color);

  TextStyle _mono(Color color) =>
      GoogleFonts.firaCode(fontSize: 14, color: color);

  @override
  ThemeData buildLight() {
    final ext = TpixThemeExtension(
      themeId: id,
      brandPrimary: _primary,
      brandSecondary: _accent,
      brandWarm: _warm,
      success: _success,
      danger: _danger,
      bg: _bgLight,
      card: _cardLight,
      surface: _surfaceLight,
      border: _borderLight,
      textPrimary: _textPrimaryLight,
      textSecondary: _textSecondaryLight,
      textMuted: _textMutedLight,
      glassColor: Colors.white.withValues(alpha: 0.92),
      glassBorder: Colors.black.withValues(alpha: 0.08),
      glassHighlight: Colors.white,
      brandGradient: const LinearGradient(
        colors: [_primary, _accent],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      balanceGradient: const LinearGradient(
        colors: [Color(0xFF0E8EA1), Color(0xFF086B7D), Color(0xFF055062)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        stops: [0.0, 0.5, 1.0],
      ),
      screenGradient: const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFEEF2FF), _bgLight],
      ),
      cardRadius: 20,
      useGlow: false,
      glowIntensity: 0.0,
      headingStyle: _heading(_textPrimaryLight),
      monoStyle: _mono(_textSecondaryLight),
      useScanlines: false,
      useGrid: false,
    );

    return ThemeData(
      brightness: Brightness.light,
      scaffoldBackgroundColor: _bgLight,
      primaryColor: _primary,
      colorScheme: const ColorScheme.light(
        primary: _primary,
        secondary: _accent,
        surface: _cardLight,
        error: _danger,
      ),
      textTheme: GoogleFonts.spaceGroteskTextTheme(
        const TextTheme(
          headlineLarge: TextStyle(fontSize: 32, fontWeight: FontWeight.w700, color: _textPrimaryLight),
          headlineMedium: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: _textPrimaryLight),
          headlineSmall: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: _textPrimaryLight),
          titleLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: _textPrimaryLight),
          titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: _textPrimaryLight),
          bodyLarge: TextStyle(fontSize: 16, color: _textSecondaryLight),
          bodyMedium: TextStyle(fontSize: 14, color: _textSecondaryLight),
          bodySmall: TextStyle(fontSize: 12, color: _textMutedLight),
        ),
      ),
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
      brandPrimary: _primary,
      brandSecondary: _accent,
      brandWarm: _warm,
      success: _success,
      danger: _danger,
      bg: _bgDark,
      card: _cardDark,
      surface: _surfaceDark,
      border: _borderDark,
      textPrimary: _textPrimaryDark,
      textSecondary: _textSecondaryDark,
      textMuted: _textMutedDark,
      glassColor: Colors.white.withValues(alpha: 0.07),
      glassBorder: Colors.white.withValues(alpha: 0.10),
      glassHighlight: Colors.white.withValues(alpha: 0.12),
      brandGradient: const LinearGradient(
        colors: [_primary, _accent],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      balanceGradient: const LinearGradient(
        colors: [Color(0xFF122E4D), Color(0xFF0D1B33), Color(0xFF081222)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        stops: [0.0, 0.6, 1.0],
      ),
      screenGradient: const RadialGradient(
        center: Alignment(0, -0.5),
        radius: 1.5,
        colors: [Color(0xFF0C1929), _bgDark],
      ),
      cardRadius: 20,
      useGlow: false,
      glowIntensity: 0.0,
      headingStyle: _heading(_textPrimaryDark),
      monoStyle: _mono(_textSecondaryDark),
      useScanlines: false,
      useGrid: false,
    );

    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: _bgDark,
      primaryColor: _primary,
      colorScheme: const ColorScheme.dark(
        primary: _primary,
        secondary: _accent,
        surface: _cardDark,
        error: _danger,
      ),
      textTheme: GoogleFonts.spaceGroteskTextTheme(
        const TextTheme(
          headlineLarge: TextStyle(fontSize: 32, fontWeight: FontWeight.w700, color: _textPrimaryDark),
          headlineMedium: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: _textPrimaryDark),
          headlineSmall: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: _textPrimaryDark),
          titleLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: _textPrimaryDark),
          titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: _textPrimaryDark),
          bodyLarge: TextStyle(fontSize: 16, color: _textSecondaryDark),
          bodyMedium: TextStyle(fontSize: 14, color: _textSecondaryDark),
          bodySmall: TextStyle(fontSize: 12, color: _textMutedDark),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      extensions: [ext],
    );
  }

  @override
  Widget wrapApp(BuildContext context, Widget child) {
    // Classic — ไม่ต้องเพิ่ม overlay (ใช้ scaffold เดิม)
    return child;
  }
}
