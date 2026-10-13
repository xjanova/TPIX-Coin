/// TPIX Wallet — แผ่นเลื่อนขึ้น + กล่องยืนยันของธีม Obsidian
///
/// แผ่นทึบ (#12141B) มนบน 28 มีขีดจับ — ทึบเพราะลอยทับเนื้อหา ต้องอ่านง่ายเสมอ
/// กล่องยืนยัน: ปุ่ม "ยกเลิก" เป็นปุ่มเข้ม · ปุ่มยืนยันเป็นปุ่มขาวนูน
/// (ถ้าเป็นการลบ/ทำลาย [danger] = ป้ายยืนยันสีแดง)
///
/// Developed by Xman Studio
library;

import 'package:flutter/material.dart';

import '../../core/themes/obsidian_tokens.dart';
import '../../core/themes/tokens.dart';
import 'obsidian_button.dart';

/// เปิดแผ่นเลื่อนขึ้นแบบ Obsidian
Future<T?> showObsidianSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  String? title,
  bool isDismissible = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    isDismissible: isDismissible,
    enableDrag: isDismissible,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0x99000000),
    builder: (ctx) => ObsidianSheetFrame(title: title, child: builder(ctx)),
  );
}

/// กรอบแผ่น: ขีดจับ + หัวข้อ + เนื้อหา (สูงไม่เกิน 90% ของจอ · เลื่อนได้ · หลบคีย์บอร์ด)
class ObsidianSheetFrame extends StatelessWidget {
  final String? title;
  final Widget child;

  const ObsidianSheetFrame({super.key, this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final st = ObsidianStyle.of(context);
    final mq = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: Container(
        constraints: BoxConstraints(maxHeight: mq.size.height * 0.9),
        decoration: const BoxDecoration(
          color: ObsidianColors.card,
          borderRadius: BorderRadius.vertical(top: Radius.circular(TpixRadius.sheet)),
          border: Border(top: BorderSide(color: Color(0x1FFFFFFF))),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                if (title != null) ...[
                  Text(
                    title!,
                    style: st.ui(fontSize: 18, fontWeight: FontWeight.w600, color: ObsidianColors.text),
                  ),
                  const SizedBox(height: 14),
                ],
                child,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// กล่องยืนยันกลางจอ — คืน true เมื่อกดยืนยันเท่านั้น (ปัดทิ้ง/ยกเลิก = false)
Future<bool> showObsidianConfirmDialog(
  BuildContext context, {
  required String title,
  required String body,
  required String confirmLabel,
  required String cancelLabel,
  bool danger = false,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    barrierColor: const Color(0x99000000),
    builder: (ctx) {
      final st = ObsidianStyle.of(ctx);
      return Dialog(
        backgroundColor: ObsidianColors.card,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: const BorderSide(color: Color(0x1AFFFFFF)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                style: st.ui(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: danger ? ObsidianColors.dangerSoft : ObsidianColors.text,
                ),
              ),
              const SizedBox(height: 10),
              Flexible(
                child: SingleChildScrollView(
                  child: Text(body, style: st.ui(fontSize: 13.5, height: 1.5, color: ObsidianColors.textSec)),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: ObsidianButton.secondary(
                      label: cancelLabel,
                      height: 48,
                      onPressed: () => Navigator.pop(ctx, false),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: danger
                        ? _DangerButton(label: confirmLabel, onPressed: () => Navigator.pop(ctx, true))
                        : ObsidianButton(label: confirmLabel, height: 48, onPressed: () => Navigator.pop(ctx, true)),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
  return ok == true;
}

/// ปุ่มเข้มป้ายแดง (ยืนยันการลบ) — ไม่ใช้ปุ่มขาวเด่นเพื่อไม่ชวนกดผิด
class _DangerButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;

  const _DangerButton({required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return ObsidianButton.secondary(
      label: label,
      height: 48,
      onPressed: onPressed,
      labelColor: ObsidianColors.dangerSoft,
    );
  }
}
