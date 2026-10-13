/// TPIX Wallet — แอนิเมชันวนลูปของธีม Obsidian (หายใจ / หมุน / ลอย / กะพริบ)
///
/// mock ใช้ CSS `animation: ... infinite` เยอะมาก (วงแหวนหมุน จุดเต้น เลเซอร์ ไอคอนลอย)
/// ตัวนี้รวมงานซ้ำ ๆ ไว้ที่เดียว:
///   - สร้าง/ทิ้ง AnimationController ให้เอง (ไม่มี ticker ค้างหลังปิดหน้า)
///   - เครื่องเปิด "ลดภาพเคลื่อนไหว" → หยุดนิ่งที่ [restValue] (pumpAndSettle ในเทสต์จบได้)
///   - [enabled] = false → หยุดนิ่งเหมือนกัน (เช่น เลเซอร์หยุดตอนสแกนเจอแล้ว)
///
/// Developed by Xman Studio
library;

import 'package:flutter/widgets.dart';

class ObsidianLoop extends StatefulWidget {
  /// ระยะเวลาหนึ่งรอบ (ถ้า [reverse] = เวลาขาไปหนึ่งเที่ยว ตามแบบ CSS alternate)
  final Duration period;

  /// ไป-กลับ (0→1→0) แทนการกระโดดกลับ 0
  final bool reverse;

  /// ค่าที่ค้างไว้ตอนหยุด (ลดภาพเคลื่อนไหว / enabled = false)
  final double restValue;

  /// เล่นอยู่ไหม
  final bool enabled;

  /// t = 0..1 ของรอบปัจจุบัน
  final Widget Function(BuildContext context, double t, Widget? child) builder;

  /// ส่วนที่ไม่ขยับ (ไม่ต้อง build ใหม่ทุกเฟรม)
  final Widget? child;

  const ObsidianLoop({
    super.key,
    required this.period,
    required this.builder,
    this.reverse = false,
    this.restValue = 0,
    this.enabled = true,
    this.child,
  });

  @override
  State<ObsidianLoop> createState() => _ObsidianLoopState();
}

class _ObsidianLoopState extends State<ObsidianLoop> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: widget.period);
  bool _reduceMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    _sync();
  }

  @override
  void didUpdateWidget(ObsidianLoop old) {
    super.didUpdateWidget(old);
    if (old.period != widget.period) _c.duration = widget.period;
    if (old.enabled != widget.enabled || old.reverse != widget.reverse || old.period != widget.period) {
      _sync(restart: old.period != widget.period || old.reverse != widget.reverse);
    }
  }

  void _sync({bool restart = false}) {
    final run = widget.enabled && !_reduceMotion;
    if (!run) {
      if (_c.isAnimating || _c.value != widget.restValue) {
        _c
          ..stop()
          ..value = widget.restValue;
      }
      return;
    }
    if (_c.isAnimating && !restart) return;
    _c.repeat(reverse: widget.reverse);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        child: widget.child,
        builder: (context, child) => widget.builder(context, _c.value, child),
      );
}
