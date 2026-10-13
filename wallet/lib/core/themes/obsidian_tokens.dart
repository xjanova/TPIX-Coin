/// TPIX Wallet — โทเคนของธีม Obsidian (ดีไซน์ A ที่เจ้าของเลือก)
///
/// ต้นฉบับ = HTML mock ที่อนุมัติแล้ว `D:/Code/TPIX/design/tpix-wallet-v2/mock/*.dc.html`
/// ค่าสี/เงา/ความมนทุกตัวในไฟล์นี้ลอกจาก inline style ของ mock ตรง ๆ —
/// ถ้าจะปรับ ให้แก้ mock ก่อนแล้วค่อยตามมาแก้ที่นี่ ไม่ใช่กลับกัน
///
/// Developed by Xman Studio
library;

import 'package:flutter/material.dart';

/// จานสีของ Obsidian — มืดล้วน (ธีมนี้ไม่มีโหมดสว่าง)
abstract final class ObsidianColors {
  /// พื้นทั้งแอป
  static const ground = Color(0xFF07080C);

  /// พื้นทึบของแผ่นที่ต้องอ่านง่าย (bottom sheet / dialog) — ไม่โปร่งเพราะลอยทับเนื้อหา
  static const card = Color(0xFF12141B);
  static const surface = Color(0xFF161920);

  /// ปุ่มรองสีเข้ม (ไล่จากบนลงล่าง)
  static const darkTop = Color(0xFF232733);
  static const darkBottom = Color(0xFF161920);

  // ── ตัวอักษร ──
  static const text = Color(0xFFF2F3F5);
  static const textSoft = Color(0xFFD5D8DF);
  static const textSec = Color(0xFFA3A8B4);
  static const textMuted = Color(0xFF8E94A2);

  /// ลูกศร/ไอคอนเส้นเล็ก ๆ และป้ายบนหน้าบัตร
  static const chrome = Color(0xFFC9CCD4);

  // ── สีแบรนด์ (ไล่ตามโลโก้ TPIX) ──
  static const cyan = Color(0xFF22D3EE);
  static const violet = Color(0xFF8B5CF6);
  static const orange = Color(0xFFFB923C);

  // ── สถานะ ──
  static const success = Color(0xFF34D399);
  static const successSoft = Color(0xFF6EE7B7);
  static const successPale = Color(0xFFA7F3D0);
  static const danger = Color(0xFFF87171);
  static const dangerSoft = Color(0xFFFCA5A5);
  static const warning = Color(0xFFFCD34D);

  /// ไล่สีหลักของแบรนด์ cyan → violet → orange
  static const accentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [cyan, violet, orange],
    stops: [0.0, 0.55, 1.0],
  );
}

/// เงาแบบ CSS `box-shadow: x y blur spread color`
///
/// ทำไมไม่ใช้ BoxShadow ตรง ๆ: ค่า blur ของ CSS คือ 2σ ส่วน BoxShadow.blurRadius
/// ถูกแปลงเป็น σ ด้วยสูตร 0.577r + 0.5 — ใส่เลขเดียวกันจะได้เงาฟุ้งต่างกันเกือบเท่าตัว
/// คลาสนี้แปลงให้ตรงกับที่เห็นใน mock
@immutable
class CssShadow {
  final double x;
  final double y;
  final double blur;
  final double spread;
  final Color color;

  const CssShadow(this.x, this.y, this.blur, this.spread, this.color);

  /// σ ของ Gaussian ตามนิยาม CSS
  double get sigma => blur / 2;

  Offset get offset => Offset(x, y);

  BoxShadow toBoxShadow() => BoxShadow(
        color: color,
        offset: offset,
        // แปลงกลับจาก σ → blurRadius ของ Flutter
        blurRadius: sigma <= 0.5 ? 0 : (sigma - 0.5) / 0.57735,
        spreadRadius: spread,
      );

  CssShadow withColor(Color c) => CssShadow(x, y, blur, spread, c);

  @override
  bool operator ==(Object other) =>
      other is CssShadow &&
      other.x == x &&
      other.y == y &&
      other.blur == blur &&
      other.spread == spread &&
      other.color == color;

  @override
  int get hashCode => Object.hash(x, y, blur, spread, color);

  static CssShadow lerp(CssShadow a, CssShadow b, double t) => CssShadow(
        a.x + (b.x - a.x) * t,
        a.y + (b.y - a.y) * t,
        a.blur + (b.blur - a.blur) * t,
        a.spread + (b.spread - a.spread) * t,
        Color.lerp(a.color, b.color, t)!,
      );
}

