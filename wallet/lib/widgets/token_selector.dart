import 'package:flutter/material.dart';
import '../core/themes/tokens.dart';
import '../core/theme.dart';
import '../models/chain_config.dart';
import '../services/swap_service.dart';
import '../services/token_list_service.dart';
import 'tpix_coin_logo.dart';

/// Bottom sheet for selecting a token from the active chain
class TokenSelectorSheet extends StatefulWidget {
  final ChainConfig chain;
  final String? walletAddress;
  final String? excludeAddress; // already-selected token to dim
  final bool showNative;

  const TokenSelectorSheet({
    super.key,
    required this.chain,
    this.walletAddress,
    this.excludeAddress,
    this.showNative = true,
  });

  /// Show the selector and return the chosen TokenDef (or null)
  static Future<TokenDef?> show(
    BuildContext context, {
    required ChainConfig chain,
    String? walletAddress,
    String? excludeAddress,
    bool showNative = true,
  }) {
    return showModalBottomSheet<TokenDef>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => TokenSelectorSheet(
        chain: chain,
        walletAddress: walletAddress,
        excludeAddress: excludeAddress,
        showNative: showNative,
      ),
    );
  }

  @override
  State<TokenSelectorSheet> createState() => _TokenSelectorSheetState();
}

class _TokenSelectorSheetState extends State<TokenSelectorSheet> {
  final _searchController = TextEditingController();
  String _query = '';
  final Map<String, BigInt> _balances = {};
  bool _loadingBalances = false;

  @override
  void initState() {
    super.initState();
    _loadBalances();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadBalances() async {
    if (widget.walletAddress == null) return;
    setState(() => _loadingBalances = true);

    try {
      // Load native balance
      final nativeBal = await SwapService.getNativeBalance(
        widget.chain,
        widget.walletAddress!,
      );
      if (!mounted) return;
      _balances[TokenDef.nativeAddress] = nativeBal;

      // Load token balances
      for (final token in widget.chain.knownTokens) {
        final bal = await SwapService.getTokenBalance(
          widget.chain,
          token.address,
          widget.walletAddress!,
        );
        if (!mounted) return;
        _balances[token.address.toLowerCase()] = bal;
      }
    } catch (_) {}

    if (mounted) setState(() => _loadingBalances = false);
  }

  List<TokenDef> get _filteredTokens {
    final all = widget.chain.allTokens;
    if (_query.isEmpty) return all;
    final q = _query.toLowerCase();
    return all.where((t) {
      return t.symbol.toLowerCase().contains(q) ||
          t.name.toLowerCase().contains(q) ||
          t.address.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = _filteredTokens;

    return Container(
      height: MediaQuery.of(context).size.height * 0.65,
      decoration: const BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.vertical(top: Radius.circular(TpixRadius.lg)),
      ),
      child: Column(
        children: [
          // Handle bar
          const SizedBox(height: TpixGap.md),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppTheme.textMuted.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: TpixGap.lg),

          // Title + chain badge
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                const Text(
                  'Select Token',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: TpixGap.sm),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(TpixRadius.xs),
                    color: widget.chain.color.withValues(alpha: 0.15),
                  ),
                  child: Text(
                    widget.chain.shortName,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: widget.chain.color,
                    ),
                  ),
                ),
                const Spacer(),
                if (_loadingBalances)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppTheme.primary,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: TpixGap.md),

          // Search bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(TpixRadius.md),
                color: AppTheme.bgSurface,
                border: Border.all(color: AppTheme.borderDim),
              ),
              child: TextField(
                controller: _searchController,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Search by name or address...',
                  hintStyle: TextStyle(
                    color: AppTheme.textMuted.withValues(alpha: 0.5),
                    fontSize: 14,
                  ),
                  prefixIcon: const Icon(Icons.search, color: AppTheme.textMuted, size: 20),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
          ),
          const SizedBox(height: TpixGap.md),

