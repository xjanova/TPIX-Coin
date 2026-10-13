/// TPIX Wallet — ชิปเลือกเชนใต้สำรับบัตร (ธีม Obsidian)
///
/// 4 ช่องเท่ากัน สูง 44 มน 15 · ช่องที่เลือก = กระจกสว่างขึ้น + วงขอบ 1.5px สีเชน
/// + เงาเรืองสีเชน (เปลี่ยนนุ่ม ๆ .35s ตาม mock)
///
/// เป็น radio group สำหรับตัวอ่านหน้าจอ — กดช่องที่เลือกอยู่แล้วไม่ยิงซ้ำ
///
/// Developed by Xman Studio
library;

import 'package:flutter/material.dart';

import '../../core/themes/obsidian_tokens.dart';
import 'chain_card_deck.dart';
import 'obsidian_assets.dart';
import 'obsidian_panel.dart';

class ChainChips extends StatelessWidget {
  final List<ObsidianChainArt> chains;
  final int activeIndex;
  final ValueChanged<int> onSelect;

  /// ป้ายสำหรับตัวอ่านหน้าจอของทั้งกลุ่ม (เช่น "เลือกเชน")
  final String semanticLabel;

  const ChainChips({
    super.key,
    required this.chains,
    required this.activeIndex,
    required this.onSelect,
    this.semanticLabel = '',
  });

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
                child: _ChainChip(
                  art: chains[i],
                  active: i == activeIndex,
                  onTap: i == activeIndex ? null : () => onSelect(i),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ChainChip extends StatelessWidget {
  final ObsidianChainArt art;
  final bool active;
  final VoidCallback? onTap;

  const _ChainChip({required this.art, required this.active, required this.onTap});

  static ObsidianSurface _surface(ObsidianChainArt art, double t) {
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return ObsidianSurface(
      radius: 15,
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          mix(const Color(0x0FFFFFFF), const Color(0x24FFFFFF)), // .06 → .14
          mix(const Color(0x05FFFFFF), const Color(0x0AFFFFFF)), // .02 → .04
        ],
      ),
      topHighlight: mix(const Color(0x1AFFFFFF), const Color(0x38FFFFFF)), // .10 → .22
      ring: t <= 0 ? null : art.accent.withValues(alpha: t),
      ringWidth: 1.5,
      shadows: [
        CssShadow.lerp(
          const CssShadow(0, 8, 18, -10, Color(0xE6000000)),
          CssShadow(0, 10, 24, -8, art.accent),
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
      label: art.shortLabel,
      child: ObsidianPressable(
        onTap: onTap,
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: active ? 1 : 0),
          duration: const Duration(milliseconds: 350),
          curve: Curves.ease,
          builder: (context, t, _) => SizedBox(
            height: 44,
            child: CustomPaint(
              painter: ObsidianSurfacePainter(_surface(art, t)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ObsidianChainLogo(art: art, size: 20),
                      const SizedBox(width: 6),
                      ExcludeSemantics(
                        child: Text(
                          art.shortLabel,
                          style: st.ui.copyWith(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
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
    );
  }
}
