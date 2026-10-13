/// TPIX Wallet — ชิ้นส่วนหน้าสะพานของธีม Obsidian (ใช้ร่วมกันทั้งสะพาน USDT และ wTPIX)
///
/// หน้าตาอย่างเดียว — กฎเงิน/ตรวจบนเชน/ยืนยัน/PIN อยู่ที่ bridge_rules · bridge_service · BridgeSendFlow เหมือนเดิม
///
/// Developed by Xman Studio
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../core/locale_provider.dart';
import '../core/themes/theme_bundle.dart';
import '../services/bridge_rules.dart';
import 'bridge_progress.dart';
import 'bridge_widgets.dart';
import 'obsidian/obsidian.dart';
import 'tpix_coin_logo.dart';

// ════════════════════════════════════════════════════════════════
//  โลโก้ / สีของเชน
// ════════════════════════════════════════════════════════════════

/// โลโก้เชนทางการ (ฝังในแอป) — เชนที่ไม่มีภาพทางการในแอป (Arbitrum / OP / Avalanche) = อักษรย่อ
/// ★ ห้ามวาดโลโก้เลียนแบบ
Widget bridgeChainLogo(int chainId, String name, double size) {
  final art = ObsidianChainArt.all.where((a) => a.chainId == chainId).firstOrNull;
  if (art != null) return ObsidianChainLogo(art: art, size: size);
  return TokenAvatar(symbol: name, size: size, color: ObsidianColors.violet);
}

/// ชื่อสั้นของเชนบนการ์ดเส้นทาง (ช่องแคบ 86px) — กล่องยืนยัน/รายละเอียดยังใช้ชื่อเต็มจากเซิร์ฟเวอร์
String bridgeChainShortName(int chainId, String name) => switch (chainId) {
  56 => 'BNB Chain',
  1 => 'Ethereum',
  137 => 'Polygon',
  42161 => 'Arbitrum',
  10 => 'OP Mainnet',
  43114 => 'Avalanche',
  4289 => 'TPIX Chain',
  _ => name,
};

/// สีวงขอบของโหนดเชน
Color bridgeChainRing(int chainId) =>
    ObsidianChainArt.all.where((a) => a.chainId == chainId).firstOrNull?.accent ?? ObsidianColors.violet;

/// โลโก้ USDT ทางการ (วงกลม)
Widget bridgeUsdtLogo(double size) => ClipOval(
  child: Image.asset(
    ObsidianLogos.usdt,
    width: size,
    height: size,
    fit: BoxFit.cover,
    cacheWidth: 128,
    excludeFromSemantics: true,
    errorBuilder: (_, _, _) => SizedBox(width: size, height: size),
  ),
);

Color bridgeObsTone(BridgeTone tone) => switch (tone) {
  BridgeTone.success => ObsidianColors.success,
  BridgeTone.info => ObsidianColors.cyan,
  BridgeTone.warning => ObsidianColors.orange,
  BridgeTone.danger => ObsidianColors.danger,
  BridgeTone.muted => ObsidianColors.textMuted,
};

// ════════════════════════════════════════════════════════════════
//  สะพานยังไม่เปิด / หยุด / ปิดเพื่อความปลอดภัย
// ════════════════════════════════════════════════════════════════

enum BridgeClosedKind { preparing, paused, locked }

/// การ์ดพระเอกตอนสะพานปิด — ตั้งใจให้ดูเป็นสถานะปกติที่ "กำลังมา" ไม่ใช่หน้าพัง
/// (บอกตรง ๆ ว่ายังไม่ต้องโอนอะไร และไม่มีปุ่มส่งเงินเลย)
class BridgeObsClosedHero extends StatefulWidget {
  final BridgeClosedKind kind;
  final String title;
  final String body;

  const BridgeObsClosedHero({super.key, required this.kind, required this.title, required this.body});

  @override
  State<BridgeObsClosedHero> createState() => _BridgeObsClosedHeroState();
}

