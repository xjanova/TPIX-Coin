/// TPIX Wallet — Synthwave / Outrun Theme
/// 80s neon retro-futuristic — magenta + cyan, sun grid, neon glow cards
///
/// Developed by Xman Studio

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'theme_bundle.dart';
import 'widgets/sun_grid_background.dart';

class SynthwaveTheme extends ThemeBundle {
  // ── Neon palette ──
  static const Color _neonPink = Color(0xFFFF2EB5);     // hot magenta
  static const Color _neonCyan = Color(0xFF00F0FF);     // electric cyan
  static const Color _neonPurple = Color(0xFF9D4EDD);   // ultraviolet
  static const Color _neonOrange = Color(0xFFFF8B41);   // sunset
  static const Color _neonGreen = Color(0xFF00FF9D);    // CRT green-cyan
  static const Color _neonRed = Color(0xFFFF1744);

  // Background (deep space night)
  static const Color _bg = Color(0xFF0A0420);
  static const Color _card = Color(0xFF1A0838);
  static const Color _surface = Color(0xFF2B0B4A);
  static const Color _border = Color(0xFF3D1864);

  // Text
  static const Color _textPrimary = Color(0xFFFFEAFB);
  static const Color _textSecondary = Color(0xFFD0A3E5);
  static const Color _textMuted = Color(0xFF8E6FAB);

  // Light variant (less common but support it)
  static const Color _bgLight = Color(0xFFFEEAF7);
  static const Color _cardLight = Color(0xFFFFFFFF);
  static const Color _surfaceLight = Color(0xFFFFD6F1);
  static const Color _borderLight = Color(0xFFFFB1E1);
  static const Color _textPrimaryLight = Color(0xFF2B0B4A);
  static const Color _textSecondaryLight = Color(0xFF6B1D8F);
  static const Color _textMutedLight = Color(0xFFB07AC8);

  @override
  ThemeId get id => ThemeId.synthwave;

  @override
  String get nameTh => 'ซินธ์เวฟ';

  @override
  String get nameEn => 'Synthwave';

  @override
  String get taglineTh => 'นีออน 80s · ขอบฟ้าเรืองแสง';

  @override
  String get taglineEn => "80s Neon · Glowing Horizon";

  @override
  IconData get icon => Icons.wb_twilight;

  TextStyle _heading(Color color) => GoogleFonts.audiowide(
        fontSize: 26,
        color: color,
        letterSpacing: 1.2,
      );

  TextStyle _mono(Color color) =>
      GoogleFonts.shareTechMono(fontSize: 14, color: color, letterSpacing: 0.8);

