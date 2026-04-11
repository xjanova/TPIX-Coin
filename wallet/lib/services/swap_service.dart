import 'dart:convert';
import 'dart:typed_data';
import 'package:hex/hex.dart';
import 'package:http/http.dart' as http;
import '../models/chain_config.dart';

/// DEX swap service — UniswapV2-compatible routers
/// Supports PancakeSwap (BSC), QuickSwap (Polygon), Uniswap V2 (ETH)
class SwapService {
  // UniswapV2Router02 function selectors
  static const _getAmountsOut = '0xd06ca61f';
  static const _swapExactTokensForTokens = '0x38ed1739';
  static const _swapExactETHForTokens = '0x7ff36ab5';
  static const _swapExactTokensForETH = '0x18cbafe5';

  // ERC-20 function selectors
  static const _approve = '0x095ea7b3';
  static const _allowance = '0xdd62ed3e';
  static const _balanceOf = '0x70a08231';

  // ================================================================
  // Quote
  // ================================================================

  /// Get swap quote — how much tokenOut for a given amountIn
  /// Returns null if quote fails (no liquidity, invalid pair, etc.)
  static Future<BigInt?> getQuote({
    required ChainConfig chain,
    required String tokenIn,
    required String tokenOut,
    required BigInt amountIn,
  }) async {
    if (chain.dexRouterAddress == null) return null;
    if (amountIn <= BigInt.zero) return null;

    try {
      // Build path — route through wrapped native if needed
      final path = _buildPath(chain, tokenIn, tokenOut);

      // ABI encode: getAmountsOut(uint256 amountIn, address[] path)
      final amountHex = amountIn.toRadixString(16).padLeft(64, '0');
      // offset to path array (64 bytes = 0x40)
      const pathOffset = '0000000000000000000000000000000000000000000000000000000000000040';
      final pathLength = path.length.toRadixString(16).padLeft(64, '0');
      final pathData = path.map((a) => a.toLowerCase().replaceFirst('0x', '').padLeft(64, '0')).join();

      final data = '$_getAmountsOut$amountHex$pathOffset$pathLength$pathData';

      final result = await _callContract(chain.rpcUrl, chain.dexRouterAddress!, data);
      if (result == null) return null;

      // Decode: returns uint256[] — last element is the output amount
      final raw = result.replaceFirst('0x', '');
      if (raw.length < 128) return null;

      // Array: offset(32) + length(32) + elements(32 each)
      final arrayOffset = int.parse(raw.substring(0, 64), radix: 16);
      final startPos = arrayOffset * 2;
      final arrayLength = int.parse(raw.substring(startPos, startPos + 64), radix: 16);
      // Last element
      final lastStart = startPos + 64 + (arrayLength - 1) * 64;
      final lastEnd = lastStart + 64;
      if (lastEnd > raw.length) return null;

      return BigInt.parse(raw.substring(lastStart, lastEnd), radix: 16);
    } catch (_) {
      return null;
    }
  }

  // ================================================================
  // Allowance & Approval
  // ================================================================

  /// Check ERC-20 allowance for the DEX router
  static Future<BigInt> checkAllowance({
    required ChainConfig chain,
    required String tokenAddress,
    required String ownerAddress,
  }) async {
    if (chain.dexRouterAddress == null) return BigInt.zero;
    try {
      final owner = ownerAddress.toLowerCase().replaceFirst('0x', '').padLeft(64, '0');
      final spender = chain.dexRouterAddress!.toLowerCase().replaceFirst('0x', '').padLeft(64, '0');
      final data = '$_allowance$owner$spender';

      final result = await _callContract(chain.rpcUrl, tokenAddress, data);
      if (result == null || result == '0x') return BigInt.zero;
      return BigInt.parse(result.replaceFirst('0x', ''), radix: 16);
    } catch (_) {
      return BigInt.zero;
    }
  }

