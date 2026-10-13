/// TPIX Wallet — การ์ดเส้นทางข้ามเชน (ธีม Obsidian)
///
/// ตาม A-Bridge.dc.html: โหนดเชนต้นทาง · รางแสง · โหนดเชนปลายทาง
///   - โหนด 58px พื้นเรเดียลเข้ม + วงขอบ 2px สีเชน + แสงม่วงเต้น (brRing 3 วิ — ปลายทางช้ากว่าครึ่งจังหวะ)
///   - ราง 4px ไล่สีจาง + จุดแสงขาว 3 ดวงไหลจากซ้ายไปขวา (brFlow 1.8 วิ ห่างกัน .6 วิ)
///   - ป้ายเวลาโดยประมาณกลางราง
///
/// [flowing] = false (สะพานยังไม่เปิด) → จุดแสงหยุดนิ่งจาง ๆ ไม่ชวนให้เข้าใจว่ากำลังโอนอยู่
/// เปิด "ลดภาพเคลื่อนไหว" = ไม่มีอะไรขยับ
///
/// Developed by Xman Studio
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/themes/obsidian_tokens.dart';
import 'obsidian_cards.dart';
import 'obsidian_panel.dart';

@immutable
class ObsidianRouteNode {
  /// โลโก้วงกลม 42px
  final Widget logo;
  final String title;
  final String caption;

  /// สีวงขอบ (สีประจำเชน)
  final Color ring;

  /// แตะเพื่อเปลี่ยนเชน — null = เปลี่ยนไม่ได้ (ไม่มีลูกศร ▾)
  final VoidCallback? onTap;
  final String? semanticLabel;

  const ObsidianRouteNode({
    required this.logo,
    required this.title,
    required this.caption,
    required this.ring,
    this.onTap,
    this.semanticLabel,
  });
}

class ObsidianRouteCard extends StatefulWidget {
  final ObsidianRouteNode from;
  final ObsidianRouteNode to;

  /// ป้ายกลางราง (เช่น "~3 นาที")
  final String? badge;

  final bool flowing;

  const ObsidianRouteCard({super.key, required this.from, required this.to, this.badge, this.flowing = true});

  @override
  State<ObsidianRouteCard> createState() => _ObsidianRouteCardState();
}

class _ObsidianRouteCardState extends State<ObsidianRouteCard> with TickerProviderStateMixin {
  late final AnimationController _flow = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800));
  late final AnimationController _ring = AnimationController(vsync: this, duration: const Duration(seconds: 3));
  bool _reduce = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    _sync();
  }

  @override
  void didUpdateWidget(ObsidianRouteCard old) {
    super.didUpdateWidget(old);
    if (old.flowing != widget.flowing) _sync();
  }

  void _sync() {
    if (_reduce) {
      _flow.stop();
      _ring.stop();
      return;
    }
    if (!_ring.isAnimating) _ring.repeat();
    if (widget.flowing) {
      if (!_flow.isAnimating) _flow.repeat();
    } else {
      _flow.stop();
    }
  }

  @override
  void dispose() {
    _flow.dispose();
    _ring.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ObsidianPanel(
      surface: ObsidianCards.hero,
      blur: 16,
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 86,
            child: _Node(node: widget.from, ring: _ring, phase: 0, live: !_reduce),
          ),
          Expanded(child: _track()),
          SizedBox(
            width: 86,
            child: _Node(node: widget.to, ring: _ring, phase: 0.5, live: !_reduce),
          ),
        ],
      ),
    );
  }

  Widget _track() {
    final st = ObsidianStyle.of(context);
    final dots = [ObsidianColors.violet, ObsidianColors.cyan, widget.from.ring];
    return SizedBox(
      height: 58,
      child: LayoutBuilder(
        builder: (context, box) {
          final w = box.maxWidth;
          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 4,
                right: 4,
                top: 27,
                height: 4,
                child: Opacity(
                  opacity: 0.35,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(2),
                      gradient: LinearGradient(
                        colors: [
                          widget.from.ring,
                          ObsidianColors.violet,
                          widget.to.ring == ObsidianColors.violet ? ObsidianColors.cyan : widget.to.ring,
                        ],
                        stops: const [0, 0.55, 1],
                      ),
                    ),
                  ),
                ),
              ),
              AnimatedBuilder(
                animation: _flow,
                builder: (context, _) {
                  final moving = widget.flowing && !_reduce;
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      for (var i = 0; i < dots.length; i++)
                        _dot(
                          w: w,
                          // brFlow: ไหล 0→100% · จาง 0–12% / 88–100% · ดวงถัดไปช้ากว่า .6 วิ
                          t: moving ? (_flow.value - i / 3) % 1.0 : 0.25 + i * 0.25,
                          glow: dots[i],
                          moving: moving,
                        ),
                    ],
                  );
                },
              ),
              if (widget.badge != null)
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0x73000000),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        widget.badge!,
                        maxLines: 1,
                        style: st.ui(fontSize: 10.5, color: ObsidianColors.chrome, height: 1.35),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _dot({required double w, required double t, required Color glow, required bool moving}) {
    double opacity;
    if (!moving) {
      opacity = widget.flowing ? 1 : 0.35;
    } else if (t < 0.12) {
      opacity = t / 0.12;
    } else if (t > 0.88) {
      opacity = (1 - t) / 0.12;
    } else {
      opacity = 1;
    }
    return Positioned(
      left: w * t - 5,
      top: 24,
      child: Opacity(
        opacity: opacity.clamp(0.0, 1.0),
        child: Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
            boxShadow: [CssShadow(0, 0, 10, 3, glow).toBoxShadow()],
          ),
        ),
      ),
    );
  }
}

