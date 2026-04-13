import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Brand Colors (shared between modes)
  static const Color primary = Color(0xFF06B6D4);    // Cyan
  static const Color accent = Color(0xFF8B5CF6);      // Purple
  static const Color warm = Color(0xFFF59E0B);        // Amber
  static const Color success = Color(0xFF00C853);     // Green
  static const Color danger = Color(0xFFFF1744);      // Red

  // ── Dark Mode Colors ──────────────────────────────
  static const Color bgDark = Color(0xFF0A0E17);
  static const Color bgCard = Color(0xFF111827);
  static const Color bgSurface = Color(0xFF1A2035);
  static const Color borderDim = Color(0xFF1E293B);
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFF94A3B8);
  static const Color textMuted = Color(0xFF475569);

  // ── Light Mode Colors ─────────────────────────────
  static const Color bgLight = Color(0xFFF5F7FA);
  static const Color bgCardLight = Color(0xFFFFFFFF);
  static const Color bgSurfaceLight = Color(0xFFF0F2F5);
  static const Color borderLight = Color(0xFFE2E8F0);
  static const Color textPrimaryLight = Color(0xFF0F172A);
  static const Color textSecondaryLight = Color(0xFF475569);
  static const Color textMutedLight = Color(0xFF94A3B8);

  // Gradients
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

  static ThemeData get darkTheme => ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: bgDark,
    primaryColor: primary,
    colorScheme: const ColorScheme.dark(
      primary: primary,
      secondary: accent,
      surface: bgCard,
      error: danger,
    ),
    textTheme: GoogleFonts.spaceGroteskTextTheme(
      const TextTheme(
        headlineLarge: TextStyle(fontSize: 32, fontWeight: FontWeight.w700, color: textPrimary),
        headlineMedium: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: textPrimary),
        headlineSmall: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: textPrimary),
        titleLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: textPrimary),
        titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: textPrimary),
        bodyLarge: TextStyle(fontSize: 16, color: textSecondary),
        bodyMedium: TextStyle(fontSize: 14, color: textSecondary),
        bodySmall: TextStyle(fontSize: 12, color: textMuted),
      ),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
    ),
  );

  static ThemeData get lightTheme => ThemeData(
    brightness: Brightness.light,
    scaffoldBackgroundColor: bgLight,
    primaryColor: primary,
    colorScheme: const ColorScheme.light(
      primary: primary,
      secondary: accent,
      surface: bgCardLight,
      error: danger,
    ),
    textTheme: GoogleFonts.spaceGroteskTextTheme(
      const TextTheme(
        headlineLarge: TextStyle(fontSize: 32, fontWeight: FontWeight.w700, color: textPrimaryLight),
        headlineMedium: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: textPrimaryLight),
        headlineSmall: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: textPrimaryLight),
        titleLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: textPrimaryLight),
        titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: textPrimaryLight),
        bodyLarge: TextStyle(fontSize: 16, color: textSecondaryLight),
        bodyMedium: TextStyle(fontSize: 14, color: textSecondaryLight),
        bodySmall: TextStyle(fontSize: 12, color: textMutedLight),
      ),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
    ),
  );
}

/// Adaptive color helper — use `AppColors.of(context)` in widgets
class AppColors {
  final bool isDark;

  const AppColors._({required this.isDark});

  factory AppColors.of(BuildContext context) {
    return AppColors._(isDark: Theme.of(context).brightness == Brightness.dark);
  }

  // Backgrounds
  Color get bg => isDark ? AppTheme.bgDark : AppTheme.bgLight;
  Color get card => isDark ? AppTheme.bgCard : AppTheme.bgCardLight;
  Color get surface => isDark ? AppTheme.bgSurface : AppTheme.bgSurfaceLight;

  // Text
  Color get text => isDark ? AppTheme.textPrimary : AppTheme.textPrimaryLight;
  Color get textSec => isDark ? AppTheme.textSecondary : AppTheme.textSecondaryLight;
  Color get textMuted => isDark ? AppTheme.textMuted : AppTheme.textMutedLight;