  @override
  ThemeData buildLight() {
    final ext = TpixThemeExtension(
      themeId: id,
      brandPrimary: _neonPink,
      brandSecondary: _neonPurple,
      brandWarm: _neonOrange,
      success: _neonGreen,
      danger: _neonRed,
      bg: _bgLight,
      card: _cardLight,
      surface: _surfaceLight,
      border: _borderLight,
      textPrimary: _textPrimaryLight,
      textSecondary: _textSecondaryLight,
      textMuted: _textMutedLight,
      glassColor: _neonPink.withValues(alpha: 0.06),
      glassBorder: _neonPink.withValues(alpha: 0.30),
      glassHighlight: Colors.white,
      brandGradient: const LinearGradient(
        colors: [_neonPink, _neonPurple, _neonCyan],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      balanceGradient: const LinearGradient(
        colors: [_neonPink, _neonPurple, _neonCyan],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        stops: [0.0, 0.5, 1.0],
      ),
      screenGradient: const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFFEEAF7), _bgLight],
      ),
      cardRadius: 12,
      useGlow: true,
      glowIntensity: 0.5,
      headingStyle: _heading(_textPrimaryLight),
      monoStyle: _mono(_textSecondaryLight),
      useScanlines: false,
      useGrid: true,
    );

    return ThemeData(
      brightness: Brightness.light,
      scaffoldBackgroundColor: Colors.transparent,
      primaryColor: _neonPink,
      colorScheme: const ColorScheme.light(
        primary: _neonPink,
        secondary: _neonCyan,
        tertiary: _neonPurple,
        surface: _cardLight,
        error: _neonRed,
      ),
      textTheme: GoogleFonts.audiowideTextTheme(
        const TextTheme(
          headlineLarge: TextStyle(fontSize: 30, color: _textPrimaryLight, letterSpacing: 1.5),
          headlineMedium: TextStyle(fontSize: 24, color: _textPrimaryLight, letterSpacing: 1.2),
          headlineSmall: TextStyle(fontSize: 18, color: _textPrimaryLight, letterSpacing: 1.0),
          titleLarge: TextStyle(fontSize: 16, color: _textPrimaryLight, letterSpacing: 0.8),
          titleMedium: TextStyle(fontSize: 14, color: _textPrimaryLight, letterSpacing: 0.6),
          bodyLarge: TextStyle(fontSize: 15, color: _textSecondaryLight),
          bodyMedium: TextStyle(fontSize: 13, color: _textSecondaryLight),
          bodySmall: TextStyle(fontSize: 11, color: _textMutedLight),
        ),
      ).apply(
        bodyColor: _textSecondaryLight,
        displayColor: _textPrimaryLight,
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
      brandPrimary: _neonPink,
      brandSecondary: _neonCyan,
      brandWarm: _neonOrange,
      success: _neonGreen,
      danger: _neonRed,
      bg: _bg,
      card: _card,
      surface: _surface,
      border: _border,
      textPrimary: _textPrimary,
      textSecondary: _textSecondary,
      textMuted: _textMuted,
      glassColor: _neonPink.withValues(alpha: 0.08),
      glassBorder: _neonPink.withValues(alpha: 0.45),
      glassHighlight: _neonCyan.withValues(alpha: 0.30),
      brandGradient: const LinearGradient(
        colors: [_neonPink, _neonPurple, _neonCyan],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      balanceGradient: const LinearGradient(
        colors: [_neonPink, _neonPurple, Color(0xFF00C4D6)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        stops: [0.0, 0.5, 1.0],
      ),
      screenGradient: const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF0A0420), Color(0xFF2B0B4A), Color(0xFF0A0420)],
        stops: [0.0, 0.55, 1.0],
      ),
      cardRadius: 12,
      useGlow: true,
      glowIntensity: 0.85,
      headingStyle: _heading(_textPrimary),
      monoStyle: _mono(_textSecondary),
      useScanlines: false,
      useGrid: true,
    );

    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: Colors.transparent,
      primaryColor: _neonPink,
      colorScheme: const ColorScheme.dark(
        primary: _neonPink,
        secondary: _neonCyan,
        tertiary: _neonPurple,
        surface: _card,
        error: _neonRed,
      ),
      textTheme: GoogleFonts.audiowideTextTheme(
        const TextTheme(
          headlineLarge: TextStyle(fontSize: 30, color: _textPrimary, letterSpacing: 1.5),
          headlineMedium: TextStyle(fontSize: 24, color: _textPrimary, letterSpacing: 1.2),
          headlineSmall: TextStyle(fontSize: 18, color: _textPrimary, letterSpacing: 1.0),
          titleLarge: TextStyle(fontSize: 16, color: _textPrimary, letterSpacing: 0.8),
          titleMedium: TextStyle(fontSize: 14, color: _textPrimary, letterSpacing: 0.6),
          bodyLarge: TextStyle(fontSize: 15, color: _textSecondary),
          bodyMedium: TextStyle(fontSize: 13, color: _textSecondary),
          bodySmall: TextStyle(fontSize: 11, color: _textMuted),
        ),
      ).apply(
        bodyColor: _textSecondary,
        displayColor: _textPrimary,
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
    // เฉพาะ dark mode → ใช้ sun grid background เต็มหน้า
    // light mode → gradient ปกติ (sun grid อ่านยาก)
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (!isDark) return child;
    return SunGridBackground(child: child);
  }
}
