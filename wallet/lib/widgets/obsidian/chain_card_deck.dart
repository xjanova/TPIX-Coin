/// TPIX Wallet — สำรับบัตรโลหะประจำเชน (หน้าแรกธีม Obsidian)
///
/// พอร์ตจาก Main.dc.html ตรงตัว:
///   ตำแหน่งในสำรับ 4 ช่อง (POS ใน mock)
///     0 = หน้าสุด · 1-2 = ซ้อนด้านหลัง (เลื่อนลง ถอยลึก ย่อ หรี่) · 3 = ใบที่เพิ่งพลิกออกซ้าย
///   transition: transform .75s cubic-bezier(.2,.85,.2,1) · opacity/filter .55s ease
///   perspective 1100px ที่กึ่งกลางสำรับ · transform-origin ขอบล่างกลางบัตร
///   แสงวาบพาดบัตร 1.1s (หน่วง .25s) ทุกครั้งที่สลับใบ
///
/// สำรับนี้ "ไม่ถือสถานะเชนเอง" — [activeIndex] มาจากเชนจริงของกระเป๋า
/// กดชิป/ปัดบัตร → [onSelect] → หน้าแรกเรียก wallet.switchChain (ทางเดียวกับแผ่นเลือกเชนเดิม)
/// → เชนเปลี่ยนจริงแล้วสำรับค่อยพลิกตาม (ไม่มีทางที่บัตรกับเชนจริงจะไม่ตรงกัน)
///
/// วาดทุกอย่างในพิกัดดีไซน์ 342 x 258 แล้วย่อ/ขยายทั้งก้อนให้พอดีความกว้างจริง
/// → สัดส่วนตรง mock ทุกขนาดจอ
///
/// Developed by Xman Studio
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/themes/obsidian_tokens.dart';
import '../tpix_coin_logo.dart';
import 'chain_emblem.dart';
import 'obsidian_assets.dart';
import 'obsidian_panel.dart';

/// ข้อมูลที่แสดงบนบัตรหนึ่งใบ (ทุกตัวเลขมาจากยอดจริงของกระเป๋า)
@immutable
class ChainCardData {
  final ObsidianChainArt art;

  /// ชื่อเต็มบนป้ายมุมซ้ายบน (เช่น "TPIX Chain")
  final String chainName;

  /// ป้ายเหนือยอด (เช่น "ยอดบนเชนนี้")
  final String balanceLabel;

  /// ยอดเหรียญหลัก — "—" เมื่อยังไม่เคยดึงยอดได้ (ไม่ใช่ 0)
  final String amount;

  /// หน่วยต่อท้ายยอด (TPIX / BNB / POL / ETH)
  final String unit;

  /// บรรทัดใต้ยอด (มูลค่า/เปลี่ยนแปลง หรือคำเตือนยอดเก่า) — null = ไม่แสดง
  final String? subline;
  final Color? sublineColor;

  /// ที่อยู่ย่อ (0xD2eA…67d7)
  final String address;

  /// ข้อความค่าแก๊สมุมขวาล่าง
  final String gasText;

  const ChainCardData({
    required this.art,
    required this.chainName,
    required this.balanceLabel,
    required this.amount,
    required this.unit,
    required this.address,
    required this.gasText,
    this.subline,
    this.sublineColor,
  });
}

/// ท่าของบัตรหนึ่งใบ (ค่าเดียวกับ POS ใน mock)
@immutable
class _Pose {
  final double tx; // สัดส่วนความกว้างบัตร
  final double ty;
  final double tz;
  final double rotY; // องศา
  final double rotZ;
  final double scale;
  final double opacity;
  final double brightness;

  const _Pose(this.tx, this.ty, this.tz, this.rotY, this.rotZ, this.scale, this.opacity, this.brightness);

  static _Pose lerp(_Pose a, _Pose b, double tm, double tf) => _Pose(
        a.tx + (b.tx - a.tx) * tm,
        a.ty + (b.ty - a.ty) * tm,
        a.tz + (b.tz - a.tz) * tm,
        a.rotY + (b.rotY - a.rotY) * tm,
        a.rotZ + (b.rotZ - a.rotZ) * tm,
        a.scale + (b.scale - a.scale) * tm,
        a.opacity + (b.opacity - a.opacity) * tf,
        a.brightness + (b.brightness - a.brightness) * tf,
      );
}

class ChainCardDeck extends StatefulWidget {
  /// บัตรทุกใบตามลำดับเชนคงที่ (ลำดับเดียวกับชิปใต้สำรับ)
  final List<ChainCardData> cards;

