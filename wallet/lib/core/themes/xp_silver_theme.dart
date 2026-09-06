/// TPIX Wallet — Windows XP Silver Theme
/// โครเมียมเงิน ขอบนูน 3 มิติ ฟ้าไฮไลต์ — บุคลิกเดสก์ท็อปยุค 2000s
///
/// ทำไมเป็นธีมเดียวไม่ใช่สองธีม: "Silver" เป็นชื่อ visual style จริงของ
/// Windows XP (คู่กับ Luna สีน้ำเงินและ Olive Green) ตัวมันเองคือชุดโครเมียม
/// สีเงินที่ขอบนูนเป็น 3 มิติอยู่แล้ว จึงเป็นธีมเดียวที่มีทั้งสองอย่าง
///
/// ข้อจำกัดที่ตั้งใจ:
/// - ไม่ใช้โลโก้ ไอคอน หรือภาพพื้นหลังของไมโครซอฟท์ — เอาเฉพาะภาษาการออกแบบ
///   (ไล่เฉดเงิน ขอบสว่างบน-เงามืดล่าง มุมมนน้อย ฟ้าไฮไลต์) ซึ่งลอกไม่ได้
/// - โหมดมืดเป็น "กราไฟต์" ที่เราแต่งเอง เพราะ XP ไม่เคยมีโหมดมืด
///   แต่สัญญา ThemeBundle บังคับให้มี buildDark() และผู้ใช้ที่ตั้งมืดไว้
///   ไม่ควรโดนสาดหน้าจอขาวใส่ตอนสลับมาธีมนี้
///
/// Developed by Xman Studio

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'theme_bundle.dart';

class XpSilverTheme extends ThemeBundle {
  // ── โครเมียมเงิน (โหมดสว่าง) ────────────────────────────────
  // ไล่จากสว่างสุดลงมา ใช้เป็นทั้งพื้นแถบและขอบนูน
  static const Color _chromeHi = Color(0xFFFDFDFF); // ขอบสว่างด้านบน-ซ้าย
  static const Color _chrome = Color(0xFFE8E8F0);
  static const Color _chromeMid = Color(0xFFCFCFDD);
  static const Color _chromeLo = Color(0xFFA9A9BE); // เงาด้านล่าง-ขวา
  static const Color _chromeEdge = Color(0xFF7C7C93); // เส้นขอบนอก 1px

  // ── สีเน้น ────────────────────────────────────────────────
  // ฟ้าไฮไลต์ของ XP (สีที่ใช้ตอนเลือกข้อความ) — เป็นตัวเดียวที่ "สด"
  // ในธีมนี้ ที่เหลือเป็นเทาหมด ของสำคัญจึงเด่นขึ้นมาเองโดยไม่ต้องเรืองแสง
  static const Color _xpBlue = Color(0xFF316AC5);
  static const Color _xpBlueDeep = Color(0xFF1C4B99);
  static const Color _xpGreen = Color(0xFF4E9A2A); // เขียวปุ่ม Start
  static const Color _xpAmber = Color(0xFFE8A317);
  static const Color _xpRed = Color(0xFFC4342A);

  // ── โหมดสว่าง ─────────────────────────────────────────────
  static const Color _bgLight = Color(0xFFF1F1F5);
  static const Color _cardLight = Color(0xFFFFFFFF);
  static const Color _surfaceLight = Color(0xFFE9E9F1);
  static const Color _borderLight = Color(0xFF9A9AB0);
  static const Color _textPrimaryLight = Color(0xFF14141C);
  static const Color _textSecondaryLight = Color(0xFF3E3E52);
  static const Color _textMutedLight = Color(0xFF74748C);

  // ── โหมดมืด "กราไฟต์" ─────────────────────────────────────
  static const Color _bgDark = Color(0xFF1B1B21);
  static const Color _cardDark = Color(0xFF262630);
  static const Color _surfaceDark = Color(0xFF31313D);
  static const Color _borderDark = Color(0xFF4C4C5C);
  static const Color _textPrimaryDark = Color(0xFFF2F2F7);
  static const Color _textSecondaryDark = Color(0xFFB9B9C8);
  static const Color _textMutedDark = Color(0xFF7E7E92);

  static const Color _chromeDarkHi = Color(0xFF5A5A6C);
  static const Color _chromeDark = Color(0xFF3A3A48);
  static const Color _chromeDarkLo = Color(0xFF232330);

  /// มุมมนของ XP — หน้าต่างมนแค่มุมบน ราว 6px ไม่ใช่การ์ดมน ๆ แบบสมัยนี้
  static const double _radius = 6;

  @override
  ThemeId get id => ThemeId.xpSilver;

  @override
  String get nameTh => 'เงินคลาสสิก';

  @override
  String get nameEn => 'XP Silver';

  @override
  String get taglineTh => 'โครเมียมเงิน ขอบนูน 3 มิติ';

