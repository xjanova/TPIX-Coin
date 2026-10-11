/// โลโก้ "เหรียญ TPIX" + โลโก้โทเค็นทั่วไป
///
/// ★ แยกจากไอคอนแอป (assets/images/logowallet.png) — ไอคอนแอปใช้กับตัวแอป
///   (หน้า PIN, splash, อวาตาร์กระเป๋า) ส่วนตรงไหนที่หมายถึง "เหรียญ TPIX"
///   (ยอดเงิน, รายการโทเค็น, ประวัติ, กราฟราคา) ใช้โลโก้เหรียญตัวใหม่ตัวนี้
///   ไฟล์เดียวกับ https://tpix.online/images/brand/tpix-coin.png (512px, ~93KB)
library;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../services/token_logo_cache.dart';

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

/// โลโก้โทเค็นจาก URL (แคชลงดิสก์) — ระหว่างโหลด/โหลดไม่ได้/ไม่มี URL
/// → วงกลมตัวอักษรแรกของสัญลักษณ์บนสีแบรนด์ ขนาดเท่ากันทุกสถานะ (ไม่มีกระตุก)
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

  /// ที่มาของรูป — เทสต์เปลี่ยนได้ (ไม่แตะดิสก์/ปลั๊กอิน)
  @visibleForTesting
  static ImageProvider Function(String url) imageProviderFor = _cachedProvider;

  static ImageProvider _cachedProvider(String url) =>
      CachedNetworkImageProvider(url, cacheManager: TokenLogoCache.instance);

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
    // ถอดรหัสตามขนาดที่วาดจริง (size x 3 dpr) ไม่ใช่ขนาดเต็มไฟล์
    final px = (size * 3).round();
    return SizedBox(
      width: size,
      height: size,
      child: ClipOval(
        child: Image(
          image: ResizeImage(imageProviderFor(url), width: px, height: px),
          width: size,
          height: size,
          fit: BoxFit.cover,
          // ยังโหลดไม่เสร็จ → โชว์ตัวอักษรไปก่อน (ขนาดเท่ากัน)
          frameBuilder: (_, child, frame, sync) =>
              sync || frame != null ? child : fallback,
          errorBuilder: (_, _, _) => fallback,
        ),
      ),
    );
  }
}
