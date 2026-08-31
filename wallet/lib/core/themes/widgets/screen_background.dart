/// TPIX Wallet — พื้นหลังหน้าจอกลาง
///
/// เดิมทุกหน้าเขียน `Container(decoration: c.screenBg, child: ...)` เอง 15 จุด
/// ผลคือ:
///   1. อยากเพิ่มลาย/ปรับพื้นหลัง ต้องไล่แก้ 15 ที่ และหลุดง่าย
///   2. พื้นหลังทึบของแต่ละหน้า **บังลายที่ธีมวาดไว้หลังฉาก** (wrapApp) จนมองไม่เห็นเลย
///      — ปัญหานี้มองไม่ออกจากการอ่านโค้ดหน้าใดหน้าหนึ่ง เห็นตอนเรนเดอร์ออกมาดูเท่านั้น
///
/// ตัวนี้รวมทุกอย่างไว้ที่เดียว: ไล่สีตามธีม → ลายพื้นผิว → เนื้อหา
///
/// Developed by Xman Studio

import 'package:flutter/material.dart';

import '../../theme.dart';
import 'luxe_texture.dart';

class TpixScreenBackground extends StatelessWidget {
  final Widget child;

  /// หน้าตั้งค่าใช้ไล่สีอีกแบบ (เรเดียลตอนธีมคลาสสิกมืด)
  final bool settings;

  /// ปิดลายเฉพาะหน้าที่ต้องการพื้นเรียบจริง ๆ (เช่น สแปลช/ออนบอร์ด)
  final bool showTexture;

  const TpixScreenBackground({
    super.key,
    required this.child,
    this.settings = false,
    this.showTexture = true,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Stack(
      children: [
        // ── ไล่สีพื้นตามธีมปัจจุบัน ──
        Positioned.fill(
          child: DecoratedBox(decoration: settings ? c.settingsBg : c.screenBg),
        ),

        // ── ลายพื้นผิว guilloché — วาดด้วยโค้ด จึงคมทุกความละเอียด ──
        if (showTexture)
          Positioned.fill(
            child: LuxeTexture(
              isDark: isDark,
              // เส้นสีอ่อนบนพื้นมืด / เส้นสีเข้มบนพื้นสว่าง
              lineColor: isDark ? Colors.white : c.text,
            ),
          ),

        // ── เนื้อหาของหน้า ──
        Positioned.fill(child: child),
      ],
    );
  }
}
