/// TPIX Wallet — ชิ้นส่วนหน้า PIN ธีม Obsidian (ตาม A-Pin.dc.html)
///
///   - [ObsidianPinDots]       จุด 6 จุด: ว่าง = หลุมจม · ใส่แล้ว = ไล่สีเรืองแสง "เด้ง" ·
///                             กำลังตรวจ = เขียวเต้นเป็นคลื่น · ผิด = แดง
///   - [ObsidianKeypad]        แป้นกระจก 3x4 + ปุ่มสแกนนิ้ว 3D + ปุ่มลบ
///   - [ObsidianFloatingHero]  ไอคอน 3D ลอยขึ้นลง (กุญแจ / ลายนิ้วมือ / โล่)
///   - [ObsidianCheckRing]     วงกลม + เครื่องหมายถูก "วาด" ทีละเส้น (หน้าสำเร็จ)
///
/// Developed by Xman Studio
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/themes/obsidian_tokens.dart';
import 'icon_3d.dart';
import 'obsidian_assets.dart';
import 'obsidian_glyph.dart';
import 'obsidian_loop.dart';
import 'obsidian_panel.dart';

enum PinDotsMode { entering, busy, error }

class ObsidianPinDots extends StatelessWidget {
  final int count;
  final int length;
  final PinDotsMode mode;

  /// คำอ่านของตัวอ่านหน้าจอ (เช่น "ใส่แล้ว 3 จาก 6 หลัก")
  final String semanticLabel;

  const ObsidianPinDots({
    super.key,
    required this.count,
    this.length = 6,
    this.mode = PinDotsMode.entering,
    this.semanticLabel = '',
  });

  static const double dot = 16;
  static const double gap = 14;

  @override
  Widget build(BuildContext context) {
    final row = ObsidianLoop(
      // คลื่นเขียว .9 วิ/รอบ — เล่นเฉพาะตอนกำลังตรวจ
      period: const Duration(milliseconds: 900),
      enabled: mode == PinDotsMode.busy,
      builder: (context, t, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < length; i++) ...[
            if (i > 0) const SizedBox(width: gap),
            _Dot(
              filled: i < count,
              mode: mode,
              wave: mode == PinDotsMode.busy ? _wave(t, i) : 0,
            ),
          ],
        ],
      ),
    );
    return Semantics(label: semanticLabel, liveRegion: true, child: ExcludeSemantics(child: row));
  }

  /// pnWave: 0%/100% = 1 · 50% = 1.25 (หน่วงทีละ 80ms ต่อจุด)
  static double _wave(double t, int i) {
    final p = (t - i * 0.08 / 0.9) % 1.0;
    final half = p < 0.5 ? p / 0.5 : 1 - (p - 0.5) / 0.5;
    return Curves.easeInOut.transform(half.clamp(0.0, 1.0));
  }
}

class _Dot extends StatefulWidget {
  final bool filled;
  final PinDotsMode mode;

  /// 0..1 ความสูงคลื่น (โหมดกำลังตรวจ)
  final double wave;

  const _Dot({required this.filled, required this.mode, required this.wave});

  @override
  State<_Dot> createState() => _DotState();
}

class _DotState extends State<_Dot> with SingleTickerProviderStateMixin {
  /// pnDot .3s: 0.4 → 1.3 (60%) → 1 — สร้างใน initState (ห้าม lazy: dispose จะสร้างตัวใหม่ตอนถูกถอด)
  late final AnimationController _pop;

  @override
  void initState() {
    super.initState();
    _pop = AnimationController(vsync: this, duration: const Duration(milliseconds: 300), value: 1);
  }

  @override
  void didUpdateWidget(_Dot old) {
    super.didUpdateWidget(old);
    if (!old.filled && widget.filled && widget.mode == PinDotsMode.entering) {
      final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
      if (!reduce) _pop.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _pop.dispose();
    super.dispose();
  }

  static double _popScale(double t) {
    final e = Curves.easeOut.transform(t);
    return e < 0.6 ? 0.4 + 0.9 * (e / 0.6) : 1.3 - 0.3 * ((e - 0.6) / 0.4);
  }

  static const _empty = ObsidianSurface(
    radius: 8,
    color: Color(0x0FFFFFFF), // .06
    innerShadows: [CssShadow(0, 1, 3, 0, Color(0xB3000000))],
    ring: Color(0x2EFFFFFF), // .18
    ringWidth: 1.5,
  );

  @override
  Widget build(BuildContext context) {
    const s = ObsidianPinDots.dot;
    if (widget.mode == PinDotsMode.busy) {
      return Transform.scale(
        scale: 1 + 0.25 * widget.wave,
        child: Opacity(opacity: 1 - 0.3 * widget.wave, child: _solid(ObsidianColors.success)),
      );
    }
    if (widget.mode == PinDotsMode.error) return _solid(ObsidianColors.danger);
    if (!widget.filled) {
      return const SizedBox.square(dimension: s, child: CustomPaint(painter: ObsidianSurfacePainter(_empty)));
    }
    return AnimatedBuilder(
      animation: _pop,
      builder: (context, child) => Transform.scale(scale: _popScale(_pop.value), child: child),
      child: Container(
        width: s,
        height: s,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [ObsidianColors.cyan, ObsidianColors.violet, ObsidianColors.orange],
            stops: [0, 0.55, 1],
          ),
          boxShadow: [const CssShadow(0, 0, 12, 0, Color(0xE68B5CF6)).toBoxShadow()],
        ),
      ),
    );
  }

  Widget _solid(Color c) => Container(
        width: ObsidianPinDots.dot,
        height: ObsidianPinDots.dot,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: c,
          boxShadow: [CssShadow(0, 0, 12, 0, c).toBoxShadow()],
        ),
      );
}

