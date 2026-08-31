/// ธีมสำหรับเทสต์ — สีครบเหมือนของจริง แต่ใช้ TextStyle ธรรมดา
///
/// 🔴 ห้ามเรียก XxxTheme().buildDark()/buildLight() ในเทสต์
/// แค่ "สร้าง" TextStyle ของ GoogleFonts ก็สั่งดาวน์โหลดฟอนต์ผ่านเน็ตแล้ว
/// ในเทสต์ที่ห่อด้วย tester.runAsync การดาวน์โหลดจะเดินจริงและ throw
/// ทำให้เทสต์ล้มด้วยเหตุผลที่ไม่เกี่ยวกับสิ่งที่กำลังทดสอบเลย
library;

import 'package:flutter/material.dart';
import 'package:tpix_wallet/core/themes/theme_bundle.dart';

ThemeData testTheme({bool dark = true, ThemeId themeId = ThemeId.liquid}) {
  const mint = Color(0xFF2DD4BF);
  const lavender = Color(0xFFA78BFA);

  final ext = TpixThemeExtension(
    themeId: themeId,
    brandPrimary: mint,
    brandSecondary: lavender,
    brandWarm: const Color(0xFFFF9E7D),
    success: const Color(0xFF34D399),
    danger: const Color(0xFFFB7185),
    bg: dark ? const Color(0xFF141733) : const Color(0xFFF3FBFF),
    card: dark ? const Color(0xFF212545) : Colors.white,
    surface: dark ? const Color(0xFF2A2F55) : const Color(0xFFEAF6FF),
    border: dark ? const Color(0xFF373D6B) : const Color(0xFFD8EDF7),
    textPrimary: dark ? Colors.white : const Color(0xFF16394D),
    textSecondary: const Color(0xFF5C7F92),
    textMuted: const Color(0xFF9BB8C6),
    glassColor: Colors.white.withValues(alpha: dark ? 0.09 : 0.78),
    glassBorder: Colors.white.withValues(alpha: 0.5),
    glassHighlight: Colors.white,
    brandGradient: const LinearGradient(colors: [mint, lavender]),
    balanceGradient: const LinearGradient(colors: [mint, lavender]),
    screenGradient: const LinearGradient(colors: [mint, lavender]),
    cardRadius: 28,
    useGlow: true,
    glowIntensity: 0.3,
    headingStyle: const TextStyle(fontSize: 24),
    monoStyle: const TextStyle(fontSize: 14),
    useScanlines: false,
    useGrid: false,
  );

  return ThemeData(
    brightness: dark ? Brightness.dark : Brightness.light,
    extensions: [ext],
  );
}
