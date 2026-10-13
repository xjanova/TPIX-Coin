// TPIX Wallet — หน้า "กิจกรรม" ธีม Obsidian (ตาม A-Activity.dc.html)
//
// เป็น part ของ tx_history_screen.dart: ใช้ตัวโหลด/สแกนเดิมของหน้านี้ร่วมกัน
// ธีมอื่นยังใช้เลย์เอาต์เดิมทั้งหมด
//
// ของบนหน้า:
//   - หัว "กิจกรรม" + วงหมุนตอนสแกน + ปุ่ม "ทุกเชน ▾" (กรองตามเชน)
//   - ชิปตัวกรอง ทั้งหมด / ส่ง / รับ / แลก / บริดจ์
//   - การ์ด "กำลังดำเนินการ" (ธุรกรรมรอเชน / สะพานยังไม่จ่ายปลายทาง) มีแสงวิ่ง + แถบเคลื่อนไหว
//     — แถบไม่ใช่เปอร์เซ็นต์จริง (ไม่มีข้อมูลว่าเหลือเท่าไร) จึงไม่มีตัวเลข % กำกับ
//   - แถวจัดกลุ่มตามวัน: ไอคอน 3D ตามชนิด · โลโก้เชน · เวลา · จำนวน · สถานะ
//   - แตะแถว = แผ่นรายละเอียด (คัดลอกแฮช / เปิด explorer ของเชนนั้น)
//   - ลากลง = สแกนบล็อกใหม่ · หน้าว่างมีปุ่มสแกนย้อนหลัง
//
// Developed by Xman Studio

part of 'tx_history_screen.dart';

