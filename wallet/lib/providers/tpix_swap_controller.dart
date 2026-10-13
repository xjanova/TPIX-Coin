/// TPIX Wallet — สถานะหน้าสวอปโหมด "TPIX Chain" (TPIX DEX)
///
/// แยกออกจากหน้าจอให้ทุกธีมใช้ตรรกะชุดเดียว (หน้าเดิมทุกธีม + Obsidian เมื่อ merge)
/// หน้าจอมีหน้าที่วาดและถามยืนยันอย่างเดียว
///  - เงินทุกก้อนเป็น BigInt · จำนวนที่พิมพ์แปลงด้วย [Units.parse] (ไม่ผ่าน double)
///  - ผลที่มาช้า (quote/ยอด) ของรายการเก่าถูกทิ้งด้วยเลขรอบ — พิมพ์เร็ว ๆ ไม่มีตัวเลขเก่ามาทับ
///  - สลับกระเป๋าระหว่างเปิดหน้า → ล้างยอด/allowance แล้วอ่านของใบใหม่
///  - ธุรกรรมเซ็นด้วยกระเป๋าใบที่อ่านยอดไว้เท่านั้น (expectedFrom) · chainId 4289 · gasPrice 0
///
/// Developed by Xman Studio
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/chain_config.dart';
import '../services/tpix_dex_service.dart';
import '../services/wallet_auth_service.dart';
import '../utils/units.dart';
import 'wallet_provider.dart';

enum TpixSwapPhase { loading, ready, unavailable, unreachable }

/// ทำไมยังกดสวอปไม่ได้ — หน้าจอแปลงเป็นข้อความ/ปุ่มเอง
enum TpixSwapBlock {
  none,
  enterAmount,
  invalidAmount,
  tooManyDecimals,
  loading,
  balanceUnknown,
  insufficient,
  quoting,
  quoteFailed,
  impactUnknown,
  impactTooHigh,
  needsApproval,
}

class TpixSwapResult {
  const TpixSwapResult({required this.txHash, required this.confirmed});

  final String txHash;

  /// false = ส่งแล้วแต่ยังไม่ยืนยันในเวลาที่รอ (ดูต่อในประวัติ)
  final bool confirmed;
}

class TpixSwapController extends ChangeNotifier {
  TpixSwapController({
    required WalletProvider wallet,
    this.quoteDebounce = const Duration(milliseconds: 500),
    this.pollInterval = const Duration(seconds: 2),
    this.maxPolls = 30,
    this.staleAfter = const Duration(seconds: 20),
  }) : _wallet = wallet {
    _owner = wallet.address;
    _wallet.addListener(_onWalletChanged);
  }

  final WalletProvider _wallet;
  final Duration quoteDebounce;

  /// เชน TPIX ออกบล็อกทุก ~2 วิ — ถามสถานะถี่กว่าฝั่ง BSC ได้
  final Duration pollInterval;
  final int maxPolls;

  /// quote เก่ากว่านี้ → ขอใหม่ก่อนเปิดกล่องยืนยัน
  final Duration staleAfter;

  TpixSwapPhase _phase = TpixSwapPhase.loading;
  TpixDexMarket? _market;
  TokenDef? _from;
  TokenDef? _to;
  String _amountText = '';
  BigInt? _amountIn;
  AmountError? _amountError = AmountError.empty;
  TpixDexQuote? _quote;
  TpixDexException? _quoteError;
  bool _quoting = false;
  BigInt? _balanceIn;
  bool _loadingBalance = false;
  BigInt _allowance = BigInt.zero;
  bool _approving = false;
  bool _swapping = false;

  /// กระเป๋าใบที่อ่านยอดไว้ — ธุรกรรมต้องเซ็นด้วยใบนี้เท่านั้น
  String? _owner;

  Timer? _debounce;
  int _loadSeq = 0;
  int _quoteSeq = 0;
  int _balanceSeq = 0;
  bool _disposed = false;

  TpixSwapPhase get phase => _phase;
  TpixDexConfig? get config => _market?.config;
  List<TokenDef> get tokens => _market?.tokens ?? const [];
  TokenDef? get from => _from;
  TokenDef? get to => _to;
  String get amountText => _amountText;
  BigInt? get amountIn => _amountIn;
  TpixDexQuote? get quote => _quote;
  TpixDexException? get quoteError => _quoteError;
  bool get quoting => _quoting;

  /// null = อ่านไม่ได้ (ไม่ใช่ 0)
  BigInt? get balanceIn => _balanceIn;
  bool get loadingBalance => _loadingBalance;
  bool get approving => _approving;
  bool get swapping => _swapping;
  bool get busy => _approving || _swapping;

