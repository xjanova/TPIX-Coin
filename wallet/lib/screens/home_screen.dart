import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import '../core/locale_provider.dart';
import '../core/theme.dart';
import '../providers/wallet_provider.dart';
import '../services/synth_service.dart';
import '../services/wallet_service.dart';
import '../widgets/price_chart.dart';
import '../models/chain_config.dart';
import '../widgets/token_selector.dart';
import 'send_screen.dart';
import 'receive_screen.dart';
import 'tx_history_screen.dart';
import 'wallet_list_sheet.dart';
import 'identity_screen.dart';
import 'settings_screen.dart';
import 'add_token_screen.dart';
import 'swap_screen.dart';
import 'bridge_screen.dart';
import 'dapp_connect_screen.dart';
import '../services/walletconnect_service.dart';
import 'package:app_links/app_links.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  late AnimationController _balanceController;
  late AnimationController _orbController;
  late Animation<double> _balanceScale;
  String _appVersion = '';

  @override
  void initState() {
    super.initState();
    _balanceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..forward();

    _orbController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat();

    _balanceScale = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _balanceController, curve: Curves.elasticOut),
    );

    _loadVersion();
    _initWalletConnect();
    _initDeepLinks();
  }

  /// Initialize WalletConnect service after wallet is ready.
  void _initWalletConnect() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final wp = context.read<WalletProvider>();
      final wc = context.read<WalletConnectService>();

      if (wp.address != null && !wc.initialized) {
        wc.init(wp);
      }

      // Show dApp approval dialog when proposal arrives
      wc.onProposalReceived = (_) {
        if (!mounted) return;
        Navigator.push(context, MaterialPageRoute(
          builder: (_) => const DAppConnectScreen(),
        ));
      };

      // Show signing dialog when request arrives
      wc.onRequestReceived = (_) {
        if (!mounted) return;
        Navigator.push(context, MaterialPageRoute(
          builder: (_) => const DAppConnectScreen(),
        ));
      };
    });
  }

  /// Handle WalletConnect deep links (wc: URI scheme).
  void _initDeepLinks() {
    final appLinks = AppLinks();

    // Handle link that opened the app
    appLinks.getInitialLink().then((uri) {
      if (uri != null) _handleDeepLink(uri);
    });

    // Handle links while app is running
    appLinks.uriLinkStream.listen((uri) {
      _handleDeepLink(uri);
    });
  }

  void _handleDeepLink(Uri uri) {
    final uriStr = uri.toString();
    if (uriStr.startsWith('wc:')) {
      // WalletConnect URI — open dApp connect screen
      if (!mounted) return;
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => DAppConnectScreen(initialUri: uriStr),
      ));
    }
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (!mounted) return;
    setState(() => _appVersion = info.version);
  }

  @override
  void dispose() {
    _balanceController.dispose();
    _orbController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<LocaleProvider>();
    return Scaffold(
      body: Consumer<WalletProvider>(
        builder: (context, wallet, _) => Container(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0, -0.5),
              radius: 1.5,
              colors: [Color(0xFF0C1929), AppTheme.bgDark],
            ),
          ),
          child: SafeArea(
            child: RefreshIndicator(
              onRefresh: wallet.refreshBalance,
              color: AppTheme.primary,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    _buildHeader(wallet, l),
                    const SizedBox(height: 16),
                    // Wallet selector (when multiple wallets)
                    if (wallet.walletCount > 1) ...[
                      _buildWalletSelector(wallet, l),
                      const SizedBox(height: 16),
                    ],
                    _buildBalanceCard(wallet, l),
                    const SizedBox(height: 20),
                    // Price chart
                    PriceChartWidget(
                      currentPrice: wallet.tpixPrice,
                      balanceTPIX: wallet.balance,
                    ),
                    const SizedBox(height: 20),
                    _buildActionButtons(context, l),
                    const SizedBox(height: 24),
                    _buildTokenList(wallet, l),
                    const SizedBox(height: 24),
                    _buildIdentityCard(l),
                    const SizedBox(height: 24),
                    _buildRecentTx(wallet, l),
                    const SizedBox(height: 24),
                    _buildInfoCards(l),
                    const SizedBox(height: 24),
                    _buildQuickLinks(l),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(WalletProvider wallet, LocaleProvider l) {
    return Row(
      children: [
        // Avatar with glow — tap to open wallet list
        GestureDetector(
          onTap: () => WalletListSheet.show(context),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: AppTheme.primary.withValues(alpha: 0.3), blurRadius: 12),
              ],
            ),
            child: ClipOval(
              child: Image.asset('assets/images/logowallet.png', fit: BoxFit.cover),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: () => WalletListSheet.show(context),
              child: Row(
                children: [
                  Text(
                    wallet.activeWallet?.name ?? 'TPIX Wallet',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white),
                  ),
                  if (wallet.walletCount > 1) ...[
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(6),
                        color: AppTheme.accent.withValues(alpha: 0.15),
                      ),
                      child: Text(
                        '${wallet.walletCount}',
                        style: const TextStyle(fontSize: 10, color: AppTheme.accent, fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(Icons.expand_more, size: 18, color: AppTheme.textMuted),
                  ],
                  if (_appVersion.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Text('v$_appVersion', style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                  ],
                ],
              ),
            ),
            GestureDetector(
              onTap: () {
                if (wallet.address != null) {
                  Clipboard.setData(ClipboardData(text: wallet.address!));
                  SynthService.playTap();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(l.t('home.copied')), backgroundColor: AppTheme.success, duration: const Duration(seconds: 1)),
                  );
                }
              },
              child: Row(
                children: [
                  Text(wallet.shortAddress, style: const TextStyle(fontSize: 13, color: AppTheme.primary, fontFamily: 'monospace')),
                  const SizedBox(width: 4),
                  const Icon(Icons.copy, size: 12, color: AppTheme.textMuted),
                ],
              ),
            ),
          ],
        ),
        const Spacer(),
        // Language toggle
        GestureDetector(
          onTap: () => l.toggle(),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: AppTheme.accent.withValues(alpha: 0.1),
              border: Border.all(color: AppTheme.accent.withValues(alpha: 0.3)),
            ),
            child: Text(l.isThai ? 'TH' : 'EN', style: const TextStyle(fontSize: 11, color: AppTheme.accent, fontWeight: FontWeight.w700)),
          ),
        ),
        const SizedBox(width: 8),
        // Settings gear
        GestureDetector(
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.06),
            ),
            child: const Icon(Icons.settings_rounded, color: AppTheme.textSecondary, size: 18),
          ),
        ),
        const SizedBox(width: 8),
        // Network badge — tap to show chain info
        GestureDetector(
          onTap: () => _showChainInfo(wallet),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: wallet.activeChain.color.withValues(alpha: 0.1),
              border: Border.all(color: wallet.activeChain.color.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ChainLogo(chain: wallet.activeChain, size: 14),
                const SizedBox(width: 4),
                Text(
                  wallet.activeChain.shortName,
                  style: TextStyle(fontSize: 11, color: wallet.activeChain.color, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Horizontal wallet selector — shows all wallets as scrollable chips
  Widget _buildWalletSelector(WalletProvider wallet, LocaleProvider l) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              l.t('wallets.title'),
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textMuted),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                color: AppTheme.primary.withValues(alpha: 0.1),
              ),
              child: Text(
                '${wallet.walletCount}',
                style: const TextStyle(fontSize: 11, color: AppTheme.primary, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 42,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: wallet.wallets.length,
            itemBuilder: (_, index) {
              final w = wallet.wallets[index];
              final isActive = w.slot == wallet.activeSlot;
              return Padding(
                padding: EdgeInsets.only(right: index < wallet.wallets.length - 1 ? 8 : 0),
                child: GestureDetector(
                  onTap: isActive
                      ? null
                      : () async {
                          SynthService.playTap();
                          await wallet.switchWallet(w.slot);
                        },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      color: isActive
                          ? AppTheme.primary.withValues(alpha: 0.15)
                          : Colors.white.withValues(alpha: 0.04),
                      border: Border.all(
                        color: isActive
                            ? AppTheme.primary.withValues(alpha: 0.4)
                            : Colors.white.withValues(alpha: 0.08),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: isActive
                                ? const LinearGradient(colors: [AppTheme.primary, AppTheme.accent])
                                : null,
                            color: isActive ? null : AppTheme.bgSurface,
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '${w.slot}',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: isActive ? Colors.white : AppTheme.textMuted,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          w.name,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                            color: isActive ? AppTheme.primary : AppTheme.textSecondary,
                          ),
                        ),
                        if (isActive) ...[
                          const SizedBox(width: 4),
                          const Icon(Icons.check_circle, color: AppTheme.success, size: 14),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildBalanceCard(WalletProvider wallet, LocaleProvider l) {
    return AnimatedBuilder(
      animation: _balanceScale,
      builder: (_, child) => Transform.scale(scale: _balanceScale.value, child: child),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          gradient: const LinearGradient(
            colors: [Color(0xFF0E2A47), Color(0xFF0A1628)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(color: AppTheme.primary.withValues(alpha: 0.15)),
          boxShadow: [
            BoxShadow(color: AppTheme.primary.withValues(alpha: 0.1), blurRadius: 40, spreadRadius: 5),
          ],
        ),
        child: Stack(
          children: [
            // Orbiting decoration
            Positioned(
              right: -10,
              top: -10,
              child: AnimatedBuilder(
                animation: _orbController,
                builder: (_, __) => Transform.rotate(
                  angle: _orbController.value * 2 * pi,
                  child: SizedBox(
                    width: 100,
                    height: 100,
                    child: CustomPaint(painter: _OrbPainter()),
                  ),
                ),
              ),
            ),

            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.t('home.balance'), style: const TextStyle(fontSize: 14, color: AppTheme.textSecondary)),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      wallet.formattedBalance,
                      style: const TextStyle(fontSize: 42, fontWeight: FontWeight.w800, color: Colors.white, height: 1),
                    ),
                    const SizedBox(width: 8),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ClipOval(child: Image.asset('assets/images/logowallet.png', width: 22, height: 22, fit: BoxFit.cover)),
                          const SizedBox(width: 4),
                          const Text('TPIX', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppTheme.primary)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '≈ \$${wallet.portfolioValueUSD.toStringAsFixed(2)} USD',
                  style: TextStyle(fontSize: 14, color: AppTheme.textMuted.withValues(alpha: 0.7)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context, LocaleProvider l) {
    return Column(
      children: [
        // Primary actions row
        Row(
          children: [
            Expanded(child: _buildActionBtn(
              icon: Icons.arrow_upward_rounded,
              label: l.t('home.send'),
              sublabel: l.t('home.sendSub'),
              color: AppTheme.primary,
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SendScreen())),
            )),
            const SizedBox(width: 12),
            Expanded(child: _buildActionBtn(
              icon: Icons.arrow_downward_rounded,
              label: l.t('home.receive'),
              sublabel: l.t('home.receiveSub'),
              color: AppTheme.success,
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ReceiveScreen())),
            )),
            const SizedBox(width: 12),
            Expanded(child: _buildActionBtn(
              icon: Icons.receipt_long_rounded,
              label: l.t('home.history'),
              sublabel: l.t('home.historySub'),
              color: AppTheme.accent,
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TxHistoryScreen())),
            )),
          ],
        ),
        const SizedBox(height: 12),
        // DeFi actions row
        Row(
          children: [
            Expanded(child: _buildActionBtn(
              icon: Icons.swap_horiz_rounded,
              label: l.t('home.swap'),
              sublabel: l.t('home.swapSub'),
              color: AppTheme.warm,
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SwapScreen())),
            )),
            const SizedBox(width: 12),
            Expanded(child: _buildActionBtn(
              icon: Icons.account_tree_rounded,
              label: l.t('home.bridge'),
              sublabel: l.t('home.bridgeSub'),
              color: const Color(0xFF00D4FF),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BridgeScreen())),
            )),
            const SizedBox(width: 12),
            Expanded(child: _buildActionBtn(
              icon: Icons.qr_code_scanner_rounded,
              label: l.t('home.connect'),
              sublabel: l.t('home.connectSub'),
              color: const Color(0xFF8B5CF6),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DAppConnectScreen())),
            )),
          ],
        ),
      ],
    );
  }

  Widget _buildActionBtn({
    required IconData icon,
    required String label,
    required String sublabel,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: color.withValues(alpha: 0.08),
            border: Border.all(color: color.withValues(alpha: 0.15)),
          ),
          child: Column(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withValues(alpha: 0.15),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(height: 10),
              Text(label, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: color)),
              Text(sublabel, style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
            ],
          ),
        ),
      ),
    );
  }

  /// Token balances list with add button
  Widget _buildTokenList(WalletProvider wallet, LocaleProvider l) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: glassCard(borderRadius: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(l.t('token.myTokens'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
              const Spacer(),
              GestureDetector(
                onTap: () async {
                  await Navigator.push(context, MaterialPageRoute(builder: (_) => const AddTokenScreen()));
                  // Refresh tokens when returning
                  if (mounted) wallet.loadTokens();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: AppTheme.primary.withValues(alpha: 0.12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.add, color: AppTheme.primary, size: 16),
                      const SizedBox(width: 4),
                      Text(l.t('token.add'), style: const TextStyle(fontSize: 12, color: AppTheme.primary, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // TPIX native — always first
          _buildTokenRow(
            symbol: 'TPIX',
            name: 'TPIX Chain',
            balance: wallet.formattedBalance,
            isNative: true,
          ),
          // Custom ERC-20 tokens
          ...wallet.tokens.map((token) {
            final bal = wallet.getTokenBalance(token.contractAddress);
            return _buildTokenRow(
              symbol: token.symbol,
              name: token.name,
              balance: bal >= 1000 ? '${(bal / 1000).toStringAsFixed(2)}K' : bal.toStringAsFixed(4),
              onLongPress: () => _confirmRemoveToken(token, wallet, l),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildTokenRow({
    required String symbol,
    required String name,
    required String balance,
    bool isNative = false,
    VoidCallback? onLongPress,
  }) {
    return GestureDetector(
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            // Logo
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isNative ? AppTheme.primary.withValues(alpha: 0.12) : AppTheme.accent.withValues(alpha: 0.12),
              ),
              child: isNative
                  ? ClipOval(child: Image.asset('assets/images/logowallet.png', width: 36, height: 36, fit: BoxFit.cover))
                  : Center(child: Text(symbol.isNotEmpty ? symbol[0] : '?', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.accent))),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(symbol, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white)),
                  Text(name, style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                ],
              ),
            ),
            Text(balance, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white)),
          ],
        ),
      ),
    );
  }

  void _showChainInfo(WalletProvider wallet) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.textMuted.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Multi-Chain Balances',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white),
            ),
            const SizedBox(height: 16),
            ...ChainConfig.all.map((chain) {
              double bal;
              if (chain.chainId == 4289) {
                bal = wallet.balance;
              } else {
                bal = wallet.getChainBalance(chain.chainId);
              }
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    ChainLogo(chain: chain, size: 32),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(chain.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white)),
                          Text('Chain ID: ${chain.chainId}', style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                        ],
                      ),
                    ),
                    Text(
                      '${bal.toStringAsFixed(4)} ${chain.symbol}',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: chain.color),
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _confirmRemoveToken(dynamic token, WalletProvider wallet, LocaleProvider l) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(l.t('token.removeConfirm'), style: const TextStyle(color: AppTheme.danger)),
        content: Text('${token.name} (${token.symbol})', style: const TextStyle(color: AppTheme.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l.t('wallets.cancel'), style: const TextStyle(color: AppTheme.textMuted)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              wallet.removeToken(token.contractAddress);
            },
            child: Text(l.t('wallets.delete'), style: const TextStyle(color: AppTheme.danger, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Widget _buildIdentityCard(LocaleProvider l) {
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const IdentityScreen())),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: [AppTheme.accent.withValues(alpha: 0.1), AppTheme.primary.withValues(alpha: 0.05)],
          ),
          border: Border.all(color: AppTheme.accent.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.accent.withValues(alpha: 0.15),
              ),
              child: const Icon(Icons.shield_rounded, color: AppTheme.accent, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l.t('identity.title'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.accent)),
                  Text(l.t('identity.subtitle'), style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios, color: AppTheme.textMuted, size: 16),
          ],
        ),
      ),
    );
  }

  /// Recent transactions preview (last 3)
  Widget _buildRecentTx(WalletProvider wallet, LocaleProvider l) {
    if (wallet.txHistory.isEmpty) return const SizedBox.shrink();

    final recent = wallet.txHistory.take(3).toList();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: glassCard(borderRadius: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(l.t('home.recentTx'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
              const Spacer(),
              GestureDetector(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TxHistoryScreen())),
                child: Text(l.t('home.viewAll'), style: const TextStyle(fontSize: 12, color: AppTheme.primary)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...recent.map((tx) {
            final isSent = tx.direction == 'sent';
            final color = isSent ? AppTheme.danger : AppTheme.success;
            final icon = isSent ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded;
            final sign = isSent ? '-' : '+';
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  // TPIX logo with direction badge
                  SizedBox(
                    width: 36,
                    height: 36,
                    child: Stack(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: color.withValues(alpha: 0.08),
                          ),
                          child: ClipOval(
                            child: Image.asset('assets/images/logowallet.png', width: 32, height: 32, fit: BoxFit.cover),
                          ),
                        ),
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            width: 16,
                            height: 16,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: color,
                              border: Border.all(color: AppTheme.bgDark, width: 1.5),
                            ),
                            child: Icon(icon, color: Colors.white, size: 10),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      isSent ? tx.shortTo : tx.shortFrom,
                      style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary, fontFamily: 'monospace'),
                    ),
                  ),
                  Text(
                    '$sign${tx.valueInTPIX.toStringAsFixed(2)}',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildInfoCards(LocaleProvider l) {
    return Column(
      children: [
        _buildInfoRow(Icons.speed, l.t('home.blockTime'), l.t('home.blockTimeVal'), AppTheme.success),
        const SizedBox(height: 10),
        _buildInfoRow(Icons.local_gas_station, l.t('home.gasFee'), l.t('home.gasFeeVal'), AppTheme.warm),
        const SizedBox(height: 10),
        _buildInfoRow(Icons.shield, l.t('home.consensus'), 'IBFT 2.0', AppTheme.accent),
        const SizedBox(height: 10),
        // Settings shortcut
        GestureDetector(
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: glassCard(borderRadius: 16),
            child: Row(
              children: [
                const Icon(Icons.settings_rounded, color: AppTheme.primary, size: 22),
                const SizedBox(width: 12),
                Text(l.t('settings.title'), style: const TextStyle(fontSize: 14, color: AppTheme.textSecondary)),
                const Spacer(),
                const Icon(Icons.arrow_forward_ios, color: AppTheme.textMuted, size: 14),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(IconData icon, String title, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: glassCard(borderRadius: 16),
      child: Row(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 12),
          Text(title, style: const TextStyle(fontSize: 14, color: AppTheme.textSecondary)),
          const Spacer(),
          Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }

  Widget _buildQuickLinks(LocaleProvider l) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: glassCard(borderRadius: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.t('home.links'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
          const SizedBox(height: 12),
          _buildLink('🌐', 'TPIX TRADE', 'https://tpix.online'),
          _buildLink('🔍', 'Explorer', TpixChain.explorerUrl),
          _buildLink('📖', 'Whitepaper', 'https://tpix.online/whitepaper'),
          _buildLink('📥', 'Master Node', 'https://tpix.online/masternode'),
        ],
      ),
    );
  }

  Widget _buildLink(String emoji, String label, String url) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 10),
          Text(label, style: const TextStyle(fontSize: 14, color: AppTheme.textSecondary)),
          const Spacer(),
          Icon(Icons.open_in_new, size: 16, color: AppTheme.textMuted.withValues(alpha: 0.5)),
        ],
      ),
    );
  }
}

class _OrbPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppTheme.primary.withValues(alpha: 0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawCircle(Offset(size.width / 2, size.height / 2), size.width / 2, paint);

    final dotPaint = Paint()..color = AppTheme.primary.withValues(alpha: 0.5);
    canvas.drawCircle(Offset(size.width / 2, 0), 3, dotPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
