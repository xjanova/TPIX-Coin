/// TPIX Wallet — ปุ่มของธีม Obsidian
///
/// - primary: ปุ่มขาวนูน ตัวอักษรดำ เงาม่วงใต้ปุ่ม (ตรวจสอบก่อนส่ง / ยืนยัน)
/// - secondary: ปุ่มเข้มทึบ (ยกเลิก / ตัวเลือกรอง)
///
/// กดซ้ำระหว่างกำลังทำงาน ([loading]) ไม่ยิง callback ซ้ำ — กันส่งธุรกรรมสองรอบ
///
/// Developed by Xman Studio
library;

import 'package:flutter/material.dart';

import '../../core/themes/obsidian_tokens.dart';
import 'obsidian_panel.dart';

enum ObsidianButtonKind { primary, secondary }

class ObsidianButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final ObsidianButtonKind kind;

  /// ไอคอนท้ายป้าย (เช่น ลูกศรขวา)
  final IconData? trailingIcon;

  /// กำลังทำงาน — โชว์วงหมุนแทนป้าย และไม่รับการกด
  final bool loading;

  final double height;

  const ObsidianButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.kind = ObsidianButtonKind.primary,
    this.trailingIcon,
    this.loading = false,
    this.height = 58,
  });

  const ObsidianButton.secondary({
    super.key,
    required this.label,
    required this.onPressed,
    this.trailingIcon,
    this.loading = false,
    this.height = 52,
  }) : kind = ObsidianButtonKind.secondary;

  @override
  Widget build(BuildContext context) {
    final primary = kind == ObsidianButtonKind.primary;
    final enabled = onPressed != null && !loading;
    final fg = primary ? const Color(0xFF0A0B0F) : ObsidianColors.textSoft;
    final text = ObsidianStyle.of(context).ui.copyWith(
          fontSize: primary ? 16.5 : 15,
          fontWeight: FontWeight.w600,
          color: fg,
        );

    final content = loading
        ? SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.4, color: fg),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text,
                ),
              ),
              if (trailingIcon != null) ...[
                const SizedBox(width: 10),
                Icon(trailingIcon, size: 18, color: fg),
              ],
            ],
          );

    final surface = primary
        ? ObsidianSurface.primaryButton
        : ObsidianSurface.dark.copyWith(radius: 17);

    return AnimatedOpacity(
      opacity: onPressed == null ? 0.45 : 1,
      duration: const Duration(milliseconds: 200),
      child: ObsidianPressable(
        onTap: enabled ? onPressed : null,
        semanticLabel: label,
        child: SizedBox(
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
