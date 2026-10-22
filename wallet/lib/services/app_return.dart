/// TPIX Wallet — พาผู้ใช้กลับแอปก่อนหน้า (เบราว์เซอร์ที่เปิดลิงก์ tpixwallet://wc มา)
///
/// Android: MainActivity.moveTaskToBack(true) ผ่าน MethodChannel — task ของกระเป๋าถอยไปข้างหลัง
/// task ของเบราว์เซอร์ที่อยู่ใต้กลับขึ้นมาเอง (แอปไม่ได้ปิด สถานะ/การเชื่อมต่อยังอยู่ครบ)
/// แพลตฟอร์มอื่นไม่ทำอะไร (iOS ไม่มีวิธีที่ถูกกติกา — ผู้ใช้กด "◀ กลับ" มุมบนเอง)
///
/// ห้ามโยน error ขึ้นไปหาคนเรียก — กลับไม่ได้ก็แค่อยู่ในแอปต่อ
///
/// Developed by Xman Studio
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class AppReturn {
  AppReturn._();

  static const _channel = MethodChannel('tpix_wallet/app_return');

  /// ย้ายแอปไปข้างหลัง — true = ระบบรับคำสั่งแล้ว
  static Future<bool> moveToBack() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      return await _channel.invokeMethod<bool>('moveToBack') ?? false;
    } catch (e) {
      // ไม่มีช่องทาง (เทสต์ / เครื่องแปลก ๆ) — อยู่ในแอปต่อ ไม่ใช่เรื่องร้ายแรง
      debugPrint('[AppReturn] moveToBack failed: ${e.runtimeType}');
      return false;
    }
  }
}