/// สร้าง TextStyle ของฟอนต์หนึ่งตระกูลตามน้ำหนัก
typedef ObsidianFont = TextStyle Function(FontWeight weight);

/// ตัวอักษร 3 ชุดของธีม — ผูกกับ ThemeData ผ่าน extension
///
/// 🔴 วิดเจ็ตห้ามเรียก GoogleFonts เอง ให้อ่านจากตรงนี้แทน
/// เพราะแค่ "สร้าง" TextStyle ของ GoogleFonts ในเทสต์ก็สั่งโหลดฟอนต์ผ่านเน็ตแล้ว
/// (ดู test/support/test_theme.dart) — ในเทสต์ที่ไม่ได้แนบ extension นี้
/// [ObsidianStyle.of] จะคืนสไตล์ธรรมดาให้แทน
///
/// 🔴 ห้าม `GoogleFonts.xxx().copyWith(fontWeight: ...)` — ชื่อฟอนต์ยังเป็นไฟล์น้ำหนักเดิม
///    (เช่น IBMPlexSansThai_regular) เครื่องจะ "ทำตัวหนาปลอม" จากตัวปกติแทนไฟล์ SemiBold จริง
///    → ใช้ [ui] / [number] / [mono] ที่เลือกไฟล์ตามน้ำหนักให้เอง
@immutable
class ObsidianStyle extends ThemeExtension<ObsidianStyle> {
  /// IBM Plex Sans Thai — ตัวหนังสือทั่วไป
  final ObsidianFont uiFont;

  /// Space Grotesk — ตัวเลขยอดเงิน
  final ObsidianFont numberFont;

  /// IBM Plex Mono — ที่อยู่กระเป๋า / แฮช
  final ObsidianFont monoFont;

  const ObsidianStyle({
    required this.uiFont,
    required this.numberFont,
    required this.monoFont,
  });

  static TextStyle _plain(FontWeight w) => TextStyle(fontWeight: w);
  static TextStyle _plainMono(FontWeight w) => TextStyle(fontFamily: 'monospace', fontWeight: w);

  static const fallback = ObsidianStyle(uiFont: _plain, numberFont: _plain, monoFont: _plainMono);

  static ObsidianStyle of(BuildContext context) =>
      Theme.of(context).extension<ObsidianStyle>() ?? fallback;

  static TextStyle _make(
    ObsidianFont font, {
    double? fontSize,
    FontWeight fontWeight = FontWeight.w400,
    Color? color,
    double? height,
    double? letterSpacing,
    List<Shadow>? shadows,
  }) =>
      font(fontWeight).copyWith(
        fontSize: fontSize,
        color: color,
        height: height,
        letterSpacing: letterSpacing,
        shadows: shadows,
      );

  TextStyle ui({
    double? fontSize,
    FontWeight fontWeight = FontWeight.w400,
    Color? color,
    double? height,
    double? letterSpacing,
    List<Shadow>? shadows,
  }) =>
      _make(uiFont,
          fontSize: fontSize, fontWeight: fontWeight, color: color, height: height, letterSpacing: letterSpacing, shadows: shadows);

  TextStyle number({
    double? fontSize,
    FontWeight fontWeight = FontWeight.w600,
    Color? color,
    double? height,
    double? letterSpacing,
    List<Shadow>? shadows,
  }) =>
      _make(numberFont,
          fontSize: fontSize, fontWeight: fontWeight, color: color, height: height, letterSpacing: letterSpacing, shadows: shadows);

  TextStyle mono({
    double? fontSize,
    FontWeight fontWeight = FontWeight.w500,
    Color? color,
    double? height,
    double? letterSpacing,
    List<Shadow>? shadows,
  }) =>
      _make(monoFont,
          fontSize: fontSize, fontWeight: fontWeight, color: color, height: height, letterSpacing: letterSpacing, shadows: shadows);

  @override
  ObsidianStyle copyWith({ObsidianFont? uiFont, ObsidianFont? numberFont, ObsidianFont? monoFont}) =>
      ObsidianStyle(
        uiFont: uiFont ?? this.uiFont,
        numberFont: numberFont ?? this.numberFont,
        monoFont: monoFont ?? this.monoFont,
      );

  @override
  ObsidianStyle lerp(ThemeExtension<ObsidianStyle>? other, double t) {
    if (other is! ObsidianStyle) return this;
    return t < 0.5 ? this : other;
  }
}
