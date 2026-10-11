/// TPIX Wallet — มาสเตอร์โหนด: ดูระดับ สเตค รับรางวัล ถอน จากกระเป๋าในแอป
///
/// ด่านความปลอดภัย (เรียงตามลำดับที่ผู้ใช้เจอ):
///   1. เว็บยังไม่ประกาศสัญญา → โชว์ "ยังไม่เปิด" ไม่มีปุ่มเขียนเลย
///   2. ที่อยู่สัญญาต้องเป็น bytecode ที่แอปตรึงไว้บนเชน 4289 (ตรวจใน MasterNodeService.discover
///      และตรวจซ้ำก่อนเขียนทุกครั้ง) — ไม่รู้จัก = ให้อัปเดตแอป, ถามเชนไม่ได้ = ไม่ส่ง
///   3. ปุ่มที่ใช้ไม่ได้ต้องบอกเหตุผล (ปิดรับ/เต็ม/ล็อกอยู่/กองรางวัลว่าง/ยอดไม่พอ)
///      กองรางวัลว่าง = ไม่โชว์ APR เหมือนจะได้จ่ายแน่ บอกตรงๆ ว่ากองยังไม่มีเงิน
///   4. กล่องยืนยันโชว์ระดับ จำนวนเต็มทุกหลัก วันล็อก ที่อยู่สัญญา → แล้วค่อยถาม PIN
///   5. ยกเลิกที่ PIN = ไม่ส่งอะไรเลย / สลับกระเป๋าระหว่างทาง = ยกเลิก
///   6. eth_estimateGas ก่อนเซ็น = ด่านสุดท้าย ถ้าสัญญาจะ revert ผู้ใช้เห็นเหตุผลแทนการเสียธุรกรรม
///
/// Developed by Xman Studio
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/locale_provider.dart';
import '../core/theme.dart';
import '../core/themes/tokens.dart';
import '../core/themes/widgets/screen_background.dart';
import '../models/chain_config.dart';
import '../providers/wallet_provider.dart';
import '../services/masternode_service.dart';
import '../services/rpc_client.dart';
import '../services/synth_service.dart';
import '../services/wallet_service.dart';
import '../widgets/tx_auth.dart';

enum _Phase { loading, error, notDeployed, unverified, unknownCode, ready }

enum _Action { stake, claim, unstake, withdraw }

final _dateFmt = DateFormat('yyyy-MM-dd HH:mm');

String _shortAddr(String a) =>
    a.length > 14 ? '${a.substring(0, 8)}…${a.substring(a.length - 6)}' : a;

class MasterNodeScreen extends StatefulWidget {
  const MasterNodeScreen({super.key});

  @override
  State<MasterNodeScreen> createState() => _MasterNodeScreenState();
}

class _MasterNodeScreenState extends State<MasterNodeScreen> {
  _Phase _phase = _Phase.loading;
  MnSnapshot? _snapshot;
  String _errorKey = 'mn.errLoad';

  /// รีเฟรชเบื้องหลัง (มีข้อมูลเดิมโชว์อยู่) — ไม่เอาสปินเนอร์เต็มจอมาบัง
  bool _refreshing = false;

  /// ลำดับการโหลด — ผลของรอบเก่า (เช่นของกระเป๋าใบก่อน) ต้องถูกทิ้ง
  int _loadSeq = 0;

  /// กระเป๋าที่ข้อมูลบนจอเป็นของมัน — เปลี่ยนเมื่อไหร่ต้องโหลดใหม่
  String? _watchedAddress;

  /// กันกดซ้อน "ตั้งแต่แตะปุ่ม" จนจบ (รวมช่วงกล่องยืนยัน/สแกนนิ้ว/PIN/รอเชน)
  bool _busy = false;
  _Action? _sending;
  MnTier? _sendingTier;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  // ================================================================
  // โหลดข้อมูล
  // ================================================================

  Future<void> _load() async {
    final seq = ++_loadSeq;
    final wallet = context.read<WalletProvider>();
    final owner = wallet.address;
    _watchedAddress = owner;

    // ข้อมูลบนจอเป็นของกระเป๋าใบอื่น → ล้างทิ้งก่อน ห้ามโชว์โหนดของใบเก่าค้างไว้
    final sameOwner = _snapshot != null &&
        owner != null &&
        _snapshot!.owner.toLowerCase() == owner.toLowerCase();
    setState(() {
      if (sameOwner && _phase == _Phase.ready) {
        _refreshing = true;
      } else {
        _phase = _Phase.loading;
        _snapshot = null;
      }
    });
    // ยอดล่าสุดไว้เช็กว่าพอสเตคไหม (ไม่ throw — ล้มก็คงยอดเดิม)
    unawaited(wallet.refreshBalance());

    try {
      final reg = await MasterNodeService.discover();
      if (!mounted || seq != _loadSeq) return;
      if (reg.availability != MnAvailability.ready) {
        setState(() {
          _snapshot = null;
          _refreshing = false;
          _phase = switch (reg.availability) {
            MnAvailability.notDeployed => _Phase.notDeployed,
            MnAvailability.unknownCode => _Phase.unknownCode,
            _ => _Phase.unverified,
          };
        });
        return;
      }
      if (owner == null) {
        _fail('mn.errLoad', seq);
        return;
      }
      final snap = await MasterNodeService.loadSnapshot(
        registry: reg.address!,
        owner: owner,
        configPaused: reg.config?.registrationPaused ?? false,
      );
      if (!mounted || seq != _loadSeq) return;
      setState(() {
        _snapshot = snap;
        _refreshing = false;
        _phase = _Phase.ready;
      });
    } on MnUnavailableException {
      _fail('mn.errNetwork', seq);
    } on MnContractMismatchException {
      // สัญญาตอบไม่ตรง ABI = ไม่ปลอดภัยที่จะเขียน
      if (!mounted || seq != _loadSeq) return;
      setState(() {
        _snapshot = null;
        _refreshing = false;
        _phase = _Phase.unverified;
      });
    } catch (e) {
      debugPrint('MasterNodeScreen._load: ${e.runtimeType}');
      _fail('mn.errLoad', seq);
    }
  }

