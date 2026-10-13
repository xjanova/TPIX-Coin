/// TPIX Wallet — กลุ่มรายการแบบแผงกระจก (หน้าตั้งค่า / กิจกรรม) ของธีม Obsidian
///
/// พอร์ตจาก A-Settings.dc.html / A-Activity.dc.html:
///   - หัวกลุ่ม 12.5/600 สี #8E94A2
///   - แผงมน 20 ไล่ขาว 6%→2% + ไฮไลต์ขอบบน + เงาขอบล่าง (ตั้งค่าไม่มีเงานอก · กิจกรรมมี)
///   - แถว: ไอคอน 3D 32 · ชื่อ 14.5 · ค่าด้านขวา 13 สี #A3A8B4 · ลูกศร #6B7280
///   - เส้นคั่น 1px ขาว 6% เว้นซ้ายให้ตรงแนวข้อความ
///
/// Developed by Xman Studio
library;

import 'package:flutter/material.dart';

import '../../core/themes/obsidian_tokens.dart';
import 'icon_3d.dart';
import 'obsidian_panel.dart';

/// หัวกลุ่มเล็ก (ทั่วไป / ความปลอดภัย / วันนี้ …)
class ObsidianSectionLabel extends StatelessWidget {
  final String text;
  final Widget? trailing;
  final EdgeInsets padding;

  const ObsidianSectionLabel(
    this.text, {
    super.key,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(4, 6, 4, 0),
  });

  @override
  Widget build(BuildContext context) {
    final st = ObsidianStyle.of(context);
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                text,
                style: st.ui(fontSize: 12.5, fontWeight: FontWeight.w600, color: ObsidianColors.textMuted),
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// แผงที่รวมหลายแถว + เส้นคั่นอัตโนมัติ
class ObsidianListGroup extends StatelessWidget {
  final List<Widget> children;

  /// ระยะซ้ายของเส้นคั่น (ไอคอน 32 + ขอบ 14 + ช่องว่าง 12 = 58)
  final double dividerIndent;

  /// ระยะขวาของเส้นคั่น (กิจกรรมเว้น 14 · ตั้งค่าชิดขอบ)
  final double dividerEndIndent;

  /// เงานอกแบบแผงเนื้อหา (กิจกรรม) — หน้าตั้งค่าใน mock ไม่มี
  final bool shadow;

  final double radius;

  /// ระยะบน-ล่างในแผง (ตั้งค่า 2 · กิจกรรม 4)
  final double verticalPadding;

  const ObsidianListGroup({
    super.key,
    required this.children,
    this.dividerIndent = 58,
    this.dividerEndIndent = 0,
    this.shadow = false,
    this.radius = 20,
    this.verticalPadding = 2,
  });

  @override
  Widget build(BuildContext context) {
    final surface = ObsidianSurface(
      radius: radius,
      gradient: ObsidianSurface.panel.gradient,
      topHighlight: ObsidianSurface.panel.topHighlight,
      bottomShade: ObsidianSurface.panel.bottomShade,
      shadows: shadow ? ObsidianSurface.panel.shadows : const [],
    );
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) {
        rows.add(Container(
          height: 1,
          margin: EdgeInsets.only(left: dividerIndent, right: dividerEndIndent),
          color: const Color(0x0FFFFFFF), // ขาว 6%
        ));
      }
      rows.add(children[i]);
    }
    return ObsidianPanel(
      surface: surface,
      padding: EdgeInsets.symmetric(vertical: verticalPadding),
      child: Column(mainAxisSize: MainAxisSize.min, children: rows),
    );
  }
}

/// หนึ่งแถวในกลุ่ม
class ObsidianListRow extends StatelessWidget {
  /// ไอคอน 3D (ObsidianIcons.*) — หรือใส่ [leading] เอง
  final String? icon;
  final Widget? leading;
  final double iconSize;

  final String title;
  final Color? titleColor;
  final String? subtitle;

  /// ค่าด้านขวา (ไทย / Obsidian / v1.13.38)
  final String? value;

  /// ของด้านขวาแทน/ต่อจาก [value] (สวิตช์ / ป้าย)
  final Widget? trailing;

  /// ลูกศรขวา — null = ใส่ให้เองเมื่อกดได้และไม่มี [trailing]
  final bool? chevron;

  final VoidCallback? onTap;
  final String? semanticLabel;

  const ObsidianListRow({
    super.key,
    this.icon,
    this.leading,
    this.iconSize = 32,
    required this.title,
    this.titleColor,
    this.subtitle,
    this.value,
    this.trailing,
    this.chevron,
    this.onTap,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    final st = ObsidianStyle.of(context);
    final showChevron = chevron ?? (onTap != null && trailing == null);
    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          if (leading != null)
            leading!
          else if (icon != null)
            Icon3D(icon!, size: iconSize),
          if (leading != null || icon != null) const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: st.ui(fontSize: 14.5, color: titleColor ?? ObsidianColors.text, height: 1.35),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: st.ui(fontSize: 12, color: ObsidianColors.textMuted, height: 1.35),
                  ),
              ],
            ),
          ),
          if (value != null) ...[
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 150),
              child: Text(
                value!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: st.ui(fontSize: 13, color: ObsidianColors.textSec),
              ),
            ),
          ],
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
          if (showChevron) ...[
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right_rounded, size: 20, color: Color(0xFF6B7280)),
          ],
        ],
      ),
    );
    if (onTap == null) {
      return Semantics(label: semanticLabel, container: true, child: row);
    }
    return ObsidianPressable(
      onTap: onTap,
      semanticLabel: semanticLabel ?? title,
      pressedScale: 0.985,
      child: row,
    );
  }
}

/// ป้ายสถานะเล็กแบบเม็ดยา (สำรองแล้ว / ใช้งาน / Imported)
class ObsidianBadge extends StatelessWidget {
  final String text;
  final Color color;

  const ObsidianBadge(this.text, {super.key, this.color = ObsidianColors.successSoft});

  @override
  Widget build(BuildContext context) {
    final st = ObsidianStyle.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(text, style: st.ui(fontSize: 11.5, fontWeight: FontWeight.w500, color: color)),
    );
  }
}
