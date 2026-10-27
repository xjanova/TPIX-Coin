// TPIX Wallet — หน้ามาสเตอร์โหนดธีม Obsidian (ตาม A-Node.dc.html)
//
// เป็น part ของ masternode_screen.dart — ไฟล์นี้ "วาด" อย่างเดียว:
//   ทุกปุ่มเรียกตัวจัดการเดิม (_openWebsite / _claim / _unstake / _withdrawSlashed / _load)
//   ทุกเงื่อนไขปุ่มมาจาก MnSnapshot เดิม (registerBlock / claimBlock / unstakeBlock / aprCapToShow)
//   ตัวเลขทุกตัวมาจากเชน (getTierInfo / tierAprCapBps / availableRewardFunds) — ไม่มีเลขตายตัวจาก mock
//
// ด่านความปลอดภัยที่หน้าตาต้องไม่ทำหาย:
//   - สมัคร/สเตคโหนดใหม่ทำที่เว็บเท่านั้น — ปุ่มหลักพาไปเว็บ ไม่มีปุ่มสเตคในแอป (เจ้าของสั่ง 2026-10-27)
//   - สัญญายังไม่ประกาศ / ตรวจไม่ผ่าน / โค้ดไม่รู้จัก (ให้อัปเดตแอป) / ติดต่อไม่ได้ = ไม่มีปุ่มเขียน
//   - กองรางวัลว่าง = ไม่โชว์ APR (โชว์ "รอเติมพูล") + บอกตรง ๆ ว่ายังไม่มีรางวัลจ่ายจริง
//   - ปิดรับลงทะเบียน = แถบเตือน + ปุ่มกดไม่ได้พร้อมเหตุผล
//   - Validator ต้อง KYC ผ่านเว็บ — ปุ่มพาไปเว็บ ไม่ใช่ปุ่มสเตค
//   - ปุ่มกดไม่ได้ต้องบอกเหตุผลเสมอ (ข้อความใต้การ์ด + แตะปุ่มแล้วขึ้นเหตุผลเต็ม)
//   - รีเฟรชล้มแต่มีข้อมูลเดิม = แถบสถานะเหลือง "ข้อมูลล่าสุดที่โหลดได้" ไม่ใช่ "ทำงานปกติ"
//
// Developed by Xman Studio

part of 'masternode_screen.dart';

bool _isObsidian(BuildContext context) => TpixThemeExtension.of(context).themeId == ThemeId.obsidian;

/// สีค่าในแผ่นยืนยัน: สีของธีมเดิม → สีของ Obsidian
Color? _obsValueColor(Color? c) {
  if (c == null) return null;
  if (c == AppTheme.success) return ObsidianColors.successSoft;
  if (c == AppTheme.primary) return ObsidianColors.cyan;
  return c;
}

/// ปุ่มยืนยันรายการเสี่ยง (ถอนสเตค) — เข้มทึบ + วงขอบแดง + ตัวอักษรแดงอ่อน
class _ObsDangerButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;

  const _ObsDangerButton({required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final st = ObsidianStyle.of(context);
    return ObsidianPanel(
      surface: ObsidianSurface.dark.copyWith(radius: 17, ring: const Color(0x80F87171), ringWidth: 1.2),
      height: 52,
      onTap: onPressed,
      semanticLabel: label,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: st.ui(fontSize: 15, fontWeight: FontWeight.w600, color: ObsidianColors.dangerSoft),
          ),
        ),
      ),
    );
  }
}

/// สีประจำระดับ (จาก A-Node.dc.html) — ภาพ/สีเท่านั้น ตัวเลขของระดับมาจากเชน
@immutable
class _ObsTierArt {
  final String emblem;

  /// วงขอบ/เงาเรืองของการ์ดและแท็บที่เลือก
  final Color rim;

  /// แสงฟุ้งใหญ่หลังการ์ด
  final Color glow;

  /// สีตัวเลข stake
  final Color text;

  const _ObsTierArt(this.emblem, this.rim, this.glow, this.text);

  static _ObsTierArt of(MnTier t) => switch (t) {
    MnTier.light => const _ObsTierArt(ObsidianIcons.tierLight, Color(0xBFF59E5B), Color(0x38F59E5B), Color(0xFFFCD9B8)),
    MnTier.sentinel => const _ObsTierArt(
      ObsidianIcons.tierSentinel,
      Color(0xBFA5B4FC),
      Color(0x38A5B4FC),
      Color(0xFFE0E7FF),
    ),
    MnTier.guardian => const _ObsTierArt(
      ObsidianIcons.tierGuardian,
      Color(0xCCF3BA2F),
      Color(0x38F3BA2F),
      Color(0xFFFDE68A),
    ),
    MnTier.validator => const _ObsTierArt(
      ObsidianIcons.tierValidator,
      Color(0xD9C084FC),
      Color(0x40C084FC),
      Color(0xFFF5D0FE),
    ),
  };
}

