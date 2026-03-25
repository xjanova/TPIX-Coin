import 'dart:async';
import 'package:flutter/material.dart';
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

  Timer? _balanceTimer;

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

  String get formattedBalance {
    if (_balance >= 1000000) return '${(_balance / 1000000).toStringAsFixed(2)}M';
    if (_balance >= 1000) return '${(_balance / 1000).toStringAsFixed(2)}K';
    return _balance.toStringAsFixed(4);
  }

  /// Initialize — check if wallet exists
  Future<void> init() async {
    _hasWallet = await _walletService.hasWallet();
    notifyListeners();
  }

  /// Create new wallet
  Future<Map<String, String>> createWallet() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final result = await _walletService.createWallet();
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
  Future<void> importFromMnemonic(String mnemonic) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _address = await _walletService.importFromMnemonic(mnemonic);
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
  Future<void> importFromPrivateKey(String key) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _address = await _walletService.importFromPrivateKey(key);
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
        await refreshBalance();
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

  /// Refresh balance
  Future<void> refreshBalance() async {
    try {
      _balance = await _walletService.getBalance();
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
      return txHash;
    } catch (e) {
      _error = e.toString();
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Lock wallet
  void lock() {
    _walletService.lock();
    _isUnlocked = false;
    _balanceTimer?.cancel();
    notifyListeners();
  }

  /// Delete wallet
  Future<void> deleteWallet() async {
    await _walletService.deleteWallet();
    _hasWallet = false;
    _isUnlocked = false;
    _address = null;
    _balance = 0;
    _mnemonic = null;
    _balanceTimer?.cancel();
    notifyListeners();
  }

  void _startBalanceRefresh() {
    _balanceTimer?.cancel();
    _balanceTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => refreshBalance(),
    );
  }

  @override
  void dispose() {
    _balanceTimer?.cancel();
    _walletService.dispose();
    super.dispose();
  }
}
