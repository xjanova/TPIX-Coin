import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../core/locale_provider.dart';
import '../core/theme.dart';
import '../models/token_info.dart';
import '../providers/wallet_provider.dart';
import '../services/db_service.dart';
import '../services/token_service.dart';
import '../services/wallet_service.dart';
import '../widgets/qr_scanner_screen.dart';

class AddTokenScreen extends StatefulWidget {
  const AddTokenScreen({super.key});

  @override
  State<AddTokenScreen> createState() => _AddTokenScreenState();
}

class _AddTokenScreenState extends State<AddTokenScreen> {
  final _controller = TextEditingController();
  bool _isLoading = false;
  bool _isAdding = false;
  TokenInfo? _foundToken;
  String? _errorMsg;
  double? _balance;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _scanQR() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => QRScannerScreen(
          titleKey: 'import.scanQR',
          onScanned: (value) {
            // Parse address from QR (could be ethereum: URI)
            final addr = WalletService.parseAddressFromQR(value) ?? value.trim();
            _controller.text = addr;
            Navigator.pop(context);
            _search();
          },
        ),
      ),
    );
  }

  Future<void> _search() async {
    final input = _controller.text.trim();
    if (input.isEmpty) return;

    // Validate address format
    if (!RegExp(r'^0x[0-9a-fA-F]{40}$').hasMatch(input)) {
      setState(() {
        _errorMsg = context.read<LocaleProvider>().t('token.invalidAddress');
        _foundToken = null;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMsg = null;
      _foundToken = null;
      _balance = null;
    });

    final wallet = context.read<WalletProvider>();
    final slot = wallet.activeSlot;

    // Check if already added
    final exists = await DbService.tokenExists(input, slot);
    if (exists) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMsg = context.read<LocaleProvider>().t('token.alreadyAdded');
        });
      }
      return;
    }

    // Fetch token info from chain
    final token = await TokenService.fetchTokenInfo(input, slot);
    if (!mounted) return;

    if (token == null) {
      setState(() {
        _isLoading = false;
        _errorMsg = context.read<LocaleProvider>().t('token.notFound');
      });
      return;
    }

    // Fetch balance
    double? bal;
    if (wallet.address != null) {
      bal = await TokenService.getFormattedBalance(
        token.contractAddress,
        wallet.address!,
        token.decimals,
      );
    }

    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _foundToken = token;
      _balance = bal;
    });
  }

  Future<void> _addToken() async {
    if (_foundToken == null || _isAdding) return; // double-tap guard
    setState(() => _isAdding = true);

    try {
      await DbService.addToken(_foundToken!);
      if (!mounted) return;

      // Refresh token list in provider
      context.read<WalletProvider>().loadTokens();

      final l = context.read<LocaleProvider>();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${l.t('token.added')} ${_foundToken!.symbol}'),
          backgroundColor: AppTheme.success,
          duration: const Duration(seconds: 2),
        ),
      );
      Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _isAdding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<LocaleProvider>();
    final c = AppColors.of(context);
    return Scaffold(
      body: Container(
        decoration: AppColors.of(context).screenBg,
        child: SafeArea(
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(Icons.arrow_back_ios, color: c.text),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l.t('token.title'), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: c.text)),
                        Text(l.t('token.subtitle'), style: TextStyle(fontSize: 12, color: c.textMuted)),
                      ],
                    ),
                  ],
                ),
              ),

              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 8),

                      // Contract address input
                      Text(l.t('token.contractAddress'), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.textSec)),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _controller,
                              style: TextStyle(color: c.text, fontSize: 14, fontFamily: 'monospace'),
                              decoration: InputDecoration(
                                hintText: '0x...',
                                hintStyle: TextStyle(color: c.textMuted),
                                filled: true,
                                fillColor: c.glassColor,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide(color: c.glassBorder),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide(color: c.glassBorder),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: const BorderSide(color: AppTheme.primary),
                                ),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                                suffixIcon: IconButton(
                                  onPressed: () async {
                                    final data = await Clipboard.getData(Clipboard.kTextPlain);
                                    if (data?.text != null) {
                                      _controller.text = data!.text!.trim();
                                      _search();
                                    }
                                  },
                                  icon: Icon(Icons.paste, color: c.textMuted, size: 20),
                                ),
                              ),
                              onSubmitted: (_) => _search(),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Scan QR button
                          GestureDetector(
                            onTap: _scanQR,
                            child: Container(
                              width: 50,
                              height: 50,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                color: AppTheme.primary.withValues(alpha: 0.12),
                                border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
                              ),
                              child: const Icon(Icons.qr_code_scanner, color: AppTheme.primary, size: 24),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 12),

                      // Search button
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _isLoading ? null : _search,
                          icon: _isLoading
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: AppTheme.primary, strokeWidth: 2))
                              : const Icon(Icons.search, color: AppTheme.primary, size: 18),
                          label: Text(
                            _isLoading ? l.t('token.searching') : l.t('token.search'),
                            style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w600),
                          ),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            side: BorderSide(color: AppTheme.primary.withValues(alpha: 0.3)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                        ),
                      ),

                      const SizedBox(height: 20),

                      // Error message
                      if (_errorMsg != null)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            color: AppTheme.danger.withValues(alpha: 0.08),
                            border: Border.all(color: AppTheme.danger.withValues(alpha: 0.2)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline, color: AppTheme.danger, size: 18),
                              const SizedBox(width: 8),
                              Expanded(child: Text(_errorMsg!, style: const TextStyle(color: AppTheme.danger, fontSize: 13))),
                            ],
                          ),
                        ),

                      // Found token preview
                      if (_foundToken != null) _buildTokenPreview(l, c),

                      const SizedBox(height: 24),

                      // Known tokens section
                      if (_foundToken == null && _errorMsg == null && !_isLoading)
                        _buildHintSection(l, c),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTokenPreview(LocaleProvider l, AppColors c) {
    final token = _foundToken!;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: [AppTheme.primary.withValues(alpha: 0.08), AppTheme.accent.withValues(alpha: 0.04)],
        ),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          // Token icon placeholder
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(colors: [AppTheme.primary.withValues(alpha: 0.3), AppTheme.accent.withValues(alpha: 0.3)]),
            ),
            child: Center(
              child: Text(
                token.symbol.isNotEmpty ? token.symbol[0] : '?',
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Colors.white),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(token.name, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c.text)),
          Text(token.symbol, style: const TextStyle(fontSize: 14, color: AppTheme.primary, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          // Details
          _detailRow(l.t('token.contractAddress'), token.shortAddress, c),
          _detailRow(l.t('token.decimalsLabel'), '${token.decimals}', c),
          if (_balance != null)
            _detailRow(l.t('home.balance'), '${_balance!.toStringAsFixed(4)} ${token.symbol}', c),
          const SizedBox(height: 16),
          // Add button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isAdding ? null : _addToken,
              icon: const Icon(Icons.add_circle_outline, color: Colors.white, size: 20),
              label: Text(l.t('token.add'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value, AppColors c) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: c.textMuted)),
          const Spacer(),
          Text(value, style: TextStyle(fontSize: 12, color: c.text, fontFamily: 'monospace')),
        ],
      ),
    );
  }

  Widget _buildHintSection(LocaleProvider l, AppColors c) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: glassCard(borderRadius: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.info_outline, color: AppTheme.accent, size: 18),
              const SizedBox(width: 8),
              Text(l.t('token.howTo'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.accent)),
            ],
          ),
          const SizedBox(height: 10),
          Text(l.t('token.howToDesc'), style: TextStyle(fontSize: 12, color: c.textSec, height: 1.5)),
        ],
      ),
    );
  }
}
