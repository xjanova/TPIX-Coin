/// TPIX Wallet — กรอบเล็งสแกน QR ธีม Obsidian (ตาม A-Scan.dc.html)
///
/// ชั้นบนภาพกล้อง:
///   - ม่านมืด .66 ทั้งจอ เว้นช่องใส 250x250 มน 28 (กลางช่องอยู่ ~42% ของความสูงจอ)
///   - มุมกรอบ 4 มุมไล่สี ฟ้า/ม่วง/ส้ม/ม่วงอ่อน เรืองแสง + หายใจ 1→1.035 ทุก 2.4 วิ
///   - ตารางจาง ๆ ในช่อง (กะพริบ .18↔.38) + เลเซอร์ไล่สีกวาดขึ้นลง 2.4 วิ
///   - สแกนเจอ ([lock] ไม่ null): มุมกรอบ "ดีด" ไปครอบโค้ด (ย้าย/ย่อ/หมุนตามมุมโค้ดจริง)
///     แล้วเปลี่ยนเป็นเขียว + วงกระเพื่อม 2 รอบ + เครื่องหมายถูกเด้งขึ้น
///
/// ไม่รับการแตะ (IgnorePointer) — ปุ่มต่าง ๆ วางทับอีกชั้น
///
/// Developed by Xman Studio
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/themes/obsidian_tokens.dart';
import 'obsidian_glyph.dart';
import 'obsidian_loop.dart';

/// ตำแหน่งที่มุมกรอบจะดีดไปครอบโค้ด (พิกัดของจอสแกน)
@immutable
class ScanSnap {
  final Offset center;

  /// เทียบกับขนาดช่องเล็ง (1 = เท่าเดิม)
  final double scale;

  /// เรเดียน (บวก = ตามเข็ม)
  final double angle;

  const ScanSnap({required this.center, required this.scale, required this.angle});

  @override
  bool operator ==(Object other) =>
      other is ScanSnap && other.center == center && other.scale == scale && other.angle == angle;

  @override
  int get hashCode => Object.hash(center, scale, angle);

  @override
  String toString() => 'ScanSnap($center, x$scale, ${angle.toStringAsFixed(3)}rad)';
}

abstract final class ScanGeometry {
  static const double windowSize = 250;
  static const double windowRadius = 28;

  /// กลางช่องเล็งอยู่ที่ 357/844 ของความสูงจอใน mock
  static const double centerYFactor = 357 / 844;

  /// ช่องเล็งบนจอขนาด [view]
  static Rect windowFor(Size view) => Rect.fromCenter(
        center: Offset(view.width / 2, view.height * centerYFactor),
        width: windowSize,
        height: windowSize,
      );

