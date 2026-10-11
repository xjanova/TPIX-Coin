import 'dart:io' show HttpException;

import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// แคชโลโก้โทเค็นลงดิสก์ — แยกจากแคชกลาง จำกัดจำนวน/อายุ/ขนาดไฟล์
///
/// โลโก้มาจากรายการโทเค็นบนเซิร์ฟเวอร์ ไม่ใช่ไฟล์ในแอป → กันไว้ก่อน:
/// https เท่านั้น และไฟล์ที่ประกาศขนาดเกิน [maxBytes] ไม่ดาวน์โหลด
class TokenLogoCache {
  static const key = 'tpixTokenLogos';
  static const maxBytes = 512 * 1024;

  static CacheManager? _instance;

  /// สร้างตอนใช้ครั้งแรก (ไม่แตะดิสก์ตอนเปิดแอป)
  static CacheManager get instance => _instance ??= CacheManager(
        Config(
          key,
          stalePeriod: const Duration(days: 14),
          maxNrOfCacheObjects: 300,
          fileService: _CappedHttpFileService(),
        ),
      );
}

class _CappedHttpFileService extends HttpFileService {
  @override
  Future<FileServiceResponse> get(String url, {Map<String, String>? headers}) async {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https') {
      throw HttpException('token logo must be https', uri: uri);
    }
    final res = await super.get(url, headers: headers);
    final len = res.contentLength;
    if (len != null && len > TokenLogoCache.maxBytes) {
      // ยกเลิกการอ่าน = ปิดการเชื่อมต่อ ไม่โหลดไฟล์ใหญ่ทั้งไฟล์
      await res.content.listen(null).cancel();
      throw HttpExceptionWithStatus(413, 'token logo too large', uri: uri);
    }
    return res;
  }
}
