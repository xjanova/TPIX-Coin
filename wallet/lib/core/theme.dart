/// TPIX Wallet — Theme Facade
/// — Backward-compat layer: AppTheme + AppColors + glass helpers
/// — อ่านสีจริงจาก TpixThemeExtension (ปรับตามธีมที่เลือก)
///
/// Developed by Xman Studio

import 'package:flutter/material.dart';
import 'themes/theme_bundle.dart';

/// Static fallback colors — ใช้ตอนที่ context ยังไม่พร้อม (เช่น splash splash early)
/// ส่วนใหญ่ widgets ควรใช้ `AppColors.of(context)` ที่ปรับตามธีมแทน
class AppTheme {
  // Brand fallbacks (Classic) — ใช้เฉพาะตอน context ไม่มี
  static const Color primary = Color(0xFF06B6D4);
  static const Color accent = Color(0xFF8B5CF6);
  static const Color warm = Color(0xFFF59E0B);
  static const Color success = Color(0xFF00C853);
  static const Color danger = Color(0xFFFF1744);

  // Surface fallbacks
  static const Color bgDark = Color(0xFF0A0E17);
  static const Color bgCard = Color(0xFF111827);
  static const Color bgSurface = Color(0xFF1A2035);
  static const Color borderDim = Color(0xFF1E293B);
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFF94A3B8);
  static const Color textMuted = Color(0xFF475569);

  static const Color bgLight = Color(0xFFF5F7FA);
  static const Color bgCardLight = Color(0xFFFFFFFF);
  static const Color bgSurfaceLight = Color(0xFFF0F2F5);
  static const Color borderLight = Color(0xFFE2E8F0);
  static const Color textPrimaryLight = Color(0xFF0F172A);
  static const Color textSecondaryLight = Color(0xFF475569);
  static const Color textMutedLight = Color(0xFF94A3B8);

  // Static gradients (fallback only — prefer AppColors.of(context).brandGradient)
  static const LinearGradient brandGradient = LinearGradient(
    colors: [primary, accent],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient goldGradient = LinearGradient(
    colors: [Color(0xFFFFD700), Color(0xFFF59E0B), Color(0xFFFF8C00)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient glassGradient = LinearGradient(
    colors: [Color(0x15FFFFFF), Color(0x05FFFFFF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

/// Adaptive color helper — อ่านจาก TpixThemeExtension (ตามธีมที่เลือก)
/// Backward compatible — API เหมือนเดิม widgets ที่ใช้อยู่ไม่ต้องแก้
class AppColors {
  final TpixThemeExtension _ext;
  final bool isDark;

  AppColors._(this._ext, this.isDark);

  factory AppColors.of(BuildContext context) {
    final ext = TpixThemeExtension.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AppColors._(ext, isDark);
  }

  // ── Brand (จากธีมปัจจุบัน — ไม่ใช่ static) ──
  Color get brandPrimary => _ext.brandPrimary;
  Color get brandSecondary => _ext.brandSecondary;
  Color get brandWarm => _ext.brandWarm;
  Color get brandSuccess => _ext.success;
  Color get brandDanger => _ext.danger;

  // ── Backgrounds ──
  Color get bg => _ext.bg;
  Color get card => _ext.card;
  Color get surface => _ext.surface;

  // ── Text ──
  Color get text => _ext.textPrimary;
  Color get textSec => _ext.textSecondary;
  Color get textMuted => _ext.textMuted;

  // ── Border ──
  Color get border => _ext.border;

  // ── Glass ──
  Color get glassColor => _ext.glassColor;
  Color get glassBorder => _ext.glassBorder;
  Color get glassHighlight => _ext.glassHighlight;

  // ── Screen background gradient ──
  BoxDecoration get screenBg => BoxDecoration(gradient: _ext.screenGradient);

  // Settings ใช้ gradient เดียวกันกับ screen — ปรับเฉพาะตอน classic
  BoxDecoration get settingsBg {
    if (_ext.themeId == ThemeId.classic && isDark) {
      return const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0, -0.3),
          radius: 1.5,
          colors: [Color(0xFF0F172A), AppTheme.bgDark],
        ),
      );
    }
    return BoxDecoration(gradient: _ext.screenGradient);
  }

  // ── Card shadows ──
  List<BoxShadow> get cardShadow {
    if (_ext.useGlow) {
      // Synthwave/Terminal — neon glow shadow
      return [
        BoxShadow(
          color: _ext.brandPrimary.withValues(alpha: 0.3 * _ext.glowIntensity),
          blurRadius: 20,
          spreadRadius: -2,
        ),
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.5),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
      ];
    }
    return isDark
        ? [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.45),
              blurRadius: 16,
              offset: const Offset(0, 6),
              spreadRadius: 1,
            ),
            BoxShadow(
              color: _ext.brandPrimary.withValues(alpha: 0.05),
              blurRadius: 24,
              offset: const Offset(0, -2),
            ),
          ]
        : [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 16,
              offset: const Offset(0, 6),
              spreadRadius: 1,
            ),
            BoxShadow(
              color: _ext.brandPrimary.withValues(alpha: 0.06),
              blurRadius: 24,
              offset: const Offset(0, 2),
            ),
          ];
  }

  List<BoxShadow> get elevatedShadow {
    if (_ext.useGlow) {
      return [
        BoxShadow(
          color: _ext.brandPrimary.withValues(alpha: 0.5 * _ext.glowIntensity),
          blurRadius: 32,
          spreadRadius: -2,
        ),
        BoxShadow(
          color: _ext.brandSecondary.withValues(alpha: 0.3 * _ext.glowIntensity),
          blurRadius: 48,
          spreadRadius: -8,
        ),
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.6),
          blurRadius: 20,
          offset: const Offset(0, 10),
        ),
      ];
    }
    return isDark
        ? [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.6),
              blurRadius: 30,
              offset: const Offset(0, 10),
              spreadRadius: 4,
            ),
            BoxShadow(
              color: _ext.brandPrimary.withValues(alpha: 0.12),
              blurRadius: 40,
              offset: const Offset(0, -4),
            ),
          ]
        : [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.10),
              blurRadius: 30,
              offset: const Offset(0, 10),
              spreadRadius: 4,
            ),
            BoxShadow(
              color: _ext.brandPrimary.withValues(alpha: 0.08),
              blurRadius: 40,
              offset: const Offset(0, 4),
            ),
          ];
  }

  List<BoxShadow> accentGlow(Color color) {
    if (_ext.useGlow) {
      return [
        BoxShadow(
          color: color.withValues(alpha: 0.45 * _ext.glowIntensity),
          blurRadius: 24,
          spreadRadius: -2,
        ),
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.5),
          blurRadius: 16,
          offset: const Offset(0, 6),
        ),
      ];
    }
    return isDark
        ? [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
            BoxShadow(
              color: color.withValues(alpha: 0.15),
              blurRadius: 30,
              spreadRadius: -4,
            ),
          ]
        : [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
            BoxShadow(
              color: color.withValues(alpha: 0.10),
              blurRadius: 30,
              spreadRadius: -4,
            ),
          ];
  }

  // ── Balance gradient ──
  Gradient get balanceGradient => _ext.balanceGradient;

  // ── Action button colors ──
  Color actionBtnBg(Color color) => _ext.useGlow
      ? color.withValues(alpha: 0.12)
      : (isDark ? color.withValues(alpha: 0.08) : color.withValues(alpha: 0.06));

  Color actionBtnBorder(Color color) => _ext.useGlow
      ? color.withValues(alpha: 0.45)
      : (isDark ? color.withValues(alpha: 0.15) : color.withValues(alpha: 0.12));

  Color actionBtnIcon(Color color) => _ext.useGlow
      ? color.withValues(alpha: 0.20)
      : (isDark ? color.withValues(alpha: 0.15) : color.withValues(alpha: 0.12));
}