  void _fail(String key, int seq) {
    if (!mounted || seq != _loadSeq) return;
    if (_phase == _Phase.ready && _snapshot != null) {
      // มีข้อมูลเดิมอยู่ — คงไว้ บอกแค่ว่ารีเฟรชไม่สำเร็จ
      setState(() => _refreshing = false);
      _snack(context.read<LocaleProvider>().t('mn.stale'), error: true);
      return;
    }
    setState(() {
      _refreshing = false;
      _errorKey = key;
      _phase = _Phase.error;
    });
  }

  // ================================================================
  // ข้อความ
  // ================================================================

  String _blockText(MnBlock block, LocaleProvider l, {MnTierInfo? info}) {
    switch (block) {
      case MnBlock.insufficientBalance:
        return l.t('mn.block.insufficientBalance').replaceAll(
            '{amount}', MasterNodeService.formatTpix(info?.minStake ?? BigInt.zero));
      case MnBlock.locked:
        final node = _snapshot?.node;
        return l.t('mn.block.locked').replaceAll(
            '{date}', node == null ? '—' : _dateFmt.format(node.unlockTime));
      case MnBlock.restakeWaitsForPool:
        return l.t('mn.block.restakeWaitsForPool').replaceAll('{amount}',
            MasterNodeService.formatTpix(_snapshot?.node.pendingUnclaimed ?? BigInt.zero));
      default:
        return l.t('mn.block.${block.name}');
    }
  }