extension _ObsidianMasterNode on _MasterNodeScreenState {
  // ════════════════════════════════════════════════════════════
  //  โครงหน้า
  // ════════════════════════════════════════════════════════════

  Widget _buildObsidian(LocaleProvider l, WalletProvider wallet) {
    final top = MediaQuery.paddingOf(context).top;
    final bottom = MediaQuery.paddingOf(context).bottom;
    final snap = _phase == _Phase.ready ? _snapshot : null;
    final selected = snap == null ? null : _obsSelected(snap);
    final ctaBottom = math.max(26.0, bottom + 12);

    final header = ObsidianScreenHeader(
      title: l.t('mn.title'),
      backSemantics: MaterialLocalizations.of(context).backButtonTooltip,
      trailing: ObsidianScreenHeaderTile(
        semanticLabel: l.t('obs.mn.help'),
        onTap: () => _obsShowHelp(l),
        child: const Icon3D(ObsidianIcons.info, size: 28),
      ),
      subtitle: _refreshing
          ? const Padding(
              padding: EdgeInsets.only(top: 4),
              child: SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2, color: ObsidianColors.cyan),
              ),
            )
          : null,
    );

    final Widget body;
    if (snap == null || selected == null) {
      body = ListView(
        padding: EdgeInsets.fromLTRB(24, math.max(52.0, top + 8), 24, 40),
        children: [header, const SizedBox(height: 28), _obsPhaseBody(l)],
      );
    } else {
      body = RefreshIndicator(
        onRefresh: _load,
        color: ObsidianColors.cyan,
        backgroundColor: ObsidianColors.card,
        edgeOffset: top,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          // ท้ายเว้นให้ปุ่มหลักที่ปักอยู่ล่างจอ
          padding: EdgeInsets.fromLTRB(24, math.max(52.0, top + 8), 24, 58 + ctaBottom + 24),
          children: _obsReadyChildren(l, wallet, snap, selected, header),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          const Positioned.fill(child: ObsidianScreenDim.node),
          Positioned.fill(child: body),
          if (snap != null && selected != null)
            Positioned(left: 24, right: 24, bottom: ctaBottom, child: _obsCta(l, wallet, snap, selected)),
        ],
      ),
    );
  }

  /// ระดับที่โชว์: ที่ผู้ใช้เลือก → ระดับของโหนดตัวเอง → ระดับแรกในรายการ (สเตคน้อยสุด)
  MnTier _obsSelected(MnSnapshot snap) {
    final display = snap.displayTiers.map((t) => t.tier).toList();
    if (_obsTier != null && display.contains(_obsTier)) return _obsTier!;
    final own = snap.node.status != MnStatus.inactive ? snap.node.tier : null;
    if (own != null && display.contains(own)) return own;
    return display.first;
  }

  // ════════════════════════════════════════════════════════════
  //  สถานะที่ไม่มีปุ่มเขียน (โหลด / ผิดพลาด / ยังไม่เปิด / ตรวจไม่ผ่าน / โค้ดไม่รู้จัก)
  // ════════════════════════════════════════════════════════════

  Widget _obsPhaseBody(LocaleProvider l) {
    final st = ObsidianStyle.of(context);
    switch (_phase) {
      case _Phase.loading:
        return Padding(
          padding: const EdgeInsets.only(top: 80),
          child: Column(
            children: [
              const SizedBox(
                width: 36,
                height: 36,
                child: CircularProgressIndicator(strokeWidth: 2.4, color: ObsidianColors.cyan),
              ),
              const SizedBox(height: 16),
              Text(l.t('mn.loading'), style: st.ui(fontSize: 14, color: ObsidianColors.textSec)),
            ],
          ),
        );
      case _Phase.error:
        return _obsMessage(
          icon: ObsidianIcons.network,
          title: l.t(_errorKey),
          body: null,
          primary: (l.t('mn.retry'), _load),
        );
      case _Phase.notDeployed:
        return _obsMessage(
          icon: ObsidianIcons.node,
          title: l.t('mn.notDeployedTitle'),
          body: l.t('mn.notDeployedBody'),
          primary: (l.t('mn.retry'), _load),
          secondary: (l.t('mn.openWebsite'), _openWebsite),
        );
      case _Phase.unverified:
        return _obsMessage(
          icon: ObsidianIcons.shield,
          danger: true,
          title: l.t('mn.unverifiedTitle'),
          body: l.t('mn.unverifiedBody'),
          primary: (l.t('mn.retry'), _load),
          secondary: (l.t('mn.openWebsite'), _openWebsite),
        );
      case _Phase.unknownCode:
        // สัญญาที่แอปไม่รู้จัก — พาไปอัปเดตแอปเท่านั้น ห้ามชี้ไปสเตคที่เว็บแทน
        return _obsMessage(
          icon: ObsidianIcons.update,
          danger: true,
          title: l.t('mn.unknownCodeTitle'),
          body: l.t('mn.unknownCodeBody'),
          primary: (l.t('mn.updateApp'), _openDownloadPage),
          secondary: (l.t('mn.retry'), _load),
        );
      case _Phase.ready:
        return const SizedBox.shrink();
    }
  }

  Widget _obsMessage({
    required String icon,
    required String title,
    required String? body,
    required (String, VoidCallback) primary,
    (String, VoidCallback)? secondary,
    bool danger = false,
  }) {
    final st = ObsidianStyle.of(context);
    return ObsidianPanel(
      surface: ObsidianSurface.panel.copyWith(radius: 26, ring: danger ? const Color(0x59F87171) : null),
      padding: const EdgeInsets.fromLTRB(22, 28, 22, 22),
      child: Column(
        children: [
          Icon3D(icon, size: 76, shadows: const [IconDropShadow.tile]),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: st.ui(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              height: 1.45,
              color: danger ? ObsidianColors.dangerSoft : ObsidianColors.text,
            ),
          ),
          if (body != null) ...[
            const SizedBox(height: 8),
            Text(
              body,
              textAlign: TextAlign.center,
              style: st.ui(fontSize: 13, height: 1.6, color: ObsidianColors.textSec),
            ),
          ],
          const SizedBox(height: 22),
          ObsidianButton(label: primary.$1, height: 52, onPressed: primary.$2),
          if (secondary != null) ...[
            const SizedBox(height: 10),
            ObsidianButton.secondary(label: secondary.$1, height: 48, onPressed: secondary.$2),
          ],
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════
  //  พร้อมใช้
  // ════════════════════════════════════════════════════════════

  List<Widget> _obsReadyChildren(
    LocaleProvider l,
    WalletProvider wallet,
    MnSnapshot snap,
    MnTier selected,
    Widget header,
  ) {
    final info = snap.tierInfo(selected);
    final block = snap.registerBlock(selected, wallet.balanceWei);
    final art = _ObsTierArt.of(selected);
    return [
      header,
      const SizedBox(height: 14),
      _obsStatusPill(l),
      if (snap.registrationPaused) ...[
        const SizedBox(height: 10),
        _obsBanner(l.t('mn.block.paused'), Icons.pause_circle_outline_rounded),
      ],
      if (snap.hasNodeCard) ...[const SizedBox(height: 14), _obsMyNodeCard(snap, l)],
      const SizedBox(height: 14),
      Semantics(
        label: l.t('mn.tiers'),
        container: true,
        child: Row(
          children: [
            for (final (i, t) in snap.displayTiers.indexed) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(child: _obsTierTab(t.tier, selected == t.tier)),
            ],
          ],
        ),
      ),
      const SizedBox(height: 14),
      // แสงฟุ้งสีประจำระดับหลังการ์ด (CSS 0 0 120px 10px) — เปลี่ยนสีนุ่ม ๆ .8 วิ
      Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 16,
            right: 16,
            top: 30,
            bottom: 10,
            child: IgnorePointer(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 800),
                curve: Curves.ease,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(60),
                  boxShadow: [BoxShadow(color: art.glow, blurRadius: 103, spreadRadius: 10)],
                ),
              ),
            ),
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 450),
            switchInCurve: Curves.easeOut,
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: SlideTransition(
                position: Tween(begin: const Offset(0, 0.03), end: Offset.zero).animate(anim),
                child: ScaleTransition(scale: Tween(begin: 0.98, end: 1.0).animate(anim), child: child),
              ),
            ),
            layoutBuilder: (current, previous) =>
                Stack(clipBehavior: Clip.none, alignment: Alignment.topCenter, children: [...previous, ?current]),
            child: KeyedSubtree(key: ValueKey(selected), child: _obsTierCard(info, snap, wallet, l, art)),
          ),
        ],
      ),
      const SizedBox(height: 14),
      _obsPoolRow(snap, l),
      // เหตุผลที่สมัครไม่ได้ตอนนี้ (บอกไว้ก่อนไปเว็บ — Validator อธิบายในการ์ดแล้ว)
      if (block != null && block != MnBlock.validatorWebsiteOnly) ...[
        const SizedBox(height: 8),
        _obsReason(_blockText(block, l, info: info)),
      ],
      const SizedBox(height: 14),
      _obsWebOnlyPanel(l),
      const SizedBox(height: 18),
      _obsFooter(snap, l),
    ];
  }

  Widget _obsStatusPill(LocaleProvider l) {
    final st = ObsidianStyle.of(context);
    final stale = _obsStale;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0x59000000), // ดำ 35%
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x14FFFFFF)),
      ),
      child: Row(
        children: [
          _ObsPulseDot(color: stale ? ObsidianColors.warning : ObsidianColors.success),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              stale ? l.t('mn.stale') : l.t('obs.mn.chainOk'),
              style: st.ui(fontSize: 12, height: 1.4, color: stale ? ObsidianColors.warning : ObsidianColors.chrome),
            ),
          ),
        ],
      ),
    );
  }

  Widget _obsBanner(String text, IconData icon) {
    final st = ObsidianStyle.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: ObsidianColors.warning.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ObsidianColors.warning.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: ObsidianColors.warning),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: st.ui(fontSize: 13, fontWeight: FontWeight.w500, color: ObsidianColors.warning),
            ),
          ),
        ],
      ),
    );
  }

  Widget _obsReason(String text, {Color color = ObsidianColors.textSec}) {
    final st = ObsidianStyle.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(Icons.info_outline_rounded, size: 15, color: color),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text, style: st.ui(fontSize: 12, height: 1.5, color: color)),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════
  //  แท็บระดับ + การ์ดระดับ
  // ════════════════════════════════════════════════════════════

  Widget _obsTierTab(MnTier tier, bool active) {
    final st = ObsidianStyle.of(context);
    final art = _ObsTierArt.of(tier);
    final surface = active
        ? ObsidianSurface(
            radius: 18,
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x24FFFFFF), Color(0x0AFFFFFF)],
            ),
            topHighlight: const Color(0x38FFFFFF),
            ring: art.rim,
            ringWidth: 1.5,
            shadows: [CssShadow(0, 12, 26, -10, art.rim)],
          )
        : const ObsidianSurface(
            radius: 18,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x0FFFFFFF), Color(0x05FFFFFF)],
            ),
            topHighlight: Color(0x1AFFFFFF),
          );
    return Semantics(
      selected: active,
      inMutuallyExclusiveGroup: true,
      child: ObsidianPressable(
        onTap: active ? null : () => _obsSelectTier(tier),
        semanticLabel: tier.label,
        child: AnimatedSlide(
          offset: Offset(0, active ? -2 / 84 : 0),
          duration: const Duration(milliseconds: 350),
          child: AnimatedOpacity(
            opacity: active ? 1 : 0.8,
            duration: const Duration(milliseconds: 350),
            child: SizedBox(
              height: 84,
              child: CustomPaint(
                painter: ObsidianSurfacePainter(surface),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon3D(art.emblem, size: 46, shadows: const [IconDropShadow(0, 6, 10, Color(0xCC000000))]),
                    const SizedBox(height: 4),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        tier.label,
                        style: st.ui(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: active ? Colors.white : ObsidianColors.textSec,
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
    );
  }

  Widget _obsTierCard(MnTierInfo info, MnSnapshot snap, WalletProvider wallet, LocaleProvider l, _ObsTierArt art) {
    final st = ObsidianStyle.of(context);
    final tier = info.tier;
    final surface = ObsidianSurface(
      radius: 26,
      // CSS linear-gradient(160deg, white .10, white .02 55%)
      gradient: const LinearGradient(
        begin: Alignment(-0.342, -0.94),
        end: Alignment(0.342, 0.94),
        colors: [Color(0x1AFFFFFF), Color(0x05FFFFFF)],
        stops: [0, 0.55],
      ),
      topHighlight: const Color(0x29FFFFFF),
      ring: art.rim,
      ringWidth: 1.5,
      shadows: const [CssShadow(0, 24, 44, -20, Color(0xF2000000))],
    );

    final apr = snap.aprCapToShow(tier);
    final (aprText, aprColor) = apr != null
        ? (MasterNodeService.formatBps(apr), ObsidianColors.successSoft)
        : !snap.poolFunded
        // กองว่าง: เพดาน APR ไม่มีความหมาย (จ่ายจริง 0) — ห้ามโชว์ตัวเลข
        ? (l.t('obs.mn.aprWaitPool'), ObsidianColors.warning)
        : ('—', ObsidianColors.textSec);
    final slots = info.isUnlimited
        ? '${info.activeNodes} / ${l.t('mn.unlimited')}'
        : '${info.activeNodes} / ${info.maxNodes}';
    final slash = info.slashPercentBps > BigInt.zero
        ? MasterNodeService.formatBps(info.slashPercentBps.toInt())
        : l.t('obs.mn.noSlash');

    // เบลอพื้นหลังก่อน แล้วค่อยวาดผิวการ์ดทับ — ถ้าให้ ObsidianPanel เบลอเอง
    // วงขอบสีระดับ (1.5px) จะโดนเบลอไปด้วยจนแทบมองไม่เห็น
    final card = Stack(
      children: [
        Positioned.fill(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(26),
            child: BackdropFilter(filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18), child: const SizedBox.expand()),
          ),
        ),
        ObsidianPanel(
          surface: surface,
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                // เว้นที่ให้ตราที่ลอยอยู่มุมขวาบน
                padding: const EdgeInsets.only(right: 112),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l.t('obs.mn.tierLabel'), style: st.ui(fontSize: 12, color: ObsidianColors.textSec)),
                    Text(
                      l.t('obs.mn.node').replaceAll('{tier}', tier.label),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: st.number(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        color: ObsidianColors.text,
                        height: 1.3,
                      ),
                    ),
                    Text(l.t('obs.mn.tag.${tier.name}'), style: st.ui(fontSize: 12.5, color: ObsidianColors.chrome)),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Text(l.t('obs.mn.mustStake'), style: st.ui(fontSize: 12, color: ObsidianColors.textSec)),
              // จำนวนจริงจาก getTierInfo — ยังไม่ตั้งค่า (minStake 0) = ขีด ไม่ใช่ 0
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: info.isConfigured ? MasterNodeService.formatTpix(info.minStake) : '—',
                        style: st.number(fontSize: 32, fontWeight: FontWeight.w700, color: art.text, letterSpacing: -1),
                      ),
                      TextSpan(
                        text: ' TPIX',
                        style: st.number(fontSize: 16, fontWeight: FontWeight.w600, color: ObsidianColors.textMuted),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _obsStat(l.t('obs.mn.minLock'), l.t('mn.days').replaceAll('{n}', '${info.lockDays}')),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _obsStat(l.t('obs.mn.nodes'), slots, color: info.isFull ? ObsidianColors.dangerSoft : null),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: _obsStat(l.t('obs.mn.aprCap'), aprText, color: aprColor)),
                  const SizedBox(width: 10),
                  Expanded(child: _obsStat(l.t('obs.mn.slash'), slash)),
                ],
              ),
              if (info.isConfigured) ...[const SizedBox(height: 14), _obsBalanceBar(info, wallet, l)],
              if (tier == MnTier.validator) ...[
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon3D(ObsidianIcons.shield, size: 22),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _blockText(MnBlock.validatorWebsiteOnly, l),
                        style: st.ui(fontSize: 12.5, height: 1.5, color: const Color(0xFFFDE68A)),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );

    return Stack(
      clipBehavior: Clip.none,
      children: [
        card,
        Positioned(
          right: 10,
          top: -26,
          child: _ObsFloatingEmblem(asset: art.emblem, rim: art.rim),
        ),
      ],
    );
  }

  Widget _obsStat(String label, String value, {Color? color}) {
    final st = ObsidianStyle.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0x4D000000), // ดำ 30%
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [BoxShadow(color: Color(0x99000000), offset: Offset(0, 1), blurRadius: 2.5, spreadRadius: -1)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: st.ui(fontSize: 11.5, color: ObsidianColors.textMuted, height: 1.4),
          ),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: st.ui(fontSize: 15, fontWeight: FontWeight.w600, color: color ?? ObsidianColors.text, height: 1.4),
          ),
        ],
      ),
    );
  }

  /// ยอดที่มีเทียบกับที่ต้องสเตค — คิดด้วย BigInt (ไม่ผ่าน double)
  Widget _obsBalanceBar(MnTierInfo info, WalletProvider wallet, LocaleProvider l) {
    final st = ObsidianStyle.of(context);
    final bal = wallet.balanceWei;
    if (bal == null) {
      return Text(l.t('obs.mn.balanceUnknown'), style: st.ui(fontSize: 12, color: ObsidianColors.textSec));
    }
    final hundred = BigInt.from(100);
    final raw = info.minStake <= BigInt.zero ? hundred : bal * hundred ~/ info.minStake;
    final pct = (raw > hundred ? hundred : (raw.isNegative ? BigInt.zero : raw)).toInt();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l.t('obs.mn.youHave').replaceAll('{amount}', MasterNodeService.formatTpix(bal, maxDecimals: 2)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: st.ui(fontSize: 12, color: ObsidianColors.textSec),
              ),
            ),
            Text('$pct%', style: st.ui(fontSize: 12, color: ObsidianColors.textSec)),
          ],
        ),
        const SizedBox(height: 6),
        ObsidianGradientBar(value: pct / 100, height: 6),
      ],
    );
  }

  Widget _obsPoolRow(MnSnapshot snap, LocaleProvider l) {
    final st = ObsidianStyle.of(context);
    final text = snap.poolFunded
        ? l
              .t('obs.mn.poolFunded')
              .replaceAll('{amount}', MasterNodeService.formatTpix(snap.availableFunds, maxDecimals: 2))
        : l.t('obs.mn.poolEmpty');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          Icon3D(ObsidianIcons.coins, size: 22, dimmed: !snap.poolFunded),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: st.ui(
                fontSize: 12,
                height: 1.5,
                color: snap.poolFunded ? ObsidianColors.textSec : ObsidianColors.warning,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// โฆษณา: เปิดโหนดได้ที่เว็บเท่านั้น (ปุ่มไปเว็บอยู่ที่ปุ่มหลักล่างจอ)
  Widget _obsWebOnlyPanel(LocaleProvider l) {
    final st = ObsidianStyle.of(context);
    return ObsidianPanel(
      surface: ObsidianSurface.panel.copyWith(radius: 20),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon3D(ObsidianIcons.network, size: 34),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.t('mn.webOnlyTitle'),
                    style: st.ui(fontSize: 14, fontWeight: FontWeight.w600, color: ObsidianColors.text)),
                const SizedBox(height: 4),
                Text(l.t('mn.webOnlyBody'),
                    style: st.ui(fontSize: 12, height: 1.55, color: ObsidianColors.textSec)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _obsFooter(MnSnapshot snap, LocaleProvider l) {
    final st = ObsidianStyle.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.t('mn.rewardNote'), style: st.ui(fontSize: 11.5, height: 1.6, color: ObsidianColors.textMuted)),
          const SizedBox(height: 6),
          GestureDetector(
            onLongPress: () async {
              await Clipboard.setData(ClipboardData(text: snap.registry));
              if (mounted) _snack(l.t('home.copied'));
            },
            child: Text(
              '${l.t('mn.contract')}: ${snap.registry}',
              style: st.mono(fontSize: 10.5, color: ObsidianColors.textMuted),
            ),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════
  //  ปุ่มหลัก (ปักล่างจอ)
  // ════════════════════════════════════════════════════════════

  Widget _obsCta(LocaleProvider l, WalletProvider wallet, MnSnapshot snap, MnTier selected) {
    final info = snap.tierInfo(selected);
    final art = _ObsTierArt.of(selected);

    // Validator: สมัครผ่านเว็บ (KYC) — ไม่มีการสเตคในแอป
    if (selected == MnTier.validator) {
      return ObsidianCta(label: l.t('obs.mn.ctaKyc'), glow: art.rim, onPressed: _sending == null ? _openWebsite : null);
    }

    // กระเป๋านี้มีโหนด/รางวัลค้างอยู่ = สัญญาไม่รับสมัครเพิ่ม ไม่ว่าจากแอปหรือเว็บ — บอกเหตุผลแทนพาไปเว็บ
    final block = snap.registerBlock(selected, wallet.balanceWei);
    if (block == MnBlock.hasNode || block == MnBlock.claimFirst || block == MnBlock.restakeWaitsForPool) {
      final labelKey = 'obs.mn.cta.${block!.name}';
      final label = l.t(labelKey);
      return ObsidianCta(
        label: label == labelKey ? l.t('mn.openNodeOnWeb') : label,
        onPressed: null,
        onDisabledTap: () => _snack(_blockText(block, l, info: info), error: true),
      );
    }
    return ObsidianCta(
      label: l.t('obs.mn.ctaWeb'),
      glow: art.rim,
      onPressed: _sending == null ? _openWebsite : null,
      onDisabledTap: () => _snack(l.t('obs.mn.cta.busy')),
    );
  }

  // ════════════════════════════════════════════════════════════
  //  โหนดของฉัน
  // ════════════════════════════════════════════════════════════

  Color _obsStatusColor(MnStatus s) => switch (s) {
    MnStatus.active => ObsidianColors.successSoft,
    MnStatus.slashed => ObsidianColors.dangerSoft,
    MnStatus.slashedWithdrawable => ObsidianColors.warning,
    _ => ObsidianColors.textSec,
  };

  Widget _obsKv(String label, String value, {Color? color, bool mono = false}) {
    final st = ObsidianStyle.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: st.ui(fontSize: 13, color: ObsidianColors.textMuted)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: mono
                  ? st.mono(fontSize: 12.5, color: color ?? ObsidianColors.text)
                  : st.ui(fontSize: 13, fontWeight: FontWeight.w600, color: color ?? ObsidianColors.text),
            ),
          ),
        ],
      ),
    );
  }

  Widget _obsMyNodeCard(MnSnapshot snap, LocaleProvider l) {
    final st = ObsidianStyle.of(context);
    final node = snap.node;
    // เงื่อนไขชุดเดียวกับการ์ดของธีมเดิมทุกข้อ
    final claimBlock = snap.claimBlock();
    final unstakeBlock = snap.unstakeBlock(DateTime.now());
    final restakeBlock = snap.pendingRewardBlock;
    final isActive = node.status == MnStatus.active;
    final statusColor = _obsStatusColor(node.status);
    final tier = node.tier;
    return ObsidianPanel(
      surface: ObsidianSurface.panel.copyWith(
        radius: 22,
        ring: tier == null ? null : _ObsTierArt.of(tier).rim.withValues(alpha: 0.45),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (tier != null) ...[Icon3D(_ObsTierArt.of(tier).emblem, size: 34), const SizedBox(width: 10)],
              Expanded(
                child: Text(
                  l.t('mn.myNode'),
                  style: st.ui(fontSize: 16, fontWeight: FontWeight.w600, color: ObsidianColors.text),
                ),
              ),
              _ObsStatusBadge(text: _statusText(node.status, l), color: statusColor),
            ],
          ),
          const SizedBox(height: 10),
          if (node.status != MnStatus.inactive) ...[
            _obsKv(l.t('mn.tier'), tier?.label ?? '—'),
            _obsKv(l.t('mn.staked'), '${MasterNodeService.formatTpix(node.stakedAmount)} TPIX'),
            if (isActive) ...[
              _obsKv(l.t('mn.unlockAt'), _dateFmt.format(node.unlockTime)),
              _obsKv(l.t('mn.uptime'), MasterNodeService.formatBps(node.uptimeBps.toInt())),
            ],
            if (node.endpoint.isNotEmpty) _obsKv(l.t('mn.endpointShort'), node.endpoint, mono: true),
            Container(height: 1, margin: const EdgeInsets.symmetric(vertical: 8), color: const Color(0x14FFFFFF)),
          ],
          _obsKv(l.t('mn.earned'), '${MasterNodeService.formatTpix(snap.pendingReward)} TPIX'),
          _obsKv(
            l.t('mn.claimable'),
            '${MasterNodeService.formatTpix(snap.claimableNow)} TPIX',
            color: ObsidianColors.successSoft,
          ),
          if (node.totalRewards > BigInt.zero)
            _obsKv(l.t('mn.totalPaid'), '${MasterNodeService.formatTpix(node.totalRewards)} TPIX'),
          if (claimBlock == MnBlock.poolEmpty && restakeBlock == null) ...[
            const SizedBox(height: 6),
            _obsReason(_blockText(MnBlock.poolEmpty, l), color: ObsidianColors.warning),
          ],
          const SizedBox(height: 12),
          if (snap.canWithdrawSlashed)
            ObsidianButton(
              label: l.t('mn.withdrawSlashed'),
              height: 48,
              loading: _sending == _Action.withdraw,
              onPressed: _sending == null ? _withdrawSlashed : null,
            )
          else
            Row(
              children: [
                Expanded(
                  child: ObsidianButton(
                    label: l.t('mn.claim'),
                    height: 48,
                    loading: _sending == _Action.claim,
                    onPressed: claimBlock == null && _sending == null ? _claim : null,
                  ),
                ),
                if (isActive) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: ObsidianButton.secondary(
                      label: l.t('mn.unstake'),
                      height: 48,
                      loading: _sending == _Action.unstake,
                      onPressed: unstakeBlock == null && _sending == null ? _unstake : null,
                    ),
                  ),
                ],
              ],
            ),
          if (isActive && unstakeBlock == MnBlock.locked) ...[
            const SizedBox(height: 8),
            _obsReason(_blockText(MnBlock.locked, l)),
          ],
          if (claimBlock == MnBlock.nothingToClaim && node.status != MnStatus.inactive) ...[
            const SizedBox(height: 8),
            _obsReason(_blockText(MnBlock.nothingToClaim, l)),
          ],
          if (restakeBlock != null) ...[
            const SizedBox(height: 8),
            _obsReason(_blockText(restakeBlock, l), color: ObsidianColors.warning),
          ],
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════
  //  วิธีใช้
  // ════════════════════════════════════════════════════════════

  void _obsShowHelp(LocaleProvider l) {
    final snap = _snapshot;
    ObsidianModalSheet.show<void>(
      context,
      builder: (sheetCtx) {
        final st = ObsidianStyle.of(sheetCtx);
        return ObsidianModalSheet(
          title: l.t('obs.mn.helpTitle'),
          children: [
            Text(l.t('mn.subtitle'), style: st.ui(fontSize: 14, height: 1.6, color: ObsidianColors.textSoft)),
            const SizedBox(height: 10),
            Text(l.t('mn.rewardNote'), style: st.ui(fontSize: 13, height: 1.6, color: ObsidianColors.textSec)),
            if (snap != null) ...[
              const SizedBox(height: 14),
              ObsidianPanel(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: ObsidianDetailRow(label: l.t('mn.contract'), value: snap.registry, mono: true, selectable: true),
              ),
            ],
            const SizedBox(height: 16),
            ObsidianButton.secondary(
              label: l.t('mn.openWebsite'),
              trailingIcon: Icons.open_in_new_rounded,
              onPressed: () {
                Navigator.pop(sheetCtx);
                _openWebsite();
              },
            ),
          ],
        );
      },
    );
  }
}

