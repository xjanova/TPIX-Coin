/// TPIX Wallet — แผงกระจกขอบนูนของธีม Obsidian
///
/// ของใน mock ทุกชิ้นสร้างจากสูตรเดียวกัน:
///   พื้นไล่สี + `inset 0 1px 0` (ไฮไลต์ขาวขอบบน) + `inset 0 -1px 0` (เงาดำขอบล่าง)
///   + เงานอกแบบ CSS (วาดเฉพาะ "นอก" แผง — ใต้แผงโปร่งต้องไม่มีเงาดำทะลุขึ้นมา)
///
/// BoxDecoration ทำ inset shadow ไม่ได้ และ BoxShadow วาดเงาใต้แผงด้วย
/// (แผงโปร่ง 6% เลยดูหม่นกว่า mock) → วาดเองด้วย [ObsidianSurfacePainter]
///
/// Developed by Xman Studio
library;

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

import '../../core/themes/obsidian_tokens.dart';

/// สเปกพื้นผิวหนึ่งชิ้น (ตรงกับ inline style ของ mock)
@immutable
class ObsidianSurface {
  final double radius;
  final Gradient? gradient;
  final Color? color;

  /// เงานอก (CSS box-shadow ไม่มี inset)
  final List<CssShadow> shadows;

  /// `inset 0 Npx 0 color` — ไฮไลต์ขอบบน
  final Color? topHighlight;
  final double topHighlightWidth;

  /// `inset 0 -Npx 0 color` — เงาขอบล่าง
  final Color? bottomShade;
  final double bottomShadeWidth;

  /// `inset 0 0 0 Npx color` — วงขอบด้านใน
  final Color? ring;
  final double ringWidth;

  /// `inset x y blur color` — เงาจมด้านใน (ช่องกรอก)
  final List<CssShadow> innerShadows;

  const ObsidianSurface({
    required this.radius,
    this.gradient,
    this.color,
    this.shadows = const [],
    this.topHighlight,
    this.topHighlightWidth = 1,
    this.bottomShade,
    this.bottomShadeWidth = 1,
    this.ring,
    this.ringWidth = 1,
    this.innerShadows = const [],
  });

  ObsidianSurface copyWith({
    double? radius,
    Color? ring,
    double? ringWidth,
    List<CssShadow>? shadows,
  }) =>
      ObsidianSurface(
        radius: radius ?? this.radius,
        gradient: gradient,
        color: color,
        shadows: shadows ?? this.shadows,
        topHighlight: topHighlight,
        topHighlightWidth: topHighlightWidth,
        bottomShade: bottomShade,
        bottomShadeWidth: bottomShadeWidth,
        ring: ring ?? this.ring,
        ringWidth: ringWidth ?? this.ringWidth,
        innerShadows: innerShadows,
      );

  @override
  bool operator ==(Object other) =>
      other is ObsidianSurface &&
      other.radius == radius &&
      other.gradient == gradient &&
      other.color == color &&
      listEquals(other.shadows, shadows) &&
      other.topHighlight == topHighlight &&
      other.topHighlightWidth == topHighlightWidth &&
      other.bottomShade == bottomShade &&
      other.bottomShadeWidth == bottomShadeWidth &&
      other.ring == ring &&
      other.ringWidth == ringWidth &&
      listEquals(other.innerShadows, innerShadows);

  @override
  int get hashCode => Object.hash(radius, gradient, color, Object.hashAll(shadows), topHighlight,
      topHighlightWidth, bottomShade, bottomShadeWidth, ring, ringWidth, Object.hashAll(innerShadows));

  // ── สูตรสำเร็จจาก mock ──

