/// TPIX Wallet — เชื่อมกระเป๋าเข้า TPIX Trade ในฮอปเดียว
///
/// เจ้าของ: "แอพวอลเลตเราเอง เราสร้างเอง ทำไมไม่ทำให้เข้ากันพอดี"
///
/// เดิม Trade เปิด `tpixwallet://connect` มาแล้วกระเป๋าไม่รู้จัก host นี้ — เปิดขึ้นมา
/// เฉยๆ ผู้ใช้ต้องหาการ์ด "เปิด TPIX Trade" เอง = ดูเหมือนค้าง แล้วพอเชื่อมได้ Trade
/// ก็เด้งกลับมาขอลายเซ็นอีกรอบ (สองแอปสลับกันสี่ครั้งกว่าจะจบ)
///
/// ตอนนี้: รับ connect → ยืนยันหนึ่งครั้ง → ขอข้อความยืนยันจากเซิร์ฟเวอร์ TPIX Trade
/// เซ็นให้เลย → ส่งกลับพร้อม address+nonce+signature → Trade เชื่อมและยืนยันจบทันที
/// (ถ้าเซิร์ฟเวอร์ตอบไม่ได้ ส่งแค่ address เหมือนเดิม Trade จะขอลายเซ็นแยกทีหลัง)
///
/// Developed by Xman Studio
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../core/locale_provider.dart';
import '../core/theme.dart';
import '../core/themes/tokens.dart';
import '../providers/wallet_provider.dart';
import '../utils/peer_app.dart';

class PeerLinkService {
  PeerLinkService._();
  static final PeerLinkService _instance = PeerLinkService._();
  factory PeerLinkService() => _instance;

  /// API ของ TPIX Trade — ที่เดียวกับที่แอป Trade ใช้ (ข้อความยืนยันต้องมาจากที่นี่)
  static const _tradeApi = 'https://tpix.online/api/v1';

  static const _timeout = Duration(seconds: 8);

  /// รับ `tpixwallet://connect?from=<address ฝั่ง Trade ถ้ามี>` จาก TPIX Trade
  ///
  /// ยืนยันกับผู้ใช้ก่อน (แอปอื่นเป็นคนเริ่ม) แล้วส่งกลับพร้อมลายเซ็น
  Future<void> handleConnect(BuildContext context, Uri uri) async {
    final wallet = context.read<WalletProvider>();
    final isThai = context.read<LocaleProvider>().isThai;

    if (!wallet.isUnlocked || wallet.address == null) {
      _snack(
        context,
        isThai
            ? 'ปลดล็อกกระเป๋าก่อน แล้วกด "เปิด TPIX Trade" ที่หน้าแรก'
            : 'Unlock the wallet first, then tap "Open TPIX Trade" on the home screen',
      );
      return;
    }

    final approved = await _confirm(context, address: wallet.address!, isThai: isThai);
    if (!approved || !context.mounted) return;

    final opened = await connectToTrade(context);
    if (!opened && context.mounted) {
      _snack(context, isThai ? 'เปิด TPIX Trade ไม่ได้' : 'Could not open TPIX Trade');
    }
  }

  /// เปิด TPIX Trade พร้อม address (+ ลายเซ็นยืนยันถ้าขอจากเซิร์ฟเวอร์ได้)
  ///
  /// ใช้ทั้งจากการ์ด "เปิด TPIX Trade" (ผู้ใช้กดเอง ไม่ต้องถามซ้ำ) และจาก deep link
  Future<bool> connectToTrade(BuildContext context) async {
    final wallet = context.read<WalletProvider>();
    final address = wallet.address;
    if (address == null) return false;

    final params = <String, String>{
      'address': address,
      'chain': wallet.activeChainId.toString(),
      // Source app name — Trade ใช้แสดง "Linked from TPIX Wallet"
      'wallet': 'TPIX Wallet',
    };

    // เซ็นข้อความยืนยันของ Trade ให้เลย — ล้มเหลวก็ไม่เป็นไร Trade จะขอแยกทีหลัง
    final challenge = await _requestChallenge(address);
    if (challenge != null && wallet.isUnlocked) {
      try {
        final signature = await wallet.signPersonalMessage(challenge.message);
        if (RegExp(r'^0x[a-fA-F0-9]{130}$').hasMatch(signature)) {
          params['nonce'] = challenge.nonce;
          params['signature'] = signature;
        }
      } catch (e) {
        debugPrint('PeerLinkService.sign: ${e.runtimeType}');
      }
    }

    return PeerApp.openTrade(path: 'connect', params: params);
  }

  /// ข้อความยืนยันจากเซิร์ฟเวอร์ TPIX Trade (nonce อายุ 5 นาที ใช้ครั้งเดียว)
  Future<_Challenge?> _requestChallenge(String address) async {
    try {
      final res = await http
          .post(
            Uri.parse('$_tradeApi/wallet/sign'),
            headers: const {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({'wallet_address': address}),
          )
          .timeout(_timeout);

      if (res.statusCode != 200) return null;

      final body = jsonDecode(res.body);
      if (body is! Map || body['success'] != true) return null;

      final data = body['data'];
      if (data is! Map) return null;

      final message = data['message'];
      final nonce = data['nonce'];
      if (message is! String || nonce is! String || message.isEmpty || nonce.isEmpty) {
        return null;
      }

      return _Challenge(message: message, nonce: nonce);
    } catch (e) {
      debugPrint('PeerLinkService.challenge: ${e.runtimeType}');
      return null;
    }
  }

  Future<bool> _confirm(
    BuildContext context, {
    required String address,
    required bool isThai,
  }) async {
    final c = AppColors.of(context);
    final short = '${address.substring(0, 6)}…${address.substring(address.length - 4)}';

    final result = await showModalBottomSheet<bool>(
      context: context,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => Container(
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(TpixRadius.lg)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: c.textSec.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: TpixGap.xl),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(TpixRadius.sm),
                  ),
                  child: const Icon(Icons.link_rounded, color: AppTheme.accent, size: 20),
                ),
                const SizedBox(width: TpixGap.md),
                Expanded(
                  child: Text(
                    isThai ? 'TPIX Trade ขอเชื่อมกระเป๋า' : 'TPIX Trade wants to link your wallet',
                    style: TextStyle(
                      color: c.text,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: TpixGap.md),
            Text(
              isThai
                  ? 'จะส่งที่อยู่ $short ไปให้ TPIX Trade พร้อมลายเซ็นยืนยันตัวตน — Trade ใช้ดูยอด/ตั้งบอทได้ แต่ทุกธุรกรรมยังต้องกลับมากดยืนยันที่กระเป๋านี้เสมอ'
                  : 'Your address $short will be sent to TPIX Trade with an identity signature. Trade can read balances and manage bots, but every transaction still comes back here for your approval.',
              style: TextStyle(color: c.textSec, fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: TpixGap.xl),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(sheetCtx).pop(false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: c.textSec,
                      side: BorderSide(color: c.textSec.withValues(alpha: 0.3)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(TpixRadius.md),
                      ),
                    ),
                    child: Text(isThai ? 'ยกเลิก' : 'Cancel'),
                  ),
                ),
                const SizedBox(width: TpixGap.md),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.of(sheetCtx).pop(true),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.accent,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(TpixRadius.md),
                      ),
                    ),
                    child: Text(isThai ? 'เชื่อมและยืนยัน' : 'Link & verify'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    return result == true;
  }

  void _snack(BuildContext context, String message) {
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 4)),
      );
    } catch (_) {}
  }
}

class _Challenge {
  final String message;
  final String nonce;
  const _Challenge({required this.message, required this.nonce});
}
