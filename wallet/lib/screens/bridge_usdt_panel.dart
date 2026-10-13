/// TPIX Wallet — สะพาน USDT หลายเชน ⇄ USDT บน TPIX Chain (USDT_TPIX)
///
/// ฝาก: transfer(vault, จำนวน) ของ USDT จริงบนเชนต้นทาง → ตัวสแกนบนเซิร์ฟเวอร์เห็นเมื่อบล็อก final
///      → mint USDT_TPIX ให้ที่อยู่เดียวกันบนเชน 4289
/// ถอน: USDT_TPIX.bridgeBurn(จำนวน, เชนปลายทาง, ที่อยู่) บนเชน 4289 → จ่าย USDT จริงบนเชนปลายทาง
///
/// แอปไม่ได้ "แจ้ง" เซิร์ฟเวอร์ — แค่ถามสถานะด้วย tx hash · ปิดหน้ากลางทางก็ไม่เสียอะไร
/// ทุกปุ่มส่ง: ตรวจบนเชนก่อน (BridgeTx.prepare) → กล่องยืนยันโชว์ครบทุกหลัก → PIN → เซ็น → จด hash
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
part 'bridge_usdt_obsidian.dart';

enum _Tab { deposit, withdraw, track }

class UsdtBridgePanel extends StatefulWidget {
  const UsdtBridgePanel({super.key});

  @override
  State<UsdtBridgePanel> createState() => _UsdtBridgePanelState();
}

class _UsdtBridgePanelState extends State<UsdtBridgePanel> with BridgeSendFlow<UsdtBridgePanel> {
  final BridgeTracker _tracker = BridgeTracker(wtpix: false);

  UsdtBridgeInfo? _info;
  bool _loading = true;
  bool _loadFailed = false;
  bool _refreshing = false;
  int _loadSeq = 0;

  /// กระเป๋าที่ข้อมูลบนจอเป็นของมัน — เปลี่ยนเมื่อไหร่ต้องล้างของใบเก่า
  String? _owner;
  bool _started = false;
  _Tab _tab = _Tab.deposit;

  // ── ฝาก ──
  int? _sourceChainId;
  final _depositCtrl = TextEditingController();
  BigInt? _sourceBalance; // หน่วยของเหรียญต้นทาง · null = ยังไม่รู้
  int _sourceSeq = 0;
  // ต้องติ๊กยอมรับใหม่ทุกครั้งที่เปิดหน้า/สลับกระเป๋า — โอนจากกระดานเทรดคือความผิดพลาดที่เรียกเงินคืนไม่ได้
  bool _ackOwnWallet = false;

  // ── ถอน ──
  int? _targetChainId;
  final _withdrawCtrl = TextEditingController();
  final _targetCtrl = TextEditingController();
  BigInt? _tpixUsdtBalance; // 6 ทศนิยม · null = ยังไม่รู้
  int _tpixSeq = 0;

  // ── ติดตามด้วย tx hash ──
  String _manualKind = usdtDeposit;
  int? _manualChainId;
  final _manualCtrl = TextEditingController();