/// Glass card decoration — backward compat (legacy widgets)
BoxDecoration glassCard({
  double borderRadius = 24,
  Color? borderColor,
  double opacity = 0.06,
}) {
  return BoxDecoration(
    borderRadius: BorderRadius.circular(borderRadius),
    color: Colors.white.withValues(alpha: opacity),
    border: Border.all(
      color: borderColor ?? Colors.white.withValues(alpha: 0.08),
      width: 1,
    ),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.25),
        blurRadius: 12,
        offset: const Offset(0, 4),
      ),
    ],
  );
}

/// Adaptive glass card — ตามธีมที่เลือก
BoxDecoration adaptiveGlassCard(
  BuildContext context, {
  double? borderRadius,
  Color? borderColor,
}) {
  final c = AppColors.of(context);
  final ext = TpixThemeExtension.of(context);
  final radius = borderRadius ?? ext.cardRadius;

  if (ext.themeId == ThemeId.terminal) {
    // Terminal — sharp box, double-line border, no gradient
    return BoxDecoration(
      borderRadius: BorderRadius.circular(radius),
      color: ext.card,
      border: Border.all(
        color: borderColor ?? ext.brandPrimary.withValues(alpha: 0.7),
        width: 1.5,
      ),
      boxShadow: [
        BoxShadow(
          color: ext.brandPrimary.withValues(alpha: 0.15),
          blurRadius: 12,
          spreadRadius: -2,
        ),
      ],
    );
  }

  if (ext.themeId == ThemeId.synthwave) {
    // Synthwave — neon outline + dark inside + subtle pink/cyan tint
    return BoxDecoration(
      borderRadius: BorderRadius.circular(radius),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          ext.brandPrimary.withValues(alpha: 0.10),
          ext.brandSecondary.withValues(alpha: 0.06),
        ],
      ),
      border: Border.all(
        color: borderColor ?? ext.brandPrimary.withValues(alpha: 0.55),
        width: 1.2,
      ),
      boxShadow: [
        BoxShadow(
          color: ext.brandPrimary.withValues(alpha: 0.25 * ext.glowIntensity),
          blurRadius: 16,
          spreadRadius: -1,
        ),
      ],
    );
  }

  // Classic glass card (default)
  return BoxDecoration(
    borderRadius: BorderRadius.circular(radius),
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: c.isDark
          ? [Colors.white.withValues(alpha: 0.09), Colors.white.withValues(alpha: 0.04)]
          : [Colors.white.withValues(alpha: 0.95), Colors.white.withValues(alpha: 0.85)],
    ),
    border: Border.all(
      color: borderColor ?? c.glassBorder,
      width: 1,
    ),
    boxShadow: c.cardShadow,
  );
}

