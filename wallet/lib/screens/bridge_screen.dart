import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../core/locale_provider.dart';
import '../core/theme.dart';
import '../services/bridge_service.dart';
import '../services/synth_service.dart';
import '../providers/wallet_provider.dart';
import '../widgets/token_selector.dart';

class BridgeScreen extends StatefulWidget {
  const BridgeScreen({super.key});

  @override
  State<BridgeScreen> createState() => _BridgeScreenState();
}

class _BridgeScreenState extends State<BridgeScreen> {
  // Route
  late BridgeRoute _route;
  final _amountController = TextEditingController();

  // Fee
  BridgeFee? _fee;
  Timer? _feeDebounce;

  // Bridge state
  bool _isBridging = false;
  String? _bridgeId;
  BridgeRecord? _bridgeStatus;
  Timer? _statusPollTimer;

  @override
  void initState() {
    super.initState();
    _route = BridgeService.routes.first;
  }

  @override
  void dispose() {
    _amountController.dispose();
    _feeDebounce?.cancel();
    _statusPollTimer?.cancel();
    super.dispose();
  }

  void _switchRoute() {
    SynthService.playTap();
    setState(() {
      // Toggle between routes
      final idx = BridgeService.routes.indexOf(_route);
      _route = BridgeService.routes[(idx + 1) % BridgeService.routes.length];
      _fee = null;
      _amountController.clear();
    });
  }

  void _onAmountChanged(String value) {
    _feeDebounce?.cancel();
    if (value.isEmpty) {
      setState(() => _fee = null);
      return;
    }
    _feeDebounce = Timer(const Duration(milliseconds: 500), () {
      _fetchFee();
    });
  }

  Future<void> _fetchFee() async {
    final amountStr = _amountController.text.trim();
    final amount = double.tryParse(amountStr);
    if (amount == null || amount <= 0) return;

    final fee = await BridgeService.getFee(
      sourceChainId: _route.sourceChain.chainId,
      destChainId: _route.destChain.chainId,
      token: _route.tokenSymbol,
      amount: amount,
    );

    if (mounted) {
      setState(() => _fee = fee);
    }
  }

