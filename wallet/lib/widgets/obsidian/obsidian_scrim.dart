/// TPIX Wallet — ม่านมืดเฉพาะหน้า (วางทับพื้นหลังคลิปของทั้งแอป ใต้เนื้อหา)
///
/// พื้นหลังของธีม (ObsidianBackground) ตั้งความสว่างไว้ตามหน้าแรก (Main.dc.html)
/// แต่ mock หน้าอื่นหรี่คลิปลงมากกว่า (ส่ง/รับ ~.75–.8 · PIN .55 + เบลอ) และไล่ดำเร็วกว่า
/// ตัวนี้หรี่เพิ่มเฉพาะครึ่งบนของจอให้ใกล้ mock — ตัวหนังสือ/ปุ่มกระจกอ่านง่ายขึ้นด้วย
///
/// Developed by Xman Studio
library;

import 'package:flutter/material.dart';

import '../../core/themes/obsidian_tokens.dart';

class ObsidianScrim extends StatelessWidget {
  /// ความทึบที่ขอบบน
  final double top;

  /// ความทึบที่ระดับ 250px (ของจอ 844)
  final double mid;

  /// หายหมดที่ระดับนี้ (px ของจอ 844)
  final double fadeTo;

  const ObsidianScrim({super.key, required this.top, required this.mid, this.fadeTo = 600});

  /// หน้าส่ง (mock: คลิป .75 เลื่อนขึ้น 120px · ไล่ .35 → .85 ที่ 300px)
  const ObsidianScrim.send({super.key})
      : top = 0.48,
        mid = 0.70,
        fadeTo = 600;

  /// หน้ารับเงิน (mock: คลิป .8 · ไล่ .30 → .80 ที่ 280px)
  const ObsidianScrim.receive({super.key})
      : top = 0.40,
        mid = 0.66,
        fadeTo = 600;

  /// หน้า PIN (mock: คลิป .55 เบลอ 2px · ไล่ .45 → .85 ที่ 360px)
  const ObsidianScrim.pin({super.key})
      : top = 0.68,
        mid = 0.74,
        fadeTo = 620;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: LayoutBuilder(builder: (context, box) {
          final h = box.maxHeight.isFinite && box.maxHeight > 0 ? box.maxHeight : 844.0;
          final k = h / 844;
          final midStop = (250 * k / h).clamp(0.0, 1.0);
          final endStop = (fadeTo * k / h).clamp(midStop, 1.0);
          return DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  ObsidianColors.ground.withValues(alpha: top),
                  ObsidianColors.ground.withValues(alpha: mid),
                  ObsidianColors.ground.withValues(alpha: 0),
                ],
                stops: [0, midStop, endStop],
              ),
            ),
          );
        }),
      ),
    );
  }
}
