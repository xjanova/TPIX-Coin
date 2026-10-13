/// TPIX Wallet — แถบความคืบหน้าไล่สีแบรนด์ + แสงวิ่งผ่าน ของธีม Obsidian
///
/// - [value] มีค่า = แถบตามสัดส่วนจริง (เช่น ยอดที่มีเทียบกับที่ต้องสเตค) เลื่อนนุ่ม .6 วิ
/// - [value] = null = "กำลังดำเนินการ" แบบไม่รู้สัดส่วน — แกว่ง 40%↔95% ช้า ๆ (mock acBar 9 วิ)
///   ไม่โชว์ตัวเลขเปอร์เซ็นต์ปลอม เพราะไม่มีข้อมูลจริงว่าเหลืออีกเท่าไร
/// - ผู้ใช้ปิดภาพเคลื่อนไหวในเครื่อง → แถบนิ่ง
///
/// Developed by Xman Studio
library;

import 'package:flutter/material.dart';

import '../../core/themes/obsidian_tokens.dart';

class ObsidianGradientBar extends StatefulWidget {
  /// 0..1 หรือ null = ไม่รู้สัดส่วน
  final double? value;
  final double height;

  const ObsidianGradientBar({super.key, this.value, this.height = 6});

  static const gradient = LinearGradient(colors: [ObsidianColors.cyan, ObsidianColors.violet, ObsidianColors.orange]);

  @override
  State<ObsidianGradientBar> createState() => _ObsidianGradientBarState();
}

class _ObsidianGradientBarState extends State<ObsidianGradientBar> with SingleTickerProviderStateMixin {
  AnimationController? _swing;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(ObsidianGradientBar old) {
    super.didUpdateWidget(old);
    _sync();
  }

  /// สร้าง/หยุดตัวแกว่งตามสถานะ (ไม่รู้สัดส่วน + ไม่ได้ปิดภาพเคลื่อนไหว)
  void _sync() {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final want = widget.value == null && !reduce;
    if (want && _swing == null) {
      _swing = AnimationController(vsync: this, duration: const Duration(seconds: 9))..repeat(reverse: true);
    } else if (!want && _swing != null) {
      _swing!.dispose();
      _swing = null;
    }
  }

  @override
  void dispose() {
    _swing?.dispose();
    super.dispose();
  }

  Widget _track(double fraction) {
    final r = BorderRadius.circular(widget.height);
    return ClipRRect(
      borderRadius: r,
      child: Container(
        height: widget.height,
        color: const Color(0x14FFFFFF), // ขาว 8%
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: fraction.clamp(0.0, 1.0),
          heightFactor: 1,
          child: DecoratedBox(
            decoration: BoxDecoration(borderRadius: r, gradient: ObsidianGradientBar.gradient),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.value;
    if (v != null) {
      return TweenAnimationBuilder<double>(
        tween: Tween(end: v),
        duration: const Duration(milliseconds: 600),
        curve: Curves.ease,
        builder: (_, f, _) => _track(f),
      );
    }
    final swing = _swing;
    if (swing == null) return _track(0.6);
    return AnimatedBuilder(
      animation: swing,
      builder: (_, _) => _track(0.4 + 0.55 * Curves.easeInOut.transform(swing.value)),
    );
  }
}

/// แสงสว่างวิ่งผ่านแผง (mock acShimmer 2.6 วิ) — วางเป็นชั้นบนสุดใน Stack ที่ตัดขอบแล้ว
class ObsidianShimmerSweep extends StatefulWidget {
  final Duration period;

  const ObsidianShimmerSweep({super.key, this.period = const Duration(milliseconds: 2600)});

  @override
  State<ObsidianShimmerSweep> createState() => _ObsidianShimmerSweepState();
}

class _ObsidianShimmerSweepState extends State<ObsidianShimmerSweep> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: widget.period);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduce) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduce) return const SizedBox.shrink();
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (_, box) => AnimatedBuilder(
          animation: _c,
          builder: (_, _) {
            // แถบกว้าง 30% เลื่อนจาก -100% → +300% ของความกว้างตัวเอง (ease-in-out)
            final t = Curves.easeInOut.transform(_c.value);
            final w = box.maxWidth * 0.3;
            return Stack(
              children: [
                Positioned(
                  left: -w + t * w * 4,
                  top: 0,
                  bottom: 0,
                  width: w,
                  child: const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [Color(0x00FFFFFF), Color(0x14FFFFFF), Color(0x00FFFFFF)]),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