  /// แปลงมุม 4 มุมของโค้ด (พิกัดภาพกล้อง [imageSize]) → ตำแหน่งดีดของกรอบบนจอ [view]
  ///
  /// คณิตเดียวกับ BarcodePainter ของ mobile_scanner (ภาพกล้องจัดแบบ [fit] เต็มจอ)
  /// ข้อมูลไม่พอ/ผลไม่สมเหตุผล (ขนาดเพี้ยน/อยู่นอกจอ) → ย่อลงตรงกลางช่องเล็งแทน
  /// ไม่เคย throw — เป็นแค่แอนิเมชัน ห้ามทำให้การสแกนพัง
  static ScanSnap snapFor({
    required List<Offset> corners,
    required Size imageSize,
    required Size view,
    BoxFit fit = BoxFit.cover,
    bool landscape = false,
    double margin = 14,
  }) {
    final window = windowFor(view);
    final fallback = ScanSnap(center: window.center, scale: 0.8, angle: 0);
    if (corners.length < 4 || imageSize.isEmpty || view.isEmpty) return fallback;

    final img = landscape ? imageSize.flipped : imageSize;
    final wr = view.width / img.width;
    final hr = view.height / img.height;
    final double rx, ry;
    switch (fit) {
      case BoxFit.fill:
        rx = wr;
        ry = hr;
      case BoxFit.contain:
        rx = ry = math.min(wr, hr);
      case BoxFit.fitWidth:
        rx = ry = wr;
      case BoxFit.fitHeight:
        rx = ry = hr;
      case BoxFit.none:
        rx = ry = 1;
      case BoxFit.scaleDown:
        rx = ry = math.min(1.0, math.min(wr, hr));
      case BoxFit.cover:
        rx = ry = math.max(wr, hr);
    }
    final padX = (img.width * rx - view.width) / 2;
    final padY = (img.height * ry - view.height) / 2;
    final pts = [for (final c in corners.take(4)) Offset(c.dx * rx - padX, c.dy * ry - padY)];

    var cx = 0.0, cy = 0.0;
    for (final p in pts) {
      cx += p.dx / 4;
      cy += p.dy / 4;
    }
    var side = 0.0;
    for (var i = 0; i < 4; i++) {
      side += (pts[(i + 1) % 4] - pts[i]).distance / 4;
    }
    if (!side.isFinite || side < 24 || side > view.shortestSide * 1.6) return fallback;
    final centre = Offset(cx, cy);
    if (!(Offset.zero & view).contains(centre)) return fallback;

    // มุมของขอบบน — กรอบสมมาตร 4 ทาง จึงพับให้อยู่ใน ±45°
    final top = pts[1] - pts[0];
    var a = math.atan2(top.dy, top.dx);
    const q = math.pi / 2;
    a = a - q * (a / q).roundToDouble();

    final scale = ((side + 2 * margin) / windowSize).clamp(0.45, 1.15);
    // ไม่ให้กรอบหลุดขอบจอ
    final half = windowSize * scale / 2;
    final safe = Rect.fromLTRB(half, half, view.width - half, view.height - half);
    final clamped = safe.isEmpty
        ? window.center
        : Offset(centre.dx.clamp(safe.left, safe.right), centre.dy.clamp(safe.top, safe.bottom));
    return ScanSnap(center: clamped, scale: scale, angle: a);
  }
}

class ScanViewfinder extends StatefulWidget {
  /// null = กำลังสแกน · ไม่ null = สแกนเจอแล้ว (ดีดไปครอบโค้ด)
  final ScanSnap? lock;

  const ScanViewfinder({super.key, this.lock});

  /// สีมุมกรอบตอนสแกน (บนซ้าย / บนขวา / ล่างขวา / ล่างซ้าย)
  static const cornerColors = [
    ObsidianColors.cyan,
    ObsidianColors.violet,
    ObsidianColors.orange,
    Color(0xFFA78BFA),
  ];

  @override
  State<ScanViewfinder> createState() => _ScanViewfinderState();
}

