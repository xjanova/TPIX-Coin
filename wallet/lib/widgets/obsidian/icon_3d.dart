/// TPIX Wallet — ไอคอน 3D ของธีม Obsidian
///
/// ห่อ Image.asset ให้:
///   - ถอดรหัสภาพแค่ขนาดที่วาดจริง (ไม่ใช่เต็มไฟล์) → ประหยัดหน่วยความจำ
///   - มีเงาแบบ CSS `filter: drop-shadow(...)` (เงาตามรูปทรงจริงของไอคอน ไม่ใช่กล่อง)
///   - สถานะ "ไม่ได้เลือก" แบบ mock: จาง 55% + ลดความอิ่มสีเหลือ 40%
///
/// Developed by Xman Studio
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// เงาตามรูปทรงภาพ — [blur] เป็นค่าเดียวกับใน CSS drop-shadow
@immutable
class IconDropShadow {
  final double dx;
  final double dy;
  final double blur;
  final Color color;

  const IconDropShadow(this.dx, this.dy, this.blur, this.color);

  /// เงาดำมาตรฐานของไทล์ (mock: 0 10px 14px rgba(0,0,0,.75))
  static const tile = IconDropShadow(0, 10, 14, Color(0xBF000000));

  /// แสงฟ้าใต้ปุ่มหลัก (mock: ปุ่มส่ง 0 4px 14px rgba(34,211,238,.30))
  static const cyanGlow = IconDropShadow(0, 4, 14, Color(0x4D22D3EE));

  /// แสงม่วงรอบเมนูที่เลือก (mock: 0 0 10px rgba(139,92,246,.55))
  static const violetGlow = IconDropShadow(0, 0, 10, Color(0x8C8B5CF6));
}

class Icon3D extends StatelessWidget {
  final String asset;
  final double size;

  /// สถานะไม่ได้เลือก (เมนูล่าง) — จาง + สีหม่น
  final bool dimmed;

  final List<IconDropShadow> shadows;

  /// null = ตกแต่งเฉย ๆ (ไม่ให้ตัวอ่านหน้าจออ่าน)
  final String? semanticLabel;

  const Icon3D(
    this.asset, {
    super.key,
    this.size = 30,
    this.dimmed = false,
    this.shadows = const [],
    this.semanticLabel,
  });

  /// CSS saturate(.4) — สัมประสิทธิ์ตามสเปก Filter Effects
  static const _desaturate = ColorFilter.matrix(<double>[
    0.5278, 0.4290, 0.0432, 0, 0, //
    0.1278, 0.8290, 0.0432, 0, 0, //
    0.1278, 0.4290, 0.4432, 0, 0, //
    0, 0, 0, 1, 0,
  ]);

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 3.0;
    final px = (size * dpr).ceil();

    Widget image(BuildContext _) => Image.asset(
          asset,
          width: size,
          height: size,
          cacheWidth: px,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.medium,
          gaplessPlayback: true,
          excludeFromSemantics: true,
          errorBuilder: (_, _, _) => SizedBox(width: size, height: size),
        );

    Widget icon = image(context);

    if (shadows.isNotEmpty) {
      icon = Stack(
        clipBehavior: Clip.none,
        children: [
          for (final s in shadows)
            Positioned.fill(
              child: Transform.translate(
                offset: Offset(s.dx, s.dy),
                child: ImageFiltered(
                  // CSS drop-shadow: ค่า blur = 2σ (เท่ากับ box-shadow)
                  imageFilter: ui.ImageFilter.blur(
                    sigmaX: s.blur / 2,
                    sigmaY: s.blur / 2,
                    tileMode: TileMode.decal,
                  ),
                  child: ColorFiltered(
                    colorFilter: ColorFilter.mode(s.color, BlendMode.srcIn),
                    child: image(context),
                  ),
                ),
              ),
            ),
          icon,
        ],
      );
    }

    if (dimmed) {
      icon = Opacity(
        opacity: 0.55,
        child: ColorFiltered(colorFilter: _desaturate, child: icon),
      );
    }

    if (semanticLabel == null) return ExcludeSemantics(child: icon);
    return Semantics(label: semanticLabel, image: true, child: icon);
  }
}
