/// TPIX Wallet — ชิ้นส่วนฟอร์มของธีม Obsidian
///
///   - ObsidianTokenPill   ปุ่มเลือกเหรียญแบบแคปซูล (โลโก้ 32 + สัญลักษณ์ + ลูกศรลง)
///   - ObsidianChipButton  ปุ่มชิปเล็ก (25% / 50% / สูงสุด / ใช้ที่อยู่ฉัน)
///   - ObsidianTextField   ช่องกรอกแบบยุบลง + ข้อความผิด/เตือนใต้ช่อง
///   - ObsidianCheckTile   ช่องติ๊กยอมรับ
///   - ObsidianNotice      แผงคำเตือน/สถานะย้อมสีตามโทน
///   - ObsidianKv          แถว ป้าย : ค่า (สูง 34 ตามแผงรายละเอียดของ mock)
///
/// Developed by Xman Studio
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/themes/obsidian_tokens.dart';
import 'obsidian_cards.dart';
import 'obsidian_panel.dart';

/// ปุ่มเลือกเหรียญ — สูง 42 แคปซูลเข้ม (mock: "เลือกเหรียญที่จ่าย")
class ObsidianTokenPill extends StatelessWidget {
  final Widget? logo;
  final String label;
  final VoidCallback? onTap;
  final String? semanticLabel;

  const ObsidianTokenPill({super.key, this.logo, required this.label, required this.onTap, this.semanticLabel});

