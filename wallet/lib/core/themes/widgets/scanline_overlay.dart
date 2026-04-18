/// TPIX Wallet — CRT Scanline Overlay
/// Animated horizontal scanlines + subtle glow + occasional flicker
/// — overlay บน scaffold ทั้งหน้าเพื่อให้รู้สึกเหมือน CRT monitor
///
/// Developed by Xman Studio

import 'dart:math';
import 'package:flutter/material.dart';

class CrtScanlineOverlay extends StatefulWidget {
  final Widget child;
  const CrtScanlineOverlay({super.key, required this.child});

  @override
  State<CrtScanlineOverlay> createState() => _CrtScanlineOverlayState();
}

class _CrtScanlineOverlayState extends State<CrtScanlineOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _scanCtrl;
  late final AnimationController _flickerCtrl;
  late final AnimationController _bootCtrl;
  late final AnimationController _cursorCtrl;
  final _rng = Random();

  @override
  void initState() {
    super.initState();
    // Scan beam — เลื่อนลงล่างเป็นวง
    _scanCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();

    // Flicker — ปรับ opacity เล็กน้อยทุก ~3-7 วินาที
    _flickerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _scheduleFlicker();

    // Boot-up — รัน 1 ครั้งตอนเปิดธีม (ฟ้าเปิด CRT จากกลาง expanding ออก)
    _bootCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..forward();

    // Cursor blink — ทุก 500ms
    _cursorCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..repeat(reverse: true);
  }

  void _scheduleFlicker() {
    Future.delayed(Duration(seconds: 3 + _rng.nextInt(5)), () {
      if (!mounted) return;
      _flickerCtrl.forward(from: 0).then((_) {
        if (mounted) _scheduleFlicker();
      });
    });
  }

  @override
  void dispose() {
    _scanCtrl.dispose();
    _flickerCtrl.dispose();
    _bootCtrl.dispose();
    _cursorCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // ── App content (ใต้ overlay) — wrap with CRT boot effect ──
        Positioned.fill(
          child: AnimatedBuilder(
            animation: _bootCtrl,
            builder: (_, child) {
              // Boot: vertical sweep จากกลางออก + horizontal sweep ตามมา
              final bootValue = Curves.easeOutCubic.transform(_bootCtrl.value);
              return ClipRect(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Real content (scaled-up vertically during boot)
                    Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.diagonal3Values(
                          1.0, bootValue.clamp(0.05, 1.0), 1.0),
                      child: Opacity(
                        opacity: bootValue,
                        child: child,
                      ),
                    ),
                    // Bright horizontal beam expanding (CRT power-on)
                    if (_bootCtrl.value < 0.6)
                      Center(
                        child: Container(
                          width: double.infinity,
                          height: 2,
                          color: const Color(0xFF00FF99).withValues(
                            alpha: (1.0 - _bootCtrl.value / 0.6) * 0.9,
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
            child: widget.child,
          ),
        ),

        // ── Layer A: Static scanlines (cover ทั้งจอ — repeating horizontal lines) ──
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _StaticScanlinesPainter(),
            ),
          ),
        ),

        // ── Layer B: Moving scan beam (bright line scrolling top → bottom) ──
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _scanCtrl,
              builder: (_, __) => CustomPaint(
                painter: _ScanBeamPainter(progress: _scanCtrl.value),
              ),
            ),
          ),
        ),

        // ── Layer C: Phosphor green tint + occasional flicker ──
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _flickerCtrl,
              builder: (_, __) {
                final flicker = sin(_flickerCtrl.value * pi) * 0.05;
                return Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF00FF66).withValues(alpha: 0.025 + flicker),
                  ),
                );
              },
            ),
          ),
        ),

        // ── Layer D: Vignette (CRT curvature feel — darker corners) ──
        Positioned.fill(
          child: IgnorePointer(
            child: Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.center,
                  radius: 1.1,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.55),
                  ],
                  stops: const [0.55, 1.0],
                ),
              ),
            ),
          ),
        ),

        // ── Layer E: Status corner (blinking cursor + system status) ──
        Positioned(
          right: 12,
          bottom: 12,
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _cursorCtrl,
              builder: (_, __) => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'TPIX://OK',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 10,
                      color: const Color(0xFF00FF66).withValues(alpha: 0.5),
                      letterSpacing: 1.0,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Container(
                    width: 7,
                    height: 12,
                    color: const Color(0xFF00FF66).withValues(
                      alpha: _cursorCtrl.value > 0.5 ? 0.8 : 0.0,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _StaticScanlinesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black.withValues(alpha: 0.12);
    // Horizontal lines ทุก 3 px
    for (double y = 0; y < size.height; y += 3) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, 1), paint);
    }
  }

  @override
  bool shouldRepaint(_) => false;
}

class _ScanBeamPainter extends CustomPainter {
  final double progress;
  _ScanBeamPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final beamY = size.height * progress;
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.transparent,
          const Color(0xFF00FF99).withValues(alpha: 0.08),
          const Color(0xFF00FF99).withValues(alpha: 0.18),
          const Color(0xFF00FF99).withValues(alpha: 0.08),
          Colors.transparent,
        ],
      ).createShader(Rect.fromLTWH(0, beamY - 30, size.width, 60));
    canvas.drawRect(
      Rect.fromLTWH(0, beamY - 30, size.width, 60),
      paint,
    );
  }

  @override
  bool shouldRepaint(_ScanBeamPainter old) => old.progress != progress;
}
