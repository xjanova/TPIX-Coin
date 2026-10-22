import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../models/chain_config.dart';
import '../models/wallet_info.dart';
import '../models/token_info.dart';
import '../models/token_list.dart';
import '../models/tx_record.dart';
import '../services/biometric_service.dart';
import '../services/db_service.dart';
import '../services/price_service.dart';
import '../services/rpc_client.dart';
import '../services/swap_service.dart';
import '../services/token_list_service.dart';
import '../services/token_service.dart';
import '../services/token_trust.dart';
import '../services/wallet_auth_service.dart';
import '../services/wallet_service.dart';
import '../utils/units.dart';

class WalletProvider extends ChangeNotifier {
  /// [walletService] ให้เทสต์ส่งตัวปลอมเข้ามาได้ — แอปจริงใช้ค่าเริ่มต้น
  WalletProvider({WalletService? walletService})
      : _walletService = walletService ?? WalletService();

  final WalletService _walletService;
  bool _disposed = false;

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  /// Sanitize error messages to prevent leaking RPC URLs, file paths, or stack traces
  static String _sanitizeError(Object e) {
    final msg = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
    // Strip URLs that might reveal RPC endpoints
    final sanitized = msg.replaceAll(RegExp(r'https?://[^\s]+'), '[server]');
    // Limit length to prevent stack traces reaching UI
    return sanitized.length > 200 ? '${sanitized.substring(0, 200)}...' : sanitized;
  }

  bool _isLoading = false;
  bool _isUnlocked = false;
  bool _hasWallet = false;
  String? _address;
  String? _mnemonic;
  String? _error;
  String? _lastTxHash;
  List<TxRecord> _txHistory = [];
  bool _isScanning = false;

  // ── ยอด TPIX ──
  // เก็บเป็น wei (BigInt) — null = ยังไม่เคยดึงสำเร็จ (ไม่ใช่ "0")
  // ดึงไม่สำเร็จ → คงค่าเดิม + ติดป้าย stale ห้ามทับด้วย 0
  BigInt? _balanceWei;
  bool _balanceStale = false;
  DateTime? _balanceUpdatedAt;

  // ── โทเค็น ──
  List<TokenInfo> _tokens = [];
  Map<String, BigInt> _tokenBalancesRaw = {}; // ที่อยู่ (ตัวเล็ก) → หน่วยย่อย
  Set<String> _staleTokenBalances = {}; // ดึงรอบล่าสุดไม่สำเร็จ (โชว์ค่าเดิม + ป้าย)
  Set<String> _missingContracts = {}; // สัญญาไม่มีบนเชนแล้ว (ซ่อนจากยอด)
  Map<String, String> _defaultTokenLogos = {}; // โลโก้จาก TPIX DEX

  // Multi-chain state
  int _activeChainId = 4289; // default: TPIX Chain
  Map<int, BigInt> _chainBalances = {}; // chainId → native balance (wei)

  // ── ราคา ── null = ยังไม่เคยได้ราคาจริงเลย (ห้ามเดา)
  PriceQuote? _priceQuote;
  bool _priceStale = false;

  Timer? _balanceTimer;
  Timer? _txPollTimer;
  Timer? _mnemonicClearTimer; // auto-clear mnemonic from memory
  String? _pendingTxHash;
  int _pollCount = 0;
  static const int _maxPolls = 100; // 100 x 3s = 5 min max
  bool _isRefreshing = false; // guard against overlapping balance refreshes
  bool _isPolling = false; // guard against overlapping tx polls

  // Getters
  bool get isLoading => _isLoading;
  bool get isUnlocked => _isUnlocked;
  bool get hasWallet => _hasWallet;
  String? get address => _address;
  String? get mnemonic => _mnemonic;
  String? get error => _error;
  String? get lastTxHash => _lastTxHash;
  String get shortAddress => _walletService.shortAddress;
  List<TxRecord> get txHistory => _txHistory;
  bool get isScanning => _isScanning;

  /// ยอด TPIX แบบทศนิยม (แสดงผล) — ยังไม่รู้ยอด = 0 (ดู [hasBalance] ก่อนเสมอ)
  double get balance =>
      _balanceWei == null ? 0 : Units.toDouble(_balanceWei!, 18);

