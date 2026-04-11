import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/token_info.dart';
import 'db_service.dart';
import 'wallet_service.dart';

/// Service for querying ERC-20 token contracts on TPIX Chain
class TokenService {
  // ERC-20 function signatures (first 4 bytes of keccak256 hash)
  static const _nameSelector = '0x06fdde03';       // name()
  static const _symbolSelector = '0x95d89b41';     // symbol()
  static const _decimalsSelector = '0x313ce567';   // decimals()
  static const _balanceOfSelector = '0x70a08231';  // balanceOf(address)
  static const _totalSupplySelector = '0x18160ddd'; // totalSupply()

  /// Fetch token info from a smart contract address on TPIX Chain
  /// Returns null if address is not a valid ERC-20 contract
  static Future<TokenInfo?> fetchTokenInfo(String contractAddress, int walletSlot) async {
    final addr = contractAddress.toLowerCase();
    if (!RegExp(r'^0x[0-9a-fA-F]{40}$').hasMatch(addr)) return null;

    try {
      // Query name, symbol, decimals in parallel
      final results = await Future.wait([
        _callContract(addr, _nameSelector),
        _callContract(addr, _symbolSelector),
        _callContract(addr, _decimalsSelector),
      ]);

      final name = _decodeString(results[0]);
      final symbol = _decodeString(results[1]);
      final decimals = _decodeUint(results[2]);

      if (name == null || symbol == null) return null;

      return TokenInfo(
        contractAddress: addr,
        name: name,
        symbol: symbol,
        decimals: decimals ?? 18,
        walletSlot: walletSlot,
      );
    } catch (_) {
      return null;
    }
  }

  /// Get ERC-20 token balance for a wallet address
  static Future<BigInt> getTokenBalance(String contractAddress, String walletAddress) async {
    try {
      // balanceOf(address) — pad address to 32 bytes
      final paddedAddr = walletAddress.toLowerCase().replaceFirst('0x', '').padLeft(64, '0');
      final data = '$_balanceOfSelector$paddedAddr';
      final result = await _callContract(contractAddress.toLowerCase(), data);
      if (result == null || result == '0x') return BigInt.zero;
      return BigInt.parse(result.replaceFirst('0x', ''), radix: 16);
    } catch (_) {
      return BigInt.zero;
    }
  }

  /// Get formatted token balance (human-readable)
  static Future<double> getFormattedBalance(String contractAddress, String walletAddress, int decimals) async {
    final balanceWei = await getTokenBalance(contractAddress, walletAddress);
    if (balanceWei == BigInt.zero) return 0.0;
    final divisor = BigInt.from(10).pow(decimals);
    final whole = balanceWei ~/ divisor;
    final frac = balanceWei % divisor;
    final fracStr = frac.toString().padLeft(decimals, '0');
    final displayDecimals = fracStr.length < 6 ? fracStr.length : 6;
    return double.parse('$whole.${fracStr.substring(0, displayDecimals)}');
  }

  /// Get all token balances for a wallet slot
  static Future<Map<String, double>> getAllTokenBalances(int walletSlot, String walletAddress) async {
    final tokens = await DbService.getTokensForSlot(walletSlot);
    final balances = <String, double>{};
    for (final token in tokens) {
      balances[token.contractAddress] = await getFormattedBalance(
        token.contractAddress,
        walletAddress,
        token.decimals,
      );
    }
    return balances;
  }

  /// Verify if a contract is a valid ERC-20 by checking totalSupply
  static Future<bool> isErc20Contract(String contractAddress) async {
    try {
      final result = await _callContract(contractAddress.toLowerCase(), _totalSupplySelector);
      return result != null && result != '0x' && result.length > 2;
    } catch (_) {
      return false;
    }
  }

  // ================================================================
  // Known tokens on TPIX Chain (can be expanded)
  // ================================================================

  /// Get list of known/popular tokens on TPIX Chain
  static List<Map<String, String>> get knownTokens => [
    // Add known TPIX Chain tokens here as they launch
    // {'address': '0x...', 'name': 'Wrapped TPIX', 'symbol': 'WTPIX'},
  ];

  // ================================================================
  // RPC Helpers
  // ================================================================

  /// Call a smart contract via eth_call
  static Future<String?> _callContract(String to, String data) async {
    final client = http.Client();
    try {
      final response = await client.post(
        Uri.parse(TpixChain.rpcUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'jsonrpc': '2.0',
          'method': 'eth_call',
          'params': [
            {'to': to, 'data': data},
            'latest',
          ],
          'id': 1,
        }),
      ).timeout(const Duration(seconds: 10));

      final body = jsonDecode(response.body);
      final result = body['result'] as String?;
      if (result == null || result == '0x') return null;
      return result;
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }

  /// Decode ABI-encoded string return value
  static String? _decodeString(String? hex) {
    if (hex == null || hex.length < 130) return null; // min: 0x + 64 offset + 64 length + 2
    try {
      final raw = hex.replaceFirst('0x', '');
      // ABI string: bytes32 offset, bytes32 length, then data
      // offset is at 0..63, length at 64..127, data starts at 128
      final lengthHex = raw.substring(64, 128);
      final length = int.parse(lengthHex, radix: 16);
      if (length == 0 || length > 256) return null;

      final dataHex = raw.substring(128, 128 + length * 2);
      final bytes = <int>[];
      for (var i = 0; i < dataHex.length; i += 2) {
        bytes.add(int.parse(dataHex.substring(i, i + 2), radix: 16));
      }
      return String.fromCharCodes(bytes).trim();
    } catch (_) {
      // Fallback: try bytes32 encoding (some tokens return fixed-length)
      try {
        final raw = hex.replaceFirst('0x', '');
        final bytes = <int>[];
        for (var i = 0; i < raw.length && i < 64; i += 2) {
          final b = int.parse(raw.substring(i, i + 2), radix: 16);
          if (b == 0) break;
          bytes.add(b);
        }
        final s = String.fromCharCodes(bytes).trim();
        return s.isNotEmpty ? s : null;
      } catch (_) {
        return null;
      }
    }
  }

  /// Decode ABI-encoded uint256 return value
  static int? _decodeUint(String? hex) {
    if (hex == null || hex.length < 66) return null;
    try {
      final raw = hex.replaceFirst('0x', '');
      return int.parse(raw.substring(0, 64), radix: 16);
    } catch (_) {
      return null;
    }
  }
}
