/// TPIX Wallet — แถบหัวหน้าย่อยของธีม Obsidian (ส่ง / รับ / สแกน / PIN)
///
/// mock ทุกหน้าใช้ grid `46px | 1fr | 46px`: ปุ่มกระจกนูน 46x46 มน 16 · หัวข้อกลาง 18/600
/// ช่องขวาว่างได้ (ยังกินที่ 46 เพื่อให้หัวข้ออยู่กึ่งกลางจอจริง)
///
/// Developed by Xman Studio
library;

import 'package:flutter/material.dart';

import '../../core/themes/obsidian_tokens.dart';
import 'obsidian_panel.dart';

/// ปุ่มกระจกนูน 46x46 (ย้อนกลับ / ปิด / รายการโปรด / ไฟฉาย)
class ObsidianTopButton extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final String semanticLabel;

  /// สีพื้นแทนกระจกปกติ (เช่น ไฟฉายเปิดอยู่ = เหลืองอ่อน)
  final Color? tint;

  /// เบลอสิ่งที่อยู่ด้านหลัง (หน้ากล้องใช้ เพราะพื้นหลังขยับ)
  final double blur;

  const ObsidianTopButton({
    super.key,
    required this.child,
    required this.onTap,
    required this.semanticLabel,
    this.tint,
    this.blur = 14,
  });

  static const double size = 46;

  @override
  Widget build(BuildContext context) {
    final surface = tint == null
        ? ObsidianSurface.raised
        : ObsidianSurface(
            radius: 16,
            color: tint,
            topHighlight: const Color(0x2EFFFFFF),
            shadows: const [CssShadow(0, 10, 24, -10, Color(0xE6000000))],
          );
    return ObsidianPanel(
      surface: surface,
      blur: blur,
      width: size,
      height: size,
      onTap: onTap,
      semanticLabel: semanticLabel,
      child: Center(child: child),
    );
  }
}

class ObsidianTopBar extends StatelessWidget {
  final Widget? leading;
  final String title;
  final Widget? trailing;

  /// แทนหัวข้อด้วยวิดเจ็ตอื่น (เช่น ป้ายสรุปธุรกรรมในหน้า PIN)
  final Widget? center;

  const ObsidianTopBar({super.key, this.leading, this.title = '', this.trailing, this.center});

  @override
  Widget build(BuildContext context) {
    final st = ObsidianStyle.of(context);
    return SizedBox(
      height: ObsidianTopButton.size,
      child: Row(
        children: [
          SizedBox.square(dimension: ObsidianTopButton.size, child: leading),
          Expanded(
            child: Center(
              child: center ??
                  Semantics(
                    header: true,
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: st.ui(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: ObsidianColors.text,
                        shadows: const [Shadow(color: Color(0xB3000000), blurRadius: 12, offset: Offset(0, 2))],
                      ),
                    ),
                  ),
            ),
          ),
          SizedBox.square(dimension: ObsidianTopButton.size, child: trailing),
        ],
      ),
    );
  }
}

/// ปิดหน้า "ของตัวเอง" เท่านั้น
///
/// แตะซ้ำระหว่างหน้ากำลังเลื่อนปิด หน้านั้นยัง mounted แต่ไม่ใช่หน้าบนสุดแล้ว —
/// Navigator.pop ครั้งที่สองจะไปปิดหน้าข้างใต้ทิ้ง (เช่น หน้าแรก) → ตัวนี้ไม่ทำอะไรแทน
void obsidianPopIfCurrent<T extends Object?>(BuildContext context, [T? result]) {
  final route = ModalRoute.of(context);
  if (route != null && !route.isCurrent) return;
  Navigator.of(context).maybePop<T>(result);
}
