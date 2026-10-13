/// TPIX Wallet — ชิปตัวกรอง + ปุ่มเม็ดยาของธีม Obsidian (A-Activity.dc.html)
///
/// ชิป (สูง 34 มนเต็ม):
///   เลือกอยู่ = ขาวไล่ #FFF→#D9DCE3 ตัวอักษรดำ 13/600
///   ไม่ได้เลือก = เข้ม #232733→#161920 + ไฮไลต์บน 12% ตัวอักษร #C9CCD4
/// ปุ่มเม็ดยา (สูง 38) = กระจกนูนแบบปุ่มหัวหน้า (ใช้กับ "ทุกเชน ▾")
///
/// Developed by Xman Studio
library;

import 'package:flutter/material.dart';

import '../../core/themes/obsidian_tokens.dart';
import 'obsidian_panel.dart';

class ObsidianFilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const ObsidianFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  static const _on = ObsidianSurface(
    radius: 17,
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFFFFFFFF), Color(0xFFD9DCE3)],
    ),
  );

  static const _off = ObsidianSurface(
    radius: 17,
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [ObsidianColors.darkTop, ObsidianColors.darkBottom],
    ),
    topHighlight: Color(0x1FFFFFFF),
  );

  @override
  Widget build(BuildContext context) {
    final st = ObsidianStyle.of(context);
    return Semantics(
      selected: selected,
      inMutuallyExclusiveGroup: true,
      child: ObsidianPressable(
        onTap: selected ? null : onTap,
        semanticLabel: label,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: SizedBox(
            key: ValueKey(selected),
            height: 34,
            child: CustomPaint(
              painter: ObsidianSurfacePainter(selected ? _on : _off),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Center(
                  widthFactor: 1,
                  child: Text(
                    label,
                    maxLines: 1,
                    style: st.ui(
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                      color: selected ? const Color(0xFF0A0B0F) : ObsidianColors.chrome,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// ปุ่มเม็ดยากระจกนูน (สูง 38) — ไอคอน/โลโก้นำหน้าได้ + ลูกศรลง
class ObsidianPillButton extends StatelessWidget {
  final String label;
  final Widget? leading;
  final VoidCallback onTap;
  final String? semanticLabel;
  final bool showChevron;

  const ObsidianPillButton({
    super.key,
    required this.label,
    required this.onTap,
    this.leading,
    this.semanticLabel,
    this.showChevron = true,
  });

  @override
  Widget build(BuildContext context) {
    final st = ObsidianStyle.of(context);
    return ObsidianPanel(
      surface: ObsidianSurface.raised.copyWith(radius: 19),
      height: 38,
      onTap: onTap,
      semanticLabel: semanticLabel ?? label,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 6)],
          Text(label, style: st.ui(fontSize: 13, color: ObsidianColors.text)),
          if (showChevron) ...[
            const SizedBox(width: 6),
            const Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: ObsidianColors.chrome),
          ],
        ],
      ),
    );
  }
}
