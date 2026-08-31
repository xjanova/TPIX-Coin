/// TPIX Wallet — Liquid Blobs Background
/// ก้อนเจลลี่ลอยไปมาแบบนุ่มๆ สดใส — ลายเซ็นของธีม "ลิควิด"
///
/// ออกแบบให้เบา: ใช้ CustomPainter ตัวเดียว + controller ตัวเดียว
/// (วาดวงกลมเบลอ ไม่ใช่ BackdropFilter ทั้งจอ ซึ่งกิน GPU มากบนมือถือ)
///
/// Developed by Xman Studio

import 'dart:math' as math;
import 'package:flutter/material.dart';

import 'luxe_texture.dart';

class LiquidBlobsBackground extends StatefulWidget {
  final Widget child;
  const LiquidBlobsBackground({super.key, required this.child});

  @override
  State<LiquidBlobsBackground> createState() => _LiquidBlobsBackgroundState();
}

class _LiquidBlobsBackgroundState extends State<LiquidBlobsBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    // 32 วิ/รอบ — ช้ามากโดยตั้งใจ ให้รู้สึกเหมือนของเหลวไหล ไม่กวนสายตา
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 32),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // จานสีของ blob — light: พาสเทลสดใส / dark: candy neon บนพื้นอินดิโก
    final blobs = isDark
        ? const [
            _BlobSpec(Color(0xFF2DD4BF), 0.18, 0.62, 0.30, 0.0),
            _BlobSpec(Color(0xFFA78BFA), 0.82, 0.20, 0.34, 0.33),
            _BlobSpec(Color(0xFFF472B6), 0.30, 0.88, 0.28, 0.66),
            _BlobSpec(Color(0xFF38BDF8), 0.90, 0.72, 0.26, 0.15),
            _BlobSpec(Color(0xFFFBBF24), 0.10, 0.12, 0.20, 0.80),
          ]
        : const [
            _BlobSpec(Color(0xFF7DE8D8), 0.16, 0.60, 0.34, 0.0),
            _BlobSpec(Color(0xFFC4B5FD), 0.84, 0.18, 0.36, 0.33),
            _BlobSpec(Color(0xFFFFC0D9), 0.28, 0.90, 0.30, 0.66),
            _BlobSpec(Color(0xFF9AD8FF), 0.92, 0.74, 0.28, 0.15),
            _BlobSpec(Color(0xFFFFE0A3), 0.08, 0.14, 0.22, 0.80),
          ];

    return Stack(
      children: [
        // ── ชั้น 1: พื้นไล่สีนุ่ม ──
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: isDark
                    ? const [Color(0xFF1B1F45), Color(0xFF141733)]
                    : const [Color(0xFFEBF9FF), Color(0xFFFFF2F8)],
              ),
            ),
          ),
        ),

        // ── ชั้น 2: ลายพื้นผิว guilloché (วาดด้วยโค้ด) ──
        // เดิมชั้นนี้เป็น liquid_bg.jpg ขนาด 720×1280 ปูเต็มจอด้วย BoxFit.cover
        // บน iPhone 13 Pro (1170×2532) = ยืด 1.63 เท่า ทำให้ทั้งหน้าจอดูเบลอ
        // ลายที่วาดด้วยโค้ดคมทุกความละเอียด และให้ผิวแบบธนบัตร/บัตรพรีเมียม
        Positioned.fill(
          child: LuxeTexture(
            isDark: isDark,
            lineColor: isDark ? Colors.white : const Color(0xFF16394D),
          ),
        ),

        // ── ชั้น 3: ก้อนเจลลี่ลอย (ไม่รับ touch) — ให้ภาพนิ่งมีชีวิต ──
        Positioned.fill(
          child: IgnorePointer(
            child: RepaintBoundary(
              child: AnimatedBuilder(
                animation: _ctrl,
                builder: (_, __) => CustomPaint(
                  painter: _BlobsPainter(
                    progress: _ctrl.value,
                    blobs: blobs,
                    opacity: isDark ? 0.42 : 0.30,
                  ),
                ),
              ),
            ),
          ),
        ),

        // ── ชั้น 4: เนื้อหาแอพ ──
        Positioned.fill(child: widget.child),
      ],
    );
  }
}

/// สเปกของ blob หนึ่งก้อน — ตำแหน่งฐาน (0..1 ของจอ), รัศมี (สัดส่วนความกว้าง), เฟส
class _BlobSpec {
  final Color color;
  final double baseX;
  final double baseY;
  final double radius;
  final double phase;

  const _BlobSpec(this.color, this.baseX, this.baseY, this.radius, this.phase);
}

class _BlobsPainter extends CustomPainter {
  final double progress; // 0..1 วนรอบ
  final List<_BlobSpec> blobs;
  final double opacity;

  _BlobsPainter({
    required this.progress,
    required this.blobs,
    required this.opacity,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final b in blobs) {
      // เดินทางแบบ Lissajous — วนกลับที่เดิมพอดีเมื่อ progress ครบ 1 รอบ
      // (ไม่มีอาการ "กระตุก" ตอน loop เพราะใช้ sin/cos ของ 2π)
      final t = (progress + b.phase) * 2 * math.pi;
      final dx = math.sin(t) * size.width * 0.10;
      final dy = math.cos(t * 0.7) * size.height * 0.06;

      final center = Offset(
        size.width * b.baseX + dx,
        size.height * b.baseY + dy,
      );
      final r = size.width * b.radius;

      // ไล่สีจากใจกลางจางออกขอบ + เบลอ = ได้ความรู้สึกเจลลี่นุ่ม
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [
            b.color.withValues(alpha: opacity),
            b.color.withValues(alpha: 0.0),
          ],
          stops: const [0.0, 1.0],
        ).createShader(Rect.fromCircle(center: center, radius: r))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 28);

      canvas.drawCircle(center, r, paint);
    }
  }

  @override
  bool shouldRepaint(_BlobsPainter old) =>
      old.progress != progress || old.opacity != opacity;
}
