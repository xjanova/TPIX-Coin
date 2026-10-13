/// TPIX Wallet — ชิ้นส่วนหน้ารับเงินธีม Obsidian (ตาม A-Receive.dc.html)
///
///   - [ReceivePalette]   สี 3 ตัวของวงแหวนหมุน + เรืองแสง ต่อเชน (ค่าจาก mock)
///   - [ChainChipsTall]   ชิปเลือกเชนแบบสูง 58 (โลโก้บน ป้ายล่าง) — radio group
///   - [ReceiveQrCard]    การ์ด QR ขอบไล่สีหมุน 4 วิ + เหรียญพุ่ง/วงกระเพื่อมตอนเงินเข้า
///   - [PulseDot]         จุดเขียวเต้น "รอรับเงิน"
///   - [IncomingToast]    แถบเงินเข้าเลื่อนลงจากบน + ตัวเลขนับขึ้น
///
/// QR ต้องสแกนได้จริงเสมอ (qr_flutter) — QR ใน mock เป็นลายสุ่มตัวอย่าง
///
/// Developed by Xman Studio
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/themes/obsidian_tokens.dart';
import 'chain_card_deck.dart';
import 'icon_3d.dart';
import 'obsidian_assets.dart';
import 'obsidian_loop.dart';
import 'obsidian_panel.dart';

/// สีประจำเชนของหน้ารับเงิน (c1 → c2 → c3 ไล่รอบวงแหวน · glow = เรืองหลังการ์ด)
@immutable
class ReceivePalette {
  final Color c1;
  final Color c2;
  final Color c3;
  final Color glow;

  const ReceivePalette(this.c1, this.c2, this.c3, this.glow);

  /// เรืองแสงเข้มตอนเงินเข้า (mock: alpha ของ glow → .6)
  Color get glowStrong => glow.withValues(alpha: 0.6);

  static const tpix = ReceivePalette(
      Color(0xFF22D3EE), Color(0xFF8B5CF6), Color(0xFFFB923C), Color(0x4D8B5CF6)); // .30
  static const bsc = ReceivePalette(
      Color(0xFFF3BA2F), Color(0xFFF59E0B), Color(0xFFFDE68A), Color(0x3DF3BA2F)); // .24
  static const polygon = ReceivePalette(
      Color(0xFF8247E5), Color(0xFFA78BFA), Color(0xFF6D28D9), Color(0x4D8247E5)); // .30
  static const ethereum = ReceivePalette(
      Color(0xFF627EEA), Color(0xFFA5B4FC), Color(0xFFE0E7FF), Color(0x4D627EEA)); // .30

  static ReceivePalette of(int chainId) => switch (chainId) {
        56 => bsc,
        137 => polygon,
        1 => ethereum,
        _ => tpix,
      };
}

// ═══════════════════════════════════════════════════════════════
//  ชิปเลือกเชน (แบบสูง)
// ═══════════════════════════════════════════════════════════════

class ChainChipsTall extends StatelessWidget {
  final List<ObsidianChainArt> chains;

  /// ป้ายใต้โลโก้ (ตามลำดับ [chains])
  final List<String> labels;

  final int activeIndex;
  final ValueChanged<int> onSelect;

  /// ระหว่างเล่นแอนิเมชันเงินเข้า mock ล็อกการสลับเชนไว้
  final bool locked;

  final String semanticLabel;

