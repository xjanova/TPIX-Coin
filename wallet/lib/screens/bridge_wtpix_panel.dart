/// TPIX Wallet — สะพาน TPIX (เชน 4289) ⇄ wTPIX (BEP-20 บน BSC)
///
/// TPIX → BSC: เรียก TPIXBridgeVault.lock() แนบ TPIX บนเชน 4289 (ไม่ใช่โอนตรง — โอนตรงต้องใช้แก๊สเกิน 21,000)
///             → เซิร์ฟเวอร์ mint wTPIX ให้ที่อยู่เดียวกันบน BSC
/// BSC → TPIX: เรียก wTPIX.burn(จำนวน) บน BSC (ไม่ต้อง approve) → คลังปล่อย TPIX ให้ที่อยู่เดียวกันบนเชน 4289
///
/// กระเป๋าในแอปใช้คีย์เดียวกันทุกเชน EVM → wTPIX บน BSC อยู่ที่ที่อยู่เดียวกับ TPIX ในกระเป๋านี้
///
/// Developed by Xman Studio
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/locale_provider.dart';
import '../core/theme.dart';
import '../core/themes/tokens.dart';
import '../providers/wallet_provider.dart';
import '../services/bridge_rules.dart';
import '../services/bridge_service.dart';
import '../services/bridge_tracker.dart';
import '../services/synth_service.dart';
import '../utils/units.dart';
import '../widgets/bridge_obsidian.dart';
import '../widgets/bridge_widgets.dart';
import '../widgets/obsidian/obsidian.dart';

// หน้าตาธีม Obsidian (ใช้สถานะ/ขั้นตอนส่งของแผงนี้ร่วมกัน)
part 'bridge_wtpix_obsidian.dart';

enum _Tab { toBsc, toTpix, track }

class WtpixBridgePanel extends StatefulWidget {
  const WtpixBridgePanel({super.key});

  @override
  State<WtpixBridgePanel> createState() => _WtpixBridgePanelState();
}

class _WtpixBridgePanelState extends State<WtpixBridgePanel> with BridgeSendFlow<WtpixBridgePanel> {
  final BridgeTracker _tracker = BridgeTracker(wtpix: true);

  WtpixBridgeInfo? _info;
  bool _loading = true;
  bool _loadFailed = false;
  bool _refreshing = false;
  int _loadSeq = 0;

  String? _owner;
  bool _started = false;
  _Tab _tab = _Tab.toBsc;

  // ── TPIX → wTPIX ──
  final _lockCtrl = TextEditingController();
  BigInt? _tpixBalance;
  int _tpixSeq = 0;
  bool _ackLock = false;

  // ── wTPIX → TPIX ──
  final _burnCtrl = TextEditingController();
  BigInt? _wtpixBalance;
  BigInt? _bnbBalance;
  int _bscSeq = 0;
  bool _ackBurn = false;

  // ── ติดตามด้วย tx hash ──
  String _manualDirection = wtpixToBsc;
  final _manualCtrl = TextEditingController();

  List<BridgeHistoryRow> _history = const [];
  int _historySeq = 0;

