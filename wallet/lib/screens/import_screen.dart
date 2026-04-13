import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/locale_provider.dart';
import '../core/theme.dart';
import '../providers/wallet_provider.dart';
import '../widgets/qr_scanner_screen.dart';
import 'pin_screen.dart';

class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key});

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  final _controller = TextEditingController();
  final _nameController = TextEditingController();
  bool _isMnemonic = true;

  @override
  void dispose() {
    _controller.dispose();
    _nameController.dispose();
    super.dispose();
  }

  void _scanQR() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => QRScannerScreen(
          titleKey: 'import.scanQR',
          onScanned: (value) {
            _controller.text = value;
            Navigator.pop(context);
          },
        ),
      ),
    );
  }

  void _import() async {
    final input = _controller.text.trim();
    if (input.isEmpty) return;

    final walletName = _nameController.text.trim();
    final l = context.read<LocaleProvider>();
    final provider = context.read<WalletProvider>();
    try {
      if (_isMnemonic) {
        await provider.importFromMnemonic(input, name: walletName.isEmpty ? null : walletName);
      } else {
        await provider.importFromPrivateKey(input, name: walletName.isEmpty ? null : walletName);
      }
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const PinScreen(isSetup: true)),
      );
    } catch (e) {
      if (!mounted) return;
      // Show user-friendly error message
      final msg = e.toString();
      String errorMsg;
      if (msg.contains('Invalid mnemonic')) {
        errorMsg = l.t('import.errorInvalidMnemonic');
      } else if (msg.contains('already exists')) {
        errorMsg = l.t('import.errorDuplicate');
      } else if (_isMnemonic) {
        errorMsg = l.t('import.errorInvalidMnemonic');
      } else {
        errorMsg = l.t('import.errorInvalidKey');
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMsg), backgroundColor: AppTheme.danger),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<LocaleProvider>();
    return Scaffold(
      body: Container(
        decoration: AppColors.of(context).screenBg,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l.t('import.title'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white)),
                        Text(l.t('import.subtitle'), style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                      ],
                    ),
                  ],
                ),

                const SizedBox(height: 32),

                // Toggle
                Container(
                  decoration: glassCard(borderRadius: 14),
                  padding: const EdgeInsets.all(4),
                  child: Row(
                    children: [
                      Expanded(child: _buildTab(l.t('import.tabSeed'), _isMnemonic, () => setState(() => _isMnemonic = true))),
                      Expanded(child: _buildTab(l.t('import.tabKey'), !_isMnemonic, () => setState(() => _isMnemonic = false))),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // Wallet name
                TextField(
                  controller: _nameController,
                  maxLength: 24,
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                  decoration: InputDecoration(
                    hintText: l.t('wallets.namePlaceholder'),
                    hintStyle: const TextStyle(color: AppTheme.textMuted),
                    counterStyle: const TextStyle(color: AppTheme.textMuted, fontSize: 10),
                    prefixIcon: const Icon(Icons.label_outline, color: AppTheme.textMuted, size: 20),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.04),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: AppTheme.primary),
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // Key / Seed input
                TextField(
                  controller: _controller,
                  maxLines: 4,
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                  decoration: InputDecoration(
                    hintText: _isMnemonic ? l.t('import.hintMnemonic') : l.t('import.hintKey'),
                    hintStyle: const TextStyle(color: AppTheme.textMuted),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.04),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: AppTheme.primary),
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Scan QR button
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _scanQR,
                    icon: const Icon(Icons.qr_code_scanner, color: AppTheme.primary),
                    label: Text(l.t('import.scanQR'), style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w600)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: BorderSide(color: AppTheme.primary.withValues(alpha: 0.3)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                ),

                const Spacer(),

                SizedBox(
                  width: double.infinity,
                  child: Consumer<WalletProvider>(
                    builder: (_, provider, __) => ElevatedButton(
                      onPressed: provider.isLoading ? null : _import,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: provider.isLoading
                          ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : Text(l.t('import.button'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTab(String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: active ? AppTheme.primary.withValues(alpha: 0.2) : Colors.transparent,
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: active ? FontWeight.w600 : FontWeight.w400,
            color: active ? AppTheme.primary : AppTheme.textMuted,
          ),
        ),
      ),
    );
  }
}
