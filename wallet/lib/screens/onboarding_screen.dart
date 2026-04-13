import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../core/locale_provider.dart';
import '../core/theme.dart';
import '../providers/wallet_provider.dart';
import 'backup_screen.dart';
import 'import_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _createWallet() async {
    final l = context.read<LocaleProvider>();
    // Ask for wallet name first
    final name = await _askWalletName(l);
    if (name == null || !mounted) return;

    final provider = context.read<WalletProvider>();
    try {
      final result = await provider.createWallet(name: name.isEmpty ? null : name);
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => BackupScreen(mnemonic: result['mnemonic']!),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l.t('import.errorGeneral')),
          backgroundColor: AppTheme.danger,
        ),
      );
    }
  }

  Future<String?> _askWalletName(LocaleProvider l) async {
    final c = AppColors.of(context);
    final controller = TextEditingController(text: '');
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(l.t('wallets.nameTitle'), style: TextStyle(color: c.text, fontSize: 18)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l.t('wallets.nameHint'), style: TextStyle(color: c.textMuted, fontSize: 13)),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              maxLength: 24,
              style: TextStyle(color: c.text),
              decoration: InputDecoration(
                hintText: l.t('wallets.namePlaceholder'),
                hintStyle: TextStyle(color: c.textMuted),
                filled: true,
                fillColor: c.surface,
                counterStyle: TextStyle(color: c.textMuted),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: c.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppTheme.primary),
                ),
              ),
              onSubmitted: (_) => Navigator.pop(ctx, controller.text.trim()),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: Text(l.t('wallets.cancel'), style: TextStyle(color: c.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text(l.t('wallets.save'), style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  void _importWallet() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ImportScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Scaffold(
      body: Container(
        decoration: c.screenBg,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              children: [
                const Spacer(flex: 2),

                // Logo with pulse
                SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.3),
                    end: Offset.zero,
                  ).animate(CurvedAnimation(
                    parent: _controller,
                    curve: const Interval(0, 0.6, curve: Curves.easeOutCubic),
                  )),
                  child: FadeTransition(
                    opacity: CurvedAnimation(
                      parent: _controller,
                      curve: const Interval(0, 0.5),
                    ),
                    child: Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.primary.withValues(alpha: 0.25),
                            blurRadius: 50,
                            spreadRadius: 15,
                          ),
                        ],
                      ),
                      child: Image.asset('assets/images/logowallet.png'),
                    ),
                  ),
                ),

                const SizedBox(height: 40),

                // Title
                FadeTransition(
                  opacity: CurvedAnimation(
                    parent: _controller,
                    curve: const Interval(0.3, 0.7),
                  ),
                  child: Builder(
                    builder: (context) {
                      final l = context.watch<LocaleProvider>();
                      return Column(
                        children: [
                          ShaderMask(
                            shaderCallback: (bounds) => AppTheme.brandGradient.createShader(bounds),
                            child: const Text(
                              'TPIX Wallet',
                              style: TextStyle(fontSize: 36, fontWeight: FontWeight.w800, color: Colors.white),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            l.t('onboarding.subtitle'),
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 15, color: c.textSec, height: 1.5),
                          ),
                        ],
                      );
                    },
                  ),
                ),

                const Spacer(flex: 2),

                // Buttons
                FadeTransition(
                  opacity: CurvedAnimation(
                    parent: _controller,
                    curve: const Interval(0.5, 1.0),
                  ),
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.2),
                      end: Offset.zero,
                    ).animate(CurvedAnimation(
                      parent: _controller,
                      curve: const Interval(0.5, 1.0, curve: Curves.easeOut),
                    )),
                    child: Builder(
                      builder: (context) {
                        final l = context.watch<LocaleProvider>();
                        return Column(
                          children: [
                            // Create Wallet Button
                            _buildGradientButton(
                              label: l.t('onboarding.createWallet'),
                              subtitle: l.t('onboarding.createWalletSub'),
                              icon: Icons.add_circle_outline,
                              gradient: AppTheme.brandGradient,
                              onTap: _createWallet,
                            ),

                            const SizedBox(height: 16),

                            // Import Wallet Button
                            _buildOutlineButton(
                              label: l.t('onboarding.importWallet'),
                              subtitle: l.t('onboarding.importWalletSub'),
                              icon: Icons.download_outlined,
                              onTap: _importWallet,
                              c: c,
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),

                const Spacer(),

                Text(
                  'by Xman Studio',
                  style: TextStyle(fontSize: 11, color: c.textMuted),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGradientButton({
    required String label,
    required String subtitle,
    required IconData icon,
    required Gradient gradient,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
          decoration: BoxDecoration(
            gradient: gradient,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primary.withValues(alpha: 0.3),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              Icon(icon, color: Colors.white, size: 28),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white)),
                  Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.7))),
                ],
              ),
              const Spacer(),
              const Icon(Icons.arrow_forward_ios, color: Colors.white54, size: 18),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOutlineButton({
    required String label,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
    required AppColors c,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: c.glassBorder, width: 1.5),
            color: c.glassColor,
          ),
          child: Row(
            children: [
              Icon(icon, color: c.textSec, size: 28),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: c.text)),
                  Text(subtitle, style: TextStyle(fontSize: 12, color: c.textMuted)),
                ],
              ),
              const Spacer(),
              Icon(Icons.arrow_forward_ios, color: c.textMuted, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}