class _BridgeObsClosedHeroState extends State<BridgeObsClosedHero> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduce) {
      _pulse.stop();
    } else if (!_pulse.isAnimating) {
      _pulse.repeat();
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<LocaleProvider>();
    final st = ObsidianStyle.of(context);
    final (pill, tone) = switch (widget.kind) {
      BridgeClosedKind.preparing => (l.t('obs.bridge.closedPill'), ObsidianColors.warning),
      BridgeClosedKind.paused => (l.t('obs.bridge.pausedPill'), ObsidianColors.orange),
      BridgeClosedKind.locked => (l.t('obs.bridge.lockedPill'), ObsidianColors.dangerSoft),
    };
    return ObsidianPanel(
      surface: ObsidianCards.hero,
      blur: 16,
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
      child: Column(
        children: [
          // ไอคอนสะพาน 3D + แสงม่วงหายใจ
          AnimatedBuilder(
            animation: _pulse,
            builder: (context, child) {
              final t = (1 - math.cos(_pulse.value * 2 * math.pi)) / 2;
              return DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    CssShadow.lerp(
                      const CssShadow(0, 0, 40, -6, Color(0x408B5CF6)),
                      const CssShadow(0, 0, 56, 0, Color(0x738B5CF6)),
                      t,
                    ).toBoxShadow(),
                  ],
                ),
                child: child,
              );
            },
            child: const Icon3D(ObsidianIcons.bridge, size: 84, shadows: [IconDropShadow.tile]),
          ),
          const SizedBox(height: 14),
          // ป้ายสถานะ + จุดกะพริบ
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: tone.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: tone.withValues(alpha: 0.35)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                FadeTransition(
                  opacity: Tween(begin: 0.35, end: 1.0).animate(_pulse),
                  child: Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: tone,
                      boxShadow: [BoxShadow(color: tone, blurRadius: 6)],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  pill,
                  style: st.ui(fontSize: 12, fontWeight: FontWeight.w600, color: tone),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            widget.title,
            textAlign: TextAlign.center,
            style: st.ui(fontSize: 17, fontWeight: FontWeight.w600, color: ObsidianColors.text, height: 1.4),
          ),
          const SizedBox(height: 6),
          Text(
            widget.body,
            textAlign: TextAlign.center,
            style: st.ui(fontSize: 13, color: ObsidianColors.textSec, height: 1.55),
          ),
          const SizedBox(height: 14),
          Container(height: 1, color: const Color(0x0FFFFFFF)),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon3D(ObsidianIcons.shield, size: 20),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  l.t('obs.bridge.closedSafe'),
                  textAlign: TextAlign.center,
                  style: st.ui(fontSize: 12, color: ObsidianColors.textMuted, height: 1.45),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
//  การ์ดจำนวน
// ════════════════════════════════════════════════════════════════

/// ช่องกรอกจำนวนตัวใหญ่ (Space Grotesk 34) — กฎตัวกรองเดียวกับช่องเดิม (bridgeAmountFormatters)
class BridgeObsAmountInput extends StatelessWidget {
  final TextEditingController controller;
  final bool enabled;
  final ValueChanged<String> onChanged;
  final String hint;

  const BridgeObsAmountInput({
    super.key,
    required this.controller,
    required this.enabled,
    required this.onChanged,
    this.hint = '0',
  });

  @override
  Widget build(BuildContext context) {
    final st = ObsidianStyle.of(context);
    final big = st.number(
      fontSize: 34,
      fontWeight: FontWeight.w700,
      letterSpacing: -1,
      height: 1.15,
      color: ObsidianColors.text,
    );
    return TextField(
      controller: controller,
      enabled: enabled,
      onChanged: onChanged,
      autocorrect: false,
      enableSuggestions: false,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: bridgeAmountFormatters,
      cursorColor: ObsidianColors.cyan,
      style: big,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: big.copyWith(color: const Color(0x40FFFFFF)),
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        disabledBorder: InputBorder.none,
        isDense: true,
        contentPadding: EdgeInsets.zero,
      ),
    );
  }
}

/// การ์ดจำนวน (mock: "ฝากจำนวน" · โลโก้ 34 · ตัวเลข 34 · ปุ่มสูงสุด · เส้นคั่น · แถวสรุป)
class BridgeObsAmountCard extends StatelessWidget {
  final String label;
  final String? balanceText;
  final Widget logo;

  /// ช่องกรอก — ผู้เรียกห่อ key ของเทสต์ไว้ที่นี่
  final Widget input;
  final String maxLabel;
  final VoidCallback? onMax;
  final String? errorText;
  final String? warningText;

  /// ส่วนเสริมใต้ช่องกรอก (เช่น ที่อยู่ปลายทางของการถอน)
  final List<Widget> extra;
  final List<Widget> rows;

  const BridgeObsAmountCard({
    super.key,
    required this.label,
    required this.balanceText,
    required this.logo,
    required this.input,
    required this.maxLabel,
    required this.onMax,
    this.errorText,
    this.warningText,
    this.extra = const [],
    this.rows = const [],
  });