/// Glass card ที่ accent color เฉพาะ (identity, promo) — ตามธีม
BoxDecoration accentGlassCard(
  BuildContext context, {
  double? borderRadius,
  required Color accent,
}) {
  final c = AppColors.of(context);
  final ext = TpixThemeExtension.of(context);
  final radius = borderRadius ?? (ext.cardRadius - 4).clamp(0.0, double.infinity);

  if (ext.themeId == ThemeId.terminal) {
    return BoxDecoration(
      borderRadius: BorderRadius.circular(radius),
      color: ext.card,
      border: Border.all(color: accent.withValues(alpha: 0.7), width: 1.5),
      boxShadow: [
        BoxShadow(
          color: accent.withValues(alpha: 0.25),
          blurRadius: 14,
          spreadRadius: -2,
        ),
      ],
    );
  }

  return BoxDecoration(
    borderRadius: BorderRadius.circular(radius),
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: c.isDark
          ? [accent.withValues(alpha: 0.12), accent.withValues(alpha: 0.04)]
          : [accent.withValues(alpha: 0.08), accent.withValues(alpha: 0.03)],
    ),
    border: Border.all(color: accent.withValues(alpha: c.isDark ? 0.25 : 0.15)),
    boxShadow: c.accentGlow(accent),
  );
}
