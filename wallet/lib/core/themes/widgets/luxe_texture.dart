/// TPIX Wallet — ลายพื้นผิวระดับพรีเมียม (วาดด้วยโค้ดล้วน)
///
/// ทำไมไม่ใช้ไฟล์ภาพ:
///   ของเดิมใช้ `liquid_bg.jpg` ขนาด 720×1280 แต่ปูเต็มจอด้วย BoxFit.cover
///   บน iPhone 13 Pro (1170×2532) = ยืด 1.63 เท่า → เบลอทั้งหน้าจอ
///   และยิ่งจอละเอียดกว่านี้ยิ่งเบลอหนัก แก้ด้วยการทำไฟล์ใหญ่ขึ้นก็แค่เลื่อนปัญหา
///   ลายที่ "วาดด้วยโค้ด" คมที่ทุกความละเอียดโดยธรรมชาติ และไม่กินพื้นที่ใน APK เลย
///
/// ทำไมเลือกลายนี้:
///   guilloché คือลายเส้นสานที่อยู่บนธนบัตร พาสปอร์ต และบัตรเครดิตระดับพรีเมียม
///   มันคือภาษาภาพของ "เงินที่เชื่อถือได้" ตรงตัว — เหมาะกับกระเป๋าคริปโตที่สุด
///   ใช้ opacity ต่ำมากโดยตั้งใจ ให้เป็น "เนื้อผิว" ที่รู้สึกได้ ไม่ใช่ "ลวดลาย" ที่แย่งสายตา
///
/// Developed by Xman Studio

import 'dart:math' as math;
import 'package:flutter/material.dart';

/// ความเข้มของลาย — การ์ดเล็กต้องจางกว่าพื้นเต็มจอ ไม่งั้นแย่งเนื้อหา
enum LuxeTextureScale { screen, card }

class LuxeTexture extends StatelessWidget {
  final bool isDark;
  final Color lineColor;
  final LuxeTextureScale scale;

  const LuxeTexture({
    super.key,
    required this.isDark,
    required this.lineColor,
    this.scale = LuxeTextureScale.screen,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      // ลายนี้นิ่ง ไม่ขยับ → RepaintBoundary กันไม่ให้วาดใหม่ตอน blob ข้างบนขยับ
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _LuxePainter(
            isDark: isDark,
            lineColor: lineColor,
            scale: scale,
          ),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _LuxePainter extends CustomPainter {
  final bool isDark;
  final Color lineColor;
  final LuxeTextureScale scale;

  _LuxePainter({
    required this.isDark,
    required this.lineColor,
    required this.scale,
  });

  bool get _isCard => scale == LuxeTextureScale.card;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    canvas.clipRect(Offset.zero & size);

    _paintHairlineMesh(canvas, size);
    _paintGuilloche(canvas, size);
    if (!_isCard) _paintVignette(canvas, size);
  }

  /// ตาข่ายเส้นขนแมว — ให้ผิวมี "เนื้อ" แบบกระดาษพิมพ์นูน ไม่ใช่พื้นเรียบตาย
  /// เส้นบางกว่า 1 พิกเซลจริงไม่ได้ จึงใช้ความจางแทนความบาง
  void _paintHairlineMesh(Canvas canvas, Size size) {
    final gap = _isCard ? 7.0 : 11.0;
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6
      ..color = lineColor.withValues(alpha: (isDark ? 0.055 : 0.045) * (_isCard ? 0.7 : 1.0));

    // เอียง 45 องศา — ตาข่ายแนวตั้ง/นอนตรง ๆ จะไปตีกับขอบการ์ดจนดูเป็นตาราง
    final diag = size.width + size.height;
    for (double d = -size.height; d < diag; d += gap) {
      canvas.drawLine(Offset(d, 0), Offset(d + size.height, size.height), p);
    }
  }

  /// ลาย guilloché — เส้นสานแบบบนธนบัตร
  /// สร้างจากสมการ hypotrochoid (spirograph) ซึ่งได้เส้นสานกันเองอย่างเป็นระเบียบ
  void _paintGuilloche(Canvas canvas, Size size) {
    final rosettes = _isCard
        ? [
            _Rosette(Offset(size.width * 0.86, size.height * 0.24),
                math.min(size.width, size.height) * 0.62, 7, 4, 0.35),
          ]
        : [
            _Rosette(Offset(size.width * 0.18, size.height * 0.20),
                size.width * 0.62, 9, 4, 0.0),
            _Rosette(Offset(size.width * 0.88, size.height * 0.46),
                size.width * 0.70, 11, 5, 0.6),
            _Rosette(Offset(size.width * 0.34, size.height * 0.84),
                size.width * 0.58, 7, 3, 1.2),
          ];

    final base = (isDark ? 0.135 : 0.105) * (_isCard ? 0.55 : 1.0);

    for (final r in rosettes) {
      // วาดซ้อนหลายวง เยื้องกันทีละนิด = ได้ "ความสาน" แบบลายบนธนบัตร
      for (int layer = 0; layer < 3; layer++) {
        final paint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.9
          ..color = lineColor.withValues(alpha: base * (1 - layer * 0.22));
        canvas.drawPath(r.build(layer * 0.06), paint);
      }
    }
  }

  /// ขอบมืดอ่อน ๆ — ดึงสายตาเข้ากลางจอ ทำให้เนื้อหาเด่นขึ้นโดยไม่ต้องเพิ่มคอนทราสต์
  void _paintVignette(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: Alignment.center,
          radius: 0.95,
          colors: [
            Colors.transparent,
            Colors.black.withValues(alpha: isDark ? 0.26 : 0.05),
          ],
          stops: const [0.62, 1.0],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_LuxePainter old) =>
      old.isDark != isDark ||
      old.lineColor != lineColor ||
      old.scale != scale;
}

/// วงลาย guilloché หนึ่งวง (hypotrochoid)
///   x = (R-r)·cos t + d·cos((R-r)/r · t)
///   y = (R-r)·sin t − d·sin((R-r)/r · t)
class _Rosette {
  final Offset center;
  final double radius;

  /// อัตราส่วน R:r — ตัวกำหนดจำนวนกลีบ
  final int bigTeeth;
  final int smallTeeth;

  /// เฟสเริ่มต้น ทำให้แต่ละวงไม่ทับกันเป๊ะ
  final double phase;

  const _Rosette(
      this.center, this.radius, this.bigTeeth, this.smallTeeth, this.phase);

  Path build(double offset) {
    final path = Path();
    final R = radius;
    final r = radius * smallTeeth / bigTeeth;
    final d = radius * (0.42 + offset);
    final k = (R - r) / r;

    // วนจนกลีบบรรจบพอดี = R/r รอบ (ตัดด้วย gcd ให้ไม่วนซ้ำเปล่า)
    final turns = smallTeeth ~/ _gcd(bigTeeth, smallTeeth);
    const steps = 900;
    final total = 2 * math.pi * turns;

    for (int i = 0; i <= steps; i++) {
      final t = total * i / steps + phase;
      final x = center.dx + (R - r) * math.cos(t) + d * math.cos(k * t);
      final y = center.dy + (R - r) * math.sin(t) - d * math.sin(k * t);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    return path;
  }

  static int _gcd(int a, int b) => b == 0 ? a : _gcd(b, a % b);
}