class _ScanViewfinderState extends State<ScanViewfinder> with TickerProviderStateMixin {
  /// ดีดกรอบ 450ms (เส้นโค้งเกินเป้านิด ๆ แบบ mock)
  late final AnimationController _snap =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 450));

  /// วงกระเพื่อม 0.9 วิ × 2 + เครื่องหมายถูก 0.5 วิ
  late final AnimationController _fx =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1800));

  static const _snapCurve = Cubic(0.2, 0.9, 0.25, 1.25);
  static const _popCurve = Cubic(0.2, 0.9, 0.3, 1.3);

  @override
  void didUpdateWidget(ScanViewfinder old) {
    super.didUpdateWidget(old);
    if (old.lock == null && widget.lock != null) {
      final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
      if (reduce) {
        _snap.value = 1;
        _fx.value = 1;
      } else {
        _snap.forward(from: 0);
        _fx.forward(from: 0);
      }
    } else if (widget.lock == null && old.lock != null) {
      _snap.value = 0;
      _fx.value = 0;
    }
  }

  @override
  void dispose() {
    _snap.dispose();
    _fx.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: LayoutBuilder(builder: (context, box) {
        final view = box.biggest;
        final window = ScanGeometry.windowFor(view);
        final lock = widget.lock;
        final scanning = lock == null;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            // ม่านมืดรอบช่องเล็ง
            Positioned.fill(child: CustomPaint(painter: _DimPainter(window))),

            // วงกระเพื่อมเขียวตอนเจอ (ที่ช่องเล็ง ตาม mock)
            if (lock != null)
              AnimatedBuilder(
                animation: _fx,
                builder: (context, _) {
                  final ms = _fx.value * 1800;
                  if (ms >= 1800 || _fx.value == 0) return const SizedBox.shrink();
                  final t = Curves.easeOut.transform((ms % 900) / 900);
                  return Positioned.fromRect(
                    rect: window,
                    child: Opacity(
                      opacity: (0.9 * (1 - t)).clamp(0.0, 1.0),
                      child: Transform.scale(
                        scale: 0.75 + 1.15 * t,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(ScanGeometry.windowRadius),
                            border: Border.all(color: ObsidianColors.success, width: 3),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),

            // มุมกรอบ + ตาราง + เลเซอร์
            Positioned.fromRect(
              rect: window,
              child: AnimatedBuilder(
                animation: _snap,
                builder: (context, child) {
                  if (lock == null) return child!;
                  final t = _snapCurve.transform(_snap.value);
                  final move = (lock.center - window.center) * t;
                  final scale = 1 + (lock.scale - 1) * t;
                  return Transform.translate(
                    offset: move,
                    child: Transform.rotate(
                      angle: lock.angle * t,
                      child: Transform.scale(scale: scale, child: child),
                    ),
                  );
                },
                child: ObsidianLoop(
                  period: const Duration(milliseconds: 1200),
                  reverse: true,
                  enabled: scanning,
                  builder: (context, b, child) => Transform.scale(
                    scale: scanning ? 1 + 0.035 * Curves.easeInOut.transform(b) : 1,
                    child: child,
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (scanning) ...[
                        ObsidianLoop(
                          period: const Duration(milliseconds: 1200),
                          reverse: true,
                          restValue: 0.5,
                          builder: (context, g, _) => CustomPaint(
                            painter: _GridPainter(0.18 + 0.2 * Curves.easeInOut.transform(g)),
                          ),
                        ),
                        ObsidianLoop(
                          period: const Duration(milliseconds: 1200),
                          reverse: true,
                          restValue: 0.5,
                          builder: (context, l, _) => CustomPaint(
                            painter: _LaserPainter(0.04 + 0.89 * Curves.easeInOut.transform(l)),
                          ),
                        ),
                      ],
                      TweenAnimationBuilder<double>(
                        tween: Tween(end: scanning ? 0 : 1),
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.ease,
                        builder: (context, g, _) => CustomPaint(
                          painter: _BracketPainter([
                            for (final c in ScanViewfinder.cornerColors) Color.lerp(c, ObsidianColors.success, g)!,
                          ]),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // เครื่องหมายถูกเด้งขึ้นกลางโค้ด
            if (lock != null)
              Positioned(
                left: lock.center.dx - 32,
                top: lock.center.dy - 32,
                width: 64,
                height: 64,
                child: AnimatedBuilder(
                  animation: _fx,
                  builder: (context, child) {
                    final k = (_fx.value * 1800 / 500).clamp(0.0, 1.0);
                    final s = _popCurve.transform(k);
                    return Opacity(
                      opacity: (k / 0.6).clamp(0.0, 1.0),
                      child: Transform.scale(scale: s, child: child),
                    );
                  },
                  child: const _CheckBadge(),
                ),
              ),
          ],
        );
      }),
    );
  }
}

class _CheckBadge extends StatelessWidget {
  const _CheckBadge();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(
          center: Alignment(-0.3, -0.4),
          radius: 0.9,
          colors: [ObsidianColors.successSoft, Color(0xFF059669)],
        ),
        boxShadow: [
          const BoxShadow(color: Color(0x4034D399), spreadRadius: 6),
          const CssShadow(0, 14, 30, -6, Color(0xE6059669)).toBoxShadow(),
        ],
      ),
      child: const Center(
        child: ObsidianGlyphIcon(ObsidianGlyph.check, size: 34, color: Colors.white, strokeWidth: 3),
      ),
    );
  }
}

class _DimPainter extends CustomPainter {
  final Rect window;

  const _DimPainter(this.window);

  @override
  void paint(Canvas canvas, Size size) {
    final p = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRRect(RRect.fromRectAndRadius(window, const Radius.circular(ScanGeometry.windowRadius)));
    canvas.drawPath(p, Paint()..color = const Color(0xA8040508)); // rgba(4,5,8,.66)
  }

  @override
  bool shouldRepaint(_DimPainter old) => old.window != window;
}

/// มุม 4 มุม: เส้น 5px ยาว 50 มุมโค้ง 26 + เรืองแสงสีเดียวกัน 8px
class _BracketPainter extends CustomPainter {
  /// บนซ้าย / บนขวา / ล่างขวา / ล่างซ้าย
  final List<Color> colors;

  const _BracketPainter(this.colors);

  static const _len = 50.0;
  static const _w = 5.0;
  static const _r = 26.0;

  static Path _topLeft() {
    const h = _w / 2;
    return Path()
      ..moveTo(h, _len)
      ..lineTo(h, _r)
      ..arcToPoint(const Offset(_r, h), radius: const Radius.circular(_r - h))
      ..lineTo(_len, h);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final base = _topLeft();
    for (var i = 0; i < 4; i++) {
      canvas.save();
      // หมุนมุมบนซ้ายไปเป็นมุมอื่นรอบกลางกล่อง
      canvas.translate(size.width / 2, size.height / 2);
      canvas.rotate(i * math.pi / 2);
      canvas.translate(-size.width / 2, -size.height / 2);
      final color = colors[i];
      canvas.drawPath(
        base,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = _w
          ..color = color
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
      canvas.drawPath(
        base,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = _w
          ..color = color,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_BracketPainter old) {
    for (var i = 0; i < 4; i++) {
      if (old.colors[i] != colors[i]) return true;
    }
    return false;
  }
}

/// ตารางเส้น 22px (แนวนอนม่วง / แนวตั้งฟ้า) จางออกจากกลางเป็นวงกลม
class _GridPainter extends CustomPainter {
  final double opacity;

  const _GridPainter(this.opacity);

  @override
  void paint(Canvas canvas, Size size) {
    final r = (Offset.zero & size).deflate(14);
    final rr = RRect.fromRectAndRadius(r, const Radius.circular(18));
    canvas.saveLayer(r, Paint());
    canvas.clipRRect(rr);
    final h = Paint()..color = ObsidianColors.violet.withValues(alpha: 0.5 * opacity);
    final v = Paint()..color = ObsidianColors.cyan.withValues(alpha: 0.5 * opacity);
    for (var y = r.top; y < r.bottom; y += 22) {
      canvas.drawRect(Rect.fromLTWH(r.left, y, r.width, 1), h);
    }
    for (var x = r.left; x < r.right; x += 22) {
      canvas.drawRect(Rect.fromLTWH(x, r.top, 1, r.height), v);
    }
    // mask-image: radial-gradient(closest-side, #000, transparent)
    canvas.drawRect(
      r,
      Paint()
        ..blendMode = BlendMode.dstIn
        ..shader = RadialGradient(colors: const [Color(0xFF000000), Color(0x00000000)])
            .createShader(Rect.fromCircle(center: r.center, radius: r.shortestSide / 2)),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GridPainter old) => old.opacity != opacity;
}

/// เลเซอร์ไล่สี ฟ้า → ม่วง → ส้ม สูง 3px + เรืองม่วง + หางแสงฟ้าด้านบน
class _LaserPainter extends CustomPainter {
  /// ตำแหน่งบนสุดของเส้น เป็นสัดส่วนของความสูงกล่อง (4% ↔ 93%)
  final double top;

  const _LaserPainter(this.top);

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height * top;
    final bar = Rect.fromLTWH(10, y, size.width - 20, 3);
    final rr = RRect.fromRectAndRadius(bar, const Radius.circular(2));
    // 0 -26px 36px -10px rgba(34,211,238,.35) — หางแสงด้านบน
    canvas.drawRRect(
      RRect.fromRectAndRadius(bar.shift(const Offset(0, -26)).inflate(-10), const Radius.circular(2)),
      Paint()
        ..color = const Color(0x5922D3EE)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18),
    );
    // 0 0 18px 4px rgba(139,92,246,.65)
    canvas.drawRRect(
      rr.inflate(4),
      Paint()
        ..color = const Color(0xA68B5CF6)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9),
    );
    canvas.drawRRect(
      rr,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0x0022D3EE), ObsidianColors.cyan, ObsidianColors.violet, ObsidianColors.orange, Color(0x00FB923C)],
          stops: [0, 0.2, 0.5, 0.8, 1],
        ).createShader(bar),
    );
  }

  @override
  bool shouldRepaint(_LaserPainter old) => old.top != top;
}
