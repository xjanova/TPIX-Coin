/// TPIX Wallet — ม่านมืดของหน้าย่อยในธีม Obsidian
///
/// พื้นหลังคลิปของทั้งแอป (ObsidianBackground) ตั้งค่าตามหน้าแรก (Main.dc.html: คลิปเต็มความสว่าง
/// ไล่มืด .05 → .40@250 → .92@500) แต่ mock ของหน้าย่อย (A-Swap / A-Bridge) ใช้คลิปจาง .7
/// เลื่อนขึ้น 140px และไล่มืด .35 → .88@260 → ทึบ@420
///
/// ม่านนี้วางไว้ชั้นล่างสุดของหน้าย่อย ให้ความมืดรวมเท่ากับ mock ของหน้าย่อย
///   alpha ที่ต้องเติม s = 1 − (1 − มืดของหน้าย่อย) / (1 − มืดของหน้าแรก)
///   → .52@0 · .65@130 · .855@260 · .90@340 · ทึบ@420 (บนจอสูง 844)
/// สัดส่วนผูกกับความสูงจอเหมือนตัวพื้นหลัง (จอสูง/เตี้ยกว่า mock ก็ได้ภาพเดียวกัน)
///
/// Developed by Xman Studio
library;

import 'package:flutter/material.dart';

import '../../core/themes/obsidian_tokens.dart';

/// ขอบบนของรายการที่เลื่อนลอดใต้หัวหน้า — จางลงนุ่ม ๆ แทนขอบตัดคม
class ObsidianTopFade extends StatelessWidget {
  final Widget child;
  final double height;

  const ObsidianTopFade({super.key, required this.child, this.height = 16});

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (rect) => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: const [Color(0x00000000), Color(0xFF000000)],
        stops: [0, rect.height <= 0 ? 0 : (height / rect.height).clamp(0.0, 1.0)],
      ).createShader(rect),
      child: child,
    );
  }
}

class ObsidianPageScrim extends StatelessWidget {
  const ObsidianPageScrim({super.key});

  static const _h = 844.0;

  static final gradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      ObsidianColors.ground.withValues(alpha: 0.52),
      ObsidianColors.ground.withValues(alpha: 0.65),
      ObsidianColors.ground.withValues(alpha: 0.855),
      ObsidianColors.ground.withValues(alpha: 0.90),
      ObsidianColors.ground,
    ],
    stops: const [0, 130 / _h, 260 / _h, 340 / _h, 420 / _h],
  );

  @override
  Widget build(BuildContext context) {
    // ผูกกับความสูงจอ ไม่ใช่ความสูงของพื้นที่วาง (คีย์บอร์ดเด้งแล้วม่านต้องไม่ยืด/หด)
    final h = MediaQuery.sizeOf(context).height;
    return IgnorePointer(
      child: OverflowBox(
        alignment: Alignment.topCenter,
        minHeight: h,
        maxHeight: h,
        child: DecoratedBox(
          decoration: BoxDecoration(gradient: gradient),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}
