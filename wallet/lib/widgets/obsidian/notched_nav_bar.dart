/// TPIX Wallet — แถบเมนูล่างแบบมีรอยเว้า (ธีม Obsidian)
///
/// พอร์ตจาก Main.dc.html:
///   - แถบกระจก 358x78 มน 26 + รอยเว้าทรง U ตรงกลางรับปุ่มสแกน
///     path: M26,0 L121,0 C133,0 139,8 139,20 A40 40 0 0 0 219,20 C219,8 225,0 237,0 …
///     (จอกว้างกว่า 390 → รอยเว้าคงขนาดอยู่กลาง เส้นตรงสองข้างยืดออก)
///   - เงาเบลอทรงเดียวกับแถบ · ขอบบนสะท้อนแสง · เส้นเรืองไล่สีตามรอยเว้า หายใจ 4 วิ
///   - ปุ่มสแกนกลม 66px จมลงในรอยเว้า โผล่พ้นขอบแถบแค่ 20% (13px)
///     วงแหวนไล่สีหมุน 3.2 วิ · จานดำด้านในมีไอคอนสแกน 3D · เรืองแสงเต้นช้า 4 วิ + รัศมีรอบปุ่ม
///
/// 🔴 กรอบของวิดเจ็ตต้องครอบปุ่มสแกนทั้งใบ (รวม 13px ที่โผล่พ้นแถบ)
///    Flutter ไม่ hit-test ส่วนที่ล้นนอกกรอบพ่อ — เคยเป็นบั๊กจริงของ LiquidNavBar
///    (เห็นปุ่มเต็มใบ แต่กดยอดปุ่มแล้วเงียบ) — test/obsidian_widgets_test.dart ล็อกไว้
///
/// Developed by Xman Studio
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/themes/obsidian_tokens.dart';
import 'icon_3d.dart';
import 'obsidian_assets.dart';
import 'obsidian_panel.dart';

/// เมนูหนึ่งช่อง
class NotchedNavItem {
  /// ไอคอน 3D (ObsidianIcons.*)
  final String asset;
  final String label;
  final VoidCallback onTap;

  const NotchedNavItem({required this.asset, required this.label, required this.onTap});
}

class NotchedNavBar extends StatefulWidget {
  /// กุญแจของปุ่มสแกน — ค่าเดียวกับ LiquidNavBar.scanButtonKey (เทสต์/เครื่องมือหาได้ทั้งสองธีม)
  static const Key scanButtonKey = Key('nav-scan-button');

  /// 4 ช่อง: ซ้าย 2 / ขวา 2 — ปุ่มสแกนอยู่ตรงกลางเอง
  final List<NotchedNavItem> items;

  /// ช่องที่ผู้ใช้อยู่ (-1 = ไม่มี)
  final int currentIndex;

  final VoidCallback onScanTap;

  /// ป้ายใต้ปุ่มสแกน ("สแกน")
  final String scanLabel;

  /// คำอ่านของตัวอ่านหน้าจอ ("สแกนจ่าย / รับ")
  final String scanSemantics;

  const NotchedNavBar({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onScanTap,
    required this.scanLabel,
    this.scanSemantics = '',
  });

  static const double barHeight = 78;
  static const double orbSize = 66;

  /// ปุ่มสแกนโผล่พ้นขอบบนของแถบ = 20% ของปุ่ม
  static const double orbRise = 13;

  /// ระยะจากขอบล่างจอ (mock 18 — เครื่องที่มีแถบท่าทางล่างใช้ระยะนั้นแทน)
  static double bottomGap(BuildContext context) =>
      math.max(18.0, MediaQuery.viewPaddingOf(context).bottom);

  /// ความสูงที่แถบนี้กินจริง (รวมระยะล่าง) — ใช้เว้นท้ายเนื้อหาในหน้าที่ extendBody
  static double heightFor(BuildContext context) => orbRise + barHeight + bottomGap(context);

  /// รูปทรงแถบ (ความกว้าง [w]) — รอยเว้าคงขนาดอยู่กึ่งกลาง
  static Path barPath(double w) {
    final cx = w / 2;
    return Path()
      ..moveTo(26, 0)
      ..lineTo(cx - 58, 0)
      ..cubicTo(cx - 46, 0, cx - 40, 8, cx - 40, 20)
      // A40 40 0 0 0 → ทวนเข็มบนจอ = ผ่านก้นรอยเว้า (cx, 60)
      ..arcToPoint(Offset(cx + 40, 20), radius: const Radius.circular(40), clockwise: false)
      ..cubicTo(cx + 40, 8, cx + 46, 0, cx + 58, 0)
      ..lineTo(w - 26, 0)
      ..quadraticBezierTo(w, 0, w, 26)
      ..lineTo(w, 52)
      ..quadraticBezierTo(w, 78, w - 26, 78)
      ..lineTo(26, 78)
      ..quadraticBezierTo(0, 78, 0, 52)
      ..lineTo(0, 26)
      ..quadraticBezierTo(0, 0, 26, 0)
      ..close();
  }

