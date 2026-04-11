import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../core/locale_provider.dart';
import '../core/theme.dart';
import '../models/chain_config.dart';
import '../services/swap_service.dart';
import '../services/synth_service.dart';
import '../providers/wallet_provider.dart';
import '../widgets/token_selector.dart';

class SwapScreen extends StatefulWidget {
  const SwapScreen({super.key});

  @override
  State<SwapScreen> createState() => _SwapScreenState();
}

class _SwapScreenState extends State<SwapScreen> with SingleTickerProviderStateMixin {
  // Chain & tokens
  ChainConfig _chain = ChainConfig.bsc;
  TokenDef? _tokenIn;
  TokenDef? _tokenOut;

  // Amount
  final _amountController = TextEditingController();
  BigInt? _quoteAmount;
  bool _isQuoting = false;
  Timer? _quoteDebounce;

  // Slippage
  double _slippagePercent = 1.0;

  // Balances
  BigInt _balanceIn = BigInt.zero;
  bool _loadingBalance = false;

  // Swap state
  bool _isSwapping = false;
  bool _isApproving = false;
  BigInt _allowance = BigInt.zero;

  // Animation
  late AnimationController _flipController;

  @override
  void initState() {
    super.initState();
    _flipController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    // Default tokens for BSC
    _tokenIn = _chain.nativeToken;
    _tokenOut = _chain.knownTokens.isNotEmpty ? _chain.knownTokens.first : null;
    _loadBalance();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _quoteDebounce?.cancel();
    _flipController.dispose();
    super.dispose();
  }

  void _onChainChanged(ChainConfig chain) {
    setState(() {
      _chain = chain;
      _tokenIn = chain.nativeToken;
      _tokenOut = chain.knownTokens.isNotEmpty ? chain.knownTokens.first : null;
      _quoteAmount = null;
      _allowance = BigInt.zero;
      _amountController.clear();
    });
    _loadBalance();
    SynthService.playTap();
  }

  Future<void> _loadBalance() async {
    final wallet = context.read<WalletProvider>();
    if (wallet.address == null || _tokenIn == null) return;

    setState(() => _loadingBalance = true);
    try {
      if (_tokenIn!.isNative) {
        _balanceIn = await SwapService.getNativeBalance(_chain, wallet.address!);
      } else {
        _balanceIn = await SwapService.getTokenBalance(
          _chain,
          _tokenIn!.address,
          wallet.address!,
        );
      }
      // Check allowance for ERC-20 tokens
      if (!_tokenIn!.isNative && _chain.dexRouterAddress != null) {
        _allowance = await SwapService.checkAllowance(
          chain: _chain,
          tokenAddress: _tokenIn!.address,
          ownerAddress: wallet.address!,
        );
      }
    } catch (_) {}
    if (mounted) setState(() => _loadingBalance = false);
  }

  void _onAmountChanged(String value) {
    _quoteDebounce?.cancel();
    if (value.isEmpty || _tokenIn == null || _tokenOut == null) {
      setState(() => _quoteAmount = null);
      return;
    }

    _quoteDebounce = Timer(const Duration(milliseconds: 500), () {
      _fetchQuote();
    });
  }

  Future<void> _fetchQuote() async {
    if (_tokenIn == null || _tokenOut == null) return;
    final amountStr = _amountController.text.trim();
    if (amountStr.isEmpty) return;

    final amountIn = SwapService.parseAmount(amountStr, _tokenIn!.decimals);
    if (amountIn <= BigInt.zero) return;

    setState(() => _isQuoting = true);

    final tokenInAddr = _tokenIn!.isNative ? TokenDef.nativeAddress : _tokenIn!.address;
    final tokenOutAddr = _tokenOut!.isNative ? TokenDef.nativeAddress : _tokenOut!.address;

    final quote = await SwapService.getQuote(
      chain: _chain,
      tokenIn: tokenInAddr,
      tokenOut: tokenOutAddr,
      amountIn: amountIn,
    );

    if (mounted) {
      setState(() {
        _quoteAmount = quote;
        _isQuoting = false;
      });
    }
  }