  @override
  Widget build(BuildContext context) {
    final st = ObsidianStyle.of(context);
    final small = st.ui(fontSize: 12.5, color: ObsidianColors.textSec, height: 1.4);
    return ObsidianPanel(
      surface: ObsidianCards.form,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(label, style: small),
              const SizedBox(width: 10),
              if (balanceText != null)
                Expanded(
                  child: Text(
                    balanceText!,
                    textAlign: TextAlign.end,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: small,
                  ),
                )
              else
                const Spacer(),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 44,
            child: Row(
              children: [
                SizedBox(width: 34, height: 34, child: logo),
                const SizedBox(width: 10),
                Expanded(child: input),
                const SizedBox(width: 8),
                ObsidianChipButton(label: maxLabel, onTap: onMax, height: 30, padding: 12),
              ],
            ),
          ),
          if (errorText != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(errorText!, style: st.ui(fontSize: 12, color: ObsidianColors.dangerSoft, height: 1.4)),
            )
          else if (warningText != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(warningText!, style: st.ui(fontSize: 12, color: ObsidianColors.warning, height: 1.4)),
            ),
          ...extra,
          if (rows.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(height: 1, color: const Color(0x0FFFFFFF)),
            const SizedBox(height: 2),
            ...rows,
          ],
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
//  ที่อยู่ / ลิงก์ / วิธีใช้ / ป้ายสถานะ
// ════════════════════════════════════════════════════════════════

/// ที่อยู่เต็มทุกตัวอักษร + ปุ่มคัดลอก (ผู้ใช้ต้องตรวจได้ครบ ห้ามตัดเป็น …)
class BridgeObsAddress extends StatelessWidget {
  final String label;
  final String address;

  const BridgeObsAddress({super.key, required this.label, required this.address});

  @override
  Widget build(BuildContext context) {
    final l = context.watch<LocaleProvider>();
    final st = ObsidianStyle.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: st.ui(fontSize: 12, color: ObsidianColors.textMuted, height: 1.4)),
        const SizedBox(height: 2),
        Row(
          children: [
            Expanded(
              child: SelectableText(address, style: st.mono(fontSize: 12, color: ObsidianColors.text, height: 1.45)),
            ),
            IconButton(
              tooltip: l.t('bridge.copy'),
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.copy_rounded, size: 16, color: ObsidianColors.textMuted),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: address));
                if (context.mounted) bridgeSnack(context, l.t('bridge.copied'));
              },
            ),
          ],
        ),
      ],
    );
  }
}

/// ลิงก์เปิดเบราว์เซอร์ (https เท่านั้น — กรองที่ openBridgeUrl)
class BridgeObsLink extends StatelessWidget {
  final String label;
  final String? url;

  const BridgeObsLink({super.key, required this.label, required this.url});

  @override
  Widget build(BuildContext context) {
    if (url == null) return const SizedBox.shrink();
    final st = ObsidianStyle.of(context);
    return ObsidianPressable(
      onTap: () => openBridgeUrl(context, url),
      semanticLabel: label,
      pressedScale: 0.97,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                label,
                style: st.ui(fontSize: 12, fontWeight: FontWeight.w500, color: ObsidianColors.cyan),
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.open_in_new_rounded, size: 13, color: ObsidianColors.cyan),
          ],
        ),
      ),
    );
  }
}

/// ขั้นตอนการทำงาน (เลขลำดับ + ข้อความ)
class BridgeObsHow extends StatelessWidget {
  final String title;
  final List<String> steps;

  const BridgeObsHow({super.key, required this.title, required this.steps});

