import 'dart:convert';
import 'dart:math';
import 'package:bip39/bip39.dart' as bip39;
import 'package:bip32/bip32.dart' as bip32;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hex/hex.dart';
import 'package:web3dart/web3dart.dart';
import 'package:http/http.dart' as http;
import '../models/wallet_info.dart';
import '../models/tx_record.dart';

/// TPIX Chain Configuration
class TpixChain {
  static const int chainId = 4289;
  static const String rpcUrl = 'https://rpc.tpix.online';
  static const String explorerUrl = 'https://explorer.tpix.online';
  static const String symbol = 'TPIX';
  static const String name = 'TPIX Chain';
  static const int decimals = 18;
}

/// Multi-wallet service for TPIX Chain (up to 128 wallets)
class WalletService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const int maxWallets = 128;
  static const String _hdPath = "m/44'/4289'/0'/0/";

  // Storage keys
  static const _keyPin = 'tpix_pin_hash';
  static const _keyWallets = 'tpix_wallets';      // JSON array of WalletInfo
  static const _keyActiveSlot = 'tpix_active_slot';
  static const _keyMnemonic = 'tpix_mnemonic';    // HD seed (shared)
  static const _keyTxHistory = 'tpix_tx_history';  // JSON map { slot: [TxRecord] }

  // Legacy single-wallet keys (for migration)
  static const _legacyKeyAddress = 'tpix_address';
  static const _legacyKeyPrivateKey = 'tpix_private_key';
  // Note: legacy mnemonic key is same as _keyMnemonic — no migration needed

  Web3Client? _web3;
  EthPrivateKey? _credentials;
  String? _address;
  String? _mnemonic;

  List<WalletInfo> _wallets = [];
  int _activeSlot = -1;

  String? get address => _address;
  String? get mnemonic => _mnemonic;
  bool get isUnlocked => _credentials != null;
  int get activeSlot => _activeSlot;
  List<WalletInfo> get wallets => List.unmodifiable(_wallets);
  int get walletCount => _wallets.length;

  WalletInfo? get activeWallet {
    try {
      return _wallets.firstWhere((w) => w.slot == _activeSlot);
    } catch (_) {
      return _wallets.isNotEmpty ? _wallets.first : null;
    }
  }

  String get shortAddress {
    if (_address == null) return '';
    return '${_address!.substring(0, 6)}...${_address!.substring(_address!.length - 4)}';
  }

  Web3Client get web3 {
    _web3 ??= Web3Client(TpixChain.rpcUrl, http.Client());
    return _web3!;
  }

  // ================================================================
  // Multi-Wallet Management
  // ================================================================

  /// Get next available slot (1-128)
  int _nextSlot() {
    final usedSlots = _wallets.map((w) => w.slot).toSet();
    for (int i = 1; i <= maxWallets; i++) {
      if (!usedSlots.contains(i)) return i;
    }
    throw Exception('Maximum $maxWallets wallets reached');
  }

  /// Create a new HD wallet from the shared seed
  Future<Map<String, String>> createWallet({String? name}) async {
    if (_wallets.length >= maxWallets) {
      throw Exception('Maximum $maxWallets wallets reached');
    }

    // Generate or load mnemonic
    String mnemonic;
    if (_mnemonic != null) {
      mnemonic = _mnemonic!;
    } else {
      final stored = await _storage.read(key: _keyMnemonic);
      if (stored != null) {
        mnemonic = stored;
        _mnemonic = stored;
      } else {
        mnemonic = bip39.generateMnemonic(strength: 128); // 12 words
        _mnemonic = mnemonic;
      }
    }

    final slot = _nextSlot();
    final hdIndex = _wallets.where((w) => w.isHD).length; // next HD index
    final walletName = name ?? 'Wallet $slot';

    // Derive key from HD path
    final seed = bip39.mnemonicToSeed(mnemonic);
    final root = bip32.BIP32.fromSeed(seed);
    final child = root.derivePath("$_hdPath$hdIndex");

    final privateKeyHex = HEX.encode(child.privateKey!);
    final credentials = EthPrivateKey.fromHex(privateKeyHex);
    final address = credentials.address.hex;

    // Add wallet info
    final walletInfo = WalletInfo(
      slot: slot,
      name: walletName,
      address: address,
      isHD: true,
    );
    _wallets.add(walletInfo);

    // Set as active
    _activeSlot = slot;
    _credentials = credentials;
    _address = address;

    // Store private key
    await _storage.write(key: 'tpix_pk_$slot', value: privateKeyHex);

    return {
      'mnemonic': mnemonic,
      'address': address,
      'privateKey': privateKeyHex,
      'slot': slot.toString(),
    };
  }

  /// Import wallet from mnemonic (recovers first wallet)
  Future<String> importFromMnemonic(String mnemonic) async {
    if (!bip39.validateMnemonic(mnemonic.trim())) {
      throw Exception('Invalid mnemonic phrase');
    }

    _mnemonic = mnemonic.trim();

    final seed = bip39.mnemonicToSeed(_mnemonic!);
    final root = bip32.BIP32.fromSeed(seed);
    final child = root.derivePath("${_hdPath}0");

    final privateKeyHex = HEX.encode(child.privateKey!);
    final credentials = EthPrivateKey.fromHex(privateKeyHex);

    final slot = _nextSlot();
    final address = credentials.address.hex;

    final walletInfo = WalletInfo(
      slot: slot,
      name: 'Wallet $slot',
      address: address,
      isHD: true,
    );
    _wallets.add(walletInfo);
    _activeSlot = slot;
    _credentials = credentials;
    _address = address;

    await _storage.write(key: 'tpix_pk_$slot', value: privateKeyHex);

    return address;
  }

  /// Import wallet from private key
  Future<String> importFromPrivateKey(String privateKey) async {
    final key = privateKey.startsWith('0x') ? privateKey.substring(2) : privateKey;
    final credentials = EthPrivateKey.fromHex(key);

    final slot = _nextSlot();
    final address = credentials.address.hex;

    // Check for duplicate address
    if (_wallets.any((w) => w.address.toLowerCase() == address.toLowerCase())) {
      throw Exception('Wallet already exists');
    }

    final walletInfo = WalletInfo(
      slot: slot,
      name: 'Imported $slot',
      address: address,
      isHD: false,
    );
    _wallets.add(walletInfo);
    _activeSlot = slot;
    _credentials = credentials;
    _address = address;

    await _storage.write(key: 'tpix_pk_$slot', value: key);

    return address;
  }

  /// Switch to a different wallet
  Future<void> switchWallet(int slot) async {
    final wallet = _wallets.firstWhere(
      (w) => w.slot == slot,
      orElse: () => throw Exception('Wallet not found'),
    );

    final pk = await _storage.read(key: 'tpix_pk_$slot');
    if (pk == null) throw Exception('Private key not found');

    _credentials = EthPrivateKey.fromHex(pk);
    _address = wallet.address;
    _activeSlot = slot;

    await _storage.write(key: _keyActiveSlot, value: slot.toString());
  }

  /// Rename wallet
  Future<void> renameWallet(int slot, String newName) async {
    final index = _wallets.indexWhere((w) => w.slot == slot);
    if (index == -1) throw Exception('Wallet not found');

    _wallets[index] = WalletInfo(
      slot: _wallets[index].slot,
      name: newName,
      address: _wallets[index].address,
      isHD: _wallets[index].isHD,
      createdAt: _wallets[index].createdAt,
    );
    await _saveWalletList();
  }

  /// Delete a wallet
  Future<void> deleteWalletBySlot(int slot) async {
    final index = _wallets.indexWhere((w) => w.slot == slot);
    if (index == -1) throw Exception('Wallet not found');

    _wallets.removeAt(index);
    await _storage.delete(key: 'tpix_pk_$slot');

    // If deleted active wallet, switch to first remaining
    if (_activeSlot == slot && _wallets.isNotEmpty) {
      await switchWallet(_wallets.first.slot);
    } else if (_wallets.isEmpty) {
      _activeSlot = -1;
      _credentials = null;
      _address = null;
    }
    await _saveWalletList();
  }

  // ================================================================
  // Secure Storage
  // ================================================================

  /// Save all wallets + PIN to encrypted storage
  Future<void> saveWallet(String pin) async {
    if (_credentials == null || _address == null) {
      throw Exception('No wallet to save');
    }

    final pinHash = _hashPin(pin);
    await _storage.write(key: _keyPin, value: pinHash);

    if (_mnemonic != null) {
      await _storage.write(key: _keyMnemonic, value: _mnemonic);
    }

    await _saveWalletList();
    await _storage.write(key: _keyActiveSlot, value: _activeSlot.toString());
  }

  /// Persist wallet list + active slot (no PIN change)
  Future<void> persistWallets() async {
    await _saveWalletList();
    await _storage.write(key: _keyActiveSlot, value: _activeSlot.toString());
    if (_mnemonic != null) {
      await _storage.write(key: _keyMnemonic, value: _mnemonic);
    }
  }

  /// Save wallet list to storage
  Future<void> _saveWalletList() async {
    final json = jsonEncode(_wallets.map((w) => w.toJson()).toList());
    await _storage.write(key: _keyWallets, value: json);
  }

  /// Load wallet from storage (requires PIN)
  Future<bool> unlockWallet(String pin) async {
    final storedPinHash = await _storage.read(key: _keyPin);
    if (storedPinHash == null) return false;
    if (_hashPin(pin) != storedPinHash) return false;

    // Load wallet list
    final walletsJson = await _storage.read(key: _keyWallets);
    if (walletsJson != null) {
      final list = jsonDecode(walletsJson) as List;
      _wallets = list.map((j) => WalletInfo.fromJson(j as Map<String, dynamic>)).toList();
    } else {
      // Migrate from legacy single-wallet storage
      await _migrateLegacy();
    }

    // Load mnemonic
    _mnemonic = await _storage.read(key: _keyMnemonic);

    // Load active slot
    final activeSlotStr = await _storage.read(key: _keyActiveSlot);
    if (activeSlotStr != null) {
      _activeSlot = int.tryParse(activeSlotStr) ?? -1;
    }
    if (_activeSlot == -1 && _wallets.isNotEmpty) {
      _activeSlot = _wallets.first.slot;
    }

    // Load active wallet credentials
    if (_activeSlot > 0) {
      final pk = await _storage.read(key: 'tpix_pk_$_activeSlot');
      if (pk != null) {
        _credentials = EthPrivateKey.fromHex(pk);
        _address = activeWallet?.address;
      }
    }

    return _credentials != null;
  }

  /// Migrate from legacy single-wallet to multi-wallet storage
  Future<void> _migrateLegacy() async {
    final legacyAddress = await _storage.read(key: _legacyKeyAddress);
    final legacyPK = await _storage.read(key: _legacyKeyPrivateKey);

    if (legacyAddress != null && legacyPK != null) {
      const slot = 1;
      final walletInfo = WalletInfo(
        slot: slot,
        name: 'Wallet 1',
        address: legacyAddress,
        isHD: true,
      );
      _wallets = [walletInfo];
      _activeSlot = slot;

      // Move PK to new key format
      await _storage.write(key: 'tpix_pk_$slot', value: legacyPK);
      await _saveWalletList();
      await _storage.write(key: _keyActiveSlot, value: slot.toString());

      // Clean up legacy keys
      await _storage.delete(key: _legacyKeyAddress);
      await _storage.delete(key: _legacyKeyPrivateKey);
    }
  }

  /// Check if wallet exists in storage
  Future<bool> hasWallet() async {
    final walletsJson = await _storage.read(key: _keyWallets);
    if (walletsJson != null) {
      final list = jsonDecode(walletsJson) as List;
      return list.isNotEmpty;
    }
    // Legacy check
    final address = await _storage.read(key: _legacyKeyAddress);
    return address != null;
  }

  /// Delete ALL wallets
  Future<void> deleteWallet() async {
    await _storage.deleteAll();
    _credentials = null;
    _address = null;
    _mnemonic = null;
    _wallets = [];
    _activeSlot = -1;
  }

  // ================================================================
  // Transaction History (Local Storage)
  // ================================================================

  /// Save a transaction record
  Future<void> saveTxRecord(TxRecord tx) async {
    final history = await getTxHistory();
    final key = _activeSlot.toString();
    history[key] ??= [];
    // Prevent duplicates
    if (history[key]!.any((t) => t.txHash == tx.txHash)) return;
    history[key]!.insert(0, tx); // newest first
    // Keep max 200 per wallet
    if (history[key]!.length > 200) {
      history[key] = history[key]!.sublist(0, 200);
    }
    await _saveTxHistory(history);
  }

  /// Get transaction history for active wallet
  Future<List<TxRecord>> getActiveTxHistory() async {
    final history = await getTxHistory();
    return history[_activeSlot.toString()] ?? [];
  }

  /// Get all transaction history
  Future<Map<String, List<TxRecord>>> getTxHistory() async {
    final json = await _storage.read(key: _keyTxHistory);
    if (json == null) return {};
    final map = jsonDecode(json) as Map<String, dynamic>;
    return map.map((key, value) {
      final list = (value as List).map((j) => TxRecord.fromJson(j as Map<String, dynamic>)).toList();
      return MapEntry(key, list);
    });
  }

  Future<void> _saveTxHistory(Map<String, List<TxRecord>> history) async {
    final map = history.map((key, value) {
      return MapEntry(key, value.map((t) => t.toJson()).toList());
    });
    await _storage.write(key: _keyTxHistory, value: jsonEncode(map));
  }

  /// Scan recent blocks for incoming/outgoing transactions via RPC
  Future<List<TxRecord>> scanRecentTransactions({int blockCount = 50}) async {
    if (_address == null) return [];

    final found = <TxRecord>[];
    final addr = _address!.toLowerCase();
    final client = http.Client();

    try {
      final latestBlock = await web3.getBlockNumber();
      final startBlock = max(0, latestBlock - blockCount);

      for (int i = latestBlock; i >= startBlock; i--) {
        try {
          // Use raw RPC to get block with full transactions
          final response = await client.post(
            Uri.parse(TpixChain.rpcUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'jsonrpc': '2.0',
              'method': 'eth_getBlockByNumber',
              'params': ['0x${i.toRadixString(16)}', true], // true = include full txs
              'id': i,
            }),
          );

          final body = jsonDecode(response.body);
          final block = body['result'];
          if (block == null) continue;

          final txs = block['transactions'] as List? ?? [];
          final blockTimestamp = block['timestamp'] != null
              ? int.parse(block['timestamp'].toString().replaceFirst('0x', ''), radix: 16)
              : DateTime.now().millisecondsSinceEpoch ~/ 1000;

          for (final txData in txs) {
            final from = (txData['from'] as String? ?? '').toLowerCase();
            final to = (txData['to'] as String? ?? '').toLowerCase();

            if (from == addr || to == addr) {
              final valueHex = txData['value'] as String? ?? '0x0';
              final valueWei = BigInt.parse(valueHex.replaceFirst('0x', ''), radix: 16);
              final direction = from == addr ? 'sent' : 'received';

              final tx = TxRecord(
                txHash: txData['hash'] as String,
                fromAddress: txData['from'] as String? ?? '',
                toAddress: txData['to'] as String? ?? '',
                value: valueWei.toString(),
                direction: direction,
                status: 'confirmed',
                blockNumber: i,
                timestamp: blockTimestamp,
              );
              found.add(tx);
              await saveTxRecord(tx);
            }
          }
        } catch (_) {
          // Skip problematic blocks
        }
      }
    } catch (_) {
      // Network error
    } finally {
      client.close();
    }

    return found;
  }

  // ================================================================
  // Blockchain Operations
  // ================================================================

  /// Get TPIX balance for active wallet
  Future<double> getBalance() async {
    if (_address == null) return 0;
    try {
      final balance = await web3.getBalance(EthereumAddress.fromHex(_address!));
      return balance.getValueInUnit(EtherUnit.ether).toDouble();
    } catch (e) {
      return 0;
    }
  }

  /// Get balance for a specific address
  Future<double> getBalanceForAddress(String address) async {
    try {
      final balance = await web3.getBalance(EthereumAddress.fromHex(address));
      return balance.getValueInUnit(EtherUnit.ether).toDouble();
    } catch (e) {
      return 0;
    }
  }

  /// Send TPIX to another address
  Future<String> sendTPIX({
    required String toAddress,
    required double amount,
  }) async {
    if (_credentials == null) throw Exception('Wallet not unlocked');

    // Use string conversion to avoid double precision loss
    final parts = amount.toStringAsFixed(18).split('.');
    final whole = BigInt.parse(parts[0]);
    final frac = parts.length > 1 ? parts[1].padRight(18, '0').substring(0, 18) : '0' * 18;
    final amountInWei = whole * BigInt.from(10).pow(18) + BigInt.parse(frac);

    final tx = await web3.sendTransaction(
      _credentials!,
      Transaction(
        to: EthereumAddress.fromHex(toAddress),
        value: EtherAmount.inWei(amountInWei),
        gasPrice: EtherAmount.inWei(BigInt.zero), // TPIX Chain is gasless
        maxGas: 21000,
      ),
      chainId: TpixChain.chainId,
    );

    // Store transaction locally
    final txRecord = TxRecord(
      txHash: tx,
      fromAddress: _address!,
      toAddress: toAddress,
      value: amountInWei.toString(),
      direction: 'sent',
      status: 'pending',
    );
    await saveTxRecord(txRecord);

    return tx;
  }

  /// Get transaction count (nonce)
  Future<int> getTransactionCount() async {
    if (_address == null) return 0;
    return await web3.getTransactionCount(EthereumAddress.fromHex(_address!));
  }

  // ================================================================
  // Helpers
  // ================================================================

  String _hashPin(String pin) {
    final bytes = utf8.encode(pin + 'tpix_salt_v1');
    var hash = 0;
    for (var byte in bytes) {
      hash = ((hash << 5) - hash + byte) & 0xFFFFFFFF;
    }
    return hash.toRadixString(16);
  }

  void lock() {
    _credentials = null;
  }

  void dispose() {
    _web3?.dispose();
    _credentials = null;
  }
}