  /// ยอด TPIX หน่วย wei — ใช้เทียบ/ส่งเงิน (ไม่ผ่าน double)
  BigInt? get balanceWei => _balanceWei;

  /// เคยดึงยอดสำเร็จแล้วหรือยัง
  bool get hasBalance => _balanceWei != null;

  /// ยอดที่โชว์อยู่ไม่ใช่ล่าสุด (ดึงรอบหลังไม่สำเร็จ)
  bool get isBalanceStale => _balanceStale;
  DateTime? get balanceUpdatedAt => _balanceUpdatedAt;

  // Multi-wallet getters
  List<WalletInfo> get wallets => _walletService.wallets;
  int get walletCount => _walletService.walletCount;
  int get activeSlot => _walletService.activeSlot;
  WalletInfo? get activeWallet => _walletService.activeWallet;

  // Token getters
  /// โทเค็นทั้งหมดที่บันทึกไว้ (รวมตัวที่สัญญาหายแล้ว — ใช้ในส่วนจัดการโทเค็น)
  List<TokenInfo> get tokens => _tokens;

  /// โทเค็นที่ใช้งานได้ (สัญญายังอยู่) — ใช้แสดงยอด/เลือกส่ง
  List<TokenInfo> get activeTokens => _tokens
      .where((t) => !_missingContracts.contains(t.contractAddress.toLowerCase()))
      .toList();

  /// โทเค็นที่สัญญาไม่มีบนเชนแล้ว (ต้องติดป้าย + ให้ลบได้แบบยืนยัน)
  List<TokenInfo> get missingContractTokens => _tokens
      .where((t) => _missingContracts.contains(t.contractAddress.toLowerCase()))
      .toList();

  bool isTokenContractMissing(String contractAddress) =>
      _missingContracts.contains(contractAddress.toLowerCase());

  Map<String, double> get tokenBalances => {
        for (final t in activeTokens)
          if (_tokenBalancesRaw[t.contractAddress.toLowerCase()] case final raw?)
            t.contractAddress.toLowerCase(): Units.toDouble(raw, t.decimals),
      };

  double getTokenBalance(String contractAddress) =>
      tokenBalances[contractAddress.toLowerCase()] ?? 0;

  /// ยอดโทเค็นหน่วยย่อย — null = ยังไม่รู้
  BigInt? getTokenBalanceRaw(String contractAddress) =>
      _tokenBalancesRaw[contractAddress.toLowerCase()];

  bool isTokenBalanceStale(String contractAddress) =>
      _staleTokenBalances.contains(contractAddress.toLowerCase());

  /// รายการโทเค็นที่ยืนยันแล้วของ TPIX Chain (null = ยังไม่มี/ดึงไม่ได้)
  TokenList? get tokenList => TokenListService.current;

  /// โลโก้ของโทเค็น: รายการที่ยืนยันแล้ว (ถ้าอยู่ในรายการ) → ที่บันทึกไว้ → TPIX DEX → ค่าในตัวแอป
  String? tokenLogo(TokenInfo token) => TokenTrustService.resolveLogo(
        token,
        list: TokenListService.current,
        dexLogos: _defaultTokenLogos,
      );

  /// ยืนยันแล้ว / ไม่ยืนยัน / ชื่อเลียนแบบตัวที่ยืนยันแล้ว (ใช้ติดป้าย)
  TokenTrust tokenTrust(TokenInfo token) =>
      TokenTrustService.trustOf(token, TokenListService.current);

  // Chain getters
  int get activeChainId => _activeChainId;
  ChainConfig get activeChain => ChainConfig.byId(_activeChainId);
  Map<int, BigInt> get chainBalances => _chainBalances;

  /// Get native balance for a specific chain in human-readable format
  double getChainBalance(int chainId) {
    final bal = _chainBalances[chainId];
    if (bal == null || bal == BigInt.zero) return 0.0;
    final chain = ChainConfig.byId(chainId);
    return SwapService.formatAmount(bal, chain.decimals);
  }

  // Price getters
  /// ราคา TPIX/USD — null = ยังไม่เคยได้ราคาจริง (UI ต้องโชว์ "ไม่พร้อมใช้งาน")
  double? get tpixPrice => _priceQuote?.price;

