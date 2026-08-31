/// TPIX Wallet — หน้ารับเงิน (โชว์ QR ที่อยู่ของเรา)
///
/// 🔴 กับดักที่เคยทำให้ "เปิดหน้ารับเงินแล้วว่างเปล่า":
/// 1. โลโก้กลาง QR เป็น PNG 2048×2048 (~8.8MB) แต่วางจริงแค่ 48px
///    qr_flutter จะคืน Container() เปล่าๆ ระหว่างรอรูปโหลด และ "คืนเปล่าเงียบๆ
///    อีกครั้งถ้าโหลดพลาด" → ผู้ใช้เห็นกล่องขาวไม่มี QR
///    แก้ด้วย ResizeImage (ถอดรหัสแค่ขนาดที่ใช้จริง) + เปิด errorStateBuilder
/// 2. สีตัวอักษรฮาร์ดโค้ด Colors.white ทั้งหน้า → พอสลับไปธีมสว่าง
///    (ลิควิด light / คลาสสิก light) กลายเป็นขาวบนขาว = มองไม่เห็นทั้งหน้า
///    ตอนนี้อ่านสีจาก AppColors.of(context) ทุกจุด
///
/// Developed by Xman Studio

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

  /// ขนาด QR บนจอ
  static const double _qrSize = 220;

  /// โลโก้กลาง QR — ถอดรหัสที่ 144px (48 logical × 3 dpr) พอสำหรับจอ 3x
  /// ไม่ใช่ 2048px ของไฟล์ต้นฉบับ ซึ่งกิน RAM ~16MB และหน่วงจนจอว่าง
  static const ImageProvider _centerLogo = ResizeImage(
    AssetImage('assets/images/logowallet.png'),
    width: 144,
    height: 144,
  );

  @override
  Widget build(BuildContext context) {
    final wallet = context.watch<WalletProvider>();
    final l = context.watch<LocaleProvider>();
    final c = AppColors.of(context);
    final address = wallet.address ?? '';

    return Scaffold(
      body: Container(
        decoration: c.screenBg,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                // ── หัวข้อ ──
                Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(Icons.arrow_back_ios, color: c.text),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(l.t('receive.title'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                  color: c.text)),
                          Text(l.t('receive.subtitle'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 12, color: c.textMuted)),
                        ],
                      ),
                    ),
                  ],
                ),

                const Spacer(),

                if (address.isEmpty)
                  _buildNoWallet(context, l, c)
                else ...[
                  _buildQr(address, c),
                  const SizedBox(height: 28),
                  Text('TPIX Chain',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: c.brandPrimary)),
                  const SizedBox(height: 8),
                  _buildAddressBar(context, address, l, c),
                  const SizedBox(height: 16),
                  _buildWarning(l, c),
                ],

                const Spacer(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── QR + โลโก้กลาง ──
  Widget _buildQr(String address, AppColors c) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        // พื้น QR ต้องขาวเสมอทุกธีม — กล้องอ่านคอนทราสต์สลับสีไม่ได้
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: c.brandPrimary.withValues(alpha: 0.2),
            blurRadius: 40,
            spreadRadius: 5,
          ),
        ],
      ),
      child: QrImageView(
        data: address,
        version: QrVersions.auto,
        size: _qrSize,
        // ที่อยู่ 42 ตัวอักษร + โลโก้บังตรงกลาง → ต้องยกระดับการกู้คืนเป็น H (30%)
        // ไม่งั้นโลโก้กินโมดูลจนบางเครื่องอ่านไม่ออก (ค่าเดิมคือ L = 7%)
        errorCorrectionLevel: QrErrorCorrectLevel.H,
        eyeStyle: const QrEyeStyle(
          eyeShape: QrEyeShape.square,
          color: AppTheme.bgDark,
        ),
        dataModuleStyle: const QrDataModuleStyle(
          dataModuleShape: QrDataModuleShape.square,
          color: AppTheme.bgDark,
        ),
        embeddedImage: _centerLogo,
        embeddedImageStyle: const QrEmbeddedImageStyle(size: Size(48, 48)),
        // โหลดโลโก้ไม่สำเร็จต้องยังได้ QR ที่สแกนได้ ไม่ใช่กล่องเปล่า
        embeddedImageEmitsError: true,
        errorStateBuilder: (_, __) => QrImageView(
          data: address,
          version: QrVersions.auto,
          size: _qrSize,
          errorCorrectionLevel: QrErrorCorrectLevel.H,
          eyeStyle: const QrEyeStyle(
            eyeShape: QrEyeShape.square,
            color: AppTheme.bgDark,
          ),
          dataModuleStyle: const QrDataModuleStyle(
            dataModuleShape: QrDataModuleShape.square,
            color: AppTheme.bgDark,
          ),
        ),
      ),
    );
  }

  // ── แถบที่อยู่ + ปุ่มคัดลอก ──
  Widget _buildAddressBar(
      BuildContext context, String address, LocaleProvider l, AppColors c) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: c.glassColor,
        border: Border.all(color: c.glassBorder),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              address,
              style: TextStyle(
                  fontSize: 13, color: c.text, fontFamily: 'monospace'),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              Clipboard.setData(ClipboardData(text: address));
              SynthService.playTap();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(l.t('receive.copied')),
                  backgroundColor: AppTheme.success,
                  duration: const Duration(seconds: 1),
                ),
              );
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: c.brandPrimary.withValues(alpha: 0.15),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.copy, size: 16, color: c.brandPrimary),
                  const SizedBox(width: 4),
                  Text(l.t('receive.copy'),
                      style: TextStyle(
                          fontSize: 13,
                          color: c.brandPrimary,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWarning(LocaleProvider l, AppColors c) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: c.brandWarm.withValues(alpha: 0.06),
        border: Border.all(color: c.brandWarm.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: c.brandWarm, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              l.t('receive.warning'),
              style:
                  TextStyle(fontSize: 12, color: c.brandWarm, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  /// ยังไม่มีกระเป๋า/ยังล็อกอยู่ — เดิมจะโชว์ QR ของสตริงว่าง ซึ่งสแกนไปก็ไม่ได้อะไร
  Widget _buildNoWallet(BuildContext context, LocaleProvider l, AppColors c) {
    return Column(
      children: [
        Icon(Icons.account_balance_wallet_outlined,
            size: 56, color: c.textMuted),
        const SizedBox(height: 16),
        Text(
          l.t('receive.noWallet'),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: c.text),
        ),
        const SizedBox(height: 8),
        Text(
          l.t('receive.noWalletHint'),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: c.textMuted, height: 1.5),
        ),
      ],
    );
  }
}
