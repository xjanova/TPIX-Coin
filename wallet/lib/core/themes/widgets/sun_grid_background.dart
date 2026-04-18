/// TPIX Wallet — Synthwave Sun + Grid Background
/// 80s Outrun retro-futuristic: dawn sun + perspective grid + mountains
///
/// Developed by Xman Studio

import 'package:flutter/material.dart';

class SunGridBackground extends StatefulWidget {
  final Widget child;
  const SunGridBackground({super.key, required this.child});

  @override
  State<SunGridBackground> createState() => _SunGridBackgroundState();
}

class _SunGridBackgroundState extends State<SunGridBackground>
    with TickerProviderStateMixin {
  late final AnimationController _gridCtrl;
  late final AnimationController _sunCtrl;
  late final Animation<double> _sunPulse;

  @override
  void initState() {
    super.initState();
    // Grid scrolling — เลื่อน perspective lines ลงมาทาง viewer ตลอด
    _gridCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();

    // Sun breathing — scale 1.0 → 1.04 → 1.0 (สบายตา ไม่กระพริบ)
    _sunCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat(reverse: true);
    _sunPulse = Tween<double>(begin: 1.0, end: 1.04).animate(
      CurvedAnimation(parent: _sunCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _gridCtrl.dispose();
    _sunCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // ── Layer 1: Sky gradient (deep purple → magenta → orange horizon) ──
        Positioned.fill(
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [0.0, 0.45, 0.55, 1.0],
                colors: [
                  Color(0xFF0A0420), // deep night
                  Color(0xFF2B0B4A), // purple
                  Color(0xFF4F0A4F), // magenta-purple
                  Color(0xFF0A0420), // bottom dark
                ],
              ),
            ),
          ),
        ),

        // ── Layer 2: Sun (gradient orb at horizon, breathing pulse) ──
        Positioned(
          top: MediaQuery.of(context).size.height * 0.32,
          left: 0,
          right: 0,
          child: Center(
            child: AnimatedBuilder(
              animation: _sunPulse,
              builder: (_, __) => Transform.scale(
                scale: _sunPulse.value,
                child: Container(
                  width: 240,
                  height: 240,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0xFFFFE066),
                        Color(0xFFFF6E9C),
                        Color(0xFFD3137A),
                        Color(0xFF6B0F8E),
                      ],
                      stops: [0.0, 0.5, 0.8, 1.0],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFF2EB5).withValues(alpha: 0.45 + (_sunPulse.value - 1.0) * 4),
                        blurRadius: 80 + (_sunPulse.value - 1.0) * 200,
                        spreadRadius: 10,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),

        // ── Layer 3: Sun horizontal stripes (silhouette of horizon strips) ──
        Positioned(
          top: MediaQuery.of(context).size.height * 0.42,
          left: 0,
          right: 0,
          height: 140,
          child: CustomPaint(
            painter: _SunStripesPainter(),
          ),
        ),

        // ── Layer 4: Perspective grid (animated scrolling) ──
        Positioned.fill(
          child: AnimatedBuilder(
            animation: _gridCtrl,
            builder: (_, __) => CustomPaint(
              painter: _PerspectiveGridPainter(progress: _gridCtrl.value),
            ),
          ),
        ),

        // ── Layer 5: Subtle vignette darken at edges for content readability ──
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.center,
                radius: 1.2,
                colors: [
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.45),
                ],
                stops: const [0.5, 1.0],
              ),
            ),
          ),
        ),

        // ── Foreground: app content ──
        Positioned.fill(child: widget.child),
      ],
    );
  }
}

/// วาดแถบสีดำพาดผ่านดวงอาทิตย์ — สไตล์ Outrun classic
class _SunStripesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xFF0A0420).withValues(alpha: 0.85);

    // 6 stripes ที่ห่างเพิ่มขึ้นเรื่อยๆ จากบนลงล่าง
    double y = 8;
    double gap = 8;
    for (int i = 0; i < 6; i++) {
      canvas.drawRect(
        Rect.fromLTWH(0, y, size.width, gap * (i * 0.4 + 1).clamp(1.0, 4.0)),
        paint,
      );
      y += gap * (i * 0.6 + 1.6);
      gap += 4;
    }
  }

  @override
  bool shouldRepaint(_) => false;
}

/// วาด perspective grid (ตาราง neon ลึกเข้าไปในเส้นขอบฟ้า)
class _PerspectiveGridPainter extends CustomPainter {
  final double progress; // 0..1 — เลื่อนต่อเนื่องเพื่อ animation
  _PerspectiveGridPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final horizonY = size.height * 0.55;
    final gridPaint = Paint()
      ..color = const Color(0xFFFF2EB5).withValues(alpha: 0.45)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    final gridGlow = Paint()
      ..color = const Color(0xFF06B6D4).withValues(alpha: 0.20)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

    // ── Vertical lines (radiating from vanishing point) ──
    const vanishX = 0.5; // center
    final vanishPoint = Offset(size.width * vanishX, horizonY);
    const verticalCount = 16;
    for (int i = -verticalCount; i <= verticalCount; i++) {
      if (i == 0) continue;
      final bottomX = size.width * (0.5 + i / verticalCount * 1.2);
      final p1 = vanishPoint;
      final p2 = Offset(bottomX, size.height);
      canvas.drawLine(p1, p2, gridGlow);
      canvas.drawLine(p1, p2, gridPaint);
    }

    // ── Horizontal lines (perspective bands moving towards viewer) ──
    // ใช้ progress เพื่อ scroll
    const bandCount = 14;
    for (int i = 0; i < bandCount; i++) {
      // t คือ 0 (horizon) → 1 (viewer)
      // เพิ่ม progress เพื่อให้เลื่อน
      double t = ((i + progress) % bandCount) / bandCount;
      // perspective: y position curve เร่งใกล้ viewer
      t = t * t * t; // power curve
      final y = horizonY + (size.height - horizonY) * t;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridGlow);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // ── Horizon line ──
    final horizonPaint = Paint()
      ..color = const Color(0xFFFF6E9C).withValues(alpha: 0.6)
      ..strokeWidth = 1.5;
    canvas.drawLine(
      Offset(0, horizonY),
      Offset(size.width, horizonY),
      horizonPaint,
    );
  }

  @override
  bool shouldRepaint(_PerspectiveGridPainter old) => old.progress != progress;
}
