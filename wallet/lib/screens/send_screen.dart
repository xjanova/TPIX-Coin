import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/locale_provider.dart';
import '../core/theme.dart';
import '../providers/wallet_provider.dart';
import '../services/biometric_service.dart';
import '../services/synth_service.dart';
import '../services/wallet_service.dart';
import '../widgets/qr_scanner_screen.dart';

class SendScreen extends StatefulWidget {
  const SendScreen({super.key});

  @override
  State<SendScreen> createState() => _SendScreenState();
}

class _SendScreenState extends State<SendScreen> with SingleTickerProviderStateMixin {
  final _addressController = TextEditingController();
  final _amountController = TextEditingController();
  bool _isSending = false;
  bool _isSent = false;
  String? _txHash;

  late AnimationController _successController;

  @override
  void initState() {
    super.initState();
    _successController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
  }

  @override
  void dispose() {
    _addressController.dispose();
    _amountController.dispose();
    _successController.dispose();
    super.dispose();
  }

  void _scanQR() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => QRScannerScreen(
          titleKey: 'send.scanQR',
          onScanned: (value) {
            final parsed = WalletService.parseAddressFromQR(value);
            if (parsed != null) {
              _addressController.text = parsed;
            } else {
              _showError(context.read<LocaleProvider>().t('send.invalidAddress'));
            }
            Navigator.pop(context);
          },
        ),
      ),
    );
  }

  void _send() async {
    if (_isSending) return; // double-tap guard
    final address = _addressController.text.trim();
    final amount = double.tryParse(_amountController.text.trim());

    final l = context.read<LocaleProvider>();
    if (!WalletService.isValidAddress(address)) {
      _showError(l.t('send.invalidAddress'));
      return;
    }
    if (amount == null || amount <= 0) {
      _showError(l.t('send.invalidAmount'));
      return;
    }

    // Balance check
    final wallet = context.read<WalletProvider>();
    if (amount > wallet.balance) {
      _showError(l.t('send.insufficientBalance'));
      return;
    }

    // Authentication required before send
    final bioService = BiometricService();
    bool authenticated = false;
    if (await bioService.isEnabled() && await bioService.isDeviceSupported()) {
      authenticated = await bioService.authenticate(l.t('send.authRequired'));
    }

    // Fallback: require PIN re-entry if biometric failed or unavailable
    if (!authenticated) {
      if (!mounted) return;
      final pinOk = await _showPinVerification(l);
      if (pinOk != true) return;
    }

    if (!mounted) return;

    // Show confirmation dialog
    final confirmed = await _showConfirmation(address, amount, l);
    if (confirmed != true || !mounted) return;

    setState(() => _isSending = true);
    SynthService.playSend();

    try {
      final txHash = await wallet.sendTPIX(address, amount);
      if (!mounted) return;
      setState(() {
        _isSent = true;
        _txHash = txHash;
        _isSending = false;
      });
      _successController.forward();
      SynthService.playSendSuccess();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSending = false);
      SynthService.playError();
      _showError(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<bool?> _showConfirmation(String address, double amount, LocaleProvider l) {
    return showModalBottomSheet<bool>(
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
            Text(l.t('send.confirmTitle'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white)),
            const SizedBox(height: 20),
            // Recipient
            _confirmRow(l.t('send.confirmTo'), '${address.substring(0, 8)}...${address.substring(address.length - 6)}'),
            // Amount
            _confirmRow(l.t('send.confirmAmount'), '${amount.toStringAsFixed(4)} TPIX'),
            // Gas
            _confirmRow(l.t('send.gasFee').replaceAll(': ', ''), l.t('send.gasFreeVal'), valueColor: AppTheme.success),
            const SizedBox(height: 24),
            // Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(l.t('send.cancel'), style: const TextStyle(color: Colors.white70)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(l.t('send.confirmButton'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<bool?> _showPinVerification(LocaleProvider l) {
    final pinController = TextEditingController();
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(l.t('pin.unlock'), style: const TextStyle(color: Colors.white, fontSize: 16)),
        content: TextField(
          controller: pinController,
          obscureText: true,
          keyboardType: TextInputType.number,
          maxLength: 6,
          autofocus: true,
          style: const TextStyle(color: Colors.white, fontSize: 24, letterSpacing: 8),
          textAlign: TextAlign.center,
          decoration: InputDecoration(
            counterText: '',
            hintText: '••••••',
            hintStyle: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.3)),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppTheme.primary.withValues(alpha: 0.3))),
            focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: AppTheme.primary)),
          ),
          onChanged: (val) async {
            if (val.length == 6) {
              final wallet = context.read<WalletProvider>();
              // Verify PIN by trying unlock (already unlocked, so just check hash)
              final service = WalletService();
              final isLocked = await service.isPinLocked();
              if (isLocked) {
                if (ctx.mounted) Navigator.pop(ctx, false);
                return;
              }
              // Use the provider's existing unlock check
              final success = await wallet.unlock(val);
              if (ctx.mounted) Navigator.pop(ctx, success);
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () {
              pinController.dispose();
              Navigator.pop(ctx, false);
            },
            child: Text(l.t('send.cancel'), style: const TextStyle(color: Colors.grey)),
          ),
        ],
      ),
    ).then((result) {
      pinController.dispose();
      return result;
    });
  }

  Widget _confirmRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Text(label, style: const TextStyle(fontSize: 14, color: AppTheme.textMuted)),
          const Spacer(),
          Text(value, style: TextStyle(fontSize: 14, color: valueColor ?? Colors.white, fontFamily: 'monospace', fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppTheme.danger),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: AppColors.of(context).screenBg,
        child: SafeArea(
          child: Builder(
            builder: (context) {
              final l = context.watch<LocaleProvider>();
              return _isSent ? _buildSuccess(l) : _buildForm(l);
            },
          ),
        ),
      ),
    );
  }

  Widget _buildForm(LocaleProvider l) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
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
                  Text(l.t('send.title'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white)),
                  Text(l.t('send.subtitle'), style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                ],
              ),
            ],
          ),

          const SizedBox(height: 32),

          // To Address
          Text(l.t('send.toAddress'), style: const TextStyle(fontSize: 14, color: AppTheme.textSecondary)),
          const SizedBox(height: 8),
          TextField(
            controller: _addressController,
            style: const TextStyle(color: Colors.white, fontSize: 14, fontFamily: 'monospace'),
            decoration: InputDecoration(
              hintText: '0x...',
              hintStyle: const TextStyle(color: AppTheme.textMuted),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.04),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: AppTheme.primary),
              ),
              suffixIcon: IconButton(
                icon: const Icon(Icons.qr_code_scanner, color: AppTheme.primary),
                onPressed: _scanQR,
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Amount
          Text(l.t('send.amount'), style: const TextStyle(fontSize: 14, color: AppTheme.textSecondary)),
          const SizedBox(height: 8),
          TextField(
            controller: _amountController,
            keyboardType: TextInputType.number,
            style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w700),
            decoration: InputDecoration(
              hintText: '0.00',
              hintStyle: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.5)),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.04),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: AppTheme.primary),
              ),
              suffixText: 'TPIX',
              suffixStyle: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w600),
            ),
          ),

          const SizedBox(height: 12),

          // Balance hint
          Consumer<WalletProvider>(
            builder: (_, wallet, __) => GestureDetector(
              onTap: () => _amountController.text = wallet.balance.toStringAsFixed(4),
              child: Row(
                children: [
                  Text(l.t('send.balance'), style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                  Text('${wallet.formattedBalance} TPIX', style: const TextStyle(fontSize: 12, color: AppTheme.primary, fontWeight: FontWeight.w600)),
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      color: AppTheme.primary.withValues(alpha: 0.1),
                    ),
                    child: const Text('MAX', style: TextStyle(fontSize: 10, color: AppTheme.primary, fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Fee info
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: AppTheme.success.withValues(alpha: 0.06),
              border: Border.all(color: AppTheme.success.withValues(alpha: 0.15)),
            ),
            child: Row(
              children: [
                const Icon(Icons.local_gas_station, color: AppTheme.success, size: 18),
                const SizedBox(width: 8),
                Text(l.t('send.gasFee'), style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
                Text(l.t('send.gasFreeVal'), style: const TextStyle(fontSize: 13, color: AppTheme.success, fontWeight: FontWeight.w700)),
              ],
            ),
          ),

          const Spacer(),

          // Send button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isSending ? null : _send,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: _isSending
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
                        const SizedBox(width: 12),
                        Text(l.t('send.sending'), style: const TextStyle(fontSize: 16, color: Colors.white)),
                      ],
                    )
                  : Text(l.t('send.button'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccess(LocaleProvider l) {
    return Center(
      child: AnimatedBuilder(
        animation: _successController,
        builder: (_, __) {
          final scale = 0.5 + (_successController.value * 0.5);
          final opacity = _successController.value.clamp(0.0, 1.0);
          return Opacity(
            opacity: opacity,
            child: Transform.scale(
              scale: scale,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Success circle with checkmark
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [AppTheme.success, Color(0xFF00E676)],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.success.withValues(alpha: 0.4),
                          blurRadius: 40,
                          spreadRadius: 10,
                        ),
                      ],
                    ),
                    child: const Icon(Icons.check_rounded, color: Colors.white, size: 60),
                  ),

                  const SizedBox(height: 32),

                  Text(l.t('send.success'), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: Colors.white)),
                  const SizedBox(height: 8),
                  Text(l.t('send.confirmed'), style: const TextStyle(fontSize: 16, color: AppTheme.success)),

                  const SizedBox(height: 24),

                  if (_txHash != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: glassCard(borderRadius: 12),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.tag, size: 14, color: AppTheme.textMuted),
                          const SizedBox(width: 6),
                          Text(
                            '${_txHash!.substring(0, 10)}...${_txHash!.substring(_txHash!.length - 8)}',
                            style: const TextStyle(fontSize: 12, color: AppTheme.primary, fontFamily: 'monospace'),
                          ),
                        ],
                      ),
                    ),

                  const SizedBox(height: 40),

                  ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: Text(l.t('send.goBack'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