  /// ใบที่อยู่หน้าสุด = เชนที่ใช้งานอยู่จริง
  final int activeIndex;

  /// ผู้ใช้ปัดบัตร → ขอเปลี่ยนเชน (หน้าแรกเป็นคนสลับเชนจริง)
  final ValueChanged<int> onSelect;

  /// กดป้ายชื่อเชนบนบัตร (มีลูกศรลง) → เปิดแผ่นรายละเอียดเชน
  final VoidCallback? onChainPillTap;

  /// กดที่อยู่บนบัตร → คัดลอก
  final VoidCallback? onAddressTap;

  final String chainPillSemantics;
  final String addressSemantics;

  const ChainCardDeck({
    super.key,
    required this.cards,
    required this.activeIndex,
    required this.onSelect,
    this.onChainPillTap,
    this.onAddressTap,
    this.chainPillSemantics = '',
    this.addressSemantics = '',
  });

  /// ขนาดดีไซน์ของ mock
  static const double designWidth = 342;
  static const double cardHeight = 228;
  static const double designHeight = 258;

  /// ความสูงจริงของสำรับที่ความกว้าง [width]
  static double heightFor(double width) => width * designHeight / designWidth;

  @override
  State<ChainCardDeck> createState() => _ChainCardDeckState();
}

class _ChainCardDeckState extends State<ChainCardDeck> with TickerProviderStateMixin {
  // POS ของ mock: [tx, ty, tz, rotY, rotZ, scale, opacity, brightness]
  static const _pos = <_Pose>[
    _Pose(0, 0, 0, 0, 0, 1, 1, 1),
    _Pose(0, 15, -40, 0, 0, 0.94, 0.55, 0.6),
    _Pose(0, 28, -80, 0, 0, 0.88, 0.22, 0.45),
    _Pose(-1.25, -10, 60, -38, -10, 0.92, 0, 1.2),
  ];
  static const _z = [40, 30, 20, 50];

  static const _moveCurve = Cubic(0.2, 0.85, 0.2, 1);
  // opacity/filter จบที่ .55s จาก .75s
  static const _fadeCurve = Interval(0, 0.55 / 0.75, curve: Curves.ease);

  late final AnimationController _move;
  late final AnimationController _shine;
  late List<_Pose> _from;
  late List<_Pose> _to;

  /// เคยสลับใบแล้วหรือยัง — แสงวาบไม่เล่นตอนเปิดหน้าครั้งแรก (เหมือน mock: flips > 0)
  bool _flipped = false;

  int get _n => widget.cards.length;

  int _slot(int i, int active) => ((i - active) % _n + _n) % _n;

  _Pose _poseFor(int slot) => _pos[math.min(slot, _pos.length - 1)];

  @override
  void initState() {
    super.initState();
    _move = AnimationController(vsync: this, duration: const Duration(milliseconds: 750), value: 1);
    // หน่วง .25s + กวาด 1.1s
    _shine = AnimationController(vsync: this, duration: const Duration(milliseconds: 1350));
    _to = [for (var i = 0; i < _n; i++) _poseFor(_slot(i, widget.activeIndex))];
    _from = List.of(_to);
  }

