/// TPIX Wallet — Peer App Card
/// แสดงการ์ด "เปิด TPIX Trade" ถ้าติดตั้งในเครื่อง
/// หรือการ์ด "ติดตั้ง TPIX Trade" (เด่น) ถ้ายังไม่ติดตั้ง
/// Re-check อัตโนมัติเมื่อ user กลับเข้าแอพ (หลังไปติดตั้ง)
///
/// Developed by Xman Studio

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/locale_provider.dart';
import '../core/theme.dart';
import '../providers/wallet_provider.dart';
import '../utils/peer_app.dart';

class PeerAppCard extends StatefulWidget {
  const PeerAppCard({super.key});

  @override
  State<PeerAppCard> createState() => _PeerAppCardState();
}

class _PeerAppCardState extends State<PeerAppCard>
    with WidgetsBindingObserver {
  bool? _installed;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // User กลับเข้าแอพ (หลังไปติดตั้ง peer) → re-check
    if (state == AppLifecycleState.resumed) {
      _check(forceRefresh: true);
    }
  }

  Future<void> _check({bool forceRefresh = false}) async {
    if (forceRefresh) PeerApp.clearCache();
    final installed = await PeerApp.isTradeInstalled(forceRefresh: forceRefresh);
    if (mounted) setState(() => _installed = installed);
  }

  Future<void> _open() async {
    final wallet = context.read<WalletProvider>();
    final params = <String, String>{};
    if (wallet.address != null) {
      params['address'] = wallet.address!;
      params['chain'] = wallet.activeChainId.toString();
    }
    await PeerApp.openTrade(
      path: 'connect',
      params: params.isEmpty ? null : params,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<LocaleProvider>();
    final c = AppColors.of(context);

    if (_installed == null) return const SizedBox.shrink();

    return _installed!
        ? _buildInstalledCard(l, c)
        : _buildInstallPromptCard(l, c);
  }

  /// การ์ด installed — compact
  Widget _buildInstalledCard(LocaleProvider l, AppColors c) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: _open,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.accent.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AppTheme.accent.withValues(alpha: 0.3),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppTheme.accent.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.candlestick_chart_rounded,
                    color: AppTheme.accent, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l.t('peer.open_trade'),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: c.text,
                      ),
                    ),
                    Text(
                      l.t('peer.trade_desc'),
                      style: TextStyle(fontSize: 11, color: c.textSec),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_rounded,
                  color: AppTheme.accent, size: 18),
            ],
          ),
        ),
      ),
    );
  }

  /// การ์ด install prompt — prominent
  Widget _buildInstallPromptCard(LocaleProvider l, AppColors c) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppTheme.accent.withValues(alpha: 0.15),
              AppTheme.primary.withValues(alpha: 0.15),
            ],
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: AppTheme.accent.withValues(alpha: 0.4),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: AppTheme.accent.withValues(alpha: 0.15),
              blurRadius: 16,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: PeerApp.openTradeInstallPage,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [AppTheme.accent, AppTheme.primary],
                      ),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.accent.withValues(alpha: 0.4),
                          blurRadius: 12,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: const Icon(Icons.candlestick_chart_rounded,
                        color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l.t('peer.install_trade'),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: c.text,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          l.t('peer.install_trade_desc'),
                          style: TextStyle(fontSize: 11, color: c.textSec),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [AppTheme.accent, AppTheme.primary],
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.download_rounded,
                            color: Colors.white, size: 14),
                        const SizedBox(width: 4),
                        Text(
                          l.t('common.download'),
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
