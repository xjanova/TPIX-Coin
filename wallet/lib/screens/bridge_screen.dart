import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../core/locale_provider.dart';
import '../core/theme.dart';
import '../services/bridge_service.dart';
import '../services/fee_service.dart';
import '../services/swap_service.dart';
import '../services/synth_service.dart';
import '../services/wallet_auth_service.dart';
import '../providers/wallet_provider.dart';
import '../widgets/token_selector.dart';

class BridgeScreen extends StatefulWidget {
  const BridgeScreen({super.key});

  @override
  State<BridgeScreen> createState() => _BridgeScreenState();
}

class _BridgeScreenState extends State<BridgeScreen> {
  // Route (loaded from tpix.online fee config)
  List<BridgeRoute> _routes = [];
  BridgeRoute? _route;
  bool _loadingRoutes = true;
  final _amountController = TextEditingController();

  // Fee
  BridgeFee? _fee;
  bool _loadingFee = false;
  Timer? _feeDebounce;

  // Bridge state
  bool _isBridging = false;
  String? _bridgeId;
  BridgeRecord? _bridgeStatus;
  Timer? _statusPollTimer;

  @override
  void initState() {
    super.initState();
    _loadRoutes();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _feeDebounce?.cancel();
    _statusPollTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadRoutes() async {
    final routes = await BridgeService.getRoutes();
    if (mounted) {
      setState(() {
        _routes = routes;
        _route = routes.isNotEmpty ? routes.first : null;
        _loadingRoutes = false;
      });
    }
  }

  void _switchRoute() {
    if (_routes.isEmpty || _route == null) return;
    SynthService.playTap();
    setState(() {
      final idx = _routes.indexOf(_route!);
      _route = _routes[(idx + 1) % _routes.length];
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
    if (_route == null) return;
    final amountStr = _amountController.text.trim();
    final amount = double.tryParse(amountStr);
    if (amount == null || amount <= 0) return;

    setState(() => _loadingFee = true);

    final fee = await BridgeService.getFee(
      sourceChainId: _route!.sourceChain.chainId,
      destChainId: _route!.destChain.chainId,
      token: _route!.tokenSymbol,
      amount: amount,
    );

    if (mounted) {
      setState(() {
        _fee = fee;
        _loadingFee = false;
      });
    }
  }

  Future<void> _executeBridge() async {
    if (_isBridging || _route == null || _fee == null) return;
    final wallet = context.read<WalletProvider>();
    if (wallet.address == null) return;

    final l = context.read<LocaleProvider>();
    final amountStr = _amountController.text.trim();
    final amount = double.tryParse(amountStr);
    if (amount == null || amount < _route!.minAmount) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l.t('bridge.minError')
              .replaceFirst('{amount}', _route!.minAmount.toInt().toString())
              .replaceFirst('{token}', _route!.tokenSymbol)),
          backgroundColor: AppTheme.danger,
        ),
      );
      return;
    }
    if (amount > _route!.maxAmount) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l.t('bridge.maxError')
              .replaceFirst('{amount}', _route!.maxAmount.toInt().toString())
              .replaceFirst('{token}', _route!.tokenSymbol)),
          backgroundColor: AppTheme.danger,
        ),
      );
      return;
    }

    // Fee wallet must be valid
    final feeWallet = _fee!.feeWallet.isNotEmpty ? _fee!.feeWallet : _route!.feeWallet;
    if (!FeeService.isValidFeeWallet(feeWallet)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l.t('bridge.unavailable')),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
      return;
    }

    // Confirm
    final confirmed = await _showConfirmDialog(amount);
    if (confirmed != true || !mounted) return;

    setState(() => _isBridging = true);
    SynthService.playSend();

    try {
      final sourceChain = _route!.sourceChain;
      String sourceTxHash;

      // Convert amount to wei (18 decimals)
      final amountWei = SwapService.parseAmount(amountStr, sourceChain.decimals);

      if (sourceChain.chainId == 4289) {
        // TPIX Chain → send TPIX to bridge wallet (gasless, use existing sendTPIX)
        sourceTxHash = await wallet.sendTPIX(feeWallet, amount);
      } else {
        // External chain (BSC) → send native/token to bridge wallet
        final gasPrice = await SwapService.getGasPrice(sourceChain);
        sourceTxHash = await wallet.sendEvmTransaction(
          rpcUrl: sourceChain.rpcUrl,
          chainId: sourceChain.chainId,
          toAddress: feeWallet,
          value: amountWei,
          gasPrice: gasPrice,
          maxGas: 21000,
        );
      }

      if (!mounted) return;

      // Wait for source chain confirmation
      String? txStatus;
      final rpcUrl = sourceChain.chainId == 4289
          ? 'https://rpc.tpix.online'
          : sourceChain.rpcUrl;
      for (int i = 0; i < 15; i++) {
        await Future.delayed(const Duration(seconds: 2));
        if (!mounted) return;
        txStatus = await wallet.checkEvmTxStatus(rpcUrl, sourceTxHash);
        if (txStatus != null) break;
      }

      if (!mounted) return;

      if (txStatus == 'failed') {
        throw Exception('Source chain transaction failed');
      }

      // Notify bridge API of the deposit (authenticated via wallet signature)
      final direction = BridgeService.directionFromChainIds(
        _route!.sourceChain.chainId,
      );
      final bridgeId = await WalletAuthService.initiateBridge(
        walletAddress: wallet.address!,
        amount: amount,
        direction: direction,
        sourceTxHash: sourceTxHash,
        chainId: _route!.sourceChain.chainId,
        signFn: wallet.signPersonalMessage,
      );

      if (mounted) {
        if (bridgeId != null) {
          // Bridge registered successfully — show status and start polling
          setState(() {
            _bridgeId = bridgeId;
            _bridgeStatus = BridgeRecord(
              bridgeId: bridgeId,
              sourceChainId: _route!.sourceChain.chainId,
              destChainId: _route!.destChain.chainId,
              tokenSymbol: _route!.tokenSymbol,
              amount: amountStr,
              status: txStatus == 'confirmed' ? 'source_confirmed' : 'pending',
              sourceTxHash: sourceTxHash,
            );
            _isBridging = false;
          });
          SynthService.playSendSuccess();
          _startStatusPolling();
        } else {
          // Funds sent but bridge API registration failed
          // Show source tx hash so user can contact support
          setState(() => _isBridging = false);
          SynthService.playError();
          _showBridgeRegistrationFailedDialog(sourceTxHash);
        }
      }
    } catch (e) {
      if (mounted) {
        SynthService.playError();
        final errMsg = e.toString().replaceFirst('Exception: ', '');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${l.t('bridge.failed')}: $errMsg'),
            backgroundColor: AppTheme.danger,
          ),
        );
        setState(() => _isBridging = false);
      }
    }
  }

  void _showBridgeRegistrationFailedDialog(String sourceTxHash) {
    final l = context.read<LocaleProvider>();
    final shortTx = sourceTxHash.length > 16
        ? '${sourceTxHash.substring(0, 10)}...${sourceTxHash.substring(sourceTxHash.length - 6)}'
        : sourceTxHash;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppTheme.warm, size: 28),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                l.t('bridge.registrationFailed'),
                style: const TextStyle(color: AppTheme.warm, fontSize: 16),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.t('bridge.registrationFailedDesc'),
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: Colors.white.withValues(alpha: 0.04),
              ),
              child: Row(
                children: [
                  const Text('TX: ', style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                  Expanded(
                    child: Text(shortTx, style: const TextStyle(fontSize: 12, color: AppTheme.primary, fontFamily: 'monospace')),
                  ),
                  GestureDetector(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: sourceTxHash));
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        SnackBar(content: Text(l.t('tx.hashCopied')), duration: const Duration(seconds: 1)),
                      );
                    },
                    child: const Icon(Icons.copy_rounded, color: AppTheme.textMuted, size: 16),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l.t('swap.done'), style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
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
    final l = context.read<LocaleProvider>();
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          l.t('bridge.confirmTitle'),
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _confirmRow(l.t('bridge.fromChain'), _route!.sourceChain.name),
            _confirmRow(l.t('bridge.toChain'), _route!.destChain.name),
            _confirmRow(l.t('bridge.token'), _route!.tokenSymbol),
            _confirmRow(l.t('bridge.amount'), '${amount.toStringAsFixed(2)} ${_route!.tokenSymbol}'),
            if (_fee != null) ...[
              const Divider(color: AppTheme.textMuted, height: 16),
              _confirmRow(l.t('bridge.fee'), '${_fee!.feeAmount.toStringAsFixed(4)} ${_route!.tokenSymbol} (${_fee!.feePercent}%)'),
              _confirmRow(l.t('bridge.receive'), '${_fee!.receiveAmount.toStringAsFixed(4)} ${_route!.tokenSymbol}'),
              _confirmRow(l.t('bridge.estTime'), '~${_fee!.estimatedTime} min'),
              if (_fee!.feeWallet.isNotEmpty)
                _confirmRow(l.t('bridge.sendTo'), FeeService.shortWallet(_fee!.feeWallet)),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.t('send.cancel'), style: const TextStyle(color: AppTheme.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.t('bridge.button'), style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w700)),
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
          Flexible(
            child: Text(
              value,
              style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
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
              _buildAppBar(l),
              Expanded(
                child: _loadingRoutes
                    ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
                    : _route == null
                        ? Center(
                            child: Text(
                              l.t('bridge.unavailable'),
                              style: const TextStyle(color: AppTheme.textMuted),
                            ),
                          )
                        : SingleChildScrollView(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              children: [
                                _buildRouteCard(),
                                const SizedBox(height: 20),
                                _buildAmountCard(l),
                                const SizedBox(height: 16),
                                if (_loadingFee)
                                  const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 12),
                                    child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary))),
                                  ),
                                if (_fee != null && !_loadingFee) _buildFeeCard(l),
                                if (_fee != null && !_loadingFee) const SizedBox(height: 16),
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
    if (_route == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: [
            _route!.sourceChain.color.withValues(alpha: 0.08),
            _route!.destChain.color.withValues(alpha: 0.08),
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
                ChainLogo(chain: _route!.sourceChain, size: 48),
                const SizedBox(height: 8),
                Text(
                  _route!.sourceChain.shortName,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: _route!.sourceChain.color,
                  ),
                ),
                Text(
                  _route!.sourceChain.name,
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
                ChainLogo(chain: _route!.destChain, size: 48),
                const SizedBox(height: 8),
                Text(
                  _route!.destChain.shortName,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: _route!.destChain.color,
                  ),
                ),
                Text(
                  _route!.destChain.name,
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
    if (_route == null) return const SizedBox.shrink();
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
                '${_route!.tokenSymbol} (${_route!.sourceChain.shortName})',
                style: TextStyle(fontSize: 12, color: _route!.sourceChain.color, fontWeight: FontWeight.w600),
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
                'Min: ${_route!.minAmount.toInt()} ${_route!.tokenSymbol}',
                style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
              ),
              const SizedBox(width: 12),
              Text(
                'Max: ${_route!.maxAmount.toInt()} ${_route!.tokenSymbol}',
                style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFeeCard(LocaleProvider l) {
    if (_fee == null || _route == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: Colors.white.withValues(alpha: 0.03),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        children: [
          _feeRow(l.t('bridge.fee'), '${_fee!.feeAmount.toStringAsFixed(4)} ${_route!.tokenSymbol}'),
          _feeRow(l.t('bridge.feePercent'), '${_fee!.feePercent}%'),
          _feeRow(l.t('bridge.receive'), '${_fee!.receiveAmount.toStringAsFixed(4)} ${_route!.tokenSymbol}'),
          _feeRow(l.t('bridge.estTime'), '~${_fee!.estimatedTime} min'),
          if (_fee!.feeWallet.isNotEmpty)
            _feeRow(l.t('bridge.sendTo'), FeeService.shortWallet(_fee!.feeWallet)),
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
          Flexible(
            child: Text(
              value,
              style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary, fontWeight: FontWeight.w600),
              textAlign: TextAlign.end,
            ),
          ),
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
          _feeRow(l.t('bridge.bridgeId'), status.bridgeId.length > 20
              ? '${status.bridgeId.substring(0, 10)}...${status.bridgeId.substring(status.bridgeId.length - 8)}'
              : status.bridgeId),
          _feeRow(l.t('bridge.amount'), '${status.amount} ${status.tokenSymbol}'),
          if (status.sourceTxHash != null)
            _feeRow(l.t('bridge.sourceTx'), '${status.sourceTxHash!.substring(0, 10)}...'),
          if (status.destTxHash != null)
            _feeRow(l.t('bridge.destTx'), '${status.destTxHash!.substring(0, 10)}...'),

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
    if (_route == null) return const SizedBox.shrink();
    final amountStr = _amountController.text.trim();
    final amount = double.tryParse(amountStr);
    final isValid = amount != null && amount >= _route!.minAmount && amount <= _route!.maxAmount;
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
            ? Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                  const SizedBox(width: 10),
                  Text(l.t('bridge.bridging'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
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
          const SizedBox(height: 8),
          // Fee source badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: AppTheme.primary.withValues(alpha: 0.08),
              border: Border.all(color: AppTheme.primary.withValues(alpha: 0.15)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.verified_rounded, color: AppTheme.primary.withValues(alpha: 0.7), size: 14),
                const SizedBox(width: 6),
                Text(
                  l.t('bridge.feeSource'),
                  style: TextStyle(
                    fontSize: 11,
                    color: AppTheme.primary.withValues(alpha: 0.8),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
