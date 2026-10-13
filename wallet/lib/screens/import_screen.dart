import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../core/themes/tokens.dart';
import 'package:provider/provider.dart';
import '../core/locale_provider.dart';
import '../core/theme.dart';
import '../core/themes/theme_bundle.dart';
import '../core/themes/widgets/screen_background.dart';
import '../widgets/obsidian/obsidian.dart';
import '../widgets/obsidian/obsidian_screen_header.dart';
import '../providers/wallet_provider.dart';
import '../widgets/qr_scanner_screen.dart';
import 'pin_screen.dart';

class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key});

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  final _controller = TextEditingController();
  final _nameController = TextEditingController();
  bool _isMnemonic = true;

  @override
  void dispose() {
    _controller.dispose();
    _nameController.dispose();
    super.dispose();
  }

  void _scanQR() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => QRScannerScreen(
          titleKey: 'import.scanQR',
          onScanned: (value) {
            _controller.text = value;
            Navigator.pop(context);
          },
        ),
      ),
    );
  }

  void _import() async {
    final input = _controller.text.trim();
    if (input.isEmpty) return;

    final walletName = _nameController.text.trim();
    final l = context.read<LocaleProvider>();
    final provider = context.read<WalletProvider>();
    try {
      if (_isMnemonic) {
        await provider.importFromMnemonic(input, name: walletName.isEmpty ? null : walletName);
      } else {
        await provider.importFromPrivateKey(input, name: walletName.isEmpty ? null : walletName);
      }
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const PinScreen(isSetup: true)),
      );
    } catch (e) {
      if (!mounted) return;
      // Show user-friendly error message
      final msg = e.toString();
      String errorMsg;
      if (msg.contains('Invalid mnemonic')) {
        errorMsg = l.t('import.errorInvalidMnemonic');
      } else if (msg.contains('already exists')) {
        errorMsg = l.t('import.errorDuplicate');
      } else if (_isMnemonic) {
        errorMsg = l.t('import.errorInvalidMnemonic');
      } else {
        errorMsg = l.t('import.errorInvalidKey');
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMsg), backgroundColor: AppTheme.danger),
      );
    }
  }


  /// ช่องกรอกแบบยุบลงของ Obsidian
  InputDecoration _obsField(String hint, {IconData? prefix}) {
    final st = ObsidianStyle.of(context);
    OutlineInputBorder b(Color c, [double w = 1]) =>
        OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide(color: c, width: w));
    return InputDecoration(
      hintText: hint,
      hintStyle: st.ui(fontSize: 14, color: ObsidianColors.textMuted),
      prefixIcon: prefix == null ? null : Icon(prefix, color: ObsidianColors.textMuted, size: 20),
      counterStyle: st.ui(fontSize: 10.5, color: ObsidianColors.textMuted),
      filled: true,
      fillColor: const Color(0xFF0B0C11),
      border: b(const Color(0x14FFFFFF)),
      enabledBorder: b(const Color(0x14FFFFFF)),
      focusedBorder: b(ObsidianColors.cyan, 1.5),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }

  /// ธีม Obsidian — ช่อง/ปุ่ม/การนำเข้า เหมือนเดิมทุกอย่าง เปลี่ยนแค่หน้าตา
  Widget _buildObsidian(LocaleProvider l) {
    final st = ObsidianStyle.of(context);
    final top = MediaQuery.paddingOf(context).top;
    Widget tab(String label, bool active, VoidCallback onTap) => ObsidianPressable(
          onTap: active ? null : onTap,
          semanticLabel: label,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: active
                  ? const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [ObsidianColors.darkTop, ObsidianColors.darkBottom],
                    )
                  : null,
              boxShadow: active ? const [BoxShadow(color: Color(0xB3000000), offset: Offset(0, 4), blurRadius: 8)] : null,
            ),
            child: Text(
              label,
              style: st.ui(
                fontSize: 14,
                fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                color: active ? ObsidianColors.text : ObsidianColors.textMuted,
              ),
            ),
          ),
        );
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: EdgeInsets.fromLTRB(24, math.max(52.0, top + 8), 24, math.max(24.0, MediaQuery.paddingOf(context).bottom + 12)),
            sliver: SliverFillRemaining(
              hasScrollBody: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ObsidianScreenHeader(
                    title: l.t('import.title'),
                    backSemantics: MaterialLocalizations.of(context).backButtonTooltip,
                  ),
                  const SizedBox(height: 24),
                  ObsidianPanel(
                    surface: ObsidianSurface.field,
                    padding: const EdgeInsets.all(4),
                    child: Row(
                      children: [
                        Expanded(child: tab(l.t('import.tabSeed'), _isMnemonic, () => setState(() => _isMnemonic = true))),
                        Expanded(child: tab(l.t('import.tabKey'), !_isMnemonic, () => setState(() => _isMnemonic = false))),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  TextField(
                    controller: _nameController,
                    maxLength: 24,
                    style: st.ui(fontSize: 15, color: ObsidianColors.text),
                    decoration: _obsField(l.t('wallets.namePlaceholder'), prefix: Icons.label_outline_rounded),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _controller,
                    maxLines: 4,
                    autocorrect: false,
                    enableSuggestions: false,
                    style: st.mono(fontSize: 14, color: ObsidianColors.text, height: 1.5),
                    decoration: _obsField(_isMnemonic ? l.t('import.hintMnemonic') : l.t('import.hintKey')),
                  ),
                  const SizedBox(height: 14),
                  ObsidianButton.secondary(
                    label: l.t('import.scanQR'),
                    trailingIcon: Icons.qr_code_scanner_rounded,
                    onPressed: _scanQR,
                  ),
                  const Spacer(),
                  const SizedBox(height: 20),
                  Consumer<WalletProvider>(
                    builder: (_, provider, _) => ObsidianButton(
                      label: l.t('import.button'),
                      loading: provider.isLoading,
                      onPressed: provider.isLoading ? null : _import,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<LocaleProvider>();
    if (TpixThemeExtension.of(context).themeId == ThemeId.obsidian) return _buildObsidian(l);
    final c = AppColors.of(context);
    return Scaffold(
      body: TpixScreenBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(Icons.arrow_back_ios, color: c.text),
                    ),
                    const SizedBox(width: TpixGap.sm),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l.t('import.title'), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: c.text)),
                        Text(l.t('import.subtitle'), style: TextStyle(fontSize: 12, color: c.textMuted)),
                      ],
                    ),
                  ],
                ),

                const SizedBox(height: TpixGap.xxxl),

                // Toggle
                Container(
                  decoration: adaptiveGlassCard(context, borderRadius: 14),
                  padding: const EdgeInsets.all(4),
                  child: Row(
                    children: [
                      Expanded(child: _buildTab(l.t('import.tabSeed'), _isMnemonic, () => setState(() => _isMnemonic = true))),
                      Expanded(child: _buildTab(l.t('import.tabKey'), !_isMnemonic, () => setState(() => _isMnemonic = false))),
                    ],
                  ),
                ),

                const SizedBox(height: TpixGap.xxl),

                // Wallet name
                TextField(
                  controller: _nameController,
                  maxLength: 24,
                  style: TextStyle(color: c.text, fontSize: 15),
                  decoration: InputDecoration(
                    hintText: l.t('wallets.namePlaceholder'),
                    hintStyle: TextStyle(color: c.textMuted),
                    counterStyle: TextStyle(color: c.textMuted, fontSize: 10),
                    prefixIcon: Icon(Icons.label_outline, color: c.textMuted, size: 20),
                    filled: true,
                    fillColor: c.glassColor,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(TpixRadius.md),
                      borderSide: BorderSide(color: c.glassBorder),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(TpixRadius.md),
                      borderSide: BorderSide(color: c.glassBorder),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(TpixRadius.md),
                      borderSide: const BorderSide(color: AppTheme.primary),
                    ),
                  ),
                ),

                const SizedBox(height: TpixGap.md),

                // Key / Seed input
                TextField(
                  controller: _controller,
                  maxLines: 4,
                  style: TextStyle(color: c.text, fontSize: 15),
                  decoration: InputDecoration(
                    hintText: _isMnemonic ? l.t('import.hintMnemonic') : l.t('import.hintKey'),
                    hintStyle: TextStyle(color: c.textMuted),
                    filled: true,
                    fillColor: c.glassColor,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(TpixRadius.md),
                      borderSide: BorderSide(color: c.glassBorder),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(TpixRadius.md),
                      borderSide: BorderSide(color: c.glassBorder),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(TpixRadius.md),
                      borderSide: const BorderSide(color: AppTheme.primary),
                    ),
                  ),
                ),

                const SizedBox(height: TpixGap.lg),

                // Scan QR button
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _scanQR,
                    icon: const Icon(Icons.qr_code_scanner, color: AppTheme.primary),
                    label: Text(l.t('import.scanQR'), style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w600)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: BorderSide(color: AppTheme.primary.withValues(alpha: 0.3)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(TpixRadius.md)),
                    ),
                  ),
                ),

                const Spacer(),

                SizedBox(
                  width: double.infinity,
                  child: Consumer<WalletProvider>(
                    builder: (_, provider, __) => ElevatedButton(
                      onPressed: provider.isLoading ? null : _import,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(TpixRadius.md)),
                      ),
                      child: provider.isLoading
                          ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : Text(l.t('import.button'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTab(String label, bool active, VoidCallback onTap) {
    final c = AppColors.of(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(TpixRadius.sm),
          color: active ? AppTheme.primary.withValues(alpha: 0.2) : Colors.transparent,
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: active ? FontWeight.w600 : FontWeight.w400,
            color: active ? AppTheme.primary : c.textMuted,
          ),
        ),
      ),
    );
  }
}