// ═══════════════════════════════════════════════════════════════
//  แป้นกด
// ═══════════════════════════════════════════════════════════════

class ObsidianKeypad extends StatelessWidget {
  final ValueChanged<String> onDigit;
  final VoidCallback onDelete;

  /// null = ไม่มีปุ่มสแกนนิ้ว (ช่องว่าง)
  final VoidCallback? onBiometric;

  /// กำลังสแกนนิ้ว — ไอคอนเรืองแสงเต้น
  final bool biometricActive;

  /// false = ไม่รับการกด (กำลังตรวจ PIN)
  final bool enabled;

  final String biometricLabel;
  final String deleteLabel;

  const ObsidianKeypad({
    super.key,
    required this.onDigit,
    required this.onDelete,
    this.onBiometric,
    this.biometricActive = false,
    this.enabled = true,
    this.biometricLabel = '',
    this.deleteLabel = '',
  });

  static const double keyWidth = 84;
  static const double keyHeight = 66;

  static const _keySurface = ObsidianSurface(
    radius: 22,
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0x17FFFFFF), Color(0x05FFFFFF)], // .09 → .02
    ),
    topHighlight: Color(0x29FFFFFF), // .16
    bottomShade: Color(0x8C000000), // .55
    shadows: [CssShadow(0, 10, 20, -12, Color(0xF2000000))],
  );

  @override
  Widget build(BuildContext context) {
    final st = ObsidianStyle.of(context);
    Widget key(String k) {
      final body = Center(
        child: Text(
          k,
          style: st.number(fontSize: 28, fontWeight: FontWeight.w600, color: ObsidianColors.text),
        ),
      );
      return ObsidianPanel(
        width: keyWidth,
        height: keyHeight,
        surface: _keySurface,
        onTap: enabled ? () => onDigit(k) : null,
        semanticLabel: k,
        child: ExcludeSemantics(child: body),
      );
    }

    Widget bare({required Widget child, required VoidCallback? onTap, required String label}) => SizedBox(
          width: keyWidth,
          height: keyHeight,
          child: ObsidianPressable(
            onTap: enabled ? onTap : null,
            semanticLabel: label,
            child: Center(child: child),
          ),
        );

    final bio = onBiometric == null
        ? const SizedBox(width: keyWidth, height: keyHeight)
        : bare(
            onTap: onBiometric,
            label: biometricLabel,
            child: ObsidianLoop(
              period: const Duration(milliseconds: 250),
              reverse: true,
              enabled: biometricActive,
              builder: (context, t, _) => Icon3D(
                ObsidianIcons.fingerprint,
                size: 44,
                shadows: biometricActive
                    ? [
                        IconDropShadow(
                          0,
                          0,
                          4 + 14 * t,
                          Color.lerp(const Color(0x808B5CF6), ObsidianColors.cyan, t)!,
                        ),
                      ]
                    : const [],
              ),
            ),
          );

    final del = bare(
      onTap: onDelete,
      label: deleteLabel,
      child: const ObsidianGlyphIcon(ObsidianGlyph.backspace, size: 28, color: Color(0xFFE9EAEE), strokeWidth: 1.8),
    );

    Widget row(List<Widget> keys) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            keys[0],
            const SizedBox(width: 18),
            keys[1],
            const SizedBox(width: 18),
            keys[2],
          ],
        );

    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.2,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          row([key('1'), key('2'), key('3')]),
          const SizedBox(height: 12),
          row([key('4'), key('5'), key('6')]),
          const SizedBox(height: 12),
          row([key('7'), key('8'), key('9')]),
          const SizedBox(height: 12),
          row([bio, key('0'), del]),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  ไอคอนลอย
// ═══════════════════════════════════════════════════════════════

class ObsidianFloatingHero extends StatelessWidget {
  final String asset;
  final double size;

  const ObsidianFloatingHero({super.key, required this.asset, this.size = 104});