          // Token list
          Expanded(
            child: tokens.isEmpty
                ? Center(
                    child: Text(
                      'No tokens found',
                      style: TextStyle(
                        color: AppTheme.textMuted.withValues(alpha: 0.5),
                        fontSize: 14,
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: tokens.length,
                    itemBuilder: (_, i) => _buildTokenTile(tokens[i]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildTokenTile(TokenDef token) {
    final isExcluded = widget.excludeAddress != null &&
        token.address.toLowerCase() == widget.excludeAddress!.toLowerCase();
    final balance = _balances[token.address.toLowerCase()];
    final formattedBal = balance != null
        ? SwapService.formatAmount(balance, token.decimals)
        : null;

    return Opacity(
      opacity: isExcluded ? 0.35 : 1.0,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isExcluded ? null : () => Navigator.pop(context, token),
          borderRadius: BorderRadius.circular(TpixRadius.md),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
            child: Row(
              children: [
                // Token logo
                _TokenLogo(token: token, chain: widget.chain, size: 40),
                const SizedBox(width: TpixGap.md),

                // Name & symbol
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        token.symbol,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        token.name,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.textMuted,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),

                // Balance
                if (formattedBal != null)
                  Text(
                    formattedBal >= 1000
                        ? '${(formattedBal / 1000).toStringAsFixed(2)}K'
                        : formattedBal.toStringAsFixed(4),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Reusable token logo widget with real images from Trust Wallet CDN
class TokenLogo extends StatelessWidget {
  final TokenDef token;
  final ChainConfig chain;
  final double size;

  const TokenLogo({
    super.key,
    required this.token,
    required this.chain,
    this.size = 36,
  });

  @override
  Widget build(BuildContext context) {
    return _TokenLogo(token: token, chain: chain, size: size);
  }
}

class _TokenLogo extends StatelessWidget {
  final TokenDef token;
  final ChainConfig chain;
  final double size;

  const _TokenLogo({
    required this.token,
    required this.chain,
    this.size = 36,
  });

  @override
  Widget build(BuildContext context) {
    // เหรียญ TPIX ใช้โลโก้เหรียญในตัวแอป (ไม่ใช่ไอคอนแอป)
    if (token.isNative && chain.chainId == 4289) {
      return TpixCoinLogo(size: size);
    }

    // Determine logo URL
    String? logoUrl = token.logoUrl;
    if (logoUrl == null && token.isNative) {
      logoUrl = chain.chainLogoUrl;
    }
    // TPIX Chain: โลโก้จากรายการโทเค็นที่ยืนยันแล้ว (ไม่มีใน Trust Wallet CDN)
    if (logoUrl == null && !token.isNative && chain.chainId == TokenListService.chainId) {
      logoUrl = TokenListService.current?.byAddress(token.address)?.logoUri;
    }
    if (logoUrl == null && !token.isNative) {
      logoUrl = chain.tokenLogoUrl(token.address);
    }

    // แคชลงดิสก์ + ตัวอักษรแรกระหว่างโหลด/โหลดไม่ได้ (ตัวเดียวกับหน้าโฮม)
    return TokenAvatar(
      symbol: token.symbol,
      logoUrl: logoUrl,
      size: size,
      color: chain.color,
    );
  }
}

/// Chain logo widget
class ChainLogo extends StatelessWidget {
  final ChainConfig chain;
  final double size;

  const ChainLogo({
    super.key,
    required this.chain,
    this.size = 24,
  });

  @override
  Widget build(BuildContext context) {
    // TPIX Chain ใช้โลโก้เหรียญ TPIX
    if (chain.chainId == 4289) {
      return TpixCoinLogo(size: size);
    }

    final logoUrl = chain.chainLogoUrl;
    if (logoUrl != null) {
      return ClipOval(
        child: Image.network(
          logoUrl,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _fallback(),
        ),
      );
    }

    return _fallback();
  }

  Widget _fallback() {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: chain.color.withValues(alpha: 0.2),
      ),
      alignment: Alignment.center,
      child: Text(
        chain.shortName[0],
        style: TextStyle(
          fontSize: size * 0.45,
          fontWeight: FontWeight.w700,
          color: chain.color,
        ),
      ),
    );
  }
}