  Future<void> _executeBridge() async {
    if (_isBridging) return;
    final wallet = context.read<WalletProvider>();
    if (wallet.address == null) return;

    final amountStr = _amountController.text.trim();
    final amount = double.tryParse(amountStr);
    if (amount == null || amount < _route.minAmount) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Minimum amount: ${_route.minAmount.toInt()} ${_route.tokenSymbol}'),
          backgroundColor: AppTheme.danger,
        ),
      );
      return;
    }
    if (amount > _route.maxAmount) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Maximum amount: ${_route.maxAmount.toInt()} ${_route.tokenSymbol}'),
          backgroundColor: AppTheme.danger,
        ),
      );
      return;
    }

    // Confirm
    final confirmed = await _showConfirmDialog(amount);
    if (confirmed != true || !mounted) return;

    setState(() => _isBridging = true);
    SynthService.playSend();

    try {
      // In real implementation: send source chain tx first, then initiate bridge
      // For MVP: simulate source tx, then call bridge API
      await Future.delayed(const Duration(seconds: 2));
      final fakeTxHash = '0x${DateTime.now().millisecondsSinceEpoch.toRadixString(16).padLeft(64, '0')}';

      final bridgeId = await BridgeService.initiateBridge(
        sourceChainId: _route.sourceChain.chainId,
        destChainId: _route.destChain.chainId,
        token: _route.tokenSymbol,
        amount: amount,
        senderAddress: wallet.address!,
        recipientAddress: wallet.address!, // same address on dest chain (EVM)
        sourceTxHash: fakeTxHash,
      );

      if (mounted) {
        setState(() {
          _bridgeId = bridgeId ?? 'bridge_${DateTime.now().millisecondsSinceEpoch}';
          _bridgeStatus = BridgeRecord(
            bridgeId: _bridgeId!,
            sourceChainId: _route.sourceChain.chainId,
            destChainId: _route.destChain.chainId,
            tokenSymbol: _route.tokenSymbol,
            amount: amountStr,
            status: 'pending',
            sourceTxHash: fakeTxHash,
          );
          _isBridging = false;
        });
        SynthService.playSendSuccess();
        _startStatusPolling();
      }
    } catch (e) {
      if (mounted) {
        SynthService.playError();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Bridge failed: ${e.toString().replaceFirst('Exception: ', '')}'),
            backgroundColor: AppTheme.danger,
          ),
        );
        setState(() => _isBridging = false);
      }
    }
  }

  void _startStatusPolling() {
    if (_bridgeId == null) return;
    _statusPollTimer?.cancel();
    int polls = 0;

    _statusPollTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
      polls++;
      if (polls > 60) {
        _statusPollTimer?.cancel();
        return;
      }

      final status = await BridgeService.getStatus(_bridgeId!);
      if (status != null && mounted) {
        setState(() => _bridgeStatus = status);
        if (status.status == 'completed' || status.status == 'failed') {
          _statusPollTimer?.cancel();
          if (status.status == 'completed') {
            SynthService.playReceive();
          }
        }
      }
    });
  }

  Future<bool?> _showConfirmDialog(double amount) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Confirm Bridge',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _confirmRow('From', _route.sourceChain.name),
            _confirmRow('To', _route.destChain.name),
            _confirmRow('Token', _route.tokenSymbol),
            _confirmRow('Amount', '${amount.toStringAsFixed(2)} ${_route.tokenSymbol}'),
            if (_fee != null) ...[
              _confirmRow('Fee', '${_fee!.feeAmount.toStringAsFixed(4)} ${_route.tokenSymbol}'),
              _confirmRow('You receive', '${_fee!.receiveAmount.toStringAsFixed(4)} ${_route.tokenSymbol}'),
              _confirmRow('Est. time', '~${_fee!.estimatedTime} min'),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: AppTheme.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Bridge', style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Widget _confirmRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: AppTheme.textMuted, fontSize: 13)),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<LocaleProvider>();

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.5),
            radius: 1.5,
            colors: [Color(0xFF0C1929), AppTheme.bgDark],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildAppBar(l),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      _buildRouteCard(),
                      const SizedBox(height: 20),
                      _buildAmountCard(l),
                      const SizedBox(height: 16),
                      if (_fee != null) _buildFeeCard(l),
                      if (_fee != null) const SizedBox(height: 16),
                      if (_bridgeStatus != null) ...[
                        _buildStatusCard(l),
                        const SizedBox(height: 16),
                      ],
                      if (_bridgeStatus == null) _buildBridgeButton(l),
                      const SizedBox(height: 24),
                      _buildInfoSection(l),
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

  Widget _buildAppBar(LocaleProvider l) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.06),
              ),
              child: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 20),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            l.t('bridge.title'),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildRouteCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: [
            _route.sourceChain.color.withValues(alpha: 0.08),
            _route.destChain.color.withValues(alpha: 0.08),
          ],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          // Source chain
          Expanded(
            child: Column(
              children: [
                ChainLogo(chain: _route.sourceChain, size: 48),
                const SizedBox(height: 8),
                Text(
                  _route.sourceChain.shortName,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: _route.sourceChain.color,
                  ),
                ),
                Text(
                  _route.sourceChain.name,
                  style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),

          // Arrow with flip
          GestureDetector(
            onTap: _switchRoute,
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.bgSurface,
                border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3), width: 2),
                boxShadow: [
                  BoxShadow(color: AppTheme.primary.withValues(alpha: 0.1), blurRadius: 12),
                ],
              ),
              child: const Icon(Icons.swap_horiz_rounded, color: AppTheme.primary, size: 24),
            ),
          ),

          // Dest chain
          Expanded(
            child: Column(
              children: [
                ChainLogo(chain: _route.destChain, size: 48),
                const SizedBox(height: 8),
                Text(
                  _route.destChain.shortName,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: _route.destChain.color,
                  ),
                ),
                Text(
                  _route.destChain.name,
                  style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAmountCard(LocaleProvider l) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: Colors.white.withValues(alpha: 0.04),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(l.t('bridge.amount'), style: const TextStyle(fontSize: 13, color: AppTheme.textMuted)),
              const Spacer(),
              Text(
                '${_route.tokenSymbol} (${_route.sourceChain.shortName})',
                style: TextStyle(fontSize: 12, color: _route.sourceChain.color, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$'))],
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: Colors.white),
            decoration: InputDecoration(
              hintText: '0.0',
              hintStyle: TextStyle(
                color: AppTheme.textMuted.withValues(alpha: 0.3),
                fontSize: 28,
                fontWeight: FontWeight.w700,
              ),
              border: InputBorder.none,
              contentPadding: EdgeInsets.zero,
            ),
            onChanged: _onAmountChanged,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                'Min: ${_route.minAmount.toInt()} ${_route.tokenSymbol}',
                style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
              ),
              const SizedBox(width: 12),
              Text(
                'Max: ${_route.maxAmount.toInt()} ${_route.tokenSymbol}',
                style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFeeCard(LocaleProvider l) {
    if (_fee == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: Colors.white.withValues(alpha: 0.03),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        children: [
          _feeRow(l.t('bridge.fee'), '${_fee!.feeAmount.toStringAsFixed(4)} ${_route.tokenSymbol}'),
          _feeRow(l.t('bridge.receive'), '${_fee!.receiveAmount.toStringAsFixed(4)} ${_route.tokenSymbol}'),
          _feeRow(l.t('bridge.estTime'), '~${_fee!.estimatedTime} min'),
          _feeRow(l.t('bridge.feePercent'), '${_route.fee}%'),
        ],
      ),
    );
  }

  Widget _feeRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
          Text(value, style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildStatusCard(LocaleProvider l) {
    if (_bridgeStatus == null) return const SizedBox.shrink();

    final status = _bridgeStatus!;
    Color statusColor;
    IconData statusIcon;

    switch (status.status) {
      case 'completed':
        statusColor = AppTheme.success;
        statusIcon = Icons.check_circle;
        break;
      case 'failed':
        statusColor = AppTheme.danger;
        statusIcon = Icons.error;
        break;
      case 'processing':
        statusColor = AppTheme.warm;
        statusIcon = Icons.autorenew;
        break;
      default:
        statusColor = AppTheme.primary;
        statusIcon = Icons.hourglass_bottom;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: statusColor.withValues(alpha: 0.08),
        border: Border.all(color: statusColor.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(statusIcon, color: statusColor, size: 24),
              const SizedBox(width: 10),
              Text(
                l.t('bridge.status'),
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: statusColor.withValues(alpha: 0.2),
                ),
                child: Text(
                  status.statusDisplay,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: statusColor),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _feeRow('Bridge ID', status.bridgeId.length > 20
              ? '${status.bridgeId.substring(0, 10)}...${status.bridgeId.substring(status.bridgeId.length - 8)}'
              : status.bridgeId),
          _feeRow('Amount', '${status.amount} ${status.tokenSymbol}'),
          if (status.sourceTxHash != null)
            _feeRow('Source TX', '${status.sourceTxHash!.substring(0, 10)}...'),
          if (status.destTxHash != null)
            _feeRow('Dest TX', '${status.destTxHash!.substring(0, 10)}...'),

          if (status.status != 'completed' && status.status != 'failed') ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: statusColor),
                ),
                const SizedBox(width: 8),
                Text(
                  l.t('bridge.monitoring'),
                  style: TextStyle(fontSize: 12, color: statusColor),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBridgeButton(LocaleProvider l) {
    final amountStr = _amountController.text.trim();
    final amount = double.tryParse(amountStr);
    final isValid = amount != null && amount >= _route.minAmount && amount <= _route.maxAmount;
    final canBridge = isValid && !_isBridging;

    return GestureDetector(
      onTap: canBridge ? _executeBridge : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: canBridge
              ? const LinearGradient(colors: [AppTheme.primary, AppTheme.accent])
              : null,
          color: canBridge ? null : AppTheme.textMuted.withValues(alpha: 0.15),
          boxShadow: canBridge
              ? [BoxShadow(color: AppTheme.primary.withValues(alpha: 0.3), blurRadius: 20, offset: const Offset(0, 6))]
              : null,
        ),
        alignment: Alignment.center,
        child: _isBridging
            ? const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                  SizedBox(width: 10),
                  Text('Bridging...', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
                ],
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.account_tree_rounded, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    l.t('bridge.button'),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: canBridge ? Colors.white : AppTheme.textMuted.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildInfoSection(LocaleProvider l) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: AppTheme.accent.withValues(alpha: 0.05),
        border: Border.all(color: AppTheme.accent.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, color: AppTheme.accent.withValues(alpha: 0.7), size: 18),
              const SizedBox(width: 8),
              Text(
                l.t('bridge.howItWorks'),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.accent.withValues(alpha: 0.8),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            l.t('bridge.howItWorksDesc'),
            style: TextStyle(
              fontSize: 12,
              color: AppTheme.textMuted.withValues(alpha: 0.7),
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
