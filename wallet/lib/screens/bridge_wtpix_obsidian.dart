// TPIX Wallet — สะพาน TPIX ⇄ wTPIX ธีม Obsidian
//
// part ของ bridge_wtpix_panel.dart โดยตั้งใจ: ใช้สถานะ · ค่าที่คำนวณ (BigInt wei) · _submitLock / _submitBurn
// · ตัวติดตาม ของเดิมทั้งหมด — ไฟล์นี้เปลี่ยนแค่หน้าตา (คีย์ของเทสต์เดิมอยู่ครบทุกตัว)
//
// Developed by Xman Studio

part of 'bridge_wtpix_panel.dart';

extension _WtpixObsidian on _WtpixBridgePanelState {
  Widget _obsBuild(LocaleProvider l) {
    if (_loading && _info == null) {
      return const Center(child: CircularProgressIndicator(color: ObsidianColors.cyan));
    }
    if (_loadFailed || _info == null) return BridgeLoadFailed(onRetry: _load);
    final info = _info!;
    final pad = MediaQuery.paddingOf(context);
    final entries = _tracker.entries;
    final latest = entries.isEmpty ? null : entries.first;
    final others = entries.skip(1).toList();
    final showCta = info.open && _tab != _Tab.track;

    return Column(
      children: [
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refreshAll,
            color: ObsidianColors.cyan,
            backgroundColor: ObsidianColors.card,
            child: ObsidianTopFade(
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
                children: [
                  if (_refreshing)
                    const Padding(padding: EdgeInsets.only(bottom: 10), child: ObsidianProgressBar(height: 3)),
                  if (!info.open)
                    ..._obsClosed(info, l)
                  else ...[
                    ObsidianSegmented<_Tab>(
                      options: [
                        ObsidianSegmentOption(_Tab.toBsc, l.t('bridge.wtpix.tabToBsc')),
                        ObsidianSegmentOption(_Tab.toTpix, l.t('bridge.wtpix.tabToTpix')),
                        ObsidianSegmentOption(_Tab.track, l.t('bridge.tabTrack')),
                      ],
                      value: _tab,
                      height: 34,
                      fontSize: 13,
                      onChanged: bridgeBusy ? null : (t) => _obsSet(() => _tab = t),
                    ),
                    const SizedBox(height: 14),
                    if (_tab == _Tab.track) _obsTrack(info, l) else ..._obsTransfer(info, l),
                  ],
                  if (latest != null) ...[const SizedBox(height: 14), _obsTrackedCard(latest, info, l, latest: true)],
                  if (info.open && _tab != _Tab.track) ..._obsRest(info, l),
                  if (others.isNotEmpty) ...[
                    const SizedBox(height: 22),
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Text(
                        l.t('bridge.tracked'),
                        style: ObsidianStyle.of(
                          context,
                        ).ui(fontSize: 15, fontWeight: FontWeight.w600, color: ObsidianColors.text),
                      ),
                    ),
                    for (final e in others) ...[const SizedBox(height: 10), _obsTrackedCard(e, info, l)],
                  ],
                  const SizedBox(height: 22),
                  BridgeObsHistory(
                    title: l.t('bridge.history'),
                    emptyText: l.t('bridge.historyEmpty'),
                    rows: [
                      for (final r in _history)
                        (
                          text: '${r.kind == wtpixToBsc ? 'TPIX → wTPIX' : 'wTPIX → TPIX'} · ${r.amount ?? '—'}',
                          label: bridgeT(l, wtpixStateBadge(r.state).labelKey, const {}, 'bridge.state.other'),
                          tone: wtpixStateBadge(r.state).tone,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        if (showCta)
          Padding(
            padding: EdgeInsets.fromLTRB(24, 8, 24, math.max(26.0, pad.bottom + 12)),
            child: _tab == _Tab.toBsc
                ? ObsidianButton(
                    key: const ValueKey('wtpix-lock-button'),
                    label: bridgeT(l, 'bridge.wtpix.lockButton', {'chain': info.bscName}),
                    onPressed: _canLock ? _submitLock : null,
                    loading: bridgeBusy,
                    loadingLabel: bridgeBusyLabel,
                  )
                : ObsidianButton(
                    key: const ValueKey('wtpix-burn-button'),
                    label: l.t('bridge.wtpix.burnButton'),
                    onPressed: _canBurn ? _submitBurn : null,
                    loading: bridgeBusy,
                    loadingLabel: bridgeBusyLabel,
                  ),
          ),
      ],
    );
  }

  ObsidianRouteNode _obsTpixNode(LocaleProvider l, String caption) =>
      ObsidianRouteNode(logo: bridgeTpixLogo(42), title: 'TPIX Chain', caption: caption, ring: ObsidianColors.violet);

  ObsidianRouteNode _obsBscNode(WtpixBridgeInfo info, String caption) => ObsidianRouteNode(
    logo: bridgeChainLogo(info.bscChainId, info.bscName, 42),
    title: bridgeChainShortName(info.bscChainId, info.bscName),
    caption: caption,
    ring: bridgeChainRing(info.bscChainId),
  );

  // ════════════════════════════════════════════════════════════
  //  ยังไม่เปิด
  // ════════════════════════════════════════════════════════════

  List<Widget> _obsClosed(WtpixBridgeInfo info, LocaleProvider l) => [
    BridgeObsClosedHero(
      key: const ValueKey('wtpix-closed'),
      kind: !info.enabled
          ? (info.installed ? BridgeClosedKind.paused : BridgeClosedKind.preparing)
          : BridgeClosedKind.locked,
      title: l.t('bridge.wtpix.notReady'),
      body: !info.enabled
          ? (info.installed ? l.t('bridge.wtpix.pausedBody') : l.t('bridge.wtpix.notReadyBody'))
          : l.t('bridge.misconfiguredBody'),
    ),
    const SizedBox(height: 14),
    ObsidianRouteCard(
      flowing: false,
      badge: l.t('obs.bridge.soon'),
      from: _obsTpixNode(l, l.t('obs.bridge.source')),
      to: _obsBscNode(info, l.t('obs.bridge.dest')),
    ),
  ];

  // ════════════════════════════════════════════════════════════
  //  ล็อก TPIX → wTPIX · เผา wTPIX → TPIX
  // ════════════════════════════════════════════════════════════

  List<Widget> _obsTransfer(WtpixBridgeInfo info, LocaleProvider l) {
    final toBsc = _tab == _Tab.toBsc;
    final check = toBsc ? _lockCheck : _burnCheck;
    final wei = toBsc ? _lockWei : _burnWei;
    final balance = toBsc ? _tpixBalance : _wtpixBalance;
    final insufficient = toBsc ? _lockInsufficient : _burnInsufficient;
    final ctrl = toBsc ? _lockCtrl : _burnCtrl;
    final limits = info.limits;
    final fee = limits[toBsc ? 'lock_fee' : 'burn_fee'];
    final symbol = toBsc ? 'TPIX' : info.tokenSymbol;

    return [
      ObsidianRouteCard(
        badge: bridgeT(l, 'obs.bridge.etaShort', {'m': '${toBsc ? info.bscEtaMinutes : info.tpixEtaMinutes}'}),
        from: toBsc ? _obsTpixNode(l, l.t('obs.bridge.source')) : _obsBscNode(info, l.t('obs.bridge.source')),
        to: toBsc ? _obsBscNode(info, l.t('obs.bridge.dest')) : _obsTpixNode(l, l.t('obs.bridge.dest')),
      ),
      const SizedBox(height: 14),
      BridgeObsAmountCard(
        label: l.t(toBsc ? 'obs.bridge.lockAmount' : 'obs.bridge.burnAmount'),
        balanceText: balance == null
            ? null
            : bridgeT(l, 'obs.bridge.balanceOn', {
                'chain': toBsc ? 'TPIX Chain' : bridgeChainShortName(info.bscChainId, info.bscName),
                'amount': obsidianAmountText(Units.toDouble(balance, tpixDecimals)),
                'symbol': symbol,
              }),
        logo: bridgeTpixLogo(34),
        input: KeyedSubtree(
          key: ValueKey(toBsc ? 'wtpix-lock-amount' : 'wtpix-burn-amount'),
          child: BridgeObsAmountInput(controller: ctrl, enabled: !bridgeBusy, onChanged: (_) => _obsSet(() {})),
        ),
        maxLabel: l.t('bridge.max'),
        onMax: bridgeBusy || balance == null ? null : () => _obsSet(() => ctrl.text = formatTpix(balance)),
        errorText: check.error != null
            ? bridgeT(l, check.error!, check.params)
            : insufficient
            ? l.t('bridge.errInsufficient')
            : null,
        warningText: check.warning != null ? bridgeT(l, check.warning!, check.warningParams) : null,
        rows: [
          ObsidianKv(
            bridgeT(l, 'obs.bridge.receiveOn', {'chain': toBsc ? info.bscName : 'TPIX Chain'}),
            wei != null && !check.blocked
                ? '${formatTpix(receiveWei(wei, fee))} ${toBsc ? info.tokenSymbol : 'TPIX'}'
                : '—',
            strong: true,
          ),
          // เวลาโดยประมาณอยู่บนป้ายกลางรางของการ์ดเส้นทางแล้ว
          ObsidianKv(l.t('bridge.wtpix.fee'), '${_limitText(fee)} TPIX'),
          ObsidianKv(
            l.t('obs.bridge.limits'),
            bridgeT(l, 'obs.bridge.limitsText', {
              'min': bridgeObsLimit(limits[toBsc ? 'min_lock' : 'min_burn']),
              'max': bridgeObsLimit(limits[toBsc ? 'max_lock_per_tx' : 'max_burn_per_tx']),
              'daily': bridgeObsLimit(limits[toBsc ? 'max_lock_per_address_daily' : 'max_burn_per_address_daily']),
              'symbol': symbol,
            }),
            quiet: true,
          ),
          ObsidianKv(
            l.t('bridge.wtpix.remainingToday'),
            '${bridgeObsLimit((toBsc ? info.minter : info.vault)['remaining_today'])} ${toBsc ? info.tokenSymbol : 'TPIX'}',
            quiet: true,
          ),
          if (toBsc)
            ObsidianKv(l.t('bridge.networkFee'), l.t('bridge.gasFree'), valueColor: ObsidianColors.successSoft)
          else
            ObsidianKv(
              bridgeT(l, 'bridge.gasBalance', {'symbol': 'BNB'}),
              _bnbBalance == null ? '—' : '${formatTpix(_bnbBalance)} BNB',
            ),
        ],
      ),
    ];
  }

  List<Widget> _obsRest(WtpixBridgeInfo info, LocaleProvider l) {
    final toBsc = _tab == _Tab.toBsc;
    // เพดานของ "สัญญาปลายทาง" ของทิศที่เลือก — ล็อก = ตัว mint บน BSC · เผา = คลังบนเชน TPIX
    final caps = toBsc ? info.minter : info.vault;
    return [
      const SizedBox(height: 14),
      ObsidianNotice(
        tone: ObsidianTone.danger,
        title: l.t('bridge.warnTitle'),
        emphasizeFirst: true,
        lines: [
          l.t('bridge.wtpix.warnNoExchange'),
          l.t('bridge.wtpix.warnSameAddress'),
          if (toBsc) l.t('bridge.wtpix.warnUseLock'),
          bridgeT(l, 'bridge.wtpix.warnCaps', {
            'perTx': _limitText(caps['max_per_tx']),
            'daily': _limitText(caps['daily_cap']),
          }),
        ],
      ),
      const SizedBox(height: 10),
      toBsc
          ? ObsidianCheckTile(
              key: const ValueKey('wtpix-ack-lock'),
              value: _ackLock,
              onChanged: bridgeBusy ? null : (v) => _obsSet(() => _ackLock = v),
              text: l.t('bridge.wtpix.ackLock'),
            )
          : ObsidianCheckTile(
              key: const ValueKey('wtpix-ack-burn'),
              value: _ackBurn,
              onChanged: bridgeBusy ? null : (v) => _obsSet(() => _ackBurn = v),
              text: l.t('bridge.wtpix.ackBurn'),
            ),
      const SizedBox(height: 14),
      BridgeObsHow(
        title: l.t('bridge.howTitle'),
        steps: toBsc
            ? [
                l.t('bridge.wtpix.howToBsc1'),
                bridgeT(l, 'bridge.wtpix.howToBsc2', {'chain': info.bscName}),
                l.t('bridge.wtpix.howToBsc3'),
              ]
            : [
                bridgeT(l, 'bridge.wtpix.howToTpix1', {'chain': info.bscName}),
                l.t('bridge.wtpix.howToTpix2'),
                l.t('bridge.wtpix.howToTpix3'),
              ],
      ),
    ];
  }

  // ════════════════════════════════════════════════════════════
  //  ติดตามด้วย tx hash
  // ════════════════════════════════════════════════════════════

  Widget _obsTrack(WtpixBridgeInfo info, LocaleProvider l) {
    final st = ObsidianStyle.of(context);
    final valid = isTxHash(_manualCtrl.text);
    return ObsidianPanel(
      surface: ObsidianCards.form,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l.t('bridge.trackTitle'),
            style: st.ui(fontSize: 14, fontWeight: FontWeight.w600, color: ObsidianColors.text),
          ),
          const SizedBox(height: 4),
          Text(l.t('bridge.wtpix.trackHint'), style: st.ui(fontSize: 12.5, height: 1.5, color: ObsidianColors.textSec)),
          const SizedBox(height: 12),
          ObsidianSegmented<String>(
            options: [
              ObsidianSegmentOption(wtpixToBsc, l.t('bridge.wtpix.trackLock')),
              ObsidianSegmentOption(wtpixToTpix, bridgeT(l, 'bridge.wtpix.trackBurn', {'chain': info.bscName})),
            ],
            value: _manualDirection,
            height: 34,
            fontSize: 12.5,
            onChanged: (d) => _obsSet(() => _manualDirection = d),
          ),
          const SizedBox(height: 12),
          ObsidianTextField(
            key: const ValueKey('wtpix-manual-hash'),
            controller: _manualCtrl,
            hint: l.t('bridge.trackTxHash'),
            mono: true,
            onChanged: (_) => _obsSet(() {}),
            errorText: _manualCtrl.text.trim().isNotEmpty && !valid ? l.t('bridge.errHashInvalid') : null,
          ),
          const SizedBox(height: 14),
          ObsidianButton(label: l.t('bridge.trackButton'), onPressed: valid ? _addManual : null, height: 52),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════
  //  การ์ดติดตาม
  // ════════════════════════════════════════════════════════════

  Widget _obsTrackedCard(TrackedTransfer e, WtpixBridgeInfo info, LocaleProvider l, {bool latest = false}) {
    final s = e.status;
    final badge = s == null ? null : wtpixStateBadge(s.state);
    final toBsc = e.kind == wtpixToBsc;
    final route = toBsc
        ? 'TPIX → ${info.tokenSymbol} (${info.bscName})'
        : '${info.tokenSymbol} (${info.bscName}) → TPIX';
    final amount = s?.amount;
    final title = '${latest ? l.t('obs.bridge.latest') : route}${amount != null ? ' · $amount' : ''}';
    final text = toBsc
        ? BridgeObsStepText(
            send: l.t('obs.bridge.step.lockTpix'),
            confirm: bridgeT(l, 'obs.bridge.step.confirm', {'chain': 'TPIX Chain'}),
            deliver: bridgeT(l, 'obs.bridge.step.mintWtpix', {'token': info.tokenSymbol, 'chain': info.bscName}),
          )
        : BridgeObsStepText(
            send: bridgeT(l, 'obs.bridge.step.burnWtpix', {'token': info.tokenSymbol, 'chain': info.bscName}),
            confirm: bridgeT(l, 'obs.bridge.step.confirm', {'chain': info.bscName}),
            deliver: l.t('obs.bridge.step.releaseTpix'),
          );
    final delivered = s?.rows
        .where((r) => r.amount != null)
        .map((r) => '${r.amount} ${(r.direction ?? e.kind) == wtpixToBsc ? info.tokenSymbol : 'TPIX'}')
        .firstOrNull;
    return BridgeObsTrackedCard(
      key: ValueKey('tracked-${e.key}'),
      title: title,
      txHash: e.txHash,
      explorerUrl: explorerTx(info.explorerFor(e.chainId), e.txHash),
      latest: latest,
      steps: bridgeObsSteps(
        l,
        status: s,
        text: text,
        badgeLabel: badge == null ? null : bridgeT(l, badge.labelKey, const {}, 'bridge.state.other'),
        delivered: delivered,
      ),
      onRemove: () => _remove(e),
      details: [
        for (final r in s?.rows ?? const <BridgeStatusRow>[])
          BridgeObsLink(
            label: (r.direction ?? e.kind) == wtpixToBsc
                ? bridgeT(l, 'bridge.wtpix.viewMint', {'chain': info.bscName})
                : l.t('bridge.wtpix.viewRelease'),
            url: r.url,
          ),
      ],
    );
  }
}
