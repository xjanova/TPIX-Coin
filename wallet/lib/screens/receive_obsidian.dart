/// TPIX Wallet — หน้ารับเงินธีม Obsidian (ตาม A-Receive.dc.html)
///
/// ธีมอื่นยังใช้ ReceiveScreen เดิมทุกอย่าง — ReceiveScreen.build สลับมาที่นี่เฉพาะ Obsidian
///
/// สิ่งที่คงไว้จากหน้าเดิม:
///   - QR ของ "ที่อยู่ล้วน" (สแกนได้ทุกกระเป๋า) ระดับกู้คืน H · พื้นขาวเสมอ
///   - ยังไม่มีกระเป๋า = บอกให้สร้างกระเป๋า ไม่วาด QR ของสตริงว่าง
///   - คำเตือนว่ารับได้เฉพาะเชนไหน (Chain ID) — เปลี่ยนตามชิปที่เลือก
///   - ปุ่มคัดลอกที่อยู่
///
/// เพิ่มตาม mock: ชิปเลือกเชน (เปลี่ยนสี/โลโก้/คำเตือน — ที่อยู่เหมือนกันทุกเชน EVM)
/// และแอนิเมชันเงินเข้าเมื่อยอดที่ระบบรีเฟรชอยู่แล้ว (ทุก 15 วิ) เพิ่มขึ้นระหว่างเปิดหน้านี้
///
/// Developed by Xman Studio
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/locale_provider.dart';
import '../models/chain_config.dart';
import '../models/token_info.dart';
import '../providers/wallet_provider.dart';
import '../services/synth_service.dart';
import '../utils/balance_watch.dart';
import '../utils/units.dart';
import '../widgets/obsidian/obsidian.dart';
import '../widgets/obsidian/obsidian_glyph.dart';
import '../widgets/obsidian/obsidian_scrim.dart';
import '../widgets/obsidian/obsidian_top_bar.dart';
import '../widgets/obsidian/receive_art.dart';
import '../widgets/tpix_coin_logo.dart';

class ObsidianReceiveView extends StatefulWidget {
  const ObsidianReceiveView({super.key});

  /// ป้ายใต้โลโก้ของชิป (ตาม mock)
  static const chipLabels = {4289: 'TPIX', 56: 'BNB', 137: 'Polygon', 1: 'Ethereum'};

  @override
  State<ObsidianReceiveView> createState() => _ObsidianReceiveViewState();
}

/// ที่มาของยอดหนึ่งตัวในชุดที่เฝ้าดู (ไว้แปลงคีย์กลับเป็นสัญลักษณ์/ทศนิยม/โลโก้)
class _Source {
  final String symbol;
  final int decimals;
  final Widget Function(double size) logo;

  const _Source(this.symbol, this.decimals, this.logo);
}

class _ObsidianReceiveViewState extends State<ObsidianReceiveView> {
  late final WalletProvider _wallet;
  final _detector = BalanceIncreaseDetector();

  int _chainIndex = 0;

  /// เงินเข้าที่กำลังโชว์อยู่ (null = ไม่มี)
  IncomingInfo? _incoming;

  /// เพิ่มทุกครั้งที่มีเงินเข้า → การ์ด QR เล่นเหรียญพุ่ง / แถบเงินเข้าเริ่มใหม่
  int _burstTick = 0;

  @override
  void initState() {
    super.initState();
    _wallet = context.read<WalletProvider>();
    final found = ChainConfig.all.indexWhere((c) => c.chainId == _wallet.activeChainId);
    _chainIndex = found < 0 ? 0 : found;
    // จุดเริ่มของการเทียบยอด — ยอดตอนเปิดหน้าไม่ใช่ "เงินเข้า"
    _detector.update(_wallet.address, _snapshot(_wallet).$1);
    _wallet.addListener(_onWalletChanged);
  }

  @override
  void dispose() {
    _wallet.removeListener(_onWalletChanged);
    super.dispose();
  }

  /// ยอดทุกตัวที่ระบบรีเฟรชอยู่แล้ว + ที่มาของแต่ละคีย์
  (Map<String, BigInt?>, Map<String, _Source>) _snapshot(WalletProvider w) {
    final values = <String, BigInt?>{};
    final sources = <String, _Source>{};
    for (final c in ChainConfig.all) {
      final key = 'native:${c.chainId}';
      values[key] = c.chainId == 4289 ? w.balanceWei : w.chainBalances[c.chainId];
      final art = ObsidianChainArt.of(c.chainId);
      sources[key] = _Source(c.symbol, c.decimals, (s) => receiveCoinLogo(art, s));
    }
    for (final t in w.activeTokens) {
      final key = 'token:${t.chainId}:${t.contractAddress.toLowerCase()}';
      values[key] = w.getTokenBalanceRaw(t.contractAddress);
      sources[key] = _Source(t.symbol, t.decimals, (s) => _tokenLogo(w, t, s));
    }
    return (values, sources);
  }

