import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import '../core/locale_provider.dart';
import '../core/theme.dart';

/// Shared QR Scanner screen used by both Send and Import flows.
/// Calls [onScanned] with the raw barcode value and auto-pops.
class QRScannerScreen extends StatefulWidget {
  final ValueChanged<String> onScanned;
  final String? titleKey; // i18n key for the title, defaults to 'send.scanQR'

  const QRScannerScreen({
    super.key,
    required this.onScanned,
    this.titleKey,
  });

  @override
  State<QRScannerScreen> createState() => _QRScannerScreenState();
}

class _QRScannerScreenState extends State<QRScannerScreen> {
  final MobileScannerController _scannerController = MobileScannerController();
  bool _hasScanned = false;

  @override
  void dispose() {
    _scannerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Builder(
          builder: (context) {
            final l = context.watch<LocaleProvider>();
            return Text(
              l.t(widget.titleKey ?? 'send.scanQR'),
              style: const TextStyle(color: Colors.white, fontSize: 18),
            );
          },
        ),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _scannerController,
            onDetect: (capture) {
              if (_hasScanned) return;
              final barcode = capture.barcodes.firstOrNull;
              if (barcode?.rawValue != null) {
                _hasScanned = true;
                widget.onScanned(barcode!.rawValue!);
              }
            },
          ),
          // Scan overlay frame
          Center(
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppTheme.primary, width: 2),
              ),
            ),
          ),
          // Hint text
          Positioned(
            bottom: 80,
            left: 0,
            right: 0,
            child: Builder(
              builder: (context) {
                final l = context.watch<LocaleProvider>();
                return Text(
                  l.t('send.scanHint'),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 14),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