  @override
  void didUpdateWidget(ChainCardDeck old) {
    super.didUpdateWidget(old);
    if (old.cards.length != _n) {
      // จำนวนเชนเปลี่ยน (ไม่ควรเกิด) → จัดใหม่ทันทีไม่ต้องเล่นแอนิเมชัน
      _to = [for (var i = 0; i < _n; i++) _poseFor(_slot(i, widget.activeIndex))];
      _from = List.of(_to);
      _move.value = 1;
      return;
    }
    if (old.activeIndex == widget.activeIndex) return;

    // เริ่มจาก "ท่าปัจจุบันจริง" — สลับรัว ๆ กลางแอนิเมชันก็ไม่กระตุกกลับไปจุดเริ่ม
    final t = _move.value;
    final tm = _moveCurve.transform(t);
    final tf = _fadeCurve.transform(t);
    _from = [for (var i = 0; i < _n; i++) _Pose.lerp(_from[i], _to[i], tm, tf)];
    _to = [for (var i = 0; i < _n; i++) _poseFor(_slot(i, widget.activeIndex))];
    _flipped = true;

    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduce) {
      // ผู้ใช้ตั้งลดภาพเคลื่อนไหว → สลับทันที ไม่มีพลิก/แสงวาบ
      _move.value = 1;
      _shine.value = 0;
      return;
    }
    _move.forward(from: 0);
    _shine.forward(from: 0);
  }

  @override
  void dispose() {
    _move.dispose();
    _shine.dispose();
    super.dispose();
  }

  void _onDragEnd(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0;
    if (v.abs() < 250) return;
    // ปัดซ้าย = ใบถัดไป (ใบหน้าพลิกออกซ้ายเหมือนใน mock) · ปัดขวา = ใบก่อนหน้า
    final next = v < 0 ? (widget.activeIndex + 1) % _n : (widget.activeIndex - 1 + _n) % _n;
    widget.onSelect(next);
  }

  Matrix4 _matrix(_Pose p) {
    const w = ChainCardDeck.designWidth;
    // จุดกำเนิด perspective = กึ่งกลางสำรับ / จุดหมุนของบัตร = ขอบล่างกลาง
    const po = Offset(w / 2, ChainCardDeck.designHeight / 2);
    const to = Offset(w / 2, ChainCardDeck.cardHeight);
    final s = p.scale;
    return Matrix4.identity()
      ..translateByDouble(po.dx, po.dy, 0, 1)
      ..multiply(Matrix4.identity()..setEntry(3, 2, -1 / 1100))
      ..translateByDouble(-po.dx, -po.dy, 0, 1)
      ..translateByDouble(to.dx, to.dy, 0, 1)
      ..translateByDouble(p.tx * w, p.ty, p.tz, 1)
      ..rotateY(p.rotY * math.pi / 180)
      ..rotateZ(p.rotZ * math.pi / 180)
      ..scaleByDouble(s, s, 1, 1)
      ..translateByDouble(-to.dx, -to.dy, 0, 1);
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.cards[widget.activeIndex];

    return LayoutBuilder(builder: (context, box) {
      final width = box.maxWidth;
      final k = width / ChainCardDeck.designWidth;
      final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 3.0;
      // ถอดรหัสหน้าบัตรตามขนาดจริงบนจอ (ไฟล์ 1024px)
      final cacheW = math.min(1024, (width * dpr).ceil());

      return GestureDetector(
        onHorizontalDragEnd: _onDragEnd,
        child: SizedBox(
          width: width,
          height: ChainCardDeck.heightFor(width),
          child: FittedBox(
            fit: BoxFit.fill,
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: ChainCardDeck.designWidth,
              height: ChainCardDeck.designHeight,
              // ตัวหนังสือบนบัตรขยายตามการตั้งค่าเครื่องได้ แต่ไม่เกิน 1.2 เท่า
              // (บัตรสัดส่วนตายตัว ขยายเกินนี้ข้อความจะล้นออกนอกบัตร)
              child: MediaQuery.withClampedTextScaling(
                maxScaleFactor: 1.2,
                child: AnimatedBuilder(
                  animation: Listenable.merge([_move, _shine]),
                  builder: (context, _) {
                    final t = _move.value;
                    final tm = _moveCurve.transform(t);
                    final tf = _fadeCurve.transform(t);
                    final order = List<int>.generate(_n, (i) => i)
                      ..sort((a, b) => _z[_slot(a, widget.activeIndex) % 4]
                          .compareTo(_z[_slot(b, widget.activeIndex) % 4]));
                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        // แสงเรืองใต้สำรับตามสีเชน (เปลี่ยนสีนุ่ม ๆ .8s)
                        Positioned(
                          left: 0,
                          right: 0,
                          top: 36,
                          height: 240,
                          child: IgnorePointer(
                            child: TweenAnimationBuilder<Color?>(
                              tween: ColorTween(end: active.art.glow),
                              duration: const Duration(milliseconds: 800),
                              curve: Curves.ease,
                              builder: (_, c, _) => CustomPaint(
                                painter: ObsidianSurfacePainter(ObsidianSurface(
                                  radius: 40,
                                  shadows: [CssShadow(0, 40, 110, -10, c ?? active.art.glow)],
                                )),
                              ),
                            ),
                          ),
                        ),
                        for (final i in order)
                          _buildCard(context, i, _Pose.lerp(_from[i], _to[i], tm, tf), cacheW, k),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );
    });
  }

  Widget _buildCard(BuildContext context, int i, _Pose pose, int cacheW, double k) {
    final data = widget.cards[i];
    final isFront = i == widget.activeIndex;
    if (pose.opacity <= 0.001) {
      // มองไม่เห็นแล้ว — ไม่ต้องวาด (ประหยัด GPU ตอนใบที่พลิกออกไปค้างอยู่ซ้ายจอ)
      return const SizedBox.shrink();
    }

    Widget card = _ChainCard(
      data: data,
      cacheWidth: cacheW,
      interactive: isFront,
      shine: isFront && _flipped ? _shine.value : null,
      onChainPillTap: widget.onChainPillTap,
      onAddressTap: widget.onAddressTap,
      chainPillSemantics: widget.chainPillSemantics,
      addressSemantics: widget.addressSemantics,
    );

    if ((pose.brightness - 1).abs() > 0.005) {
      final b = pose.brightness;
      card = ColorFiltered(
        colorFilter: ColorFilter.matrix(<double>[
          b, 0, 0, 0, 0, //
          0, b, 0, 0, 0, //
          0, 0, b, 0, 0, //
          0, 0, 0, 1, 0,
        ]),
        child: card,
      );
    }
    if (pose.opacity < 0.999) {
      card = Opacity(opacity: pose.opacity.clamp(0.0, 1.0), child: card);
    }

    return Positioned(
      left: 0,
      top: 0,
      width: ChainCardDeck.designWidth,
      height: ChainCardDeck.cardHeight,
      child: IgnorePointer(
        // ใบหลังไม่รับการแตะ (เหมือน pointer-events: none ใน mock)
        ignoring: !isFront,
        child: Transform(transform: _matrix(pose), child: card),
      ),
    );
  }
}

/// บัตรหนึ่งใบในพิกัดดีไซน์ 342 x 228
class _ChainCard extends StatelessWidget {
  final ChainCardData data;
  final int cacheWidth;
  final bool interactive;

  /// ความคืบหน้าแสงวาบ 0..1 (รวมช่วงหน่วง) — null = ไม่มีแสง
  final double? shine;

  final VoidCallback? onChainPillTap;
  final VoidCallback? onAddressTap;
  final String chainPillSemantics;
  final String addressSemantics;

  const _ChainCard({
    required this.data,
    required this.cacheWidth,
    required this.interactive,
    required this.shine,
    required this.onChainPillTap,
    required this.onAddressTap,
    required this.chainPillSemantics,
    required this.addressSemantics,
  });

  // มุมโค้งของภาพหน้าบัตร = 78/1536 ของความกว้าง ≈ 17.4 → mock ใช้ 18 ตัดมุมเรืองแสงทิ้ง
  static const _radius = 18.0;

  static const _cardShadow = ObsidianSurface(
    radius: _radius,
    shadows: [CssShadow(0, 34, 60, -22, Color(0xF2000000))],
  );
  static const _cardRim = ObsidianSurface(
    radius: _radius,
    topHighlight: Color(0x1FFFFFFF), // inset 0 1px 0 rgba(255,255,255,.12)
  );

  @override
  Widget build(BuildContext context) {
    final st = ObsidianStyle.of(context);
    final art = data.art;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        const Positioned.fill(child: CustomPaint(painter: ObsidianSurfacePainter(_cardShadow))),
        Positioned.fill(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(_radius),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // หน้าบัตรโลหะ (ยืดเต็มบัตรเหมือน background-size: 100% 100%)
                DecoratedBox(
                  decoration: const BoxDecoration(color: Color(0xFF12141B)),
                  child: Image.asset(
                    art.card,
                    fit: BoxFit.fill,
                    cacheWidth: cacheWidth,
                    gaplessPlayback: true,
                    excludeFromSemantics: true,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
                // เงาวาวเฉียง — linear-gradient(115deg, rgba(255,255,255,.10) 0%, transparent 40%)
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment(-0.906, -0.423),
                      end: Alignment(0.906, 0.423),
                      colors: [Color(0x1AFFFFFF), Color(0x00FFFFFF)],
                      stops: [0, 0.4],
                    ),
                  ),
                ),
                // ตราเชนทางการในหลุม (กล่อง 62x62 ที่ left 245 top 78)
                Positioned(
                  left: 245,
                  top: 78,
                  width: 62,
                  height: 62,
                  child: Center(
                    child: OverflowBox(
                      maxHeight: 70,
                      child: ChainEmblem(art: art),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _pill(st),
                      _balance(st),
                      _footer(st),
                    ],
                  ),
                ),
                if (shine != null) _shineBand(shine!),
              ],
            ),
          ),
        ),
        const Positioned.fill(
          child: IgnorePointer(child: CustomPaint(painter: ObsidianSurfacePainter(_cardRim))),
        ),
      ],
    );
  }

  Widget _pill(ObsidianStyle st) {
    final pill = Container(
      padding: const EdgeInsets.fromLTRB(4, 4, 9, 4),
      decoration: BoxDecoration(
        color: const Color(0x61000000), // rgba(0,0,0,.38)
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0x24FFFFFF)), // inset ring .14
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ObsidianChainLogo(art: data.art, size: 22),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              data.chainName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: st.ui.copyWith(fontSize: 12.5, fontWeight: FontWeight.w600, color: ObsidianColors.text, height: 1.2),
            ),
          ),
          const SizedBox(width: 5),
          const Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: ObsidianColors.chrome),
        ],
      ),
    );
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 210),
      child: onChainPillTap == null || !interactive
          ? pill
          : ObsidianPressable(onTap: onChainPillTap, semanticLabel: chainPillSemantics, child: pill),
    );
  }

  Widget _balance(ObsidianStyle st) {
    return SizedBox(
      width: 220,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            data.balanceLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: st.ui.copyWith(fontSize: 12, color: ObsidianColors.chrome, height: 1.3),
          ),
          const SizedBox(height: 4),
          // ยอดเยอะแค่ไหนก็ "ย่อ" ไม่ "ล้น" — ตัวเลขล้นบัตร = ดูเชื่อถือไม่ได้ทันที
          SizedBox(
            height: 40,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(
                    text: data.amount,
                    style: st.number.copyWith(
                      fontSize: 38,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -1.2,
                      height: 1,
                      color: ObsidianColors.text,
                      shadows: const [Shadow(color: Color(0xB3000000), offset: Offset(0, 4), blurRadius: 14.7)],
                    ),
                  ),
                  TextSpan(
                    text: ' ${data.unit}',
                    style: st.number.copyWith(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      height: 1,
                      color: ObsidianColors.chrome,
                    ),
                  ),
                ]),
                maxLines: 1,
              ),
            ),
          ),
          if (data.subline != null) ...[
            const SizedBox(height: 4),
            Text(
              data.subline!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: st.ui.copyWith(fontSize: 12.5, color: data.sublineColor ?? ObsidianColors.chrome, height: 1.3),
            ),
          ],
        ],
      ),
    );
  }

  Widget _footer(ObsidianStyle st) {
    final address = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          data.address,
          style: st.mono.copyWith(fontSize: 12.5, fontWeight: FontWeight.w500, color: ObsidianColors.textSoft),
        ),
        const SizedBox(width: 6),
        const Icon(Icons.copy_rounded, size: 14, color: ObsidianColors.chrome),
      ],
    );
    return Row(
      children: [
        onAddressTap == null || !interactive
            ? address
            : ObsidianPressable(onTap: onAddressTap, semanticLabel: addressSemantics, child: address),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            data.gasText,
            textAlign: TextAlign.right,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: st.ui.copyWith(fontSize: 11.5, color: ObsidianColors.chrome),
          ),
        ),
      ],
    );
  }

  /// แถบแสงกว้าง 38% เอียง -18° กวาดจาก -140% → 260% ของความกว้างตัวเอง
  Widget _shineBand(double t) {
    const delay = 0.25 / 1.35;
    final p = t <= delay ? 0.0 : Curves.easeOut.transform(((t - delay) / (1 - delay)).clamp(0.0, 1.0));
    const bandW = ChainCardDeck.designWidth * 0.38;
    final x = bandW * (-1.4 + 4.0 * p);
    return Positioned(
      left: 0,
      top: -ChainCardDeck.cardHeight * 0.2,
      bottom: -ChainCardDeck.cardHeight * 0.2,
      width: bandW,
      child: IgnorePointer(
        child: Transform(
          alignment: Alignment.center,
          transform: Matrix4.translationValues(x, 0, 0)..multiply(Matrix4.skewX(-18 * math.pi / 180)),
          child: const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0x00FFFFFF), Color(0x47FFFFFF), Color(0x00FFFFFF)], // .28
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// โลโก้สีวงกลมของเชน (ทางการ) — TPIX ใช้โลโก้เหรียญ TPIX
class ObsidianChainLogo extends StatelessWidget {
  final ObsidianChainArt art;
  final double size;

  const ObsidianChainLogo({super.key, required this.art, required this.size});

  @override
  Widget build(BuildContext context) {
    final chip = art.chip;
    if (chip == null) return TpixCoinLogo(size: size);
    return ClipOval(
      child: Image.asset(
        chip,
        width: size,
        height: size,
        fit: BoxFit.cover,
        cacheWidth: 96,
        excludeFromSemantics: true,
        errorBuilder: (_, _, _) => SizedBox(width: size, height: size),
      ),
    );
  }
}