  /// เส้นเรืองตามขอบรอยเว้า (เส้นเปิด ไม่ปิดรูป)
  static Path notchPath(double w) {
    final cx = w / 2;
    return Path()
      ..moveTo(cx - 67, 0.6)
      ..lineTo(cx - 58, 0.6)
      ..cubicTo(cx - 46, 0.6, cx - 40.4, 8.6, cx - 40.4, 20)
      ..arcToPoint(Offset(cx + 40.4, 20), radius: const Radius.circular(40.4), clockwise: false)
      ..cubicTo(cx + 40.4, 8.6, cx + 46, 0.6, cx + 58, 0.6)
      ..lineTo(cx + 67, 0.6);
  }

  @override
  State<NotchedNavBar> createState() => _NotchedNavBarState();
}

class _NotchedNavBarState extends State<NotchedNavBar> with TickerProviderStateMixin {
  /// หายใจ 4 วิ (0→1→0) — เส้นเรือง / เรืองแสงปุ่ม / รัศมี
  late final AnimationController _breath;

  /// วงแหวนไล่สีหมุน 3.2 วิต่อรอบ
  late final AnimationController _spin;

  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _breath = AnimationController(vsync: this, duration: const Duration(seconds: 2));
    _spin = AnimationController(vsync: this, duration: const Duration(milliseconds: 3200));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduce == _reduceMotion && (_breath.isAnimating || reduce)) return;
    _reduceMotion = reduce;
    if (reduce) {
      // ลดภาพเคลื่อนไหว → หยุดนิ่งที่ครึ่งทาง (ยังเห็นเรืองแสง แต่ไม่กะพริบ/หมุน)
      _breath
        ..stop()
        ..value = 0.5;
      _spin
        ..stop()
        ..value = 0;
    } else {
      _breath.repeat(reverse: true);
      _spin.repeat();
    }
  }

  @override
  void dispose() {
    _breath.dispose();
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    assert(widget.items.length == 4, 'NotchedNavBar ต้องมี 4 ช่องพอดี');
    const rise = NotchedNavBar.orbRise;
    const barH = NotchedNavBar.barHeight;
    final gap = NotchedNavBar.bottomGap(context);
    final st = ObsidianStyle.of(context);

    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.2,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, gap),
        child: SizedBox(
          height: rise + barH,
          child: LayoutBuilder(builder: (context, box) {
            final w = box.maxWidth;
            final cx = w / 2;
            return Stack(
              clipBehavior: Clip.none,
              children: [
                // ── เงาเบลอทรงแถบ (เลื่อนลง 14 · σ14 · .9) ──
                Positioned(
                  left: 0,
                  top: rise,
                  width: w,
                  height: barH,
                  child: IgnorePointer(child: CustomPaint(painter: _BarShadowPainter())),
                ),
                // ── ตัวแถบกระจก (ตัดตามรอยเว้า) ──
                Positioned(
                  left: 0,
                  top: rise,
                  width: w,
                  height: barH,
                  child: ClipPath(
                    clipper: _BarClipper(),
                    child: BackdropFilter(
                      filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                      child: const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Color(0xE6242733), Color(0xF212141B), Color(0xF70B0C11)],
                            stops: [0, 0.55, 1],
                          ),
                        ),
                        child: SizedBox.expand(),
                      ),
                    ),
                  ),
                ),
                // ── ขอบสะท้อนแสง + เส้นเรืองรอยเว้า ──
                Positioned(
                  left: 0,
                  top: rise,
                  width: w,
                  height: barH,
                  child: IgnorePointer(
                    child: AnimatedBuilder(
                      animation: _breath,
                      builder: (_, _) => CustomPaint(
                        painter: _BarRimPainter(glow: 0.3 + 0.7 * Curves.easeInOut.transform(_breath.value)),
                      ),
                    ),
                  ),
                ),
                // ── 4 เมนู (ช่องกลางเว้นให้ปุ่มสแกน) ──
                Positioned(
                  left: 4,
                  right: 4,
                  top: rise + 6,
                  height: barH - 6,
                  child: Row(
                    children: [
                      for (var slot = 0; slot < 5; slot++)
                        Expanded(
                          child: slot == 2
                              ? const SizedBox.shrink()
                              : _NavCell(
                                  item: widget.items[slot < 2 ? slot : slot - 1],
                                  active: widget.currentIndex == (slot < 2 ? slot : slot - 1),
                                  style: st,
                                ),
                        ),
                    ],
                  ),
                ),
                // ── ป้าย "สแกน" ใต้ปุ่ม ──
                Positioned(
                  left: cx - 50,
                  width: 100,
                  bottom: 3,
                  child: IgnorePointer(
                    child: Text(
                      widget.scanLabel,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      style: st.ui(fontSize: 10, fontWeight: FontWeight.w600, color: ObsidianColors.chrome),
                    ),
                  ),
                ),
                // ── รัศมีรอบปุ่ม (ตกแต่ง ไม่รับการแตะ) ──
                Positioned(
                  left: cx - 70,
                  top: rise - 50,
                  width: 140,
                  height: 140,
                  child: IgnorePointer(
                    child: AnimatedBuilder(
                      animation: _breath,
                      builder: (_, child) {
                        final b = Curves.easeInOut.transform(_breath.value);
                        return Opacity(
                          opacity: 0.25 + 0.65 * b,
                          child: Transform.scale(scale: 0.85 + 0.23 * b, child: child),
                        );
                      },
                      child: const DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [Color(0x8C8B5CF6), Color(0x3822D3EE), Color(0x00000000)],
                            stops: [0, 0.55, 1],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // ── ปุ่มสแกน ──
                Positioned(
                  left: cx - NotchedNavBar.orbSize / 2,
                  top: 0,
                  width: NotchedNavBar.orbSize,
                  height: NotchedNavBar.orbSize,
                  child: Semantics(
                    button: true,
                    label: widget.scanSemantics.isEmpty ? widget.scanLabel : widget.scanSemantics,
                    child: ObsidianPressable(
                      key: NotchedNavBar.scanButtonKey,
                      onTap: widget.onScanTap,
                      pressedScale: 0.94,
                      child: _ScanOrb(breath: _breath, spin: _spin),
                    ),
                  ),
                ),
              ],
            );
          }),
        ),
      ),
    );
  }
}

