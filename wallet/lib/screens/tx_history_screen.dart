import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/locale_provider.dart';
import '../core/theme.dart';
import '../models/tx_record.dart';
import '../providers/wallet_provider.dart';
import '../services/wallet_service.dart';
class TxHistoryScreen extends StatefulWidget {
  const TxHistoryScreen({super.key});

  @override
  State<TxHistoryScreen> createState() => _TxHistoryScreenState();
}

class _TxHistoryScreenState extends State<TxHistoryScreen> {
  @override
  void initState() {
    super.initState();
    // Load and scan on open
    final wallet = context.read<WalletProvider>();
    wallet.loadTxHistory();
    wallet.scanTransactions(blockCount: 50);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<LocaleProvider>();
    return Scaffold(
      body: Container(
        decoration: AppColors.of(context).screenBg,
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(l),
              Expanded(
                child: Consumer<WalletProvider>(
                  builder: (_, wallet, __) {
                    if (wallet.isScanning && wallet.txHistory.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const SizedBox(
                              width: 40, height: 40,
                              child: CircularProgressIndicator(color: AppTheme.primary, strokeWidth: 2),
                            ),
                            const SizedBox(height: 16),
                            Text(l.t('tx.scanning'), style: const TextStyle(color: AppTheme.textMuted)),
                          ],
                        ),
                      );
                    }

                    if (wallet.txHistory.isEmpty) {
                      return _buildEmpty(l);
                    }

                    return RefreshIndicator(
                      onRefresh: () => wallet.scanTransactions(blockCount: 50),
                      color: AppTheme.primary,
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        itemCount: wallet.txHistory.length + (wallet.isScanning ? 1 : 0),
                        itemBuilder: (_, index) {
                          if (index == wallet.txHistory.length) {
                            return const Padding(
                              padding: EdgeInsets.all(16),
                              child: Center(
                                child: SizedBox(
                                  width: 20, height: 20,
                                  child: CircularProgressIndicator(color: AppTheme.primary, strokeWidth: 2),
                                ),
                              ),
                            );
                          }
                          return _buildTxItem(wallet.txHistory[index], l);
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(LocaleProvider l) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.t('tx.title'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white)),
              Text(l.t('tx.subtitle'), style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
            ],
          ),
          const Spacer(),
          Consumer<WalletProvider>(
            builder: (_, wallet, __) => IconButton(
              onPressed: wallet.isScanning ? null : () => wallet.scanTransactions(blockCount: 100),
              icon: Icon(
                Icons.refresh,
                color: wallet.isScanning ? AppTheme.textMuted : AppTheme.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty(LocaleProvider l) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.receipt_long_outlined, size: 64, color: AppTheme.textMuted.withValues(alpha: 0.3)),
          const SizedBox(height: 16),
          Text(l.t('tx.empty'), style: const TextStyle(fontSize: 16, color: AppTheme.textMuted)),
          const SizedBox(height: 8),
          Text(l.t('tx.emptyHint'), style: const TextStyle(fontSize: 13, color: AppTheme.textMuted)),
          const SizedBox(height: 24),
          Consumer<WalletProvider>(
            builder: (_, wallet, __) => OutlinedButton.icon(
              onPressed: wallet.isScanning ? null : () => wallet.scanTransactions(blockCount: 200),
              icon: const Icon(Icons.search, color: AppTheme.primary, size: 18),
              label: Text(l.t('tx.scan'), style: const TextStyle(color: AppTheme.primary)),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: AppTheme.primary.withValues(alpha: 0.3)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTxItem(TxRecord tx, LocaleProvider l) {
    final isSent = tx.direction == 'sent';
    final color = isSent ? AppTheme.danger : AppTheme.success;
    final icon = isSent ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded;
    final sign = isSent ? '-' : '+';

    final dateStr = _formatDate(tx);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: glassCard(borderRadius: 16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _showTxDetail(tx, l),
        child: Row(
          children: [
            // TPIX logo with direction badge
            SizedBox(
              width: 46,
              height: 46,
              child: Stack(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: color.withValues(alpha: 0.08),
                    ),
                    child: ClipOval(
                      child: Image.asset('assets/images/logowallet.png', width: 42, height: 42, fit: BoxFit.cover),
                    ),
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: color,
                        border: Border.all(color: AppTheme.bgDark, width: 1.5),
                      ),
                      child: Icon(icon, color: Colors.white, size: 11),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // Address + date
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isSent ? tx.shortTo : tx.shortFrom,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white, fontFamily: 'monospace'),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      if (tx.status == 'pending') ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(4),
                            color: AppTheme.warm.withValues(alpha: 0.15),
                          ),
                          child: Text('Pending', style: TextStyle(fontSize: 9, color: AppTheme.warm, fontWeight: FontWeight.w600)),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Text(dateStr, style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                    ],
                  ),
                ],
              ),
            ),
            // Amount
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '$sign${tx.valueInTPIX.toStringAsFixed(4)}',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: color),
                ),
                const Text('TPIX', style: TextStyle(fontSize: 10, color: AppTheme.textMuted)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(TxRecord tx) {
    DateTime dt;
    if (tx.timestamp != null) {
      dt = DateTime.fromMillisecondsSinceEpoch(tx.timestamp! * 1000);
    } else {
      dt = DateTime.tryParse(tx.createdAt) ?? DateTime.now();
    }
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  void _showTxDetail(TxRecord tx, LocaleProvider l) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(2),
                  color: AppTheme.textMuted.withValues(alpha: 0.3),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                ClipOval(child: Image.asset('assets/images/logowallet.png', width: 28, height: 28, fit: BoxFit.cover)),
                const SizedBox(width: 10),
                Text(l.t('tx.detail'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white)),
              ],
            ),
            const SizedBox(height: 20),
            _detailRow(l.t('tx.hash'), tx.shortHash, onTap: () {
              Clipboard.setData(ClipboardData(text: tx.txHash));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(l.t('home.copied')), backgroundColor: AppTheme.success, duration: const Duration(seconds: 1)),
              );
            }),
            _detailRow(l.t('tx.from'), tx.shortFrom),
            _detailRow(l.t('tx.to'), tx.shortTo),
            _detailRow(l.t('tx.amount'), '${tx.valueInTPIX.toStringAsFixed(6)} TPIX'),
            _detailRow(l.t('tx.status'), tx.status.toUpperCase()),
            if (tx.blockNumber != null)
              _detailRow(l.t('tx.block'), '#${tx.blockNumber}'),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: tx.txHash));
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(l.t('tx.hashCopied')), backgroundColor: AppTheme.success, duration: const Duration(seconds: 1)),
                  );
                },
                icon: const Icon(Icons.copy, size: 16, color: AppTheme.primary),
                label: Text(l.t('tx.copyHash'), style: const TextStyle(color: AppTheme.primary)),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  side: BorderSide(color: AppTheme.primary.withValues(alpha: 0.3)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  final url = Uri.parse('${TpixChain.explorerUrl}/tx/${tx.txHash}');
                  launchUrl(url, mode: LaunchMode.externalApplication);
                  Navigator.pop(context);
                },
                icon: const Icon(Icons.open_in_new, size: 16, color: Colors.white),
                label: Text(l.t('tx.viewExplorer'), style: const TextStyle(color: Colors.white)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value, {VoidCallback? onTap}) {
    final child = Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Text(label, style: const TextStyle(fontSize: 13, color: AppTheme.textMuted)),
          const Spacer(),
          Text(value, style: const TextStyle(fontSize: 13, color: Colors.white, fontFamily: 'monospace')),
          if (onTap != null) ...[
            const SizedBox(width: 4),
            const Icon(Icons.copy, size: 12, color: AppTheme.textMuted),
          ],
        ],
      ),
    );
    return onTap != null ? GestureDetector(onTap: onTap, child: child) : child;
  }
}