  @override
  Widget build(BuildContext context) {
    // pnFloat 4 วิ: 0 → -8px → 0
    return ObsidianLoop(
      period: const Duration(seconds: 2),
      reverse: true,
      builder: (context, t, child) => Transform.translate(
        offset: Offset(0, -8 * Curves.easeInOut.transform(t)),
        child: child,
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: Icon3D(
          asset,
          key: ValueKey(asset),
          size: size,
          shadows: const [
            IconDropShadow(0, 16, 20, Color(0xD9000000)),
            IconDropShadow(0, 0, 26, Color(0x998B5CF6)),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  วงกลม + เครื่องหมายถูก (วาดทีละเส้น)
// ═══════════════════════════════════════════════════════════════

class ObsidianCheckRing extends StatefulWidget {
  final double size;
  final Color color;

  /// แสงกวาดหมุนรอบวง (หน้าส่งสำเร็จ)
  final bool rays;

  const ObsidianCheckRing({
    super.key,
    this.size = 150,
    this.color = ObsidianColors.success,
    this.rays = true,
  });

  @override
  State<ObsidianCheckRing> createState() => _ObsidianCheckRingState();
}

class _ObsidianCheckRingState extends State<ObsidianCheckRing> with SingleTickerProviderStateMixin {
  /// วง .8 วิ · เครื่องหมายถูกเริ่ม .4 วิ ยาว .7 วิ → จบที่ 1.1 วิ
  late final AnimationController _draw =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduce) {
      _draw.value = 1;
    } else if (_draw.value == 0 && !_draw.isAnimating) {
      _draw.forward();
    }
  }

  @override
  void dispose() {
    _draw.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    final ring = AnimatedBuilder(
      animation: _draw,
      builder: (context, _) {
        final ms = _draw.value * 1100;
        final circle = Curves.easeOut.transform((ms / 800).clamp(0.0, 1.0));
        final check = Curves.easeOut.transform(((ms - 400) / 700).clamp(0.0, 1.0));
        return CustomPaint(
          size: Size.square(s),
          painter: _CheckRingPainter(circle, check, widget.color),
        );
      },
    );
    if (!widget.rays) return SizedBox.square(dimension: s, child: ring);
    final halo = s * 170 / 150;
    return SizedBox.square(
      dimension: halo,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          // pnRay: กรวยแสงเขียว/ม่วงหมุน 6 วิ เบลอ 12px ขยายออก 40px รอบวง
          Positioned(
            left: -40,
            top: -40,
            right: -40,
            bottom: -40,
            child: IgnorePointer(
              child: ImageFiltered(
                imageFilter: ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6, tileMode: TileMode.decal),
                child: ObsidianLoop(
                  period: const Duration(seconds: 6),
                  builder: (context, t, _) => DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: SweepGradient(
                        transform: GradientRotation(-math.pi / 2 + 2 * math.pi * t),
                        colors: const [
                          Color(0x0034D399),
                          Color(0x5934D399),
                          Color(0x0022D3EE),
                          Color(0x4D8B5CF6),
                          Color(0x0034D399),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          ring,
        ],
      ),
    );
  }
}

class _CheckRingPainter extends CustomPainter {
  final double circle;
  final double check;
  final Color color;

  const _CheckRingPainter(this.circle, this.check, this.color);

  static Path _partial(Path p, double t) {
    if (t <= 0) return Path();
    final out = Path();
    for (final m in p.computeMetrics()) {
      out.addPath(m.extractPath(0, m.length * t), Offset.zero);
    }
    return out;
  }

  @override
  void paint(Canvas canvas, Size size) {
    // viewBox 60x60 · วง r=26 เส้น 3 · ถูก M18 31 l8 8 16-17 เส้น 4
    final k = size.width / 60;
    canvas.scale(k);
    // วาดเริ่มที่ 3 นาฬิกา ตามเข็ม (เหมือน SVG circle + stroke-dashoffset)
    final ringPath = Path()..addArc(const Rect.fromLTWH(4, 4, 52, 52), 0, 2 * math.pi * 0.9999);
    final tick = Path()
      ..moveTo(18, 31)
      ..lineTo(26, 39)
      ..lineTo(42, 22);
    final ringPart = _partial(ringPath, circle);
    final tickPart = _partial(tick, check);

    Paint stroke(double w, {bool glow = false}) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = glow ? color.withValues(alpha: 0.8) : color
      ..maskFilter = glow ? MaskFilter.blur(BlurStyle.normal, 8 / k) : null;

    // drop-shadow(0 0 16px rgba(52,211,153,.8))
    canvas.drawPath(ringPart, stroke(3, glow: true));
    canvas.drawPath(tickPart, stroke(4, glow: true));
    canvas.drawPath(ringPart, stroke(3));
    canvas.drawPath(tickPart, stroke(4));
  }

  @override
  bool shouldRepaint(_CheckRingPainter old) => old.circle != circle || old.check != check || old.color != color;
}
