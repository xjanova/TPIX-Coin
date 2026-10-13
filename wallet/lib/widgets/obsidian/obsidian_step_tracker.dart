/// TPIX Wallet — ตัวติดตามขั้นตอน (ธีม Obsidian)
///
/// ตาม A-Bridge.dc.html "รายการล่าสุด":
///   - จุด 28px: เสร็จ = เขียวนูน + เครื่องหมายถูกเด้งเข้า (brPop .4s) · กำลังทำ = ม่วงนูน + วงหมุน
///     · ยังไม่ถึง = วงจาง · ต้องรอคน/มีปัญหา = เหลือง/แดง
///   - หัวข้อ 13.5 + คำอธิบาย 12 + แถบความคืบหน้าไล่สี (กว้างขยับนุ่ม .6s)
///   - ไม่รู้ว่าต้องรออีกกี่บล็อก → แถบวิ่งแบบไม่ระบุสัดส่วน (ห้ามเดาเปอร์เซ็นต์)
///
/// Developed by Xman Studio
library;

import 'package:flutter/material.dart';

import '../../core/themes/obsidian_tokens.dart';

enum ObsidianStepState { done, active, idle, warning, failed }

@immutable
class ObsidianStep {
  final String title;
  final String? sub;
  final ObsidianStepState state;

  /// โชว์แถบความคืบหน้าใต้ข้อความ
  final bool showBar;

  /// 0–1 · null = ไม่รู้สัดส่วน (แถบวิ่ง)
  final double? progress;

  const ObsidianStep({required this.title, this.sub, required this.state, this.showBar = false, this.progress});
}

class ObsidianStepTracker extends StatelessWidget {
  final List<ObsidianStep> steps;

  const ObsidianStepTracker({super.key, required this.steps});

  @override
  Widget build(BuildContext context) {
    final st = ObsidianStyle.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < steps.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // เปลี่ยนสถานะ = สร้างจุดใหม่ → เครื่องหมายถูกเด้งเข้าตอนเพิ่งเสร็จ
              _StepDot(key: ValueKey('${steps[i].state}'), state: steps[i].state),
              const SizedBox(width: 10),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        steps[i].title,
                        style: st.ui(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w500,
                          height: 1.35,
                          color: switch (steps[i].state) {
                            ObsidianStepState.idle => ObsidianColors.textMuted,
                            ObsidianStepState.failed => ObsidianColors.dangerSoft,
                            _ => ObsidianColors.text,
                          },
                        ),
                      ),
                      if (steps[i].sub != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          steps[i].sub!,
                          style: st.ui(
                            fontSize: 12,
                            height: 1.4,
                            color: steps[i].state == ObsidianStepState.warning
                                ? ObsidianColors.warning
                                : ObsidianColors.textMuted,
                          ),
                        ),
                      ],
                      if (steps[i].showBar) ...[
                        const SizedBox(height: 6),
                        ObsidianProgressBar(progress: steps[i].progress),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _StepDot extends StatelessWidget {
  final ObsidianStepState state;

  const _StepDot({super.key, required this.state});

  static BoxDecoration _deco(ObsidianStepState s) => switch (s) {
    ObsidianStepState.done => const BoxDecoration(
      shape: BoxShape.circle,
      gradient: RadialGradient(
        center: Alignment(-0.3, -0.4),
        radius: 0.95,
        colors: [ObsidianColors.successSoft, Color(0xFF059669)],
      ),
      boxShadow: [BoxShadow(color: ObsidianColors.success, blurRadius: 6.4, spreadRadius: -2)],
    ),
    ObsidianStepState.active => const BoxDecoration(
      shape: BoxShape.circle,
      gradient: RadialGradient(
        center: Alignment(-0.3, -0.4),
        radius: 0.95,
        colors: [Color(0xFFA78BFA), Color(0xFF6D28D9)],
      ),
      boxShadow: [BoxShadow(color: ObsidianColors.violet, blurRadius: 7.6, spreadRadius: -2)],
    ),
    ObsidianStepState.warning => const BoxDecoration(
      shape: BoxShape.circle,
      gradient: RadialGradient(
        center: Alignment(-0.3, -0.4),
        radius: 0.95,
        colors: [ObsidianColors.warning, Color(0xFFB45309)],
      ),
      boxShadow: [BoxShadow(color: Color(0xFFF59E0B), blurRadius: 7.6, spreadRadius: -2)],
    ),
    ObsidianStepState.failed => const BoxDecoration(
      shape: BoxShape.circle,
      gradient: RadialGradient(
        center: Alignment(-0.3, -0.4),
        radius: 0.95,
        colors: [ObsidianColors.dangerSoft, Color(0xFFB91C1C)],
      ),
      boxShadow: [BoxShadow(color: ObsidianColors.danger, blurRadius: 7.6, spreadRadius: -2)],
    ),
    ObsidianStepState.idle => BoxDecoration(
      shape: BoxShape.circle,
      color: const Color(0x0FFFFFFF),
      border: Border.all(color: const Color(0x26FFFFFF), width: 1.5),
    ),
  };

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final Widget? glyph = switch (state) {
      ObsidianStepState.done => const Icon(Icons.check_rounded, size: 16, color: Colors.white),
      ObsidianStepState.active => const SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white, backgroundColor: Color(0x40FFFFFF)),
      ),
      ObsidianStepState.warning => const Icon(Icons.priority_high_rounded, size: 16, color: Colors.white),
      ObsidianStepState.failed => const Icon(Icons.close_rounded, size: 16, color: Colors.white),
      ObsidianStepState.idle => null,
    };
    return Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: _deco(state),
      child: glyph == null || reduce || state == ObsidianStepState.active
          ? glyph
          // brPop: 0% scale .4 จาง → 70% scale 1.15 → 100% scale 1
          : TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeOut,
              builder: (_, t, child) {
                final scale = t < 0.7 ? 0.4 + (1.15 - 0.4) * (t / 0.7) : 1.15 - 0.15 * ((t - 0.7) / 0.3);
                return Opacity(
                  opacity: (t / 0.7).clamp(0.0, 1.0),
                  child: Transform.scale(scale: scale, child: child),
                );
              },
              child: glyph,
            ),
    );
  }
}

