/// TPIX Wallet — ลูกแก้วสลับทิศ + วงนับถอยหลังอัปเดตราคา (ธีม Obsidian)
///
/// ตาม A-Swap.dc.html:
///   - ลูกแก้ว 58px: วงไล่สี conic cyan→violet→orange หมุนรอบละ 3.2 วิ
///     + แสงม่วงเต้นเข้าออก 4 วิ + ไอคอนสลับ 3D หมุน 180° ทุกครั้งที่แตะ (.5s เด้งนิดหน่อย)
///   - วงนับถอยหลัง 18px: เส้นม่วงหดจากเต็มวงเหลือศูนย์ตามเวลาที่เหลือ
///
/// เปิด "ลดภาพเคลื่อนไหว" = วงหยุดหมุน/ไม่เต้น (ไอคอนยังพลิกทิศทันทีเพื่อบอกผล)
///
/// Developed by Xman Studio
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/themes/obsidian_tokens.dart';
import 'obsidian_assets.dart';
import 'obsidian_panel.dart';

class ObsidianSwapOrb extends StatefulWidget {
  /// จำนวนครั้งที่สลับทิศแล้ว — ไอคอนหมุนไปที่ flips × 180°
  final int flips;
  final VoidCallback? onTap;
  final String semanticLabel;
  final double size;

  const ObsidianSwapOrb({
    super.key,
    required this.flips,
    required this.onTap,
    required this.semanticLabel,
    this.size = 58,
  });

  /// เส้นโค้ง cubic-bezier(.2,.9,.25,1.2) ของ mock (เกินนิดแล้วกลับ)
  static const flipCurve = Cubic(0.2, 0.9, 0.25, 1.2);

  @override
  State<ObsidianSwapOrb> createState() => _ObsidianSwapOrbState();
}

class _ObsidianSwapOrbState extends State<ObsidianSwapOrb> with TickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(vsync: this, duration: const Duration(milliseconds: 3200));
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(seconds: 4));
  bool _reduce = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (_reduce) {
      _spin.stop();
      _pulse.stop();
    } else {
      if (!_spin.isAnimating) _spin.repeat();
      if (!_pulse.isAnimating) _pulse.repeat();
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    final inner = s - 6;
    return Semantics(
      button: true,
      enabled: widget.onTap != null,
      label: widget.semanticLabel,
      excludeSemantics: true,
      // ClipOval ไม่ตัดภาพ (Clip.none) แต่จำกัดพื้นที่รับการแตะให้เป็นวงกลม
      child: ClipOval(
        clipBehavior: Clip.none,
        child: ObsidianPressable(
          onTap: widget.onTap,
          pressedScale: 0.92,
          child: AnimatedBuilder(
            animation: _pulse,
            builder: (context, child) {
              // swPulse: 0%/100% = 0 0 12px 0 .45 · 50% = 0 0 28px 6px .75
              final t = _reduce ? 0.0 : (1 - math.cos(_pulse.value * 2 * math.pi)) / 2;
              final glow = CssShadow.lerp(
                const CssShadow(0, 0, 12, 0, Color(0x738B5CF6)),
                const CssShadow(0, 0, 28, 6, Color(0xBF8B5CF6)),
                t,
              );
              return DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [glow.toBoxShadow(), const CssShadow(0, 12, 22, -6, Color(0xE6000000)).toBoxShadow()],
                ),
                child: child,
              );
            },
            child: SizedBox(
              width: s,
              height: s,
              child: ClipOval(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // วงไล่สีหมุน (ใหญ่กว่าลูกแก้ว ตัดขอบเหลือเป็นวงแหวน 3px)
                    RotationTransition(
                      turns: _spin,
                      child: OverflowBox(
                        maxWidth: s * 96 / 58,
                        maxHeight: s * 96 / 58,
                        child: const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: SweepGradient(
                              colors: [
                                ObsidianColors.cyan,
                                ObsidianColors.violet,
                                ObsidianColors.orange,
                                ObsidianColors.cyan,
                              ],
                            ),
                          ),
                          child: SizedBox.expand(),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: inner,
                      height: inner,
                      child: ClipOval(
                        child: CustomPaint(
                          painter: ObsidianSurfacePainter(
                            ObsidianSurface(
                              radius: inner / 2,
                              color: const Color(0xFF0A0B10),
                              topHighlight: const Color(0x29FFFFFF),
                              topHighlightWidth: 2,
                            ),
                          ),
                          child: TweenAnimationBuilder<double>(
                            tween: Tween(end: widget.flips * 0.5),
                            duration: _reduce ? Duration.zero : const Duration(milliseconds: 500),
                            curve: ObsidianSwapOrb.flipCurve,
                            builder: (_, turns, child) => Transform.rotate(angle: turns * 2 * math.pi, child: child),
                            child: OverflowBox(
                              maxWidth: s * 74 / 58,
                              maxHeight: s * 74 / 58,
                              child: Image.asset(
                                ObsidianIcons.swap,
                                width: s * 74 / 58,
                                height: s * 74 / 58,
                                cacheWidth: 240,
                                excludeFromSemantics: true,
                                errorBuilder: (_, _, _) =>
                                    const Icon(Icons.swap_vert_rounded, color: ObsidianColors.text, size: 26),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// วงนับถอยหลัง — [remaining] 1 = เต็มวง · 0 = หมด
class ObsidianCountdownRing extends StatelessWidget {
  final double remaining;
  final double size;
  final Color color;

  const ObsidianCountdownRing({super.key, required this.remaining, this.size = 18, this.color = ObsidianColors.violet});

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: CustomPaint(painter: _RingPainter(remaining.clamp(0.0, 1.0), color)),
  );
}

class _RingPainter extends CustomPainter {
  final double remaining;
  final Color color;

  const _RingPainter(this.remaining, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    // mock: viewBox 32 · r 14 · stroke 3
    final k = size.width / 32;
    final c = size.center(Offset.zero);
    final r = 14 * k;
    final stroke = 3 * k;
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = const Color(0x1FFFFFFF),
    );
    if (remaining <= 0) return;
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r),
      -math.pi / 2,
      2 * math.pi * remaining,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.remaining != remaining || old.color != color;
}
