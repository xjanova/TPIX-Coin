import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/themes/tokens.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../core/locale_provider.dart';
import '../core/theme.dart';
import '../core/themes/theme_bundle.dart';
import '../core/themes/widgets/screen_background.dart';
import '../models/chain_config.dart';
import '../services/fee_service.dart';
import '../services/rpc_client.dart';
import '../services/swap_service.dart';
import '../services/synth_service.dart';
import '../services/tpix_dex_service.dart';
import '../services/wallet_auth_service.dart';
import '../services/wallet_service.dart' show InsufficientGasException, WalletChangedException;
import '../providers/tpix_swap_controller.dart';
import '../providers/wallet_provider.dart';
import '../utils/units.dart';
import '../widgets/obsidian/obsidian.dart';
import '../widgets/token_selector.dart';

// หน้าแลกธีม Obsidian (ใช้สถานะ/ตัวจัดการเดิมของหน้านี้ร่วมกัน)
part 'swap_obsidian.dart';

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

  /// เลขรอบของการขอราคา — เพิ่มทุกครั้งที่อินพุตเปลี่ยนหรือเริ่มขอรอบใหม่
  /// ผลที่กลับมาพร้อมเลขเก่า = ราคาของจำนวน/เหรียญ/เชนชุดเดิม → ทิ้ง (เน็ตช้าตอบสลับลำดับได้)
  int _quoteRequestId = 0;

  // Slippage
  double _slippagePercent = 1.0;

  // Balances
  BigInt _balanceIn = BigInt.zero;
  bool _loadingBalance = false;

  /// เลขรอบของการโหลดยอด + allowance — สลับเชน/เหรียญระหว่างรอ ผลของเหรียญเก่าห้ามทับของใหม่
  int _balanceRequestId = 0;

  // Swap state
  bool _isSwapping = false;
  bool _isApproving = false;
  BigInt _allowance = BigInt.zero;

  /// กำลังอนุมัติ/แลก — ธุรกรรมที่รอผลอ้างอิงเชน/เหรียญ/จำนวนชุดนี้ ห้ามแก้อินพุตกลางทาง
  bool get _busy => _isSwapping || _isApproving;

  // Platform fee from tpix.online
  SwapFeeConfig _swapFee = SwapFeeConfig.fallback();
  bool _loadingFeeConfig = true;

  // Animation
  late AnimationController _flipController;

  // ── ธีม Obsidian (หน้าตาอย่างเดียว — กฎการแลกใช้ของเดิมทั้งหมด) ──
  static const _obsRefreshSeconds = 15;

  /// จำนวนครั้งที่สลับทิศ (ลูกแก้วหมุนทีละ 180°)
  int _obsFlips = 0;

  /// ตำแหน่งรอยต่อระหว่างการ์ดจ่าย/ได้รับ — ลูกแก้วลอยทับตรงนี้
  final LayerLink _obsOrbLink = LayerLink();

  /// นับถอยหลังขอราคาใหม่ (วินาทีที่เหลือ)
  final ValueNotifier<int> _obsRefreshLeft = ValueNotifier(_obsRefreshSeconds);
  Timer? _obsRefreshTimer;

  /// กำลังขอราคารอบอัตโนมัติ (แยกจาก _isQuoting — ตัวเลขเดิมยังโชว์อยู่)
  bool _obsRefreshing = false;

  bool get _isObsidian => TpixThemeExtension.of(context).themeId == ThemeId.obsidian;

  void _obsSet(VoidCallback fn) => setState(fn);

  // ── โหมด TPIX Chain (TPIX DEX) — ตรรกะทั้งหมดอยู่ใน TpixSwapController ทุกธีมใช้ร่วมกัน ──
  late final TpixSwapController _tpix;

  /// กันกดซ้ำตั้งแต่แตะครั้งแรก (ก่อนกล่องยืนยันขึ้น / ระหว่างขอราคาใหม่)
  bool _tpixTapBusy = false;

  bool get _isTpix => _chain.chainId == ChainConfig.tpix.chainId;

  /// ระหว่างอนุมัติ/สวอป (ทุกเครือข่าย) ห้ามสลับเชนหรือแก้อินพุต — ธุรกรรมกับผลที่รออยู่ต้องเป็นของชุดเดิม
  bool get _networkLocked => _busy || _tpix.busy || _tpixTapBusy;

  @override
  void initState() {
    super.initState();
    _flipController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    final wallet = context.read<WalletProvider>();
    _tpix = TpixSwapController(wallet: wallet)..addListener(_onTpixChanged);
    // เปิดจากเชน TPIX → เริ่มที่ TPIX Chain (ยังไม่พร้อม = บอกเหตุผล + ปุ่มไปสวอปบน BSC)
    if (wallet.activeChainId == ChainConfig.tpix.chainId) _chain = ChainConfig.tpix;
    // Default tokens for BSC
    final evmChain = _isTpix ? ChainConfig.bsc : _chain;
    _tokenIn = evmChain.nativeToken;
    _tokenOut = evmChain.knownTokens.isNotEmpty ? evmChain.knownTokens.first : null;
    _loadBalance();
    _loadFeeConfig();
    _tpix.load();
  }

  void _onTpixChanged() {
    if (!mounted) return;
    // ตัวควบคุมล้างจำนวนเอง (สลับฝั่ง / สวอปเสร็จ) — ช่องกรอกต้องตามให้ตรง
    if (_isTpix && _amountController.text != _tpix.amountText) {
      _amountController.text = _tpix.amountText;
    }
    setState(() {});
  }

  Future<void> _loadFeeConfig() async {
    final fee = await FeeService.getSwapFee();
    if (mounted) {
      setState(() {
        _swapFee = fee;
        _loadingFeeConfig = false;
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // ธีม Obsidian นับถอยหลังแล้วขอราคาใหม่ทุก 15 วิ — ธีมอื่นทำงานเหมือนเดิม (ไม่มีตัวจับเวลา)
    if (_isObsidian) {
      _obsRefreshTimer ??= Timer.periodic(const Duration(seconds: 1), (_) => _obsRefreshTick());
    } else {
      _obsRefreshTimer?.cancel();
      _obsRefreshTimer = null;
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _quoteDebounce?.cancel();
    _flipController.dispose();
    _obsRefreshTimer?.cancel();
    _obsRefreshLeft.dispose();
    _tpix.removeListener(_onTpixChanged);
    _tpix.dispose();
    super.dispose();
  }

  /// อินพุตเปลี่ยน (จำนวน/เหรียญ/เชน/ทิศ) → ราคาที่มีอยู่เป็นของอินพุตเก่า: ล้างทิ้งทันที
  /// พร้อมยกเลิก debounce และทิ้งผลที่ยังค้างกลางทาง — ปุ่มแลกปิดจนกว่าราคาของอินพุตใหม่มาถึง
  /// (ไม่งั้นกดแลกได้ทั้งที่กล่องยืนยัน/amountOutMin คิดจากราคาของจำนวนเก่า) · เรียกภายใน setState
  void _invalidateQuote() {
    _quoteDebounce?.cancel();
    _quoteRequestId++;
    _quoteAmount = null;
    _isQuoting = false;
  }

  void _onChainChanged(ChainConfig chain) {
    if (_networkLocked) return; // ธุรกรรมที่รอผลอยู่อ้างอิงเชนเดิม — ห้ามสลับกลางทาง
    setState(() {
      _chain = chain;
      if (!_isTpix) {
        _tokenIn = chain.nativeToken;
        _tokenOut = chain.knownTokens.isNotEmpty ? chain.knownTokens.first : null;
      }
      _invalidateQuote();
      _allowance = BigInt.zero;
      _amountController.clear();
    });
    if (_isTpix) {
      _tpix.setAmount('');
      // เคยปิด/ติดต่อไม่ได้ → ถามทะเบียนใหม่ทุกครั้งที่ผู้ใช้กลับมาที่แท็บนี้
      if (_tpix.phase == TpixSwapPhase.ready) {
        _tpix.refreshBalance();
      } else if (_tpix.phase != TpixSwapPhase.loading) {
        _tpix.load(force: true);
      }
    } else {
      _loadBalance();
    }
    SynthService.playTap();
  }

  Future<void> _loadBalance() async {
    if (_isTpix) return; // โหมด TPIX Chain อ่านยอดผ่าน TpixSwapController
    final address = context.read<WalletProvider>().address;
    final tokenIn = _tokenIn;
    final chain = _chain;
    if (address == null || tokenIn == null) return;

    // รอบล่าสุดเท่านั้นที่เขียนผลได้ — สลับเชน/เหรียญระหว่างรอ ผลของเหรียญเก่าถูกทิ้ง
    final requestId = ++_balanceRequestId;
    setState(() => _loadingBalance = true);
    BigInt? balance;
    BigInt? allowance;
    try {
      balance = tokenIn.isNative
          ? await SwapService.getNativeBalance(chain, address)
          : await SwapService.getTokenBalance(chain, tokenIn.address, address);
      // Check allowance for ERC-20 tokens
      if (!tokenIn.isNative && chain.dexRouterAddress != null) {
        allowance = await SwapService.checkAllowance(
          chain: chain,
          tokenAddress: tokenIn.address,
          ownerAddress: address,
        );
      }
    } catch (_) {}
    if (!mounted) return;
    if (requestId != _balanceRequestId) return; // รอบใหม่กว่าจะปิดสถานะโหลดเอง
    setState(() {
      // ดึงไม่ได้ → คงค่าเดิม (ห้ามทับด้วย 0)
      if (balance != null) _balanceIn = balance;
      if (allowance != null) _allowance = allowance;
      _loadingBalance = false;
    });
  }

  void _onAmountChanged(String value) {
    // ราคาเดิมเป็นของจำนวนเก่า — ล้างทันที ไม่ต้องรอ debounce
    setState(_invalidateQuote);
    if (value.isEmpty || _tokenIn == null || _tokenOut == null) return;

    _quoteDebounce = Timer(const Duration(milliseconds: 500), () {
      _fetchQuote();
    });
  }

  Future<void> _fetchQuote() async {
    final tokenIn = _tokenIn;
    final tokenOut = _tokenOut;
    if (tokenIn == null || tokenOut == null) return;
    final amountStr = _amountController.text.trim();
    if (amountStr.isEmpty) return;

    final amountIn = SwapService.parseAmount(amountStr, tokenIn.decimals);
    if (amountIn <= BigInt.zero) return;

    // รอบนี้คือรอบล่าสุด — ราคาเดิม (ถ้ามี) ไม่ใช่ของรอบนี้ ล้างไว้ระหว่างรอ
    final requestId = ++_quoteRequestId;
    final chain = _chain;
    setState(() {
      _quoteAmount = null;
      _isQuoting = true;
    });

    final quote = await SwapService.getQuote(
      chain: chain,
      tokenIn: tokenIn.isNative ? TokenDef.nativeAddress : tokenIn.address,
      tokenOut: tokenOut.isNative ? TokenDef.nativeAddress : tokenOut.address,
      amountIn: amountIn,
    );

    if (!mounted) return;
    // ระหว่างรอมีการแก้จำนวน/เหรียญ/เชน หรือเริ่มขอรอบใหม่ = ผลนี้เป็นของอินพุตเก่า ทิ้ง
    if (requestId != _quoteRequestId) return;
    setState(() {
      _quoteAmount = quote;
      _isQuoting = false;
    });
  }

  void _flipTokens() {
    if (_busy || _tokenIn == null || _tokenOut == null) return;
    _flipController.forward().then((_) => _flipController.reset());
    SynthService.playTap();
    setState(() {
      final temp = _tokenIn;
      _tokenIn = _tokenOut;
      _tokenOut = temp;
      _invalidateQuote();
      _amountController.clear();
      _allowance = BigInt.zero;
    });
    _loadBalance();
  }

  Future<void> _selectTokenIn() async {
    if (_busy) return;
    final token = await TokenSelectorSheet.show(
      context,
      chain: _chain,
      walletAddress: context.read<WalletProvider>().address,
      excludeAddress: _tokenOut?.address,
    );
    if (token == null || !mounted || _busy) return;
    setState(() {
      _tokenIn = token;
      _invalidateQuote();
      _allowance = BigInt.zero;
    });
    _loadBalance();
    if (_amountController.text.isNotEmpty) _fetchQuote();
  }

  Future<void> _selectTokenOut() async {
    if (_busy) return;
    final token = await TokenSelectorSheet.show(
      context,
      chain: _chain,
      walletAddress: context.read<WalletProvider>().address,
      excludeAddress: _tokenIn?.address,
    );
    if (token == null || !mounted || _busy) return;
    setState(() {
      _tokenOut = token;
      _invalidateQuote();
    });
    if (_amountController.text.isNotEmpty) _fetchQuote();
  }

  // ================================================================
  // โหมด TPIX Chain — หน้าจอแค่ถามยืนยัน/แสดงผล ตรรกะอยู่ใน TpixSwapController
  // ================================================================

  Future<void> _selectTpixToken({required bool isFrom}) async {
    if (_tpix.busy) return;
    final owner = context.read<WalletProvider>().address;
    final other = isFrom ? _tpix.to : _tpix.from;
    final token = await TokenSelectorSheet.show(
      context,
      chain: ChainConfig.tpix,
      walletAddress: owner,
      excludeAddress: other?.address,
      tokens: _tpix.tokens,
      balanceOf: owner == null ? null : (t) => TpixDexService.balanceOf(t, owner),
    );
    if (token == null || !mounted) return;
    isFrom ? _tpix.selectFrom(token) : _tpix.selectTo(token);
  }

  /// เต็มยอดแบบตรงตัว (BigInt → ข้อความ) — เชน TPIX ไม่มีค่าแก๊ส ไม่ต้องเผื่อ
  void _onTpixMax() {
    final text = _tpix.maxAmountText;
    if (text == null || _tpix.busy) return;
    _amountController.text = text;
    _tpix.setAmount(text);
  }

  void _flipTpix() {
    if (_tpix.busy) return;
    _flipController.forward().then((_) => _flipController.reset());
    SynthService.playTap();
    _tpix.flip(); // ช่องกรอกถูกล้างตามใน _onTpixChanged
  }

  Future<void> _approveTpix() async {
    if (_tpixTapBusy || _tpix.busy) return;
    _tpixTapBusy = true;
    SynthService.playTap();
    try {
      await _tpix.approve();
      if (!mounted) return;
      SynthService.playSendSuccess();
    } catch (e) {
      if (!mounted) return;
      SynthService.playError();
      _showTpixError('swap.approvalFailed', e);
    } finally {
      _tpixTapBusy = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _executeTpixSwap() async {
    if (_tpixTapBusy || _tpix.busy) return; // กันกดซ้ำตั้งแต่แตะครั้งแรก
    _tpixTapBusy = true;
    try {
      // ราคาเก่า → ขอใหม่ก่อน ผู้ใช้ต้องยืนยันกับตัวเลขล่าสุด
      if (_tpix.quoteIsStale) {
        await _tpix.refreshQuote();
        if (!mounted) return;
      }
      final quote = _tpix.quote;
      // ราคาใหม่เกินเพดาน/ขอไม่สำเร็จ → ปุ่มบอกเหตุผลเอง ไม่เปิดกล่องยืนยัน
      if (quote == null || _tpix.block != TpixSwapBlock.none) return;

      final confirmed = await _showTpixConfirmDialog(quote);
      if (confirmed != true || !mounted) return;

      SynthService.playSend();
      // ส่งตาม quote ที่ผู้ใช้เห็นในกล่องยืนยันเท่านั้น (minOut ผูกกับตัวเลขนั้น)
      final result = await _tpix.swap(quote: quote, slippagePct: _slippagePercent);
      if (!mounted || result == null) return;
      SynthService.playSendSuccess();
      _showSuccessDialog(result.txHash);
    } catch (e) {
      if (!mounted) return;
      SynthService.playError();
      _showTpixError('swap.failed', e);
    } finally {
      _tpixTapBusy = false;
      if (mounted) setState(() {});
    }
  }

  void _showTpixError(String titleKey, Object e) {
    final l = context.read<LocaleProvider>();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${l.t(titleKey)}: ${_tpixErrorText(e, l)}'), backgroundColor: AppTheme.danger),
    );
  }

  /// แปลง error เป็นข้อความตามภาษาของแอป — ห้ามโชว์ "Exception: ..." ดิบ
  String _tpixErrorText(Object e, LocaleProvider l) {
    if (e is TpixDexException) return l.t(e.localeKey);
    if (e is RpcUnavailableException) return l.t('swap.tpix.err.unreachable');
    if (e is WalletChangedException) return l.t('send.errWalletChanged');
    if (e is InsufficientGasException) return l.t('send.errGas');
    if (e is RpcException) {
      final m = e.message.toLowerCase();
      if (m.contains('insufficient funds') || m.contains('exceeds balance')) {
        return l.t('send.insufficientBalance');
      }
      // จำลองธุรกรรม (estimateGas) แล้ว revert = ราคาขยับเกิน slippage / allowance ไม่พอ
      if (m.contains('revert')) return l.t('swap.tpix.err.reverted');
    }
    return l.t('swap.tpix.err.generic');
  }

  String _impactText(TpixDexQuote q, LocaleProvider l) {
    final bps = q.impactBps;
    if (bps == null) return l.t('swap.tpix.impactUnknownValue');
    if (bps == 0) return '< 0.01%';
    return '${(bps / 100).toStringAsFixed(2)}%';
  }

  String _routeText(TpixDexQuote q) => [q.from.symbol, if (q.viaWtpix) 'WTPIX', q.to.symbol].join(' → ');

  String get _slippageText => '${_slippagePercent % 1 == 0 ? _slippagePercent.toInt() : _slippagePercent}%';

  Future<bool?> _showTpixConfirmDialog(TpixDexQuote q) {
    final l = context.read<LocaleProvider>();
    final BigInt minOut;
    try {
      minOut = q.minOut(_slippagePercent);
    } on TpixDexException catch (e) {
      _showTpixError('swap.failed', e);
      return Future.value(false);
    }

    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(TpixRadius.lg)),
        title: Text(
          l.t('swap.confirmTitle'),
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _confirmRow(l.t('swap.from'), '${TpixDexMath.display(q.amountIn, q.from.decimals)} ${q.from.symbol}'),
            _confirmRow(l.t('swap.toEstimated'), '${TpixDexMath.display(q.amountOut, q.to.decimals)} ${q.to.symbol}'),
            _confirmRow(l.t('swap.minReceived'), '${TpixDexMath.display(minOut, q.to.decimals)} ${q.to.symbol}'),
            _confirmRow(l.t('swap.tpix.priceImpact'), _impactText(q, l)),
            _confirmRow(l.t('swap.slippage'), _slippageText),
            const Divider(color: AppTheme.textMuted, height: 16),
            _confirmRow(l.t('swap.tpix.poolFee'), l.t('swap.tpix.poolFeeValue')),
            _confirmRow(l.t('swap.tpix.gasFee'), l.t('swap.tpix.gasFeeValue')),
            _confirmRow(l.t('swap.tpix.route'), _routeText(q)),
            _confirmRow(l.t('swap.network'), ChainConfig.tpix.name),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.t('send.cancel'), style: const TextStyle(color: AppTheme.textMuted)),
          ),
          TextButton(
            key: const ValueKey('tpix-confirm-swap'),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              l.t('swap.button'),
              style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  bool get _needsApproval {
    if (_tokenIn == null || _tokenIn!.isNative) return false;
    final amountStr = _amountController.text.trim();
    if (amountStr.isEmpty) return false;
    final amountIn = SwapService.parseAmount(amountStr, _tokenIn!.decimals);
    return _allowance < amountIn;
  }

  Future<void> _approve() async {
    // ถ่ายเชน/เหรียญไว้ตั้งแต่ต้น — ทุกขั้นหลัง await อ้างอิงชุดนี้ (ไม่อ่าน _chain/_tokenIn ซ้ำ)
    final tokenIn = _tokenIn;
    final chain = _chain;
    final router = chain.dexRouterAddress;
    if (_busy || tokenIn == null || router == null) return;
    setState(() => _isApproving = true);
    SynthService.playTap();

    try {
      final wallet = context.read<WalletProvider>();
      // Max uint256 approval
      final maxApproval = BigInt.parse(
        'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff',
        radix: 16,
      );

      // Build ERC-20 approve calldata
      final approveData = SwapService.buildApproveData(router, maxApproval);

      // Get gas price for this chain
      final gasPrice = await SwapService.getGasPrice(chain);

      // Sign and broadcast approval tx to the token contract
      final txHash = await wallet.sendEvmTransaction(
        rpcUrl: chain.rpcUrl,
        chainId: chain.chainId,
        toAddress: tokenIn.address,
        data: approveData,
        gasPrice: gasPrice,
        maxGas: 60000, // ERC-20 approve typically costs ~46K gas
      );

      // Wait for confirmation (poll up to 30s)
      if (mounted) {
        String? status;
        for (int i = 0; i < 15; i++) {
          await Future.delayed(const Duration(seconds: 2));
          if (!mounted) return;
          status = await wallet.checkEvmTxStatus(chain.rpcUrl, txHash);
          if (status != null) break;
        }

        if (status == 'confirmed') {
          // Reload actual allowance from chain
          final allowance = await SwapService.checkAllowance(
            chain: chain,
            tokenAddress: tokenIn.address,
            ownerAddress: wallet.address!,
          );
          if (mounted) {
            setState(() {
              _allowance = allowance;
              _isApproving = false;
            });
            SynthService.playSendSuccess();
          }
        } else {
          throw Exception(status == 'failed' ? 'Approval transaction failed' : 'Approval timed out');
        }
      }
    } catch (e) {
      if (mounted) {
        final l = context.read<LocaleProvider>();
        SynthService.playError();
        final errMsg = e.toString().replaceFirst('Exception: ', '');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${l.t('swap.approvalFailed')}: $errMsg'),
            backgroundColor: AppTheme.danger,
          ),
        );
        setState(() => _isApproving = false);
      }
    }
  }

  Future<void> _executeSwap() async {
    // ถ่ายทุกอย่างที่ธุรกรรมอ้างอิงไว้ก่อนเปิดกล่องยืนยัน — กล่องยืนยัน, amountOutMin,
    // เชนที่ส่ง/ถามสถานะ และบันทึกหลังบ้าน ใช้ชุดเดียวกันทั้งหมด (ไม่อ่าน _quoteAmount/_chain ซ้ำ)
    final tokenIn = _tokenIn;
    final tokenOut = _tokenOut;
    final quote = _quoteAmount;
    final chain = _chain;
    final router = chain.dexRouterAddress;
    final slippage = _slippagePercent;
    if (_busy || _isQuoting || tokenIn == null || tokenOut == null || quote == null || router == null) return;

    final amountStr = _amountController.text.trim();
    if (amountStr.isEmpty) return;
    final amountIn = SwapService.parseAmount(amountStr, tokenIn.decimals);
    if (amountIn <= BigInt.zero || amountIn > _balanceIn) return;

    // Confirm dialog — "รับขั้นต่ำ" ที่ผู้ใช้เห็น = amountOutMin ที่ส่งจริง
    final confirmed = await _showConfirmDialog(amountStr, amountIn, quote, slippage);
    if (confirmed != true || !mounted) return;

    setState(() => _isSwapping = true);
    SynthService.playSend();

    try {
      final wallet = context.read<WalletProvider>();
      final amountOutMin = SwapService.applySlippage(quote, slippage);

      final tokenInAddr = tokenIn.isNative ? TokenDef.nativeAddress : tokenIn.address;
      final tokenOutAddr = tokenOut.isNative ? TokenDef.nativeAddress : tokenOut.address;
      final isFromNative = tokenIn.isNative;

      // Build swap calldata for the DEX router
      final swapData = SwapService.buildSwapData(
        chain: chain,
        tokenIn: tokenInAddr,
        tokenOut: tokenOutAddr,
        amountIn: amountIn,
        amountOutMin: amountOutMin,
        recipientAddress: wallet.address!,
      );

      // Get gas price
      final gasPrice = await SwapService.getGasPrice(chain);

      // Sign and broadcast swap tx to the DEX router
      final txHash = await wallet.sendEvmTransaction(
        rpcUrl: chain.rpcUrl,
        chainId: chain.chainId,
        toAddress: router,
        data: swapData,
        // For native→token swaps, send the native value with the tx
        value: isFromNative ? amountIn : null,
        gasPrice: gasPrice,
        maxGas: 300000, // DEX swaps typically cost 150K-250K gas
      );

      // Wait for confirmation (poll up to 60s)
      String? status;
      for (int i = 0; i < 20; i++) {
        await Future.delayed(const Duration(seconds: 3));
        if (!mounted) return;
        status = await wallet.checkEvmTxStatus(chain.rpcUrl, txHash);
        if (status != null) break;
      }

      if (!mounted) return;

      if (status == 'confirmed') {
        SynthService.playSendSuccess();
        _showSuccessDialog(txHash);

        // Record swap on backend (best-effort, non-blocking)
        final outAmount = SwapService.formatAmount(quote, tokenOut.decimals);
        final feeAmt = SwapService.formatAmount(
          _swapFee.calculateFee(amountIn),
          tokenIn.decimals,
        );
        WalletAuthService.recordSwap(
          walletAddress: wallet.address!,
          fromToken: tokenIn.isNative ? '0x0000000000000000000000000000000000000000' : tokenIn.address,
          toToken: tokenOut.isNative ? '0x0000000000000000000000000000000000000000' : tokenOut.address,
          fromAmount: double.tryParse(amountStr) ?? 0,
          toAmount: outAmount,
          feeAmount: feeAmt,
          txHash: txHash,
          chainId: chain.chainId,
          signFn: wallet.signPersonalMessage,
        );
      } else if (status == 'failed') {
        throw Exception('Swap transaction reverted on-chain');
      } else {
        // Still pending after 60s — show tx hash so user can track
        SynthService.playSendSuccess();
        _showSuccessDialog(txHash);
      }
    } catch (e) {
      if (mounted) {
        final l = context.read<LocaleProvider>();
        SynthService.playError();
        final errMsg = e.toString().replaceFirst('Exception: ', '');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${l.t('swap.failed')}: $errMsg'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSwapping = false);
        _loadBalance(); // Refresh balance after swap
      }
    }
  }

  /// [quote]/[slippage] = ชุดที่ _executeSwap ถ่ายไว้และจะใช้คิด amountOutMin จริง
  Future<bool?> _showConfirmDialog(String amountStr, BigInt amountIn, BigInt quote, double slippage) {
    if (_isObsidian) return _obsConfirm(amountStr, amountIn, quote, slippage);
    final l = context.read<LocaleProvider>();
    final outFormatted = SwapService.formatAmount(quote, _tokenOut!.decimals);
    final minOut = SwapService.formatAmount(
      SwapService.applySlippage(quote, slippage),
      _tokenOut!.decimals,
    );

    // Platform fee calculation
    final feeAmount = _swapFee.calculateFee(amountIn);
    final feeFormatted = SwapService.formatAmount(feeAmount, _tokenIn!.decimals);

    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(TpixRadius.lg)),
        title: Text(
          l.t('swap.confirmTitle'),
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _confirmRow(l.t('swap.from'), '$amountStr ${_tokenIn!.symbol}'),
            _confirmRow(l.t('swap.toEstimated'), '${outFormatted.toStringAsFixed(6)} ${_tokenOut!.symbol}'),
            _confirmRow(l.t('swap.minReceived'), '${minOut.toStringAsFixed(6)} ${_tokenOut!.symbol}'),
            _confirmRow(l.t('swap.slippage'), '${slippage % 1 == 0 ? slippage.toInt() : slippage}%'),
            if (_swapFee.feePercent > 0) ...[
              const Divider(color: AppTheme.textMuted, height: 16),
              _confirmRow(l.t('swap.platformFee'), '${feeFormatted.toStringAsFixed(6)} ${_tokenIn!.symbol} (${_swapFee.feePercent}%)'),
              if (_swapFee.feeWallet.isNotEmpty)
                _confirmRow(l.t('swap.feeWallet'), FeeService.shortWallet(_swapFee.feeWallet)),
            ],
            _confirmRow(l.t('swap.network'), _chain.name),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.t('send.cancel'), style: const TextStyle(color: AppTheme.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.t('swap.button'), style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w700)),
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

  void _showSuccessDialog(String txHash) {
    if (_isObsidian) {
      _obsSuccess(txHash);
      return;
    }
    final l = context.read<LocaleProvider>();
    final shortTx = txHash.length > 16
        ? '${txHash.substring(0, 10)}...${txHash.substring(txHash.length - 6)}'
        : txHash;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(TpixRadius.lg)),
        title: Row(
          children: [
            const Icon(Icons.check_circle, color: AppTheme.success, size: 28),
            const SizedBox(width: TpixGap.sm),
            Flexible(child: Text(l.t('swap.success'), style: const TextStyle(color: AppTheme.success))),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.t('swap.successDesc'), style: const TextStyle(color: AppTheme.textSecondary)),
            const SizedBox(height: TpixGap.md),
            // TX Hash row
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(TpixRadius.sm),
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
                      Clipboard.setData(ClipboardData(text: txHash));
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
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop(context);
            },
            child: Text(l.t('swap.done'), style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<LocaleProvider>();
    // ธีม Obsidian มีเลย์เอาต์ของตัวเอง (swap_obsidian.dart) — ธีมอื่นใช้ของเดิมด้านล่าง
    if (_isObsidian) return _obsBuild(l);

    return Scaffold(
      body: TpixScreenBackground(
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
                      const SizedBox(height: TpixGap.xl),
                      // TPIX Chain ยังไม่พร้อม = ไม่มีฟอร์ม ไม่มีปุ่มส่ง (fail-closed) + บอกเหตุผล
                      if (_isTpix && _tpix.phase != TpixSwapPhase.ready)
                        _buildTpixStatus(l)
                      else ...[
                        _buildFromCard(l),
                        _buildFlipButton(),
                        _buildToCard(l),
                        const SizedBox(height: TpixGap.lg),
                        _buildSlippageSelector(),
                        const SizedBox(height: TpixGap.lg),
                        if (_isTpix) _buildTpixQuoteInfo(l) else if (_quoteAmount != null) _buildRateInfo(),
                        const SizedBox(height: TpixGap.xxl),
                        if (_isTpix) _buildTpixSwapButton(l) else _buildSwapButton(l),
                      ],
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
          const SizedBox(width: TpixGap.md),
          Text(
            l.t('swap.title'),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white),
          ),
          const Spacer(),
          // Settings icon for slippage
          GestureDetector(
            onTap: _networkLocked ? null : _showSlippageDialog,
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
        borderRadius: BorderRadius.circular(TpixRadius.md),
        color: Colors.white.withValues(alpha: 0.04),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        // TPIX Chain ไม่มี router ใน ChainConfig (ที่อยู่ DEX มาจากทะเบียนบนเซิร์ฟเวอร์เท่านั้น)
        children: [ChainConfig.tpix, ...ChainConfig.all.where((c) => c.hasSwap)].map((chain) {
          final isActive = chain.chainId == _chain.chainId;
          // ทะเบียนไม่พร้อม/ติดต่อไม่ได้ — ยังแตะได้ (ถามใหม่ + บอกเหตุผล) แต่จางลง
          final dimmed =
              chain.chainId == ChainConfig.tpix.chainId &&
              (_tpix.phase == TpixSwapPhase.unavailable || _tpix.phase == TpixSwapPhase.unreachable);
          return Expanded(
            child: GestureDetector(
              key: ValueKey('swap-chain-${chain.chainId}'),
              // ระหว่างอนุมัติ/แลก ห้ามสลับเชน (ธุรกรรมที่รอผลอ้างอิงเชนเดิม)
              onTap: _networkLocked ? null : () => _onChainChanged(chain),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(TpixRadius.sm),
                  color: isActive ? chain.color.withValues(alpha: 0.15) : Colors.transparent,
                  border: isActive
                      ? Border.all(color: chain.color.withValues(alpha: 0.3))
                      : null,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ChainLogo(chain: chain, size: 18),
                    const SizedBox(width: TpixGap.sm),
                    Text(
                      chain.shortName,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                        color: isActive ? chain.color : AppTheme.textMuted.withValues(alpha: dimmed ? 0.45 : 1),
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

  /// ยอดสูงสุดที่กรอกได้ — เหรียญหลักของเชนที่มีค่าแก๊สเผื่อไว้ ~0.005 สำหรับค่าแก๊ส
  String _maxAmountText() {
    final formattedBalance = SwapService.formatAmount(_balanceIn, _tokenIn?.decimals ?? 18);
    // Reserve gas for native token swaps on non-gasless chains
    double maxAmount = formattedBalance;
    if (_tokenIn != null && _tokenIn!.isNative && !_chain.isGasless) {
      // Reserve ~0.005 native token for gas (covers most swap gas costs)
      const gasReserve = 0.005;
      maxAmount = (formattedBalance - gasReserve).clamp(0.0, formattedBalance);
    }
    return maxAmount.toStringAsFixed(8);
  }

  Widget _buildFromCard(LocaleProvider l) {
    final tpix = _isTpix;
    final tokenIn = tpix ? _tpix.from : _tokenIn;
    final formattedBalance = SwapService.formatAmount(_balanceIn, _tokenIn?.decimals ?? 18);
    // โหมด TPIX: ยอดเป็น BigInt ตรงตัว · อ่านไม่ได้ = "—" (ไม่ใช่ 0)
    final tpixBalance = _tpix.balanceIn;
    final balanceText = !tpix
        ? formattedBalance.toStringAsFixed(4)
        : (tpixBalance == null || tokenIn == null
              ? '—'
              : TpixDexMath.display(tpixBalance, tokenIn.decimals, maxFraction: 4));

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(TpixRadius.lg),
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
                  if (tpix ? _tpix.loadingBalance : _loadingBalance)
                    const Padding(
                      padding: EdgeInsets.only(right: 4),
                      child: SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 1.5, color: AppTheme.textMuted)),
                    ),
                  Text(
                    '${l.t('swap.balance')}: $balanceText',
                    style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                  ),
                  const SizedBox(width: TpixGap.sm),
                  GestureDetector(
                    key: const ValueKey('swap-max'),
                    onTap: _networkLocked
                        ? null
                        : tpix
                        ? _onTpixMax
                        : () {
                            _amountController.text = _maxAmountText();
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
          const SizedBox(height: TpixGap.md),
          Row(
            children: [
              // Token selector button
              GestureDetector(
                key: const ValueKey('swap-token-in'),
                onTap: _networkLocked ? null : (tpix ? () => _selectTpixToken(isFrom: true) : _selectTokenIn),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(TpixRadius.md),
                    color: Colors.white.withValues(alpha: 0.06),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (tokenIn != null) ...[
                        TokenLogo(token: tokenIn, chain: _chain, size: 28),
                        const SizedBox(width: TpixGap.sm),
                        Text(
                          tokenIn.symbol,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white),
                        ),
                      ] else
                        const Text('Select', style: TextStyle(color: AppTheme.textMuted)),
                      const SizedBox(width: TpixGap.xs),
                      const Icon(Icons.keyboard_arrow_down, color: AppTheme.textMuted, size: 20),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: TpixGap.md),
              // Amount input
              Expanded(
                child: TextField(
                  key: const ValueKey('swap-amount'),
                  controller: _amountController,
                  // ระหว่างอนุมัติ/สวอปห้ามแก้จำนวน — ธุรกรรมที่รออยู่ผูกกับจำนวนเดิม
                  enabled: !_networkLocked,
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
                  onChanged: tpix ? _tpix.setAmount : _onAmountChanged,
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
          key: const ValueKey('swap-flip'),
          onTap: _networkLocked ? null : (_isTpix ? _flipTpix : _flipTokens),
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
    final tpix = _isTpix;
    final tokenOut = tpix ? _tpix.to : _tokenOut;
    final tpixQuote = _tpix.quote;
    final String? outText;
    if (tpix) {
      outText = tpixQuote == null ? null : TpixDexMath.display(tpixQuote.amountOut, tpixQuote.to.decimals);
    } else {
      outText = _quoteAmount != null && _tokenOut != null
          ? SwapService.formatAmount(_quoteAmount!, _tokenOut!.decimals).toStringAsFixed(6)
          : null;
    }
    final quoting = tpix ? _tpix.quoting && tpixQuote == null : _isQuoting;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(TpixRadius.lg),
        color: Colors.white.withValues(alpha: 0.04),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.t('swap.to'), style: const TextStyle(fontSize: 13, color: AppTheme.textMuted)),
          const SizedBox(height: TpixGap.md),
          Row(
            children: [
              GestureDetector(
                key: const ValueKey('swap-token-out'),
                onTap: _networkLocked ? null : (tpix ? () => _selectTpixToken(isFrom: false) : _selectTokenOut),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(TpixRadius.md),
                    color: Colors.white.withValues(alpha: 0.06),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (tokenOut != null) ...[
                        TokenLogo(token: tokenOut, chain: _chain, size: 28),
                        const SizedBox(width: TpixGap.sm),
                        Text(
                          tokenOut.symbol,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white),
                        ),
                      ] else
                        const Text('Select', style: TextStyle(color: AppTheme.textMuted)),
                      const SizedBox(width: TpixGap.xs),
                      const Icon(Icons.keyboard_arrow_down, color: AppTheme.textMuted, size: 20),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: TpixGap.md),
              Expanded(
                child: quoting
                    ? const Align(
                        alignment: Alignment.centerRight,
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary),
                        ),
                      )
                    : Text(
                        outText ?? '0.0',
                        key: const ValueKey('swap-amount-out'),
                        textAlign: TextAlign.right,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: outText != null ? Colors.white : AppTheme.textMuted.withValues(alpha: 0.3),
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
    final l = context.read<LocaleProvider>();
    const options = [0.5, 1.0, 3.0];
    return Row(
      children: [
        // ป้าย "ค่าคลาดเคลื่อน" ภาษาไทยยาวกว่าอังกฤษ ดันชิป 3 ตัวตกขอบ
        Flexible(
          child: Text('${l.t('swap.slippage')}:',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: AppColors.of(context).textMuted)),
        ),
        const SizedBox(width: TpixGap.sm),
        ...options.map((s) {
          final isActive = _slippagePercent == s;
          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: GestureDetector(
              onTap: _networkLocked
                  ? null
                  : () {
                      setState(() => _slippagePercent = s);
                      SynthService.playTap();
                    },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(TpixRadius.sm),
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
          onTap: _networkLocked ? null : _showSlippageDialog,
          child: Text(
            l.t('swap.custom'),
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

    final l = context.read<LocaleProvider>();
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

    // Platform fee
    final feeAmount = _swapFee.calculateFee(amountIn);
    final feeFormatted = SwapService.formatAmount(feeAmount, _tokenIn!.decimals);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(TpixRadius.md),
        color: Colors.white.withValues(alpha: 0.03),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        children: [
          _infoRow(l.t('swap.rate'), '1 ${_tokenIn!.symbol} = ${rate.toStringAsFixed(6)} ${_tokenOut!.symbol}'),
          _infoRow(l.t('swap.minReceived'), '${minReceived.toStringAsFixed(6)} ${_tokenOut!.symbol}'),
          _infoRow(l.t('swap.slippage'), '${_slippagePercent % 1 == 0 ? _slippagePercent.toInt() : _slippagePercent}%'),
          if (_swapFee.feePercent > 0)
            _infoRow(l.t('swap.platformFee'), '${feeFormatted.toStringAsFixed(6)} ${_tokenIn!.symbol} (${_swapFee.feePercent}%)'),
          if (_swapFee.feeWallet.isNotEmpty)
            _infoRow(l.t('swap.feeWallet'), FeeService.shortWallet(_swapFee.feeWallet)),
          _infoRow(l.t('swap.network'), _chain.name),
          // Fee source badge
          const SizedBox(height: TpixGap.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (_loadingFeeConfig)
                const Padding(
                  padding: EdgeInsets.only(right: 4),
                  child: SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 1, color: AppTheme.textMuted)),
                ),
              Icon(Icons.verified_rounded, color: AppTheme.primary.withValues(alpha: 0.5), size: 12),
              const SizedBox(width: TpixGap.xs),
              Text(
                'TPIX.ONLINE',
                style: TextStyle(fontSize: 10, color: AppTheme.primary.withValues(alpha: 0.5), fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value, {Color? valueColor, Key? valueKey}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
          const SizedBox(width: TpixGap.sm),
          Flexible(
            child: Text(
              value,
              key: valueKey,
              style: TextStyle(fontSize: 12, color: valueColor ?? AppTheme.textSecondary, fontWeight: FontWeight.w600),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }

  /// สถานะโหมด TPIX Chain ตอนยังใช้ไม่ได้ — โหลดอยู่ / ทะเบียนไม่พร้อม / ติดต่อไม่ได้
  Widget _buildTpixStatus(LocaleProvider l) {
    final colors = AppColors.of(context);
    if (_tpix.phase == TpixSwapPhase.loading) {
      return Padding(
        key: const ValueKey('tpix-swap-loading'),
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Column(
          children: [
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary),
            ),
            const SizedBox(height: TpixGap.md),
            Text(l.t('swap.tpix.loading'), style: TextStyle(fontSize: 13, color: colors.textMuted)),
          ],
        ),
      );
    }

    final unreachable = _tpix.phase == TpixSwapPhase.unreachable;
    return Container(
      key: const ValueKey('tpix-swap-closed'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(TpixRadius.lg),
        color: Colors.white.withValues(alpha: 0.04),
        border: Border.all(color: colors.brandWarm.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(unreachable ? Icons.cloud_off_rounded : Icons.lock_clock_rounded, color: colors.brandWarm, size: 20),
              const SizedBox(width: TpixGap.sm),
              Expanded(
                child: Text(
                  l.t(unreachable ? 'swap.tpix.unreachable' : 'swap.tpix.unavailable'),
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: colors.text),
                ),
              ),
            ],
          ),
          const SizedBox(height: TpixGap.sm),
          Text(
            l.t(unreachable ? 'swap.tpix.unreachableBody' : 'swap.tpix.unavailableBody'),
            style: TextStyle(fontSize: 13, height: 1.4, color: colors.textSec),
          ),
          const SizedBox(height: TpixGap.lg),
          Wrap(
            spacing: TpixGap.sm,
            runSpacing: TpixGap.sm,
            children: [
              TextButton.icon(
                key: const ValueKey('tpix-retry'),
                onPressed: () => _tpix.load(force: true),
                icon: const Icon(Icons.refresh_rounded, size: 18, color: AppTheme.primary),
                label: Text(
                  l.t('swap.tpix.retry'),
                  style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w700),
                ),
              ),
              TextButton(
                key: const ValueKey('tpix-use-bsc'),
                onPressed: () => _onChainChanged(ChainConfig.bsc),
                child: Text(l.t('swap.tpix.useBsc'), style: TextStyle(color: colors.textSec)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// ราคา / ผลกระทบต่อราคา / ค่าธรรมเนียมในพูล ของโหมด TPIX Chain
  Widget _buildTpixQuoteInfo(LocaleProvider l) {
    final colors = AppColors.of(context);
    final q = _tpix.quote;
    final err = _tpix.quoteError;
    if (q == null) {
      if (err == null || _tpix.quoting) return const SizedBox.shrink();
      return Text(
        l.t(err.localeKey),
        key: const ValueKey('tpix-quote-error'),
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 13, color: colors.brandDanger),
      );
    }

    final inAmount = Units.toDouble(q.amountIn, q.from.decimals);
    final outAmount = Units.toDouble(q.amountOut, q.to.decimals);
    final rate = inAmount > 0 ? outAmount / inAmount : 0.0; // แสดงผลเท่านั้น
    String minText;
    try {
      minText = '${TpixDexMath.display(q.minOut(_slippagePercent), q.to.decimals)} ${q.to.symbol}';
    } on TpixDexException {
      minText = '—';
    }
    final bps = q.impactBps;
    final impactColor = bps == null || q.exceedsImpactLimit
        ? colors.brandDanger
        : (bps >= 300 ? colors.brandWarm : null);
    final maxIn = q.exceedsImpactLimit ? q.maxAmountInUnderLimit : null;

    return Container(
      key: const ValueKey('tpix-quote-info'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(TpixRadius.md),
        color: Colors.white.withValues(alpha: 0.03),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        children: [
          _infoRow(l.t('swap.rate'), '1 ${q.from.symbol} = ${rate.toStringAsFixed(6)} ${q.to.symbol}'),
          _infoRow(l.t('swap.minReceived'), minText),
          _infoRow(
            l.t('swap.tpix.priceImpact'),
            _impactText(q, l),
            valueColor: impactColor,
            valueKey: const ValueKey('tpix-impact'),
          ),
          _infoRow(l.t('swap.slippage'), _slippageText),
          _infoRow(l.t('swap.tpix.poolFee'), l.t('swap.tpix.poolFeeValue')),
          _infoRow(l.t('swap.tpix.gasFee'), l.t('swap.tpix.gasFeeValue')),
          _infoRow(l.t('swap.tpix.route'), _routeText(q)),
          _infoRow(l.t('swap.network'), ChainConfig.tpix.name),
          if (maxIn != null && maxIn > BigInt.zero) ...[
            const SizedBox(height: TpixGap.sm),
            Text(
              l
                  .t('swap.tpix.maxHint')
                  .replaceAll('{amount}', TpixDexMath.display(maxIn, q.from.decimals, maxFraction: 4))
                  .replaceAll('{symbol}', q.from.symbol),
              key: const ValueKey('tpix-max-hint'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: colors.brandDanger),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTpixSwapButton(LocaleProvider l) {
    final block = _tpix.block;
    String text;
    Color color;
    VoidCallback? onTap;
    switch (block) {
      case TpixSwapBlock.enterAmount:
        text = l.t('swap.enterAmount');
        color = AppTheme.textMuted;
      case TpixSwapBlock.invalidAmount:
        text = l.t('swap.tpix.invalidAmount');
        color = AppTheme.danger;
      case TpixSwapBlock.tooManyDecimals:
        text = l.t('swap.tpix.tooManyDecimals');
        color = AppTheme.danger;
      case TpixSwapBlock.loading:
        text = l.t('swap.tpix.loadingShort');
        color = AppTheme.textMuted;
      case TpixSwapBlock.balanceUnknown:
        text = l.t('swap.tpix.balanceUnknown');
        color = AppTheme.accent;
        onTap = _tpix.refreshBalance;
      case TpixSwapBlock.insufficient:
        text = l.t('swap.insufficient');
        color = AppTheme.danger;
      case TpixSwapBlock.quoting:
        text = l.t('swap.tpix.quoting');
        color = AppTheme.textMuted;
      case TpixSwapBlock.quoteFailed:
        text = l.t('swap.tpix.retryQuote');
        color = AppTheme.accent;
        onTap = _tpix.refreshQuote;
      case TpixSwapBlock.impactUnknown:
        text = l.t('swap.tpix.impactUnknownButton');
        color = AppTheme.danger;
      case TpixSwapBlock.impactTooHigh:
        text = l.t('swap.tpix.impactTooHighButton');
        color = AppTheme.danger;
      case TpixSwapBlock.needsApproval:
        text = _tpix.approving ? l.t('swap.approving') : '${l.t('swap.approve')} ${_tpix.from?.symbol ?? ''}';
        color = AppTheme.accent;
        onTap = _tpix.busy ? null : _approveTpix;
      case TpixSwapBlock.none:
        text = _tpix.swapping ? l.t('swap.swapping') : l.t('swap.button');
        color = AppTheme.primary;
        onTap = _tpix.busy ? null : _executeTpixSwap;
    }

    return Column(
      children: [
        _actionButton(
          key: const ValueKey('tpix-swap-button'),
          text: text,
          color: color,
          onTap: onTap,
          busy: _tpix.busy,
        ),
        if (block == TpixSwapBlock.needsApproval) ...[
          const SizedBox(height: TpixGap.sm),
          Text(
            l.t('swap.tpix.approveNote'),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: AppColors.of(context).textMuted),
          ),
        ],
      ],
    );
  }

  Widget _buildSwapButton(LocaleProvider l) {
    final amountStr = _amountController.text.trim();
    final hasAmount = amountStr.isNotEmpty;
    final amountIn = hasAmount ? SwapService.parseAmount(amountStr, _tokenIn?.decimals ?? 18) : BigInt.zero;
    final hasQuote = _quoteAmount != null && _quoteAmount! > BigInt.zero;
    final hasSufficientBalance = amountIn <= _balanceIn && amountIn > BigInt.zero;
    // ยอด/allowance ของเหรียญที่เพิ่งเลือกยังโหลดไม่เสร็จ = ยังเชื่อค่าไม่ได้ (กันแลกเกินยอด/อนุมัติซ้ำเสียค่าแก๊ส)
    final canSwap = hasAmount && hasQuote && hasSufficientBalance && !_busy && !_isQuoting && !_loadingBalance;

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
      onTap = _busy || _loadingBalance ? null : _approve;
    } else {
      buttonText = _isSwapping ? l.t('swap.swapping') : l.t('swap.button');
      buttonColor = AppTheme.primary;
      onTap = canSwap ? _executeSwap : null;
    }

    return _actionButton(text: buttonText, color: buttonColor, onTap: onTap, busy: _isSwapping || _isApproving);
  }

  /// ปุ่มหลักของหน้า (อนุมัติ/แลก) — หน้าตาเดียวกันทุกเครือข่าย
  Widget _actionButton({
    Key? key,
    required String text,
    required Color color,
    required VoidCallback? onTap,
    required bool busy,
  }) {
    final buttonText = text;
    final buttonColor = color;
    return GestureDetector(
      key: key,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(TpixRadius.lg),
          gradient: onTap != null
              ? LinearGradient(colors: [buttonColor, buttonColor.withValues(alpha: 0.8)])
              : null,
          color: onTap == null ? buttonColor.withValues(alpha: 0.15) : null,
          boxShadow: onTap != null
              ? [BoxShadow(color: buttonColor.withValues(alpha: 0.3), blurRadius: 20, offset: const Offset(0, 6))]
              : null,
        ),
        alignment: Alignment.center,
        child: busy
            ? Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  ),
                  const SizedBox(width: TpixGap.md),
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
    if (_isObsidian) {
      _obsShowSlippage();
      return;
    }
    final l = context.read<LocaleProvider>();
    final controller = TextEditingController(text: _slippagePercent.toString());
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(TpixRadius.lg)),
        title: Text(l.t('swap.slippage'), style: const TextStyle(color: Colors.white)),
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
            child: Text(l.t('send.cancel'), style: const TextStyle(color: AppTheme.textMuted)),
          ),
          TextButton(
            onPressed: () {
              final val = double.tryParse(controller.text);
              if (val != null && val > 0 && val <= 50) {
                setState(() => _slippagePercent = val);
              }
              Navigator.pop(ctx);
            },
            child: Text(l.t('swap.set'), style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    ).then((_) => controller.dispose()); // Single disposal point after dialog closes
  }
}