  String _friendlyError(Object e, LocaleProvider l) {
    // ด่านตรวจ bytecode ก่อนเขียน — ทุกกรณีคือ "ยังไม่ได้ส่งอะไร"
    if (e is MnUnknownCodeException) return l.t('mn.unknownCodeTitle');
    if (e is MnContractMismatchException) return l.t('mn.unverifiedTitle');
    if (e is MnUnavailableException) return l.t('mn.errVerifyNetwork');
    if (e is RpcUnavailableException) return l.t('send.errNetwork');
    if (e is WalletChangedException) return l.t('send.errWalletChanged');
    if (e is RpcException) {
      final r = MasterNodeService.classifyRevert(e.message);
      if (r != MnRevert.unknown) return l.t('mn.revert.${r.name}');
      // ข้อความจากโหนด (ไม่มี URL/ข้อมูลลับ) ต่อท้ายได้ ช่วยแจ้งบั๊ก
      final short = e.message.length > 120 ? '${e.message.substring(0, 120)}…' : e.message;
      return '${l.t('mn.txError')}: $short';
    }
    return l.t('mn.txError');
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? AppTheme.danger : AppTheme.success,
      ),
    );
  }

  String _statusText(MnStatus s, LocaleProvider l) => l.t('mn.status.${s.name}');

  Color _statusColor(MnStatus s) {
    switch (s) {
      case MnStatus.active:
        return AppTheme.success;
      case MnStatus.slashed:
        return AppTheme.danger;
      case MnStatus.slashedWithdrawable:
        return AppTheme.warm;
      default:
        return AppTheme.textSecondary;
    }
  }

  // ================================================================
  // ธุรกรรม
  // ================================================================

  /// ตรวจว่ากระเป๋าที่ใช้อยู่ยังเป็นใบเดียวกับข้อมูลบนจอ — ไม่ใช่ = ยกเลิก + โหลดใหม่
  bool _ownerStillActive(MnSnapshot snap) {
    final current = context.read<WalletProvider>().address;
    if (current != null && current.toLowerCase() == snap.owner.toLowerCase()) {
      return true;
    }
    _snack(context.read<LocaleProvider>().t('send.errWalletChanged'), error: true);
    unawaited(_load());
    return false;
  }

  /// ห่อทุกปุ่ม: กันกดซ้อนตั้งแต่แตะครั้งแรก
  Future<void> _guard(Future<void> Function() flow) async {
    if (_busy || _sending != null) return;
    _busy = true;
    try {
      await flow();
    } finally {
      _busy = false;
    }
  }

  Future<void> _stake(MnTierInfo info) => _guard(() async {
        final snap = _snapshot;
        if (snap == null || !_ownerStillActive(snap)) return;
        final l = context.read<LocaleProvider>();
        final wallet = context.read<WalletProvider>();
        final block = snap.registerBlock(info.tier, wallet.balanceWei);
        if (block != null) {
          _snack(_blockText(block, l, info: info), error: true);
          return;
        }
        final endpoint = await showModalBottomSheet<String>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => _StakeSheet(
            info: info,
            registry: snap.registry,
            fromLabel: _fromLabel(wallet, snap.owner),
            poolFunded: snap.poolFunded,
          ),
        );
        if (endpoint == null || !mounted) return;
        await _authorizeAndSend(
          snap: snap,
          action: _Action.stake,
          tier: info.tier,
          // ★ ต้องเท่ากับ minStake ของระดับนั้นพอดี — สัญญารุ่นใหม่ไม่รับเกิน
          value: info.minStake,
          data: MasterNodeService.encodeRegister(info.tier, endpoint),
          gasFloor: MasterNodeService.gasFloorRegister,
        );
      });

  Future<void> _claim() => _guard(() async {
        final snap = _snapshot;
        if (snap == null || !_ownerStillActive(snap)) return;
        final l = context.read<LocaleProvider>();
        final block = snap.claimBlock();
        if (block != null) {
          _snack(_blockText(block, l), error: block != MnBlock.poolEmpty);
          return;
        }
        final ok = await _confirm(
          title: l.t('mn.confirmClaimTitle'),
          rows: [
            (l.t('send.from'), _fromLabel(context.read<WalletProvider>(), snap.owner)),
            (l.t('mn.claimable'), '${MasterNodeService.formatTpix(snap.claimableNow, maxDecimals: 18)} TPIX'),
            (l.t('mn.contract'), snap.registry),
          ],
          notes: [
            if (snap.pendingReward > snap.claimableNow) l.t('mn.claimPartialNote'),
          ],
          confirmLabel: l.t('mn.claim'),
        );
        if (!ok || !mounted) return;
        await _authorizeAndSend(
          snap: snap,
          action: _Action.claim,
          data: MasterNodeService.encodeClaim(),
          gasFloor: MasterNodeService.gasFloorClaim,
        );
      });

  Future<void> _unstake() => _guard(() async {
        final snap = _snapshot;
        if (snap == null || !_ownerStillActive(snap)) return;
        final l = context.read<LocaleProvider>();
        final block = snap.unstakeBlock(DateTime.now());
        if (block != null) {
          _snack(_blockText(block, l), error: true);
          return;
        }
        final ok = await _confirm(
          title: l.t('mn.confirmUnstakeTitle'),
          rows: [
            (l.t('send.from'), _fromLabel(context.read<WalletProvider>(), snap.owner)),
            (l.t('mn.tier'), snap.node.tier?.label ?? '—'),
            (l.t('mn.returned'), '${MasterNodeService.formatTpix(snap.node.stakedAmount, maxDecimals: 18)} TPIX'),
            (l.t('mn.contract'), snap.registry),
          ],
          notes: [
            l.t('mn.unstakeNote'),
            // กองจ่ายไม่ครบตอนถอน = ส่วนที่ค้างจะล็อกการสเตคใหม่ไว้ — บอกก่อนกดยืนยัน
            if (snap.unpaidAfterExit > BigInt.zero)
              l.t('mn.unstakeUnpaidNote').replaceAll(
                  '{amount}', MasterNodeService.formatTpix(snap.unpaidAfterExit)),
          ],
          confirmLabel: l.t('mn.unstake'),
          danger: true,
        );
        if (!ok || !mounted) return;
        await _authorizeAndSend(
          snap: snap,
          action: _Action.unstake,
          data: MasterNodeService.encodeDeregister(),
          gasFloor: MasterNodeService.gasFloorDeregister,
        );
      });

  Future<void> _withdrawSlashed() => _guard(() async {
        final snap = _snapshot;
        if (snap == null || !_ownerStillActive(snap)) return;
        if (!snap.canWithdrawSlashed) return;
        final l = context.read<LocaleProvider>();
        final ok = await _confirm(
          title: l.t('mn.confirmWithdrawTitle'),
          rows: [
            (l.t('send.from'), _fromLabel(context.read<WalletProvider>(), snap.owner)),
            (l.t('mn.returned'), '${MasterNodeService.formatTpix(snap.node.stakedAmount, maxDecimals: 18)} TPIX'),
            (l.t('mn.contract'), snap.registry),
          ],
          notes: const [],
          confirmLabel: l.t('mn.withdrawSlashed'),
        );
        if (!ok || !mounted) return;
        await _authorizeAndSend(
          snap: snap,
          action: _Action.withdraw,
          data: MasterNodeService.encodeWithdrawSlashed(),
          gasFloor: MasterNodeService.gasFloorWithdrawSlashed,
        );
      });

  String _fromLabel(WalletProvider wallet, String owner) {
    final name = wallet.activeWallet?.name;
    return name != null && name.isNotEmpty
        ? '$name · ${_shortAddr(owner)}'
        : _shortAddr(owner);
  }

  /// ตรวจล่วงหน้าบนเชน → ยืนยันตัวตน → ตรวจกระเป๋าซ้ำ → เซ็น+ส่ง → รอเชนยืนยัน → โหลดใหม่
  Future<void> _authorizeAndSend({
    required MnSnapshot snap,
    required _Action action,
    required Uint8List data,
    required int gasFloor,
    MnTier? tier,
    BigInt? value,
  }) async {
    final l = context.read<LocaleProvider>();
    final wallet = context.read<WalletProvider>();

    setState(() {
      _sending = action;
      _sendingTier = tier;
    });
    var sent = false;
    try {
      // ด่านแรก: สัญญาที่จะส่งเงินเข้าต้องยังเป็น bytecode ที่แอปตรึงไว้ (จำผลไว้ทั้งรอบ)
      // ถามเชนไม่ได้ = ไม่ส่ง — ห้ามถือว่าผ่าน
      await MasterNodeService.verifyRegistryCode(snap.registry);
      if (!mounted) return;

      // จำลองบนเชนก่อน — สัญญาจะปฏิเสธ (เต็ม/ล็อก/ปิดรับ) ก็บอกเหตุผลเลย
      // ไม่ต้องให้ผู้ใช้ใส่ PIN เพื่อไปเจอธุรกรรมที่ล้มแน่ๆ
      final estimated = await MasterNodeService.estimateGas(
        registry: snap.registry,
        from: snap.owner,
        value: value,
        data: data,
      );
      if (!mounted) return;

      final authed = await authorizeTransaction(context, reason: l.t('mn.authReason'));
      // ยกเลิก/PIN ผิด = จบตรงนี้ ยังไม่มีอะไรถูกเซ็นหรือส่ง
      if (!authed || !mounted) return;
      if (!_ownerStillActive(snap)) return;

      SynthService.playSend();
      final hash = await wallet.sendEvmTransaction(
        rpcUrl: ChainConfig.tpix.rpcUrl,
        chainId: MasterNodeService.chainId,
        toAddress: snap.registry,
        value: value,
        data: data,
        maxGas: MasterNodeService.gasLimit(estimated, gasFloor),
        gasPrice: BigInt.zero, // TPIX Chain ไม่มีค่าแก๊ส
        expectedFrom: snap.owner, // สลับกระเป๋าระหว่างนี้ = WalletChangedException
      );
      sent = true;
      // บล็อกละ ~2 วินาที รอได้ถึง 60 วินาที แล้วค่อยบอกว่า "ส่งแล้ว รอยืนยัน"
      String? status;
      for (var i = 0; i < 30; i++) {
        await Future.delayed(const Duration(seconds: 2));
        if (!mounted) return;
        status = await wallet.checkEvmTxStatus(ChainConfig.tpix.rpcUrl, hash);
        if (!mounted) return;
        if (status != null) break;
      }
      if (status == 'failed') {
        SynthService.playError();
        _snack(l.t('mn.txFailed'), error: true);
      } else if (status == 'confirmed') {
        SynthService.playSendSuccess();
        _snack(l.t('mn.txSuccess'));
      } else {
        _snack(l.t('mn.txPending'));
      }
    } catch (e) {
      if (!mounted) return;
      SynthService.playError();
      _snack(_friendlyError(e, l), error: true);
    } finally {
      if (mounted) {
        setState(() {
          _sending = null;
          _sendingTier = null;
        });
      }
    }
    if (!mounted) return;
    if (sent) {
      unawaited(wallet.loadTxHistory());
    }
    await _load();
  }

  /// กล่องยืนยันทั่วไป (รับรางวัล/ถอน) — คืน true เมื่อกดยืนยันเท่านั้น
  Future<bool> _confirm({
    required String title,
    required List<(String, String)> rows,
    required List<String> notes,
    required String confirmLabel,
    bool danger = false,
  }) async {
    final l = context.read<LocaleProvider>();
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        final c = AppColors.of(sheetCtx);
        return _SheetFrame(
          title: title,
          children: [
            for (final r in rows) _ConfirmRow(label: r.$1, value: r.$2),
            _ConfirmRow(label: l.t('send.network'), value: 'TPIX Chain (4289)'),
            _ConfirmRow(
              label: l.t('send.gasFee').replaceAll(': ', ''),
              value: l.t('send.gasFreeVal'),
              valueColor: AppTheme.success,
            ),
            for (final n in notes) _Note(text: n, color: c.brandWarm),
            const SizedBox(height: TpixGap.xl),
            _SheetButtons(
              cancelLabel: l.t('send.cancel'),
              confirmLabel: confirmLabel,
              danger: danger,
              onCancel: () => Navigator.pop(sheetCtx, false),
              onConfirm: () => Navigator.pop(sheetCtx, true),
            ),
          ],
        );
      },
    );
    return ok == true;
  }

  // ================================================================
  // UI
  // ================================================================

  @override
  Widget build(BuildContext context) {
    final l = context.watch<LocaleProvider>();
    final wallet = context.watch<WalletProvider>();

    // สลับกระเป๋าขณะเปิดหน้านี้อยู่ → โหลดของใบใหม่ (ทิ้งของใบเก่า)
    if (wallet.address != _watchedAddress && _phase != _Phase.loading) {
      _watchedAddress = wallet.address;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load();
      });
    }

    return Scaffold(
      body: TpixScreenBackground(
        child: SafeArea(
          child: Column(
            children: [
              _header(l),
              Expanded(child: _body(l, wallet)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(LocaleProvider l) {
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(TpixGap.sm, TpixGap.lg, TpixGap.lg, TpixGap.sm),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: Icon(Icons.arrow_back_ios, color: c.text),
          ),
          const SizedBox(width: TpixGap.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.t('mn.title'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: c.text)),
                Text(l.t('mn.subtitle'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: c.textMuted)),
              ],
            ),
          ),
          if (_refreshing)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary),
            ),
        ],
      ),
    );
  }

  Widget _body(LocaleProvider l, WalletProvider wallet) {
    switch (_phase) {
      case _Phase.loading:
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: AppTheme.primary),
              const SizedBox(height: TpixGap.lg),
              Text(l.t('mn.loading'), style: TextStyle(color: AppColors.of(context).textMuted)),
            ],
          ),
        );
      case _Phase.error:
        return _messageCard(
          icon: Icons.cloud_off_rounded,
          color: AppTheme.danger,
          title: l.t(_errorKey),
          body: null,
          actions: [_primaryButton(l.t('mn.retry'), _load)],
        );
      case _Phase.notDeployed:
        return _messageCard(
          icon: Icons.hourglass_top_rounded,
          color: AppTheme.warm,
          title: l.t('mn.notDeployedTitle'),
          body: l.t('mn.notDeployedBody'),
          actions: [
            _primaryButton(l.t('mn.retry'), _load),
            _textButton(l.t('mn.openWebsite'), _openWebsite),
          ],
        );
      case _Phase.unverified:
        return _messageCard(
          icon: Icons.gpp_maybe_rounded,
          color: AppTheme.danger,
          title: l.t('mn.unverifiedTitle'),
          body: l.t('mn.unverifiedBody'),
          actions: [
            _primaryButton(l.t('mn.retry'), _load),
            _textButton(l.t('mn.openWebsite'), _openWebsite),
          ],
        );
      case _Phase.unknownCode:
        return _messageCard(
          icon: Icons.system_update_rounded,
          color: AppTheme.danger,
          title: l.t('mn.unknownCodeTitle'),
          body: l.t('mn.unknownCodeBody'),
          actions: [
            _primaryButton(l.t('mn.updateApp'), _openDownloadPage),
            _textButton(l.t('mn.retry'), _load),
          ],
        );
      case _Phase.ready:
        final snap = _snapshot!;
        return RefreshIndicator(
          onRefresh: _load,
          color: AppTheme.primary,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(TpixGap.lg, TpixGap.sm, TpixGap.lg, TpixGap.huge),
            children: [
              if (snap.registrationPaused) ...[
                _banner(l.t('mn.block.paused'), AppTheme.warm, Icons.pause_circle_outline),
                const SizedBox(height: TpixGap.md),
              ],
              // กองว่าง = ยังไม่มีรางวัลจ่ายจริง — บอกก่อนผู้ใช้ตัดสินใจสเตค
              if (!snap.poolFunded) ...[
                _banner(l.t('mn.poolUnfunded'), AppTheme.warm, Icons.savings_outlined),
                const SizedBox(height: TpixGap.md),
              ],
              if (snap.hasNodeCard) ...[
                _myNodeCard(snap, l),
                const SizedBox(height: TpixGap.xl),
              ],
              _sectionTitle(l.t('mn.tiers')),
              const SizedBox(height: TpixGap.sm),
              for (final t in snap.displayTiers) ...[
                _tierCard(t, snap, wallet, l),
                const SizedBox(height: TpixGap.md),
              ],
              const SizedBox(height: TpixGap.sm),
              _footer(snap, l),
            ],
          ),
        );
    }
  }

  Future<void> _openWebsite() async {
    try {
      await launchUrl(Uri.parse(MasterNodeService.websiteUrl),
          mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) _snack(context.read<LocaleProvider>().t('common.browser_error'), error: true);
    }
  }

  /// หน้าดาวน์โหลดแอป — ไม่พาไปสเตคที่เว็บ เพราะแอปยังไม่รู้จักสัญญาตัวนี้
  Future<void> _openDownloadPage() async {
    try {
      await launchUrl(Uri.parse(MasterNodeService.downloadUrl),
          mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) _snack(context.read<LocaleProvider>().t('common.browser_error'), error: true);
    }
  }

  Widget _messageCard({
    required IconData icon,
    required Color color,
    required String title,
    required String? body,
    required List<Widget> actions,
  }) {
    final c = AppColors.of(context);
    return ListView(
      padding: const EdgeInsets.all(TpixGap.xxl),
      children: [
        const SizedBox(height: TpixGap.xxxl),
        Container(
          padding: const EdgeInsets.all(TpixGap.xxl),
          decoration: adaptiveGlassCard(context, borderRadius: TpixRadius.lg),
          child: Column(
            children: [
              Icon(icon, color: color, size: 48),
              const SizedBox(height: TpixGap.lg),
              Text(title,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: c.text)),
              if (body != null) ...[
                const SizedBox(height: TpixGap.sm),
                Text(body,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, height: 1.5, color: c.textSec)),
              ],
              const SizedBox(height: TpixGap.xl),
              ...actions,
            ],
          ),
        ),
      ],
    );
  }

  Widget _primaryButton(String label, VoidCallback onTap) => SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: onTap,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primary,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(TpixRadius.sm)),
          ),
          child: Text(label,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        ),
      );

  Widget _textButton(String label, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(top: TpixGap.sm),
        child: TextButton(
          onPressed: onTap,
          child: Text(label, style: const TextStyle(color: AppTheme.primary)),
        ),
      );

  Widget _banner(String text, Color color, IconData icon) => Container(
        padding: const EdgeInsets.all(TpixGap.md),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(TpixRadius.sm),
          color: color.withValues(alpha: 0.10),
          border: Border.all(color: color.withValues(alpha: 0.30)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: TpixGap.sm),
            Expanded(
              child: Text(text,
                  style: TextStyle(fontSize: 13, color: color, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );

  Widget _sectionTitle(String text) => Text(
        text,
        style: TextStyle(
            fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.of(context).text),
      );

  Widget _kv(String label, String value, {Color? valueColor, bool mono = false}) {
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 13, color: c.textMuted)),
          const SizedBox(width: TpixGap.md),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: valueColor ?? c.text,
                fontFamily: mono ? 'monospace' : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _reason(String text) => Padding(
        padding: const EdgeInsets.only(top: TpixGap.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline, size: 15, color: AppColors.of(context).textMuted),
            const SizedBox(width: TpixGap.xs),
            Expanded(
              child: Text(text,
                  style: TextStyle(fontSize: 12, color: AppColors.of(context).textSec)),
            ),
          ],
        ),
      );

  Widget _actionButton({
    required String label,
    required bool enabled,
    required bool loading,
    required VoidCallback onTap,
    Color color = AppTheme.primary,
    bool outlined = false,
  }) {
    final child = loading
        ? const SizedBox(
            width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
        : Text(label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontWeight: FontWeight.w700, color: outlined ? color : Colors.white));
    // กำลังส่งรายการไหนอยู่ = ทุกปุ่มปิดหมด (กันส่งซ้อน nonce)
    final onPressed = enabled && _sending == null ? onTap : null;
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(TpixRadius.sm));
    return outlined
        ? OutlinedButton(
            onPressed: onPressed,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
              side: BorderSide(color: color.withValues(alpha: onPressed == null ? 0.3 : 0.8)),
              shape: shape,
            ),
            child: child,
          )
        : ElevatedButton(
            onPressed: onPressed,
            style: ElevatedButton.styleFrom(
              backgroundColor: color,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: shape,
            ),
            child: child,
          );
  }

  Widget _myNodeCard(MnSnapshot snap, LocaleProvider l) {
    final c = AppColors.of(context);
    final node = snap.node;
    final claimBlock = snap.claimBlock();
    final unstakeBlock = snap.unstakeBlock(DateTime.now());
    // ถอนแล้วแต่รางวัลค้าง = สเตคใหม่ไม่ได้ — อธิบายที่นี่ที่เดียว (การ์ดระดับซ่อนปุ่มไว้)
    final restakeBlock = snap.pendingRewardBlock;
    final isActive = node.status == MnStatus.active;
    final statusColor = _statusColor(node.status);
    return Container(
      padding: const EdgeInsets.all(TpixGap.lg),
      decoration: adaptiveGlassCard(context, borderRadius: TpixRadius.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(l.t('mn.myNode'),
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.text)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(TpixRadius.xs),
                  color: statusColor.withValues(alpha: 0.12),
                ),
                child: Text(_statusText(node.status, l),
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: statusColor)),
              ),
            ],
          ),
          const SizedBox(height: TpixGap.md),
          if (node.status != MnStatus.inactive) ...[
            _kv(l.t('mn.tier'), node.tier?.label ?? '—'),
            _kv(l.t('mn.staked'), '${MasterNodeService.formatTpix(node.stakedAmount)} TPIX'),
            if (isActive) ...[
              _kv(l.t('mn.unlockAt'), _dateFmt.format(node.unlockTime)),
              _kv(l.t('mn.uptime'), MasterNodeService.formatBps(node.uptimeBps.toInt())),
            ],
            if (node.endpoint.isNotEmpty) _kv(l.t('mn.endpointShort'), node.endpoint, mono: true),
            Divider(color: c.glassBorder, height: TpixGap.xl),
          ],
          _kv(l.t('mn.earned'), '${MasterNodeService.formatTpix(snap.pendingReward)} TPIX'),
          _kv(l.t('mn.claimable'), '${MasterNodeService.formatTpix(snap.claimableNow)} TPIX',
              valueColor: AppTheme.success),
          if (node.totalRewards > BigInt.zero)
            _kv(l.t('mn.totalPaid'), '${MasterNodeService.formatTpix(node.totalRewards)} TPIX'),
          if (claimBlock == MnBlock.poolEmpty && restakeBlock == null)
            _reason(_blockText(MnBlock.poolEmpty, l)),
          const SizedBox(height: TpixGap.md),
          if (snap.canWithdrawSlashed)
            _actionButton(
              label: l.t('mn.withdrawSlashed'),
              enabled: true,
              loading: _sending == _Action.withdraw,
              onTap: _withdrawSlashed,
              color: AppTheme.warm,
            )
          else
            Row(
              children: [
                Expanded(
                  child: _actionButton(
                    label: l.t('mn.claim'),
                    enabled: claimBlock == null,
                    loading: _sending == _Action.claim,
                    onTap: _claim,
                    color: AppTheme.success,
                  ),
                ),
                if (isActive) ...[
                  const SizedBox(width: TpixGap.md),
                  Expanded(
                    child: _actionButton(
                      label: l.t('mn.unstake'),
                      enabled: unstakeBlock == null,
                      loading: _sending == _Action.unstake,
                      onTap: _unstake,
                      color: AppTheme.danger,
                      outlined: true,
                    ),
                  ),
                ],
              ],
            ),
          if (isActive && unstakeBlock == MnBlock.locked) _reason(_blockText(MnBlock.locked, l)),
          if (claimBlock == MnBlock.nothingToClaim && node.status != MnStatus.inactive)
            _reason(_blockText(MnBlock.nothingToClaim, l)),
          if (restakeBlock != null) _reason(_blockText(restakeBlock, l)),
        ],
      ),
    );
  }

  Widget _tierCard(MnTierInfo info, MnSnapshot snap, WalletProvider wallet, LocaleProvider l) {
    final c = AppColors.of(context);
    final block = snap.registerBlock(info.tier, wallet.balanceWei);
    final slots = info.isUnlimited
        ? '${info.activeNodes} / ${l.t('mn.unlimited')}'
        : '${info.activeNodes} / ${info.maxNodes}';
    // ติดทั้งกระเป๋า (มีโหนดอยู่แล้ว / รางวัลค้างต้องจ่ายครบก่อน): ไม่ต้องย้ำเหตุผลซ้ำทุกการ์ด
    // — การ์ดโหนดของฉันด้านบนอธิบายไว้แล้ว
    final showButton = block != MnBlock.hasNode &&
        block != MnBlock.claimFirst &&
        block != MnBlock.restakeWaitsForPool;
    final apr = snap.aprCapToShow(info.tier);
    return Container(
      padding: const EdgeInsets.all(TpixGap.lg),
      decoration: adaptiveGlassCard(context, borderRadius: TpixRadius.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(info.tier.label,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.text)),
              ),
              // กองว่าง: เพดาน APR ไม่มีความหมาย (จ่ายจริง 0) — โชว์สถานะกองแทน
              if (apr != null)
                Text('${l.t('mn.aprCap')} ${MasterNodeService.formatBps(apr)}',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.success))
              else if (!snap.poolFunded)
                Text(l.t('mn.poolUnfundedBadge'),
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.warm)),
            ],
          ),
          const SizedBox(height: TpixGap.sm),
          _kv(l.t('mn.minStake'),
              info.isConfigured ? '${MasterNodeService.formatTpix(info.minStake)} TPIX' : '—'),
          _kv(l.t('mn.lockDays'), l.t('mn.days').replaceAll('{n}', '${info.lockDays}')),
          _kv(l.t('mn.slots'), slots,
              valueColor: info.isFull ? AppTheme.danger : null),
          if (showButton) ...[
            const SizedBox(height: TpixGap.md),
            if (info.tier == MnTier.validator) ...[
              _actionButton(
                label: l.t('mn.openWebsite'),
                enabled: true,
                loading: false,
                onTap: _openWebsite,
                outlined: true,
              ),
              _reason(_blockText(MnBlock.validatorWebsiteOnly, l)),
            ] else ...[
              _actionButton(
                label: l.t('mn.stakeButton'),
                enabled: block == null,
                loading: _sending == _Action.stake && _sendingTier == info.tier,
                onTap: () => _stake(info),
              ),
              if (block != null) _reason(_blockText(block, l, info: info)),
            ],
          ],
        ],
      ),
    );
  }

  Widget _footer(MnSnapshot snap, LocaleProvider l) {
    final c = AppColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l.t('mn.rewardNote'),
            style: TextStyle(fontSize: 12, height: 1.5, color: c.textMuted)),
        const SizedBox(height: TpixGap.sm),
        GestureDetector(
          onLongPress: () async {
            await Clipboard.setData(ClipboardData(text: snap.registry));
            if (mounted) _snack(l.t('home.copied'));
          },
          child: Text('${l.t('mn.contract')}: ${snap.registry}',
              style: TextStyle(fontSize: 11, color: c.textMuted, fontFamily: 'monospace')),
        ),
      ],
    );
  }
}

