import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../core/theme.dart';
import '../providers/wallet_provider.dart';

class ReceiveScreen extends StatelessWidget {
  const ReceiveScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final wallet = context.watch<WalletProvider>();
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
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('รับ TPIX', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white)),
                        Text('Receive TPIX', style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
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
                      eyeShape: QrEyeShape.roundedOuter,
                      color: AppTheme.bgDark,
                    ),
                    dataModuleStyle: const QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.roundedOutsideCorners,
                      color: AppTheme.bgDark,
                    ),
                    embeddedImage: const AssetImage('assets/images/tpixlogo.webp'),
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
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('คัดลอกที่อยู่แล้ว!'),
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
                              Icon(Icons.copy, size: 16, color: AppTheme.primary),
                              SizedBox(width: 4),
                              Text('คัดลอก', style: TextStyle(fontSize: 13, color: AppTheme.primary, fontWeight: FontWeight.w600)),
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
                          'ส่งเฉพาะ TPIX (Chain ID: 4289) มาที่อยู่นี้เท่านั้น',
                          style: TextStyle(fontSize: 12, color: AppTheme.warm, height: 1.4),
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
