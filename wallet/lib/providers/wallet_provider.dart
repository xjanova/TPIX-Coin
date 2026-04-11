import 'dart:async';
import 'package:flutter/material.dart';
import '../models/chain_config.dart';
import '../models/wallet_info.dart';
import '../models/token_info.dart';
import '../models/tx_record.dart';
import '../services/biometric_service.dart';
import '../services/db_service.dart';
import '../services/price_service.dart';
import '../services/swap_service.dart';
import '../services/token_service.dart';
import '../services/wallet_service.dart';

class WalletProvider extends ChangeNotifier {
  final WalletService _walletService = WalletService();

  bool _isLoading = false;
  bool _isUnlocked = false;
  bool _hasWallet = false;
  double _balance = 0;
  String? _address;
  String? _mnemonic;
  String? _error;
  String? _lastTxHash;
  List<TxRecord> _txHistory = [];
  bool _isScanning = false;

  // Token state
  List<TokenInfo> _tokens = [];
  Map<String, double> _tokenBalances = {};

  // Multi-chain state
  int _activeChainId = 4289; // default: TPIX Chain
  Map<int, BigInt> _chainBalances = {}; // chainId → native balance (wei)

  // Price state
  double _tpixPrice = PriceService.defaultPrice;

  Timer? _balanceTimer;
  Timer? _txPollTimer;
  String? _pendingTxHash;
  int _pollCount = 0;
  static const int _maxPolls = 100; // 100 x 3s = 5 min max

  // Getters
  bool get isLoading => _isLoading;
  bool get isUnlocked => _isUnlocked;
  bool get hasWallet => _hasWallet;
  double get balance => _balance;
  String? get address => _address;
  String? get mnemonic => _mnemonic;
  String? get error => _error;
  String? get lastTxHash => _lastTxHash;
  String get shortAddress => _walletService.shortAddress;
  List<TxRecord> get txHistory => _txHistory;
  bool get isScanning => _isScanning;

  // Multi-wallet getters
  List<WalletInfo> get wallets => _walletService.wallets;
  int get walletCount => _walletService.walletCount;
  int get activeSlot => _walletService.activeSlot;
  WalletInfo? get activeWallet => _walletService.activeWallet;

  // Token getters
  List<TokenInfo> get tokens => _tokens;
  Map<String, double> get tokenBalances => _tokenBalances;
  double getTokenBalance(String contractAddress) => _tokenBalances[contractAddress.toLowerCase()] ?? 0;

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
  double get tpixPrice => _tpixPrice;
  double get portfolioValueUSD => _balance * _tpixPrice;

  String get formattedBalance {
    if (_balance >= 1000000) return '${(_balance / 1000000).toStringAsFixed(2)}M';
    if (_balance >= 1000) return '${(_balance / 1000).toStringAsFixed(2)}K';
    return _balance.toStringAsFixed(4);
  }

