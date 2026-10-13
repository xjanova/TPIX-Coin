/// TPIX Wallet — โลโก้ TPIX ในจานแก้วมืด + วงแหวนไล่สีหมุน (ธีม Obsidian)
///
/// ใช้กับหน้าเปิดแอป / หน้าต้อนรับ — โลโก้เป็น path เวกเตอร์ทางการ (TpixMonogramPainter)
/// วงแหวนแบบเดียวกับปุ่มสแกนของแถบเมนู (conic cyan → violet → orange)
/// [spin] = 0..1 ของรอบหมุน (ผู้เรียกคุมแอนิเมชันเอง · ปิดภาพเคลื่อนไหวก็ส่งค่าคงที่)
///
/// Developed by Xman Studio
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/themes/obsidian_tokens.dart';
import 'chain_emblem.dart';

class ObsidianBrandOrb extends StatelessWidget {
  final double size;
  final double spin;

  const ObsidianBrandOrb({super.key, this.size = 140, this.spin = 0});

  @override
  Widget build(BuildContext context) {
    final ring = size * 0.035;
    return SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(color: ObsidianColors.violet.withValues(alpha: 0.45), blurRadius: size * 0.35, spreadRadius: size * 0.04),
            BoxShadow(color: ObsidianColors.cyan.withValues(alpha: 0.18), blurRadius: size * 0.6, spreadRadius: size * 0.1),
          ],
        ),
        child: ClipOval(
          child: Stack(
            fit: StackFit.expand,
            children: [
              Transform.rotate(
                angle: spin * 2 * math.pi,
                child: const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: SweepGradient(
                      colors: [ObsidianColors.cyan, ObsidianColors.violet, ObsidianColors.orange, ObsidianColors.cyan],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.all(ring),
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      center: Alignment(0, -0.3),
                      colors: [Color(0xFF1E2230), Color(0xFF0A0B10)],
                      stops: [0, 0.7],
                    ),
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(size * 0.2),
                    child: CustomPaint(painter: TpixMonogramPainter(glow: ObsidianColors.violet, glowBlur: size * 0.1)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