  // Borders
  Color get border => isDark ? AppTheme.borderDim : AppTheme.borderLight;

  // Glass card colors
  Color get glassColor => isDark
      ? Colors.white.withValues(alpha: 0.07)
      : Colors.white.withValues(alpha: 0.92);
  Color get glassBorder => isDark
      ? Colors.white.withValues(alpha: 0.10)
      : Colors.black.withValues(alpha: 0.08);
  // Top-edge highlight for light-catch effect
  Color get glassHighlight => isDark
      ? Colors.white.withValues(alpha: 0.12)
      : Colors.white;

  // Screen background gradient
  BoxDecoration get screenBg => BoxDecoration(
    gradient: isDark
        ? const RadialGradient(
            center: Alignment(0, -0.5),
            radius: 1.5,
            colors: [Color(0xFF0C1929), AppTheme.bgDark],
          )
        : const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFEEF2FF), AppTheme.bgLight],
          ),
  );

  // Settings screen gradient (slightly different tint)
  BoxDecoration get settingsBg => BoxDecoration(
    gradient: isDark
        ? const RadialGradient(
            center: Alignment(0, -0.3),
            radius: 1.5,
            colors: [Color(0xFF0F172A), AppTheme.bgDark],
          )
        : const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFEEF2FF), AppTheme.bgLight],
          ),
  );

  // Card shadows for depth
  List<BoxShadow> get cardShadow => isDark
      ? [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 16,
            offset: const Offset(0, 6),
            spreadRadius: 1,
          ),
          BoxShadow(
            color: AppTheme.primary.withValues(alpha: 0.05),
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
            color: AppTheme.primary.withValues(alpha: 0.06),
            blurRadius: 24,
            offset: const Offset(0, 2),
          ),
        ];

  // Elevated card shadows (balance card, etc.)
  List<BoxShadow> get elevatedShadow => isDark
      ? [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.6),
            blurRadius: 30,
            offset: const Offset(0, 10),
            spreadRadius: 4,
          ),
          BoxShadow(
            color: AppTheme.primary.withValues(alpha: 0.12),
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
            color: AppTheme.primary.withValues(alpha: 0.08),
            blurRadius: 40,
            offset: const Offset(0, 4),
          ),
        ];

  // Accent glow shadow for special cards (identity, promo)
  List<BoxShadow> accentGlow(Color color) => isDark
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

  // Balance card gradient
  LinearGradient get balanceGradient => isDark
      ? const LinearGradient(
          colors: [Color(0xFF122E4D), Color(0xFF0D1B33), Color(0xFF081222)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          stops: [0.0, 0.6, 1.0],
        )
      : const LinearGradient(
          colors: [Color(0xFF0E8EA1), Color(0xFF086B7D), Color(0xFF055062)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          stops: [0.0, 0.5, 1.0],
        );

  // Action button background
  Color actionBtnBg(Color color) => isDark
      ? color.withValues(alpha: 0.08)
      : color.withValues(alpha: 0.06);

  // Action button border
  Color actionBtnBorder(Color color) => isDark
      ? color.withValues(alpha: 0.15)
      : color.withValues(alpha: 0.12);

  // Action button icon circle
  Color actionBtnIcon(Color color) => isDark
      ? color.withValues(alpha: 0.15)
      : color.withValues(alpha: 0.12);
}

/// Glass card decoration with depth — use adaptive version via `adaptiveGlassCard(context)`
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

/// Adaptive glass card that respects current theme — with inner gradient for depth
BoxDecoration adaptiveGlassCard(BuildContext context, {
  double borderRadius = 24,
  Color? borderColor,
}) {
  final c = AppColors.of(context);
  return BoxDecoration(
    borderRadius: BorderRadius.circular(borderRadius),
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

/// Glass card with colored accent glow
BoxDecoration accentGlassCard(BuildContext context, {
  double borderRadius = 20,
  required Color accent,
}) {
  final c = AppColors.of(context);
  return BoxDecoration(
    borderRadius: BorderRadius.circular(borderRadius),
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
