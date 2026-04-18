/// TPIX Wallet — Theme Bundle Contract
/// แต่ละธีมต้อง implement bundle นี้ — return ThemeData + extension + helpers
///
/// Developed by Xman Studio

import 'package:flutter/material.dart';

/// Identifier ของธีม — ใช้สำหรับ persistence + UI picker
enum ThemeId {
  classic('classic'),
  synthwave('synthwave'),
  terminal('terminal');

  final String key;
  const ThemeId(this.key);

  static ThemeId fromKey(String? k) {
    return ThemeId.values.firstWhere(
      (t) => t.key == k,
      orElse: () => ThemeId.classic,
    );
  }
}

/// Mode ของธีม (light/dark) — บางธีม (เช่น terminal) บังคับ dark เท่านั้น
enum ThemeMode2 { light, dark }

/// Bundle ที่แต่ละธีมต้อง implement
/// — ส่ง ThemeData ที่มี TpixThemeExtension แนบไป
/// — ส่ง background overlay สำหรับ wrap ทุก scaffold
/// — ส่ง metadata (ชื่อ, tagline, icon) สำหรับ picker UI
abstract class ThemeBundle {
  ThemeId get id;
  String get nameTh;
  String get nameEn;
  String get taglineTh;
  String get taglineEn;
  IconData get icon;

  /// บางธีมไม่รองรับ light mode (เช่น terminal CRT)
  bool get supportsLight => true;

  /// Build ThemeData สำหรับ light mode (ถ้า supportsLight=false จะถูก ignore)
  ThemeData buildLight();

  /// Build ThemeData สำหรับ dark mode
  ThemeData buildDark();

  /// Wrap child ด้วย background overlay เฉพาะธีม (sun grid, scanlines, ฯลฯ)
  /// — เรียกที่ MaterialApp.builder → apply ทุกหน้าโดยอัตโนมัติ
  Widget wrapApp(BuildContext context, Widget child);
}

/// Extension ที่แนบกับ ThemeData — widgets เรียกผ่าน
/// `Theme.of(context).extension<TpixThemeExtension>()!`
@immutable
class TpixThemeExtension extends ThemeExtension<TpixThemeExtension> {
  final ThemeId themeId;

  // Brand accents (ปรับตามธีม)
  final Color brandPrimary;
  final Color brandSecondary;
  final Color brandWarm;
  final Color success;
  final Color danger;

  // Surface tones (ใช้แทน hard-coded AppTheme.bgDark/bgCard)
  final Color bg;
  final Color card;
  final Color surface;
  final Color border;

  // Text
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;

  // Glass / effect colors
  final Color glassColor;
  final Color glassBorder;
  final Color glassHighlight;

  // Theme-specific gradients
  final Gradient brandGradient;
  final Gradient balanceGradient;
  final Gradient screenGradient;

  // Card style (ปรับ radius + glow ตามธีม)
  final double cardRadius;
  final bool useGlow;
  final double glowIntensity; // 0..1

  // Typography
  final TextStyle headingStyle;
  final TextStyle monoStyle;

  // Effects
  final bool useScanlines;
  final bool useGrid;

  const TpixThemeExtension({
    required this.themeId,
    required this.brandPrimary,
    required this.brandSecondary,
    required this.brandWarm,
    required this.success,
    required this.danger,
    required this.bg,
    required this.card,
    required this.surface,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.glassColor,
    required this.glassBorder,
    required this.glassHighlight,
    required this.brandGradient,
    required this.balanceGradient,
    required this.screenGradient,
    required this.cardRadius,
    required this.useGlow,
    required this.glowIntensity,
    required this.headingStyle,
    required this.monoStyle,
    required this.useScanlines,
    required this.useGrid,
  });

  /// Helper — เรียกผ่าน `TpixThemeExtension.of(context)` แทน
  /// `Theme.of(context).extension<TpixThemeExtension>()!`
  static TpixThemeExtension of(BuildContext context) {
    final ext = Theme.of(context).extension<TpixThemeExtension>();
    if (ext == null) {
      throw FlutterError(
        'TpixThemeExtension not found — make sure ThemeBundle.buildLight/Dark '
        'attaches it via ThemeData(extensions: [...])',
      );
    }
    return ext;
  }

  @override
  TpixThemeExtension copyWith({
    ThemeId? themeId,
    Color? brandPrimary,
    Color? brandSecondary,
    Color? brandWarm,
    Color? success,
    Color? danger,
    Color? bg,
    Color? card,
    Color? surface,
    Color? border,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? glassColor,
    Color? glassBorder,
    Color? glassHighlight,
    Gradient? brandGradient,
    Gradient? balanceGradient,
    Gradient? screenGradient,
    double? cardRadius,
    bool? useGlow,
    double? glowIntensity,
    TextStyle? headingStyle,
    TextStyle? monoStyle,
    bool? useScanlines,
    bool? useGrid,
  }) {
    return TpixThemeExtension(
      themeId: themeId ?? this.themeId,
      brandPrimary: brandPrimary ?? this.brandPrimary,
      brandSecondary: brandSecondary ?? this.brandSecondary,
      brandWarm: brandWarm ?? this.brandWarm,
      success: success ?? this.success,
      danger: danger ?? this.danger,
      bg: bg ?? this.bg,
      card: card ?? this.card,
      surface: surface ?? this.surface,
      border: border ?? this.border,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      glassColor: glassColor ?? this.glassColor,
      glassBorder: glassBorder ?? this.glassBorder,
      glassHighlight: glassHighlight ?? this.glassHighlight,
      brandGradient: brandGradient ?? this.brandGradient,
      balanceGradient: balanceGradient ?? this.balanceGradient,
      screenGradient: screenGradient ?? this.screenGradient,
      cardRadius: cardRadius ?? this.cardRadius,
      useGlow: useGlow ?? this.useGlow,
      glowIntensity: glowIntensity ?? this.glowIntensity,
      headingStyle: headingStyle ?? this.headingStyle,
      monoStyle: monoStyle ?? this.monoStyle,
      useScanlines: useScanlines ?? this.useScanlines,
      useGrid: useGrid ?? this.useGrid,
    );
  }

  @override
  TpixThemeExtension lerp(ThemeExtension<TpixThemeExtension>? other, double t) {
    // ไม่ทำ lerp จริง — switch ธีมเป็น discrete event ไม่ใช่ animation
    if (other is! TpixThemeExtension) return this;
    return t < 0.5 ? this : other;
  }
}
