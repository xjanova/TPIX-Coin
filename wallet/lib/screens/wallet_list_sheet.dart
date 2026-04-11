import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/locale_provider.dart';
import '../core/theme.dart';
import '../models/wallet_info.dart';
import '../providers/wallet_provider.dart';
import '../services/synth_service.dart';

/// Bottom sheet for managing multiple wallets
class WalletListSheet extends StatelessWidget {
  const WalletListSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const WalletListSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<LocaleProvider>();
    return Consumer<WalletProvider>(
      builder: (context, wallet, _) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        decoration: const BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 8),
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(2),
                  color: AppTheme.textMuted.withValues(alpha: 0.3),
                ),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  Text(l.t('wallets.title'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white)),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      color: AppTheme.primary.withValues(alpha: 0.1),
                    ),
                    child: Text('${wallet.walletCount}/128', style: const TextStyle(fontSize: 11, color: AppTheme.primary, fontWeight: FontWeight.w600)),
                  ),
                  const Spacer(),
                  // Add sub-wallet button (derives from same HD seed)
                  GestureDetector(
                    onTap: wallet.walletCount >= 128 ? null : () => _addWallet(context, l),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        color: AppTheme.primary.withValues(alpha: 0.12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.add, color: AppTheme.primary, size: 16),
                          const SizedBox(width: 4),
                          Text(l.t('wallets.addSub'), style: const TextStyle(fontSize: 12, color: AppTheme.primary, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(color: AppTheme.borderDim, height: 1),
            // Wallet list
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: wallet.wallets.length,
                itemBuilder: (_, index) => _buildWalletItem(
                  context, wallet.wallets[index], wallet, l,
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildWalletItem(BuildContext context, WalletInfo info, WalletProvider wallet, LocaleProvider l) {
    final isActive = info.slot == wallet.activeSlot;
    final shortAddr = '${info.address.substring(0, 6)}...${info.address.substring(info.address.length - 4)}';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: isActive ? AppTheme.primary.withValues(alpha: 0.08) : Colors.transparent,
        border: Border.all(
          color: isActive ? AppTheme.primary.withValues(alpha: 0.25) : AppTheme.borderDim,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: isActive
                ? const LinearGradient(colors: [AppTheme.primary, AppTheme.accent])
                : null,
            color: isActive ? null : AppTheme.bgSurface,
          ),
          alignment: Alignment.center,
          child: Text(
            '${info.slot}',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: isActive ? Colors.white : AppTheme.textMuted,
            ),
          ),
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(
                info.name,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: isActive ? Colors.white : AppTheme.textSecondary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isActive) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  color: AppTheme.success.withValues(alpha: 0.15),
                ),
                child: Text(l.t('wallets.active'), style: const TextStyle(fontSize: 9, color: AppTheme.success, fontWeight: FontWeight.w700)),
              ),
            ],
            if (!info.isHD) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  color: AppTheme.warm.withValues(alpha: 0.15),
                ),
                child: const Text('Imported', style: TextStyle(fontSize: 9, color: AppTheme.warm, fontWeight: FontWeight.w600)),
              ),
            ],
          ],
        ),
        subtitle: Text(
          shortAddr,
          style: const TextStyle(fontSize: 12, color: AppTheme.textMuted, fontFamily: 'monospace'),
        ),
        trailing: PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, color: AppTheme.textMuted, size: 20),
          color: AppTheme.bgSurface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          onSelected: (action) => _handleAction(context, action, info, wallet, l),
          itemBuilder: (_) => [
            PopupMenuItem(
              value: 'rename',
              child: Row(
                children: [
                  const Icon(Icons.edit, size: 18, color: AppTheme.primary),
                  const SizedBox(width: 8),
                  Text(l.t('wallets.rename'), style: const TextStyle(color: Colors.white)),
                ],
              ),
            ),
            if (!isActive)
              PopupMenuItem(
                value: 'switch',
                child: Row(
                  children: [
                    const Icon(Icons.swap_horiz, size: 18, color: AppTheme.accent),
                    const SizedBox(width: 8),
                    Text(l.t('wallets.switch'), style: const TextStyle(color: Colors.white)),
                  ],
                ),
              ),
            if (wallet.walletCount > 1)
              PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    const Icon(Icons.delete_outline, size: 18, color: AppTheme.danger),
                    const SizedBox(width: 8),
                    Text(l.t('wallets.delete'), style: const TextStyle(color: AppTheme.danger)),
                  ],
                ),
              ),
          ],
        ),
        onTap: isActive ? null : () async {
          SynthService.playTap();
          await wallet.switchWallet(info.slot);
          if (context.mounted) Navigator.pop(context);
        },
      ),
    );
  }

  void _handleAction(BuildContext context, String action, WalletInfo info, WalletProvider wallet, LocaleProvider l) {
    switch (action) {
      case 'switch':
        wallet.switchWallet(info.slot);
        Navigator.pop(context);
        break;
      case 'rename':
        _showRenameDialog(context, info, wallet, l);
        break;
      case 'delete':
        _showDeleteDialog(context, info, wallet, l);
        break;
    }
  }

  void _showRenameDialog(BuildContext context, WalletInfo info, WalletProvider wallet, LocaleProvider l) {
    final controller = TextEditingController(text: info.name);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(l.t('wallets.rename'), style: const TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: l.t('wallets.newName'),
            hintStyle: const TextStyle(color: AppTheme.textMuted),
            filled: true,
            fillColor: AppTheme.bgSurface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppTheme.borderDim),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l.t('wallets.cancel'), style: const TextStyle(color: AppTheme.textMuted)),
          ),
          TextButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                wallet.renameWallet(info.slot, name);
              }
              Navigator.pop(ctx);
            },
            child: Text(l.t('wallets.save'), style: const TextStyle(color: AppTheme.primary)),
          ),
        ],
      ),
    );
  }

  void _showDeleteDialog(BuildContext context, WalletInfo info, WalletProvider wallet, LocaleProvider l) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(l.t('wallets.deleteConfirm'), style: const TextStyle(color: AppTheme.danger)),
        content: Text(
          '${l.t('wallets.deleteMsg')}\n\n${info.name}\n${info.address.substring(0, 10)}...',
          style: const TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l.t('wallets.cancel'), style: const TextStyle(color: AppTheme.textMuted)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await wallet.deleteWalletBySlot(info.slot);
              if (context.mounted && wallet.walletCount == 0) {
                Navigator.pop(context); // Close sheet
              }
            },
            child: Text(l.t('wallets.delete'), style: const TextStyle(color: AppTheme.danger)),
          ),
        ],
      ),
    );
  }

  void _addWallet(BuildContext context, LocaleProvider l) async {
    final wallet = context.read<WalletProvider>();
    if (wallet.isLoading) return; // double-tap guard via provider state

    // Ask for wallet name
    final nameController = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(l.t('wallets.nameTitle'), style: const TextStyle(color: Colors.white, fontSize: 18)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l.t('wallets.nameHint'), style: const TextStyle(color: AppTheme.textMuted, fontSize: 13)),
            const SizedBox(height: 16),
            TextField(
              controller: nameController,
              autofocus: true,
              maxLength: 24,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: l.t('wallets.namePlaceholder'),
                hintStyle: const TextStyle(color: AppTheme.textMuted),
                filled: true,
                fillColor: AppTheme.bgSurface,
                counterStyle: const TextStyle(color: AppTheme.textMuted),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppTheme.borderDim),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppTheme.primary),
                ),
              ),
              onSubmitted: (_) => Navigator.pop(ctx, nameController.text.trim()),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: Text(l.t('wallets.cancel'), style: const TextStyle(color: AppTheme.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, nameController.text.trim()),
            child: Text(l.t('wallets.save'), style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    nameController.dispose();
    if (name == null || !context.mounted) return;

    try {
      SynthService.playTap();
      await wallet.addWallet(name: name.isEmpty ? null : name);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l.t('wallets.created')),
            backgroundColor: AppTheme.success,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        final msg = e.toString().replaceFirst('Exception: ', '');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg.contains('Maximum') ? l.t('wallets.maxReached') : l.t('import.errorGeneral')),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    }
  }
}