  @override
  Widget build(BuildContext context) {
    final st = ObsidianStyle.of(context);
    return ObsidianPanel(
      surface: ObsidianCards.details,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon3D(ObsidianIcons.info, size: 22),
              const SizedBox(width: 8),
              Text(
                title,
                style: st.ui(fontSize: 14, fontWeight: FontWeight.w600, color: ObsidianColors.text),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < steps.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 20,
                    height: 20,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: ObsidianColors.violet.withValues(alpha: 0.18),
                      border: Border.all(color: ObsidianColors.violet.withValues(alpha: 0.45)),
                    ),
                    child: Text(
                      '${i + 1}',
                      style: st.number(fontSize: 10.5, fontWeight: FontWeight.w600, color: const Color(0xFFC4B5FD)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(steps[i], style: st.ui(fontSize: 12.5, height: 1.5, color: ObsidianColors.textSec)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// ป้ายสถานะเม็ดยา
class BridgeObsStateChip extends StatelessWidget {
  final String label;
  final BridgeTone tone;

  const BridgeObsStateChip({super.key, required this.label, required this.tone});

  @override
  Widget build(BuildContext context) {
    final st = ObsidianStyle.of(context);
    final color = bridgeObsTone(tone);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: st.ui(fontSize: 11, fontWeight: FontWeight.w600, color: color, height: 1.3),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
//  เลือกเชน (แผ่นเลื่อนขึ้น)
// ════════════════════════════════════════════════════════════════

typedef BridgeObsChainOption = ({int id, String title, String subtitle, bool enabled});

/// คืน chainId ที่เลือก · null = ปิดไปเฉย ๆ / เลือกตัวเดิม
Future<int?> showBridgeObsChainPicker(
  BuildContext context, {
  required String title,
  required List<BridgeObsChainOption> chains,
  required int? selected,
}) {
  return showObsidianSheet<int>(
    context,
    title: title,
    builder: (ctx) {
      final st = ObsidianStyle.of(ctx);
      return ObsidianPanel(
        surface: ObsidianCards.details,
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          children: [
            for (final c in chains)
              Opacity(
                opacity: c.enabled ? 1 : 0.45,
                child: ObsidianPressable(
                  onTap: !c.enabled ? null : () => Navigator.pop(ctx, c.id == selected ? null : c.id),
                  semanticLabel: c.title,
                  pressedScale: 0.985,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    child: Row(
                      children: [
                        bridgeChainLogo(c.id, c.title, 36),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                c.title,
                                style: st.ui(fontSize: 14.5, fontWeight: FontWeight.w600, color: ObsidianColors.text),
                              ),
                              Text(c.subtitle, style: st.ui(fontSize: 12, color: ObsidianColors.textMuted)),
                            ],
                          ),
                        ),
                        if (c.id == selected)
                          const Icon(Icons.check_circle_rounded, size: 20, color: ObsidianColors.success),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );
}

// ════════════════════════════════════════════════════════════════
//  การ์ดติดตามรายการ (ขั้นตอน 3 ขั้น)
// ════════════════════════════════════════════════════════════════

/// ข้อความของ 3 ขั้น (ต่างกันตามชนิดรายการ) — สถานะมาจาก [bridgeProgressOf]
@immutable
class BridgeObsStepText {
  final String send;
  final String confirm;
  final String deliver;

  const BridgeObsStepText({required this.send, required this.confirm, required this.deliver});
}

/// ประกอบขั้นตอนบนจอจากสถานะจริง
///
/// [badgeLabel] ป้ายสถานะจากเซิร์ฟเวอร์ (ไว้อธิบายขั้นที่ติด/กำลังทำ) · [delivered] ยอดที่ส่งมอบแล้ว
List<ObsidianStep> bridgeObsSteps(
  LocaleProvider l, {
  required BridgeStatusView? status,
  required BridgeObsStepText text,
  required String? badgeLabel,
  String? delivered,
}) {
  final p = bridgeProgressOf(status);
  final focus = p.focus;
  String? sub(int i) {
    final s = p.steps[i];
    if (s == ObsidianStepState.idle) return l.t('obs.bridge.step.waitPrev');
    if (s == ObsidianStepState.done) {
      return switch (i) {
        0 => l.t('obs.bridge.step.inChain'),
        1 => l.t('obs.bridge.step.confirmed'),
        _ => delivered == null ? l.t('obs.bridge.step.delivered') : '${l.t('obs.bridge.step.delivered')} · $delivered',
      };
    }
    // ขั้นที่กำลังทำ/ติด
    if (status == null) return l.t('obs.bridge.step.checking');
    if (i == 1 && s == ObsidianStepState.active) {
      if (status.isFinal) return l.t('bridge.finalSoon');
      final n = status.confirmations;
      return n == null ? badgeLabel : bridgeT(l, 'bridge.confirmations', {'n': '$n'});
    }
    return i == focus ? badgeLabel : null;
  }

  final titles = [text.send, text.confirm, text.deliver];
  return [
    for (var i = 0; i < 3; i++)
      ObsidianStep(
        title: titles[i],
        sub: sub(i),
        state: p.steps[i],
        showBar: i == 1 && p.showConfirmBar,
        progress: i == 1 ? p.confirmProgress : null,
      ),
  ];
}

/// หนึ่งรายการที่กำลังติดตาม — [latest] = การ์ดเน้นสีม่วงแบบ mock "รายการล่าสุด"
class BridgeObsTrackedCard extends StatelessWidget {
  final String title;
  final String txHash;
  final String? explorerUrl;
  final List<ObsidianStep> steps;
  final bool latest;
  final VoidCallback onRemove;

  /// ลิงก์ธุรกรรมปลายทาง ฯลฯ
  final List<Widget> details;

  const BridgeObsTrackedCard({
    super.key,
    required this.title,
    required this.txHash,
    required this.explorerUrl,
    required this.steps,
    required this.onRemove,
    this.latest = false,
    this.details = const [],
  });

  @override
  Widget build(BuildContext context) {
    final l = context.watch<LocaleProvider>();
    final st = ObsidianStyle.of(context);
    return ObsidianPanel(
      surface: latest ? ObsidianCards.accent : ObsidianCards.details.copyWith(radius: 22),
      padding: const EdgeInsets.fromLTRB(16, 10, 6, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: st.ui(fontSize: 13, fontWeight: FontWeight.w600, color: ObsidianColors.text, height: 1.4),
                ),
              ),
              const SizedBox(width: 8),
              ObsidianPressable(
                onTap: explorerUrl == null ? null : () => openBridgeUrl(context, explorerUrl),
                semanticLabel: txHash,
                pressedScale: 0.97,
                child: Text(
                  bridgeShort(txHash, head: 6, tail: 4),
                  style: st.mono(
                    fontSize: 11.5,
                    color: explorerUrl == null ? ObsidianColors.textMuted : ObsidianColors.textSec,
                  ),
                ),
              ),
              IconButton(
                tooltip: l.t('bridge.remove'),
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close_rounded, size: 17, color: ObsidianColors.textMuted),
                onPressed: onRemove,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: ObsidianStepTracker(steps: steps),
          ),
          if (details.isNotEmpty) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(left: 38, right: 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: details),
            ),
          ],
        ],
      ),
    );
  }
}

/// แผงประวัติ (จากเซิร์ฟเวอร์)
class BridgeObsHistory extends StatelessWidget {
  final String title;
  final String emptyText;
  final List<({String text, String label, BridgeTone tone})> rows;

  const BridgeObsHistory({super.key, required this.title, required this.emptyText, required this.rows});

  @override
  Widget build(BuildContext context) {
    final st = ObsidianStyle.of(context);
    return ObsidianPanel(
      surface: ObsidianCards.details,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon3D(ObsidianIcons.activity, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: st.ui(fontSize: 14, fontWeight: FontWeight.w600, color: ObsidianColors.text),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(emptyText, style: st.ui(fontSize: 12.5, color: ObsidianColors.textMuted)),
            )
          else
            for (final r in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(r.text, style: st.ui(fontSize: 12.5, color: ObsidianColors.textSoft, height: 1.4)),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: BridgeObsStateChip(label: r.label, tone: r.tone),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

/// ชิปเลือกเชนแบบเล็ก (แท็บติดตาม)
class BridgeObsChainChoice extends StatelessWidget {
  final List<BridgeObsChainOption> chains;
  final int? selected;
  final ValueChanged<int>? onSelect;

  const BridgeObsChainChoice({super.key, required this.chains, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final st = ObsidianStyle.of(context);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final c in chains)
          Opacity(
            opacity: c.enabled ? 1 : 0.45,
            child: ObsidianPressable(
              onTap: !c.enabled || onSelect == null || c.id == selected ? null : () => onSelect!(c.id),
              semanticLabel: c.title,
              child: CustomPaint(
                painter: ObsidianSurfacePainter(
                  c.id == selected
                      ? ObsidianCards.segment.copyWith(ring: bridgeChainRing(c.id), ringWidth: 1.5)
                      : ObsidianCards.chip.copyWith(radius: 14),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(6, 6, 12, 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      bridgeChainLogo(c.id, c.title, 22),
                      const SizedBox(width: 8),
                      Text(
                        c.title,
                        style: st.ui(
                          fontSize: 12.5,
                          fontWeight: c.id == selected ? FontWeight.w600 : FontWeight.w400,
                          color: c.id == selected ? ObsidianColors.text : ObsidianColors.textSec,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// ตัวเลข "วงเงิน" ของสะพาน (ค่าจากเซิร์ฟเวอร์เป็นข้อความ) — ไม่มี = "—"
String bridgeObsLimit(Object? v) {
  final text = v is String ? v.trim() : (v is num ? '$v' : '');
  if (text.isEmpty) return '—';
  // ตัวเลขล้วน → ใส่จุลภาคหลักพัน (แสดงผลอย่างเดียว · กล่องยืนยันยังโชว์ค่าดิบจากเซิร์ฟเวอร์)
  final n = num.tryParse(text);
  return n == null ? text : _limitFmt.format(n);
}

final _limitFmt = NumberFormat('#,##0.######', 'en_US');

/// TPIX coin logo (ใช้กับ TPIX / wTPIX)
Widget bridgeTpixLogo(double size) => TpixCoinLogo(size: size);

// ════════════════════════════════════════════════════════════════
//  กล่องยืนยันก่อนเซ็น / โหลดไม่สำเร็จ (เรียกจาก bridge_widgets เมื่อเป็นธีม Obsidian)
// ════════════════════════════════════════════════════════════════

bool bridgeIsObsidian(BuildContext context) =>
    Theme.of(context).extension<TpixThemeExtension>()?.themeId == ThemeId.obsidian;

/// เหมือน showBridgeConfirmSheet ทุกอย่าง (แถวเดิม · ที่อยู่เต็มทุกตัวอักษร · คืน true เมื่อกดยืนยันเท่านั้น)
Future<bool> showBridgeObsConfirmSheet(
  BuildContext context, {
  required String title,
  required List<(String, String)> rows,
  required List<String> notes,
  required String confirmLabel,
  required bool danger,
}) async {
  final l = context.read<LocaleProvider>();
  final ok = await showObsidianSheet<bool>(
    context,
    title: title,
    builder: (ctx) {
      final st = ObsidianStyle.of(ctx);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ObsidianPanel(
            surface: ObsidianCards.details,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            child: Column(
              children: [
                for (var i = 0; i < rows.length; i++) ...[
                  if (i > 0) Container(height: 1, color: const Color(0x0AFFFFFF)),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 4,
                          child: Text(
                            rows[i].$1,
                            style: st.ui(fontSize: 13, color: ObsidianColors.textSec, height: 1.4),
                          ),
                        ),
                        const SizedBox(width: 12),
                        // ที่อยู่ยาว — ตัดบรรทัดได้ ห้ามตัดเป็น … (ผู้ใช้ต้องตรวจได้ทุกตัวอักษร)
                        Expanded(
                          flex: 6,
                          child: SelectableText(
                            rows[i].$2,
                            textAlign: TextAlign.end,
                            style: st.mono(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w500,
                              color: ObsidianColors.text,
                              height: 1.45,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (notes.isNotEmpty) ...[
            const SizedBox(height: 12),
            ObsidianNotice(tone: danger ? ObsidianTone.danger : ObsidianTone.warning, lines: notes),
          ],
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: ObsidianButton.secondary(label: l.t('send.cancel'), onPressed: () => Navigator.pop(ctx, false)),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: ObsidianButton(
                  key: const ValueKey('bridge-confirm'),
                  label: confirmLabel,
                  height: 52,
                  onPressed: () => Navigator.pop(ctx, true),
                ),
              ),
            ],
          ),
        ],
      );
    },
  );
  return ok == true;
}

/// โหลดสถานะสะพานไม่สำเร็จ — ข้อความ + ปุ่มลองใหม่ (ไม่ใช่หน้าว่าง/Exception ดิบ)
class BridgeObsLoadFailed extends StatelessWidget {
  final VoidCallback onRetry;

  const BridgeObsLoadFailed({super.key, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final l = context.watch<LocaleProvider>();
    final st = ObsidianStyle.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
      children: [
        ObsidianPanel(
          surface: ObsidianCards.hero,
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
          child: Column(
            children: [
              const Icon3D(ObsidianIcons.network, size: 64, dimmed: true),
              const SizedBox(height: 14),
              Text(
                l.t('bridge.loadFailed'),
                textAlign: TextAlign.center,
                style: st.ui(fontSize: 15, fontWeight: FontWeight.w600, color: ObsidianColors.text, height: 1.45),
              ),
              const SizedBox(height: 18),
              ObsidianButton(label: l.t('bridge.retry'), onPressed: onRetry, height: 52),
            ],
          ),
        ),
      ],
    );
  }
}