class _NavCell extends StatelessWidget {
  final NotchedNavItem item;
  final bool active;
  final ObsidianStyle style;

  const _NavCell({required this.item, required this.active, required this.style});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: active,
      label: item.label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: item.onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon3D(
              item.asset,
              size: active ? 32 : 30,
              dimmed: !active,
              shadows: active ? const [IconDropShadow.violetGlow] : const [],
            ),
            const SizedBox(height: 2),
            Text(
              item.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style.ui(
                fontSize: 11,
                height: 1.3,
                fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                color: active ? ObsidianColors.text : ObsidianColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ปุ่มสแกนกลม: เรืองแสงเต้น → วงแหวนไล่สีหมุน → จานดำ + ไอคอน 3D + เงาวาว
class _ScanOrb extends StatelessWidget {
  final Animation<double> breath;
  final Animation<double> spin;

  const _ScanOrb({required this.breath, required this.spin});

  // navPulse: 0%/100% กับ 50% (เติมเงาฟ้าใสไว้ให้จำนวนเท่ากันเพื่อ lerp ได้)
  static const _calm = [
    CssShadow(0, 0, 10, 0, Color(0x598B5CF6)), // violet .35
    CssShadow(0, 0, 0, 0, Color(0x0022D3EE)),
    CssShadow(0, 14, 26, -6, Color(0xE6000000)),
  ];
  static const _peak = [
    CssShadow(0, 0, 34, 10, Color(0xBF8B5CF6)), // violet .75
    CssShadow(0, 0, 60, 18, Color(0x4D22D3EE)), // cyan .30
    CssShadow(0, 14, 26, -6, Color(0xE6000000)),
  ];

  static const _disc = ObsidianSurface(
    radius: 30,
    gradient: RadialGradient(
      center: Alignment(0, -0.3),
      radius: 0.82,
      colors: [Color(0xFF1E2230), Color(0xFF0A0B10)],
      stops: [0, 0.7],
    ),
    topHighlight: Color(0x2EFFFFFF), // inset 0 2px 0 rgba(255,255,255,.18)
    topHighlightWidth: 2,
    innerShadows: [CssShadow(0, -3, 6, 0, Color(0x99000000))],
  );

  @override
  Widget build(BuildContext context) {
    const size = NotchedNavBar.orbSize;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // เรืองแสงเต้น 4 วิ
        Positioned.fill(
          child: AnimatedBuilder(
            animation: breath,
            builder: (_, _) {
              final b = Curves.easeInOut.transform(breath.value);
              return CustomPaint(
                painter: ObsidianSurfacePainter(ObsidianSurface(
                  radius: size / 2,
                  shadows: [for (var i = 0; i < 3; i++) CssShadow.lerp(_calm[i], _peak[i], b)],
                )),
              );
            },
          ),
        ),
        // วงแหวนไล่สีหมุน (conic-gradient from 0deg = เริ่มที่ 12 นาฬิกา)
        Positioned.fill(
          child: RepaintBoundary(
            child: AnimatedBuilder(
              animation: spin,
              builder: (_, _) => DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: SweepGradient(
                    colors: const [ObsidianColors.cyan, ObsidianColors.violet, ObsidianColors.orange, ObsidianColors.cyan],
                    stops: const [0, 1 / 3, 2 / 3, 1],
                    transform: GradientRotation(spin.value * 2 * math.pi - math.pi / 2),
                  ),
                ),
              ),
            ),
          ),
        ),
        // จานดำด้านใน (inset 3) + ไอคอนสแกน 84px ที่ถูกตัดขอบเหลือแต่ลวดลายกลาง
        Positioned.fill(
          left: 3,
          top: 3,
          right: 3,
          bottom: 3,
          child: ClipOval(
            child: CustomPaint(
              painter: const ObsidianSurfacePainter(_disc),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  const Center(
                    child: OverflowBox(
                      maxWidth: 84,
                      maxHeight: 84,
                      child: Icon3D(ObsidianIcons.scan, size: 84),
                    ),
                  ),
                  // เงาวาวครึ่งบน
                  Positioned(
                    left: 6,
                    right: 6,
                    top: 3,
                    height: 24,
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(999),
                          gradient: const LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Color(0x38FFFFFF), Color(0x00FFFFFF)],
                          ),
                        ),
                      ),
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

class _BarClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) => NotchedNavBar.barPath(size.width);

  @override
  bool shouldReclip(_BarClipper old) => false;
}

/// เงาทรงแถบ — CSS: filter blur(14px) · opacity .9 · translateY(14px)
class _BarShadowPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(0, 14);
    canvas.drawPath(
      NotchedNavBar.barPath(size.width),
      Paint()
        ..color = const Color(0xE6000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BarShadowPainter old) => false;
}

/// ขอบบนสะท้อนแสง (ไล่ขาว .22 → .05 → ดำ .4) + เส้นเรืองรอยเว้า (cyan → violet → orange)
class _BarRimPainter extends CustomPainter {
  /// ความสว่างของเส้นเรือง 0.3..1 (navGlow)
  final double glow;