  bool get quoteIsStale {
    final q = _quote;
    return q == null || DateTime.now().difference(q.at) > staleAfter;
  }

  bool get needsApproval {
    final f = _from;
    final a = _amountIn;
    return f != null && !f.isNative && a != null && _allowance < a;
  }

  /// ข้อความเต็มยอดสำหรับปุ่ม MAX — เชน TPIX ไม่มีค่าแก๊ส ใช้ได้ทั้งยอด (ไม่ปัดขึ้นจนเกิน)
  String? get maxAmountText {
    final f = _from;
    final b = _balanceIn;
    if (f == null || b == null || b <= BigInt.zero) return null;
    return Units.format(b, f.decimals);
  }

  TpixSwapBlock get block {
    if (_from == null || _to == null || _amountText.trim().isEmpty) {
      return TpixSwapBlock.enterAmount;
    }
    if (_amountError == AmountError.tooManyDecimals) return TpixSwapBlock.tooManyDecimals;
    final amount = _amountIn;
    if (_amountError != null || amount == null) return TpixSwapBlock.invalidAmount;
    final balance = _balanceIn;
    if (balance == null) {
      return _loadingBalance ? TpixSwapBlock.loading : TpixSwapBlock.balanceUnknown;
    }
    if (amount > balance) return TpixSwapBlock.insufficient;
    final q = _quote;
    if (q == null || !_matches(q)) {
      return !_quoting && _quoteError != null ? TpixSwapBlock.quoteFailed : TpixSwapBlock.quoting;
    }
    if (!q.impactKnown) return TpixSwapBlock.impactUnknown;
    if (q.exceedsImpactLimit) return TpixSwapBlock.impactTooHigh;
    if (needsApproval) return TpixSwapBlock.needsApproval;
    return TpixSwapBlock.none;
  }

  bool _matches(TpixDexQuote q) =>
      q.from.address == _from?.address && q.to.address == _to?.address && q.amountIn == _amountIn;

  // ── โหลด ──

  /// โหลดทะเบียน DEX + รายการเหรียญ — ไม่พร้อม/ผิดรูป = ปิดโหมด (fail-closed)
  Future<void> load({bool force = false}) async {
    final seq = ++_loadSeq;
    _phase = TpixSwapPhase.loading;
    _notify();
    try {
      final market = await TpixDexService.loadMarket(force: force);
      if (_disposed || seq != _loadSeq) return;
      if (!market.available) {
        _market = null;
        _phase = TpixSwapPhase.unavailable;
        _notify();
        return;
      }
      _market = market;
      final from = _find(_from) ?? market.tokens.first; // TPIX เนทีฟอยู่ตัวแรกเสมอ
      var to = _find(_to);
      if (to == null || to.address == from.address) {
        final others = market.tokens.where((t) => t.address != from.address);
        to = others.firstWhere((t) => t.address == market.config.usdt,
            orElse: () => others.first);
      }
      _from = from;
      _to = to;
      _reparse();
      _phase = TpixSwapPhase.ready;
      _notify();
      unawaited(refreshBalance());
      _scheduleQuote(immediate: true);
    } catch (e) {
      if (_disposed || seq != _loadSeq) return;
      if (e is! TpixDexException) debugPrint('TpixSwapController.load: ${e.runtimeType}');
      final unreachable = e is! TpixDexException || e.code == TpixDexError.unreachable;
      _phase = unreachable ? TpixSwapPhase.unreachable : TpixSwapPhase.unavailable;
      _notify();
    }
  }

  TokenDef? _find(TokenDef? t) {
    if (t == null) return null;
    for (final c in tokens) {
      if (c.address == t.address) return c;
    }
    return null;
  }

  // ── จำนวน / เหรียญ ──

  void setAmount(String text) {
    if (busy) return;
    _amountText = text;
    _reparse();
    _quote = null;
    _quoteError = null;
    _scheduleQuote();
    _notify();
  }

  void _reparse() {
    final f = _from;
    if (f == null || _amountText.trim().isEmpty) {
      _amountIn = null;
      _amountError = AmountError.empty;
      return;
    }
    final parsed = Units.parse(_amountText, f.decimals);
    _amountIn = parsed.value;
    _amountError = parsed.error;
  }

  void selectFrom(TokenDef token) {
    if (busy || _find(token) == null) return;
    if (token.address == _to?.address) return flip();
    _from = _find(token);
    _balanceIn = null;
    _allowance = BigInt.zero;
    _reparse(); // ทศนิยมคนละแบบ — คิดจำนวนใหม่ตามเหรียญที่เลือก
    _quote = null;
    _quoteError = null;
    _scheduleQuote();
    _notify();
    unawaited(refreshBalance());
  }