  Widget _tokenLogo(WalletProvider w, TokenInfo t, double size) {
    final local = ObsidianLogos.forSymbol(t.symbol);
    if (local != null) {
      return ClipOval(
        child: Image.asset(
          local,
          width: size,
          height: size,
          cacheWidth: 96,
          excludeFromSemantics: true,
          errorBuilder: (_, _, _) => SizedBox.square(dimension: size),
        ),
      );
    }
    return TokenAvatar(symbol: t.symbol, logoUrl: w.tokenLogo(t), size: size, color: ObsidianColors.violet);
  }

  /// WalletProvider แจ้งเปลี่ยน (รีเฟรชยอดตามรอบเดิม) → เทียบหาเงินเข้า
  void _onWalletChanged() {
    if (!mounted) return;
    final (values, sources) = _snapshot(_wallet);
    final ups = _detector.update(_wallet.address, values);
    if (ups.isEmpty) return;

    // หลายตัวเข้าพร้อมกัน (หายาก) → โชว์ตัวแรก ที่เหลือยังอยู่ในยอดบนหน้าแรกตามปกติ
    final up = ups.first;
    final src = sources[up.key];
    if (src == null) return;
    final text = Units.format(up.delta, src.decimals);
    final dot = text.indexOf('.');
    final info = IncomingInfo(
      amountText: groupDigits(text),
      amount: Units.toDouble(up.delta, src.decimals),
      fractionDigits: dot < 0 ? 0 : math.min(6, text.length - dot - 1),
      symbol: src.symbol,
      logo: src.logo(40),
    );

    void show() {
      if (!mounted) return;
      setState(() {
        _incoming = info;
        _burstTick++;
      });
      SynthService.playReceive();
      HapticFeedback.mediumImpact();
    }

    // แจ้งเตือนอาจมาระหว่าง build ของหน้าอื่น → เลื่อนไปหลังเฟรม
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) => show());
    } else {
      show();
    }
  }

  void _copy(String address, LocaleProvider l) {
    Clipboard.setData(ClipboardData(text: address));
    SynthService.playTap();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(l.t('receive.copied')),
        duration: const Duration(seconds: 1),
      ));
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<LocaleProvider>();
    final wallet = context.watch<WalletProvider>();
    final address = wallet.address ?? '';
    final topInset = MediaQuery.paddingOf(context).top;
    final chains = ChainConfig.all;
    final chain = chains[_chainIndex.clamp(0, chains.length - 1)];
    final art = ObsidianChainArt.of(chain.chainId);
    final palette = ReceivePalette.of(chain.chainId);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          const ObsidianScrim.receive(),
          SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(24, math.max(52.0, topInset + 8), 24, 24 + MediaQuery.paddingOf(context).bottom),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ObsidianTopBar(
                  leading: ObsidianTopButton(
                    // mock หน้านี้ไม่มี backdrop-filter (เบลอแล้วปุ่มติดสีม่วงของคลิปพื้นหลัง)
                    blur: 0,
                    onTap: () => Navigator.maybePop(context),
                    semanticLabel: l.t('obs.sr.back'),
                    child: const ObsidianGlyphIcon(ObsidianGlyph.back, strokeWidth: 2.2),
                  ),
                  title: l.t('obs.rcv.title'),
                ),
                const SizedBox(height: 16),
                if (address.isEmpty)
                  _noWallet(l)
                else ...[
                  ChainChipsTall(
                    chains: [for (final c in chains) ObsidianChainArt.of(c.chainId)],
                    labels: [for (final c in chains) ObsidianReceiveView.chipLabels[c.chainId] ?? c.shortName],
                    activeIndex: _chainIndex,
                    locked: _incoming != null,
                    semanticLabel: l.t('obs.pickChain'),
                    onSelect: (i) {
                      SynthService.playTap();
                      setState(() => _chainIndex = i);
                    },
                  ),
                  const SizedBox(height: 22),
                  _qr(address, chain, art, palette, l),
                  const SizedBox(height: 16),
                  _status(address, chain, l),
                  const SizedBox(height: 16),
                  _copyButton(address, l),
                  const SizedBox(height: 16),
                  _warning(chain, l),
                ],
              ],
            ),
          ),
          if (_incoming != null)
            Positioned(
              left: 16,
              right: 16,
              top: math.max(44.0, topInset + 4),
              child: IncomingToast(
                key: ValueKey(_burstTick),
                info: _incoming!,
                title: l.t('obs.rcv.received'),
                accent: palette.c1,
                onDone: () {
                  if (mounted) setState(() => _incoming = null);
                },
              ),
            ),
        ],
      ),
    );
  }

  /// การ์ด QR + เรืองแสงสีเชนด้านหลัง (เปลี่ยนสีนุ่ม ๆ .6 วิ ตอนสลับชิป)
  Widget _qr(String address, ChainConfig chain, ObsidianChainArt art, ReceivePalette palette, LocaleProvider l) {
    return Center(
      child: SizedBox.square(
        dimension: ReceiveQrCard.size,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            // mock: กลางเรืองแสงอยู่สูงกว่ากลางการ์ด ~35px
            Positioned(
              left: -119,
              top: -154,
              width: 520,
              height: 520,
              child: IgnorePointer(
                child: TweenAnimationBuilder<Color?>(
                  tween: ColorTween(end: palette.glow),
                  duration: const Duration(milliseconds: 600),
                  curve: Curves.ease,
                  builder: (context, c, _) => DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(colors: [c ?? palette.glow, (c ?? palette.glow).withValues(alpha: 0)]),
                    ),
                  ),
                ),
              ),
            ),
            ReceiveQrCard(
              data: address,
              palette: palette,
              logo: receiveCoinLogo(art, 46),
              coin: _incoming?.logo ?? receiveCoinLogo(art, 34),
              burstTick: _burstTick,
              semanticLabel: l.t('obs.rcv.qrLabel').replaceAll('{name}', chain.name),
            ),
          ],
        ),
      ),
    );
  }

  /// ป้าย "รอรับเงิน" + ที่อยู่เต็ม (เลือกคัดลอกได้)
  Widget _status(String address, ChainConfig chain, LocaleProvider l) {
    final st = ObsidianStyle.of(context);
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0x1F34D399), // .12
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: const Color(0x5934D399)), // .35
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const PulseDot(),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  l.t('obs.rcv.waiting').replaceAll('{name}', chain.name),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: st.ui(fontSize: 12.5, color: ObsidianColors.successPale),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: SelectableText(
            address,
            textAlign: TextAlign.center,
            style: st.mono(fontSize: 14, height: 1.5, color: const Color(0xFFE9EAEE)),
          ),
        ),
      ],
    );
  }

  Widget _copyButton(String address, LocaleProvider l) {
    final st = ObsidianStyle.of(context);
    return ObsidianPanel(
      height: 48,
      onTap: () => _copy(address, l),
      semanticLabel: l.t('receive.copy'),
      surface: const ObsidianSurface(
        radius: 16,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFF7F8FA), Color(0xFFD9DCE3)],
        ),
        bottomShade: Color(0x2E000000),
        bottomShadeWidth: 2,
        shadows: [CssShadow(0, 12, 24, -12, Color(0xE6000000))],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const ObsidianGlyphIcon(ObsidianGlyph.copy, size: 16, color: Color(0xFF0A0B0F)),
          const SizedBox(width: 6),
          Text(
            l.t('receive.copy'),
            style: st.ui(fontSize: 14, fontWeight: FontWeight.w600, color: const Color(0xFF0A0B0F)),
          ),
        ],
      ),
    );
  }

  /// คำเตือนว่ารับได้เฉพาะเชนที่เลือก — ส่งข้ามเชนผิดตัว = เงินหาย
  Widget _warning(ChainConfig chain, LocaleProvider l) {
    final st = ObsidianStyle.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0x14FBBF24), // .08
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x47FBBF24)), // .28
      ),
      child: Row(
        children: [
          const Icon3D(ObsidianIcons.shield, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              l.t('obs.rcv.warning').replaceAll('{name}', chain.name).replaceAll('{id}', '${chain.chainId}'),
              style: st.ui(fontSize: 12.5, height: 1.4, color: const Color(0xFFFDE68A)),
            ),
          ),
        ],
      ),
    );
  }

  /// ยังไม่มีกระเป๋า/ยังล็อก — ไม่วาด QR ของสตริงว่าง
  Widget _noWallet(LocaleProvider l) {
    final st = ObsidianStyle.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 80),
      child: Column(
        children: [
          const Icon3D(ObsidianIcons.wallet, size: 72, dimmed: true),
          const SizedBox(height: 16),
          Text(
            l.t('receive.noWallet'),
            textAlign: TextAlign.center,
            style: st.ui(fontSize: 16, fontWeight: FontWeight.w600, color: ObsidianColors.text),
          ),
          const SizedBox(height: 8),
          Text(
            l.t('receive.noWalletHint'),
            textAlign: TextAlign.center,
            style: st.ui(fontSize: 13, height: 1.5, color: ObsidianColors.textSec),
          ),
        ],
      ),
    );
  }
}
