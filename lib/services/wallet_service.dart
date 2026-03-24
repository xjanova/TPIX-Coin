import 'dart:convert';
import 'dart:math';
import 'package:bip39/bip39.dart' as bip39;
import 'package:bip32/bip32.dart' as bip32;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hex/hex.dart';
import 'package:web3dart/web3dart.dart';
import 'package:http/http.dart' as http;

/// TPIX Chain Configuration
class TpixChain {
  static const int chainId = 4289;
  static const String rpcUrl = 'https://rpc.tpix.online';
  static const String explorerUrl = 'https://explorer.tpix.online';
  static const String symbol = 'TPIX';
  static const String name = 'TPIX Chain';
  static const int decimals = 18;
}

/// Secure wallet service for TPIX Chain
class WalletService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const _keyMnemonic = 'tpix_mnemonic';
  static const _keyPrivateKey = 'tpix_private_key';
  static const _keyAddress = 'tpix_address';
  static const _keyPin = 'tpix_pin_hash';

  Web3Client? _web3;
  EthPrivateKey? _credentials;
  String? _address;
  String? _mnemonic;

  String? get address => _address;
  String? get mnemonic => _mnemonic;
  bool get isUnlocked => _credentials != null;

  String get shortAddress {
    if (_address == null) return '';
    return '${_address!.substring(0, 6)}...${_address!.substring(_address!.length - 4)}';
  }

  Web3Client get web3 {
    _web3 ??= Web3Client(TpixChain.rpcUrl, http.Client());
    return _web3!;
  }

  // ================================================================
  // Wallet Creation
  // ================================================================

  /// Create a new wallet from fresh mnemonic
  Future<Map<String, String>> createWallet() async {
    final mnemonic = bip39.generateMnemonic(strength: 128); // 12 words
    final seed = bip39.mnemonicToSeed(mnemonic);
    final root = bip32.BIP32.fromSeed(seed);
    final child = root.derivePath("m/44'/60'/0'/0/0");

    final privateKeyHex = HEX.encode(child.privateKey!);
    final credentials = EthPrivateKey.fromHex(privateKeyHex);
    final address = credentials.address.hex;

    _mnemonic = mnemonic;
    _credentials = credentials;
    _address = address;

    return {
      'mnemonic': mnemonic,
      'address': address,
      'privateKey': privateKeyHex,
    };
  }

  /// Import wallet from mnemonic phrase
  Future<String> importFromMnemonic(String mnemonic) async {
    if (!bip39.validateMnemonic(mnemonic.trim())) {
      throw Exception('Invalid mnemonic phrase');
    }

    final seed = bip39.mnemonicToSeed(mnemonic.trim());
    final root = bip32.BIP32.fromSeed(seed);
    final child = root.derivePath("m/44'/60'/0'/0/0");

    final privateKeyHex = HEX.encode(child.privateKey!);
    final credentials = EthPrivateKey.fromHex(privateKeyHex);

    _mnemonic = mnemonic.trim();
    _credentials = credentials;
    _address = credentials.address.hex;

    return _address!;
  }

  /// Import wallet from private key
  Future<String> importFromPrivateKey(String privateKey) async {
    final key = privateKey.startsWith('0x') ? privateKey.substring(2) : privateKey;
    final credentials = EthPrivateKey.fromHex(key);

    _credentials = credentials;
    _address = credentials.address.hex;
    _mnemonic = null;

    return _address!;
  }

  // ================================================================
  // Secure Storage
  // ================================================================

  /// Save wallet to encrypted storage
  Future<void> saveWallet(String pin) async {
    if (_credentials == null || _address == null) {
      throw Exception('No wallet to save');
    }

    final pinHash = _hashPin(pin);
    final privateKeyHex = HEX.encode(_credentials!.privateKey.sublist(0));

    await _storage.write(key: _keyAddress, value: _address);
    await _storage.write(key: _keyPrivateKey, value: privateKeyHex);
    await _storage.write(key: _keyPin, value: pinHash);

    if (_mnemonic != null) {
      await _storage.write(key: _keyMnemonic, value: _mnemonic);
    }
  }

  /// Load wallet from storage (requires PIN)
  Future<bool> unlockWallet(String pin) async {
    final storedPinHash = await _storage.read(key: _keyPin);
    if (storedPinHash == null) return false;

    if (_hashPin(pin) != storedPinHash) return false;

    final privateKeyHex = await _storage.read(key: _keyPrivateKey);
    final address = await _storage.read(key: _keyAddress);
    final mnemonic = await _storage.read(key: _keyMnemonic);

    if (privateKeyHex == null || address == null) return false;

    _credentials = EthPrivateKey.fromHex(privateKeyHex);
    _address = address;
    _mnemonic = mnemonic;

    return true;
  }

  /// Check if wallet exists in storage
  Future<bool> hasWallet() async {
    final address = await _storage.read(key: _keyAddress);
    return address != null;
  }

  /// Delete wallet from storage
  Future<void> deleteWallet() async {
    await _storage.deleteAll();
    _credentials = null;
    _address = null;
    _mnemonic = null;
  }

  // ================================================================
  // Blockchain Operations
  // ================================================================

  /// Get TPIX balance
  Future<double> getBalance() async {
    if (_address == null) return 0;

    try {
      final balance = await web3.getBalance(
        EthereumAddress.fromHex(_address!),
      );
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

    final amountInWei = BigInt.from(amount * 1e18);

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

    return tx;
  }

  /// Get transaction count (nonce)
  Future<int> getTransactionCount() async {
    if (_address == null) return 0;
    return await web3.getTransactionCount(
      EthereumAddress.fromHex(_address!),
    );
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