  void selectTo(TokenDef token) {
    if (busy || _find(token) == null) return;
    if (token.address == _from?.address) return flip();
    _to = _find(token);
    _quote = null;
    _quoteError = null;
    _scheduleQuote();
    _notify();
  }

  /// สลับฝั่ง — ล้างจำนวน (ทศนิยม/ความหมายเปลี่ยน) แบบเดียวกับโหมด BSC
  void flip() {
    if (busy || _from == null || _to == null) return;
    final f = _from;
    _from = _to;
    _to = f;
    _amountText = '';
    _reparse();
    _quote = null;
    _quoteError = null;
    _balanceIn = null;
    _allowance = BigInt.zero;
    _scheduleQuote();
    _notify();
    unawaited(refreshBalance());
  }

  // ── Quote ──

  void _scheduleQuote({bool immediate = false}) {
    _debounce?.cancel();
    final seq = ++_quoteSeq; // ผลของรอบก่อนหน้าที่ยังไม่กลับมา = ทิ้ง
    if (_phase != TpixSwapPhase.ready || _from == null || _to == null || _amountIn == null) {
      _quoting = false;
      return;
    }
    _quoting = true;
    _debounce = Timer(immediate ? Duration.zero : quoteDebounce, () => _fetchQuote(seq));
  }

  /// ขอราคาใหม่ทันที (ปุ่มลองใหม่ / ก่อนเปิดกล่องยืนยันเมื่อราคาเก่า)
  Future<void> refreshQuote() async {
    _debounce?.cancel();
    final seq = ++_quoteSeq;
    if (_phase != TpixSwapPhase.ready || _from == null || _to == null || _amountIn == null) return;
    _quoting = true;
    _quoteError = null;
    _notify();
    await _fetchQuote(seq);
  }

  Future<void> _fetchQuote(int seq) async {
    final from = _from;
    final to = _to;
    final amount = _amountIn;
    if (from == null || to == null || amount == null) return;
    TpixDexQuote? q;
    TpixDexException? err;
    try {
      q = await TpixDexService.quote(from: from, to: to, amountIn: amount);
    } on TpixDexException catch (e) {
      err = e;
    } catch (e) {
      debugPrint('TpixSwapController.quote: ${e.runtimeType}');
      err = const TpixDexException(TpixDexError.unreachable);
    }
    if (_disposed || seq != _quoteSeq) return;
    _quote = q;
    _quoteError = err;
    _quoting = false;
    _notify();
  }

  // ── ยอด / allowance ──

  Future<void> refreshBalance() async {
    final from = _from;
    final owner = _wallet.address;
    if (_disposed || from == null || owner == null || _phase != TpixSwapPhase.ready) return;
    final seq = ++_balanceSeq;
    _owner = owner;
    _loadingBalance = true;
    _notify();

    final balance = await TpixDexService.balanceOf(from, owner);
    var allowance = BigInt.zero;
    if (!from.isNative) {
      try {
        allowance = await TpixDexService.allowance(from.address, owner);
      } catch (_) {
        // อ่านไม่ได้ = ถือว่ายังไม่อนุมัติ (บังคับ approve ปลอดภัยกว่าเดาว่าพอ)
      }
    }
    if (_disposed || seq != _balanceSeq) return;
    // อ่านรอบนี้ไม่ได้ → คงยอดที่อ่านได้ล่าสุดของเหรียญ/กระเป๋าเดิม (ถูกล้างไปแล้วถ้าเปลี่ยน)
    _balanceIn = balance ?? _balanceIn;
    _allowance = allowance;
    _loadingBalance = false;
    _notify();
  }

  void _onWalletChanged() {
    final addr = _wallet.address;
    if (addr?.toLowerCase() == _owner?.toLowerCase()) return;
    // สลับกระเป๋า — ยอด/allowance เดิมเป็นของอีกใบ ห้ามใช้ต่อ
    _owner = addr;
    _balanceIn = null;
    _allowance = BigInt.zero;
    _notify();
    unawaited(refreshBalance());
  }

  // ── ธุรกรรม ──

  /// อนุมัติ router **เท่ากับจำนวนของไม้นี้พอดี** แล้วรอจนยืนยันบนเชน
  Future<void> approve() async {
    if (busy) return;
    final from = _from;
    final amount = _amountIn;
    final owner = _owner;
    final router = config?.router;
    if (from == null || from.isNative || amount == null || owner == null || router == null) return;

    _approving = true;
    _notify();
    try {
      await TpixDexService.verifyChain();
      final hash = await _wallet.sendEvmTransaction(
        rpcUrl: ChainConfig.tpix.rpcUrl,
        chainId: ChainConfig.tpix.chainId,
        toAddress: from.address,
        data: TpixDexService.approveCalldata(router, amount),
        gasPrice: BigInt.zero, // เชน TPIX ไม่มีค่าแก๊ส
        expectedFrom: owner,
      );
      final status = await _waitStatus(hash);
      if (status == 'failed') throw const TpixDexException(TpixDexError.reverted);
      if (status != 'confirmed') throw const TpixDexException(TpixDexError.approvalPending);
      final fresh = await TpixDexService.allowance(from.address, owner);
      if (_disposed) return;
      _allowance = fresh;
      if (fresh < amount) throw const TpixDexException(TpixDexError.approvalPending);
    } finally {
      _approving = false;
      _notify();
    }
  }

