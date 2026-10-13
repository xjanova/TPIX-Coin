/// TPIX Wallet — ยืนยันตัวตนก่อนเซ็นธุรกรรม (สแกนนิ้ว/ใบหน้า → ไม่ผ่านค่อยใส่ PIN)
///
/// แยกออกมาจากหน้าโอนเงิน เพื่อให้ทุกหน้าที่ส่งธุรกรรม (โอน, สเตคมาสเตอร์โหนด)
/// ใช้ด่านเดียวกัน — ไม่มีหน้าไหนเผลอส่งโดยไม่ถาม PIN
///
/// ธีม Obsidian (tx_auth_obsidian.dart): ใส่ PIN เต็มจอ แป้นกระจก + ป้ายสรุปธุรกรรม
/// แทนกล่องเล็ก — ด่านเดียวกันทุกอย่าง (สแกนนิ้วก่อน · ตรวจล็อก · นับครั้งผิดใน WalletService)
///
/// Developed by Xman Studio
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/locale_provider.dart';
import '../core/theme.dart';
import '../core/themes/theme_bundle.dart';
import '../core/themes/tokens.dart';
import '../providers/wallet_provider.dart';
import '../services/biometric_service.dart';
import '../services/synth_service.dart';
import '../services/wallet_service.dart';
import 'obsidian/obsidian.dart';
import 'obsidian/obsidian_glyph.dart';
import 'obsidian/obsidian_scrim.dart';
import 'obsidian/obsidian_top_bar.dart';
import 'obsidian/pin_pad.dart';

part 'tx_auth_obsidian.dart';

/// ป้ายสรุปธุรกรรมบนหน้า PIN ธีม Obsidian (เช่น "ส่ง 1,500 TPIX · ถึง บัญชีสำรอง")
/// ธีมอื่นไม่ใช้ — กล่อง PIN เดิมไม่มีที่แสดง
@immutable
class TxAuthSummary {
  final String title;
  final String? subtitle;

  /// โลโก้เหรียญ 30px
  final Widget? leading;

  const TxAuthSummary({required this.title, this.subtitle, this.leading});
}

/// true = ยืนยันผ่าน, false = ยกเลิก/PIN ผิด/ถูกล็อก → ผู้เรียกต้องไม่ส่งอะไรเลย
Future<bool> authorizeTransaction(
  BuildContext context, {
  required String reason,
  TxAuthSummary? summary,
}) async {
  final bio = BiometricService();
  final bioReady = await bio.isEnabled() && await bio.isDeviceSupported();
  if (bioReady) {
    if (await bio.authenticate(reason)) return true;
  }
  // สแกนไม่ผ่าน/ยกเลิก/ไม่ได้เปิดไว้ → ใส่ PIN แทน
  if (!context.mounted) return false;
  if (TpixThemeExtension.of(context).themeId == ThemeId.obsidian) {
    final ok = await Navigator.of(context).push<bool>(ObsidianPinVerifyPage.route(
      reason: reason,
      summary: summary,
      biometric: bioReady,
    ));
    return ok == true;
  }
  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const PinVerifyDialog(),
  );
  return ok == true;
}

/// กล่องใส่ PIN ยืนยันก่อนส่ง
///
/// แยกเป็น StatefulWidget เพื่อให้ controller ถูก dispose ใน dispose() ของตัวเอง
/// ของเดิม dispose ซ้ำ 2 ครั้ง (ปุ่มยกเลิก + .then) และ dispose ตอนกล่องยังเล่น
/// แอนิเมชันปิดอยู่ → "TextEditingController was used after being disposed"
class PinVerifyDialog extends StatefulWidget {
  const PinVerifyDialog({super.key});

  @override
  State<PinVerifyDialog> createState() => _PinVerifyDialogState();
}

class _PinVerifyDialogState extends State<PinVerifyDialog> {
  final _pinController = TextEditingController();
  bool _checking = false; // กันตรวจ PIN ซ้อนเมื่อพิมพ์เร็ว

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _onChanged(String val) async {
    if (val.length != 6 || _checking) return;
    _checking = true;
    final wallet = context.read<WalletProvider>();
    // Verify PIN by trying unlock (already unlocked, so just check hash)
    final isLocked = await WalletService().isPinLocked();
    if (!mounted) return;
    if (isLocked) {
      Navigator.pop(context, false);
      return;
    }
    // Use the provider's existing unlock check
    final success = await wallet.unlock(val);
    if (!mounted) return;
    Navigator.pop(context, success);
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final l = context.watch<LocaleProvider>();
    return AlertDialog(
      backgroundColor: c.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(TpixRadius.lg)),
      title: Text(l.t('pin.unlock'), style: TextStyle(color: c.text, fontSize: 16)),
      content: TextField(
        controller: _pinController,
        obscureText: true,
        keyboardType: TextInputType.number,
        maxLength: 6,
        autofocus: true,
        style: TextStyle(color: c.text, fontSize: 24, letterSpacing: 8),
        textAlign: TextAlign.center,
        decoration: InputDecoration(
          counterText: '',
          hintText: '••••••',
          hintStyle: TextStyle(color: c.textMuted.withValues(alpha: 0.3)),
          enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppTheme.primary.withValues(alpha: 0.3))),
          focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: AppTheme.primary)),
        ),
        onChanged: _onChanged,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l.t('send.cancel'), style: const TextStyle(color: Colors.grey)),
        ),
      ],
    );
  }
}