/// ป้ายสถานะโหนด (ทำงาน / ถูกปรับ / ออกแล้ว)
class _ObsStatusBadge extends StatelessWidget {
  final String text;
  final Color color;

  const _ObsStatusBadge({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    final st = ObsidianStyle.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        text,
        style: st.ui(fontSize: 12, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }
}

/// ตราระดับลอยขึ้นลง + เอียงเล็กน้อย (mock ndFloat 5 วิ) · ปิดภาพเคลื่อนไหว = นิ่ง
class _ObsFloatingEmblem extends StatefulWidget {
  final String asset;
  final Color rim;

  const _ObsFloatingEmblem({required this.asset, required this.rim});

  @override
  State<_ObsFloatingEmblem> createState() => _ObsFloatingEmblemState();
}

class _ObsFloatingEmblemState extends State<_ObsFloatingEmblem> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2500));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduce) {
      _c
        ..stop()
        ..value = 0.5;
    } else if (!_c.isAnimating) {
      _c.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final icon = Icon3D(
      widget.asset,
      size: 128,
      shadows: [const IconDropShadow(0, 18, 22, Color(0xD9000000)), IconDropShadow(0, 0, 22, widget.rim)],
    );
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, child) {
          final t = Curves.easeInOut.transform(_c.value);
          return Transform.translate(
            offset: Offset(0, -8 * t),
            child: Transform.rotate(angle: (-3 + 6 * t) * math.pi / 180, child: child),
          );
        },
        child: icon,
      ),
    );
  }
}

/// จุดสถานะเต้นช้า ๆ (mock ndDot 2 วิ)
class _ObsPulseDot extends StatefulWidget {
  final Color color;

  const _ObsPulseDot({required this.color});

  @override
  State<_ObsPulseDot> createState() => _ObsPulseDotState();
}

class _ObsPulseDotState extends State<_ObsPulseDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 1));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduce) {
      _c
        ..stop()
        ..value = 1;
    } else if (!_c.isAnimating) {
      _c.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, _) => Opacity(
        opacity: 0.4 + 0.6 * _c.value,
        child: Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.color,
            boxShadow: [BoxShadow(color: widget.color, blurRadius: 6)],
          ),
        ),
      ),
    );
  }
}
