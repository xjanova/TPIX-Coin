/// TPIX Wallet — ธีม Obsidian (ดีไซน์ A · Obsidian Premium)
///
/// พื้นดำ obsidian + คลิปพื้นหลังเทคเคลื่อนไหวครึ่งบนของจอ + บัตรโลหะประจำเชน
/// + ไอคอน 3D + แผงกระจกขอบนูน (ไฮไลต์ขาวด้านบน / เงาดำด้านล่าง)
///
/// เป็นธีมมืดอย่างเดียว (เหมือน terminal) — ภาษาออกแบบทั้งชุดตั้งอยู่บนพื้นดำ
/// ถ้ามีโหมดสว่าง บัตรโลหะ/ไอคอนเรืองแสงจะดูผิดที่ทันที
///
/// Developed by Xman Studio
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'obsidian_tokens.dart';
import 'theme_bundle.dart';
import 'widgets/obsidian_background.dart';

class ObsidianTheme extends ThemeBundle {
  @override
  ThemeId get id => ThemeId.obsidian;

  @override
  String get nameTh => 'ออบซิเดียน';

  @override
  String get nameEn => 'Obsidian';

  @override
  String get taglineTh => 'ดำพรีเมียม · บัตรโลหะ · ไอคอน 3D';

  @override
  String get taglineEn => 'Premium black · Metal cards · 3D icons';

  @override
  IconData get icon => Icons.diamond_rounded;

  /// มืดอย่างเดียว — หน้าเลือกธีมจะซ่อนสวิตช์สว่าง/มืดให้เอง
  @override
  bool get supportsLight => false;

  @override
  ThemeData buildLight() => buildDark();

  @override
  ThemeData buildDark() {
    const c = ObsidianColors.text;
    const sec = ObsidianColors.textSec;
    const muted = ObsidianColors.textMuted;

    final ext = TpixThemeExtension(
      themeId: id,
      brandPrimary: ObsidianColors.cyan,
      brandSecondary: ObsidianColors.violet,
      brandWarm: ObsidianColors.orange,
      success: ObsidianColors.success,
      danger: ObsidianColors.danger,
      bg: ObsidianColors.ground,
      card: ObsidianColors.card,
      surface: ObsidianColors.surface,
      border: Colors.white.withValues(alpha: 0.10),
      textPrimary: c,
      textSecondary: sec,
      textMuted: muted,
      // แผงกระจก: ขาว 6% → 2% (ดู ObsidianPanel) — glassColor ใช้กับวิดเจ็ตเดิมที่ยังไม่รื้อ
      glassColor: Colors.white.withValues(alpha: 0.06),
      glassBorder: Colors.white.withValues(alpha: 0.10),
      glassHighlight: Colors.white.withValues(alpha: 0.18),
      brandGradient: ObsidianColors.accentGradient,
      // การ์ดยอดเงินแบบเดิม (หน้าที่ยังไม่รื้อ) = โลหะเข้ม ไม่ใช่ไล่สีสด
      balanceGradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF1E2230), Color(0xFF12141B), Color(0xFF0A0B10)],
        stops: [0.0, 0.55, 1.0],
      ),
      // ★ โปร่งใส: ให้พื้นหลังวิดีโอของ wrapApp โชว์ผ่านทุกหน้า
      // (TpixScreenBackground วาดไล่สีนี้ทับ — ถ้าทึบจะบังคลิปพื้นหลังหมด)
      screenGradient: const LinearGradient(
        colors: [Color(0x00000000), Color(0x00000000)],
      ),
      cardRadius: 22,
      useGlow: false,
      glowIntensity: 0,
      headingStyle: GoogleFonts.ibmPlexSansThai(
        fontSize: 24,
        fontWeight: FontWeight.w600,
        color: c,
      ),
      monoStyle: GoogleFonts.ibmPlexMono(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: ObsidianColors.textSoft,
      ),
      useScanlines: false,
      useGrid: false,
    );

    // เลือกไฟล์ฟอนต์ตามน้ำหนักจริง (google_fonts โหลด/แคชให้ทีละน้ำหนัก)
    final style = ObsidianStyle(
      uiFont: (w) => GoogleFonts.ibmPlexSansThai(fontWeight: w, color: c),
      numberFont: (w) => GoogleFonts.spaceGrotesk(fontWeight: w, color: c),
      monoFont: (w) => GoogleFonts.ibmPlexMono(fontWeight: w, color: ObsidianColors.textSoft),
    );

    final textTheme = GoogleFonts.ibmPlexSansThaiTextTheme(
      const TextTheme(
        headlineLarge: TextStyle(fontSize: 30, fontWeight: FontWeight.w600, color: c),
        headlineMedium: TextStyle(fontSize: 24, fontWeight: FontWeight.w600, color: c),
        headlineSmall: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: c),
        titleLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: c),
        titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: c),
        titleSmall: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c),
        bodyLarge: TextStyle(fontSize: 15, color: c),
        bodyMedium: TextStyle(fontSize: 14, color: sec),
        bodySmall: TextStyle(fontSize: 12, color: muted),
        labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c),
        labelMedium: TextStyle(fontSize: 12, color: sec),
        labelSmall: TextStyle(fontSize: 11, color: muted),
      ),
    );

    return ThemeData(
      brightness: Brightness.dark,
      // โปร่ง — พื้นจริงคือ ObsidianBackground ที่ห่อทั้งแอป
      scaffoldBackgroundColor: Colors.transparent,
      canvasColor: ObsidianColors.card,
      primaryColor: ObsidianColors.cyan,
      colorScheme: const ColorScheme.dark(
        primary: ObsidianColors.cyan,
        onPrimary: ObsidianColors.ground,
        secondary: ObsidianColors.violet,
        onSecondary: Colors.white,
        tertiary: ObsidianColors.orange,
        surface: ObsidianColors.card,
        onSurface: c,
        error: ObsidianColors.danger,
      ),
      textTheme: textTheme,
      iconTheme: const IconThemeData(color: ObsidianColors.chrome),
      dividerColor: Colors.white.withValues(alpha: 0.08),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: c,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF1E2230),
        contentTextStyle: GoogleFonts.ibmPlexSansThai(fontSize: 14, color: c),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: ObsidianColors.card,
        modalBackgroundColor: ObsidianColors.card,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: ObsidianColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: ObsidianColors.cyan,
      ),
      extensions: [ext, style],
    );
  }

  @override
  Widget wrapApp(BuildContext context, Widget child) {
    // คลิปพื้นหลังวนลูปหลังครึ่งบนของจอ + ไล่มืดลงล่าง (ทุกหน้า)
    return ObsidianBackground(child: child);
  }
}
