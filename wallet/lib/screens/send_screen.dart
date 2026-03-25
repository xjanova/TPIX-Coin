import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/theme.dart';
import '../providers/wallet_provider.dart';
import '../services/wallet_service.dart';

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

  void _send() async {
    final address = _addressController.text.trim();
    final amount = double.tryParse(_amountController.text.trim());

    if (address.isEmpty || !address.startsWith('0x') || address.length != 42) {
      _showError('ที่อยู่ไม่ถูกต้อง');
      return;
    }
    if (amount == null || amount <= 0) {
      _showError('จำนวนไม่ถูกต้อง');
      return;
    }

    setState(() => _isSending = true);

    try {
      final wallet = context.read<WalletProvider>();
      final txHash = await wallet.sendTPIX(address, amount);
      setState(() {
        _isSent = true;
        _txHash = txHash;
        _isSending = false;
      });
      _successController.forward();
    } catch (e) {
      setState(() => _isSending = false);
      _showError(e.toString());
    }
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
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.3),
            radius: 1.5,
            colors: [Color(0xFF0F172A), AppTheme.bgDark],
          ),
        ),
        child: SafeArea(
          child: _isSent ? _buildSuccess() : _buildForm(),
        ),
      ),
    );
  }

  Widget _buildForm() {
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
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('ส่ง TPIX', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white)),
                  Text('Send TPIX — Zero Gas Fee', style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                ],
              ),
            ],
          ),

          const SizedBox(height: 32),

          // To Address
          const Text('ที่อยู่ผู้รับ', style: TextStyle(fontSize: 14, color: AppTheme.textSecondary)),
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
                onPressed: () {}, // TODO: QR scanner
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Amount
          const Text('จำนวน', style: TextStyle(fontSize: 14, color: AppTheme.textSecondary)),
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
                  const Text('ยอดคงเหลือ: ', style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
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
            child: const Row(
              children: [
                Icon(Icons.local_gas_station, color: AppTheme.success, size: 18),
                SizedBox(width: 8),
                Text('Gas Fee: ', style: TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
                Text('ฟรี! (0 TPIX)', style: TextStyle(fontSize: 13, color: AppTheme.success, fontWeight: FontWeight.w700)),
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
                  ? const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
                        SizedBox(width: 12),
                        Text('กำลังส่ง...', style: TextStyle(fontSize: 16, color: Colors.white)),
                      ],
                    )
                  : const Text('ส่ง TPIX', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccess() {
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

                  const Text('ส่งสำเร็จ!', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: Colors.white)),
                  const SizedBox(height: 8),
                  const Text('Transaction Confirmed', style: TextStyle(fontSize: 16, color: AppTheme.success)),

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
                    child: const Text('กลับหน้าหลัก', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
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