  const ChainChipsTall({
    super.key,
    required this.chains,
    required this.labels,
    required this.activeIndex,
    required this.onSelect,
    this.locked = false,
    this.semanticLabel = '',
  }) : assert(labels.length == chains.length);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      container: true,
      child: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.3,
        child: Row(
          children: [
            for (var i = 0; i < chains.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(
                child: _TallChip(
                  art: chains[i],
                  label: labels[i],
                  palette: ReceivePalette.of(chains[i].chainId),
                  active: i == activeIndex,
                  // กดตัวที่เลือกอยู่แล้ว/ระหว่างเงินเข้า = ไม่ทำอะไร
                  onTap: i == activeIndex || locked ? null : () => onSelect(i),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TallChip extends StatelessWidget {
  final ObsidianChainArt art;
  final String label;
  final ReceivePalette palette;
  final bool active;
  final VoidCallback? onTap;

  const _TallChip({
    required this.art,
    required this.label,
    required this.palette,
    required this.active,
    required this.onTap,
  });

  static ObsidianSurface _surface(Color accent, double t) {
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return ObsidianSurface(
      radius: 16,
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          mix(const Color(0x0FFFFFFF), const Color(0x24FFFFFF)), // .06 → .14
          mix(const Color(0x05FFFFFF), const Color(0x0AFFFFFF)), // .02 → .04
        ],
      ),
      topHighlight: mix(const Color(0x1AFFFFFF), const Color(0x38FFFFFF)), // .10 → .22
      ring: t <= 0 ? null : accent.withValues(alpha: t),
      ringWidth: 1.5,
      shadows: [
        CssShadow.lerp(
          const CssShadow(0, 8, 18, -10, Color(0xE6000000)),
          CssShadow(0, 10, 26, -8, accent),
          t,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final st = ObsidianStyle.of(context);
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: active,
      button: true,
      label: label,
      child: ObsidianPressable(
        onTap: onTap,
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: active ? 1 : 0),
          duration: const Duration(milliseconds: 350),
          curve: Curves.ease,
          builder: (context, t, _) => Opacity(
            // mock: ชิปที่ไม่ได้เลือกจาง .85
            opacity: 0.85 + 0.15 * t,
            child: SizedBox(
              height: 58,
              child: CustomPaint(
                painter: ObsidianSurfacePainter(_surface(palette.c1, t)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ObsidianChainLogo(art: art, size: 26),
                        const SizedBox(height: 4),
                        ExcludeSemantics(
                          child: Text(
                            label,
                            style: st.ui(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              height: 1.2,
                              color: Color.lerp(ObsidianColors.textSec, Colors.white, t),
                            ),
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
      ),
    );
  }
}

/// โลโก้เหรียญวงกลมของเชน — ใช้ซ้ำในการ์ด QR / เหรียญพุ่ง / แถบเงินเข้า
Widget receiveCoinLogo(ObsidianChainArt art, double size) => ObsidianChainLogo(art: art, size: size);

// ═══════════════════════════════════════════════════════════════
//  การ์ด QR
// ═══════════════════════════════════════════════════════════════

class ReceiveQrCard extends StatefulWidget {
  /// ข้อมูลใน QR (ที่อยู่กระเป๋า) — ต้องไม่ว่าง
  final String data;

  final ReceivePalette palette;

  /// โลโก้กลาง QR (46px)
  final Widget logo;

  /// โลโก้เหรียญที่พุ่งออกตอนเงินเข้า (34px)
  final Widget coin;

  /// เปลี่ยนค่าเมื่อไร = เล่นเหรียญพุ่ง + วงกระเพื่อมหนึ่งครั้ง (0 = ยังไม่เคย)
  final int burstTick;

  final String semanticLabel;

  const ReceiveQrCard({
    super.key,
    required this.data,
    required this.palette,
    required this.logo,
    required this.coin,
    this.burstTick = 0,
    this.semanticLabel = '',
  });

  static const double size = 282;

  /// ปลายทางของเหรียญ 8 ทิศ (px จากกลางการ์ด — คีย์เฟรม rcvCoin0..7 ใน mock)
  static const coinTargets = <Offset>[
    Offset(143, 4),
    Offset(70, 93),
    Offset(-44, 103),
    Offset(-133, 30),
    Offset(-143, -84),
    Offset(-70, -173),
    Offset(44, -183),
    Offset(133, -110),
  ];

  @override
  State<ReceiveQrCard> createState() => _ReceiveQrCardState();
}

class _ReceiveQrCardState extends State<ReceiveQrCard> with SingleTickerProviderStateMixin {
  /// เวลาเล่นทั้งชุด = วงกระเพื่อม 1.1 วิ × 2 รอบ (ยาวที่สุดในชุด)
  static const _burstMs = 2200;

  late final AnimationController _burst =
      AnimationController(vsync: this, duration: const Duration(milliseconds: _burstMs));

  static const _coinCurve = Cubic(0.15, 0.7, 0.2, 1);

  @override
  void didUpdateWidget(ReceiveQrCard old) {
    super.didUpdateWidget(old);
    if (widget.burstTick != old.burstTick && widget.burstTick > 0) {
      final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
      // ลดภาพเคลื่อนไหว → ไม่เล่นเหรียญพุ่ง (แถบแจ้งเงินเข้ายังขึ้นตามปกติ)
      if (!reduce) _burst.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _burst.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    const s = ReceiveQrCard.size;
    return SizedBox.square(
      dimension: s,
      child: AnimatedBuilder(
        animation: _burst,
        child: _card(p),
        builder: (context, card) {
          final ms = _burst.value * _burstMs;
          final active = _burst.isAnimating;
          return Stack(
            clipBehavior: Clip.none,
            children: [
              if (active) ..._glowAndRipple(p, ms),
              Positioned.fill(child: card!),
              if (active) ..._coins(ms),
            ],
          );
        },
      ),
    );
  }

  /// เรืองแสงแรง (1.6 วิ) + วงขอบกระเพื่อม 2 รอบ (รอบละ 1.1 วิ)
  List<Widget> _glowAndRipple(ReceivePalette p, double ms) {
    final out = <Widget>[];
    if (ms < 1600) {
      final t = Curves.easeOut.transform(ms / 1600);
      final o = t < 0.3 ? t / 0.3 : 1 - (t - 0.3) / 0.7;
      out.add(Positioned(
        left: -30,
        top: -30,
        right: -30,
        bottom: -30,
        child: IgnorePointer(
          child: Opacity(
            opacity: o.clamp(0.0, 1.0),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(60),
                gradient: RadialGradient(colors: [p.glowStrong, p.glowStrong.withValues(alpha: 0)]),
              ),
            ),
          ),
        ),
      ));
    }
    final r = (ms % 1100) / 1100;
    if (ms < 2200) {
      final t = Curves.easeOut.transform(r);
      out.add(Positioned(
        left: -10,
        top: -10,
        right: -10,
        bottom: -10,
        child: IgnorePointer(
          child: Opacity(
            opacity: (0.85 * (1 - t)).clamp(0.0, 1.0),
            child: Transform.scale(
              scale: 0.7 + 1.2 * t,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(40),
                  border: Border.all(color: p.c1, width: 3),
                ),
              ),
            ),
          ),
        ),
      ));
    }
    return out;
  }

  /// เหรียญ 8 เหรียญพุ่งออก (หน่วงทีละ 50ms) — หมุนรอบแกนตั้ง 2 รอบ
  List<Widget> _coins(double ms) {
    const half = ReceiveQrCard.size / 2;
    final out = <Widget>[];
    for (var k = 0; k < ReceiveQrCard.coinTargets.length; k++) {
      final local = (ms - k * 50) / 1100;
      if (local <= 0 || local >= 1) continue;
      final p = _coinCurve.transform(local);
      final target = ReceiveQrCard.coinTargets[k];
      final scale = 0.3 + 0.7 * p;
      // CSS rotateY ไม่มี perspective = บีบแกน x ด้วย cos(มุม)
      final flip = math.cos(p * 4 * math.pi);
      final opacity = local < 0.15 ? local / 0.15 : 1 - (local - 0.15) / 0.85;
      out.add(Positioned(
        left: half - 17 + target.dx * p,
        top: half - 17 + target.dy * p,
        width: 34,
        height: 34,
        child: IgnorePointer(
          child: Opacity(
            opacity: opacity.clamp(0.0, 1.0),
            child: Transform(
              alignment: Alignment.center,
              transform: Matrix4.diagonal3Values(scale * flip, scale, 1),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [const CssShadow(0, 6, 10, 0, Color(0xB3000000)).toBoxShadow()],
                ),
                child: widget.coin,
              ),
            ),
          ),
        ),
      ));
    }
    return out;
  }

  Widget _card(ReceivePalette p) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(34),
        boxShadow: [
          const CssShadow(0, 30, 60, -20, Color(0xF2000000)).toBoxShadow(),
          CssShadow(0, 0, 40, -10, p.c1).toBoxShadow(),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(34),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // ขอบไล่สีหมุน 4 วิ/รอบ (conic-gradient from 0deg = เริ่มที่ 12 นาฬิกา)
            ObsidianLoop(
              period: const Duration(seconds: 4),
              builder: (context, t, _) => CustomPaint(painter: _ConicPainter(p, t)),
            ),
            Padding(
              padding: const EdgeInsets.all(3),
              child: CustomPaint(
                painter: const ObsidianSurfacePainter(ObsidianSurface(
                  radius: 31,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFF161922), Color(0xFF0B0D12)],
                  ),
                  topHighlight: Color(0x1FFFFFFF),
                )),
              ),
            ),
            Positioned(
              left: 24,
              top: 24,
              width: 234,
              height: 234,
              child: _plate(),
            ),
          ],
        ),
      ),
    );
  }

  /// แผ่นขาวของ QR — พื้นขาวเสมอ (กล้องอ่านคอนทราสต์กลับสีไม่ได้)
  Widget _plate() {
    const ink = Color(0xFF0B0D12);
    return CustomPaint(
      painter: const ObsidianSurfacePainter(ObsidianSurface(
        radius: 18,
        color: Color(0xFFF7F8FA),
        innerShadows: [CssShadow(0, 2, 6, 0, Color(0x40000000))],
      )),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Semantics(
            label: widget.semanticLabel,
            image: true,
            child: QrImageView(
              data: widget.data,
              version: QrVersions.auto,
              size: 210,
              padding: EdgeInsets.zero,
              backgroundColor: const Color(0xFFF7F8FA),
              // ที่อยู่ + โลโก้บังกลาง → ระดับกู้คืน H (30%) เหมือนหน้ารับเงินเดิม
              errorCorrectionLevel: QrErrorCorrectLevel.H,
              eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: ink),
              dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: ink),
            ),
          ),
          // โลโก้วาดทับด้วย Flutter เอง (ไม่ใช้ embeddedImage ของ qr_flutter
          // ซึ่งคืนกล่องเปล่าทั้งใบถ้าโลโก้โหลดพลาด — กับดักเดิมของหน้านี้)
          Container(
            width: 58,
            height: 58,
            alignment: Alignment.center,
            decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFF7F8FA)),
            child: SizedBox.square(dimension: 46, child: widget.logo),
          ),
        ],
      ),
    );
  }
}

