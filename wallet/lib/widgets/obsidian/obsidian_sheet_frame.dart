/// TPIX Wallet — กรอบแผ่นล่าง (bottom sheet) ของธีม Obsidian
///
/// สูตรเดียวกับแผ่นแจ้งเตือนของหน้าแรก: พื้นทึบ #12141B มนบน 28 · ที่จับ 40x4 ขาว 18%
/// ทึบเพราะลอยทับเนื้อหา (กระจกโปร่งจะอ่านตัวเลข/ที่อยู่ยาก)
///
/// - ดันขึ้นพ้นคีย์บอร์ดเอง (ช่องกรอกในแผ่น)
/// - สูงเกิน [maxHeightFactor] ของจอ = เลื่อนในแผ่นได้
///
/// Developed by Xman Studio
library;

import 'package:flutter/material.dart';

import '../../core/themes/obsidian_tokens.dart';

class ObsidianModalSheet extends StatelessWidget {
  final String? title;

  /// ของท้ายหัวข้อ (เช่น ปุ่ม "เพิ่ม" / ตัวนับ)
  final Widget? titleTrailing;

  final List<Widget> children;

  final double maxHeightFactor;

  /// ระยะขอบเนื้อหา (ไม่รวมขอบล่างของเครื่อง — ใส่ให้เอง)
  final EdgeInsets padding;

  const ObsidianModalSheet({
    super.key,
    this.title,
    this.titleTrailing,
    required this.children,
    this.maxHeightFactor = 0.9,
    this.padding = const EdgeInsets.fromLTRB(20, 12, 20, 20),
  });

  /// ที่จับด้านบน (ใช้แยกได้ถ้าเนื้อหาไม่ได้อยู่ในกรอบนี้)
  static Widget handle() => Center(
        child: Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );

  /// เปิดแผ่นแบบมาตรฐานของธีม (พื้นโปร่ง ให้กรอบนี้วาดเอง)
  static Future<T?> show<T>(BuildContext context, {required WidgetBuilder builder}) =>
      showModalBottomSheet<T>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: builder,
      );

  @override
  Widget build(BuildContext context) {
    final st = ObsidianStyle.of(context);
    final mq = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: Container(
        constraints: BoxConstraints(maxHeight: mq.size.height * maxHeightFactor),
        decoration: const BoxDecoration(
          color: ObsidianColors.card,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          // ขอบบนสะท้อนแสงบาง ๆ แยกแผ่นออกจากพื้นหลังที่มืดเท่ากัน
          border: Border(top: BorderSide(color: Color(0x14FFFFFF))),
        ),
        child: SingleChildScrollView(
          padding: padding.copyWith(bottom: padding.bottom + mq.viewPadding.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              handle(),
              if (title != null) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title!,
                        style: st.ui(fontSize: 18, fontWeight: FontWeight.w600, color: ObsidianColors.text),
                      ),
                    ),
                    ?titleTrailing,
                  ],
                ),
                const SizedBox(height: 14),
              ] else
                const SizedBox(height: 12),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

/// แถว "หัวข้อ : ค่า" ในแผ่นยืนยัน/รายละเอียด
///
/// [selectable] = ค่ายาว (ที่อยู่สัญญา/แฮช) ต้องตรวจได้ทุกตัวอักษร — ตัดบรรทัด ไม่ตัดเป็น …
class ObsidianDetailRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final bool mono;
  final bool selectable;
  final Widget? leading;
  final VoidCallback? onTap;

  /// ไอคอนท้ายค่า (เช่น คัดลอก)
  final IconData? trailingIcon;

  const ObsidianDetailRow({
    super.key,
    required this.label,
    required this.value,
    this.valueColor,
    this.mono = false,
    this.selectable = false,
    this.leading,
    this.onTap,
    this.trailingIcon,
  });

  @override
  Widget build(BuildContext context) {
    final st = ObsidianStyle.of(context);
    final style = mono
        ? st.mono(fontSize: 13, color: valueColor ?? ObsidianColors.text)
        : st.ui(fontSize: 14, fontWeight: FontWeight.w500, color: valueColor ?? ObsidianColors.text);
    final text = selectable
        ? SelectableText(value, textAlign: TextAlign.end, style: style)
        : Text(value, textAlign: TextAlign.end, style: style);
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: st.ui(fontSize: 13.5, color: ObsidianColors.textMuted)),
          const SizedBox(width: 14),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (leading != null) ...[leading!, const SizedBox(width: 6)],
                Flexible(child: text),
                if (trailingIcon != null) ...[
                  const SizedBox(width: 6),
                  Icon(trailingIcon, size: 14, color: ObsidianColors.textMuted),
                ],
              ],
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return row;
    return GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap, child: row);
  }
}

/// โน้ตเตือนสั้น ๆ (ไอคอน + ข้อความสี)
class ObsidianNote extends StatelessWidget {
  final String text;
  final Color color;
  final IconData icon;

  const ObsidianNote({
    super.key,
    required this.text,
    this.color = ObsidianColors.warning,
    this.icon = Icons.info_outline_rounded,
  });

  @override
  Widget build(BuildContext context) {
    final st = ObsidianStyle.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: st.ui(fontSize: 12.5, height: 1.45, color: color))),
        ],
      ),
    );
  }
}
