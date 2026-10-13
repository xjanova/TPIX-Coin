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
                      _obsHero(l),
                      if (_error != null) ...[
                        const SizedBox(height: 14),
                        ObsidianNotice(tone: ObsidianTone.danger, lines: [_error!]),
                      ],
                      if (wc.hasPendingProposal) ...[const SizedBox(height: 14), _obsProposal(l, wc)],
                      if (wc.hasPendingRequest) ...[const SizedBox(height: 14), _obsRequest(l, wc)],
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

  Widget _obsProposal(LocaleProvider l, WalletConnectService wc) {
    final st = ObsidianStyle.of(context);
    final peer = wc.pendingProposal!.params.proposer.metadata;
    return ObsidianPanel(
      surface: ObsidianCards.accent,
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
          const SizedBox(height: 10),
          Text(
            l.t('wc.wantsToConnect'),
            textAlign: TextAlign.center,
            style: st.ui(fontSize: 13, color: ObsidianColors.textSec),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ObsidianButton.secondary(
                  label: l.t('wc.reject'),
                  labelColor: ObsidianColors.dangerSoft,
                  onPressed: () => wc.rejectProposal(),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ObsidianButton(label: l.t('wc.approve'), height: 52, onPressed: () => wc.approveProposal()),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _obsRequest(LocaleProvider l, WalletConnectService wc) {
    final st = ObsidianStyle.of(context);
    final info = wc.getRequestDisplayInfo();
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
                  info['title'] ?? l.t('obs.wc.request'),
                  style: st.ui(fontSize: 15.5, fontWeight: FontWeight.w600, color: ObsidianColors.text),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          CustomPaint(
            painter: ObsidianSurfacePainter(ObsidianSurface.field.copyWith(radius: 14)),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                info['description'] ?? '',
                maxLines: 6,
                overflow: TextOverflow.ellipsis,
                style: st.mono(fontSize: 12, color: ObsidianColors.textSoft, height: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: ObsidianButton.secondary(
                  label: l.t('wc.reject'),
                  labelColor: ObsidianColors.dangerSoft,
                  onPressed: () => wc.rejectRequest(),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ObsidianButton(label: l.t('wc.confirm'), height: 52, onPressed: () => wc.approveRequest()),
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
