import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../core/themes/tokens.dart';
import 'package:provider/provider.dart';
import 'package:tpix_wallet/core/locale_provider.dart';
import 'package:tpix_wallet/core/theme.dart';
import 'package:tpix_wallet/core/themes/theme_bundle.dart';
import 'package:tpix_wallet/services/walletconnect_service.dart';
import 'package:tpix_wallet/services/wc_request_rules.dart';
import 'package:tpix_wallet/widgets/obsidian/obsidian.dart';
import 'package:tpix_wallet/widgets/qr_scanner_screen.dart';

// หน้าตาธีม Obsidian (ใช้สถานะ/ตัวจัดการเดิมของหน้านี้ร่วมกัน)
part 'dapp_connect_obsidian.dart';

/// Screen for managing WalletConnect dApp connections.
///
/// Entry points:
/// 1. Home screen "Connect" action button → opens QR scanner
/// 2. Deep link wc: / tpixwallet://wc?uri= → auto-pairs and shows approval card
/// 3. Settings → shows active sessions list
///
/// เปิดได้ทีละหน้า: คำขอเชื่อมต่อ/คำขอเซ็นที่เข้ามาตอนหน้านี้เปิดอยู่แล้ว ไม่ push หน้าซ้ำ
/// (หน้าเดิมวาดใหม่จาก [WalletConnectService] เอง) — ดู [isOpen] / [pairInOpenScreen]
class DAppConnectScreen extends StatefulWidget {
  /// If provided, auto-pair with this WC URI (from deep link or direct input).
  final String? initialUri;

  const DAppConnectScreen({super.key, this.initialUri});

  /// มีหน้านี้เปิดค้างอยู่ไหม (ทุกทางเข้า: หน้าแรก / ตั้งค่า / ลิงก์)
  static bool get isOpen => _DAppConnectScreenState._live.isNotEmpty;

  /// ส่ง wc: URI ให้หน้าที่เปิดอยู่จับคู่แทนการ push หน้าซ้ำ — false = ไม่มีหน้าเปิดอยู่
  static bool pairInOpenScreen(String uri) {
    final live = _DAppConnectScreenState._live;
    if (live.isEmpty) return false;
    live.last._pairWithUri(uri);
    return true;
  }

  @override
  State<DAppConnectScreen> createState() => _DAppConnectScreenState();
}

class _DAppConnectScreenState extends State<DAppConnectScreen> {
  /// หน้าที่ mount อยู่ตอนนี้ (ปกติมีไม่เกินหนึ่ง)
  static final List<_DAppConnectScreenState> _live = [];

  late final WalletConnectService _wc;

  /// จับคู่ที่กำลังวิ่งอยู่ (ลิงก์ใหม่มาระหว่างรอได้)
  int _pairing = 0;
  bool get _isPairing => _pairing > 0;
  String? _error;

  /// ปุ่มที่กำลังทำงาน — วงหมุนขึ้นที่ปุ่มนั้น และกดปุ่มอื่นซ้ำไม่ได้
  String? _action;

  @override
  void initState() {
    super.initState();
    _live.add(this);
    _wc = context.read<WalletConnectService>();
    if (widget.initialUri != null) {
      _pairWithUri(widget.initialUri!);
    }
  }

  @override
  void dispose() {
    _live.remove(this);
    // ข้อความค้างจากรอบนี้ไม่ต้องโผล่ตอนเปิดหน้าครั้งหน้า (ไม่แจ้ง listener — ต้นไม้กำลังถูกรื้อ)
    if (_live.isEmpty) _wc.clearNotice(notify: false);
    super.dispose();
  }

  Future<void> _pairWithUri(String uri) async {
    setState(() {
      _pairing++;
      _error = null;
    });

    try {
      await _wc.pair(uri);
      // Proposal will arrive via onProposalReceived callback
    } catch (e) {
      // ห้ามโชว์ Exception ดิบ — บอกสิ่งที่ผู้ใช้ทำต่อได้ (QR หมดอายุ → สร้างใหม่บนเว็บ)
      debugPrint('WalletConnect pair failed: ${e.runtimeType}');
      if (!mounted) return;
      setState(() {
        _error = context.read<LocaleProvider>().t('wc.pairFailed');
      });
    } finally {
      if (mounted) {
        setState(() => _pairing--);
      }
    }
  }

