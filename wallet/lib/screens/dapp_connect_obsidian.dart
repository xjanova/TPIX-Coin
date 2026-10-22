// TPIX Wallet — หน้าเชื่อมต่อ dApp (WalletConnect) ธีม Obsidian
//
// part ของ dapp_connect_screen.dart โดยตั้งใจ: จับคู่ · อนุมัติ/ปฏิเสธคำขอ · ยกเลิกการเชื่อมต่อ
// ใช้ตัวจัดการเดิมทั้งหมด — ไฟล์นี้เปลี่ยนแค่หน้าตา
//
// Developed by Xman Studio

part of 'dapp_connect_screen.dart';

extension _DAppObsidian on _DAppConnectScreenState {
  Widget _obsBuild(LocaleProvider l, WalletConnectService wc) {
    final pad = MediaQuery.paddingOf(context);
    final sessions = wc.sessions;
    final st = ObsidianStyle.of(context);
    final notice = wc.notice;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          const Positioned.fill(child: ObsidianPageScrim()),
          Column(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(24, math.max(52.0, pad.top + 8), 24, 14),
                child: ObsidianPageHeader(
                  title: l.t('wc.title'),
                  backLabel: l.t('obs.back'),
                  trailing: ObsidianHeaderTile(
                    asset: ObsidianIcons.qr,
                    label: l.t('wc.scanConnect'),
                    onTap: _isPairing ? null : _openScanner,
                  ),
                ),
              ),
              Expanded(
                child: ObsidianTopFade(
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(24, 4, 24, 24 + pad.bottom),
                    children: [
                      // ข้อความ + การ์ดที่รอผู้ใช้ตอบขึ้นก่อนการ์ดแนะนำ — มาจากลิงก์ของเว็บบนมือถือ
                      // ต้องเห็นปุ่มอนุมัติ/ปฏิเสธทันทีโดยไม่ต้องเลื่อน (ไม่มีอะไรค้าง = หน้าตาเหมือนเดิม)
                      for (final card in [
                        // แตะข้อความเพื่อปิด
                        if (_error != null)
                          _obsDismissible(
                            l,
                            ObsidianNotice(tone: ObsidianTone.danger, lines: [_error!]),
                            _dismissError,
                          ),
                        if (notice != null)
                          _obsDismissible(
                            l,
                            ObsidianNotice(tone: ObsidianTone.danger, lines: [_noticeText(l, notice)]),
                            wc.clearNotice,
                          ),
                        // เปิดจากลิงก์ของเว็บแล้ว แต่คำขอยังวิ่งทาง relay มาไม่ถึง
                        if (!_isPairing && wc.awaitingBrowserProposal)
                          ObsidianNotice(tone: ObsidianTone.info, icon: Icons.sync_rounded, lines: [l.t('wc.pairing')]),
                        if (wc.awaitingBrowserRequest)
                          ObsidianNotice(
                            tone: ObsidianTone.info,
                            icon: Icons.hourglass_top_rounded,
                            lines: [l.t('wc.waitingRequest')],
                          ),
                        if (wc.hasPendingProposal) _obsProposal(l, wc),
                        if (wc.hasPendingRequest) _obsRequest(l, wc),
                      ]) ...[card, const SizedBox(height: 14)],
                      _obsHero(l),
                      const SizedBox(height: 22),
                      Row(
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(left: 4),
                            child: Text(
                              l.t('wc.activeSessions'),
                              style: st.ui(fontSize: 15, fontWeight: FontWeight.w600, color: ObsidianColors.text),
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (sessions.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: ObsidianColors.success.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(color: ObsidianColors.success.withValues(alpha: 0.35)),
                              ),
                              child: Text(
                                '${sessions.length}',
                                style: st.number(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: ObsidianColors.successSoft,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      if (sessions.isEmpty)
                        _obsEmpty(l)
                      else
                        ObsidianPanel(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Column(children: [for (final s in sessions) _obsSession(s, wc, l)]),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _obsHero(LocaleProvider l) {
    final st = ObsidianStyle.of(context);
    return ObsidianPanel(
      surface: ObsidianCards.hero,
      blur: 16,
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
      child: Column(
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: Color(0x4D22D3EE), blurRadius: 40, spreadRadius: -6)],
            ),
            child: Icon3D(ObsidianIcons.link, size: 76, shadows: [IconDropShadow.tile]),
          ),
          const SizedBox(height: 12),
          Text(
            l.t('obs.wc.heroTitle'),
            textAlign: TextAlign.center,
            style: st.ui(fontSize: 17, fontWeight: FontWeight.w600, color: ObsidianColors.text),
          ),
          const SizedBox(height: 6),
          Text(
            l.t('obs.wc.heroBody'),
            textAlign: TextAlign.center,
            style: st.ui(fontSize: 13, height: 1.55, color: ObsidianColors.textSec),
          ),
          const SizedBox(height: 18),
          ObsidianButton(
            key: const ValueKey('obs-wc-scan'),
            label: l.t('wc.scanConnect'),
            loading: _isPairing,
            loadingLabel: l.t('wc.pairing'),
            onPressed: _isPairing ? null : _openScanner,
          ),
        ],
      ),
    );
  }

  Widget _obsDappIcon(String? url, double size) {
    final placeholder = SizedBox(
      width: size,
      height: size,
      child: Icon3D(ObsidianIcons.link, size: size),
    );
    if (url == null || url.isEmpty) return placeholder;
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.28),
      child: Image.network(url, width: size, height: size, fit: BoxFit.cover, errorBuilder: (_, _, _) => placeholder),
    );
  }

  /// แตะเพื่อปิดข้อความ
  Widget _obsDismissible(LocaleProvider l, Widget child, VoidCallback onDismiss) => GestureDetector(
        onTap: onDismiss,
        child: Semantics(hint: l.t('wc.dismiss'), child: child),
      );

  Widget _obsProposal(LocaleProvider l, WalletConnectService wc) {
    final st = ObsidianStyle.of(context);
    final proposal = wc.pendingProposal!;
    final peer = proposal.params.proposer.metadata;
    final origin = WcOrigin.check(proposal.verifyContext, peer.url);
    final scam = origin.level == WcOriginLevel.scam;
    final locked = _locked(wc);

    final reject = scam
        // เว็บหลอกลวง → ปฏิเสธคือปุ่มหลัก (ปุ่มขาวนูน ป้ายแดง) ส่วนอนุมัติถอยเป็นปุ่มรอง
        ? ObsidianButton(
            label: l.t('wc.reject'),
            height: 52,
            labelColor: ObsidianColors.danger,
            loading: _action == 'rejectProposal',
            onPressed: locked ? null : () => _run('rejectProposal', () => wc.rejectProposal(proposal.id)),
          )
        : ObsidianButton.secondary(
            label: l.t('wc.reject'),
            labelColor: ObsidianColors.dangerSoft,
            loading: _action == 'rejectProposal',
            onPressed: locked ? null : () => _run('rejectProposal', () => wc.rejectProposal(proposal.id)),
          );
    final approve = scam
        ? ObsidianButton.secondary(
            label: l.t('wc.approveAnyway'),
            labelColor: ObsidianColors.textMuted,
            loading: _action == 'approveProposal',
            onPressed: locked ? null : () => _run('approveProposal', () => wc.approveProposal(proposal.id)),
          )
        : ObsidianButton(
            label: l.t('wc.approve'),
            height: 52,
            loading: _action == 'approveProposal',
            onPressed: locked ? null : () => _run('approveProposal', () => wc.approveProposal(proposal.id)),
          );

    return ObsidianPanel(
      surface: origin.isDanger ? ObsidianCards.tinted(ObsidianColors.danger, radius: 22) : ObsidianCards.accent,
      padding: const EdgeInsets.all(18),
      child: Column(
        children: [
          _obsDappIcon(peer.icons.isEmpty ? null : peer.icons.first, 56),
          const SizedBox(height: 12),
          Text(
            peer.name.isEmpty ? l.t('obs.wc.unknownDapp') : peer.name,
            textAlign: TextAlign.center,
            style: st.ui(fontSize: 18, fontWeight: FontWeight.w600, color: ObsidianColors.text),
          ),
          const SizedBox(height: 4),
          // ที่อยู่เว็บเต็ม — ผู้ใช้ต้องเห็นว่าเป็นเว็บที่ตั้งใจเชื่อมจริง
          Text(
            peer.url,
            textAlign: TextAlign.center,
            style: st.mono(fontSize: 12.5, color: ObsidianColors.cyan),
          ),
          const SizedBox(height: 12),
          // ที่มาของเว็บตาม WalletConnect Verify — แดง = อาจเป็นเว็บปลอม (ผู้ใช้ยังตัดสินใจเองได้)
          ObsidianNotice(
            key: ValueKey(origin.isDanger ? 'wc-origin-warning' : 'wc-origin-${origin.level.name}'),
            tone: origin.isDanger
                ? ObsidianTone.danger
                : origin.level == WcOriginLevel.verified
                    ? ObsidianTone.success
                    : ObsidianTone.info,
            icon: origin.isDanger
                ? Icons.gpp_bad_rounded
                : origin.level == WcOriginLevel.verified
                    ? Icons.verified_rounded
                    : Icons.help_outline_rounded,
            lines: [_originText(l, origin)],
            emphasizeFirst: origin.isDanger,
          ),
          const SizedBox(height: 10),
          Text(
            l.t('wc.wantsToConnect'),
            textAlign: TextAlign.center,
            style: st.ui(fontSize: 13, color: ObsidianColors.textSec),
          ),
          const SizedBox(height: 16),
          // ปุ่มหลักอยู่ขวาเสมอ
          Row(
            children: [
              Expanded(child: scam ? approve : reject),
              const SizedBox(width: 10),
              Expanded(child: scam ? reject : approve),
            ],
          ),
        ],
      ),
    );
  }

  Widget _obsRequest(LocaleProvider l, WalletConnectService wc) {
    final st = ObsidianStyle.of(context);
    final request = wc.pendingRequest!;
    final view = wc.pendingRequestView!;
    final from = _requestFrom(l, wc);
    final more = wc.pendingRequestCount - 1;
    final locked = _locked(wc);
    return ObsidianPanel(
      surface: ObsidianCards.tinted(ObsidianColors.orange, radius: 22),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon3D(ObsidianIcons.signHistory, size: 28),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  view.kind == WcRequestKind.other ? l.t('obs.wc.request') : _requestTitle(l, view),
                  style: st.ui(fontSize: 15.5, fontWeight: FontWeight.w600, color: ObsidianColors.text),
                ),
              ),
            ],
          ),
          if (from != null) ...[
            const SizedBox(height: 4),
            Text(from, style: st.ui(fontSize: 12.5, color: ObsidianColors.textSec)),
          ],
          const SizedBox(height: 10),
          CustomPaint(
            painter: ObsidianSurfacePainter(ObsidianSurface.field.copyWith(radius: 14)),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                _requestBody(l, view),
                maxLines: 10,
                overflow: TextOverflow.ellipsis,
                style: st.mono(fontSize: 12, color: ObsidianColors.textSoft, height: 1.5),
              ),
            ),
          ),
          if (more > 0) ...[
            const SizedBox(height: 8),
            Text(
              _DAppConnectScreenState._fill(l.t('wc.moreRequests'), {'n': '$more'}),
              style: st.ui(fontSize: 12, color: ObsidianColors.textMuted),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: ObsidianButton.secondary(
                  label: l.t('wc.reject'),
                  labelColor: ObsidianColors.dangerSoft,
                  loading: _action == 'rejectRequest',
                  onPressed: locked ? null : () => _run('rejectRequest', () => wc.rejectRequest(request.id)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ObsidianButton(
                  label: l.t('wc.confirm'),
                  height: 52,
                  loading: _action == 'approveRequest',
                  onPressed: locked ? null : () => _run('approveRequest', () => wc.approveRequest(request.id)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _obsSession(dynamic session, WalletConnectService wc, LocaleProvider l) {
    final st = ObsidianStyle.of(context);
    final peer = wc.getPeerInfo(session);
    final name = (peer['name'] ?? '').isEmpty ? l.t('obs.wc.unknownDapp') : peer['name']!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 6, 10),
      child: Row(
        children: [
          _obsDappIcon(peer['icon'], 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: st.ui(fontSize: 14.5, fontWeight: FontWeight.w600, color: ObsidianColors.text),
                ),
                Text(
                  peer['url'] ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: st.ui(fontSize: 12, color: ObsidianColors.textMuted),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: l.t('wc.disconnect'),
            icon: const Icon(Icons.link_off_rounded, color: ObsidianColors.dangerSoft, size: 20),
            onPressed: () => _confirmDisconnect(session.topic, peer['name'] ?? '', l, wc),
          ),
        ],
      ),
    );
  }

  Widget _obsEmpty(LocaleProvider l) {
    final st = ObsidianStyle.of(context);
    return ObsidianPanel(
      surface: ObsidianCards.details,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
      child: Column(
        children: [
          const Icon3D(ObsidianIcons.link, size: 52, dimmed: true),
          const SizedBox(height: 10),
          Text(
            l.t('wc.noSessions'),
            style: st.ui(fontSize: 14.5, fontWeight: FontWeight.w500, color: ObsidianColors.textSoft),
          ),
          const SizedBox(height: 4),
          Text(
            l.t('wc.noSessionsDesc'),
            textAlign: TextAlign.center,
            style: st.ui(fontSize: 12.5, height: 1.5, color: ObsidianColors.textMuted),
          ),
        ],
      ),
    );
  }
}
