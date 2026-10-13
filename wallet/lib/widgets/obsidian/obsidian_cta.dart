/// TPIX Wallet — ปุ่มหลักแบบ "ยกนูน + สถานะกดไม่ได้" ของธีม Obsidian (A-Node.dc.html)
///
/// ต่างจาก ObsidianButton ตรงที่:
///   - เงาเรืองใต้ปุ่มเป็นสีที่กำหนดได้ (เช่น สีประจำระดับโหนด) แทนม่วงตายตัว
///   - กดไม่ได้ = ปุ่มเข้มทึบ ตัวอักษร #A3A8B4 (ไม่ใช่ปุ่มขาวจาง 45%) ตาม mock
///     และแตะได้ถ้าส่ง [onDisabledTap] มา (เช่น บอกเหตุผลที่กดไม่ได้)
///
/// กดซ้ำระหว่าง [loading] ไม่ยิง callback ซ้ำ
///
/// Developed by Xman Studio
library;

import 'package:flutter/material.dart';

import '../../core/themes/obsidian_tokens.dart';
import 'obsidian_panel.dart';

class ObsidianCta extends StatelessWidget {
  final String label;

  /// null = กดไม่ได้
  final VoidCallback? onPressed;

  /// แตะตอนกดไม่ได้ (ไม่บังคับ)
  final VoidCallback? onDisabledTap;

  final bool loading;

  /// สีเงาเรืองใต้ปุ่มตอนกดได้ (null = ม่วงของแบรนด์)
  final Color? glow;

  final double height;

  const ObsidianCta({
    super.key,
    required this.label,
    required this.onPressed,
    this.onDisabledTap,
    this.loading = false,
    this.glow,
    this.height = 58,
  });

  @override
  Widget build(BuildContext context) {
    final st = ObsidianStyle.of(context);
    final enabled = onPressed != null;
    final surface = enabled
        ? ObsidianSurface.primaryButton.copyWith(shadows: [
            CssShadow(0, 18, 34, -12, glow ?? const Color(0xA68B5CF6)),
            const CssShadow(0, 10, 20, -10, Color(0xE6000000)),
          ])
        : const ObsidianSurface(
            radius: 19,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [ObsidianColors.darkTop, ObsidianColors.darkBottom],
            ),
            topHighlight: Color(0x1AFFFFFF),
          );
    final fg = enabled ? const Color(0xFF0A0B0F) : ObsidianColors.textSec;
    final content = loading
        ? SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: fg))
        : Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: st.ui(fontSize: 16.5, fontWeight: FontWeight.w600, color: fg),
          );
    final tap = loading ? null : (enabled ? onPressed : onDisabledTap);
    return ObsidianPressable(
      onTap: tap,
      pressedScale: enabled ? 0.97 : 1,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        child: SizedBox(
          key: ValueKey(enabled),
          height: height,
          width: double.infinity,
          child: CustomPaint(
            painter: ObsidianSurfacePainter(surface),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: content,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
