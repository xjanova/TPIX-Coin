/// TPIX Wallet — ชั้นหรี่พื้นหลังเฉพาะหน้า (ธีม Obsidian)
///
/// พื้นหลังคลิปของธีมวาดครั้งเดียวทั้งแอป (wrapApp) ในแบบของหน้าแรก (คลิปสว่างเต็มครึ่งบน)
/// แต่ mock ของหน้ากิจกรรม/ตั้งค่า/มาสเตอร์โหนด ใช้คลิปจางกว่าและมืดลงเร็วกว่า
/// (คลิปเลื่อนขึ้น 120–200px ทึบ 60–75% + ไล่ดำถึงทึบที่ 360–460px)
/// → วางชั้นไล่ดำนี้ไว้หลังเนื้อหาของหน้านั้นเพื่อให้ได้ความสว่างใกล้ mock
///   (ค่าคำนวณจาก: (1 − ไล่ดำหน้าแรก) × (1 − ชั้นนี้) ≈ ความทึบคลิป × (1 − ไล่ดำของ mock))
///
/// Developed by Xman Studio
library;

import 'package:flutter/material.dart';

import '../../core/themes/obsidian_tokens.dart';

class ObsidianScreenDim extends StatelessWidget {
  /// จุดไล่สี (ระยะจากขอบบนจอ px, ความทึบ 0..1)
  final List<(double, double)> stops;

  const ObsidianScreenDim._(this.stops);

  /// A-Activity.dc.html (คลิปเลื่อนขึ้น 180 · ทึบ .6 · ไล่ .40→.90@220→ทึบ@380)
  static const activity = ObsidianScreenDim._([(0, 0.62), (110, 0.74), (220, 0.91), (380, 1)]);

  /// A-Settings.dc.html (คลิปเลื่อนขึ้น 200 · ทึบ .6 · ไล่ .40→.90@200→ทึบ@360)
  static const settings = ObsidianScreenDim._([(0, 0.62), (100, 0.74), (200, 0.92), (360, 1)]);

  /// A-Node.dc.html (คลิปเลื่อนขึ้น 120 · ทึบ .75 · ไล่ .30→.85@280→ทึบ@460)
  static const node = ObsidianScreenDim._([(0, 0.45), (140, 0.59), (280, 0.82), (460, 1)]);

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (_, box) {
          final h = box.maxHeight.isFinite && box.maxHeight > 0 ? box.maxHeight : 844.0;
          return DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [for (final s in stops) ObsidianColors.ground.withValues(alpha: s.$2)],
                stops: [for (final s in stops) (s.$1 / h).clamp(0.0, 1.0)],
              ),
            ),
          );
        },
      ),
    );
  }
}
