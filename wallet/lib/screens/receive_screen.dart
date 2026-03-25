import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../core/locale_provider.dart';
import '../core/theme.dart';
import '../providers/wallet_provider.dart';
import '../services/synth_service.dart';

class ReceiveScreen extends StatelessWidget {
  const ReceiveScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final wallet = context.watch<WalletProvider>();
    final l = context.watch<LocaleProvider>();
    final address = wallet.address ?? '';

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.3),
            radius: 1.5,
            colors: [Color(0xFF0F172A), AppTheme.bgDark],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                // Header
                Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l.t('receive.title'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white)),
                        Text(l.t('receive.subtitle'), style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                      ],
                    ),
                  ],
                ),

                const Spacer(),

                // QR Code with glow
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(28),
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.primary.withValues(alpha: 0.2),
                        blurRadius: 40,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: QrImageView(
                    data: address,
                    version: QrVersions.auto,
                    size: 220,
                    eyeStyle: const QrEyeStyle(
                      eyeShape: QrEyeShape.square,
                      color: AppTheme.bgDark,
                    ),
                    dataModuleStyle: const QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.square,
                      color: AppTheme.bgDark,
                    ),
                    embeddedImage: const AssetImage('assets/images/logowallet.png'),
                    embeddedImageStyle: const QrEmbeddedImageStyle(size: Size(48, 48)),
                  ),
                ),

                const SizedBox(height: 28),

                const Text('TPIX Chain', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppTheme.primary)),
                const SizedBox(height: 8),

                // Address
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: glassCard(borderRadius: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          address,
                          style: const TextStyle(fontSize: 13, color: Colors.white, fontFamily: 'monospace'),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () {
                          Clipboard.setData(ClipboardData(text: address));
                          SynthService.playTap();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(l.t('receive.copied')),
                              backgroundColor: AppTheme.success,
                              duration: Duration(seconds: 1),
                            ),
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            color: AppTheme.primary.withValues(alpha: 0.15),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.copy, size: 16, color: AppTheme.primary),
                              const SizedBox(width: 4),
                              Text(l.t('receive.copy'), style: const TextStyle(fontSize: 13, color: AppTheme.primary, fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Info
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: AppTheme.warm.withValues(alpha: 0.06),
                    border: Border.all(color: AppTheme.warm.withValues(alpha: 0.15)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline, color: AppTheme.warm, size: 18),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          l.t('receive.warning'),
                          style: const TextStyle(fontSize: 12, color: AppTheme.warm, height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),

                const Spacer(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