  void _flipTokens() {
    if (_tokenIn == null || _tokenOut == null) return;
    _flipController.forward().then((_) => _flipController.reset());
    SynthService.playTap();
    setState(() {
      final temp = _tokenIn;
      _tokenIn = _tokenOut;
      _tokenOut = temp;
      _quoteAmount = null;
      _amountController.clear();
      _allowance = BigInt.zero;
    });
    _loadBalance();
  }

  Future<void> _selectTokenIn() async {
    final token = await TokenSelectorSheet.show(
      context,
      chain: _chain,
      walletAddress: context.read<WalletProvider>().address,
      excludeAddress: _tokenOut?.address,
    );
    if (token != null && mounted) {
      setState(() {
        _tokenIn = token;
        _quoteAmount = null;
        _allowance = BigInt.zero;
      });
      _loadBalance();
      if (_amountController.text.isNotEmpty) _fetchQuote();
    }
  }

  Future<void> _selectTokenOut() async {
    final token = await TokenSelectorSheet.show(
      context,
      chain: _chain,
      walletAddress: context.read<WalletProvider>().address,
      excludeAddress: _tokenIn?.address,
    );
    if (token != null && mounted) {
      setState(() {
        _tokenOut = token;
        _quoteAmount = null;
      });
      if (_amountController.text.isNotEmpty) _fetchQuote();
    }
  }

  bool get _needsApproval {
    if (_tokenIn == null || _tokenIn!.isNative) return false;
    final amountStr = _amountController.text.trim();
    if (amountStr.isEmpty) return false;
    final amountIn = SwapService.parseAmount(amountStr, _tokenIn!.decimals);
    return _allowance < amountIn;
  }

  Future<void> _approve() async {
    if (_isApproving || _tokenIn == null) return;
    setState(() => _isApproving = true);
    SynthService.playTap();

    // Build approve tx — max uint256
    final maxApproval = BigInt.parse(
      'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff',
      radix: 16,
    );

    // Show "approval sent" — in real implementation, sign and broadcast
    await Future.delayed(const Duration(seconds: 2));

    if (mounted) {
      setState(() {
        _allowance = maxApproval;
        _isApproving = false;
      });
      SynthService.playSendSuccess();
    }
  }