  /// Build approval transaction data
  static Uint8List buildApproveData(String spenderAddress, BigInt amount) {
    final spender = spenderAddress.toLowerCase().replaceFirst('0x', '').padLeft(64, '0');
    final amountHex = amount.toRadixString(16).padLeft(64, '0');
    final hex = '${_approve.replaceFirst('0x', '')}$spender$amountHex';
    return Uint8List.fromList(HEX.decode(hex));
  }

  // ================================================================
  // Swap Execution
  // ================================================================

  /// Build swap transaction data
  static Uint8List buildSwapData({
    required ChainConfig chain,
    required String tokenIn,
    required String tokenOut,
    required BigInt amountIn,
    required BigInt amountOutMin,
    required String recipientAddress,
  }) {
    final isFromNative = tokenIn.toLowerCase() == TokenDef.nativeAddress.toLowerCase();
    final isToNative = tokenOut.toLowerCase() == TokenDef.nativeAddress.toLowerCase();
    final path = _buildPath(chain, tokenIn, tokenOut);
    final deadline = (DateTime.now().millisecondsSinceEpoch ~/ 1000 + 1200).toRadixString(16).padLeft(64, '0'); // 20 min

    String selector;
    String params;

    if (isFromNative) {
      // swapExactETHForTokens(uint amountOutMin, address[] path, address to, uint deadline)
      selector = _swapExactETHForTokens.replaceFirst('0x', '');
      final amountOutHex = amountOutMin.toRadixString(16).padLeft(64, '0');
      const pathOffset = '0000000000000000000000000000000000000000000000000000000000000080';
      final toAddr = recipientAddress.toLowerCase().replaceFirst('0x', '').padLeft(64, '0');
      final pathLength = path.length.toRadixString(16).padLeft(64, '0');
      final pathData = path.map((a) => a.toLowerCase().replaceFirst('0x', '').padLeft(64, '0')).join();
      params = '$amountOutHex$pathOffset$toAddr$deadline$pathLength$pathData';
    } else if (isToNative) {
      // swapExactTokensForETH(uint amountIn, uint amountOutMin, address[] path, address to, uint deadline)
      selector = _swapExactTokensForETH.replaceFirst('0x', '');
      final amountInHex = amountIn.toRadixString(16).padLeft(64, '0');
      final amountOutHex = amountOutMin.toRadixString(16).padLeft(64, '0');
      const pathOffset = '00000000000000000000000000000000000000000000000000000000000000a0';
      final toAddr = recipientAddress.toLowerCase().replaceFirst('0x', '').padLeft(64, '0');
      final pathLength = path.length.toRadixString(16).padLeft(64, '0');
      final pathData = path.map((a) => a.toLowerCase().replaceFirst('0x', '').padLeft(64, '0')).join();
      params = '$amountInHex$amountOutHex$pathOffset$toAddr$deadline$pathLength$pathData';
    } else {
      // swapExactTokensForTokens(uint amountIn, uint amountOutMin, address[] path, address to, uint deadline)
      selector = _swapExactTokensForTokens.replaceFirst('0x', '');
      final amountInHex = amountIn.toRadixString(16).padLeft(64, '0');
      final amountOutHex = amountOutMin.toRadixString(16).padLeft(64, '0');
      const pathOffset = '00000000000000000000000000000000000000000000000000000000000000a0';
      final toAddr = recipientAddress.toLowerCase().replaceFirst('0x', '').padLeft(64, '0');
      final pathLength = path.length.toRadixString(16).padLeft(64, '0');
      final pathData = path.map((a) => a.toLowerCase().replaceFirst('0x', '').padLeft(64, '0')).join();
      params = '$amountInHex$amountOutHex$pathOffset$toAddr$deadline$pathLength$pathData';
    }

    return Uint8List.fromList(HEX.decode('$selector$params'));
  }

  /// Calculate minimum output with slippage
  static BigInt applySlippage(BigInt amountOut, double slippagePercent) {
    final factor = ((1 - slippagePercent / 100) * 10000).round();
    return amountOut * BigInt.from(factor) ~/ BigInt.from(10000);
  }