  /// Initialize — check if wallet exists + seed price data
  Future<void> init() async {
    _hasWallet = await _walletService.hasWallet();
    // Load last known price & seed initial chart data
    await PriceService.loadLastPrice();
    _tpixPrice = PriceService.lastPrice;
    await PriceService.seedInitialData();
    notifyListeners();
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
      return result;
    } catch (e) {
      _error = e.toString();
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
    } catch (e) {
      _error = e.toString();
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
    } catch (e) {
      _error = e.toString();
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
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final success = await _walletService.unlockWallet(pin);
      if (success) {
        _isUnlocked = true;
        _address = _walletService.address;
        _mnemonic = _walletService.mnemonic;
        // Update biometric token if biometric is enabled
        final bioService = BiometricService();
        if (await bioService.isEnabled()) {
          await _walletService.saveBiometricToken(pin);
        }
        await refreshBalance();
        await loadTxHistory();
        await loadTokens();
        loadChainBalances(); // Load multi-chain balances in background
        _startBalanceRefresh();
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
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final success = await _walletService.unlockWithBiometric();
      if (success) {
        _isUnlocked = true;
        _address = _walletService.address;
        _mnemonic = _walletService.mnemonic;
        await refreshBalance();
        await loadTxHistory();
        await loadTokens();
        _startBalanceRefresh();
      }
      return success;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Save biometric token after successful PIN unlock
  Future<void> saveBiometricToken(String pin) async {
    await _walletService.saveBiometricToken(pin);
  }

  /// Clear biometric token
  Future<void> clearBiometricToken() async {
    await _walletService.clearBiometricToken();
  }

  /// Refresh balance + price
  Future<void> refreshBalance() async {
    try {
      _balance = await _walletService.getBalance();
      // Fetch latest price in background
      _tpixPrice = await PriceService.fetchPrice();
      notifyListeners();
    } catch (_) {}
  }

  /// Send TPIX
  Future<String> sendTPIX(String toAddress, double amount) async {
    _isLoading = true;
    _error = null;
    _lastTxHash = null;
    notifyListeners();

    try {
      final txHash = await _walletService.sendTPIX(
        toAddress: toAddress,
        amount: amount,
      );
      _lastTxHash = txHash;
      await refreshBalance();
      await loadTxHistory();
      _startTxPolling(txHash);
      return txHash;
    } catch (e) {
      _error = e.toString();
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ═══════════════════════════════════════════════════════════
  //  Multi-Chain Operations
  // ═══════════════════════════════════════════════════════════

  /// Switch active chain
  Future<void> switchChain(int chainId) async {
    _activeChainId = chainId;
    notifyListeners();
    await loadChainBalances();
  }

  /// Load native balances for all supported chains in background
  Future<void> loadChainBalances() async {
    if (_address == null) return;
    for (final chain in ChainConfig.all) {
      if (chain.chainId == 4289) {
        // TPIX balance is already managed by _balance
        continue;
      }
      try {
        final bal = await SwapService.getNativeBalance(chain, _address!);
        _chainBalances[chain.chainId] = bal;
      } catch (_) {}
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
      await _walletService.switchWallet(slot);
      _address = _walletService.address;
      await refreshBalance();
      await loadTxHistory();
      await loadTokens();
    } catch (e) {
      _error = e.toString();
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
      await _walletService.persistWallets(); // Save wallet list (PIN already set)
      await refreshBalance();
      await loadTxHistory();
      return result;
    } catch (e) {
      _error = e.toString();
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
    await _walletService.deleteWalletBySlot(slot);
    _address = _walletService.address;
    if (_walletService.walletCount > 0) {
      await refreshBalance();
      await loadTxHistory();
    } else {
      _balance = 0;
      _txHistory = [];
    }
    _hasWallet = _walletService.walletCount > 0;
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════
  //  Transaction History
  // ═══════════════════════════════════════════════════════════

  /// Load tx history from local storage
  Future<void> loadTxHistory() async {
    _txHistory = await _walletService.getActiveTxHistory();
    notifyListeners();
  }

  /// Scan blockchain for recent transactions
  Future<void> scanTransactions({int blockCount = 50}) async {
    if (_isScanning) return;
    _isScanning = true;
    notifyListeners();

    try {
      await _walletService.scanRecentTransactions(blockCount: blockCount);
      await loadTxHistory();
    } catch (_) {}

    _isScanning = false;
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════
  //  Custom Tokens
  // ═══════════════════════════════════════════════════════════

  /// Load tokens from SQLite
  Future<void> loadTokens() async {
    _tokens = await DbService.getTokensForSlot(_walletService.activeSlot);
    notifyListeners();
    // Refresh balances in background
    refreshTokenBalances();
  }

  /// Refresh all token balances
  Future<void> refreshTokenBalances() async {
    if (_address == null || _tokens.isEmpty) return;
    _tokenBalances = await TokenService.getAllTokenBalances(
      _walletService.activeSlot,
      _address!,
    );
    notifyListeners();
  }

  /// Remove a token
  Future<void> removeToken(String contractAddress) async {
    await DbService.removeToken(contractAddress, _walletService.activeSlot);
    _tokenBalances.remove(contractAddress.toLowerCase());
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
          _txPollTimer?.cancel();
          _pendingTxHash = null;
        }
      },
    );
  }

  /// Lock wallet
  void lock() {
    _walletService.lock();
    _isUnlocked = false;
    _balanceTimer?.cancel();
    _txPollTimer?.cancel();
    _pendingTxHash = null;
    _tokens = [];
    _tokenBalances = {};
    _chainBalances = {};
    _activeChainId = 4289;
    notifyListeners();
  }

  /// Delete ALL wallets
  Future<void> deleteWallet() async {
    await _walletService.deleteWallet();
    _hasWallet = false;
    _isUnlocked = false;
    _address = null;
    _balance = 0;
    _mnemonic = null;
    _txHistory = [];
    _tokens = [];
    _tokenBalances = {};
    _chainBalances = {};
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
      (_) {
        refreshBalance();
        refreshTokenBalances();
      },
    );
  }

  @override
  void dispose() {
    _balanceTimer?.cancel();
    _txPollTimer?.cancel();
    _walletService.dispose();
    super.dispose();
  }
}
