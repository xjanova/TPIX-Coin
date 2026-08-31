/// TPIX Wallet — หน้าสแกน QR (ใช้ร่วมกันทั้งหน้าส่ง / นำเข้า / เชื่อม dApp)
///
/// เรียก [onScanned] พร้อมค่าดิบที่อ่านได้ แล้วผู้เรียกเป็นคนปิดหน้านี้เอง
///
/// 🔴 กับดักที่เคยทำให้ "สแกนแล้วจอดำ ไม่มีอะไรเกิดขึ้น":
/// 1. MobileScanner จะลงทะเบียน WidgetsBindingObserver ให้ก็ต่อเมื่อ
///    "ไม่ได้ส่ง controller เข้าไป" เท่านั้น — เราส่งเอง (เพราะต้องใช้ไฟฉาย)
///    จึงต้องดูแลจังหวะแอพสลับไปมาเอง ไม่งั้นตอนแอนดรอยด์เด้งกล่องขออนุญาต
///    กล้อง แอพจะถูก pause แล้วกล้องไม่กลับมาเปิดอีกเลย = จอดำค้าง
/// 2. errorBuilder ค่าเริ่มต้นของแพ็กเกจคือ "กล่องดำ + ไอคอน error ขาวเล็กๆ"
///    ผู้ใช้ไม่รู้เลยว่าเพราะไม่ได้ให้สิทธิ์กล้อง → ต้องบอกเป็นภาษาคนเอง
///
/// Developed by Xman Studio

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import '../core/locale_provider.dart';
import '../core/themes/theme_bundle.dart';

class QRScannerScreen extends StatefulWidget {
  final ValueChanged<String> onScanned;

  /// คีย์ i18n ของหัวข้อ (ไม่ใส่ = 'send.scanQR')
  final String? titleKey;

  const QRScannerScreen({super.key, required this.onScanned, this.titleKey});

  @override
  State<QRScannerScreen> createState() => _QRScannerScreenState();
}

class _QRScannerScreenState extends State<QRScannerScreen>
    with WidgetsBindingObserver {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    // อ่านเฉพาะ QR — บาร์โค้ดแบบอื่นไม่เกี่ยวกับกระเป๋าเงิน และการตัดออก
    // ทำให้จับ QR ได้ไวขึ้นเพราะไม่ต้องลองถอดรหัสฟอร์แมตอื่นทุกเฟรม
    formats: const [BarcodeFormat.qrCode],
  );

  bool _hasScanned = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // ยังไม่ได้สิทธิ์กล้อง = อย่าเพิ่งสั่งอะไร ปล่อยให้ flow ขออนุญาตทำงานไป
    if (!_controller.value.hasCameraPermission) return;

    switch (state) {
      case AppLifecycleState.resumed:
        // กลับเข้าแอพ → เปิดกล้องใหม่ (จุดที่แก้อาการ "จอดำหลังกดอนุญาต")
        _controller.start().ignore();
      case AppLifecycleState.inactive:
        _controller.stop().ignore();
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        break;
    }
  }

  void _onDetect(BarcodeCapture capture) {
    if (_hasScanned) return;
    final raw = capture.barcodes
        .map((b) => b.rawValue)
        .firstWhere((v) => v != null && v.trim().isNotEmpty, orElse: () => null);
    if (raw == null) return;

    _hasScanned = true;
    widget.onScanned(raw);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<LocaleProvider>();

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          l.t(widget.titleKey ?? 'send.scanQR'),
          style: const TextStyle(color: Colors.white, fontSize: 18),
        ),
        centerTitle: true,
        actions: [
          // ไฟฉาย — QR บนจอมืดหรือในที่แสงน้อยอ่านไม่ออกถ้าไม่มีตัวนี้
          ValueListenableBuilder<MobileScannerState>(
            valueListenable: _controller,
            builder: (_, state, __) {
              if (state.torchState == TorchState.unavailable) {
                return const SizedBox.shrink();
              }
              final on = state.torchState == TorchState.on;
              return IconButton(
                tooltip: l.t('scan.torch'),
                icon: Icon(
                  on ? Icons.flashlight_on_rounded : Icons.flashlight_off_rounded,
                  color: on ? Colors.amber : Colors.white,
                ),
                onPressed: () => _controller.toggleTorch().ignore(),
              );
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) => _buildError(context, error, l),
          ),

          // กรอบเล็งสแกน
          IgnorePointer(
            child: Center(
              child: Container(
                width: 260,
                height: 260,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: TpixThemeExtension.of(context).brandPrimary,
                    width: 2,
                  ),
                ),
              ),
            ),
          ),

          // คำใบ้
          Positioned(
            bottom: 80,
            left: 24,
            right: 24,
            child: IgnorePointer(
              child: Text(
                l.t('send.scanHint'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 14,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// จอเวลากล้องเปิดไม่ได้ — บอกสาเหตุเป็นภาษาคน แทนกล่องดำเปล่าๆ
  Widget _buildError(
    BuildContext context,
    MobileScannerException error,
    LocaleProvider l,
  ) {
    final denied = error.errorCode == MobileScannerErrorCode.permissionDenied;
    final unsupported = error.errorCode == MobileScannerErrorCode.unsupported;

    final (icon, title, hint) = denied
        ? (Icons.no_photography_rounded, l.t('scan.noPermission'), l.t('scan.noPermissionHint'))
        : unsupported
            ? (Icons.videocam_off_rounded, l.t('scan.unsupported'), l.t('scan.unsupportedHint'))
            : (Icons.error_outline_rounded, l.t('scan.cameraError'), l.t('scan.cameraErrorHint'));

    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white.withValues(alpha: 0.85), size: 56),
              const SizedBox(height: 20),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                hint,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
              if (!unsupported) ...[
                const SizedBox(height: 28),
                FilledButton.icon(
                  onPressed: () async {
                    await _controller.stop();
                    await _controller.start();
                  },
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text(l.t('scan.retry')),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