  _BarRimPainter({required this.glow});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final bar = NotchedNavBar.barPath(w);

    // ขอบ 1px ด้านในของรูปแถบ (ตัดให้เหลือแต่ครึ่งใน)
    canvas.save();
    canvas.clipPath(bar);
    canvas.drawPath(
      bar,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..shader = ui.Gradient.linear(
          Offset.zero,
          const Offset(0, NotchedNavBar.barHeight),
          const [Color(0x38FFFFFF), Color(0x0DFFFFFF), Color(0x66000000)],
          const [0, 0.35, 1],
        ),
    );
    canvas.restore();

    final cx = w / 2;
    final notch = NotchedNavBar.notchPath(w);
    // ไล่สีตามแนวนอน — ปลายสองข้างจางหาย (เงาเรืองก็ต้องจางตาม เหมือน drop-shadow ของ CSS)
    Shader grad(List<Color> cs) => ui.Gradient.linear(
          Offset(cx - 67, 0),
          Offset(cx + 67, 0),
          cs,
          const [0, 0.18, 0.5, 0.82, 1],
        );
    List<Color> tint(Color c, double k) =>
        [c.withValues(alpha: 0), c.withValues(alpha: k), c.withValues(alpha: k), c.withValues(alpha: k), c.withValues(alpha: 0)];
    Paint stroke(Shader sh, [double sigma = 0]) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..shader = sh
      ..maskFilter = sigma > 0 ? MaskFilter.blur(BlurStyle.normal, sigma) : null;

    // drop-shadow(0 0 10px rgba(34,211,238,.7)) + drop-shadow(0 0 4px violet)
    canvas.drawPath(notch, stroke(grad(tint(ObsidianColors.cyan, 0.7 * glow)), 5));
    canvas.drawPath(notch, stroke(grad(tint(ObsidianColors.violet, glow)), 2));
    canvas.drawPath(
      notch,
      stroke(grad([
        ObsidianColors.cyan.withValues(alpha: 0),
        ObsidianColors.cyan.withValues(alpha: glow),
        ObsidianColors.violet.withValues(alpha: glow),
        ObsidianColors.orange.withValues(alpha: glow),
        ObsidianColors.orange.withValues(alpha: 0),
      ])),
    );
  }

  @override
  bool shouldRepaint(_BarRimPainter old) => old.glow != glow;
}