class _ConicPainter extends CustomPainter {
  final ReceivePalette p;
  final double t;

  const _ConicPainter(this.p, this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    // mock วาดสี่เหลี่ยม 420px แล้วหมุน — วาดวงกลมรัศมีครอบมุมการ์ดแทน ได้ผลเหมือนกัน
    final r = size.longestSide;
    final shader = SweepGradient(
      colors: [p.c1, p.c2, p.c3, p.c1],
      transform: GradientRotation(-math.pi / 2 + 2 * math.pi * t),
    ).createShader(Rect.fromCircle(center: c, radius: r));
    canvas.drawCircle(c, r, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(_ConicPainter old) => old.t != t || old.p != p;
}

// ═══════════════════════════════════════════════════════════════
//  จุดเต้น "รอรับเงิน"
// ═══════════════════════════════════════════════════════════════

class PulseDot extends StatelessWidget {
  final Color color;
  final double size;

  const PulseDot({super.key, this.color = ObsidianColors.success, this.size = 8});

  @override
  Widget build(BuildContext context) {
    // mock rcvPulse 1.6 วิ: วงรอบจุดขยาย 0→10px + จางจาก .7 → 0 ภายใน 70% แรกของรอบ
    return ObsidianLoop(
      period: const Duration(milliseconds: 1600),
      restValue: 0,
      builder: (context, t, _) {
        final k = t < 0.7 ? t / 0.7 : 1.0;
        return SizedBox.square(
          dimension: size,
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              boxShadow: [
                if (k < 1)
                  BoxShadow(color: color.withValues(alpha: 0.7 * (1 - k)), spreadRadius: 10 * k),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  แถบเงินเข้า
// ═══════════════════════════════════════════════════════════════

/// ข้อมูลเงินเข้าหนึ่งครั้ง
@immutable
class IncomingInfo {
  /// จำนวนสุดท้ายที่แสดง (สตริงเต็มความแม่นยำ เช่น "250" / "0.05")
  final String amountText;

  /// จำนวนแบบ double — ใช้ทำตัวเลขนับขึ้นเท่านั้น
  final double amount;

  /// ทศนิยมที่โชว์ระหว่างนับ
  final int fractionDigits;

  final String symbol;
  final Widget logo;

  const IncomingInfo({
    required this.amountText,
    required this.amount,
    required this.fractionDigits,
    required this.symbol,
    required this.logo,
  });
}

class IncomingToast extends StatefulWidget {
  final IncomingInfo info;
  final String title;
  final Color accent;

  /// เล่นจบ (เลื่อนกลับขึ้นไปแล้ว)
  final VoidCallback onDone;

  const IncomingToast({
    super.key,
    required this.info,
    required this.title,
    required this.accent,
    required this.onDone,
  });

  /// mock rcvToast 3.6 วิ
  static const total = Duration(milliseconds: 3600);

  /// ตัวเลขนับขึ้น 24 ขั้น × 34ms
  static const countUp = Duration(milliseconds: 816);

  @override
  State<IncomingToast> createState() => _IncomingToastState();
}

class _IncomingToastState extends State<IncomingToast> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: IncomingToast.total)
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed && mounted) widget.onDone();
      })
      ..forward();
  }

  static const _ease = Cubic(0.2, 0.8, 0.2, 1);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  String _count(double t) {
    final i = widget.info;
    final k = (t * IncomingToast.total.inMilliseconds / IncomingToast.countUp.inMilliseconds).clamp(0.0, 1.0);
    // จบที่สตริงจริงเสมอ (ไม่ใช่ double ที่ปัดเศษ)
    if (k >= 1) return i.amountText;
    return (i.amount * k).toStringAsFixed(i.fractionDigits);
  }

  @override
  Widget build(BuildContext context) {
    final st = ObsidianStyle.of(context);
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value;
        // เข้า 0–12% · ค้าง · ออก 85–100%
        final double slide;
        if (reduce) {
          slide = t < 0.97 ? 1 : 0;
        } else if (t < 0.12) {
          slide = _ease.transform(t / 0.12);
        } else if (t < 0.85) {
          slide = 1;
        } else {
          slide = 1 - _ease.transform((t - 0.85) / 0.15);
        }
        return FractionalTranslation(
          translation: Offset(0, -1.4 * (1 - slide)),
          child: Opacity(
            opacity: slide.clamp(0.0, 1.0),
            child: Semantics(
              liveRegion: true,
              label: '${widget.title} +${widget.info.amountText} ${widget.info.symbol}',
              child: ExcludeSemantics(
                child: CustomPaint(
                  painter: ObsidianSurfacePainter(ObsidianSurface(
                    radius: 20,
                    gradient: const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0xF51E222C), Color(0xFA101218)],
                    ),
                    topHighlight: const Color(0x24FFFFFF),
                    shadows: [
                      const CssShadow(0, 24, 40, -14, Color(0xF2000000)),
                      CssShadow(0, 0, 30, -8, widget.accent),
                    ],
                  )),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    child: Row(
                      children: [
                        ObsidianLoop(
                          period: const Duration(milliseconds: 600),
                          reverse: true,
                          builder: (context, f, child) => Transform.translate(
                            offset: Offset(0, -6 * Curves.easeInOut.transform(f)),
                            child: child,
                          ),
                          child: SizedBox.square(dimension: 40, child: widget.info.logo),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                widget.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: st.ui(fontSize: 12, color: ObsidianColors.textSec),
                              ),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  '+${_count(t)} ${widget.info.symbol}',
                                  maxLines: 1,
                                  style: st.number(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w700,
                                    color: ObsidianColors.successSoft,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon3D(ObsidianIcons.shield, size: 30),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