  void _openScanner() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => QRScannerScreen(
          onScanned: (value) {
            Navigator.pop(context);
            if (value.startsWith('wc:')) {
              // สแกนเองในแอป (เช่น QR บนคอม) — ไม่ใช่ลิงก์จากเบราว์เซอร์ในเครื่อง ห้ามพากลับเบราว์เซอร์
              _wc.endBrowserVisit();
              _pairWithUri(value);
            } else {
              if (!mounted) return;
              setState(() {
                _error = context.read<LocaleProvider>().t('wc.invalidQr');
              });
            }
          },
          titleKey: 'wc.scanTitle',
        ),
      ),
    );
  }

  /// รันคำสั่งของปุ่ม (อนุมัติ/ปฏิเสธ) ทีละอัน — แตะรัวไม่ส่งซ้ำ
  Future<void> _run(String action, Future<void> Function() task) async {
    if (_action != null) return;
    setState(() => _action = action);
    try {
      await task();
    } finally {
      if (mounted) setState(() => _action = null);
    }
  }

  bool _locked(WalletConnectService wc) => wc.busy || _action != null;

  void _dismissError() => setState(() => _error = null);

  // ── ข้อความ (ใช้ร่วมสองธีม) ──

  static String _fill(String template, Map<String, String> params) {
    var text = template;
    params.forEach((k, v) => text = text.replaceAll('{$k}', v));
    return text;
  }

  String _noticeText(LocaleProvider l, WcNotice notice) {
    final text = _fill(l.t(notice.key), notice.params);
    final detail = notice.detail;
    return detail == null || detail.isEmpty ? text : '$text ($detail)';
  }

  String _originText(LocaleProvider l, WcOrigin origin) => switch (origin.level) {
        WcOriginLevel.verified => _fill(l.t('wc.originVerified'), {'host': origin.host}),
        WcOriginLevel.unknown => _fill(l.t('wc.originUnknown'), {'host': origin.displayHost}),
        WcOriginLevel.mismatch =>
          _fill(l.t('wc.originMismatch'), {'origin': origin.host, 'claimed': origin.claimedHost}),
        WcOriginLevel.invalid => l.t('wc.originInvalid'),
        WcOriginLevel.scam => l.t('wc.originScam'),
      };

  String _requestTitle(LocaleProvider l, WcRequestView view) => switch (view.kind) {
        WcRequestKind.signMessage => l.t('wc.reqSign'),
        WcRequestKind.sendTransaction => l.t('wc.reqSendTx'),
        WcRequestKind.signTypedData => l.t('wc.reqTypedData'),
        WcRequestKind.other => view.method,
      };

  String _requestBody(LocaleProvider l, WcRequestView view) {
    if (view.kind != WcRequestKind.sendTransaction) return view.body;
    return [
      '${l.t('wc.to')}: ${view.to ?? '—'}',
      '${l.t('wc.value')}: ${view.value ?? '—'}',
      if (view.chainName != null) '${l.t('wc.network')}: ${view.chainName}',
    ].join('\n');
  }

  /// "คำขอจาก tpix.online" — null = ไม่รู้จัก session นั้น
  String? _requestFrom(LocaleProvider l, WalletConnectService wc) {
    final request = wc.pendingRequest;
    final url = request == null ? null : wc.peerOf(request.topic)?.url;
    final host = url == null ? '' : (Uri.tryParse(url)?.host ?? '');
    return host.isEmpty ? null : _fill(l.t('wc.requestFrom'), {'host': host});
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<LocaleProvider>();
    final wc = context.watch<WalletConnectService>();
    // ธีม Obsidian มีเลย์เอาต์ของตัวเอง (dapp_connect_obsidian.dart) — ธีมอื่นใช้ของเดิมด้านล่าง
    if (TpixThemeExtension.of(context).themeId == ThemeId.obsidian) return _obsBuild(l, wc);
    final c = AppColors.of(context);
    final activeSessions = wc.sessions;
    final notice = wc.notice;

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          l.t('wc.title'),
          style: TextStyle(color: c.text, fontWeight: FontWeight.bold),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: c.text),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        // เลื่อนได้ทั้งหน้า — การ์ดคำขอ + คำเตือนที่มาของเว็บ + ข้อความ ซ้อนกันแล้วจอเล็กไม่ล้น
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // Scan QR Button
            _buildScanButton(l),
            const SizedBox(height: TpixGap.sm),

            // Error message (จับคู่ในหน้านี้) + ข้อความจาก service (คำขอ/คำตอบ) — แตะเพื่อปิด
            if (_error != null) ...[
              _buildErrorBox(l, _error!, _dismissError),
              const SizedBox(height: TpixGap.lg),
            ],
            if (notice != null) ...[
              _buildErrorBox(l, _noticeText(l, notice), wc.clearNotice),
              const SizedBox(height: TpixGap.lg),
            ],

            // Pairing indicator (รวมช่วงรอคำขอเชื่อมต่อหลังเปิดจากลิงก์ของเว็บ)
            if (_isPairing || wc.awaitingBrowserProposal) ...[
              _buildProgress(l.t('wc.pairing')),
              const SizedBox(height: TpixGap.lg),
            ],
            if (wc.awaitingBrowserRequest) ...[
              _buildProgress(l.t('wc.waitingRequest')),
              const SizedBox(height: TpixGap.lg),
            ],

            // Pending Proposal
            if (wc.hasPendingProposal) ...[
              _buildProposalCard(l, wc, c),
              const SizedBox(height: TpixGap.lg),
            ],

            // Pending Request
            if (wc.hasPendingRequest) ...[
              _buildRequestCard(l, wc, c),
              const SizedBox(height: TpixGap.lg),
            ],

            // Active Sessions
            Text(
              l.t('wc.activeSessions'),
              style: TextStyle(
                color: c.textSec,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: TpixGap.md),
            if (activeSessions.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: TpixGap.xxl),
                child: _buildEmptyState(l),
              )
            else
              for (final session in activeSessions)
                Padding(
                  padding: const EdgeInsets.only(bottom: TpixGap.sm),
                  child: _buildSessionCard(session, wc, l, c),
                ),
          ],
        ),
      ),
    );
  }

  // ================================================================
  //  Widget Builders
  // ================================================================

  Widget _buildScanButton(LocaleProvider l) {
    return GestureDetector(
      onTap: _isPairing ? null : _openScanner,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          gradient: AppTheme.brandGradient,
          borderRadius: BorderRadius.circular(TpixRadius.md),
          boxShadow: [
            BoxShadow(
              color: AppTheme.primary.withValues(alpha: 0.3),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.qr_code_scanner_rounded, color: Colors.white, size: 24),
            const SizedBox(width: TpixGap.md),
            Text(
              l.t('wc.scanConnect'),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorBox(LocaleProvider l, String text, VoidCallback onDismiss) {
    return GestureDetector(
      onTap: onDismiss,
      child: Semantics(
        hint: l.t('wc.dismiss'),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.danger.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(TpixRadius.sm),
            border: Border.all(color: AppTheme.danger.withValues(alpha: 0.3)),
          ),
          child: Text(
            text,
            style: const TextStyle(color: AppTheme.danger, fontSize: 13),
          ),
        ),
      ),
    );
  }

  Widget _buildProgress(String label) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(TpixRadius.md),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppTheme.primary,
            ),
          ),
          const SizedBox(width: TpixGap.md),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: AppTheme.primary, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  /// ที่มาของเว็บตาม WalletConnect Verify — แดง = อาจเป็นเว็บปลอม (ผู้ใช้ยังตัดสินใจเองได้)
  Widget _buildOriginInfo(LocaleProvider l, WcOrigin origin, AppColors c) {
    final danger = origin.isDanger;
    final verified = origin.level == WcOriginLevel.verified;
    final color = danger
        ? AppTheme.danger
        : verified
            ? AppTheme.success
            : c.textMuted;
    final icon = danger
        ? Icons.gpp_bad_rounded
        : verified
            ? Icons.verified_rounded
            : Icons.help_outline_rounded;
    return Container(
      key: ValueKey(danger ? 'wc-origin-warning' : 'wc-origin-${origin.level.name}'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: danger ? 0.12 : 0.07),
        borderRadius: BorderRadius.circular(TpixRadius.sm),
        border: Border.all(color: color.withValues(alpha: danger ? 0.45 : 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: TpixGap.sm),
          Expanded(
            child: Text(
              _originText(l, origin),
              style: TextStyle(
                color: danger ? AppTheme.danger : c.textSec,
                fontSize: 12.5,
                height: 1.4,
                fontWeight: danger ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProposalCard(LocaleProvider l, WalletConnectService wc, AppColors c) {
    final proposal = wc.pendingProposal!;
    final peer = proposal.params.proposer.metadata;
    final origin = WcOrigin.check(proposal.verifyContext, peer.url);
    final scam = origin.level == WcOriginLevel.scam;
    final locked = _locked(wc);

    final reject = _actionButton(
      label: l.t('wc.reject'),
      color: AppTheme.danger,
      // เว็บหลอกลวง → ปฏิเสธคือปุ่มหลัก (ทึบ) ส่วนอนุมัติถอยเป็นปุ่มรอง
      filled: scam,
      loading: _action == 'rejectProposal',
      onTap: locked ? null : () => _run('rejectProposal', () => wc.rejectProposal(proposal.id)),
    );
    final approve = _actionButton(
      label: l.t(scam ? 'wc.approveAnyway' : 'wc.approve'),
      color: scam ? c.textMuted : AppTheme.success,
      filled: !scam,
      loading: _action == 'approveProposal',
      onTap: locked ? null : () => _run('approveProposal', () => wc.approveProposal(proposal.id)),
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(TpixRadius.md),
        border: Border.all(color: (origin.isDanger ? AppTheme.danger : AppTheme.primary).withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primary.withValues(alpha: 0.1),
            blurRadius: 20,
          ),
        ],
      ),
      child: Column(
        children: [
          // dApp icon
          if (peer.icons.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(TpixRadius.sm),
              child: Image.network(
                peer.icons.first,
                width: 48,
                height: 48,
                errorBuilder: (_, _, _) => Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(TpixRadius.sm),
                  ),
                  child: const Icon(Icons.language, color: AppTheme.primary),
                ),
              ),
            ),
          const SizedBox(height: TpixGap.md),
          Text(
            peer.name,
            style: TextStyle(
              color: c.text,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: TpixGap.xs),
          Text(
            peer.url,
            style: TextStyle(color: c.textSec, fontSize: 13),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: TpixGap.md),
          _buildOriginInfo(l, origin, c),
          const SizedBox(height: TpixGap.md),
          Text(
            l.t('wc.wantsToConnect'),
            style: TextStyle(color: c.textMuted, fontSize: 13),
          ),
          const SizedBox(height: TpixGap.lg),
          // Approve / Reject buttons — ปุ่มหลักอยู่ขวาเสมอ
          Row(
            children: [
              Expanded(child: scam ? approve : reject),
              const SizedBox(width: TpixGap.md),
              Expanded(child: scam ? reject : approve),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRequestCard(LocaleProvider l, WalletConnectService wc, AppColors c) {
    final request = wc.pendingRequest!;
    final view = wc.pendingRequestView!;
    final from = _requestFrom(l, wc);
    final more = wc.pendingRequestCount - 1;
    final locked = _locked(wc);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(TpixRadius.md),
        border: Border.all(color: AppTheme.warm.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.edit_note_rounded, color: AppTheme.warm, size: 20),
              const SizedBox(width: TpixGap.sm),
              Expanded(
                child: Text(
                  _requestTitle(l, view),
                  style: TextStyle(
                    color: c.text,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          if (from != null) ...[
            const SizedBox(height: TpixGap.xs),
            Text(from, style: TextStyle(color: c.textSec, fontSize: 12.5)),
          ],
          const SizedBox(height: TpixGap.sm),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(TpixRadius.xs),
            ),
            child: Text(
              _requestBody(l, view),
              style: TextStyle(
                color: c.textSec,
                fontSize: 12,
                fontFamily: 'monospace',
              ),
              maxLines: 10,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (more > 0) ...[
            const SizedBox(height: TpixGap.sm),
            Text(
              _fill(l.t('wc.moreRequests'), {'n': '$more'}),
              style: TextStyle(color: c.textMuted, fontSize: 12),
            ),
          ],
          const SizedBox(height: TpixGap.md),
          Row(
            children: [
              Expanded(
                child: _actionButton(
                  label: l.t('wc.reject'),
                  color: AppTheme.danger,
                  loading: _action == 'rejectRequest',
                  onTap: locked ? null : () => _run('rejectRequest', () => wc.rejectRequest(request.id)),
                ),
              ),
              const SizedBox(width: TpixGap.md),
              Expanded(
                child: _actionButton(
                  label: l.t('wc.confirm'),
                  color: AppTheme.success,
                  filled: true,
                  loading: _action == 'approveRequest',
                  onTap: locked ? null : () => _run('approveRequest', () => wc.approveRequest(request.id)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSessionCard(dynamic session, WalletConnectService wc, LocaleProvider l, AppColors c) {
    final peer = wc.getPeerInfo(session);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(TpixRadius.md),
        border: Border.all(color: c.border),
      ),
      child: Row(
        children: [
          // dApp icon
          ClipRRect(
            borderRadius: BorderRadius.circular(TpixRadius.sm),
            child: peer['icon']!.isNotEmpty
                ? Image.network(
                    peer['icon']!,
                    width: 40,
                    height: 40,
                    errorBuilder: (_, _, _) => _iconPlaceholder(),
                  )
                : _iconPlaceholder(),
          ),
          const SizedBox(width: TpixGap.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  peer['name'] ?? 'Unknown dApp',
                  style: TextStyle(
                    color: c.text,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: TpixGap.hair),
                Text(
                  peer['url'] ?? '',
                  style: TextStyle(color: c.textMuted, fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.link_off_rounded, color: AppTheme.danger, size: 20),
            onPressed: () => _confirmDisconnect(session.topic, peer['name'] ?? '', l, wc),
            tooltip: l.t('wc.disconnect'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(LocaleProvider l) {
    final c = AppColors.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.link_off_rounded, size: 48, color: c.textMuted.withValues(alpha: 0.4)),
          const SizedBox(height: TpixGap.md),
          Text(
            l.t('wc.noSessions'),
            style: TextStyle(color: c.textMuted, fontSize: 14),
          ),
          const SizedBox(height: TpixGap.xs),
          Text(
            l.t('wc.noSessionsDesc'),
            style: TextStyle(color: c.textMuted.withValues(alpha: 0.6), fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _iconPlaceholder() {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(TpixRadius.sm),
      ),
      child: const Icon(Icons.language, color: AppTheme.primary, size: 20),
    );
  }

  /// [onTap] null = ปิดอยู่ (กำลังส่งคำตอบ) · [loading] = วงหมุนแทนป้าย
  Widget _actionButton({
    required String label,
    required Color color,
    required VoidCallback? onTap,
    bool filled = false,
    bool loading = false,
  }) {
    final fg = filled ? Colors.white : color;
    return Opacity(
      opacity: onTap == null && !loading ? 0.5 : 1,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: filled ? color : Colors.transparent,
            borderRadius: BorderRadius.circular(TpixRadius.sm),
            border: Border.all(color: color.withValues(alpha: 0.5)),
          ),
          child: loading
              ? Center(
                  child: SizedBox(
                    width: 17,
                    height: 17,
                    child: CircularProgressIndicator(strokeWidth: 2, color: fg),
                  ),
                )
              : Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: fg,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
        ),
      ),
    );
  }

  void _confirmDisconnect(String topic, String name, LocaleProvider l, WalletConnectService wc) {
    if (TpixThemeExtension.of(context).themeId == ThemeId.obsidian) {
      showObsidianConfirmDialog(
        context,
        title: l.t('wc.disconnectTitle'),
        body: '${l.t('wc.disconnectMsg')} $name?',
        confirmLabel: l.t('wc.disconnect'),
        cancelLabel: l.t('common.cancel'),
        danger: true,
      ).then((ok) {
        if (ok) wc.disconnectSession(topic);
      });
      return;
    }
    final c = AppColors.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(TpixRadius.md)),
        title: Text(l.t('wc.disconnectTitle'), style: TextStyle(color: c.text)),
        content: Text(
          '${l.t('wc.disconnectMsg')} $name?',
          style: TextStyle(color: c.textSec),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l.t('common.cancel'), style: TextStyle(color: c.textMuted)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              wc.disconnectSession(topic);
            },
            child: Text(l.t('wc.disconnect'), style: const TextStyle(color: AppTheme.danger)),
          ),
        ],
      ),
    );
  }
}
