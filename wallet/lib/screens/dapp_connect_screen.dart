import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tpix_wallet/core/locale_provider.dart';
import 'package:tpix_wallet/core/theme.dart';
import 'package:tpix_wallet/services/walletconnect_service.dart';
import 'package:tpix_wallet/widgets/qr_scanner_screen.dart';

/// Screen for managing WalletConnect dApp connections.
///
/// Entry points:
/// 1. Home screen "Connect" action button → opens QR scanner
/// 2. Deep link wc: URI → auto-pairs and shows approval dialog
/// 3. Settings → shows active sessions list
class DAppConnectScreen extends StatefulWidget {
  /// If provided, auto-pair with this WC URI (from deep link or direct input).
  final String? initialUri;

  const DAppConnectScreen({super.key, this.initialUri});

  @override
  State<DAppConnectScreen> createState() => _DAppConnectScreenState();
}

class _DAppConnectScreenState extends State<DAppConnectScreen> {
  bool _isPairing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.initialUri != null) {
      _pairWithUri(widget.initialUri!);
    }
  }

  Future<void> _pairWithUri(String uri) async {
    final wc = context.read<WalletConnectService>();
    setState(() {
      _isPairing = true;
      _error = null;
    });

    try {
      await wc.pair(uri);
      // Proposal will arrive via onProposalReceived callback
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() => _isPairing = false);
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
              _pairWithUri(value);
            } else {
              setState(() {
                _error = 'Invalid QR code. Please scan a WalletConnect QR code.';
              });
            }
          },
          titleKey: 'wc.scanTitle',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<LocaleProvider>();
    final wc = context.watch<WalletConnectService>();
    final activeSessions = wc.sessions;

    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          l.t('wc.title'),
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Scan QR Button
              _buildScanButton(l),
              const SizedBox(height: 8),

              // Error message
              if (_error != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.danger.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.danger.withOpacity(0.3)),
                  ),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: AppTheme.danger, fontSize: 13),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Pairing indicator
              if (_isPairing) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.primary.withOpacity(0.2)),
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
                      const SizedBox(width: 12),
                      Text(
                        l.t('wc.pairing'),
                        style: const TextStyle(color: AppTheme.primary, fontSize: 14),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Pending Proposal
              if (wc.hasPendingProposal) ...[
                _buildProposalCard(l, wc),
                const SizedBox(height: 16),
              ],

              // Pending Request
              if (wc.hasPendingRequest) ...[
                _buildRequestCard(l, wc),
                const SizedBox(height: 16),
              ],

              // Active Sessions
              Text(
                l.t('wc.activeSessions'),
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: activeSessions.isEmpty
                    ? _buildEmptyState(l)
                    : ListView.separated(
                        itemCount: activeSessions.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, i) =>
                            _buildSessionCard(activeSessions[i], wc, l),
                      ),
              ),
            ],
          ),
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
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: AppTheme.primary.withOpacity(0.3),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.qr_code_scanner_rounded, color: Colors.white, size: 24),
            const SizedBox(width: 10),
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

  Widget _buildProposalCard(LocaleProvider l, WalletConnectService wc) {
    final proposal = wc.pendingProposal!;
    final peer = proposal.params.proposer.metadata;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.primary.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primary.withOpacity(0.1),
            blurRadius: 20,
          ),
        ],
      ),
      child: Column(
        children: [
          // dApp icon
          if (peer.icons.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                peer.icons.first,
                width: 48,
                height: 48,
                errorBuilder: (_, __, ___) => Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.language, color: AppTheme.primary),
                ),
              ),
            ),
          const SizedBox(height: 12),
          Text(
            peer.name,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            peer.url,
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            l.t('wc.wantsToConnect'),
            style: const TextStyle(color: AppTheme.textMuted, fontSize: 13),
          ),
          const SizedBox(height: 16),
          // Approve / Reject buttons
          Row(
            children: [
              Expanded(
                child: _actionButton(
                  label: l.t('wc.reject'),
                  color: AppTheme.danger,
                  onTap: () => wc.rejectProposal(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _actionButton(
                  label: l.t('wc.approve'),
                  color: AppTheme.success,
                  filled: true,
                  onTap: () => wc.approveProposal(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRequestCard(LocaleProvider l, WalletConnectService wc) {
    final info = wc.getRequestDisplayInfo();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.warm.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.edit_note_rounded, color: AppTheme.warm, size: 20),
              const SizedBox(width: 8),
              Text(
                info['title'] ?? 'Request',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.bgDark,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              info['description'] ?? '',
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 12,
                fontFamily: 'monospace',
              ),
              maxLines: 6,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _actionButton(
                  label: l.t('wc.reject'),
                  color: AppTheme.danger,
                  onTap: () => wc.rejectRequest(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _actionButton(
                  label: l.t('wc.confirm'),
                  color: AppTheme.success,
                  filled: true,
                  onTap: () => wc.approveRequest(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSessionCard(dynamic session, WalletConnectService wc, LocaleProvider l) {
    final peer = wc.getPeerInfo(session);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.borderDim),
      ),
      child: Row(
        children: [
          // dApp icon
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: peer['icon']!.isNotEmpty
                ? Image.network(
                    peer['icon']!,
                    width: 40,
                    height: 40,
                    errorBuilder: (_, __, ___) => _iconPlaceholder(),
                  )
                : _iconPlaceholder(),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  peer['name'] ?? 'Unknown dApp',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  peer['url'] ?? '',
                  style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
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
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.link_off_rounded, size: 48, color: AppTheme.textMuted.withOpacity(0.4)),
          const SizedBox(height: 12),
          Text(
            l.t('wc.noSessions'),
            style: const TextStyle(color: AppTheme.textMuted, fontSize: 14),
          ),
          const SizedBox(height: 4),
          Text(
            l.t('wc.noSessionsDesc'),
            style: TextStyle(color: AppTheme.textMuted.withOpacity(0.6), fontSize: 12),
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
        color: AppTheme.primary.withOpacity(0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Icon(Icons.language, color: AppTheme.primary, size: 20),
    );
  }

  Widget _actionButton({
    required String label,
    required Color color,
    required VoidCallback onTap,
    bool filled = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: filled ? color : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.5)),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: filled ? Colors.white : color,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  void _confirmDisconnect(String topic, String name, LocaleProvider l, WalletConnectService wc) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(l.t('wc.disconnectTitle'), style: const TextStyle(color: Colors.white)),
        content: Text(
          '${l.t('wc.disconnectMsg')} $name?',
          style: const TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l.t('common.cancel'), style: const TextStyle(color: AppTheme.textMuted)),
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
