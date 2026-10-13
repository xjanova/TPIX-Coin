/// TPIX Wallet — แถบแท็บแบบหลุม + ปุ่มนูนเลื่อนตาม (ธีม Obsidian)
///
/// ตาม A-Bridge.dc.html: หลุมดำ .35 มน 18 ขอบใน 4px · แท็บที่เลือกเป็นปุ่มนูนสีเข้ม
/// ปุ่มนูนเลื่อนไปหาแท็บที่แตะ (ไม่กะพริบ) · กดแท็บที่เลือกอยู่แล้ว = ไม่ยิงซ้ำ
///
/// Developed by Xman Studio
library;

import 'package:flutter/material.dart';

import '../../core/themes/obsidian_tokens.dart';
import 'obsidian_cards.dart';
import 'obsidian_panel.dart';

@immutable
class ObsidianSegmentOption<T> {
  final T value;
  final String label;

  /// โลโก้/ไอคอนหน้าป้าย (เช่น โลโก้ USDT 22px)
  final Widget? leading;

  const ObsidianSegmentOption(this.value, this.label, {this.leading});
}

class ObsidianSegmented<T> extends StatelessWidget {
  final List<ObsidianSegmentOption<T>> options;
  final T value;

  /// null = ปิดทั้งแถบ (เช่น ระหว่างส่งธุรกรรม)
  final ValueChanged<T>? onChanged;

  final double height;
  final double fontSize;

  const ObsidianSegmented({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.height = 40,
    this.fontSize = 14,
  });

  @override
  Widget build(BuildContext context) {
    final st = ObsidianStyle.of(context);
    final index = options.indexWhere((o) => o.value == value);
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    return CustomPaint(
      painter: const ObsidianSurfacePainter(ObsidianCards.well),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: SizedBox(
          height: height,
          child: LayoutBuilder(
            builder: (context, box) {
              final w = box.maxWidth / options.length;
              return Stack(
                children: [
                  if (index >= 0)
                    AnimatedPositioned(
                      duration: reduce ? Duration.zero : const Duration(milliseconds: 280),
                      curve: Curves.easeOutCubic,
                      left: w * index,
                      width: w,
                      top: 0,
                      bottom: 0,
                      child: const CustomPaint(painter: ObsidianSurfacePainter(ObsidianCards.segment)),
                    ),
                  Row(
                    children: [
                      for (final o in options)
                        Expanded(
                          child: Semantics(
                            inMutuallyExclusiveGroup: true,
                            selected: o.value == value,
                            button: true,
                            enabled: onChanged != null,
                            label: o.label,
                            excludeSemantics: true,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: onChanged == null || o.value == value ? null : () => onChanged!(o.value),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 6),
                                child: Center(
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (o.leading != null) ...[o.leading!, const SizedBox(width: 8)],
                                        Text(
                                          o.label,
                                          maxLines: 1,
                                          style: st.ui(
                                            fontSize: fontSize,
                                            fontWeight: o.value == value ? FontWeight.w600 : FontWeight.w400,
                                            color: o.value == value ? ObsidianColors.text : ObsidianColors.textSec,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
