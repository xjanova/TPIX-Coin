// TPIX Wallet — สะพาน USDT ธีม Obsidian (ตาม A-Bridge.dc.html)
//
// part ของ bridge_usdt_panel.dart โดยตั้งใจ: ใช้สถานะ · ค่าที่คำนวณ (BigInt) · _submitDeposit / _submitWithdraw
// · ตัวติดตาม ของเดิมทั้งหมด — ไฟล์นี้เปลี่ยนแค่หน้าตา (คีย์ของเทสต์เดิมอยู่ครบทุกตัว)
//
// เลย์เอาต์: [แท็บ ฝาก/ถอน/ติดตาม] → การ์ดเส้นทาง → การ์ดจำนวน → รายการล่าสุด (ขั้นตอน)
//            → คำเตือน · ที่อยู่ให้ตรวจ · ติ๊กยอมรับ · วิธีใช้ → รายการอื่น → ประวัติ · ปุ่มหลักขาวติดขอบล่าง
// สะพานปิด (ค่าจริงตอนนี้): การ์ดสถานะ "กำลังเตรียมเปิด" + เส้นทางตัวอย่าง (ไม่มีช่องกรอก ไม่มีปุ่มส่ง)
//
// Developed by Xman Studio

part of 'bridge_usdt_panel.dart';

extension _UsdtObsidian on _UsdtBridgePanelState {
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