  /// แผงเนื้อหา (รายการเหรียญ / สรุปค่าธรรมเนียม) — ขาว 6%→2%
  static const panel = ObsidianSurface(
    radius: 22,
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0x0FFFFFFF), Color(0x05FFFFFF)],
    ),
    topHighlight: Color(0x1AFFFFFF), // .10
    bottomShade: Color(0x80000000), // .5
    shadows: [CssShadow(0, 20, 40, -24, Color(0xE6000000))],
  );

  /// ปุ่มกระจกนูน (ปุ่มหัวหน้า 46x46 / ตัวเลือกเหรียญ) — ขาว 10%→3%
  static const raised = ObsidianSurface(
    radius: 16,
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0x1AFFFFFF), Color(0x08FFFFFF)],
    ),
    topHighlight: Color(0x2EFFFFFF), // .18
    bottomShade: Color(0x80000000),
    shadows: [CssShadow(0, 10, 24, -10, Color(0xE6000000))],
  );

  /// ปุ่มรองสีเข้มทึบ (25% / 50% / วาง / ปุ่มรอง)
  static const dark = ObsidianSurface(
    radius: 13,
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [ObsidianColors.darkTop, ObsidianColors.darkBottom],
    ),
    topHighlight: Color(0x1FFFFFFF), // .12
    bottomShade: Color(0x99000000), // .6
    shadows: [CssShadow(0, 8, 16, -8, Color(0xE6000000))],
  );

  /// ช่องกรอกแบบยุบลง
  static const field = ObsidianSurface(
    radius: 18,
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFF08090D), Color(0xFF11131A)],
    ),
    innerShadows: [CssShadow(0, 3, 8, 0, Color(0xBF000000))],
  );

  /// ปุ่มหลักสีขาวนูน
  static const primaryButton = ObsidianSurface(
    radius: 19,
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFFFFFFFF), Color(0xFFD9DCE3)],
    ),
    topHighlight: Color(0xFFFFFFFF),
    bottomShade: Color(0x2E000000), // .18
    bottomShadeWidth: 2,
    shadows: [
      CssShadow(0, 18, 34, -12, Color(0xA68B5CF6)), // violet .65
      CssShadow(0, 10, 20, -10, Color(0xE6000000)),
    ],
  );
}

/// วาด [ObsidianSurface] ตามความหมายของ CSS
class ObsidianSurfacePainter extends CustomPainter {
  final ObsidianSurface s;

  const ObsidianSurfacePainter(this.s);