class _Node extends StatelessWidget {
  final ObsidianRouteNode node;
  final Animation<double> ring;
  final double phase;
  final bool live;

  const _Node({required this.node, required this.ring, required this.phase, required this.live});

  @override
  Widget build(BuildContext context) {
    final st = ObsidianStyle.of(context);
    final center = Color.lerp(const Color(0xFF07080C), node.ring, 0.16)!;
    final edge = Color.lerp(const Color(0xFF07080C), node.ring, 0.05)!;

    final body = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: ring,
          builder: (context, child) {
            // brRing: 0%/100% → 0 0 0 0 .0 + 0 0 18px 2px .35 · 50% → 0 0 0 6px .12 + 0 0 30px 8px .55
            final t = live ? (1 - math.cos(((ring.value + phase) % 1.0) * 2 * math.pi)) / 2 : 0.0;
            return DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  CssShadow.lerp(
                    const CssShadow(0, 0, 0, 0, Color(0x008B5CF6)),
                    const CssShadow(0, 0, 0, 6, Color(0x1F8B5CF6)),
                    t,
                  ).toBoxShadow(),
                  CssShadow.lerp(
                    const CssShadow(0, 0, 18, 2, Color(0x598B5CF6)),
                    const CssShadow(0, 0, 30, 8, Color(0x8C8B5CF6)),
                    t,
                  ).toBoxShadow(),
                ],
              ),
              child: child,
            );
          },
          child: Container(
            width: 58,
            height: 58,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(center: const Alignment(0, -0.3), colors: [center, edge]),
              border: Border.all(color: node.ring, width: 2),
            ),
            child: SizedBox(width: 42, height: 42, child: node.logo),
          ),
        ),
        const SizedBox(height: 6),
        // ลูกศร ▾ ติดท้ายชื่อเสมอ (ชื่อยาวขึ้นบรรทัดใหม่ ลูกศรตามไปด้วย)
        Text.rich(
          TextSpan(
            text: node.title,
            children: [
              if (node.onTap != null)
                const WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: Icon(Icons.arrow_drop_down_rounded, size: 16, color: ObsidianColors.chrome),
                ),
            ],
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: st.ui(fontSize: 11.5, fontWeight: FontWeight.w600, color: ObsidianColors.text, height: 1.3),
        ),
        const SizedBox(height: 6),
        Text(
          node.caption,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: st.ui(fontSize: 10.5, color: ObsidianColors.textMuted, height: 1.3),
        ),
      ],
    );

    if (node.onTap == null) {
      return Semantics(label: '${node.caption} ${node.title}', container: true, excludeSemantics: true, child: body);
    }
    // ตัวอ่านหน้าจอ: "เปลี่ยนเชนต้นทาง" + ค่า = เชนที่เลือกอยู่
    return Semantics(
      value: node.title,
      child: ObsidianPressable(
        onTap: node.onTap,
        semanticLabel: node.semanticLabel ?? node.caption,
        pressedScale: 0.95,
        child: ExcludeSemantics(child: body),
      ),
    );
  }
}