  /// เปลี่ยนแปลงราคา TPIX 24 ชม. (%) จากเซิร์ฟเวอร์ — null = ไม่รู้ (ห้ามเดา)
  double? get tpixChange24h => _priceQuote?.change24h;

  /// ราคาที่โชว์เป็นราคาเก่า (ดึงล่าสุดไม่สำเร็จ)
  bool get isPriceStale => _priceStale;
  DateTime? get priceUpdatedAt => _priceQuote?.fetchedAt;

  /// มูลค่า TPIX ในกระเป๋าเป็น USD — null เมื่อยังไม่รู้ยอดหรือไม่รู้ราคา
  double? get portfolioValueUSD {
    final price = tpixPrice;
    if (price == null || _balanceWei == null) return null;
    return balance * price;
  }

  /// ยอดย่อสำหรับแสดงผล — ยังไม่เคยดึงสำเร็จ = "—" (ไม่ใช่ 0 ที่ทำให้ตกใจ)
  String get formattedBalance {
    if (_balanceWei == null) return '—';
    final b = balance;
    if (b >= 1000000) return '${(b / 1000000).toStringAsFixed(2)}M';
    if (b >= 1000) return '${(b / 1000).toStringAsFixed(2)}K';
    return b.toStringAsFixed(4);
  }

  /// Initialize — check if wallet exists + load last real price
  Future<void> init() async {
    _hasWallet = await _walletService.hasWallet();
    // ราคาจริงล่าสุดที่เคยได้ (ถ้ามี) — ติดป้ายว่าเก่าจนกว่าจะดึงใหม่สำเร็จ
    await PriceService.loadLastPrice();
    _priceQuote = PriceService.lastQuote;
    _priceStale = _priceQuote != null;
    notifyListeners();
  }

  /// ล้างข้อมูลที่ผูกกับกระเป๋าใบปัจจุบัน — เรียกทุกครั้งที่เปลี่ยน/ลบ/ล็อกกระเป๋า
  ///
  /// ★ ไม่ล้าง = หลังสลับกระเป๋า ถ้าดึงยอดใบใหม่ไม่สำเร็จ ระบบ "คงยอดเดิม"
  ///   ซึ่งเป็นยอดของอีกใบ — ผู้ใช้เห็นเงินผิดกระเป๋า
  void _clearWalletScopedState() {
    _balanceWei = null;
    _balanceStale = false;
    _balanceUpdatedAt = null;
    _tokens = [];
    _tokenBalancesRaw = {};
    _staleTokenBalances = {};
    _missingContracts = {};
    _chainBalances = {};
    _txHistory = [];
  }

  /// Clear mnemonic from memory after a timeout (for security)
  void _scheduleMnemonicClear() {
    _mnemonicClearTimer?.cancel();
    _mnemonicClearTimer = Timer(const Duration(seconds: 120), () {
      _mnemonic = null;
      notifyListeners();
    });
  }