  @override
  String get taglineEn => 'Silver chrome · 3D bevels';

  @override
  IconData get icon => Icons.desktop_windows_outlined;

  /// Tahoma คือฟอนต์ UI ของ XP แต่เป็นของมีลิขสิทธิ์ Noto Sans เป็นตัวที่
  /// สัดส่วนใกล้ที่สุดในชุดที่แจกฟรี (humanist sans ความสูง x ใกล้กัน)
  TextStyle _heading(Color color) => GoogleFonts.notoSans(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        color: color,
      );

  /// Courier Prime แทน Courier New ที่ XP ใช้กับตัวเลข/โค้ด
  TextStyle _mono(Color color) => GoogleFonts.courierPrime(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: color,
      );

  TextTheme _textTheme(Color primary, Color secondary, Color muted) =>
      GoogleFonts.notoSansTextTheme(
        TextTheme(
          headlineLarge: TextStyle(fontSize: 32, fontWeight: FontWeight.w700, color: primary),
          headlineMedium: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: primary),
          headlineSmall: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: primary),
          titleLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: primary),
          titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: primary),
          bodyLarge: TextStyle(fontSize: 16, color: secondary),
          bodyMedium: TextStyle(fontSize: 14, color: secondary),
          bodySmall: TextStyle(fontSize: 12, color: muted),
        ),
      );

  /// ปุ่มทรง XP — เหลี่ยม ขอบ 1px เงาสั้น ๆ ให้รู้สึกว่ากดลงไปได้
  /// ไม่ใช้ elevation สูงเพราะ XP ไม่มีเงาฟุ้ง มีแต่ขอบคม
  ButtonStyle _buttonStyle({
    required Color fill,
    required Color text,
    required Color edge,
  }) =>
      ElevatedButton.styleFrom(
        backgroundColor: fill,
        foregroundColor: text,
        elevation: 2,
        shadowColor: Colors.black.withValues(alpha: 0.4),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 15),
        textStyle: GoogleFonts.notoSans(fontSize: 15, fontWeight: FontWeight.w700),
        // ทรงแคปซูลตามปุ่ม Start ของ XP — ลายเซ็นของมันคือรูปทรงกับผิวเจล
        // ไม่ใช่สีเขียว สีจึงอิงโทนของเราเอง
        shape: StadiumBorder(side: BorderSide(color: edge, width: 1)),
      );

  /// ช่องกรอกทรง XP — พื้นขาว ขอบจม ไม่มีมุมมนเยอะ
  InputDecorationTheme _inputTheme({
    required Color fill,
    required Color edge,
    required Color hint,
  }) =>
      InputDecorationTheme(
        filled: true,
        fillColor: fill,
        hintStyle: TextStyle(color: hint),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_radius - 3),
          borderSide: BorderSide(color: edge, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_radius - 3),
          borderSide: BorderSide(color: edge, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_radius - 3),
          borderSide: const BorderSide(color: _xpBlue, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_radius - 3),
          borderSide: const BorderSide(color: _xpRed, width: 1),
        ),
      );

  @override
  ThemeData buildLight() {
    final ext = TpixThemeExtension(
      themeId: id,
      brandPrimary: _xpBlue,
      brandSecondary: _chromeLo,
      brandWarm: _xpAmber,
      success: _xpGreen,
      danger: _xpRed,
      bg: _bgLight,
      card: _cardLight,
      surface: _surfaceLight,
      border: _borderLight,
      textPrimary: _textPrimaryLight,
      textSecondary: _textSecondaryLight,
      textMuted: _textMutedLight,
      // "กระจก" ของธีมนี้ไม่ใช่ฝ้า แต่เป็นแผ่นโลหะทึบ — โปร่งแสงแล้วจะเสีย
      // ความรู้สึกว่ามันเป็นของแข็งที่กดได้ ซึ่งคือหัวใจของหน้าตายุคนั้น
      glassColor: _chrome,
      glassBorder: _chromeEdge,
      glassHighlight: _chromeHi,
      // โค้งแสงบนผิวโลหะ — ห้ามเป็นไล่สองสีเรียบ ๆ
      // ของ XP มีแถบสว่างเด้งใกล้ยอด (8%) ค่อย ๆ คล้ำลง แล้วจบด้วยเส้นเข้ม
      // คมที่ก้นสุด นั่นคือขอบล่างของแผ่นที่รับแสงไม่ถึง — ตัดสต็อปไหนออก
      // ก็เหลือแค่ "เทา ๆ" ไม่ใช่โลหะ
      brandGradient: const LinearGradient(
        colors: [_chromeHi, Color(0xFFF4F4F9), _chrome, _chromeMid, _chromeLo],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        stops: [0.0, 0.08, 0.55, 0.94, 1.0],
      ),
      // การ์ดยอดเงินใช้ฟ้าไฮไลต์ ไม่ใช่เงิน — โครเมียมเงินเป็นสีของ "กรอบ"
      // ถ้าเอามาเป็นพื้นการ์ดพระเอกด้วย ตัวเลขยอดเงินจะจมหายไปกับกรอบ
      balanceGradient: const LinearGradient(
        colors: [Color(0xFF5B8FE0), _xpBlue, _xpBlueDeep],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        stops: [0.0, 0.5, 1.0],
      ),
      screenGradient: const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFF8F8FC), _bgLight],
      ),
      cardRadius: _radius,
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
      primaryColor: _xpBlue,
      colorScheme: const ColorScheme.light(
        primary: _xpBlue,
        secondary: _chromeLo,
        tertiary: _xpGreen,
        surface: _cardLight,
        error: _xpRed,
        onPrimary: Colors.white,
        onSurface: _textPrimaryLight,
      ),
      textTheme: _textTheme(_textPrimaryLight, _textSecondaryLight, _textMutedLight),
      iconTheme: const IconThemeData(color: _textSecondaryLight),
      dividerColor: _borderLight,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: _textSecondaryLight),
      ),
      cardTheme: CardThemeData(
        color: _cardLight,
        elevation: 1,
        shadowColor: Colors.black.withValues(alpha: 0.25),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_radius),
          side: const BorderSide(color: _borderLight, width: 1),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: _buttonStyle(fill: _xpBlue, text: Colors.white, edge: _xpBlueDeep),
      ),
      inputDecorationTheme: _inputTheme(
        fill: Colors.white,
        edge: _borderLight,
        hint: _textMutedLight,
      ),
      // แถบเลื่อน/สวิตช์ใช้ฟ้าไฮไลต์ตัวเดียวกัน ให้ทั้งแอปพูดภาษาเดียว
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? _xpBlue : _chromeLo,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? _xpBlue.withValues(alpha: 0.35)
              : _chromeMid,
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: _xpGreen,
        linearTrackColor: _chromeMid,
      ),
      extensions: [ext],
    );
  }

  @override
  ThemeData buildDark() {
    final ext = TpixThemeExtension(
      themeId: id,
      brandPrimary: _xpBlue,
      brandSecondary: _chromeDarkHi,
      brandWarm: _xpAmber,
      success: _xpGreen,
      danger: _xpRed,
      bg: _bgDark,
      card: _cardDark,
      surface: _surfaceDark,
      border: _borderDark,
      textPrimary: _textPrimaryDark,
      textSecondary: _textSecondaryDark,
      textMuted: _textMutedDark,
      glassColor: _chromeDark,
      glassBorder: _chromeDarkLo,
      glassHighlight: _chromeDarkHi,
      brandGradient: const LinearGradient(
        colors: [
          Color(0xFF6C6C80), _chromeDarkHi, _chromeDark,
          Color(0xFF2C2C38), _chromeDarkLo,
        ],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        stops: [0.0, 0.08, 0.55, 0.94, 1.0],
      ),
      balanceGradient: const LinearGradient(
        colors: [Color(0xFF2F5FA8), Color(0xFF224881), Color(0xFF16305F)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        stops: [0.0, 0.5, 1.0],
      ),
      screenGradient: const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF23232C), _bgDark],
      ),
      cardRadius: _radius,
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
      primaryColor: _xpBlue,
      colorScheme: const ColorScheme.dark(
        primary: _xpBlue,
        secondary: _chromeDarkHi,
        tertiary: _xpGreen,
        surface: _cardDark,
        error: _xpRed,
        onPrimary: Colors.white,
        onSurface: _textPrimaryDark,
      ),
      textTheme: _textTheme(_textPrimaryDark, _textSecondaryDark, _textMutedDark),
      iconTheme: const IconThemeData(color: _textSecondaryDark),
      dividerColor: _borderDark,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: _textSecondaryDark),
      ),
      cardTheme: CardThemeData(
        color: _cardDark,
        elevation: 1,
        shadowColor: Colors.black.withValues(alpha: 0.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_radius),
          side: const BorderSide(color: _borderDark, width: 1),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: _buttonStyle(fill: _xpBlue, text: Colors.white, edge: _xpBlueDeep),
      ),
      inputDecorationTheme: _inputTheme(
        fill: _surfaceDark,
        edge: _borderDark,
        hint: _textMutedDark,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? _xpBlue : _chromeDarkHi,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? _xpBlue.withValues(alpha: 0.4)
              : _chromeDarkLo,
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: _xpGreen,
        linearTrackColor: _chromeDarkLo,
      ),
      extensions: [ext],
    );
  }

  @override
  Widget wrapApp(BuildContext context, Widget child) {
    // ไม่มี overlay — บุคลิกของธีมนี้อยู่ที่ขอบและเฉดของตัวชิ้นส่วนเอง
    // ถ้าคลุมทับด้วยอะไรอีกชั้น ขอบนูนที่เป็นตัวตนของมันจะจมหายไปทันที
    return child;
  }
}
