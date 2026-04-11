import 'package:flutter/material.dart';

/// Token definition for pre-loaded known tokens
class TokenDef {
  final String address;
  final String name;
  final String symbol;
  final int decimals;
  final String? logoUrl;

  const TokenDef({
    required this.address,
    required this.name,
    required this.symbol,
    required this.decimals,
    this.logoUrl,
  });

  bool get isNative => address == nativeAddress;
  static const nativeAddress = '0x0000000000000000000000000000000000000000';
}

/// Chain configuration for multi-chain support
class ChainConfig {
  final int chainId;
  final String name;
  final String shortName;
  final String symbol;
  final int decimals;
  final String rpcUrl;
  final List<String> fallbackRpcs;
  final String explorerUrl;
  final String? dexRouterAddress;
  final String? wrappedNativeAddress;
  final String? bridgeAddress;
  final bool isGasless;
  final Color color;
  final String? trustWalletSlug; // for icon CDN
  final List<TokenDef> knownTokens;

  const ChainConfig({
    required this.chainId,
    required this.name,
    required this.shortName,
    required this.symbol,
    this.decimals = 18,
    required this.rpcUrl,
    this.fallbackRpcs = const [],
    required this.explorerUrl,
    this.dexRouterAddress,
    this.wrappedNativeAddress,
    this.bridgeAddress,
    this.isGasless = false,
    required this.color,
    this.trustWalletSlug,
    this.knownTokens = const [],
  });

  /// Native token as a TokenDef
  TokenDef get nativeToken => TokenDef(
        address: TokenDef.nativeAddress,
        name: name,
        symbol: symbol,
        decimals: decimals,
        logoUrl: chainLogoUrl,
      );

  /// All available tokens (native + known)
  List<TokenDef> get allTokens => [nativeToken, ...knownTokens];

  /// Chain logo URL from Trust Wallet CDN
  String? get chainLogoUrl => trustWalletSlug != null
      ? 'https://raw.githubusercontent.com/trustwallet/assets/master/blockchains/$trustWalletSlug/info/logo.png'
      : null;

  /// Token logo URL from Trust Wallet CDN
  String? tokenLogoUrl(String contractAddress) => trustWalletSlug != null
      ? 'https://raw.githubusercontent.com/trustwallet/assets/master/blockchains/$trustWalletSlug/assets/$contractAddress/logo.png'
      : null;

  /// Whether swap is supported on this chain
  bool get hasSwap => dexRouterAddress != null;

  /// Whether bridge is supported
  bool get hasBridge => bridgeAddress != null;

  // ================================================================
  // Static chain registry
  // ================================================================

  static ChainConfig byId(int chainId) =>
      all.firstWhere((c) => c.chainId == chainId, orElse: () => tpix);

  static final List<ChainConfig> all = [tpix, bsc, polygon, ethereum];

  // --- TPIX Chain ---
  static const tpix = ChainConfig(
    chainId: 4289,
    name: 'TPIX Chain',
    shortName: 'TPIX',
    symbol: 'TPIX',
    rpcUrl: 'https://rpc.tpix.online',
    explorerUrl: 'https://explorer.tpix.online',
    isGasless: true,
    color: Color(0xFF00D4FF),
    knownTokens: [],
  );

  // --- BNB Smart Chain ---
  static const bsc = ChainConfig(
    chainId: 56,
    name: 'BNB Smart Chain',
    shortName: 'BSC',
    symbol: 'BNB',
    rpcUrl: 'https://bsc-dataseed1.binance.org',
    fallbackRpcs: [
      'https://bsc-dataseed2.binance.org',
      'https://bsc-dataseed1.defibit.io',
    ],
    explorerUrl: 'https://bscscan.com',
    dexRouterAddress: '0x10ED43C718714eb63d5aA57B78B54704E256024E', // PancakeSwap V2
    wrappedNativeAddress: '0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c', // WBNB
    color: Color(0xFFF0B90B),
    trustWalletSlug: 'smartchain',
    knownTokens: [
      TokenDef(
        address: '0x55d398326f99059fF775485246999027B3197955',
        name: 'Tether USD',
        symbol: 'USDT',
        decimals: 18,
        logoUrl:
            'https://raw.githubusercontent.com/trustwallet/assets/master/blockchains/smartchain/assets/0x55d398326f99059fF775485246999027B3197955/logo.png',
      ),
      TokenDef(
        address: '0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d',
        name: 'USD Coin',
        symbol: 'USDC',
        decimals: 18,
        logoUrl:
            'https://raw.githubusercontent.com/trustwallet/assets/master/blockchains/smartchain/assets/0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d/logo.png',
      ),
    ],
  );

  // --- Polygon ---
  static const polygon = ChainConfig(
    chainId: 137,
    name: 'Polygon',
    shortName: 'POL',
    symbol: 'POL',
    rpcUrl: 'https://polygon-rpc.com',
    fallbackRpcs: [
      'https://rpc-mainnet.matic.quiknode.pro',
    ],
    explorerUrl: 'https://polygonscan.com',
    dexRouterAddress: '0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff', // QuickSwap
    wrappedNativeAddress: '0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270', // WMATIC
    color: Color(0xFF8247E5),
    trustWalletSlug: 'polygon',
    knownTokens: [
      TokenDef(
        address: '0xc2132D05D31c914a87C6611C10748AEb04B58e8F',
        name: 'Tether USD',
        symbol: 'USDT',
        decimals: 6,
        logoUrl:
            'https://raw.githubusercontent.com/trustwallet/assets/master/blockchains/polygon/assets/0xc2132D05D31c914a87C6611C10748AEb04B58e8F/logo.png',
      ),
      TokenDef(
        address: '0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359',
        name: 'USD Coin',
        symbol: 'USDC',
        decimals: 6,
        logoUrl:
            'https://raw.githubusercontent.com/trustwallet/assets/master/blockchains/polygon/assets/0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359/logo.png',
      ),
    ],
  );

  // --- Ethereum ---
  static const ethereum = ChainConfig(
    chainId: 1,
    name: 'Ethereum',
    shortName: 'ETH',
    symbol: 'ETH',
    rpcUrl: 'https://eth.llamarpc.com',
    fallbackRpcs: [
      'https://rpc.ankr.com/eth',
    ],
    explorerUrl: 'https://etherscan.io',
    dexRouterAddress: '0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D', // Uniswap V2
    wrappedNativeAddress: '0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2', // WETH
    color: Color(0xFF627EEA),
    trustWalletSlug: 'ethereum',
    knownTokens: [
      TokenDef(
        address: '0xdAC17F958D2ee523a2206206994597C13D831ec7',
        name: 'Tether USD',
        symbol: 'USDT',
        decimals: 6,
        logoUrl:
            'https://raw.githubusercontent.com/trustwallet/assets/master/blockchains/ethereum/assets/0xdAC17F958D2ee523a2206206994597C13D831ec7/logo.png',
      ),
      TokenDef(
        address: '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48',
        name: 'USD Coin',
        symbol: 'USDC',
        decimals: 6,
        logoUrl:
            'https://raw.githubusercontent.com/trustwallet/assets/master/blockchains/ethereum/assets/0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48/logo.png',
      ),
    ],
  );
}
