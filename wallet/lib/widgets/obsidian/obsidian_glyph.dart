/// TPIX Wallet — ไอคอนเส้นบางของธีม Obsidian (ลอกจาก SVG ใน mock ตรง ๆ)
///
/// mock ใช้ไอคอนเส้น viewBox 24 · stroke-linecap/linejoin = round
/// Material Icons หน้าตาคนละแบบ (หนา/มนต่างกัน) → วาดเองให้ตรง mock
///
/// Developed by Xman Studio
library;

import 'package:flutter/widgets.dart';

enum ObsidianGlyph {
  /// ย้อนกลับ `M15 18l-6-6 6-6`
  back,

  /// ปิด (กากบาท)
  close,

  /// ไฟฉาย
  flash,

  /// วางจากคลิปบอร์ด
  paste,

  /// คัดลอก
  copy,

  /// ลูกศรขวา (ปุ่มหลัก)
  arrowRight,

  /// ลูกศรลง (ตัวเลือก)
  chevronDown,

  /// กุญแจเล็ก (คำใบ้ใต้ปุ่มส่ง)
  lock,

  /// ลบตัวเลข (แป้น PIN)
  backspace,

  /// เครื่องหมายถูก
  check,
}

class ObsidianGlyphIcon extends StatelessWidget {
  final ObsidianGlyph glyph;
  final double size;
  final Color color;
  final double strokeWidth;

  const ObsidianGlyphIcon(
    this.glyph, {
    super.key,
    this.size = 20,
    this.color = const Color(0xFFF2F3F5),
    this.strokeWidth = 2,
  });

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: SizedBox.square(
          dimension: size,
          child: CustomPaint(painter: _GlyphPainter(glyph, color, strokeWidth)),
        ),
      );
}

class _GlyphPainter extends CustomPainter {
  final ObsidianGlyph glyph;
  final Color color;
  final double strokeWidth;

  const _GlyphPainter(this.glyph, this.color, this.strokeWidth);

  /// สี่เหลี่ยมมุมมน (เหมือน `<rect rx>` ของ SVG)
  static Path _rect(double x, double y, double w, double h, double r) =>
      Path()..addRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, y, w, h), Radius.circular(r)));

  static Path pathFor(ObsidianGlyph g) {
    switch (g) {
      case ObsidianGlyph.back:
        return Path()
          ..moveTo(15, 18)
          ..lineTo(9, 12)
          ..lineTo(15, 6);
      case ObsidianGlyph.close:
        return Path()
          ..moveTo(6, 6)
          ..lineTo(18, 18)
          ..moveTo(18, 6)
          ..lineTo(6, 18);
      case ObsidianGlyph.flash:
        return Path()
          ..moveTo(13, 2)
          ..lineTo(4, 14)
          ..lineTo(11, 14)
          ..lineTo(10, 22)
          ..lineTo(19, 10)
          ..lineTo(12, 10)
          ..close();
      case ObsidianGlyph.paste:
        return Path()
          ..addPath(_rect(8, 3, 8, 4, 1), Offset.zero)
          ..moveTo(16, 5)
          ..lineTo(18, 5)
          ..arcToPoint(const Offset(19, 6), radius: const Radius.circular(1))
          ..lineTo(19, 20)
          ..arcToPoint(const Offset(18, 21), radius: const Radius.circular(1))
          ..lineTo(6, 21)
          ..arcToPoint(const Offset(5, 20), radius: const Radius.circular(1))
          ..lineTo(5, 6)
          ..arcToPoint(const Offset(6, 5), radius: const Radius.circular(1))
          ..lineTo(8, 5);
      case ObsidianGlyph.copy:
        return Path()
          ..addPath(_rect(9, 9, 11, 11, 2), Offset.zero)
          ..moveTo(5, 15)
          ..lineTo(4, 15)
          ..arcToPoint(const Offset(3, 14), radius: const Radius.circular(1))
          ..lineTo(3, 4)
          ..arcToPoint(const Offset(4, 3), radius: const Radius.circular(1))
          ..lineTo(14, 3)
          ..arcToPoint(const Offset(15, 4), radius: const Radius.circular(1))
          ..lineTo(15, 5);
      case ObsidianGlyph.arrowRight:
        return Path()
          ..moveTo(5, 12)
          ..lineTo(19, 12)
          ..moveTo(13, 6)
          ..lineTo(19, 12)
          ..lineTo(13, 18);
      case ObsidianGlyph.chevronDown:
        return Path()
          ..moveTo(6, 9)
          ..lineTo(12, 15)
          ..lineTo(18, 9);
      case ObsidianGlyph.lock:
        return Path()
          ..addPath(_rect(5, 11, 14, 10, 2), Offset.zero)
          ..moveTo(8, 11)
          ..lineTo(8, 7)
          ..arcToPoint(const Offset(16, 7), radius: const Radius.circular(4))
          ..lineTo(16, 11);
      case ObsidianGlyph.backspace:
        return Path()
          ..moveTo(21, 5)
          ..lineTo(9, 5)
          ..lineTo(3, 12)
          ..lineTo(9, 19)
          ..lineTo(21, 19)
          ..arcToPoint(const Offset(22, 18), radius: const Radius.circular(1), clockwise: false)
          ..lineTo(22, 6)
          ..arcToPoint(const Offset(21, 5), radius: const Radius.circular(1), clockwise: false)
          ..close()
          ..moveTo(12, 9)
          ..lineTo(18, 15)
          ..moveTo(18, 9)
          ..lineTo(12, 15);
      case ObsidianGlyph.check:
        return Path()
          ..moveTo(5, 12)
          ..lineTo(10, 17)
          ..lineTo(20, 7);
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 24;
    canvas.scale(k);
    canvas.drawPath(
      pathFor(glyph),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color
        ..isAntiAlias = true,
    );
  }

  @override
  bool shouldRepaint(_GlyphPainter old) =>
      old.glyph != glyph || old.color != color || old.strokeWidth != strokeWidth;
}
