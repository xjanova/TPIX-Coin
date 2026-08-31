/// TPIX Wallet — โทเคนของระบบออกแบบ (สเกลระยะ + สเกลความมน)
///
/// ทำไมต้องมี: สำรวจโค้ดจริงแล้วพบว่าค่าความมนถูกใช้อยู่ **17 ค่า**
/// (1,2,3,4,6,8,10,12,14,16,18,20,22,24,28,36,50) และระยะห่างอีก 17 ค่า
/// คนดูบอกไม่ถูกว่าตรงไหนผิด แต่ตารู้ว่า "มั่ว" เพราะการ์ดที่วางข้างกัน
/// มนไม่เท่ากันทีละ 2px และช่องไฟระหว่างบล็อกไม่เป็นจังหวะเดียวกัน
///
/// สเกลนี้ตั้งจากค่าที่ใช้บ่อยที่สุดอยู่แล้ว เพื่อให้เปลี่ยนน้อยที่สุด
/// แต่กำจัดค่านอกแถวทิ้ง — 14→16, 10→12, 18/22/24→20, 28/36→ของธีม
///
/// Developed by Xman Studio

import 'package:flutter/widgets.dart';

import 'theme_bundle.dart';

/// สเกลความมน — 5 ขั้น
///
/// เลือกขั้นตาม "ขนาดของสิ่งที่มน" ไม่ใช่ตามความรู้สึก:
/// ของยิ่งเล็กยิ่งมนน้อย ไม่งั้นมันจะกลายเป็นแคปซูลโดยไม่ตั้งใจ
abstract final class TpixRadius {
  /// ป้ายเล็ก ชิป แถบสถานะ
  static const double xs = 8;

  /// ช่องกรอก ปุ่มเล็ก การ์ดในลิสต์
  static const double sm = 12;

  /// การ์ดย่อย กล่องข้อมูล
  static const double md = 16;

  /// การ์ดหลักของหน้า
  static const double lg = 20;

  /// การ์ดพระเอก — ผูกกับธีม เพราะแต่ละธีมมีบุคลิกความมนต่างกัน
  /// (ลิควิด 28 มนมาก / เทอร์มินัลเกือบเหลี่ยม)
  static double hero(BuildContext context) =>
      TpixThemeExtension.of(context).cardRadius;

  /// มุมบนของแผ่นที่เลื่อนขึ้นมาจากขอบล่าง (bottom sheet)
  /// แยกจาก [hero] เพราะเป็นคนละบทบาท และต้องเป็น const ได้
  /// (BorderRadius.vertical ของแผ่นพวกนี้ถูกประกาศเป็น const)
  static const double sheet = 28;

  /// ทรงแคปซูล — ใช้กับสิ่งที่ต้องมนสุดจริง ๆ เท่านั้น
  static const double pill = 999;
}

/// สเกลระยะห่าง — กริด 4pt
///
/// 4pt เป็นกริดมาตรฐานของทั้ง iOS และ Android ค่านอกกริดจะอ่านเป็น
/// "เผลอพิมพ์" มากกว่า "ตั้งใจ" — ยกเว้น [hair] ที่ใช้กับระยะระหว่าง
/// บรรทัดหัวข้อกับบรรทัดคำอธิบาย ซึ่งต้องชิดกว่ากริดจริง ๆ
abstract final class TpixGap {
  /// ระหว่างหัวข้อกับคำอธิบายใต้หัวข้อเท่านั้น
  static const double hair = 2;

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;
  static const double huge = 40;
}
