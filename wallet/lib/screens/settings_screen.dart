import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/locale_provider.dart';
import '../core/theme.dart';
import '../providers/wallet_provider.dart';
import '../services/biometric_service.dart';
import '../services/wallet_service.dart';
import 'backup_screen.dart';
import 'pin_screen.dart';
import 'onboarding_screen.dart';
import 'dapp_connect_screen.dart';
import '../services/walletconnect_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _appVersion = '';
  bool _isBioToggling = false;

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) setState(() => _appVersion = '${info.version} (${info.buildNumber})');
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<LocaleProvider>();
    final c = AppColors.of(context);
    return Scaffold(
      body: Container(
        decoration: c.settingsBg,
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(l),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // --- General ---
                      _sectionTitle(l.t('settings.general')),
                      const SizedBox(height: 8),
                      _buildLanguageTile(l),
                      const SizedBox(height: 8),
                      _buildThemeTile(l),
                      const SizedBox(height: 8),
                      _buildBiometricTile(l),

                      const SizedBox(height: 24),

                      // --- Security ---
                      _sectionTitle(l.t('settings.security')),
                      const SizedBox(height: 8),
                      _buildTile(
                        icon: Icons.vpn_key_rounded,
                        color: AppTheme.accent,
                        title: l.t('settings.backup'),
                        subtitle: l.t('settings.backupDesc'),
                        onTap: () => _viewBackup(l),
                      ),
                      const SizedBox(height: 8),
                      _buildTile(
                        icon: Icons.lock_rounded,
                        color: AppTheme.warm,
                        title: l.t('settings.lock'),
                        subtitle: l.t('settings.lockDesc'),
                        onTap: () {
                          context.read<WalletProvider>().lock();
                          Navigator.pushAndRemoveUntil(
                            context,
                            MaterialPageRoute(builder: (_) => const PinScreen()),
                            (_) => false,
                          );
                        },
                      ),

                      const SizedBox(height: 24),

                      // --- Network ---
                      _sectionTitle(l.t('settings.network')),
                      const SizedBox(height: 8),
                      _buildInfoTile(Icons.link_rounded, 'RPC', TpixChain.rpcUrl, AppTheme.primary),
                      const SizedBox(height: 8),
                      _buildInfoTile(Icons.tag, 'Chain ID', TpixChain.chainId.toString(), AppTheme.accent),
                      const SizedBox(height: 8),
                      _buildInfoTile(Icons.token_rounded, l.t('settings.symbol'), TpixChain.symbol, AppTheme.warm),
                      const SizedBox(height: 8),
                      _buildInfoTile(Icons.speed, l.t('home.consensus'), 'IBFT 2.0', AppTheme.success),

                      const SizedBox(height: 24),

                      // --- WalletConnect ---
                      _sectionTitle(l.t('wc.sectionTitle')),
                      const SizedBox(height: 8),
                      _buildWalletConnectTile(l),

                      const SizedBox(height: 24),

                      // --- Danger Zone ---
                      _sectionTitle(l.t('settings.dangerZone')),
                      const SizedBox(height: 8),
                      _buildTile(
                        icon: Icons.delete_forever_rounded,
                        color: AppTheme.danger,
                        title: l.t('settings.deleteAll'),
                        subtitle: l.t('settings.deleteAllDesc'),
                        onTap: () => _confirmDeleteAll(l),
                      ),

                      const SizedBox(height: 24),

                      // --- About ---
                      Center(
                        child: Column(
                          children: [
                            Image.asset('assets/images/logowallet.png', width: 48, height: 48),
                            const SizedBox(height: 8),
                            Text('TPIX Wallet', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.of(context).text)),
                            if (_appVersion.isNotEmpty)
                              Text('v$_appVersion', style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                            const SizedBox(height: 4),
                            GestureDetector(
                              onTap: () => launchUrl(Uri.parse('https://tpix.online'), mode: LaunchMode.externalApplication),
                              child: const Text('tpix.online', style: TextStyle(fontSize: 12, color: AppTheme.primary)),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(LocaleProvider l) {
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: Icon(Icons.arrow_back_ios, color: c.text),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.t('settings.title'), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: c.text)),
              Text(l.t('settings.subtitle'), style: TextStyle(fontSize: 12, color: c.textMuted)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.of(context).textMuted, letterSpacing: 1)),
    );
  }

  Widget _buildLanguageTile(LocaleProvider l) {
    final c = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: adaptiveGlassCard(context, borderRadius: 16),
      child: Row(
        children: [
          const Icon(Icons.language_rounded, color: AppTheme.primary, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.t('settings.language'), style: TextStyle(fontSize: 14, color: c.text)),
                Text(l.isThai ? 'Thai' : 'English', style: TextStyle(fontSize: 11, color: c.textMuted)),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => l.toggle(),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: AppTheme.primary.withValues(alpha: 0.12),
                border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
              ),
              child: Text(l.isThai ? 'TH' : 'EN', style: const TextStyle(fontSize: 13, color: AppTheme.primary, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThemeTile(LocaleProvider l) {
    final c = AppColors.of(context);
    final isDark = l.isDark;
    return GestureDetector(
      onTap: () => l.toggleTheme(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: adaptiveGlassCard(context, borderRadius: 16),
        child: Row(
          children: [
            Icon(isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                color: isDark ? AppTheme.accent : AppTheme.warm, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l.t('settings.theme'), style: TextStyle(fontSize: 14, color: c.text)),
                  Text(isDark ? l.t('settings.themeDark') : l.t('settings.themeLight'),
                      style: TextStyle(fontSize: 11, color: c.textMuted)),
                ],
              ),
            ),
            Container(
              width: 44,
              height: 24,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: isDark ? AppTheme.accent.withValues(alpha: 0.3) : AppTheme.warm.withValues(alpha: 0.3),
              ),
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 200),
                alignment: isDark ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  width: 20,
                  height: 20,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isDark ? AppTheme.accent : AppTheme.warm,
                  ),
                  child: Icon(isDark ? Icons.dark_mode : Icons.light_mode, size: 12, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBiometricTile(LocaleProvider l) {
    final bioService = BiometricService();
    return FutureBuilder<bool>(
      future: bioService.isDeviceSupported(),
      builder: (context, snapshot) {
        if (snapshot.data != true) return const SizedBox.shrink();
        return FutureBuilder<bool>(
          future: bioService.isEnabled(),
          builder: (context, enabledSnap) {
            final enabled = enabledSnap.data ?? false;
            return GestureDetector(
              onTap: () async {
                if (_isBioToggling) return; // double-tap guard
                setState(() => _isBioToggling = true);

                try {
                  final newVal = !enabled;
                  final wallet = context.read<WalletProvider>();
                  if (newVal) {
                    // Ask for PIN to save biometric token
                    final pin = await _askPinDialog(l);
                    if (pin == null || !mounted) return;

                    final pinValid = await WalletService.verifyPin(pin);
                    if (!pinValid) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(l.t('pin.wrong')), backgroundColor: AppTheme.danger, duration: const Duration(seconds: 2)),
                      );
                      return;
                    }

                    final authed = await bioService.authenticate(l.t('home.biometricSetup'));
                    if (!authed || !mounted) return;

                    await bioService.setEnabled(true);
                    await wallet.saveBiometricToken(pin);
                  } else {
                    await bioService.setEnabled(false);
                    await wallet.clearBiometricToken();
                  }
                } finally {
                  if (mounted) setState(() => _isBioToggling = false);
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: adaptiveGlassCard(context, borderRadius: 16),
                child: Row(
                  children: [
                    Icon(Icons.fingerprint, color: enabled ? AppTheme.primary : AppColors.of(context).textMuted, size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(l.t('settings.biometric'), style: TextStyle(fontSize: 14, color: AppColors.of(context).text)),
                          Text(l.t('settings.biometricDesc'), style: TextStyle(fontSize: 11, color: AppColors.of(context).textMuted)),
                        ],
                      ),
                    ),
                    Container(
                      width: 44,
                      height: 24,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: enabled ? AppTheme.primary.withValues(alpha: 0.3) : Colors.white.withValues(alpha: 0.1),
                      ),
                      child: AnimatedAlign(
                        duration: const Duration(milliseconds: 200),
                        alignment: enabled ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          width: 20,
                          height: 20,
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: enabled ? AppTheme.primary : AppTheme.textMuted,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildTile({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final c = AppColors.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: adaptiveGlassCard(context, borderRadius: 16),
        child: Row(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontSize: 14, color: c.text)),
                  Text(subtitle, style: TextStyle(fontSize: 11, color: c.textMuted)),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios, color: c.textMuted, size: 14),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoTile(IconData icon, String title, String value, Color color) {
    final c = AppColors.of(context);
    return GestureDetector(
      onTap: () {
        Clipboard.setData(ClipboardData(text: value));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${context.read<LocaleProvider>().t('home.copied')}'), backgroundColor: AppTheme.success, duration: const Duration(seconds: 1)),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: adaptiveGlassCard(context, borderRadius: 16),
        child: Row(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 12),
            Text(title, style: TextStyle(fontSize: 14, color: c.textSec)),
            const Spacer(),
            Flexible(
              child: Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color), overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(width: 4),
            Icon(Icons.copy, size: 12, color: c.textMuted),
          ],
        ),
      ),
    );
  }

  Widget _buildWalletConnectTile(LocaleProvider l) {
    final wc = context.watch<WalletConnectService>();
    final sessionCount = wc.sessions.length;

    return _buildTile(
      icon: Icons.qr_code_scanner_rounded,
      color: AppTheme.accent,
      title: l.t('wc.title'),
      subtitle: sessionCount > 0
          ? '$sessionCount ${l.t('wc.activeCount')}'
          : l.t('wc.noSessions'),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const DAppConnectScreen()),
      ),
    );
  }

  /// View backup seed phrase — requires PIN verification first
  Future<void> _viewBackup(LocaleProvider l) async {
    final mnemonic = context.read<WalletProvider>().mnemonic;
    if (mnemonic == null || mnemonic.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.t('settings.noMnemonic')), backgroundColor: AppTheme.warm, duration: const Duration(seconds: 2)),
      );
      return;
    }

    // Require PIN verification before showing seed phrase
    final pin = await _askPinDialog(l);
    if (pin == null || !mounted) return;

    final pinValid = await WalletService.verifyPin(pin);
    if (!pinValid) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.t('pin.wrong')), backgroundColor: AppTheme.danger, duration: const Duration(seconds: 2)),
      );
      return;
    }

    if (!mounted) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => BackupScreen(mnemonic: mnemonic)));
  }

  Future<void> _confirmDeleteAll(LocaleProvider l) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(l.t('settings.deleteConfirm'), style: const TextStyle(color: AppTheme.danger)),
        content: Text(l.t('settings.deleteConfirmMsg'), style: const TextStyle(color: AppTheme.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l.t('wallets.cancel'), style: const TextStyle(color: AppTheme.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l.t('wallets.delete'), style: const TextStyle(color: AppTheme.danger, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    await context.read<WalletProvider>().deleteWallet();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const OnboardingScreen()),
      (_) => false,
    );
  }

  /// PIN dialog for biometric enable (same as home_screen version)
  Future<String?> _askPinDialog(LocaleProvider l) async {
    String pin = '';
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              backgroundColor: AppTheme.bgCard,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Text(l.t('settings.enterPin'), style: const TextStyle(color: Colors.white, fontSize: 18)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(l.t('settings.enterPinHint'), style: const TextStyle(color: AppTheme.textMuted, fontSize: 13)),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(6, (i) {
                      final filled = i < pin.length;
                      return Container(
                        margin: const EdgeInsets.symmetric(horizontal: 6),
                        width: filled ? 16 : 12,
                        height: filled ? 16 : 12,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: filled ? AppTheme.primary : Colors.white.withValues(alpha: 0.1),
                          border: !filled ? Border.all(color: Colors.white.withValues(alpha: 0.15)) : null,
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 20),
                  ...[['1','2','3'], ['4','5','6'], ['7','8','9'], ['','0','DEL']].map((row) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: row.map((key) {
                          if (key.isEmpty) return const SizedBox(width: 56, height: 56);
                          if (key == 'DEL') {
                            return SizedBox(
                              width: 56, height: 56,
                              child: IconButton(
                                onPressed: () {
                                  if (pin.isNotEmpty) setDialogState(() => pin = pin.substring(0, pin.length - 1));
                                },
                                icon: const Icon(Icons.backspace_outlined, color: AppTheme.textSecondary, size: 20),
                              ),
                            );
                          }
                          return SizedBox(
                            width: 56, height: 56,
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(28),
                                onTap: () {
                                  if (pin.length >= 6) return;
                                  setDialogState(() => pin += key);
                                  if (pin.length == 6) Navigator.of(ctx).pop(pin);
                                },
                                child: Container(
                                  decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.04)),
                                  alignment: Alignment.center,
                                  child: Text(key, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: Colors.white)),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    );
                  }),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(null),
                  child: Text(l.t('wallets.cancel'), style: const TextStyle(color: AppTheme.textMuted)),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