  /// Create new wallet
  Future<Map<String, String>> createWallet({String? name}) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final result = await _walletService.createWallet(name: name);
      _mnemonic = result['mnemonic'];
      _address = result['address'];
      _clearWalletScopedState();
      _scheduleMnemonicClear();
      return result;
    } catch (e) {
      _error = _sanitizeError(e);
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Import from mnemonic
  Future<void> importFromMnemonic(String mnemonic, {String? name}) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _address = await _walletService.importFromMnemonic(mnemonic, name: name);
      _mnemonic = mnemonic;
      _clearWalletScopedState();
      _scheduleMnemonicClear();
    } catch (e) {
      _error = _sanitizeError(e);
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Import from private key
  Future<void> importFromPrivateKey(String key, {String? name}) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _address = await _walletService.importFromPrivateKey(key, name: name);
      _clearWalletScopedState();
    } catch (e) {
      _error = _sanitizeError(e);
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Save wallet with PIN
  Future<void> saveWallet(String pin) async {
    await _walletService.saveWallet(pin);
    _hasWallet = true;
    _isUnlocked = true;
    notifyListeners();
    _startBalanceRefresh();
  }

  /// Unlock wallet with PIN
  Future<bool> unlock(String pin) async {
    if (_isLoading) return false; // double-tap guard
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final success = await _walletService.unlockWallet(pin);
      if (success) {
        _isUnlocked = true;
        _address = _walletService.address;
        _mnemonic = _walletService.mnemonic;
        // Load data in background — don't block navigation
        _loadDataInBackground(pin: pin);
      } else {
        _error = 'Invalid PIN';
      }
      return success;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Unlock wallet using biometric token
  Future<bool> unlockWithBiometric() async {
    if (_isLoading) return false; // double-tap guard
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final success = await _walletService.unlockWithBiometric();
      if (success) {
        _isUnlocked = true;
        _address = _walletService.address;
        _mnemonic = _walletService.mnemonic;
        // Load data in background — don't block navigation
        _loadDataInBackground();
      }
      return success;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Load balance, TX history, tokens in background after unlock
  void _loadDataInBackground({String? pin}) async {
    final slot = _walletService.activeSlot; // capture current slot
    // Save biometric token if PIN was provided
    if (pin != null) {
      final bioService = BiometricService();
      if (await bioService.isEnabled()) {
        await _walletService.saveBiometricToken(pin);
      }
    }
    // Abort if wallet was switched during biometric save
    if (_walletService.activeSlot != slot || _disposed) return;
    // Load data concurrently — each notifies listeners when done
    await Future.wait([
      refreshBalance(),
      loadTxHistory(),
      loadTokens(),
    ]);
    if (_walletService.activeSlot != slot || _disposed) return;
    loadChainBalances();
    _startBalanceRefresh();
  }

  /// Save biometric token after successful PIN unlock
  Future<void> saveBiometricToken(String pin) async {
    await _walletService.saveBiometricToken(pin);
  }

  /// Clear biometric token
  Future<void> clearBiometricToken() async {
    await _walletService.clearBiometricToken();
  }

  /// Refresh balance + price (ไม่ throw — ล้มแล้วคงค่าเดิม + ติดป้าย)
  Future<void> refreshBalance() async {
    await Future.wait([_refreshNativeBalance(), refreshPrice()]);
  }

  Future<void> _refreshNativeBalance() async {
    final address = _walletService.address;
    if (address == null) return;
    try {
      final wei = await _walletService.getBalanceWei();
      // สลับกระเป๋าระหว่างรอ → ยอดนี้เป็นของอีกใบ ทิ้ง
      if (_walletService.address != address || _disposed) return;
      _balanceWei = wei;
      _balanceStale = false;
      _balanceUpdatedAt = DateTime.now();
    } catch (e) {
      if (_walletService.address != address || _disposed) return;
      // ★ คงยอดเดิมไว้ — แค่ติดป้ายว่าไม่อัปเดต (ห้ามกลายเป็น 0)
      _balanceStale = true;
      debugPrint('refreshBalance failed: ${e.runtimeType}');
    }
    notifyListeners();
  }

  /// ดึงราคาใหม่ — ไม่ได้ก็ใช้ราคาจริงล่าสุด + ติดป้ายว่าเก่า (ห้ามเดาราคา)
  Future<void> refreshPrice() async {
    final quote = await PriceService.fetchPrice();
    if (_disposed) return;
    if (quote != null) {
      _priceQuote = quote;
      _priceStale = false;
    } else {
      _priceQuote ??= PriceService.lastQuote;
      _priceStale = _priceQuote != null;
    }
    notifyListeners();
  }

  /// Send TPIX — [amountWei] หน่วย wei (BigInt), [expectedFrom] = ที่อยู่ที่ผู้ใช้ยืนยัน
  Future<String> sendTPIX(
    String toAddress,
    BigInt amountWei, {
    String? expectedFrom,
  }) async {
    _isLoading = true;
    _error = null;
    _lastTxHash = null;
    notifyListeners();

    try {
      final txHash = await _walletService.sendTPIX(
        toAddress: toAddress,
        amountWei: amountWei,
        expectedFrom: expectedFrom,
      );
      _lastTxHash = txHash;
      await refreshBalance();
      await loadTxHistory();
      _startTxPolling(txHash);
      return txHash;
    } catch (e) {
      _error = _sanitizeError(e);
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// ส่งโทเค็น ERC-20 — [amount] หน่วยย่อยของโทเค็น
  Future<String> sendToken(
    TokenInfo token,
    String toAddress,
    BigInt amount, {
    String? expectedFrom,
  }) async {
    _isLoading = true;
    _error = null;
    _lastTxHash = null;
    notifyListeners();

    try {
      final txHash = await _walletService.sendToken(
        tokenAddress: token.contractAddress,
        tokenSymbol: token.symbol,
        tokenDecimals: token.decimals,
        toAddress: toAddress,
        amount: amount,
        chainId: token.chainId,
        expectedFrom: expectedFrom,
      );
      _lastTxHash = txHash;
      await refreshTokenBalances();
      await loadTxHistory();
      _startTxPolling(txHash);
      return txHash;
    } catch (e) {
      _error = _sanitizeError(e);
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ═══════════════════════════════════════════════════════════
  //  Cross-Chain EVM Transactions
  // ═══════════════════════════════════════════════════════════

  /// Sign and send a transaction on any EVM chain (BSC, Polygon, ETH, etc.)
  /// Used by swap screens for DEX interactions and bridge for fund transfers
  /// [historyAs] = แถวประวัติที่ควรโชว์แทนค่าเริ่มต้น (ดู [TxHistoryOverride])
  Future<String> sendEvmTransaction({
    required String rpcUrl,
    required int chainId,
    required String toAddress,
    BigInt? value,
    Uint8List? data,
    int? maxGas,
    BigInt? gasPrice,
    String? expectedFrom,
    TxHistoryOverride? historyAs,
  }) async {
    return _walletService.sendEvmTransaction(
      rpcUrl: rpcUrl,
      chainId: chainId,
      toAddress: toAddress,
      value: value,
      data: data,
      maxGas: maxGas,
      gasPrice: gasPrice,
      expectedFrom: expectedFrom,
      historyAs: historyAs,
    );
  }

  /// Check transaction status on any EVM chain
  Future<String?> checkEvmTxStatus(String rpcUrl, String txHash) async {
    return _walletService.checkEvmTxStatus(rpcUrl, txHash);
  }

  /// Sign a personal message (EIP-191) for wallet verification
  /// Used by WalletAuthService challenge-sign-verify flow
  Future<String> signPersonalMessage(String message) async =>
      _walletService.signPersonalMessage(message);

  /// เซ็นไบต์ดิบแบบ EIP-191 (personal_sign / eth_sign ของ WalletConnect)
  /// [expectedAddress] ไม่ตรงกับกระเป๋าที่เปิดอยู่ → WalletChangedException ไม่เซ็น
  Future<String> signPersonalMessageBytes(Uint8List message, {String? expectedAddress}) async =>
      _walletService.signPersonalMessageBytes(message, expectedAddress: expectedAddress);

  // ═══════════════════════════════════════════════════════════
  //  Multi-Chain Operations
  // ═══════════════════════════════════════════════════════════

  /// Switch active chain
  Future<void> switchChain(int chainId) async {
    _activeChainId = chainId;
    notifyListeners();
    await loadChainBalances();
  }

  /// Load native balances for all supported chains in parallel
  /// ดึงไม่ได้ → คงยอดเดิมของเชนนั้น (ห้ามทับด้วย 0)
  Future<void> loadChainBalances() async {
    final address = _address;
    if (address == null) return;
    final chains = ChainConfig.all.where((c) => c.chainId != 4289).toList();
    final results = await Future.wait(
      chains.map((chain) async {
        try {
          return MapEntry(chain.chainId, await RpcClient.forChain(chain).getBalance(address));
        } catch (_) {
          return null;
        }
      }),
    );
    if (_address != address) return; // สลับกระเป๋าระหว่างรอ
    for (final entry in results) {
      if (entry != null) _chainBalances[entry.key] = entry.value;
    }
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════
  //  Multi-Wallet Operations
  // ═══════════════════════════════════════════════════════════

  /// Switch to another wallet
  Future<void> switchWallet(int slot) async {
    _isLoading = true;
    notifyListeners();

    try {
      WalletAuthService.clearSession(); // Clear auth on wallet switch
      await _walletService.switchWallet(slot);
      _address = _walletService.address;
      _clearWalletScopedState();
      notifyListeners();
      await refreshBalance();
      await loadTxHistory();
      await loadTokens();
      unawaited(loadChainBalances());
    } catch (e) {
      _error = _sanitizeError(e);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Add a new wallet from HD seed
  Future<Map<String, String>> addWallet({String? name}) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final result = await _walletService.createWallet(name: name);
      _address = result['address'];
      _clearWalletScopedState();
      await _walletService.persistWallets(); // Save wallet list (PIN already set)
      await refreshBalance();
      await loadTxHistory();
      await loadTokens();
      return result;
    } catch (e) {
      _error = _sanitizeError(e);
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Rename a wallet
  Future<void> renameWallet(int slot, String newName) async {
    await _walletService.renameWallet(slot, newName);
    notifyListeners();
  }

  /// Delete a wallet
  Future<void> deleteWalletBySlot(int slot) async {
    WalletAuthService.clearSession(); // Clear auth on slot delete
    final previousAddress = _address;
    await _walletService.deleteWalletBySlot(slot);
    _address = _walletService.address;
    if (_address != previousAddress) _clearWalletScopedState();
    if (_walletService.walletCount > 0) {
      await refreshBalance();
      await loadTxHistory();
      await loadTokens();
    } else {
      _clearWalletScopedState();
    }
    _hasWallet = _walletService.walletCount > 0;
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════
  //  Transaction History
  // ═══════════════════════════════════════════════════════════

  /// Load tx history from local storage
  Future<void> loadTxHistory() async {
    final slot = _walletService.activeSlot;
    final list = await _walletService.getActiveTxHistory();
    if (_walletService.activeSlot != slot) return;
    _txHistory = list;
    notifyListeners();
  }

  /// ดึงประวัติจาก explorer (ถอยไปสแกนบล็อกถ้า explorer ใช้ไม่ได้)
  Future<void> scanTransactions({int blockCount = 50}) async {
    if (_isScanning) return;
    _isScanning = true;
    notifyListeners();

    try {
      await _walletService.syncHistory(blockCount: blockCount);
      await loadTxHistory();
    } catch (_) {}

    _isScanning = false;
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════
  //  Custom Tokens
  // ═══════════════════════════════════════════════════════════

  /// Load tokens from SQLite (+ โทเค็นมาตรฐานของ TPIX Chain ครั้งแรก, ตรวจสัญญาที่หายไป)
  Future<void> loadTokens() async {
    final slot = _walletService.activeSlot;
    final list = await DbService.getTokensForSlot(slot);
    if (_walletService.activeSlot != slot || _disposed) return;
    _tokens = list;
    notifyListeners();
    // งานที่ต้องรอเน็ต ทำเบื้องหลัง — ไม่ให้รายการโทเค็นรอ API
    unawaited(refreshTokenBalances());
    unawaited(_syncTokensInBackground(slot));
    unawaited(refreshTokenList());
  }

  /// โหลดรายการโทเค็นที่ยืนยันแล้ว (แคชในเครื่องก่อน เก่าเกิน 6 ชม.ค่อยดึงใหม่)
  /// — ได้ชุดใหม่ก็วาดโลโก้/ป้ายใหม่ · ไม่ผูกกับกระเป๋าใบไหน · ไม่ throw
  Future<void> refreshTokenList({bool force = false}) async {
    final before = TokenListService.current;
    final after = await TokenListService.load(forceRefresh: force);
    if (_disposed || identical(before, after)) return;
    notifyListeners();
  }

  Future<void> _syncTokensInBackground(int slot) async {
    try {
      // 1. เพิ่ม USDT ฯลฯ ของ TPIX Chain ให้ครั้งเดียวต่อกระเป๋า
      final before = _tokens.length;
      final defaults = await TokenService.ensureDefaultTokens(slot);
      if (_walletService.activeSlot != slot || _disposed) return;
      _defaultTokenLogos = {
        for (final d in defaults)
          if (d.logoUrl != null) d.address.toLowerCase(): d.logoUrl!,
      };
      final list = await DbService.getTokensForSlot(slot);
      if (_walletService.activeSlot != slot || _disposed) return;
      _tokens = list;

      // 2. ตรวจว่าสัญญายังอยู่ไหม — ตัวที่ตรวจไม่ได้คงสถานะเดิม
      final check = await TokenService.checkContracts(list);
      if (_walletService.activeSlot != slot || _disposed) return;
      _missingContracts = {
        ..._missingContracts.difference(check.present),
        ...check.missing,
      };
      notifyListeners();
      if (list.length != before || check.missing.isNotEmpty) {
        await refreshTokenBalances();
      }
    } catch (e) {
      debugPrint('syncTokens: ${e.runtimeType}');
    }
  }

  /// Refresh all token balances — ตัวที่ดึงไม่ได้คงยอดเดิม + ติดป้าย stale
  Future<void> refreshTokenBalances() async {
    final address = _walletService.address;
    final targets = activeTokens;
    if (address == null || targets.isEmpty) return;
    final result = await TokenService.getBalances(targets, address);
    if (_walletService.address != address || _disposed) return;
    _tokenBalancesRaw = {..._tokenBalancesRaw, ...result.balances};
    _staleTokenBalances = result.failed;
    notifyListeners();
  }

  /// Remove a token (UI ต้องถามยืนยันก่อนเรียกเสมอ)
  Future<void> removeToken(String contractAddress) async {
    await DbService.removeToken(contractAddress, _walletService.activeSlot);
    final key = contractAddress.toLowerCase();
    _tokenBalancesRaw.remove(key);
    _staleTokenBalances.remove(key);
    _missingContracts.remove(key);
    await loadTokens();
  }

  // ═══════════════════════════════════════════════════════════
  //  TX Status Polling
  // ═══════════════════════════════════════════════════════════

  void _startTxPolling(String txHash) {
    _txPollTimer?.cancel();
    _pendingTxHash = txHash;
    _pollCount = 0;
    final pollSlot = _walletService.activeSlot; // capture slot at send time

    _txPollTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) async {
        if (_isPolling) return; // prevent overlapping polls
        _isPolling = true;
        try {
          _pollCount++;
          if (_pollCount > _maxPolls || _pendingTxHash == null) {
            _txPollTimer?.cancel();
            return;
          }

          final status = await _walletService.checkTransactionStatus(_pendingTxHash!);
          if (status != null) {
            await _walletService.updateTxStatus(_pendingTxHash!, status, slot: pollSlot);
            await loadTxHistory();
            await refreshBalance();
            await refreshTokenBalances();
            _txPollTimer?.cancel();
            _pendingTxHash = null;
          }
        } finally {
          _isPolling = false;
        }
      },
    );
  }

  /// Lock wallet
  void lock() {
    _walletService.lock();
    WalletAuthService.clearSession(); // Clear auth on lock
    _isUnlocked = false;
    _mnemonic = null; // clear sensitive data immediately
    _balanceTimer?.cancel();
    _txPollTimer?.cancel();
    _mnemonicClearTimer?.cancel();
    _pendingTxHash = null;
    _clearWalletScopedState();
    _activeChainId = 4289;
    notifyListeners();
  }

  /// Delete ALL wallets
  Future<void> deleteWallet() async {
    WalletAuthService.clearSession(); // Clear auth on delete
    await _walletService.deleteWallet();
    _hasWallet = false;
    _isUnlocked = false;
    _address = null;
    _mnemonic = null;
    _clearWalletScopedState();
    _activeChainId = 4289;
    _balanceTimer?.cancel();
    _txPollTimer?.cancel();
    _pendingTxHash = null;
    notifyListeners();
  }

  void _startBalanceRefresh() {
    _balanceTimer?.cancel();
    _balanceTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) async {
        if (_isRefreshing) return; // prevent overlapping refreshes
        _isRefreshing = true;
        try {
          await refreshBalance();
          await refreshTokenBalances();
        } finally {
          _isRefreshing = false;
        }
      },
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _balanceTimer?.cancel();
    _txPollTimer?.cancel();
    _mnemonicClearTimer?.cancel();
    _walletService.dispose();
    super.dispose();
  }
}