  // ── ประวัติ ──
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
      if (_owner != null) _targetCtrl.text = _owner!;
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
    _depositCtrl.dispose();
    _withdrawCtrl.dispose();
    _targetCtrl.dispose();
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
        _refreshing = true; // มีข้อมูลเดิมอยู่ — ไม่เอาสปินเนอร์เต็มจอมาบัง
      } else {
        _loading = true;
        _loadFailed = false;
      }
    });
    try {
      final info = await BridgeService.fetchUsdtInfo();
      if (!mounted || seq != _loadSeq) return;
      final sourceBefore = _sourceChainId;
      setState(() {
        _info = info;
        _loading = false;
        _loadFailed = false;
        _refreshing = false;
        _sourceChainId = _pick(info, _sourceChainId, (c) => c.depositable);
        _targetChainId = _pick(info, _targetChainId, (c) => c.withdrawable);
        _manualChainId = _pick(info, _manualChainId, (c) => c.chainId > 0 && c.chainId != bridgeTpixChainId);
      });
      unawaited(_refreshSourceBalance(reset: sourceBefore != _sourceChainId));
      unawaited(_refreshTpixBalance());
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

  /// เลือกเชนเดิมถ้ายังใช้ได้ ไม่งั้นตัวแรกที่ใช้ได้
  int? _pick(UsdtBridgeInfo info, int? current, bool Function(UsdtBridgeChain) ok) {
    final usable = info.chains.where(ok).toList();
    if (current != null && usable.any((c) => c.chainId == current)) return current;
    return usable.isEmpty ? null : usable.first.chainId;
  }

  Future<void> _refreshSourceBalance({bool reset = false}) async {
    final seq = ++_sourceSeq;
    final info = _info;
    final owner = _owner;
    final chain = info?.chain(_sourceChainId ?? -1);
    if (reset && mounted) setState(() => _sourceBalance = null);
    if (owner == null || chain == null || !chain.depositable || !(info?.open ?? false)) return;
    try {
      final balance = await BridgeTx.tokenBalance(BridgeChains.rpc(chain.chainId), chain.usdtAddress!, owner);
      if (!mounted || seq != _sourceSeq) return;
      setState(() => _sourceBalance = balance);
    } catch (_) {
      // อ่านไม่ได้ ≠ ศูนย์ — ไม่บล็อกปุ่ม ด่านก่อนส่งอ่านยอดใหม่อีกรอบ
    }
  }

  Future<void> _refreshTpixBalance() async {
    final seq = ++_tpixSeq;
    final token = _info?.usdtTpix;
    final owner = _owner;
    if (owner == null || token == null || !(_info?.open ?? false)) return;
    try {
      final balance = await BridgeTx.tokenBalance(BridgeChains.rpc(bridgeTpixChainId), token, owner);
      if (!mounted || seq != _tpixSeq) return;
      setState(() => _tpixUsdtBalance = balance);
    } catch (_) {}
  }

  Future<void> _loadHistory() async {
    final seq = ++_historySeq;
    final owner = _owner;
    if (owner == null) return;
    try {
      final rows = await BridgeService.fetchUsdtHistory(owner);
      if (!mounted || seq != _historySeq) return;
      setState(() => _history = rows);
    } catch (_) {
      // ประวัติเป็นของเสริม — ไม่โชว์ error
    }
  }

  /// สลับกระเป๋าขณะเปิดหน้านี้ — ล้างยอด/ประวัติ/การติ๊กยอมรับของใบเก่า
  void _onOwnerChanged(String? next) {
    final prev = _owner;
    _owner = next;
    _tracker.setOwner(next);
    setState(() {
      _ackOwnWallet = false;
      _sourceBalance = null;
      _tpixUsdtBalance = null;
      _history = const [];
      final target = _targetCtrl.text.trim().toLowerCase();
      if (target.isEmpty || target == prev?.toLowerCase()) _targetCtrl.text = next ?? '';
    });
    unawaited(_refreshSourceBalance());
    unawaited(_refreshTpixBalance());
    unawaited(_loadHistory());
  }

  Future<void> _refreshAll() async {
    await _load();
    await _tracker.pollOnce();
  }

  // ================================================================
  // ค่าที่คำนวณจากช่องกรอก (BigInt ทั้งหมด)
  // ================================================================

  UsdtBridgeChain? get _source => _info?.chain(_sourceChainId ?? -1);
  UsdtBridgeChain? get _target => _info?.chain(_targetChainId ?? -1);

  BigInt? get _depositUnits {
    final s = _source;
    return s == null ? null : parseAmountToUnits(_depositCtrl.text, s.usdtDecimals);
  }

  BigInt? get _depositUnits6 {
    final u = _depositUnits;
    final s = _source;
    return u == null || s == null ? null : toUsdt6(u, s.usdtDecimals);
  }

  AmountCheck get _depositCheck => _depositCtrl.text.trim().isEmpty
      ? AmountCheck.ok
      : checkDepositAmount(_depositUnits6, _info?.limits);

  bool get _depositInsufficient {
    final u = _depositUnits;
    final b = _sourceBalance;
    return u != null && b != null && u > b;
  }

  bool get _canDeposit =>
      (_info?.open ?? false) &&
      (_source?.depositable ?? false) &&
      _owner != null &&
      !bridgeBusy &&
      _ackOwnWallet &&
      _depositUnits != null &&
      !_depositCheck.blocked &&
      !_depositInsufficient;

  BigInt? get _withdrawUnits => parseAmountToUnits(_withdrawCtrl.text, usdtTpixDecimals);

  AmountCheck get _withdrawCheck => _withdrawCtrl.text.trim().isEmpty
      ? AmountCheck.ok
      : checkWithdrawAmount(_withdrawUnits,
          fee: _target?.withdrawFee, limits: _info?.limits, balance: _tpixUsdtBalance);

  String? get _addressError =>
      _targetCtrl.text.trim().isNotEmpty && !isValidEvmAddress(_targetCtrl.text) ? 'bridge.errAddressInvalid' : null;

  BigInt get _withdrawReceive {
    final u = _withdrawUnits;
    final t = _target;
    return u == null || t == null ? BigInt.zero : withdrawReceiveUnits(u, t.withdrawFee);
  }

  bool get _canWithdraw =>
      (_info?.open ?? false) &&
      (_target?.withdrawable ?? false) &&
      _owner != null &&
      !bridgeBusy &&
      _withdrawCtrl.text.trim().isNotEmpty &&
      !_withdrawCheck.blocked &&
      _targetCtrl.text.trim().isNotEmpty &&
      _addressError == null;

  String _fromLabel(String owner) {
    final name = context.read<WalletProvider>().activeWallet?.name;
    return name != null && name.isNotEmpty ? '$name · ${bridgeShort(owner, head: 8)}' : bridgeShort(owner, head: 8);
  }

  String _chainName(int? chainId) {
    if (chainId == null) return '—';
    return _info?.chainName(chainId) ?? BridgeChains.of(chainId)?.name ?? '#$chainId';
  }

  // ================================================================
  // ธุรกรรม
  // ================================================================

  Future<void> _submitDeposit() => bridgeGuard(() async {
        final l = context.read<LocaleProvider>();
        final info = _info;
        final owner = _owner;
        final chain = _source;
        final units = _depositUnits;
        if (info == null || !info.open || owner == null || chain == null || !chain.depositable) return;
        if (units == null || !_ackOwnWallet) return;
        final check = checkDepositAmount(toUsdt6(units, chain.usdtDecimals), info.limits);
        if (check.blocked) return;
        final vault = info.vaultAddress!;
        final token = chain.usdtAddress!;

        // ตรวจบนเชนก่อน (chain id · ทศนิยมจริง · ยอด · จำลองธุรกรรม · ค่าแก๊ส) — ยังไม่ถาม PIN
        setBridgeBusyLabel(l.t('bridge.checking'));
        final plan = await BridgeTx.prepare(
          chainId: chain.chainId,
          from: owner,
          to: token,
          data: BridgeTx.encodeTransfer(vault, units),
          spend: (token: token, amount: units, decimals: chain.usdtDecimals),
        );
        if (!mounted) return;
        setBridgeBusyLabel(null);

        final amountText = formatUnitsPlain(units, chain.usdtDecimals);
        final ok = await showBridgeConfirmSheet(
          context,
          title: l.t('bridge.confirmDepositTitle'),
          rows: [
            (l.t('send.from'), _fromLabel(owner)),
            (l.t('bridge.network'), '${chain.name} (${chain.chainId})'),
            (l.t('bridge.amount'), '$amountText ${chain.usdtSymbol}'),
            (l.t('bridge.usdtContract'), token),
            (l.t('bridge.vaultAddress'), vault),
            (l.t('bridge.youReceive'), '${formatUnitsPlain(toUsdt6(units, chain.usdtDecimals), usdtTpixDecimals)} USDT · TPIX Chain'),
            (l.t('bridge.receiver'), owner),
            (l.t('bridge.networkFee'), '≈ ${BridgeTx.feeText(plan)} ${plan.nativeSymbol}'),
          ],
          notes: [
            if (check.warning != null) bridgeT(l, check.warning!, check.warningParams),
            l.t('bridge.confirmDepositNote'),
          ],
          confirmLabel: l.t('bridge.sendUsdt'),
        );
        if (!ok || !mounted) return;

        final hash = await bridgeAuthorizeAndSend(
          plan,
          owner: owner,
          historyAs: (to: vault, value: units, tokenAddress: token, symbol: chain.usdtSymbol, decimals: chain.usdtDecimals),
        );
        if (hash == null) return;
        // จดทันทีที่ได้ hash (แม้หน้านี้ถูกปิดไปแล้ว) — เปิดใหม่ก็ติดตามต่อได้
        await _tracker.add(TrackedTransfer(kind: usdtDeposit, chainId: chain.chainId, txHash: hash, owner: owner, sentHere: true));
        SynthService.playSendSuccess();
        if (!mounted) return;
        setState(() => _depositCtrl.clear());
        bridgeSnack(context, l.t('bridge.sentNotice'));
        unawaited(_refreshSourceBalance());
        unawaited(_loadHistory());
      });

  Future<void> _submitWithdraw() => bridgeGuard(() async {
        final l = context.read<LocaleProvider>();
        final info = _info;
        final owner = _owner;
        final chain = _target;
        final units = _withdrawUnits;
        final targetAddress = _targetCtrl.text.trim();
        if (info == null || !info.open || owner == null || chain == null || !chain.withdrawable) return;
        if (units == null || !isValidEvmAddress(targetAddress)) return;
        final check = checkWithdrawAmount(units, fee: chain.withdrawFee, limits: info.limits, balance: _tpixUsdtBalance);
        if (check.blocked) return;
        final token = info.usdtTpix!;
        final receive = withdrawReceiveUnits(units, chain.withdrawFee);

        setBridgeBusyLabel(l.t('bridge.checking'));
        final plan = await BridgeTx.prepare(
          chainId: bridgeTpixChainId,
          from: owner,
          to: token,
          data: BridgeTx.encodeBridgeBurn(units, chain.chainId, targetAddress),
          spend: (token: token, amount: units, decimals: usdtTpixDecimals),
        );
        if (!mounted) return;
        setBridgeBusyLabel(null);

        final maxText = info.limits['max_withdraw_per_tx'];
        final max = maxText is String ? usdtToUnits(maxText) : BigInt.zero;
        final ok = await showBridgeConfirmSheet(
          context,
          title: l.t('bridge.confirmWithdrawTitle'),
          rows: [
            (l.t('send.from'), _fromLabel(owner)),
            (l.t('bridge.network'), 'TPIX Chain ($bridgeTpixChainId)'),
            (l.t('bridge.burnAmount'), '${formatUnitsPlain(units, usdtTpixDecimals)} USDT'),
            (l.t('bridge.withdrawFee'), '${chain.withdrawFee} USDT'),
            (l.t('bridge.youReceive'), '${formatUnitsPlain(receive, usdtTpixDecimals)} ${chain.usdtSymbol}'),
            (l.t('bridge.targetChain'), '${chain.name} (${chain.chainId})'),
            (l.t('bridge.receiver'), targetAddress),
            (l.t('bridge.networkFee'), l.t('bridge.gasFree')),
          ],
          notes: [
            l.t('bridge.confirmWithdrawNote'),
            if (targetAddress.toLowerCase() != owner.toLowerCase()) l.t('bridge.notYourAddress'),
            if (max > BigInt.zero && units > max) bridgeT(l, 'bridge.warnAboveMaxWithdraw', {'max': maxText as String}),
          ],
          confirmLabel: bridgeT(l, 'bridge.burnUsdt', {'chain': chain.name}),
          danger: true,
        );
        if (!ok || !mounted) return;

        final hash = await bridgeAuthorizeAndSend(
          plan,
          owner: owner,
          historyAs: (to: targetAddress, value: units, tokenAddress: token, symbol: 'USDT', decimals: usdtTpixDecimals),
        );
        if (hash == null) return;
        await _tracker.add(TrackedTransfer(
          kind: usdtWithdraw,
          chainId: bridgeTpixChainId,
          txHash: hash,
          targetChainId: chain.chainId,
          owner: owner,
          sentHere: true,
        ));
        SynthService.playSendSuccess();
        if (!mounted) return;
        setState(() => _withdrawCtrl.clear());
        bridgeSnack(context, l.t('bridge.sentNotice'));
        unawaited(_refreshTpixBalance());
        unawaited(_loadHistory());
      });

  Future<void> _addManual() async {
    final hash = _manualCtrl.text.trim();
    final owner = _owner;
    if (!isTxHash(hash) || owner == null) return;
    final chainId = _manualKind == usdtDeposit ? _manualChainId : bridgeTpixChainId;
    if (chainId == null) return;
    await _tracker.add(TrackedTransfer(kind: _manualKind, chainId: chainId, txHash: hash, owner: owner));
    if (!mounted) return;
    setState(() => _manualCtrl.clear());
  }

  Future<void> _remove(TrackedTransfer entry) async {
    if (!await confirmRemoveTracked(context)) return;
    await _tracker.remove(entry);
  }

  /// ยอดสูงสุดที่กรอกได้ (ตัดเหลือ 6 ทศนิยม — เศษที่เกินอยู่ในกระเป๋าต่อ ไม่กลายเป็นฝุ่นใน vault)
  void _fillMaxDeposit() {
    final b = _sourceBalance;
    final s = _source;
    if (b == null || s == null) return;
    final units6 = toUsdt6(b, s.usdtDecimals);
    setState(() => _depositCtrl.text = formatUnitsPlain(units6, usdtTpixDecimals));
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
            // ยังไม่เปิด / หยุดชั่วคราว / ตั้งค่าไม่ครบ — บอกตรงๆ ดีกว่าโชว์ปุ่มที่กดแล้วเงินไปค้าง
            BridgeBanner(
              key: const ValueKey('usdt-closed'),
              title: l.t('bridge.notReady'),
              text: !info.enabled
                  ? (info.installed ? l.t('bridge.pausedBody') : l.t('bridge.notReadyBody'))
                  : l.t('bridge.misconfiguredBody'),
              color: AppTheme.warm,
              icon: Icons.construction_rounded,
            ),
            const SizedBox(height: TpixGap.lg),
          ] else ...[
            BridgeSegmented<_Tab>(
              options: [
                (_Tab.deposit, l.t('bridge.tabDeposit')),
                (_Tab.withdraw, l.t('bridge.tabWithdraw')),
                (_Tab.track, l.t('bridge.tabTrack')),
              ],
              value: _tab,
              onChanged: (t) => setState(() => _tab = t),
            ),
            const SizedBox(height: TpixGap.lg),
            switch (_tab) {
              _Tab.deposit => _depositSection(info, l),
              _Tab.withdraw => _withdrawSection(info, l),
              _Tab.track => _trackSection(info, l),
            },
            const SizedBox(height: TpixGap.lg),
          ],
          _trackedSection(info, l),
          const SizedBox(height: TpixGap.lg),
          _historySection(info, l),
        ],
      ),
    );
  }

  Widget _depositSection(UsdtBridgeInfo info, LocaleProvider l) {
    final c = AppColors.of(context);
    final source = _source;
    final check = _depositCheck;
    final units6 = _depositUnits6;
    final limits = info.limits;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BridgeWarningBox(
          title: l.t('bridge.warnTitle'),
          items: [l.t('bridge.warnNoExchange'), l.t('bridge.warnOwnWallet'), l.t('bridge.warnSameAddress'), l.t('bridge.warnUsdtOnly')],
        ),
        const SizedBox(height: TpixGap.lg),
        BridgeCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l.t('bridge.sourceChain'), style: TextStyle(fontSize: 12, color: c.textMuted)),
              const SizedBox(height: TpixGap.sm),
              BridgeChainPicker(
                chains: [
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
                ],
                selected: _sourceChainId,
                onSelect: bridgeBusy
                    ? null
                    : (id) {
                        setState(() {
                          _sourceChainId = id;
                          _depositCtrl.clear();
                        });
                        unawaited(_refreshSourceBalance(reset: true));
                      },
              ),
              if (source != null && source.depositable) ...[
                const SizedBox(height: TpixGap.lg),
                BridgeAddressLine(label: '${l.t('bridge.vaultAddress')} (${source.name})', address: info.vaultAddress!),
                const SizedBox(height: TpixGap.sm),
                BridgeAddressLine(
                  label: bridgeT(l, 'bridge.usdtContractDecimals', {'decimals': '${source.usdtDecimals}'}),
                  address: source.usdtAddress!,
                ),
                BridgeLink(
                  label: l.t('bridge.viewContract'),
                  url: source.explorer == null ? null : '${source.explorer}/token/${source.usdtAddress}',
                ),
                const SizedBox(height: TpixGap.lg),
                Row(
                  children: [
                    Expanded(child: Text(l.t('bridge.amount'), style: TextStyle(fontSize: 12, color: c.textMuted))),
                    if (_sourceBalance != null)
                      InkWell(
                        onTap: bridgeBusy ? null : _fillMaxDeposit,
                        child: Text(
                          '${l.t('bridge.balance')}: ${formatUnitsPlain(_sourceBalance!, source.usdtDecimals)} · ${l.t('bridge.max')}',
                          style: const TextStyle(fontSize: 12, color: AppTheme.primary),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: TpixGap.xs),
                BridgeInput(
                  key: const ValueKey('usdt-deposit-amount'),
                  controller: _depositCtrl,
                  hint: '0.00',
                  amount: true,
                  enabled: !bridgeBusy,
                  onChanged: (_) => setState(() {}),
                  errorText: check.error != null
                      ? bridgeT(l, check.error!, check.params)
                      : _depositInsufficient
                          ? l.t('bridge.errInsufficient')
                          : null,
                  warningText: check.warning != null ? bridgeT(l, check.warning!, check.warningParams) : null,
                ),
                const SizedBox(height: TpixGap.md),
                BridgeKv(l.t('bridge.depositFee'), l.t('bridge.free')),
                BridgeKv(
                  l.t('bridge.youReceive'),
                  units6 != null && !check.blocked
                      ? '${formatUnitsPlain(units6, usdtTpixDecimals)} ${l.t('bridge.receiveOnTpix')}'
                      : '—',
                  valueColor: AppTheme.success,
                ),
                BridgeKv(l.t('bridge.eta'), bridgeT(l, 'bridge.etaMinutes', {'minutes': '${source.etaMinutes}'})),
                BridgeKv('${l.t('bridge.minDeposit')} / ${l.t('bridge.maxPerTx')}',
                    '${limits['min_deposit'] ?? '—'} / ${limits['max_deposit_per_tx'] ?? '—'} USDT'),
                BridgeKv(l.t('bridge.dailyPerAddress'), '${limits['max_deposit_per_address_daily'] ?? '—'} USDT'),
                const SizedBox(height: TpixGap.sm),
                BridgeAckTile(
                  key: const ValueKey('usdt-ack'),
                  value: _ackOwnWallet,
                  onChanged: bridgeBusy ? null : (v) => setState(() => _ackOwnWallet = v),
                  text: l.t('bridge.ackOwnWallet'),
                ),
                const SizedBox(height: TpixGap.md),
                BridgePrimaryButton(
                  key: const ValueKey('usdt-deposit-button'),
                  label: l.t('bridge.sendUsdt'),
                  onPressed: _canDeposit ? _submitDeposit : null,
                  loading: bridgeBusy,
                  loadingLabel: bridgeBusyLabel,
                ),
              ] else ...[
                const SizedBox(height: TpixGap.md),
                Text(l.t('bridge.noDepositChain'), style: TextStyle(fontSize: 12.5, color: c.textSec)),
              ],
            ],
          ),
        ),
        const SizedBox(height: TpixGap.lg),
        BridgeHowItWorks(title: l.t('bridge.howTitle'), steps: [
          l.t('bridge.howDeposit1'),
          l.t('bridge.howDeposit2'),
          l.t('bridge.howDeposit3'),
          l.t('bridge.howDeposit4'),
        ]),
      ],
    );
  }

  Widget _withdrawSection(UsdtBridgeInfo info, LocaleProvider l) {
    final c = AppColors.of(context);
    final target = _target;
    final check = _withdrawCheck;
    final limits = info.limits;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BridgeCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l.t('bridge.targetChain'), style: TextStyle(fontSize: 12, color: c.textMuted)),
              const SizedBox(height: TpixGap.sm),
              BridgeChainPicker(
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
                onSelect: bridgeBusy ? null : (id) => setState(() => _targetChainId = id),
              ),
              const SizedBox(height: TpixGap.lg),
              Row(
                children: [
                  Expanded(child: Text(l.t('bridge.amount'), style: TextStyle(fontSize: 12, color: c.textMuted))),
                  if (_tpixUsdtBalance != null)
                    InkWell(
                      onTap: bridgeBusy
                          ? null
                          : () => setState(() => _withdrawCtrl.text = formatUnitsPlain(_tpixUsdtBalance!, usdtTpixDecimals)),
                      child: Text(
                        '${l.t('bridge.tpixBalance')}: ${formatUnitsPlain(_tpixUsdtBalance!, usdtTpixDecimals)} · ${l.t('bridge.max')}',
                        style: const TextStyle(fontSize: 12, color: AppTheme.primary),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: TpixGap.xs),
              BridgeInput(
                key: const ValueKey('usdt-withdraw-amount'),
                controller: _withdrawCtrl,
                hint: '0.00',
                amount: true,
                enabled: !bridgeBusy,
                onChanged: (_) => setState(() {}),
                errorText: check.error != null ? bridgeT(l, check.error!, check.params) : null,
              ),
              const SizedBox(height: TpixGap.md),
              Text(l.t('bridge.targetAddress'), style: TextStyle(fontSize: 12, color: c.textMuted)),
              const SizedBox(height: TpixGap.xs),
              BridgeInput(
                key: const ValueKey('usdt-target-address'),
                controller: _targetCtrl,
                hint: '0x…',
                mono: true,
                enabled: !bridgeBusy,
                onChanged: (_) => setState(() {}),
                errorText: _addressError != null ? l.t(_addressError!) : null,
                suffix: _owner == null
                    ? null
                    : TextButton(
                        onPressed: bridgeBusy ? null : () => setState(() => _targetCtrl.text = _owner!),
                        child: Text(l.t('bridge.useMyAddress'), style: const TextStyle(fontSize: 12, color: AppTheme.primary)),
                      ),
              ),
              const SizedBox(height: TpixGap.md),
              BridgeKv(l.t('bridge.withdrawFee'), '${target?.withdrawFee ?? '—'} USDT'),
              BridgeKv(
                l.t('bridge.youReceive'),
                '${formatUnitsPlain(_withdrawReceive, usdtTpixDecimals)} ${target?.usdtSymbol ?? 'USDT'} · ${target?.name ?? ''}',
                valueColor: AppTheme.success,
              ),
              BridgeKv('${l.t('bridge.minDeposit')} / ${l.t('bridge.maxPerTx')}',
                  '${limits['min_withdraw'] ?? '—'} / ${limits['max_withdraw_per_tx'] ?? '—'} USDT'),
              const SizedBox(height: TpixGap.md),
              BridgePrimaryButton(
                key: const ValueKey('usdt-withdraw-button'),
                label: bridgeT(l, 'bridge.burnUsdt', {'chain': target?.name ?? ''}),
                onPressed: _canWithdraw ? _submitWithdraw : null,
                loading: bridgeBusy,
                loadingLabel: bridgeBusyLabel,
              ),
            ],
          ),
        ),
        const SizedBox(height: TpixGap.lg),
        BridgeHowItWorks(title: l.t('bridge.howTitle'), steps: [
          l.t('bridge.howWithdraw1'),
          l.t('bridge.howWithdraw2'),
          l.t('bridge.howWithdraw3'),
        ]),
      ],
    );
  }

  Widget _trackSection(UsdtBridgeInfo info, LocaleProvider l) {
    final c = AppColors.of(context);
    final valid = isTxHash(_manualCtrl.text);
    return BridgeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l.t('bridge.trackTitle'), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.text)),
          const SizedBox(height: TpixGap.xs),
          Text(l.t('bridge.trackHint'), style: TextStyle(fontSize: 12, color: c.textSec)),
          const SizedBox(height: TpixGap.md),
          BridgeSegmented<String>(
            options: [(usdtDeposit, l.t('bridge.tabDeposit')), (usdtWithdraw, l.t('bridge.trackWithdrawal'))],
            value: _manualKind,
            onChanged: (k) => setState(() => _manualKind = k),
          ),
          if (_manualKind == usdtDeposit) ...[
            const SizedBox(height: TpixGap.md),
            BridgeChainPicker(
              chains: [
                for (final ch in info.chains.where((ch) => ch.chainId != bridgeTpixChainId && ch.chainId > 0))
                  (id: ch.chainId, title: ch.name, subtitle: ch.usdtSymbol, enabled: true),
              ],
              selected: _manualChainId,
              onSelect: (id) => setState(() => _manualChainId = id),
            ),
          ],
          const SizedBox(height: TpixGap.md),
          BridgeInput(
            key: const ValueKey('usdt-manual-hash'),
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

  Widget _trackedSection(UsdtBridgeInfo info, LocaleProvider l) {
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

  Widget _trackedTile(TrackedTransfer e, UsdtBridgeInfo info, LocaleProvider l) {
    final c = AppColors.of(context);
    final s = e.status;
    final badge = s == null ? null : stateBadge(s.state);
    final deposit = e.kind == usdtDeposit;
    final targetChain = e.targetChainId ?? s?.rows.where((r) => r.targetChainId != null).firstOrNull?.targetChainId;
    return BridgeTrackedTile(
      key: ValueKey('tracked-${e.key}'),
      title: deposit ? '${_chainName(e.chainId)} → TPIX' : 'TPIX → ${_chainName(targetChain)}',
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
              '${s.isFinal ? l.t('bridge.finalSoon') : bridgeT(l, 'bridge.confirmations', {'n': '${s.confirmations ?? 0}'})}'
              '${s.amount != null ? ' · ${s.amount} USDT' : ''}',
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
                  deposit
                      ? '${r.amount ?? '—'} USDT'
                      : '${r.amount ?? '—'} USDT → ${bridgeShort(r.targetAddress, head: 8)}',
                  style: TextStyle(fontSize: 12, color: c.text, fontWeight: FontWeight.w600),
                ),
                BridgeLink(label: deposit ? l.t('bridge.viewMint') : l.t('bridge.viewPayout'), url: r.url),
              ],
            ),
          ),
      ],
    );
  }

  Widget _historySection(UsdtBridgeInfo info, LocaleProvider l) {
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
                        '${r.kind == usdtDeposit ? l.t('bridge.deposits') : l.t('bridge.withdrawals')}'
                        ' · ${_chainName(r.chainId)} · ${r.amount ?? '—'} USDT',
                        style: TextStyle(fontSize: 12, color: c.text),
                      ),
                    ),
                    const SizedBox(width: TpixGap.sm),
                    BridgeStateChip(
                      label: bridgeT(l, stateBadge(r.state).labelKey, const {}, 'bridge.state.other'),
                      tone: stateBadge(r.state).tone,
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}