  /// ส่งสวอปตาม [quote] ที่ผู้ใช้กดยืนยัน (minOut ผูกกับ quote นี้) — null = ไม่ได้ส่ง (กำลังทำงานอยู่)
  ///
  /// รอใบเสร็จ → ล้มบนเชน = throw reverted · ยืนยัน/ยังรอ = บันทึกกับเซิร์ฟเวอร์ (best-effort)
  Future<TpixSwapResult?> swap({
    required TpixDexQuote quote,
    required double slippagePct,
  }) async {
    if (busy) return null;
    final owner = _owner;
    final balance = _balanceIn;
    if (owner == null || balance == null) {
      throw const TpixDexException(TpixDexError.unreachable);
    }
    if (quote.amountIn > balance) {
      throw const TpixDexException(TpixDexError.insufficientBalance);
    }
    if (!quote.from.isNative && _allowance < quote.amountIn) {
      throw const TpixDexException(TpixDexError.approvalPending);
    }
    // ด่านสุดท้าย: impact/slippage ตามกติกาเว็บ — ไม่ผ่าน = ไม่มีอะไรถูกเซ็น
    final tx = TpixDexService.buildSwapTx(
        quote: quote, slippagePct: slippagePct, recipient: owner);

    _swapping = true;
    _notify();
    try {
      await TpixDexService.verifyChain();
      final hash = await _wallet.sendEvmTransaction(
        rpcUrl: ChainConfig.tpix.rpcUrl,
        chainId: ChainConfig.tpix.chainId,
        toAddress: tx.to,
        data: tx.data,
        value: tx.value,
        gasPrice: BigInt.zero, // เชน TPIX ไม่มีค่าแก๊ส
        expectedFrom: owner,
        // ประวัติในเครื่องโชว์ "จ่าย X USDT" แทน "ส่ง 0 TPIX ให้ router"
        historyAs: quote.from.isNative
            ? null
            : (
                to: tx.to,
                value: quote.amountIn,
                tokenAddress: quote.from.address,
                symbol: quote.from.symbol,
                decimals: quote.from.decimals,
              ),
      );
      final status = await _waitStatus(hash);
      if (status == 'failed') throw const TpixDexException(TpixDexError.reverted);

      // บันทึกฝั่งเซิร์ฟเวอร์แบบเดียวกับแอป TRADE — ค่าธรรมเนียมอยู่ในพูล (fee 0)
      // เซิร์ฟเวอร์ไม่เชื่อตัวเลขจากแอปสำหรับเชน 4289: อ่านไม้จริงจาก tx hash บนเชนเอง
      unawaited(WalletAuthService.recordSwap(
        walletAddress: owner,
        fromToken: quote.from.isNative ? TokenDef.nativeAddress : quote.from.address,
        toToken: quote.to.isNative ? TokenDef.nativeAddress : quote.to.address,
        fromAmount: Units.toDouble(quote.amountIn, quote.from.decimals),
        toAmount: Units.toDouble(quote.amountOut, quote.to.decimals),
        feeAmount: 0,
        txHash: hash,
        chainId: ChainConfig.tpix.chainId,
        signFn: _wallet.signPersonalMessage,
      ));

      if (!_disposed) {
        _amountText = '';
        _reparse();
        _quote = null;
        _quoteError = null;
      }
      return TpixSwapResult(txHash: hash, confirmed: status == 'confirmed');
    } finally {
      _swapping = false;
      _notify();
      unawaited(refreshBalance());
    }
  }

  /// 'confirmed' / 'failed' / null (ยังไม่ยืนยันในเวลาที่รอ หรือหน้าถูกปิด)
  Future<String?> _waitStatus(String hash) async {
    for (var i = 0; i < maxPolls; i++) {
      await Future<void>.delayed(pollInterval);
      if (_disposed) return null;
      final status = await _wallet.checkEvmTxStatus(ChainConfig.tpix.rpcUrl, hash);
      if (status != null) return status;
    }
    return null;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    _wallet.removeListener(_onWalletChanged);
    super.dispose();
  }
}