  @override
  Widget build(BuildContext context) {
    final st = ObsidianStyle.of(context);
    // ตัวอ่านหน้าจอ: "เลือกเหรียญที่จ่าย" + ค่า = เหรียญที่เลือกอยู่
    return Semantics(
      value: semanticLabel == null ? null : label,
      child: ObsidianPressable(
        onTap: onTap,
        semanticLabel: semanticLabel ?? label,
        child: ExcludeSemantics(
          child: CustomPaint(
            painter: const ObsidianSurfacePainter(ObsidianCards.pill),
            child: SizedBox(
              height: 42,
              child: Padding(
                padding: EdgeInsets.fromLTRB(logo == null ? 14 : 5, 0, 10, 0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (logo != null) ...[SizedBox(width: 32, height: 32, child: logo), const SizedBox(width: 8)],
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 96),
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: st.ui(fontSize: 15, fontWeight: FontWeight.w600, color: ObsidianColors.text),
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: ObsidianColors.chrome),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// ปุ่มชิปเล็กสีเข้ม
class ObsidianChipButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final double height;
  final double padding;
  final Color? color;

  const ObsidianChipButton({
    super.key,
    required this.label,
    required this.onTap,
    this.height = 28,
    this.padding = 10,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final st = ObsidianStyle.of(context);
    return Opacity(
      opacity: onTap == null ? 0.45 : 1,
      child: ObsidianPressable(
        onTap: onTap,
        semanticLabel: label,
        pressedScale: 0.94,
        child: CustomPaint(
          painter: const ObsidianSurfacePainter(ObsidianCards.chip),
          child: SizedBox(
            height: height,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: padding),
              child: Center(
                widthFactor: 1,
                child: Text(
                  label,
                  maxLines: 1,
                  style: st.ui(fontSize: 12, fontWeight: FontWeight.w500, color: color ?? ObsidianColors.chrome),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// ช่องกรอกแบบยุบลง (ObsidianSurface.field) — ผิด = วงขอบแดง + ข้อความใต้ช่อง
class ObsidianTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final bool enabled;
  final bool mono;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final String? errorText;
  final String? warningText;
  final Widget? prefix;
  final Widget? suffix;
  final TextStyle? style;

  /// ฟอนต์สำรองเมื่อฟอนต์หลักไม่มีอักษรไทย (เช่น mono + คำค้นภาษาไทย)
  final List<String>? fontFamilyFallback;

  /// บรรทัดสูงสุด — ที่อยู่ยาวใช้ 2 (เห็นครบทุกตัวอักษรโดยไม่ต้องเลื่อน)
  final int maxLines;

  const ObsidianTextField({
    super.key,
    required this.controller,
    required this.hint,
    this.enabled = true,
    this.mono = false,
    this.keyboardType,
    this.inputFormatters,
    this.onChanged,
    this.onSubmitted,
    this.errorText,
    this.warningText,
    this.prefix,
    this.suffix,
    this.style,
    this.fontFamilyFallback,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    final st = ObsidianStyle.of(context);
    final base =
        style ??
        (mono
            ? st.mono(fontSize: 13, fontWeight: FontWeight.w500, color: ObsidianColors.text)
            : st.ui(fontSize: 15, color: ObsidianColors.text));
    final textStyle = fontFamilyFallback == null
        ? base
        : base.copyWith(fontFamilyFallback: [...?base.fontFamilyFallback, ...fontFamilyFallback!]);
    final surface = errorText != null
        ? ObsidianSurface.field.copyWith(radius: 16, ring: ObsidianColors.danger.withValues(alpha: 0.7), ringWidth: 1.2)
        : ObsidianSurface.field.copyWith(radius: 16);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        CustomPaint(
          painter: ObsidianSurfacePainter(surface),
          child: Padding(
            padding: EdgeInsets.only(left: prefix == null ? 14 : 10, right: suffix == null ? 14 : 6),
            child: Row(
              children: [
                if (prefix != null) ...[prefix!, const SizedBox(width: 8)],
                Expanded(
                  child: TextField(
                    controller: controller,
                    enabled: enabled,
                    onChanged: onChanged,
                    onSubmitted: onSubmitted,
                    autocorrect: false,
                    enableSuggestions: false,
                    keyboardType: keyboardType ?? TextInputType.text,
                    inputFormatters: inputFormatters,
                    minLines: 1,
                    maxLines: maxLines,
                    cursorColor: ObsidianColors.cyan,
                    style: textStyle,
                    decoration: InputDecoration(
                      hintText: hint,
                      hintStyle: textStyle.copyWith(color: ObsidianColors.textMuted.withValues(alpha: 0.7)),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                      filled: false,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 15),
                    ),
                  ),
                ),
                ?suffix,
              ],
            ),
          ),
        ),
        if (errorText != null)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Text(errorText!, style: st.ui(fontSize: 12, color: ObsidianColors.dangerSoft, height: 1.4)),
          )
        else if (warningText != null)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Text(warningText!, style: st.ui(fontSize: 12, color: ObsidianColors.warning, height: 1.4)),
          ),
      ],
    );
  }
}

/// ช่องติ๊กยอมรับ — กล่องมน 7 ติ๊กแล้วเป็นเขียวนูน
class ObsidianCheckTile extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  final String text;

  const ObsidianCheckTile({super.key, required this.value, required this.onChanged, required this.text});

  @override
  Widget build(BuildContext context) {
    final st = ObsidianStyle.of(context);
    final enabled = onChanged != null;
    return Semantics(
      checked: value,
      enabled: enabled,
      label: text,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? () => onChanged!(!value) : null,
        child: Opacity(
          opacity: enabled ? 1 : 0.55,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 22,
                  height: 22,
                  margin: const EdgeInsets.only(top: 1),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(7),
                    gradient: value
                        ? const RadialGradient(
                            center: Alignment(-0.3, -0.4),
                            radius: 0.95,
                            colors: [ObsidianColors.successSoft, Color(0xFF059669)],
                          )
                        : null,
                    color: value ? null : const Color(0x0FFFFFFF),
                    border: value ? null : Border.all(color: const Color(0x33FFFFFF), width: 1.5),
                    boxShadow: value
                        ? const [BoxShadow(color: Color(0x8034D399), blurRadius: 10, spreadRadius: -2)]
                        : null,
                  ),
                  child: value ? const Icon(Icons.check_rounded, size: 16, color: Colors.white) : null,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(text, style: st.ui(fontSize: 12.5, height: 1.5, color: ObsidianColors.textSec)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum ObsidianTone { info, success, warning, danger }

Color obsidianToneColor(ObsidianTone tone) => switch (tone) {
  ObsidianTone.info => ObsidianColors.cyan,
  ObsidianTone.success => ObsidianColors.success,
  ObsidianTone.warning => ObsidianColors.orange,
  ObsidianTone.danger => ObsidianColors.danger,
};

/// แผงคำเตือน/สถานะ — หัวข้อสีตามโทน + บรรทัดข้อความ (หลายบรรทัด = มีจุดนำ)
class ObsidianNotice extends StatelessWidget {
  final ObsidianTone tone;
  final String? title;
  final List<String> lines;
  final IconData? icon;

  /// บรรทัดแรกตัวหนาสีขาว (ข้อที่ร้ายแรงที่สุด)
  final bool emphasizeFirst;

  const ObsidianNotice({
    super.key,
    required this.tone,
    this.title,
    this.lines = const [],
    this.icon,
    this.emphasizeFirst = false,
  });

  @override
  Widget build(BuildContext context) {
    final st = ObsidianStyle.of(context);
    final color = obsidianToneColor(tone);
    final bullets = lines.length > 1;
    final glyph =
        icon ??
        switch (tone) {
          ObsidianTone.info => Icons.info_outline_rounded,
          ObsidianTone.success => Icons.check_circle_outline_rounded,
          ObsidianTone.warning => Icons.warning_amber_rounded,
          ObsidianTone.danger => Icons.gpp_maybe_rounded,
        };
    return ObsidianPanel(
      surface: ObsidianCards.tinted(color),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(glyph, size: 18, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null)
                  Text(
                    title!,
                    style: st.ui(fontSize: 13.5, fontWeight: FontWeight.w600, color: color, height: 1.4),
                  ),
                for (var i = 0; i < lines.length; i++)
                  Padding(
                    padding: EdgeInsets.only(top: i == 0 && title == null ? 0 : 5),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (bullets)
                          Padding(
                            padding: const EdgeInsets.only(top: 7, right: 8),
                            child: Container(
                              width: 4,
                              height: 4,
                              decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: 0.8)),
                            ),
                          ),
                        Expanded(
                          child: Text(
                            lines[i],
                            style: st.ui(
                              fontSize: 12.5,
                              height: 1.5,
                              fontWeight: i == 0 && emphasizeFirst ? FontWeight.w600 : FontWeight.w400,
                              color: i == 0 && emphasizeFirst ? ObsidianColors.text : ObsidianColors.textSec,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// แถว ป้าย : ค่า — ค่ายาว (ที่อยู่) ตัดบรรทัดได้ ไม่ตัดเป็น …
class ObsidianKv extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final bool mono;
  final bool strong;
  final Widget? trailing;

  /// ค่าทั้งบรรทัดเป็นตัวอักษรเล็กจาง (วงเงิน)
  final bool quiet;

  const ObsidianKv(
    this.label,
    this.value, {
    super.key,
    this.valueColor,
    this.mono = false,
    this.strong = false,
    this.quiet = false,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final st = ObsidianStyle.of(context);
    final size = quiet ? 12.0 : 13.0;
    final valueStyle = mono
        ? st.mono(fontSize: size - 0.5, color: valueColor ?? ObsidianColors.text)
        : st.ui(
            fontSize: size,
            fontWeight: strong ? FontWeight.w600 : FontWeight.w400,
            color: valueColor ?? (quiet ? ObsidianColors.textMuted : ObsidianColors.text),
          );
    return LayoutBuilder(
      builder: (context, box) => ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 34),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: box.maxWidth.isFinite ? box.maxWidth * 0.55 : double.infinity),
                child: Text(
                  label,
                  style: st.ui(
                    fontSize: size,
                    color: quiet ? ObsidianColors.textMuted : ObsidianColors.textSec,
                    height: 1.35,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Flexible(
                      child: Text(value, textAlign: TextAlign.end, style: valueStyle.copyWith(height: 1.35)),
                    ),
                    if (trailing != null) ...[const SizedBox(width: 6), trailing!],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