extension _ObsidianActivity on _TxHistoryScreenState {
  Widget _buildObsidian(LocaleProvider l) {
    final wallet = context.watch<WalletProvider>();
    final top = MediaQuery.paddingOf(context).top;
    final feed = buildActivityFeed(wallet.txHistory, _ctx);
    final visible = [for (final i in feed) if (activityMatches(i, _filter, _chainFilter)) i];
    final inProgress = [for (final i in visible) if (i.inProgress) i];
    final days = groupActivityByDay([for (final i in visible) if (!i.inProgress) i]);

    final children = <Widget>[
      _obsHeader(l, wallet),
      const SizedBox(height: 14),
      _obsChips(l),
      const SizedBox(height: 14),
    ];

    if (feed.isEmpty) {
      children.add(wallet.isScanning ? _obsScanning(l) : _obsEmpty(l, wallet));
    } else if (visible.isEmpty) {
      children.add(_obsNoMatch(l));
    } else {
      if (inProgress.isNotEmpty) {
        // mock ไม่มีหัวข้อเหนือการ์ด (มีแค่ aria-label) — ตัวอ่านหน้าจอยังได้ยินหัวข้อนี้
        children.add(Semantics(header: true, label: l.t('obs.act.inProgress'), child: const SizedBox.shrink()));
        for (var i = 0; i < inProgress.length; i++) {
          final it = inProgress[i];
          if (i > 0) children.add(const SizedBox(height: 10));
          children.add(_ObsPendingCard(
              item: it,
              title: _obsTitle(it, l),
              amount: _obsAmountText(it),
              status: _obsPendingStatus(it, l),
              onTap: () => _obsShowDetail(it, l),
            ));
        }
        children.add(const SizedBox(height: 14));
      }
      final now = DateTime.now();
      for (var d = 0; d < days.length; d++) {
        if (d > 0) children.add(const SizedBox(height: 18));
        children
          ..add(ObsidianSectionLabel(
            activityDayLabel(days[d].day, now,
                thai: l.isThai, today: l.t('obs.act.today'), yesterday: l.t('obs.act.yesterday')),
            padding: const EdgeInsets.symmetric(horizontal: 4),
          ))
          ..add(const SizedBox(height: 14))
          ..add(ObsidianListGroup(
            shadow: true,
            radius: 22,
            verticalPadding: 4,
            dividerIndent: 70,
            dividerEndIndent: 14,
            children: [for (final it in days[d].items) _obsRow(it, l)],
          ));
      }
      if (wallet.isScanning) {
        children.add(const Padding(
          padding: EdgeInsets.only(top: 18),
          child: Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: ObsidianColors.cyan),
            ),
          ),
        ));
      }
    }

    return Scaffold(
      // เนื้อหาไหลลอดใต้แถบเมนูลอย (เหมือนหน้าแรก)
      extendBody: true,
      backgroundColor: Colors.transparent,
      bottomNavigationBar: ObsidianTabBar(current: ObsidianTab.activity, onReselect: _obsScrollTop),
      body: Stack(
        children: [
          // คลิปพื้นหลังจางกว่าหน้าแรกตาม mock (ไม่เลื่อนตามเนื้อหา)
          const Positioned.fill(child: ObsidianScreenDim.activity),
          RefreshIndicator(
            onRefresh: () async {
              await wallet.scanTransactions(blockCount: 50);
              await _loadContext();
            },
            color: ObsidianColors.cyan,
            backgroundColor: ObsidianColors.card,
            edgeOffset: top,
            child: ListView(
              controller: _scroll,
              physics: const AlwaysScrollableScrollPhysics(),
              // mock: หัวเริ่มที่ 56 · ท้ายเว้นให้แถบเมนูล่าง (รวมปุ่มสแกนที่โผล่พ้นแถบ)
              padding: EdgeInsets.fromLTRB(24, math.max(56.0, top + 12), 24, NotchedNavBar.heightFor(context) + 24),
              children: children,
            ),
          ),
        ],
      ),
    );
  }

  void _obsScrollTop() {
    if (_scroll.hasClients) {
      _scroll.animateTo(0, duration: const Duration(milliseconds: 400), curve: Curves.easeOutCubic);
    }
  }

  // ════════════════════════════════════════════════════════════
  //  หัว + ตัวกรอง
  // ════════════════════════════════════════════════════════════

  Widget _obsHeader(LocaleProvider l, WalletProvider wallet) {
    final st = ObsidianStyle.of(context);
    final chain = _chainFilter == null ? null : ChainConfig.byId(_chainFilter!);
    return Row(
      children: [
        Flexible(
          child: Semantics(
            header: true,
            child: Text(
              l.t('nav.activity'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: st.ui(fontSize: 26, fontWeight: FontWeight.w600, color: ObsidianColors.text),
            ),
          ),
        ),
        // กำลังสแกนบล็อก (มีรายการอยู่แล้ว — ไม่เอาวงหมุนเต็มจอมาบัง)
        if (wallet.isScanning && wallet.txHistory.isNotEmpty) ...[
          const SizedBox(width: 10),
          Semantics(
            label: l.t('tx.scanning'),
            child: const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: ObsidianColors.cyan),
            ),
          ),
        ],
        const Spacer(),
        ObsidianPillButton(
          label: chain == null ? l.t('obs.act.allChains') : chain.name,
          semanticLabel: l.t('obs.act.filterChain'),
          leading: chain == null ? null : ObsidianChainLogo(art: ObsidianChainArt.of(chain.chainId), size: 18),
          onTap: () => _obsPickChain(l),
        ),
      ],
    );
  }

  Widget _obsChips(LocaleProvider l) {
    const filters = ActivityFilter.values;
    String label(ActivityFilter f) => l.t('obs.act.f.${f.name}');
    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        // ชิปติดขอบหน้า (padding 24) — ให้เลื่อนเลยขอบได้โดยไม่ตัดเงา
        clipBehavior: Clip.none,
        itemCount: filters.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) => ObsidianFilterChip(
          label: label(filters[i]),
          selected: _filter == filters[i],
          onTap: () => _setFilter(filters[i]),
        ),
      ),
    );
  }

  void _obsPickChain(LocaleProvider l) {
    ObsidianModalSheet.show<void>(
      context,
      builder: (sheetCtx) {
        Widget option(int? chainId) {
          final selected = _chainFilter == chainId;
          final c = chainId == null ? null : ChainConfig.byId(chainId);
          return ObsidianListRow(
            leading: c == null
                ? const Icon3D(ObsidianIcons.network, size: 30)
                : ObsidianChainLogo(art: ObsidianChainArt.of(c.chainId), size: 30),
            title: c?.name ?? l.t('obs.act.allChains'),
            trailing: selected ? const Icon(Icons.check_rounded, size: 20, color: ObsidianColors.cyan) : null,
            chevron: false,
            onTap: () {
              Navigator.pop(sheetCtx);
              if (!selected) _setChainFilter(chainId);
            },
          );
        }

        return ObsidianModalSheet(
          title: l.t('obs.act.filterChain'),
          children: [
            ObsidianListGroup(children: [
              option(null),
              for (final c in ChainConfig.all) option(c.chainId),
            ]),
          ],
        );
      },
    );
  }

  // ════════════════════════════════════════════════════════════
  //  ข้อความของแถว
  // ════════════════════════════════════════════════════════════

  String _obsChainShort(int? id) => id == null ? '?' : ObsidianChainArt.of(id).shortLabel;

  String _obsTitle(ActivityItem it, LocaleProvider l) {
    final who = it.counterpartyName ?? activityShortAddress(it.counterparty);
    switch (it.kind) {
      case ActivityKind.send:
        return l.t('obs.act.sendTo').replaceAll('{who}', who);
      case ActivityKind.receive:
        return l.t('obs.act.recvFrom').replaceAll('{who}', who);
      case ActivityKind.swap:
        return l.t('obs.act.swap');
      case ActivityKind.contract:
        return l.t('obs.act.contract').replaceAll('{who}', who);
      case ActivityKind.bridge:
        final b = it.bridge!;
        final route = '${_obsChainShort(b.fromChainId)} → ${_obsChainShort(b.toChainId)}';
        return '${l.t('obs.act.bridge').replaceAll('{asset}', b.asset)} · $route';
    }
  }

  /// "−1,500 TPIX" / "+0.12 BNB" / "250 USDT" (บริดจ์ไม่มีเครื่องหมาย) · ไม่มีจำนวน = null
  String? _obsAmountText(ActivityItem it) {
    if (!it.hasAmount) return null;
    final sign = switch (it.kind) {
      ActivityKind.receive => '+',
      ActivityKind.bridge => '',
      _ => '−',
    };
    return '$sign${activityAmountText(it)} ${it.tx.symbol}';
  }

  String _obsPendingStatus(ActivityItem it, LocaleProvider l) {
    final b = it.bridge;
    if (b != null && it.status == ActivityStatus.confirmed) {
      final n = b.confirmations;
      return n == null ? l.t('obs.act.bridgeWorking') : l.t('obs.act.confirming').replaceAll('{n}', '$n');
    }
    return l.t('obs.act.waitChain');
  }

  (String, Color) _obsStatus(ActivityItem it, LocaleProvider l) => switch (it.status) {
        ActivityStatus.confirmed => (l.t('obs.act.ok'), ObsidianColors.successSoft),
        ActivityStatus.failed => (l.t('obs.act.failed'), ObsidianColors.dangerSoft),
        ActivityStatus.pending => (l.t('obs.act.pending'), const Color(0xFFC4B5FD)),
      };

  Widget _obsChainLine(ActivityItem it, LocaleProvider l, ObsidianStyle st) {
    final chain = it.chainId == null ? null : ChainConfig.byId(it.chainId!);
    return Row(
      children: [
        if (chain != null) ...[
          ObsidianChainLogo(art: ObsidianChainArt.of(chain.chainId), size: 14),
          const SizedBox(width: 5),
        ],
        Flexible(
          child: Text(
            '${chain?.name ?? l.t('obs.act.unknownChain')} · ${activityClock(it.time)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: st.ui(fontSize: 12, color: ObsidianColors.textMuted, height: 1.4),
          ),
        ),
      ],
    );
  }

  Widget _obsRow(ActivityItem it, LocaleProvider l) {
    final st = ObsidianStyle.of(context);
    final amount = _obsAmountText(it);
    final (statusText, statusColor) = _obsStatus(it, l);
    // ล้มเหลว: จำนวนสีปกติแบบ mock แต่สถานะบอกชัดว่าไม่ได้โอนออก
    final amountColor = it.kind == ActivityKind.receive && it.status != ActivityStatus.failed
        ? ObsidianColors.successSoft
        : ObsidianColors.text;
    final rowStatus = it.status == ActivityStatus.failed ? l.t('obs.act.failedRow') : statusText;
    final title = _obsTitle(it, l);
    return ObsidianPressable(
      onTap: () => _obsShowDetail(it, l),
      semanticLabel: '$title ${amount ?? ''} $rowStatus',
      pressedScale: 0.985,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(
          children: [
            Icon3D(_obsActivityIcon(it.kind), size: 44),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: st.ui(fontSize: 14.5, fontWeight: FontWeight.w500, color: ObsidianColors.text, height: 1.4),
                  ),
                  _obsChainLine(it, l, st),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (amount != null)
                  Text(
                    amount,
                    style: st.number(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: amountColor,
                      height: 1.4,
                    ),
                  ),
                Text(rowStatus, style: st.ui(fontSize: 11.5, color: statusColor, height: 1.4)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════
  //  หน้าว่าง / สแกน / ไม่ตรงตัวกรอง
  // ════════════════════════════════════════════════════════════

  Widget _obsScanning(LocaleProvider l) {
    final st = ObsidianStyle.of(context);
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
          Text(l.t('tx.scanning'), style: st.ui(fontSize: 14, color: ObsidianColors.textSec)),
        ],
      ),
    );
  }

  Widget _obsEmpty(LocaleProvider l, WalletProvider wallet) {
    final st = ObsidianStyle.of(context);
    return ObsidianPanel(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
      child: Column(
        children: [
          const Icon3D(ObsidianIcons.activity, size: 72, shadows: [IconDropShadow.tile]),
          const SizedBox(height: 16),
          Text(
            l.t('tx.empty'),
            textAlign: TextAlign.center,
            style: st.ui(fontSize: 17, fontWeight: FontWeight.w600, color: ObsidianColors.text),
          ),
          const SizedBox(height: 6),
          Text(
            l.t('tx.emptyHint'),
            textAlign: TextAlign.center,
            style: st.ui(fontSize: 13, color: ObsidianColors.textSec, height: 1.5),
          ),
          const SizedBox(height: 20),
          ObsidianButton.secondary(
            label: l.t('tx.scan'),
            trailingIcon: Icons.search_rounded,
            onPressed: wallet.isScanning ? null : () => wallet.scanTransactions(blockCount: 200),
          ),
        ],
      ),
    );
  }

  Widget _obsNoMatch(LocaleProvider l) {
    final st = ObsidianStyle.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 48),
      child: Column(
        children: [
          const Icon3D(ObsidianIcons.activity, size: 56, dimmed: true),
          const SizedBox(height: 12),
          Text(l.t('obs.act.noMatch'), style: st.ui(fontSize: 14, color: ObsidianColors.textSec)),
          const SizedBox(height: 14),
          ObsidianFilterChip(
            label: l.t('obs.act.clearFilter'),
            selected: false,
            onTap: () {
              _setFilter(ActivityFilter.all);
              _setChainFilter(null);
            },
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════
  //  แผ่นรายละเอียด
  // ════════════════════════════════════════════════════════════

  void _obsCopy(String text, String message) {
    Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 1)),
    );
  }

  Future<void> _obsOpenExplorer(ActivityItem it) async {
    try {
      await launchUrl(Uri.parse(activityExplorerUrl(it)), mode: LaunchMode.externalApplication);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.read<LocaleProvider>().t('common.browser_error'))),
      );
    }
  }

  String _obsFullDate(DateTime t, LocaleProvider l) {
    final day = activityDayLabel(t, DateTime(9999), thai: l.isThai, today: '', yesterday: '');
    return '$day · ${activityClock(t)}';
  }

  void _obsShowDetail(ActivityItem it, LocaleProvider l) {
    final tx = it.tx;
    final chain = it.chainId == null ? null : ChainConfig.byId(it.chainId!);
    final amount = _obsAmountText(it);
    final (statusText, statusColor) = _obsStatus(it, l);
    ObsidianModalSheet.show<void>(
      context,
      builder: (sheetCtx) {
        final st = ObsidianStyle.of(sheetCtx);
        final amountColor = it.status == ActivityStatus.failed
            ? ObsidianColors.textMuted
            : it.kind == ActivityKind.receive
                ? ObsidianColors.successSoft
                : ObsidianColors.text;
        return ObsidianModalSheet(
          children: [
            const SizedBox(height: 4),
            Row(
              children: [
                Icon3D(_obsActivityIcon(it.kind), size: 52),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _obsTitle(it, l),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: st.ui(fontSize: 16.5, fontWeight: FontWeight.w600, color: ObsidianColors.text),
                      ),
                      _obsChainLine(it, l, st),
                    ],
                  ),
                ),
              ],
            ),
            if (amount != null) ...[
              const SizedBox(height: 16),
              Text(
                amount,
                style: st.number(fontSize: 30, fontWeight: FontWeight.w700, color: amountColor, letterSpacing: -0.5),
              ),
            ],
            const SizedBox(height: 10),
            Align(alignment: Alignment.centerLeft, child: ObsidianBadge(statusText, color: statusColor)),
            if (it.inProgress && it.status == ActivityStatus.confirmed && it.bridge != null)
              ObsidianNote(text: _obsPendingStatus(it, l), color: const Color(0xFFC4B5FD)),
            const SizedBox(height: 14),
            ObsidianPanel(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Column(
                children: [
                  ObsidianDetailRow(label: l.t('obs.act.time'), value: _obsFullDate(it.time, l)),
                  ObsidianDetailRow(
                    label: l.t('obs.act.network'),
                    value: chain?.name ?? l.t('obs.act.unknownChain'),
                    leading: chain == null
                        ? null
                        : ObsidianChainLogo(art: ObsidianChainArt.of(chain.chainId), size: 16),
                  ),
                  if (it.bridge != null)
                    ObsidianDetailRow(
                      label: l.t('obs.act.route'),
                      value: '${_obsChainShort(it.bridge!.fromChainId)} → ${_obsChainShort(it.bridge!.toChainId)}',
                    ),
                  ObsidianDetailRow(
                    label: l.t('tx.from'),
                    value: activityShortAddress(tx.fromAddress),
                    mono: true,
                    trailingIcon: Icons.copy_rounded,
                    onTap: () => _obsCopy(tx.fromAddress, l.t('home.copied')),
                  ),
                  ObsidianDetailRow(
                    label: l.t('tx.to'),
                    value: activityShortAddress(tx.toAddress),
                    mono: true,
                    trailingIcon: Icons.copy_rounded,
                    onTap: () => _obsCopy(tx.toAddress, l.t('home.copied')),
                  ),
                  if (tx.tokenAddress != null)
                    ObsidianDetailRow(
                      label: l.t('token.contractAddress'),
                      value: activityShortAddress(tx.tokenAddress!),
                      mono: true,
                      trailingIcon: Icons.copy_rounded,
                      onTap: () => _obsCopy(tx.tokenAddress!, l.t('home.copied')),
                    ),
                  ObsidianDetailRow(
                    label: l.t('tx.hash'),
                    value: tx.shortHash,
                    mono: true,
                    trailingIcon: Icons.copy_rounded,
                    onTap: () => _obsCopy(tx.txHash, l.t('tx.hashCopied')),
                  ),
                  if (tx.blockNumber != null) ObsidianDetailRow(label: l.t('tx.block'), value: '#${tx.blockNumber}'),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: ObsidianButton.secondary(
                    label: l.t('tx.copyHash'),
                    onPressed: () {
                      Navigator.pop(sheetCtx);
                      _obsCopy(tx.txHash, l.t('tx.hashCopied'));
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ObsidianButton(
                    label: l.t('tx.viewExplorer'),
                    height: 52,
                    trailingIcon: Icons.open_in_new_rounded,
                    onPressed: () {
                      Navigator.pop(sheetCtx);
                      _obsOpenExplorer(it);
                    },
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// การ์ด "กำลังดำเนินการ" — ไล่ม่วง + วงขอบม่วง + แสงวิ่ง + แถบเคลื่อนไหว (A-Activity.dc.html)
class _ObsPendingCard extends StatelessWidget {
  final ActivityItem item;
  final String title;
  final String? amount;
  final String status;
  final VoidCallback onTap;

  const _ObsPendingCard({
    required this.item,
    required this.title,
    required this.amount,
    required this.status,
    required this.onTap,
  });

  static const _surface = ObsidianSurface(
    radius: 20,
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0x248B5CF6), Color(0x05FFFFFF)], // violet .14 → white .02
    ),
    topHighlight: Color(0x1FFFFFFF),
    ring: Color(0x598B5CF6), // violet .35
    shadows: [CssShadow(0, 16, 30, -18, Color(0xB38B5CF6))],
  );

  static const _lilac = Color(0xFFC4B5FD);

  @override
  Widget build(BuildContext context) {
    final st = ObsidianStyle.of(context);
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return ObsidianPressable(
      onTap: onTap,
      semanticLabel: '$title ${amount ?? ''} $status',
      pressedScale: 0.985,
      child: CustomPaint(
        painter: const ObsidianSurfacePainter(_surface),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            children: [
              const Positioned.fill(child: ObsidianShimmerSweep()),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  children: [
                    Icon3D(_obsActivityIcon(item.kind), size: 44),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: st.ui(fontSize: 14, fontWeight: FontWeight.w600, color: ObsidianColors.text),
                                ),
                              ),
                              if (amount != null) ...[
                                const SizedBox(width: 8),
                                Text(
                                  amount!,
                                  style: st.number(fontSize: 14, fontWeight: FontWeight.w600, color: ObsidianColors.text),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 5),
                          Row(
                            children: [
                              SizedBox(
                                width: 11,
                                height: 11,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  value: reduce ? 0.3 : null,
                                  color: _lilac,
                                  backgroundColor: _lilac.withValues(alpha: 0.3),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  status,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: st.ui(fontSize: 12, color: _lilac),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 5),
                          const ObsidianGradientBar(height: 4),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// ไอคอน 3D ตามชนิดรายการ (แถว / การ์ดกำลังดำเนินการ / แผ่นรายละเอียด)
String _obsActivityIcon(ActivityKind k) => switch (k) {
      ActivityKind.send => ObsidianIcons.send,
      ActivityKind.receive => ObsidianIcons.receive,
      ActivityKind.swap => ObsidianIcons.swap,
      ActivityKind.bridge => ObsidianIcons.bridge,
      ActivityKind.contract => ObsidianIcons.link,
    };