    final (top, rest) = !info.open
        ? (const <Widget>[], const <Widget>[])
        : switch (_tab) {
            _Tab.deposit => (_obsDepositTop(info, l), _obsDepositRest(info, l)),
            _Tab.withdraw => (_obsWithdrawTop(info, l), _obsWithdrawRest(l)),
            _Tab.track => (<Widget>[_obsTrack(info, l)], const <Widget>[]),
          };
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
                        ObsidianSegmentOption(_Tab.deposit, l.t('bridge.tabDeposit')),
                        ObsidianSegmentOption(_Tab.withdraw, l.t('bridge.tabWithdraw')),
                        ObsidianSegmentOption(_Tab.track, l.t('bridge.tabTrack')),
                      ],
                      value: _tab,
                      height: 34,
                      fontSize: 13,
                      // ระหว่างส่ง ห้ามสลับไปแก้ฟอร์มอื่น
                      onChanged: bridgeBusy ? null : (t) => _obsSet(() => _tab = t),
                    ),
                    const SizedBox(height: 14),
                    ...top,
                  ],
                  if (latest != null) ...[const SizedBox(height: 14), _obsTrackedCard(latest, info, l, latest: true)],
                  ...rest,
                  if (others.isNotEmpty) ...[
                    const SizedBox(height: 22),
                    _obsSectionTitle(l.t('bridge.tracked')),
                    for (final e in others) ...[const SizedBox(height: 10), _obsTrackedCard(e, info, l)],
                  ],
                  const SizedBox(height: 22),
                  BridgeObsHistory(
                    title: l.t('bridge.history'),
                    emptyText: l.t('bridge.historyEmpty'),
                    rows: [
                      for (final r in _history)
                        (
                          text:
                              '${r.kind == usdtDeposit ? l.t('bridge.deposits') : l.t('bridge.withdrawals')}'
                              ' · ${_chainName(r.chainId)} · ${r.amount ?? '—'} USDT',
                          label: bridgeT(l, stateBadge(r.state).labelKey, const {}, 'bridge.state.other'),
                          tone: stateBadge(r.state).tone,
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
            child: _tab == _Tab.deposit ? _obsDepositCta(l) : _obsWithdrawCta(l),
          ),
      ],
    );
  }

  Widget _obsSectionTitle(String text) => Padding(
    padding: const EdgeInsets.only(left: 4),
    child: Text(
      text,
      style: ObsidianStyle.of(context).ui(fontSize: 15, fontWeight: FontWeight.w600, color: ObsidianColors.text),
    ),
  );

  // ════════════════════════════════════════════════════════════
  //  สะพานยังไม่เปิด / หยุด / ตั้งค่าไม่ครบ
  // ════════════════════════════════════════════════════════════

  List<Widget> _obsClosed(UsdtBridgeInfo info, LocaleProvider l) {
    final chains = info.chains.where((c) => c.chainId > 0 && c.chainId != bridgeTpixChainId).toList();
    // เส้นทางตัวอย่าง — เชนแรกที่เซิร์ฟเวอร์ประกาศ (BSC ก่อนถ้ามี)
    final preview = chains.where((c) => c.chainId == 56).firstOrNull ?? chains.firstOrNull;
    return [
      BridgeObsClosedHero(
        key: const ValueKey('usdt-closed'),
        kind: !info.enabled
            ? (info.installed ? BridgeClosedKind.paused : BridgeClosedKind.preparing)
            : BridgeClosedKind.locked,
        title: l.t('bridge.notReady'),
        body: !info.enabled
            ? (info.installed ? l.t('bridge.pausedBody') : l.t('bridge.notReadyBody'))
            : l.t('bridge.misconfiguredBody'),
      ),
      if (preview != null) ...[
        const SizedBox(height: 14),
        ObsidianRouteCard(
          flowing: false,
          badge: l.t('obs.bridge.soon'),
          from: ObsidianRouteNode(
            logo: bridgeChainLogo(preview.chainId, preview.name, 42),
            title: bridgeChainShortName(preview.chainId, preview.name),
            caption: l.t('obs.bridge.source'),
            ring: bridgeChainRing(preview.chainId),
          ),
          to: ObsidianRouteNode(
            logo: bridgeTpixLogo(42),
            title: 'TPIX Chain',
            caption: l.t('obs.bridge.dest'),
            ring: ObsidianColors.violet,
          ),
        ),
      ],
    ];
  }

  // ════════════════════════════════════════════════════════════
  //  ฝาก
  // ════════════════════════════════════════════════════════════

  List<BridgeObsChainOption> _obsDepositOptions(UsdtBridgeInfo info, LocaleProvider l) => [
    for (final ch in info.chains.where((ch) => ch.chainId != bridgeTpixChainId && ch.chainId > 0))
      (
        id: ch.chainId,
        title: ch.name,
        subtitle: ch.depositable
            ? ch.usdtSymbol
            : !ch.serverEnabled
            ? l.t('bridge.chainDisabled')
            : !ch.appSupported
            ? l.t('bridge.chainNotInApp')
            : l.t('bridge.chainMisconfigured'),
        enabled: ch.depositable,
      ),
  ];

  /// เปลี่ยนเชนต้นทาง — ผลเหมือนแตะตัวเลือกเชนแบบเดิม (ล้างจำนวน + อ่านยอดใหม่)
  Future<void> _obsPickSource(UsdtBridgeInfo info, LocaleProvider l) async {
    final id = await showBridgeObsChainPicker(
      context,
      title: l.t('obs.bridge.pickSource'),
      chains: _obsDepositOptions(info, l),
      selected: _sourceChainId,
    );
    if (id == null || !mounted || bridgeBusy) return;
    _obsSet(() {
      _sourceChainId = id;
      _depositCtrl.clear();
    });
    unawaited(_refreshSourceBalance(reset: true));
  }

  List<Widget> _obsDepositTop(UsdtBridgeInfo info, LocaleProvider l) {
    final source = _source;
    final shown = source ?? info.chains.where((c) => c.chainId > 0 && c.chainId != bridgeTpixChainId).firstOrNull;
    return [
      if (shown != null)
        ObsidianRouteCard(
          flowing: source?.depositable ?? false,
          badge: source == null ? null : bridgeT(l, 'obs.bridge.etaShort', {'m': '${source.etaMinutes}'}),
          from: ObsidianRouteNode(
            logo: bridgeChainLogo(shown.chainId, shown.name, 42),
            title: bridgeChainShortName(shown.chainId, shown.name),
            caption: l.t('obs.bridge.source'),
            ring: bridgeChainRing(shown.chainId),
            semanticLabel: l.t('obs.bridge.changeSource'),
            onTap: bridgeBusy ? null : () => _obsPickSource(info, l),
          ),
          to: ObsidianRouteNode(
            logo: bridgeTpixLogo(42),
            title: 'TPIX Chain',
            caption: l.t('obs.bridge.dest'),
            ring: ObsidianColors.violet,
          ),
        ),
      const SizedBox(height: 14),
      if (source == null || !source.depositable)
        ObsidianNotice(tone: ObsidianTone.warning, lines: [l.t('bridge.noDepositChain')])
      else
        _obsDepositAmount(info, l, source),
    ];
  }

  Widget _obsDepositAmount(UsdtBridgeInfo info, LocaleProvider l, UsdtBridgeChain source) {
    final check = _depositCheck;
    final units6 = _depositUnits6;
    final limits = info.limits;
    final balance = _sourceBalance;
    return BridgeObsAmountCard(
      label: l.t('obs.bridge.depositAmount'),
      balanceText: balance == null
          ? null
          : bridgeT(l, 'obs.bridge.balanceOn', {
              'chain': bridgeChainShortName(source.chainId, source.name),
              'amount': obsidianStableText(Units.toDouble(balance, source.usdtDecimals)),
              'symbol': source.usdtSymbol,
            }),
      logo: bridgeUsdtLogo(34),
      input: KeyedSubtree(
        key: const ValueKey('usdt-deposit-amount'),
        child: BridgeObsAmountInput(controller: _depositCtrl, enabled: !bridgeBusy, onChanged: (_) => _obsSet(() {})),
      ),
      maxLabel: l.t('bridge.max'),
      onMax: bridgeBusy || balance == null ? null : _fillMaxDeposit,
      errorText: check.error != null
          ? bridgeT(l, check.error!, check.params)
          : _depositInsufficient
          ? l.t('bridge.errInsufficient')
          : null,
      warningText: check.warning != null ? bridgeT(l, check.warning!, check.warningParams) : null,
      rows: [
        ObsidianKv(
          bridgeT(l, 'obs.bridge.receiveOn', {'chain': 'TPIX Chain'}),
          units6 != null && !check.blocked ? '${formatUnitsPlain(units6, usdtTpixDecimals)} USDT' : '—',
          strong: true,
        ),
        // เวลาโดยประมาณอยู่บนป้ายกลางรางของการ์ดเส้นทางแล้ว (ตาม mock)
        ObsidianKv(l.t('bridge.depositFee'), l.t('bridge.free'), valueColor: ObsidianColors.successSoft, strong: true),
        ObsidianKv(
          l.t('obs.bridge.limits'),
          bridgeT(l, 'obs.bridge.limitsText', {
            'min': bridgeObsLimit(limits['min_deposit']),
            'max': bridgeObsLimit(limits['max_deposit_per_tx']),
            'daily': bridgeObsLimit(limits['max_deposit_per_address_daily']),
            'symbol': 'USDT',
          }),
          quiet: true,
        ),
      ],
    );
  }

  List<Widget> _obsDepositRest(UsdtBridgeInfo info, LocaleProvider l) {
    final source = _source;
    final how = BridgeObsHow(
      title: l.t('bridge.howTitle'),
      steps: [
        l.t('bridge.howDeposit1'),
        l.t('bridge.howDeposit2'),
        l.t('bridge.howDeposit3'),
        l.t('bridge.howDeposit4'),
      ],
    );
    if (source == null || !source.depositable) return [const SizedBox(height: 14), how];
    return [
      const SizedBox(height: 14),
      // ความผิดพลาดแบบนี้เรียกเงินคืนไม่ได้ — ต้องอยู่ก่อนช่องติ๊กยอมรับเสมอ
      ObsidianNotice(
        tone: ObsidianTone.danger,
        title: l.t('bridge.warnTitle'),
        emphasizeFirst: true,
        lines: [
          l.t('bridge.warnNoExchange'),
          l.t('bridge.warnOwnWallet'),
          l.t('bridge.warnSameAddress'),
          l.t('bridge.warnUsdtOnly'),
        ],
      ),
      const SizedBox(height: 14),
      ObsidianPanel(
        surface: ObsidianCards.details,
        padding: const EdgeInsets.fromLTRB(16, 14, 6, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.t('obs.bridge.addresses'),
              style: ObsidianStyle.of(
                context,
              ).ui(fontSize: 13, fontWeight: FontWeight.w600, color: ObsidianColors.text),
            ),
            const SizedBox(height: 8),
            BridgeObsAddress(label: '${l.t('bridge.vaultAddress')} (${source.name})', address: info.vaultAddress!),
            const SizedBox(height: 6),
            BridgeObsAddress(
              label: bridgeT(l, 'bridge.usdtContractDecimals', {'decimals': '${source.usdtDecimals}'}),
              address: source.usdtAddress!,
            ),
            BridgeObsLink(
              label: l.t('bridge.viewContract'),
              url: source.explorer == null ? null : '${source.explorer}/token/${source.usdtAddress}',
            ),
          ],
        ),
      ),
      const SizedBox(height: 10),
      ObsidianCheckTile(
        key: const ValueKey('usdt-ack'),
        value: _ackOwnWallet,
        onChanged: bridgeBusy ? null : (v) => _obsSet(() => _ackOwnWallet = v),
        text: l.t('bridge.ackOwnWallet'),
      ),
      const SizedBox(height: 14),
      how,
    ];
  }

  Widget _obsDepositCta(LocaleProvider l) {
    final units = _depositUnits;
    final source = _source;
    final ready = units != null && source != null && !_depositCheck.blocked;
    return ObsidianButton(
      key: const ValueKey('usdt-deposit-button'),
      label: ready
          ? bridgeT(l, 'obs.bridge.depositCta', {'amount': formatUnitsPlain(units, source.usdtDecimals)})
          : l.t('bridge.sendUsdt'),
      onPressed: _canDeposit ? _submitDeposit : null,
      loading: bridgeBusy,
      loadingLabel: bridgeBusyLabel,
    );
  }

  // ════════════════════════════════════════════════════════════
  //  ถอน
  // ════════════════════════════════════════════════════════════

  Future<void> _obsPickTarget(UsdtBridgeInfo info, LocaleProvider l) async {
    final id = await showBridgeObsChainPicker(
      context,
      title: l.t('obs.bridge.pickTarget'),
      chains: [
        for (final ch in info.chains.where((ch) => ch.chainId != bridgeTpixChainId && ch.chainId > 0))
          (
            id: ch.chainId,
            title: ch.name,
            subtitle: ch.withdrawable
                ? '${l.t('bridge.feeShort')}: ${ch.withdrawFee} USDT'
                : l.t('bridge.chainDisabled'),
            enabled: ch.withdrawable,
          ),
      ],
      selected: _targetChainId,
    );
    if (id == null || !mounted || bridgeBusy) return;
    _obsSet(() => _targetChainId = id);
  }

  List<Widget> _obsWithdrawTop(UsdtBridgeInfo info, LocaleProvider l) {
    final target = _target;
    final shown = target ?? info.chains.where((c) => c.chainId > 0 && c.chainId != bridgeTpixChainId).firstOrNull;
    final check = _withdrawCheck;
    final limits = info.limits;
    final balance = _tpixUsdtBalance;
    final hasAmount = _withdrawCtrl.text.trim().isNotEmpty;
    return [
      if (shown != null)
        ObsidianRouteCard(
          flowing: target?.withdrawable ?? false,
          from: ObsidianRouteNode(
            logo: bridgeTpixLogo(42),
            title: 'TPIX Chain',
            caption: l.t('obs.bridge.source'),
            ring: ObsidianColors.violet,
          ),
          to: ObsidianRouteNode(
            logo: bridgeChainLogo(shown.chainId, shown.name, 42),
            title: bridgeChainShortName(shown.chainId, shown.name),
            caption: l.t('obs.bridge.dest'),
            ring: bridgeChainRing(shown.chainId),
            semanticLabel: l.t('obs.bridge.changeTarget'),
            onTap: bridgeBusy ? null : () => _obsPickTarget(info, l),
          ),
        ),
      const SizedBox(height: 14),
      BridgeObsAmountCard(
        label: l.t('obs.bridge.withdrawAmount'),
        balanceText: balance == null
            ? null
            : bridgeT(l, 'obs.bridge.balanceOn', {
                'chain': 'TPIX Chain',
                'amount': obsidianStableText(Units.toDouble(balance, usdtTpixDecimals)),
                'symbol': 'USDT',
              }),
        logo: bridgeUsdtLogo(34),
        input: KeyedSubtree(
          key: const ValueKey('usdt-withdraw-amount'),
          child: BridgeObsAmountInput(
            controller: _withdrawCtrl,
            enabled: !bridgeBusy,
            onChanged: (_) => _obsSet(() {}),
          ),
        ),
        maxLabel: l.t('bridge.max'),
        onMax: bridgeBusy || balance == null
            ? null
            : () => _obsSet(() => _withdrawCtrl.text = formatUnitsPlain(balance, usdtTpixDecimals)),
        errorText: check.error != null ? bridgeT(l, check.error!, check.params) : null,
        extra: [
          const SizedBox(height: 12),
          Text(
            l.t('bridge.targetAddress'),
            style: ObsidianStyle.of(context).ui(fontSize: 12.5, color: ObsidianColors.textSec),
          ),
          const SizedBox(height: 6),
          ObsidianTextField(
            key: const ValueKey('usdt-target-address'),
            controller: _targetCtrl,
            hint: '0x…',
            mono: true,
            maxLines: 2,
            enabled: !bridgeBusy,
            onChanged: (_) => _obsSet(() {}),
            errorText: _addressError != null ? l.t(_addressError!) : null,
            suffix: _owner == null
                ? null
                : ObsidianChipButton(
                    label: l.t('bridge.useMyAddress'),
                    onTap: bridgeBusy ? null : () => _obsSet(() => _targetCtrl.text = _owner!),
                  ),
          ),
        ],
        rows: [
          ObsidianKv(l.t('bridge.withdrawFee'), '${target?.withdrawFee ?? '—'} USDT'),
          ObsidianKv(
            bridgeT(l, 'obs.bridge.receiveOn', {'chain': target?.name ?? '—'}),
            hasAmount ? '${formatUnitsPlain(_withdrawReceive, usdtTpixDecimals)} ${target?.usdtSymbol ?? 'USDT'}' : '—',
            strong: true,
          ),
          ObsidianKv(
            l.t('obs.bridge.limits'),
            bridgeT(l, 'obs.bridge.limitsTx', {
              'min': bridgeObsLimit(limits['min_withdraw']),
              'max': bridgeObsLimit(limits['max_withdraw_per_tx']),
              'symbol': 'USDT',
            }),
            quiet: true,
          ),
        ],
      ),
    ];
  }

  List<Widget> _obsWithdrawRest(LocaleProvider l) => [
    const SizedBox(height: 14),
    BridgeObsHow(
      title: l.t('bridge.howTitle'),
      steps: [l.t('bridge.howWithdraw1'), l.t('bridge.howWithdraw2'), l.t('bridge.howWithdraw3')],
    ),
  ];

  Widget _obsWithdrawCta(LocaleProvider l) => ObsidianButton(
    key: const ValueKey('usdt-withdraw-button'),
    label: bridgeT(l, 'bridge.burnUsdt', {'chain': _target?.name ?? ''}),
    onPressed: _canWithdraw ? _submitWithdraw : null,
    loading: bridgeBusy,
    loadingLabel: bridgeBusyLabel,
  );

  // ════════════════════════════════════════════════════════════
  //  ติดตามด้วย tx hash
  // ════════════════════════════════════════════════════════════

  Widget _obsTrack(UsdtBridgeInfo info, LocaleProvider l) {
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
          Text(l.t('bridge.trackHint'), style: st.ui(fontSize: 12.5, height: 1.5, color: ObsidianColors.textSec)),
          const SizedBox(height: 12),
          ObsidianSegmented<String>(
            options: [
              ObsidianSegmentOption(usdtDeposit, l.t('bridge.tabDeposit')),
              ObsidianSegmentOption(usdtWithdraw, l.t('bridge.trackWithdrawal')),
            ],
            value: _manualKind,
            height: 34,
            fontSize: 12.5,
            onChanged: (k) => _obsSet(() => _manualKind = k),
          ),
          if (_manualKind == usdtDeposit) ...[
            const SizedBox(height: 12),
            BridgeObsChainChoice(
              chains: [
                for (final ch in info.chains.where((ch) => ch.chainId != bridgeTpixChainId && ch.chainId > 0))
                  (id: ch.chainId, title: ch.name, subtitle: ch.usdtSymbol, enabled: true),
              ],
              selected: _manualChainId,
              onSelect: (id) => _obsSet(() => _manualChainId = id),
            ),
          ],
          const SizedBox(height: 12),
          ObsidianTextField(
            key: const ValueKey('usdt-manual-hash'),
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
  //  การ์ดติดตาม (ขั้นตอน 3 ขั้นจากสถานะจริง)
  // ════════════════════════════════════════════════════════════

  Widget _obsTrackedCard(TrackedTransfer e, UsdtBridgeInfo info, LocaleProvider l, {bool latest = false}) {
    final s = e.status;
    final badge = s == null ? null : stateBadge(s.state);
    final deposit = e.kind == usdtDeposit;
    final targetChain = e.targetChainId ?? s?.rows.where((r) => r.targetChainId != null).firstOrNull?.targetChainId;
    final amount = s?.amount ?? s?.rows.where((r) => r.amount != null).firstOrNull?.amount;
    String short(int? id) => id == null ? '—' : bridgeChainShortName(id, _chainName(id));
    final route = deposit ? '${short(e.chainId)} → TPIX' : 'TPIX → ${short(targetChain)}';
    final title = '${latest ? l.t('obs.bridge.latest') : route}${amount != null ? ' · $amount USDT' : ''}';
    final text = deposit
        ? BridgeObsStepText(
            send: bridgeT(l, 'obs.bridge.step.sendUsdt', {'chain': short(e.chainId)}),
            confirm: bridgeT(l, 'obs.bridge.step.confirm', {'chain': short(e.chainId)}),
            deliver: l.t('obs.bridge.step.mintUsdt'),
          )
        : BridgeObsStepText(
            send: l.t('obs.bridge.step.burnUsdt'),
            confirm: bridgeT(l, 'obs.bridge.step.confirm', {'chain': 'TPIX Chain'}),
            deliver: bridgeT(l, 'obs.bridge.step.payUsdt', {'chain': short(targetChain)}),
          );
    final delivered = s?.rows.where((r) => r.amount != null).map((r) => '${r.amount} USDT').firstOrNull;
    final st = ObsidianStyle.of(context);
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
          Wrap(
            spacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (!deposit)
                Text(
                  '${r.amount ?? '—'} USDT → ${bridgeShort(r.targetAddress, head: 8)}',
                  style: st.ui(fontSize: 12, color: ObsidianColors.textSoft),
                ),
              BridgeObsLink(label: deposit ? l.t('bridge.viewMint') : l.t('bridge.viewPayout'), url: r.url),
            ],
          ),
      ],
    );
  }
}