  Future<void> _executeSwap() async {
    if (_isSwapping || _tokenIn == null || _tokenOut == null || _quoteAmount == null) return;

    final amountStr = _amountController.text.trim();
    if (amountStr.isEmpty) return;
    final amountIn = SwapService.parseAmount(amountStr, _tokenIn!.decimals);
    if (amountIn <= BigInt.zero || amountIn > _balanceIn) return;

    // Confirm dialog
    final confirmed = await _showConfirmDialog(amountStr, amountIn);
    if (confirmed != true || !mounted) return;

    setState(() => _isSwapping = true);
    SynthService.playSend();

    try {
      // Build swap data
      final amountOutMin = SwapService.applySlippage(_quoteAmount!, _slippagePercent);
      final wallet = context.read<WalletProvider>();

      final tokenInAddr = _tokenIn!.isNative ? TokenDef.nativeAddress : _tokenIn!.address;
      final tokenOutAddr = _tokenOut!.isNative ? TokenDef.nativeAddress : _tokenOut!.address;

      SwapService.buildSwapData(
        chain: _chain,
        tokenIn: tokenInAddr,
        tokenOut: tokenOutAddr,
        amountIn: amountIn,
        amountOutMin: amountOutMin,
        recipientAddress: wallet.address!,
      );

      // In real implementation: sign tx with wallet private key and broadcast
      // For now: simulate success
      await Future.delayed(const Duration(seconds: 3));

      if (mounted) {
        SynthService.playSendSuccess();
        _showSuccessDialog();
      }
    } catch (e) {
      if (mounted) {
        SynthService.playError();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Swap failed: ${e.toString().replaceFirst('Exception: ', '')}'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSwapping = false);
    }
  }

  Future<bool?> _showConfirmDialog(String amountStr, BigInt amountIn) {
    final outFormatted = _quoteAmount != null
        ? SwapService.formatAmount(_quoteAmount!, _tokenOut!.decimals)
        : 0.0;
    final minOut = _quoteAmount != null
        ? SwapService.formatAmount(
            SwapService.applySlippage(_quoteAmount!, _slippagePercent),
            _tokenOut!.decimals,
          )
        : 0.0;

    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Confirm Swap',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _confirmRow('From', '$amountStr ${_tokenIn!.symbol}'),
            _confirmRow('To (estimated)', '${outFormatted.toStringAsFixed(6)} ${_tokenOut!.symbol}'),
            _confirmRow('Min received', '${minOut.toStringAsFixed(6)} ${_tokenOut!.symbol}'),
            _confirmRow('Slippage', '${_slippagePercent % 1 == 0 ? _slippagePercent.toInt() : _slippagePercent}%'),
            _confirmRow('Network', _chain.name),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: AppTheme.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Swap', style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w700)),
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

  void _showSuccessDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: AppTheme.success, size: 28),
            SizedBox(width: 8),
            Text('Swap Successful!', style: TextStyle(color: AppTheme.success)),
          ],
        ),
        content: const Text(
          'Your swap has been submitted to the network.',
          style: TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop(context);
            },
            child: const Text('Done', style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w700)),
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
                      _buildChainSelector(),
                      const SizedBox(height: 20),
                      _buildFromCard(l),
                      _buildFlipButton(),
                      _buildToCard(l),
                      const SizedBox(height: 16),
                      _buildSlippageSelector(),
                      const SizedBox(height: 16),
                      if (_quoteAmount != null) _buildRateInfo(),
                      const SizedBox(height: 24),
                      _buildSwapButton(l),
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
            l.t('swap.title'),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white),
          ),
          const Spacer(),
          // Settings icon for slippage
          GestureDetector(
            onTap: _showSlippageDialog,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.06),
              ),
              child: const Icon(Icons.tune_rounded, color: AppTheme.textSecondary, size: 18),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChainSelector() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Colors.white.withValues(alpha: 0.04),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: ChainConfig.all.where((c) => c.hasSwap).map((chain) {
          final isActive = chain.chainId == _chain.chainId;
          return Expanded(
            child: GestureDetector(
              onTap: () => _onChainChanged(chain),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: isActive ? chain.color.withValues(alpha: 0.15) : Colors.transparent,
                  border: isActive
                      ? Border.all(color: chain.color.withValues(alpha: 0.3))
                      : null,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ChainLogo(chain: chain, size: 18),
                    const SizedBox(width: 6),
                    Text(
                      chain.shortName,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                        color: isActive ? chain.color : AppTheme.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildFromCard(LocaleProvider l) {
    final formattedBalance = SwapService.formatAmount(_balanceIn, _tokenIn?.decimals ?? 18);

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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(l.t('swap.from'), style: const TextStyle(fontSize: 13, color: AppTheme.textMuted)),
              Row(
                children: [
                  if (_loadingBalance)
                    const Padding(
                      padding: EdgeInsets.only(right: 4),
                      child: SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 1.5, color: AppTheme.textMuted)),
                    ),
                  Text(
                    '${l.t('swap.balance')}: ${formattedBalance.toStringAsFixed(4)}',
                    style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                  ),
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: () {
                      // Reserve gas for native token swaps on non-gasless chains
                      double maxAmount = formattedBalance;
                      if (_tokenIn != null && _tokenIn!.isNative && !_chain.isGasless) {
                        // Reserve ~0.005 native token for gas (covers most swap gas costs)
                        const gasReserve = 0.005;
                        maxAmount = (formattedBalance - gasReserve).clamp(0.0, formattedBalance);
                      }
                      _amountController.text = maxAmount.toStringAsFixed(8);
                      _onAmountChanged(_amountController.text);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(6),
                        color: AppTheme.primary.withValues(alpha: 0.15),
                      ),
                      child: const Text('MAX', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppTheme.primary)),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              // Token selector button
              GestureDetector(
                onTap: _selectTokenIn,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    color: Colors.white.withValues(alpha: 0.06),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_tokenIn != null) ...[
                        TokenLogo(token: _tokenIn!, chain: _chain, size: 28),
                        const SizedBox(width: 8),
                        Text(
                          _tokenIn!.symbol,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white),
                        ),
                      ] else
                        const Text('Select', style: TextStyle(color: AppTheme.textMuted)),
                      const SizedBox(width: 4),
                      const Icon(Icons.keyboard_arrow_down, color: AppTheme.textMuted, size: 20),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Amount input
              Expanded(
                child: TextField(
                  controller: _amountController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$'))],
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: Colors.white),
                  textAlign: TextAlign.right,
                  decoration: InputDecoration(
                    hintText: '0.0',
                    hintStyle: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.3), fontSize: 24, fontWeight: FontWeight.w700),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                  ),
                  onChanged: _onAmountChanged,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFlipButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Center(
        child: GestureDetector(
          onTap: _flipTokens,
          child: RotationTransition(
            turns: Tween(begin: 0.0, end: 0.5).animate(
              CurvedAnimation(parent: _flipController, curve: Curves.easeInOut),
            ),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.bgSurface,
                border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3), width: 2),
                boxShadow: [
                  BoxShadow(color: AppTheme.primary.withValues(alpha: 0.1), blurRadius: 12),
                ],
              ),
              child: const Icon(Icons.swap_vert_rounded, color: AppTheme.primary, size: 22),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildToCard(LocaleProvider l) {
    final outFormatted = _quoteAmount != null && _tokenOut != null
        ? SwapService.formatAmount(_quoteAmount!, _tokenOut!.decimals)
        : null;

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
          Text(l.t('swap.to'), style: const TextStyle(fontSize: 13, color: AppTheme.textMuted)),
          const SizedBox(height: 12),
          Row(
            children: [
              GestureDetector(
                onTap: _selectTokenOut,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    color: Colors.white.withValues(alpha: 0.06),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_tokenOut != null) ...[
                        TokenLogo(token: _tokenOut!, chain: _chain, size: 28),
                        const SizedBox(width: 8),
                        Text(
                          _tokenOut!.symbol,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white),
                        ),
                      ] else
                        const Text('Select', style: TextStyle(color: AppTheme.textMuted)),
                      const SizedBox(width: 4),
                      const Icon(Icons.keyboard_arrow_down, color: AppTheme.textMuted, size: 20),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _isQuoting
                    ? const Align(
                        alignment: Alignment.centerRight,
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary),
                        ),
                      )
                    : Text(
                        outFormatted != null ? outFormatted.toStringAsFixed(6) : '0.0',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: outFormatted != null ? Colors.white : AppTheme.textMuted.withValues(alpha: 0.3),
                        ),
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSlippageSelector() {
    const options = [0.5, 1.0, 3.0];
    return Row(
      children: [
        const Text('Slippage:', style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
        const SizedBox(width: 8),
        ...options.map((s) {
          final isActive = _slippagePercent == s;
          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: GestureDetector(
              onTap: () {
                setState(() => _slippagePercent = s);
                SynthService.playTap();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: isActive ? AppTheme.primary.withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.04),
                  border: Border.all(
                    color: isActive ? AppTheme.primary.withValues(alpha: 0.4) : Colors.white.withValues(alpha: 0.06),
                  ),
                ),
                child: Text(
                  '$s%',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isActive ? AppTheme.primary : AppTheme.textMuted,
                  ),
                ),
              ),
            ),
          );
        }),
        const Spacer(),
        GestureDetector(
          onTap: _showSlippageDialog,
          child: Text(
            'Custom',
            style: TextStyle(
              fontSize: 12,
              color: AppTheme.accent.withValues(alpha: 0.7),
              decoration: TextDecoration.underline,
              decorationColor: AppTheme.accent.withValues(alpha: 0.3),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRateInfo() {
    if (_tokenIn == null || _tokenOut == null || _quoteAmount == null) {
      return const SizedBox.shrink();
    }

    final amountStr = _amountController.text.trim();
    if (amountStr.isEmpty) return const SizedBox.shrink();

    final amountIn = SwapService.parseAmount(amountStr, _tokenIn!.decimals);
    if (amountIn <= BigInt.zero) return const SizedBox.shrink();

    final inDouble = SwapService.formatAmount(amountIn, _tokenIn!.decimals);
    final outDouble = SwapService.formatAmount(_quoteAmount!, _tokenOut!.decimals);
    final rate = inDouble > 0 ? outDouble / inDouble : 0.0;

    final minReceived = SwapService.formatAmount(
      SwapService.applySlippage(_quoteAmount!, _slippagePercent),
      _tokenOut!.decimals,
    );

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: Colors.white.withValues(alpha: 0.03),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        children: [
          _infoRow('Rate', '1 ${_tokenIn!.symbol} = ${rate.toStringAsFixed(6)} ${_tokenOut!.symbol}'),
          _infoRow('Min. received', '${minReceived.toStringAsFixed(6)} ${_tokenOut!.symbol}'),
          _infoRow('Slippage tolerance', '${_slippagePercent % 1 == 0 ? _slippagePercent.toInt() : _slippagePercent}%'),
          _infoRow('Network', _chain.name),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
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

  Widget _buildSwapButton(LocaleProvider l) {
    final amountStr = _amountController.text.trim();
    final hasAmount = amountStr.isNotEmpty;
    final amountIn = hasAmount ? SwapService.parseAmount(amountStr, _tokenIn?.decimals ?? 18) : BigInt.zero;
    final hasQuote = _quoteAmount != null && _quoteAmount! > BigInt.zero;
    final hasSufficientBalance = amountIn <= _balanceIn && amountIn > BigInt.zero;
    final canSwap = hasAmount && hasQuote && hasSufficientBalance && !_isSwapping && !_isApproving;

    String buttonText;
    Color buttonColor;
    VoidCallback? onTap;

    if (!hasAmount) {
      buttonText = l.t('swap.enterAmount');
      buttonColor = AppTheme.textMuted;
      onTap = null;
    } else if (!hasSufficientBalance) {
      buttonText = l.t('swap.insufficient');
      buttonColor = AppTheme.danger;
      onTap = null;
    } else if (_needsApproval) {
      buttonText = _isApproving ? l.t('swap.approving') : '${l.t('swap.approve')} ${_tokenIn!.symbol}';
      buttonColor = AppTheme.accent;
      onTap = _isApproving ? null : _approve;
    } else {
      buttonText = _isSwapping ? l.t('swap.swapping') : l.t('swap.button');
      buttonColor = AppTheme.primary;
      onTap = canSwap ? _executeSwap : null;
    }

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: onTap != null
              ? LinearGradient(colors: [buttonColor, buttonColor.withValues(alpha: 0.8)])
              : null,
          color: onTap == null ? buttonColor.withValues(alpha: 0.15) : null,
          boxShadow: onTap != null
              ? [BoxShadow(color: buttonColor.withValues(alpha: 0.3), blurRadius: 20, offset: const Offset(0, 6))]
              : null,
        ),
        alignment: Alignment.center,
        child: (_isSwapping || _isApproving)
            ? Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    buttonText,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white),
                  ),
                ],
              )
            : Text(
                buttonText,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: onTap != null ? Colors.white : buttonColor.withValues(alpha: 0.5),
                ),
              ),
      ),
    );
  }

  void _showSlippageDialog() {
    final controller = TextEditingController(text: _slippagePercent.toString());
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Slippage Tolerance', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: '0.5 - 50',
            hintStyle: TextStyle(color: AppTheme.textMuted),
            suffixText: '%',
            suffixStyle: TextStyle(color: AppTheme.textSecondary),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: AppTheme.textMuted)),
          ),
          TextButton(
            onPressed: () {
              final val = double.tryParse(controller.text);
              if (val != null && val > 0 && val <= 50) {
                setState(() => _slippagePercent = val);
              }
              Navigator.pop(ctx);
            },
            child: const Text('Set', style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    ).then((_) => controller.dispose()); // Single disposal point after dialog closes
  }
}
