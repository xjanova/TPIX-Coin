/// TPIX Wallet — หัวหน้าย่อยของธีม Obsidian (A-Node.dc.html)
///
/// grid `46px | 1fr | 46px`: ปุ่มกระจกย้อนกลับ 46x46 · หัวข้อกลาง 18/600 · ปุ่มขวา (ไม่บังคับ)
/// ช่องขวาว่างก็ยังกินที่ 46 ให้หัวข้ออยู่กึ่งกลางจอจริง
///
/// Developed by Xman Studio
library;

import 'package:flutter/material.dart';

import '../../core/themes/obsidian_tokens.dart';
import 'obsidian_panel.dart';

class ObsidianPageHeader extends StatelessWidget {
  final String title;

  /// null = Navigator.maybePop
  final VoidCallback? onBack;
  final String backSemantics;

  /// ปุ่มขวา 46x46 (เช่น วิธีใช้) — ใช้ [ObsidianHeaderTile]
  final Widget? trailing;

  /// ของเล็ก ๆ ใต้หัวข้อ (เช่น วงหมุนตอนรีเฟรช)
  final Widget? subtitle;

  const ObsidianPageHeader({
    super.key,
    required this.title,
    this.onBack,
    this.backSemantics = 'Back',
    this.trailing,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final st = ObsidianStyle.of(context);
    return Row(
      children: [
        ObsidianHeaderTile(
          semanticLabel: backSemantics,
          onTap: onBack ?? () => Navigator.maybePop(context),
          child: const Icon(Icons.chevron_left_rounded, size: 26, color: ObsidianColors.text),
        ),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(
                header: true,
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: st.ui(fontSize: 18, fontWeight: FontWeight.w600, color: ObsidianColors.text),
                ),
              ),
              ?subtitle,
            ],
          ),
        ),
        trailing ?? const SizedBox(width: 46, height: 46),
      ],
    );
  }
}

/// ปุ่มกระจกนูน 46x46 มน 16 (หัวหน้า)
class ObsidianHeaderTile extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final String semanticLabel;

  const ObsidianHeaderTile({
    super.key,
    required this.child,
    required this.onTap,
    required this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    return ObsidianPanel(
      surface: ObsidianSurface.raised,
      blur: 14,
      width: 46,
      height: 46,
      onTap: onTap,
      semanticLabel: semanticLabel,
      child: Center(child: child),
    );
  }
}
