/// TPIX Wallet — Terminal / CRT Theme
/// Green-on-black phosphor monitor — Mr. Robot / Matrix / DOS aesthetic
/// Mono font + scanlines + ASCII feel
///
/// Developed by Xman Studio

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'theme_bundle.dart';
import 'widgets/scanline_overlay.dart';

class TerminalTheme extends ThemeBundle {
  // ── Phosphor palette ──
  static const Color _phosphor = Color(0xFF00FF66);     // bright green CRT
  static const Color _phosphorDim = Color(0xFF00B348);  // dimmer green
  static const Color _amber = Color(0xFFFFB000);        // amber CRT alt
  static const Color _danger = Color(0xFFFF3333);       // alert red
  static const Color _cyan = Color(0xFF00E5FF);         // info cyan

  // Background (deep CRT black with hint of green)
  static const Color _bg = Color(0xFF000A04);
  static const Color _card = Color(0xFF021407);
  static const Color _surface = Color(0xFF03200B);
  static const Color _border = Color(0xFF00B348);

  // Text — เน้น phosphor green
  static const Color _textPrimary = Color(0xFF00FF66);
  static const Color _textSecondary = Color(0xFF00B348);
  static const Color _textMuted = Color(0xFF005C24);

  @override
  ThemeId get id => ThemeId.terminal;

  @override
  String get nameTh => 'เทอร์มินัล';

  @override
  String get nameEn => 'Terminal';

  @override
  String get taglineTh => 'CRT phosphor · เทอร์มินัล hacker';

  @override
  String get taglineEn => 'CRT Phosphor · Hacker Terminal';

  @override
  IconData get icon => Icons.terminal;

  @override
  bool get supportsLight => false; // CRT terminal — dark-only ตามอุดมการณ์

  TextStyle _heading(Color color) => GoogleFonts.vt323(
        fontSize: 32,
        color: color,
        letterSpacing: 1.2,
      );

  TextStyle _mono(Color color) => GoogleFonts.firaCode(
        fontSize: 13,
        color: color,
        letterSpacing: 0.4,
      );

  @override
  ThemeData buildLight() {
    // Terminal ไม่รองรับ light — fallback เป็น dark
    return buildDark();
  }

  @override
  ThemeData buildDark() {
    final ext = TpixThemeExtension(
      themeId: id,
      brandPrimary: _phosphor,
      brandSecondary: _cyan,
      brandWarm: _amber,
      success: _phosphor,
      danger: _danger,
      bg: _bg,
      card: _card,
      surface: _surface,
      border: _border,
      textPrimary: _textPrimary,
      textSecondary: _textSecondary,
      textMuted: _textMuted,
      glassColor: _phosphor.withValues(alpha: 0.04),
      glassBorder: _phosphor.withValues(alpha: 0.55),
      glassHighlight: _phosphor.withValues(alpha: 0.20),
      brandGradient: LinearGradient(
        colors: [_phosphor, _phosphorDim],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      balanceGradient: LinearGradient(
        colors: [_card, _surface, _bg],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        stops: const [0.0, 0.5, 1.0],
      ),
      screenGradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [_bg, Color(0xFF000402)],
      ),
      cardRadius: 0, // ไม่มีโค้ง — sharp corners เหมือน DOS box
      useGlow: true,
      glowIntensity: 0.6,
      headingStyle: _heading(_textPrimary),
      monoStyle: _mono(_textSecondary),
      useScanlines: true,
      useGrid: false,
    );

    // Mono font ทุก text style — ทำให้รู้สึกเหมือน terminal จริง
    final mono = GoogleFonts.firaCodeTextTheme(
      const TextTheme(
        headlineLarge: TextStyle(fontSize: 26, color: _textPrimary, fontWeight: FontWeight.w700, letterSpacing: 1.0),
        headlineMedium: TextStyle(fontSize: 22, color: _textPrimary, fontWeight: FontWeight.w700, letterSpacing: 0.8),
        headlineSmall: TextStyle(fontSize: 18, color: _textPrimary, fontWeight: FontWeight.w600, letterSpacing: 0.6),
        titleLarge: TextStyle(fontSize: 16, color: _textPrimary, fontWeight: FontWeight.w600, letterSpacing: 0.6),
        titleMedium: TextStyle(fontSize: 14, color: _textPrimary, fontWeight: FontWeight.w500, letterSpacing: 0.4),
        bodyLarge: TextStyle(fontSize: 14, color: _textSecondary),
        bodyMedium: TextStyle(fontSize: 13, color: _textSecondary),
        bodySmall: TextStyle(fontSize: 11, color: _textMuted),
        labelLarge: TextStyle(fontSize: 14, color: _textPrimary, fontWeight: FontWeight.w600),
        labelMedium: TextStyle(fontSize: 12, color: _textSecondary),
        labelSmall: TextStyle(fontSize: 10, color: _textMuted),
      ),
    );

    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: _bg,
      primaryColor: _phosphor,
      colorScheme: const ColorScheme.dark(
        primary: _phosphor,
        secondary: _cyan,
        tertiary: _amber,
        surface: _card,
        error: _danger,
        onPrimary: _bg,
        onSecondary: _bg,
        onSurface: _textPrimary,
      ),
      textTheme: mono.apply(
        bodyColor: _textSecondary,
        displayColor: _textPrimary,
      ),
      iconTheme: const IconThemeData(color: _phosphor),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: _phosphor),
      ),
      dividerColor: _phosphor.withValues(alpha: 0.3),
      extensions: [ext],
    );
  }

  @override
  Widget wrapApp(BuildContext context, Widget child) {
    return CrtScanlineOverlay(child: child);
  }
}
