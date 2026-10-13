/// TPIX Wallet — ตราเชนทางการในหลุมวงกลมของบัตรโลหะ
///
/// - TPIX: path เวกเตอร์ทางการจาก `ThaiXTrade/public_html/images/brand/tpix-trade-icon.svg`
///   (viewBox 0 0 512 512) ระบายด้วยไล่สีของแบรนด์ — วาดสด คมทุกความละเอียด
/// - BNB / Polygon / Ethereum: หน้ากากขาวจากโลโก้ทางการ (Trust Wallet assets)
///   ปั๊มเป็นโลหะไล่สีด้วย ShaderMask + เรืองแสงสีประจำเชน
///
/// 🔴 ห้ามวาดโลโก้ใหม่/ประมาณรูปเอง — เจ้าของต้องการโลโก้ที่ถูกต้องเท่านั้น
///
/// Developed by Xman Studio
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'obsidian_assets.dart';

/// โลโก้ TPIX ทางการ (path เดียวกับไฟล์ SVG ของแบรนด์ — ห้ามแก้พิกัด)
class TpixMonogram {
  TpixMonogram._();

  /// กรอบที่ใช้วาด (ตาม mock: viewBox="104 88 304 356")
  static const Rect viewBox = Rect.fromLTWH(104, 88, 304, 356);

  static final Path path = _build();

  static Path _build() {
    const pts = <List<double>>[
      [109.70, 107.54], [125.10, 92.14], [381.30, 92.14], [402.30, 113.14],
      [402.30, 197.07], [315.50, 270.85], [315.50, 390.48], [257.40, 439.86],
      [127.90, 329.79], [127.90, 278.34], [257.40, 388.41], [276.30, 372.35],
      [276.30, 252.72], [363.10, 178.94], [363.10, 131.34], [206.30, 131.34],
      [206.30, 319.25], [167.10, 285.93], [167.10, 131.34], [109.70, 131.34],
    ];
    final p = Path()..moveTo(pts.first[0], pts.first[1]);
    for (final q in pts.skip(1)) {
      p.lineTo(q[0], q[1]);
    }
    return p..close();
  }

  /// ไล่สีของแบรนด์ (userSpaceOnUse จาก (106,250) ไป (406,190))
  static final Shader _brandShader = ui.Gradient.linear(
    const Offset(106, 250),
    const Offset(406, 190),
    const [Color(0xFF22D3EE), Color(0xFF3B82F6), Color(0xFF8B5CF6), Color(0xFFC026D3), Color(0xFFFB923C)],
    const [0, 0.34, 0.6, 0.8, 1],
  );

  /// เงาวาวด้านบน (objectBoundingBox: ขาว .45 → 0 ที่ 45% ของความสูง)
  static final Shader _shineShader = () {
    final b = path.getBounds();
    return ui.Gradient.linear(
      b.topCenter,
      b.bottomCenter,
      const [Color(0x73FFFFFF), Color(0x00FFFFFF)],
      const [0, 0.45],
    );
  }();

  static Paint get brandPaint => Paint()
    ..shader = _brandShader
    ..isAntiAlias = true;

  static Paint get shinePaint => Paint()..shader = _shineShader;
}

/// วาดโลโก้ TPIX พอดีกล่อง (meet) พร้อมเรืองแสง/เงาแบบ CSS drop-shadow
class TpixMonogramPainter extends CustomPainter {
  final Color? glow;

  /// ค่า blur ของ drop-shadow เรืองแสง (CSS) ในหน่วยของกล่องที่วาด
  final double glowBlur;

  /// เงาดำใต้ตรา (CSS 0 5px 6px rgba(0,0,0,.7))
  final bool shadow;

  final bool shine;

  const TpixMonogramPainter({
    this.glow,
    this.glowBlur = 12,
    this.shadow = true,
    this.shine = true,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const vb = TpixMonogram.viewBox;
    final scale = (size.width / vb.width) < (size.height / vb.height)
        ? size.width / vb.width
        : size.height / vb.height;
    final dx = (size.width - vb.width * scale) / 2;
    final dy = (size.height - vb.height * scale) / 2;

    canvas.save();
    canvas.translate(dx, dy);
    canvas.scale(scale);
    canvas.translate(-vb.left, -vb.top);
    final path = TpixMonogram.path;

    // σ ใน path space = (blur/2) / scale
    if (glow != null) {
      canvas.drawPath(
        path,
        Paint()
          ..color = glow!
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, glowBlur / 2 / scale),
      );
    }
    if (shadow) {
      canvas.save();
      canvas.translate(0, 5 / scale);
      canvas.drawPath(
        path,
        Paint()
          ..color = const Color(0xB3000000)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 3 / scale),
      );
      canvas.restore();
    }
    canvas.drawPath(path, TpixMonogram.brandPaint);
    if (shine) canvas.drawPath(path, TpixMonogram.shinePaint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(TpixMonogramPainter old) =>
      old.glow != glow || old.glowBlur != glowBlur || old.shadow != shadow || old.shine != shine;
}

/// ตราในหลุมบัตร — ขนาดตาม mock: TPIX 58x66 / ตราอื่น 58x58 (บนบัตรกว้าง 342)
class ChainEmblem extends StatelessWidget {
  final ObsidianChainArt art;

  /// ความกว้างของตรา
  final double size;

  const ChainEmblem({super.key, required this.art, this.size = 58});

  @override
  Widget build(BuildContext context) {
    if (art.isTpix) {
      return SizedBox(
        width: size,
        height: size * 66 / 58,
        child: CustomPaint(
          painter: TpixMonogramPainter(glow: art.accent, glowBlur: 12 * size / 58),
        ),
      );
    }

    final mask = art.mask!;
    Widget maskImage({Color? tint}) {
      final img = Image.asset(
        mask,
        width: size,
        height: size,
        fit: BoxFit.contain,
        cacheWidth: 192,
        excludeFromSemantics: true,
        errorBuilder: (_, _, _) => SizedBox(width: size, height: size),
      );
      if (tint == null) return img;
      return ColorFiltered(colorFilter: ColorFilter.mode(tint, BlendMode.srcIn), child: img);
    }

    final k = size / 58;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // เรืองแสงสีประจำเชน — drop-shadow(0 0 12px accent)
          Positioned.fill(
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 6 * k, sigmaY: 6 * k, tileMode: TileMode.decal),
              child: maskImage(tint: art.accent),
            ),
          ),
          // เงาดำใต้ตรา — drop-shadow(0 5px 6px rgba(0,0,0,.7))
          Positioned.fill(
            child: Transform.translate(
              offset: Offset(0, 5 * k),
              child: ImageFiltered(
                imageFilter: ui.ImageFilter.blur(sigmaX: 3 * k, sigmaY: 3 * k, tileMode: TileMode.decal),
                child: maskImage(tint: const Color(0xB3000000)),
              ),
            ),
          ),
          // ตัวตราโลหะ — linear-gradient(160deg, ...) ผ่านหน้ากาก
          Positioned.fill(
            child: ShaderMask(
              blendMode: BlendMode.srcIn,
              // 160deg ของ CSS: ชี้ลงล่างเอียงขวาเล็กน้อย
              shaderCallback: (r) => LinearGradient(
                begin: const Alignment(-0.342, -0.94),
                end: const Alignment(0.342, 0.94),
                colors: art.metal,
                stops: art.metalStops,
              ).createShader(r),
              child: maskImage(),
            ),
          ),
        ],
      ),
    );
  }
}
