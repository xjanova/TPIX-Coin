/// TPIX Wallet — หัวหน้าของหน้าย่อยในธีม Obsidian
///
/// ตาม mock (A-Swap / A-Bridge): grid 46 · 1fr · 46 — ปุ่มย้อนกลับกระจกนูน 46x46 ซ้าย
/// ชื่อหน้า 18px กลางจอ ปุ่มไอคอน 3D ขวา (ไม่มีปุ่มขวา = เว้นที่ไว้ให้ชื่ออยู่กลางจริง)
///
/// Developed by Xman Studio
library;

import 'package:flutter/material.dart';

import '../../core/themes/obsidian_tokens.dart';
import 'icon_3d.dart';
import 'obsidian_panel.dart';

/// ปุ่มกระจกนูน 46x46 มน 16 (ไอคอน 3D 28px หรือไอคอนเส้น)
class ObsidianHeaderTile extends StatelessWidget {
  final String? asset;
  final IconData? icon;
  final String label;
  final VoidCallback? onTap;

  /// จุดส้มมุมขวาบน (มีเรื่องรอให้ดู)
  final bool dot;

  /// เบลอสิ่งที่อยู่ด้านหลัง — หน้าย่อยใน mock ไม่เบลอ (0)
  final double blur;

  const ObsidianHeaderTile({
    super.key,
    this.asset,
    this.icon,
    required this.label,
    required this.onTap,
    this.dot = false,
    this.blur = 0,
  }) : assert(asset != null || icon != null);

  /// ปุ่มย้อนกลับ (ลูกศรเส้น ตาม mock)
  const ObsidianHeaderTile.back({super.key, required this.label, required this.onTap, this.blur = 0})
    : asset = null,
      icon = Icons.chevron_left_rounded,
      dot = false;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onTap == null ? 0.45 : 1,
      child: ObsidianPanel(
        surface: ObsidianSurface.raised,
        blur: blur,
        width: 46,
        height: 46,
        onTap: onTap,
        semanticLabel: label,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            const SizedBox.expand(),
            Center(child: asset != null ? Icon3D(asset!, size: 28) : Icon(icon, size: 28, color: ObsidianColors.text)),
            if (dot)
              Positioned(
                top: 9,
                right: 10,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: ObsidianColors.orange,
                    boxShadow: [
                      BoxShadow(color: Color(0xFF10131A), spreadRadius: 2),
                      BoxShadow(color: ObsidianColors.orange, blurRadius: 8),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// แถวหัวหน้า: [ย้อนกลับ] ชื่อหน้า (+คำอธิบายสั้น) [ปุ่มขวา]
class ObsidianPageHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String backLabel;

  /// null = Navigator.maybePop
  final VoidCallback? onBack;

  /// ปุ่มขวา (ปกติ [ObsidianHeaderTile]) — null = ช่องว่างขนาดเท่ากัน
  final Widget? trailing;

  const ObsidianPageHeader({
    super.key,
    required this.title,
    required this.backLabel,
    this.subtitle,
    this.onBack,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final st = ObsidianStyle.of(context);
    return Row(
      children: [
        ObsidianHeaderTile.back(label: backLabel, onTap: onBack ?? () => Navigator.maybePop(context)),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(
                header: true,
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: st.ui(fontSize: 18, fontWeight: FontWeight.w600, color: ObsidianColors.text, height: 1.3),
                ),
              ),
              if (subtitle != null)
                Text(
                  subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: st.ui(fontSize: 11.5, color: ObsidianColors.textMuted, height: 1.3),
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        trailing ?? const SizedBox(width: 46, height: 46),
      ],
    );
  }
}