/// แถบความคืบหน้าไล่สี cyan → violet → orange
class ObsidianProgressBar extends StatefulWidget {
  /// null = ไม่รู้สัดส่วน (วิ่งวน)
  final double? progress;
  final double height;

  const ObsidianProgressBar({super.key, this.progress, this.height = 5});

  @override
  State<ObsidianProgressBar> createState() => _ObsidianProgressBarState();
}

class _ObsidianProgressBarState extends State<ObsidianProgressBar> with SingleTickerProviderStateMixin {
  late final AnimationController _run = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));

  static const _fill = LinearGradient(colors: [ObsidianColors.cyan, ObsidianColors.violet, ObsidianColors.orange]);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(ObsidianProgressBar old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (widget.progress == null && !reduce) {
      if (!_run.isAnimating) _run.repeat();
    } else {
      _run.stop();
    }
  }

  @override
  void dispose() {
    _run.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h = widget.height;
    final radius = BorderRadius.circular(h);
    return Semantics(
      value: widget.progress == null ? null : '${(widget.progress! * 100).round()}%',
      child: ClipRRect(
        borderRadius: radius,
        child: Container(
          height: h,
          color: const Color(0x14FFFFFF),
          child: LayoutBuilder(
            builder: (context, box) {
              final w = box.maxWidth;
              if (widget.progress != null) {
                return Align(
                  alignment: Alignment.centerLeft,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 600),
                    curve: Curves.ease,
                    width: w * widget.progress!.clamp(0.0, 1.0),
                    decoration: BoxDecoration(borderRadius: radius, gradient: _fill),
                  ),
                );
              }
              // แถบยาว 40% วิ่งจากซ้ายออกขวา
              return AnimatedBuilder(
                animation: _run,
                builder: (context, _) {
                  final seg = w * 0.4;
                  final left = -seg + (w + seg) * Curves.easeInOut.transform(_run.value);
                  return Stack(
                    children: [
                      Positioned(
                        left: left,
                        top: 0,
                        bottom: 0,
                        width: seg,
                        child: DecoratedBox(
                          decoration: BoxDecoration(borderRadius: radius, gradient: _fill),
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}