  /// Get native token balance on a chain
  static Future<BigInt> getNativeBalance(ChainConfig chain, String address) async {
    try {
      final client = http.Client();
      try {
        final response = await client.post(
          Uri.parse(chain.rpcUrl),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'jsonrpc': '2.0',
            'method': 'eth_getBalance',
            'params': [address, 'latest'],
            'id': 1,
          }),
        ).timeout(const Duration(seconds: 10));
        final body = jsonDecode(response.body);
        final result = body['result'] as String?;
        if (result == null) return BigInt.zero;
        return BigInt.parse(result.replaceFirst('0x', ''), radix: 16);
      } finally {
        client.close();
      }
    } catch (_) {
      return BigInt.zero;
    }
  }

  /// Get ERC-20 token balance on a chain
  static Future<BigInt> getTokenBalance(ChainConfig chain, String tokenAddress, String walletAddress) async {
    try {
      final paddedAddr = walletAddress.toLowerCase().replaceFirst('0x', '').padLeft(64, '0');
      final data = '$_balanceOf$paddedAddr';
      final result = await _callContract(chain.rpcUrl, tokenAddress, data);
      if (result == null || result == '0x') return BigInt.zero;
      return BigInt.parse(result.replaceFirst('0x', ''), radix: 16);
    } catch (_) {
      return BigInt.zero;
    }
  }

  /// Get gas price for a chain
  static Future<BigInt> getGasPrice(ChainConfig chain) async {
    if (chain.isGasless) return BigInt.zero;
    try {
      final client = http.Client();
      try {
        final response = await client.post(
          Uri.parse(chain.rpcUrl),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'jsonrpc': '2.0',
            'method': 'eth_gasPrice',
            'params': [],
            'id': 1,
          }),
        ).timeout(const Duration(seconds: 10));
        final body = jsonDecode(response.body);
        final result = body['result'] as String?;
        if (result == null) return BigInt.zero;
        return BigInt.parse(result.replaceFirst('0x', ''), radix: 16);
      } finally {
        client.close();
      }
    } catch (_) {
      return BigInt.zero;
    }
  }

  // ================================================================
  // Helpers
  // ================================================================

  /// Build swap path — direct or via wrapped native
  static List<String> _buildPath(ChainConfig chain, String tokenIn, String tokenOut) {
    final isFromNative = tokenIn.toLowerCase() == TokenDef.nativeAddress.toLowerCase();
    final isToNative = tokenOut.toLowerCase() == TokenDef.nativeAddress.toLowerCase();
    final wrapped = chain.wrappedNativeAddress ?? TokenDef.nativeAddress;

    final actualIn = isFromNative ? wrapped : tokenIn;
    final actualOut = isToNative ? wrapped : tokenOut;

    // Direct pair
    return [actualIn, actualOut];
  }

  /// Raw eth_call
  static Future<String?> _callContract(String rpcUrl, String to, String data) async {
    final client = http.Client();
    try {
      final response = await client.post(
        Uri.parse(rpcUrl),
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
      ).timeout(const Duration(seconds: 15));
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

  /// Format BigInt amount to human-readable double
  static double formatAmount(BigInt amount, int decimals) {
    if (amount == BigInt.zero) return 0.0;
    final divisor = BigInt.from(10).pow(decimals);
    final whole = amount ~/ divisor;
    final frac = amount % divisor;
    final fracStr = frac.toString().padLeft(decimals, '0');
    final displayDecimals = fracStr.length < 8 ? fracStr.length : 8;
    return double.parse('$whole.${fracStr.substring(0, displayDecimals)}');
  }

  /// Parse human-readable amount to BigInt
  static BigInt parseAmount(String amount, int decimals) {
    if (amount.isEmpty) return BigInt.zero;
    final parts = amount.split('.');
    final whole = BigInt.parse(parts[0].isEmpty ? '0' : parts[0]);
    final frac = parts.length > 1 ? parts[1].padRight(decimals, '0').substring(0, decimals) : '0'.padRight(decimals, '0');
    return whole * BigInt.from(10).pow(decimals) + BigInt.parse(frac);
  }
}