  static RRect _spread(RRect r, double d) {
    if (d == 0) return r;
    final rect = r.outerRect.inflate(d);
    final rad = (r.tlRadiusX + d).clamp(0.0, double.infinity);
    return RRect.fromRectAndRadius(
      rect.width <= 0 || rect.height <= 0 ? Rect.fromCenter(center: rect.center, width: 0, height: 0) : rect,
      Radius.circular(rad),
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rr = RRect.fromRectAndRadius(rect, Radius.circular(s.radius));

    // 1) เงานอก — ตัดส่วนที่อยู่ใต้แผงทิ้ง (CSS ไม่วาด box-shadow ใต้กล่อง)
    if (s.shadows.isNotEmpty) {
      canvas.save();
      var reach = 0.0;
      for (final sh in s.shadows) {
        final r = sh.blur * 1.5 + sh.spread.abs() + sh.x.abs() + sh.y.abs();
        if (r > reach) reach = r;
      }
      final outside = Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(rect.inflate(reach + 4))
        ..addRRect(rr);
      canvas.clipPath(outside);
      for (final sh in s.shadows) {
        final r = _spread(rr.shift(sh.offset), sh.spread);
        canvas.drawRRect(
          r,
          Paint()
            ..color = sh.color
            ..maskFilter = sh.sigma > 0 ? MaskFilter.blur(BlurStyle.normal, sh.sigma) : null,
        );
      }
      canvas.restore();
    }

    // 2) พื้น
    final fill = Paint();
    if (s.gradient != null) {
      fill.shader = s.gradient!.createShader(rect);
    } else if (s.color != null) {
      fill.color = s.color!;
    }
    if (s.gradient != null || s.color != null) canvas.drawRRect(rr, fill);

    // 3) เอฟเฟกต์ด้านใน (ตัดให้อยู่ในแผง)
    final needInner = s.topHighlight != null ||
        s.bottomShade != null ||
        s.ring != null ||
        s.innerShadows.isNotEmpty;
    if (!needInner) return;
    canvas.save();
    canvas.clipRRect(rr);
    final whole = Path()..addRRect(rr);

    for (final sh in s.innerShadows) {
      // เงาจม = ทุกอย่างนอก "แผงที่เลื่อนตาม offset" แล้วเบลอ
      final hole = Path()..addRRect(_spread(rr.shift(sh.offset), -sh.spread));
      final ring = Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(rect.inflate(sh.blur * 2 + 8))
        ..addPath(hole, Offset.zero);
      canvas.drawPath(
        ring,
        Paint()
          ..color = sh.color
          ..maskFilter = sh.sigma > 0 ? MaskFilter.blur(BlurStyle.normal, sh.sigma) : null,
      );
    }
    if (s.topHighlight != null) {
      final strip = Path.combine(
        PathOperation.difference,
        whole,
        Path()..addRRect(rr.shift(Offset(0, s.topHighlightWidth))),
      );
      canvas.drawPath(strip, Paint()..color = s.topHighlight!);
    }
    if (s.bottomShade != null) {
      final strip = Path.combine(
        PathOperation.difference,
        whole,
        Path()..addRRect(rr.shift(Offset(0, -s.bottomShadeWidth))),
      );
      canvas.drawPath(strip, Paint()..color = s.bottomShade!);
    }
    if (s.ring != null) {
      canvas.drawRRect(
        rr.deflate(s.ringWidth / 2),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = s.ringWidth
          ..color = s.ring!,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(ObsidianSurfacePainter old) => old.s != s;
}

/// แผงกระจกขอบนูน — ใช้แทน Container+BoxDecoration ทุกที่ในธีม Obsidian
class ObsidianPanel extends StatelessWidget {
  final Widget child;
  final ObsidianSurface surface;
  final EdgeInsetsGeometry? padding;

  /// เบลอสิ่งที่อยู่ด้านหลัง (CSS backdrop-filter) — 0 = ไม่เบลอ (ประหยัด GPU)
  final double blur;

  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final String? semanticLabel;
  final double? width;
  final double? height;

  const ObsidianPanel({
    super.key,
    required this.child,
    this.surface = ObsidianSurface.panel,
    this.padding,
    this.blur = 0,
    this.onTap,
    this.onLongPress,
    this.semanticLabel,
    this.width,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(surface.radius);
    Widget body = Padding(padding: padding ?? EdgeInsets.zero, child: child);

    if (blur > 0) {
      body = ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: body,
        ),
      );
    }

    Widget panel = CustomPaint(
      painter: ObsidianSurfacePainter(surface),
      child: body,
    );
    if (width != null || height != null) {
      panel = SizedBox(width: width, height: height, child: panel);
    }

    if (onTap == null && onLongPress == null) {
      return semanticLabel == null
          ? panel
          : Semantics(label: semanticLabel, container: true, child: panel);
    }
    return ObsidianPressable(
      onTap: onTap,
      onLongPress: onLongPress,
      semanticLabel: semanticLabel,
      child: panel,
    );
  }
}

/// ปุ่มกดได้แบบ "ยุบเล็กน้อย" ตอนนิ้วแตะ (แทน ripple ที่ไม่เข้ากับวัตถุ 3D)
class ObsidianPressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final String? semanticLabel;

  /// ขนาดตอนกดค้าง (1 = ไม่ยุบ)
  final double pressedScale;

  const ObsidianPressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.semanticLabel,
    this.pressedScale = 0.97,
  });

  @override
  State<ObsidianPressable> createState() => _ObsidianPressableState();
}

class _ObsidianPressableState extends State<ObsidianPressable> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v && mounted) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null || widget.onLongPress != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        onTapDown: enabled ? (_) => _set(true) : null,
        onTapUp: enabled ? (_) => _set(false) : null,
        onTapCancel: enabled ? () => _set(false) : null,
        child: AnimatedScale(
          scale: _down ? widget.pressedScale : 1,
          duration: const Duration(milliseconds: 110),
          curve: Curves.easeOut,
          child: widget.child,
        ),
      ),
    );
  }
}
