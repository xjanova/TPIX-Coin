/// โลโก้ "เหรียญ TPIX" + โลโก้โทเค็นทั่วไป
///
/// ★ แยกจากไอคอนแอป (assets/images/logowallet.png) — ไอคอนแอปใช้กับตัวแอป
///   (หน้า PIN, splash, อวาตาร์กระเป๋า) ส่วนตรงไหนที่หมายถึง "เหรียญ TPIX"
///   (ยอดเงิน, รายการโทเค็น, ประวัติ, กราฟราคา) ใช้โลโก้เหรียญตัวใหม่ตัวนี้
///   ไฟล์เดียวกับ https://tpix.online/images/brand/tpix-coin.png (512px, ~93KB)
library;

import 'package:flutter/material.dart';

class TpixCoinLogo extends StatelessWidget {
  static const asset = 'assets/images/tpix_coin.png';

  final double size;

  const TpixCoinLogo({super.key, required this.size});

  @override
  Widget build(BuildContext context) {
    // ถอดรหัสตามขนาดที่วาดจริง (size x 3 dpr) ไม่ใช่ 512px เต็มไฟล์
    final px = (size * 3).round();
    return ClipOval(
      child: Image.asset(
        asset,
        width: size,
        height: size,
        fit: BoxFit.cover,
        cacheWidth: px,
        cacheHeight: px,
      ),
    );
  }
}

/// โลโก้โทเค็นจาก URL — โหลดไม่ได้/ไม่มี URL → วงกลมตัวอักษรแรกของสัญลักษณ์
class TokenAvatar extends StatelessWidget {
  final String symbol;
  final String? logoUrl;
  final double size;
  final Color color;

  const TokenAvatar({
    super.key,
    required this.symbol,
    required this.size,
    required this.color,
    this.logoUrl,
  });

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.12),
      ),
      alignment: Alignment.center,
      child: Text(
        symbol.isNotEmpty ? symbol.characters.first.toUpperCase() : '?',
        style: TextStyle(
          fontSize: size * 0.44,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
    final url = logoUrl;
    if (url == null || !url.startsWith('https://')) return fallback;
    final px = (size * 3).round();
    return ClipOval(
      child: Image.network(
        url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        cacheWidth: px,
        cacheHeight: px,
        errorBuilder: (_, _, _) => fallback,
      ),
    );
  }
}