  @override
  void initState() {
    super.initState();
    _tracker.addListener(_onTracker);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _started = true;
      _owner = context.read<WalletProvider>().address;
      _tracker.setOwner(_owner);
      unawaited(_tracker.load());
      unawaited(_load());
    });
  }

  void _onTracker() {
    if (mounted) setState(() {});
  }

  /// setState สำหรับส่วนหน้าตาของธีม Obsidian (ไฟล์ part)
  void _obsSet(VoidCallback fn) => setState(fn);

  @override
  void dispose() {
    _tracker.removeListener(_onTracker);
    _tracker.dispose();
    _lockCtrl.dispose();
    _burnCtrl.dispose();
    _manualCtrl.dispose();
    super.dispose();
  }

  // ================================================================
  // โหลด
  // ================================================================

  Future<void> _load() async {
    final seq = ++_loadSeq;
    setState(() {
      if (_info != null) {
        _refreshing = true;
      } else {
        _loading = true;
        _loadFailed = false;
      }
    });
    try {
      final info = await BridgeService.fetchWtpixInfo();
      if (!mounted || seq != _loadSeq) return;
      setState(() {
        _info = info;
        _loading = false;
        _loadFailed = false;
        _refreshing = false;
      });
      unawaited(_refreshBalances());
      unawaited(_loadHistory());
      unawaited(_tracker.pollOnce());
    } catch (_) {
      if (!mounted || seq != _loadSeq) return;
      final hadData = _info != null;
      setState(() {
        _loading = false;
        _refreshing = false;
        _loadFailed = !hadData;
      });
      if (hadData) bridgeSnack(context, context.read<LocaleProvider>().t('bridge.refreshFailed'), error: true);
    }
  }

  /// ยอด TPIX บนเชน 4289 + wTPIX/BNB บน BSC — อ่านไม่ได้ = ไม่รู้ (ไม่ใช่ 0)
  Future<void> _refreshBalances() async {
    final owner = _owner;
    final info = _info;
    // ปิดอยู่ = ไม่มีฟอร์ม ไม่ต้องยิง RPC
    if (owner == null || info == null || !info.open) return;

    final tpixSeq = ++_tpixSeq;
    unawaited(() async {
      try {
        final b = await BridgeChains.rpc(bridgeTpixChainId).getBalance(owner);
        if (mounted && tpixSeq == _tpixSeq) setState(() => _tpixBalance = b);
      } catch (_) {}
    }());

    final bscSeq = ++_bscSeq;
    final rpc = BridgeChains.rpc(info.bscChainId);
    try {
      final results = await Future.wait([
        BridgeTx.tokenBalance(rpc, info.wtpixAddress!, owner),
        rpc.getBalance(owner),
      ]);
      if (!mounted || bscSeq != _bscSeq) return;
      setState(() {
        _wtpixBalance = results[0];
        _bnbBalance = results[1];
      });
    } catch (_) {}
  }

  Future<void> _loadHistory() async {
    final seq = ++_historySeq;
    final owner = _owner;
    if (owner == null) return;
    try {
      final rows = await BridgeService.fetchWtpixHistory(owner);
      if (!mounted || seq != _historySeq) return;
      setState(() => _history = rows);
    } catch (_) {}
  }

  /// สลับกระเป๋า — ยอด/ประวัติต้องตามคนใหม่ และต้องติ๊กยอมรับใหม่
  void _onOwnerChanged(String? next) {
    _owner = next;
    _tracker.setOwner(next);
    setState(() {
      _ackLock = false;
      _ackBurn = false;
      _tpixBalance = null;
      _wtpixBalance = null;
      _bnbBalance = null;
      _history = const [];
    });
    unawaited(_refreshBalances());
    unawaited(_loadHistory());
  }

  Future<void> _refreshAll() async {
    await _load();
    await _tracker.pollOnce();
  }

  // ================================================================
  // ค่าที่คำนวณ (BigInt wei ทั้งหมด)
  // ================================================================

  BigInt? get _lockWei => parseTpixAmount(_lockCtrl.text);
  BigInt? get _burnWei => parseTpixAmount(_burnCtrl.text);

  AmountCheck get _lockCheck =>
      _lockCtrl.text.trim().isEmpty ? AmountCheck.ok : checkWtpixAmount(_lockWei, wtpixToBsc, _info?.raw);
  AmountCheck get _burnCheck =>
      _burnCtrl.text.trim().isEmpty ? AmountCheck.ok : checkWtpixAmount(_burnWei, wtpixToTpix, _info?.raw);

  bool get _lockInsufficient {
    final w = _lockWei;
    final b = _tpixBalance;
    return w != null && b != null && w > b;
  }

  bool get _burnInsufficient {
    final w = _burnWei;
    final b = _wtpixBalance;
    return w != null && b != null && w > b;
  }

  bool get _canLock =>
      (_info?.open ?? false) &&
      _owner != null &&
      !bridgeBusy &&
      _ackLock &&
      _lockWei != null &&
      !_lockCheck.blocked &&
      !_lockInsufficient;

  bool get _canBurn =>
      (_info?.open ?? false) &&
      _owner != null &&
      !bridgeBusy &&
      _ackBurn &&
      _burnWei != null &&
      !_burnCheck.blocked &&
      !_burnInsufficient;

  String _fromLabel(String owner) {
    final name = context.read<WalletProvider>().activeWallet?.name;
    return name != null && name.isNotEmpty ? '$name · ${bridgeShort(owner, head: 8)}' : bridgeShort(owner, head: 8);
  }

  String _limitText(Object? v) => v is String && v.isNotEmpty ? v : '—';

  // ================================================================
  // ธุรกรรม
  // ================================================================

  Future<void> _submitLock() => bridgeGuard(() async {
        final l = context.read<LocaleProvider>();
        final info = _info;
        final owner = _owner;
        final wei = _lockWei;
        if (info == null || !info.open || owner == null || wei == null || !_ackLock) return;
        final check = checkWtpixAmount(wei, wtpixToBsc, info.raw);
        if (check.blocked) return;
        final vault = info.vaultAddress!;
        final fee = info.limits['lock_fee'];

        // lock() ไม่ใช่โอนตรง — จำลองบนเชนก่อน (หยุดอยู่/ต่ำกว่า minLock/เกิน maxLock = revert → บอกเลย)
        setBridgeBusyLabel(l.t('bridge.checking'));
        final plan = await BridgeTx.prepare(
          chainId: bridgeTpixChainId,
          from: owner,
          to: vault,
          data: BridgeTx.encodeLock(),
          value: wei,
        );
        if (!mounted) return;
        setBridgeBusyLabel(null);

        final ok = await showBridgeConfirmSheet(
          context,
          title: l.t('bridge.wtpix.confirmLockTitle'),
          rows: [
            (l.t('send.from'), _fromLabel(owner)),
            (l.t('bridge.network'), 'TPIX Chain ($bridgeTpixChainId)'),
            (l.t('bridge.wtpix.lockAmount'), '${formatTpix(wei)} TPIX'),
            (l.t('bridge.wtpix.fee'), '${_limitText(fee)} TPIX'),
            (l.t('bridge.youReceive'), '${formatTpix(receiveWei(wei, fee))} ${info.tokenSymbol} · ${info.bscName}'),
            (l.t('bridge.receiver'), owner),
            (l.t('bridge.wtpix.vaultContract'), vault),
            (l.t('bridge.networkFee'), l.t('bridge.gasFree')),
          ],
          notes: [
            if (check.warning != null) bridgeT(l, check.warning!, check.warningParams),
            l.t('bridge.wtpix.confirmLockNote'),
          ],
          confirmLabel: l.t('bridge.wtpix.confirmLock'),
          danger: true,
        );
        if (!ok || !mounted) return;

        // ประวัติแบบเดิมถูกอยู่แล้ว: "ส่ง X TPIX ให้คลัง" (ไม่ต้องแทนแถว)
        final hash = await bridgeAuthorizeAndSend(plan, owner: owner);
        if (hash == null) return;
        await _tracker.add(TrackedTransfer(kind: wtpixToBsc, chainId: bridgeTpixChainId, txHash: hash, owner: owner, sentHere: true));
        SynthService.playSendSuccess();
        if (!mounted) return;
        setState(() => _lockCtrl.clear());
        bridgeSnack(context, l.t('bridge.wtpix.sentNotice'));
        unawaited(_refreshBalances());
        unawaited(_loadHistory());
        unawaited(context.read<WalletProvider>().refreshBalance());
      });

  Future<void> _submitBurn() => bridgeGuard(() async {
        final l = context.read<LocaleProvider>();
        final info = _info;
        final owner = _owner;
        final wei = _burnWei;
        if (info == null || !info.open || owner == null || wei == null || !_ackBurn) return;
        final check = checkWtpixAmount(wei, wtpixToTpix, info.raw);
        if (check.blocked) return;
        final token = info.wtpixAddress!;
        final fee = info.limits['burn_fee'];

        setBridgeBusyLabel(l.t('bridge.checking'));
        final plan = await BridgeTx.prepare(
          chainId: info.bscChainId,
          from: owner,
          to: token,
          data: BridgeTx.encodeBurn(wei),
          spend: (token: token, amount: wei, decimals: tpixDecimals),
        );
        if (!mounted) return;
        setBridgeBusyLabel(null);

        final ok = await showBridgeConfirmSheet(
          context,
          title: l.t('bridge.wtpix.confirmBurnTitle'),
          rows: [
            (l.t('send.from'), _fromLabel(owner)),
            (l.t('bridge.network'), '${info.bscName} (${info.bscChainId})'),
            (l.t('bridge.wtpix.burnAmount'), '${formatTpix(wei)} ${info.tokenSymbol}'),
            (l.t('bridge.wtpix.fee'), '${_limitText(fee)} TPIX'),
            (l.t('bridge.youReceive'), '${formatTpix(receiveWei(wei, fee))} TPIX · TPIX Chain'),
            (l.t('bridge.receiver'), owner),
            (l.t('bridge.wtpix.tokenContract'), token),
            (l.t('bridge.networkFee'), '≈ ${BridgeTx.feeText(plan)} ${plan.nativeSymbol}'),
          ],
          notes: [
            if (check.warning != null) bridgeT(l, check.warning!, check.warningParams),
            l.t('bridge.wtpix.confirmBurnNote'),
          ],
          confirmLabel: l.t('bridge.wtpix.confirmBurn'),
          danger: true,
        );
        if (!ok || !mounted) return;

        final hash = await bridgeAuthorizeAndSend(
          plan,
          owner: owner,
          historyAs: (to: token, value: wei, tokenAddress: token, symbol: info.tokenSymbol, decimals: tpixDecimals),
        );
        if (hash == null) return;
        await _tracker.add(TrackedTransfer(kind: wtpixToTpix, chainId: info.bscChainId, txHash: hash, owner: owner, sentHere: true));
        SynthService.playSendSuccess();
        if (!mounted) return;
        setState(() => _burnCtrl.clear());
        bridgeSnack(context, l.t('bridge.wtpix.sentNotice'));
        unawaited(_refreshBalances());
        unawaited(_loadHistory());
      });

  Future<void> _addManual() async {
    final hash = _manualCtrl.text.trim();
    final owner = _owner;
    final info = _info;
    if (!isTxHash(hash) || owner == null || info == null) return;
    final chainId = _manualDirection == wtpixToBsc ? bridgeTpixChainId : BridgeChains.wtpixBscChainId;
    await _tracker.add(TrackedTransfer(kind: _manualDirection, chainId: chainId, txHash: hash, owner: owner));
    if (!mounted) return;
    setState(() => _manualCtrl.clear());
  }

  Future<void> _remove(TrackedTransfer entry) async {
    if (!await confirmRemoveTracked(context)) return;
    await _tracker.remove(entry);
  }

  // ================================================================
  // UI
  // ================================================================

  @override
  Widget build(BuildContext context) {
    final l = context.watch<LocaleProvider>();
    final wallet = context.watch<WalletProvider>();
    // สลับกระเป๋าขณะเปิดหน้านี้อยู่ → ล้างของใบเก่า โหลดของใบใหม่ (ทำหลังวาดเสร็จ ห้าม setState ใน build)
    if (_started && wallet.address?.toLowerCase() != _owner?.toLowerCase()) {
      final next = wallet.address;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || context.read<WalletProvider>().address != next) return;
        if (next?.toLowerCase() != _owner?.toLowerCase()) _onOwnerChanged(next);
      });
    }

    // ธีม Obsidian มีเลย์เอาต์ของตัวเอง — กฎ/สถานะ/ปุ่มส่งชุดเดียวกัน
    if (bridgeIsObsidian(context)) return _obsBuild(l);

    if (_loading && _info == null) {
      return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
    }
    if (_loadFailed || _info == null) {
      return BridgeLoadFailed(onRetry: _load);
    }
    final info = _info!;

    return RefreshIndicator(
      onRefresh: _refreshAll,
      color: AppTheme.primary,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(TpixGap.lg, TpixGap.sm, TpixGap.lg, TpixGap.huge),
        children: [
          if (_refreshing)
            const Padding(
              padding: EdgeInsets.only(bottom: TpixGap.sm),
              child: LinearProgressIndicator(minHeight: 2, color: AppTheme.primary),
            ),
          if (!info.open) ...[
            BridgeBanner(
              key: const ValueKey('wtpix-closed'),
              title: l.t('bridge.wtpix.notReady'),
              text: !info.enabled
                  ? (info.installed ? l.t('bridge.wtpix.pausedBody') : l.t('bridge.wtpix.notReadyBody'))
                  : l.t('bridge.misconfiguredBody'),
              color: AppTheme.warm,
              icon: Icons.construction_rounded,
            ),
            const SizedBox(height: TpixGap.lg),
          ] else ...[
            BridgeSegmented<_Tab>(
              options: [
                (_Tab.toBsc, l.t('bridge.wtpix.tabToBsc')),
                (_Tab.toTpix, l.t('bridge.wtpix.tabToTpix')),
                (_Tab.track, l.t('bridge.tabTrack')),
              ],
              value: _tab,
              onChanged: (t) => setState(() => _tab = t),
            ),
            const SizedBox(height: TpixGap.lg),
            if (_tab != _Tab.track) ...[
              _warnings(info, l),
              const SizedBox(height: TpixGap.lg),
            ],
            switch (_tab) {
              _Tab.toBsc => _lockSection(info, l),
              _Tab.toTpix => _burnSection(info, l),
              _Tab.track => _trackSection(info, l),
            },
            const SizedBox(height: TpixGap.lg),
          ],
          _trackedSection(info, l),
          const SizedBox(height: TpixGap.lg),
          _historySection(l),
        ],
      ),
    );
  }

  Widget _warnings(WtpixBridgeInfo info, LocaleProvider l) {
    // เพดานของ "สัญญาปลายทาง" ของทิศที่เลือก — ล็อก = ตัว mint บน BSC · เผา = คลังบนเชน TPIX
    final caps = _tab == _Tab.toTpix ? info.vault : info.minter;
    return BridgeWarningBox(
      title: l.t('bridge.warnTitle'),
      items: [
        l.t('bridge.wtpix.warnNoExchange'),
        l.t('bridge.wtpix.warnSameAddress'),
        if (_tab == _Tab.toBsc) l.t('bridge.wtpix.warnUseLock'),
        bridgeT(l, 'bridge.wtpix.warnCaps', {
          'perTx': _limitText(caps['max_per_tx']),
          'daily': _limitText(caps['daily_cap']),
        }),
      ],
    );
  }

  Widget _amountHeader(String label, String? balanceText, VoidCallback? onMax) {
    final c = AppColors.of(context);
    return Row(
      children: [
        Expanded(child: Text(label, style: TextStyle(fontSize: 12, color: c.textMuted))),
        if (balanceText != null)
          InkWell(
            onTap: onMax,
            child: Text(balanceText, style: const TextStyle(fontSize: 12, color: AppTheme.primary)),
          ),
      ],
    );
  }

  Widget _lockSection(WtpixBridgeInfo info, LocaleProvider l) {
    final c = AppColors.of(context);
    final check = _lockCheck;
    final wei = _lockWei;
    final limits = info.limits;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BridgeCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('${l.t('bridge.wtpix.from')}: TPIX Chain → ${l.t('bridge.wtpix.to')}: ${info.bscName}',
                  style: TextStyle(fontSize: 12.5, color: c.textSec, fontWeight: FontWeight.w600)),
              const SizedBox(height: TpixGap.md),
              _amountHeader(
                l.t('bridge.wtpix.amountTpix'),
                _tpixBalance == null ? null : '${l.t('bridge.balance')}: ${formatTpix(_tpixBalance)} TPIX · ${l.t('bridge.max')}',
                bridgeBusy || _tpixBalance == null ? null : () => setState(() => _lockCtrl.text = formatTpix(_tpixBalance)),
              ),
              const SizedBox(height: TpixGap.xs),
              BridgeInput(
                key: const ValueKey('wtpix-lock-amount'),
                controller: _lockCtrl,
                hint: '0.0',
                amount: true,
                enabled: !bridgeBusy,
                onChanged: (_) => setState(() {}),
                errorText: check.error != null
                    ? bridgeT(l, check.error!, check.params)
                    : _lockInsufficient
                        ? l.t('bridge.errInsufficient')
                        : null,
                warningText: check.warning != null ? bridgeT(l, check.warning!, check.warningParams) : null,
              ),
              const SizedBox(height: TpixGap.md),
              BridgeKv(l.t('bridge.wtpix.fee'), '${_limitText(limits['lock_fee'])} TPIX'),
              BridgeKv(
                l.t('bridge.youReceive'),
                wei != null && !check.blocked
                    ? '${formatTpix(receiveWei(wei, limits['lock_fee']))} ${info.tokenSymbol} · ${info.bscName}'
                    : '—',
                valueColor: AppTheme.success,
              ),
              BridgeKv(l.t('bridge.eta'), bridgeT(l, 'bridge.etaMinutes', {'minutes': '${info.bscEtaMinutes}'})),
              BridgeKv('${l.t('bridge.minDeposit')} / ${l.t('bridge.maxPerTx')}',
                  '${_limitText(limits['min_lock'])} / ${_limitText(limits['max_lock_per_tx'])} TPIX'),
              BridgeKv(l.t('bridge.dailyPerAddress'), '${_limitText(limits['max_lock_per_address_daily'])} TPIX'),
              BridgeKv(l.t('bridge.wtpix.remainingToday'), '${_limitText(info.minter['remaining_today'])} ${info.tokenSymbol}'),
              BridgeKv(l.t('bridge.networkFee'), l.t('bridge.gasFree'), valueColor: AppTheme.success),
              const SizedBox(height: TpixGap.sm),
              BridgeAckTile(
                key: const ValueKey('wtpix-ack-lock'),
                value: _ackLock,
                onChanged: bridgeBusy ? null : (v) => setState(() => _ackLock = v),
                text: l.t('bridge.wtpix.ackLock'),
              ),
              const SizedBox(height: TpixGap.md),
              BridgePrimaryButton(
                key: const ValueKey('wtpix-lock-button'),
                label: bridgeT(l, 'bridge.wtpix.lockButton', {'chain': info.bscName}),
                onPressed: _canLock ? _submitLock : null,
                loading: bridgeBusy,
                loadingLabel: bridgeBusyLabel,
              ),
            ],
          ),
        ),
        const SizedBox(height: TpixGap.lg),
        BridgeHowItWorks(title: l.t('bridge.howTitle'), steps: [
          l.t('bridge.wtpix.howToBsc1'),
          bridgeT(l, 'bridge.wtpix.howToBsc2', {'chain': info.bscName}),
          l.t('bridge.wtpix.howToBsc3'),
        ]),
      ],
    );
  }

  Widget _burnSection(WtpixBridgeInfo info, LocaleProvider l) {
    final c = AppColors.of(context);
    final check = _burnCheck;
    final wei = _burnWei;
    final limits = info.limits;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BridgeCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('${l.t('bridge.wtpix.from')}: ${info.bscName} → ${l.t('bridge.wtpix.to')}: TPIX Chain',
                  style: TextStyle(fontSize: 12.5, color: c.textSec, fontWeight: FontWeight.w600)),
              const SizedBox(height: TpixGap.md),
              _amountHeader(
                l.t('bridge.wtpix.amountWtpix'),
                _wtpixBalance == null
                    ? null
                    : '${l.t('bridge.balance')}: ${formatTpix(_wtpixBalance)} ${info.tokenSymbol} · ${l.t('bridge.max')}',
                bridgeBusy || _wtpixBalance == null ? null : () => setState(() => _burnCtrl.text = formatTpix(_wtpixBalance)),
              ),
              const SizedBox(height: TpixGap.xs),
              BridgeInput(
                key: const ValueKey('wtpix-burn-amount'),
                controller: _burnCtrl,
                hint: '0.0',
                amount: true,
                enabled: !bridgeBusy,
                onChanged: (_) => setState(() {}),
                errorText: check.error != null
                    ? bridgeT(l, check.error!, check.params)
                    : _burnInsufficient
                        ? l.t('bridge.errInsufficient')
                        : null,
                warningText: check.warning != null ? bridgeT(l, check.warning!, check.warningParams) : null,
              ),
              const SizedBox(height: TpixGap.md),
              BridgeKv(l.t('bridge.wtpix.fee'), '${_limitText(limits['burn_fee'])} TPIX'),
              BridgeKv(
                l.t('bridge.youReceive'),
                wei != null && !check.blocked ? '${formatTpix(receiveWei(wei, limits['burn_fee']))} TPIX · TPIX Chain' : '—',
                valueColor: AppTheme.success,
              ),
              BridgeKv(l.t('bridge.eta'), bridgeT(l, 'bridge.etaMinutes', {'minutes': '${info.tpixEtaMinutes}'})),
              BridgeKv('${l.t('bridge.minDeposit')} / ${l.t('bridge.maxPerTx')}',
                  '${_limitText(limits['min_burn'])} / ${_limitText(limits['max_burn_per_tx'])} ${info.tokenSymbol}'),
              BridgeKv(l.t('bridge.dailyPerAddress'), '${_limitText(limits['max_burn_per_address_daily'])} ${info.tokenSymbol}'),
              BridgeKv(l.t('bridge.wtpix.remainingToday'), '${_limitText(info.vault['remaining_today'])} TPIX'),
              BridgeKv(
                bridgeT(l, 'bridge.gasBalance', {'symbol': 'BNB'}),
                _bnbBalance == null ? '—' : '${formatTpix(_bnbBalance)} BNB',
              ),
              const SizedBox(height: TpixGap.sm),
              BridgeAckTile(
                key: const ValueKey('wtpix-ack-burn'),
                value: _ackBurn,
                onChanged: bridgeBusy ? null : (v) => setState(() => _ackBurn = v),
                text: l.t('bridge.wtpix.ackBurn'),
              ),
              const SizedBox(height: TpixGap.md),
              BridgePrimaryButton(
                key: const ValueKey('wtpix-burn-button'),
                label: l.t('bridge.wtpix.burnButton'),
                onPressed: _canBurn ? _submitBurn : null,
                loading: bridgeBusy,
                loadingLabel: bridgeBusyLabel,
              ),
            ],
          ),
        ),
        const SizedBox(height: TpixGap.lg),
        BridgeHowItWorks(title: l.t('bridge.howTitle'), steps: [
          bridgeT(l, 'bridge.wtpix.howToTpix1', {'chain': info.bscName}),
          l.t('bridge.wtpix.howToTpix2'),
          l.t('bridge.wtpix.howToTpix3'),
        ]),
      ],
    );
  }

  Widget _trackSection(WtpixBridgeInfo info, LocaleProvider l) {
    final c = AppColors.of(context);
    final valid = isTxHash(_manualCtrl.text);
    return BridgeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l.t('bridge.trackTitle'), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.text)),
          const SizedBox(height: TpixGap.xs),
          Text(l.t('bridge.wtpix.trackHint'), style: TextStyle(fontSize: 12, color: c.textSec)),
          const SizedBox(height: TpixGap.md),
          BridgeSegmented<String>(
            options: [
              (wtpixToBsc, l.t('bridge.wtpix.trackLock')),
              (wtpixToTpix, bridgeT(l, 'bridge.wtpix.trackBurn', {'chain': info.bscName})),
            ],
            value: _manualDirection,
            onChanged: (d) => setState(() => _manualDirection = d),
          ),
          const SizedBox(height: TpixGap.md),
          BridgeInput(
            key: const ValueKey('wtpix-manual-hash'),
            controller: _manualCtrl,
            hint: l.t('bridge.trackTxHash'),
            mono: true,
            onChanged: (_) => setState(() {}),
            errorText: _manualCtrl.text.trim().isNotEmpty && !valid ? l.t('bridge.errHashInvalid') : null,
          ),
          const SizedBox(height: TpixGap.md),
          BridgePrimaryButton(label: l.t('bridge.trackButton'), onPressed: valid ? _addManual : null),
        ],
      ),
    );
  }

  Widget _trackedSection(WtpixBridgeInfo info, LocaleProvider l) {
    final c = AppColors.of(context);
    final entries = _tracker.entries;
    return BridgeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BridgeSectionTitle(l.t('bridge.tracked')),
          if (entries.isEmpty)
            Text(l.t('bridge.noTracked'), style: TextStyle(fontSize: 12, color: c.textMuted))
          else
            for (final e in entries) _trackedTile(e, info, l),
        ],
      ),
    );
  }

  Widget _trackedTile(TrackedTransfer e, WtpixBridgeInfo info, LocaleProvider l) {
    final c = AppColors.of(context);
    final s = e.status;
    final badge = s == null ? null : wtpixStateBadge(s.state);
    final toBsc = e.kind == wtpixToBsc;
    return BridgeTrackedTile(
      key: ValueKey('tracked-${e.key}'),
      title: toBsc ? 'TPIX → ${info.tokenSymbol} (${info.bscName})' : '${info.tokenSymbol} (${info.bscName}) → TPIX',
      txHash: e.txHash,
      explorerUrl: explorerTx(info.explorerFor(e.chainId), e.txHash),
      badge: badge,
      badgeLabel: badge == null ? null : bridgeT(l, badge.labelKey, const {}, 'bridge.state.other'),
      onRemove: () => _remove(e),
      details: [
        if (s != null && s.state == 'confirming')
          Padding(
            padding: const EdgeInsets.only(top: TpixGap.xs),
            child: Text(
              '${s.isFinal ? l.t('bridge.wtpix.finalSoon') : bridgeT(l, 'bridge.confirmations', {'n': '${s.confirmations ?? 0}'})}'
              '${s.amount != null ? ' · ${s.amount}' : ''}',
              style: TextStyle(fontSize: 12, color: c.textSec),
            ),
          ),
        for (final r in s?.rows ?? const <BridgeStatusRow>[])
          Padding(
            padding: const EdgeInsets.only(top: TpixGap.xs),
            child: Wrap(
              spacing: TpixGap.md,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  '${r.amount ?? '—'} ${(r.direction ?? e.kind) == wtpixToBsc ? info.tokenSymbol : 'TPIX'}',
                  style: TextStyle(fontSize: 12, color: c.text, fontWeight: FontWeight.w600),
                ),
                BridgeLink(
                  label: (r.direction ?? e.kind) == wtpixToBsc
                      ? bridgeT(l, 'bridge.wtpix.viewMint', {'chain': info.bscName})
                      : l.t('bridge.wtpix.viewRelease'),
                  url: r.url,
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _historySection(LocaleProvider l) {
    final c = AppColors.of(context);
    return BridgeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BridgeSectionTitle(l.t('bridge.history')),
          if (_history.isEmpty)
            Text(l.t('bridge.historyEmpty'), style: TextStyle(fontSize: 12, color: c.textMuted))
          else
            for (final r in _history)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: TpixGap.xs),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${r.kind == wtpixToBsc ? 'TPIX → wTPIX' : 'wTPIX → TPIX'} · ${r.amount ?? '—'}',
                        style: TextStyle(fontSize: 12, color: c.text),
                      ),
                    ),
                    const SizedBox(width: TpixGap.sm),
                    BridgeStateChip(
                      label: bridgeT(l, wtpixStateBadge(r.state).labelKey, const {}, 'bridge.state.other'),
                      tone: wtpixStateBadge(r.state).tone,
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}