// ================================================================
// แผ่นสเตค — กรอก endpoint + ยืนยันทุกรายละเอียดในที่เดียว
// ================================================================

class _StakeSheet extends StatefulWidget {
  final MnTierInfo info;
  final String registry;
  final String fromLabel;

  /// กองรางวัลมีเงินไหม — ไม่มี = เตือนว่าสเตคตอนนี้ยังไม่ได้รางวัลจริง
  final bool poolFunded;

  const _StakeSheet({
    required this.info,
    required this.registry,
    required this.fromLabel,
    required this.poolFunded,
  });

  @override
  State<_StakeSheet> createState() => _StakeSheetState();
}

class _StakeSheetState extends State<_StakeSheet> {
  final _endpoint = TextEditingController();
  MnEndpointError? _error;

  @override
  void dispose() {
    _endpoint.dispose();
    super.dispose();
  }

  void _submit() {
    final err = MasterNodeService.validateEndpoint(_endpoint.text);
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    Navigator.pop(context, _endpoint.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<LocaleProvider>();
    final c = AppColors.of(context);
    final info = widget.info;
    final lockDays = info.lockDays.toInt();
    final unlockEst = DateTime.now().add(Duration(days: lockDays));
    return _SheetFrame(
      title: l.t('mn.stakeTitle').replaceAll('{tier}', info.tier.label),
      children: [
        Text(l.t('mn.endpoint'), style: TextStyle(fontSize: 13, color: c.textSec)),
        const SizedBox(height: TpixGap.xs),
        TextField(
          controller: _endpoint,
          autofocus: true,
          keyboardType: TextInputType.url,
          autocorrect: false,
          enableSuggestions: false,
          maxLength: MasterNodeService.maxEndpointLength,
          // ASCII เท่านั้น — สัญญานับความยาวเป็นไบต์
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9.\-:\[\]]'))],
          style: TextStyle(color: c.text, fontSize: 14, fontFamily: 'monospace'),
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
          onSubmitted: (_) => _submit(),
          decoration: InputDecoration(
            hintText: '203.0.113.10:8545',
            hintStyle: TextStyle(color: c.textMuted),
            errorText: _error == null ? null : l.t('mn.endpointErr.${_error!.name}'),
            helperText: l.t('mn.endpointHelp'),
            helperMaxLines: 2,
            helperStyle: TextStyle(color: c.textMuted, fontSize: 11),
            filled: true,
            fillColor: c.glassColor,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(TpixRadius.sm),
              borderSide: BorderSide(color: c.glassBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(TpixRadius.sm),
              borderSide: BorderSide(color: c.glassBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(TpixRadius.sm),
              borderSide: const BorderSide(color: AppTheme.primary),
            ),
          ),
        ),
        const SizedBox(height: TpixGap.sm),
        _ConfirmRow(label: l.t('mn.tier'), value: info.tier.label),
        // จำนวนเต็มทุกหลัก — นี่คือ msg.value ที่จะส่งจริง
        _ConfirmRow(
          label: l.t('send.confirmAmount'),
          value: '${MasterNodeService.formatTpix(info.minStake, maxDecimals: 18)} TPIX',
          valueColor: AppTheme.primary,
        ),
        _ConfirmRow(
            label: l.t('mn.lockDays'), value: l.t('mn.days').replaceAll('{n}', '$lockDays')),
        _ConfirmRow(label: l.t('mn.unlockEst'), value: _dateFmt.format(unlockEst)),
        _ConfirmRow(label: l.t('send.from'), value: widget.fromLabel),
        _ConfirmRow(label: l.t('mn.contract'), value: widget.registry),
        _ConfirmRow(label: l.t('send.network'), value: 'TPIX Chain (4289)'),
        _ConfirmRow(
          label: l.t('send.gasFee').replaceAll(': ', ''),
          value: l.t('send.gasFreeVal'),
          valueColor: AppTheme.success,
        ),
        if (!widget.poolFunded) _Note(text: l.t('mn.stakePoolEmptyNote'), color: c.brandWarm),
        _Note(text: l.t('mn.lockWarn').replaceAll('{n}', '$lockDays'), color: c.brandWarm),
        if (info.slashPercentBps > BigInt.zero)
          _Note(
            text: l.t('mn.slashWarn').replaceAll(
                '{pct}', MasterNodeService.formatBps(info.slashPercentBps.toInt())),
            color: c.brandWarm,
          ),
        const SizedBox(height: TpixGap.xl),
        _SheetButtons(
          cancelLabel: l.t('send.cancel'),
          confirmLabel: l.t('mn.confirmStake'),
          onCancel: () => Navigator.pop(context),
          onConfirm: _submit,
        ),
      ],
    );
  }
}

// ================================================================
// ชิ้นส่วนแผ่นยืนยัน
// ================================================================

class _SheetFrame extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _SheetFrame({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Padding(
      // ดันขึ้นพ้นคีย์บอร์ด (ช่อง endpoint)
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.9),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(TpixRadius.lg)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(TpixGap.xxl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(2),
                      color: c.textMuted.withValues(alpha: 0.3),
                    ),
                  ),
                ),
                const SizedBox(height: TpixGap.xl),
                Text(title,
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c.text)),
                const SizedBox(height: TpixGap.lg),
                ...children,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ConfirmRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _ConfirmRow({required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 14, color: c.textMuted)),
          const SizedBox(width: TpixGap.md),
          // ที่อยู่สัญญายาว — ตัดบรรทัดได้ ห้ามตัดเป็น … (ผู้ใช้ต้องตรวจได้ทุกตัวอักษร)
          Expanded(
            child: SelectableText(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(
                fontSize: 14,
                color: valueColor ?? c.text,
                fontFamily: 'monospace',
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  final String text;
  final Color color;

  const _Note({required this.text, required this.color});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: TpixGap.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.warning_amber_rounded, size: 16, color: color),
            const SizedBox(width: TpixGap.xs),
            Expanded(child: Text(text, style: TextStyle(fontSize: 12, height: 1.4, color: color))),
          ],
        ),
      );
}

class _SheetButtons extends StatelessWidget {
  final String cancelLabel;
  final String confirmLabel;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;
  final bool danger;

  const _SheetButtons({
    required this.cancelLabel,
    required this.confirmLabel,
    required this.onCancel,
    required this.onConfirm,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(TpixRadius.sm));
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: onCancel,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              side: BorderSide(color: c.glassBorder),
              shape: shape,
            ),
            child: Text(cancelLabel, style: TextStyle(color: c.textSec)),
          ),
        ),
        const SizedBox(width: TpixGap.md),
        Expanded(
          flex: 2,
          child: ElevatedButton(
            onPressed: onConfirm,
            style: ElevatedButton.styleFrom(
              backgroundColor: danger ? AppTheme.danger : AppTheme.primary,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: shape,
            ),
            child: Text(confirmLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ),
      ],
    );
  }
}
