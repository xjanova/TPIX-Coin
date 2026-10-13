/// TPIX Wallet — สวิตช์ไล่สีของธีม Obsidian (A-Settings.dc.html)
///
/// 52x30 มนเต็ม · ปุ่มกลม 24 ขาวไล่เทา
///   เปิด  = ราง cyan→violet + เรืองม่วง · ปุ่มเลื่อนไปขวา (เด้งเล็กน้อยแบบ mock)
///   ปิด   = รางเข้ม #1B1E27 + เงาจม
/// [busy] = กำลังทำงาน (ถาม PIN/สแกนนิ้ว) → ไม่รับการกดซ้ำ
///
/// Developed by Xman Studio
library;

import 'package:flutter/material.dart';

import '../../core/themes/obsidian_tokens.dart';
import 'obsidian_panel.dart';

class ObsidianSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool busy;
  final String? semanticLabel;

  const ObsidianSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.busy = false,
    this.semanticLabel,
  });

  /// cubic-bezier(.2,.9,.25,1.2) ของ mock — เกิน 1 นิดหน่อยตอนท้าย
  static const _knobCurve = Cubic(0.2, 0.9, 0.25, 1.2);

  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null && !busy;
    return Semantics(
      toggled: value,
      enabled: enabled,
      label: semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? () => onChanged!(!value) : null,
        // พื้นที่กดใหญ่กว่าตัวสวิตช์ (ขั้นต่ำ 44 ตามแนวทางการเข้าถึง)
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: AnimatedOpacity(
            opacity: onChanged == null ? 0.5 : 1,
            duration: const Duration(milliseconds: 200),
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: value ? 1 : 0),
              duration: const Duration(milliseconds: 300),
              curve: Curves.ease,
              builder: (context, t, _) {
                final track = ObsidianSurface(
                  radius: 15,
                  gradient: LinearGradient(colors: [
                    Color.lerp(const Color(0xFF1B1E27), ObsidianColors.cyan, t)!,
                    Color.lerp(const Color(0xFF1B1E27), ObsidianColors.violet, t)!,
                  ]),
                  ring: Color.lerp(const Color(0x14FFFFFF), const Color(0x00FFFFFF), t),
                  innerShadows: const [CssShadow(0, 1, 3, 0, Color(0x99000000))],
                  shadows: t <= 0
                      ? const []
                      : [CssShadow(0, 0, 14, -2, ObsidianColors.violet.withValues(alpha: 0.9 * t))],
                );
                return SizedBox(
                  width: 52,
                  height: 30,
                  child: CustomPaint(
                    painter: ObsidianSurfacePainter(track),
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(end: value ? 1 : 0),
                      duration: const Duration(milliseconds: 300),
                      curve: _knobCurve,
                      builder: (context, k, _) => Stack(
                        children: [
                          Positioned(
                            left: 3 + 22 * k,
                            top: 3,
                            child: Container(
                              width: 24,
                              height: 24,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [Colors.white, ObsidianColors.chrome],
                                ),
                                boxShadow: [BoxShadow(color: Color(0x99000000), offset: Offset(0, 3), blurRadius: 6)],
                              ),
                              child: busy
                                  ? const Padding(
                                      padding: EdgeInsets.all(5),
                                      child: CircularProgressIndicator(strokeWidth: 2, color: ObsidianColors.violet),
                                    )
                                  : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
