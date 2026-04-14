/// TPIX Wallet — Peer App Card
/// แสดงการ์ด "เปิด TPIX Trade" ถ้าติดตั้งในเครื่อง (หรือ "ติดตั้ง" ถ้ายังไม่มี)
/// ส่ง wallet address ให้ Trade auto-connect
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

class _PeerAppCardState extends State<PeerAppCard> {
  Future<bool>? _installedFuture;

  @override
  void initState() {
    super.initState();
    _installedFuture = PeerApp.isTradeInstalled();
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

    return FutureBuilder<bool>(
      future: _installedFuture,
      builder: (_, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const SizedBox.shrink();
        }

        final installed = snap.data == true;
        final title =
            installed ? l.t('peer.open_trade') : l.t('peer.install_trade');
        final desc = installed
            ? l.t('peer.trade_desc')
            : l.t('peer.install_trade_desc');

        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () {
              if (installed) {
                _open();
              } else {
                PeerApp.openTradeInstallPage();
              }
            },
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
                    child: Icon(
                      installed
                          ? Icons.candlestick_chart_rounded
                          : Icons.download_rounded,
                      color: AppTheme.accent,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: c.text,
                          ),
                        ),
                        Text(
                          desc,
                          style: TextStyle(
                            fontSize: 11,
                            color: c.textSec,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    installed
                        ? Icons.arrow_forward_rounded
                        : Icons.open_in_new_rounded,
                    color: AppTheme.accent,
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
