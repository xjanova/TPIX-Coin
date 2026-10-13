/// TPIX Wallet — สูตรพื้นผิวเพิ่มเติมของธีม Obsidian (หน้าแลก / บริดจ์ / เพิ่มโทเค็น / dApp)
///
/// ค่าทุกตัวลอกจาก inline style ของ A-Swap.dc.html / A-Bridge.dc.html ตรง ๆ
/// (สูตรพื้นฐาน panel/raised/dark/field/primaryButton อยู่ที่ ObsidianSurface)
///
/// Developed by Xman Studio
library;

import 'package:flutter/material.dart';

import '../../core/themes/obsidian_tokens.dart';
import 'obsidian_panel.dart';

abstract final class ObsidianCards {
  static const _down = Alignment.topCenter;
  static const _up = Alignment.bottomCenter;

  /// การ์ดหลัก — "จ่าย" ของหน้าแลก / การ์ดเส้นทางบริดจ์ (ขาว 8%→2% · ขอบบน .14)
  static const hero = ObsidianSurface(
    radius: 24,
    gradient: LinearGradient(begin: _down, end: _up, colors: [Color(0x14FFFFFF), Color(0x05FFFFFF)]),
    topHighlight: Color(0x24FFFFFF),
    bottomShade: Color(0x80000000),
    shadows: [CssShadow(0, 18, 34, -18, Color(0xF2000000))],
  );

  /// การ์ดรอง — "ได้รับ" ของหน้าแลก (ขาว 5%→1.5% · ขอบบน .10)
  static const quiet = ObsidianSurface(
    radius: 24,
    gradient: LinearGradient(begin: _down, end: _up, colors: [Color(0x0DFFFFFF), Color(0x04FFFFFF)]),
    topHighlight: Color(0x1AFFFFFF),
    bottomShade: Color(0x80000000),
    shadows: [CssShadow(0, 18, 34, -18, Color(0xF2000000))],
  );

  /// แผงรายละเอียดแบบเรียบ (ไม่มีเงานอก)
  static const details = ObsidianSurface(
    radius: 20,
    gradient: LinearGradient(begin: _down, end: _up, colors: [Color(0x0DFFFFFF), Color(0x04FFFFFF)]),
    topHighlight: Color(0x14FFFFFF),
  );

  /// การ์ดฟอร์ม (จำนวนของบริดจ์)
  static const form = ObsidianSurface(
    radius: 22,
    gradient: LinearGradient(begin: _down, end: _up, colors: [Color(0x0FFFFFFF), Color(0x04FFFFFF)]),
    topHighlight: Color(0x1AFFFFFF),
    bottomShade: Color(0x80000000),
  );

  /// การ์ดเน้นสีม่วง (ตัวติดตามรายการล่าสุด)
  static const accent = ObsidianSurface(
    radius: 22,
    gradient: LinearGradient(begin: _down, end: _up, colors: [Color(0x1A8B5CF6), Color(0x04FFFFFF)]),
    topHighlight: Color(0x1AFFFFFF),
    ring: Color(0x408B5CF6),
  );

  /// หลุมของแถบแท็บ — ดำ .35 + เงาจม + วงขอบขาว .06
  static const well = ObsidianSurface(
    radius: 18,
    color: Color(0x59000000),
    innerShadows: [CssShadow(0, 1, 3, 0, Color(0x99000000))],
    ring: Color(0x0FFFFFFF),
  );

  /// แท็บที่เลือก (ปุ่มนูนในหลุม)
  static const segment = ObsidianSurface(
    radius: 14,
    gradient: LinearGradient(begin: _down, end: _up, colors: [Color(0xFF2A2E3B), Color(0xFF191C25)]),
    topHighlight: Color(0x29FFFFFF),
    shadows: [CssShadow(0, 6, 14, -6, Color(0xE6000000))],
  );

  /// ปุ่มเลือกเหรียญแบบแคปซูล (สูง 42)
  static const pill = ObsidianSurface(
    radius: 21,
    gradient: LinearGradient(begin: _down, end: _up, colors: [Color(0xFF262A36), Color(0xFF171A21)]),
    topHighlight: Color(0x24FFFFFF),
    shadows: [CssShadow(0, 8, 18, -8, Color(0xE6000000))],
  );

  /// ปุ่มชิปเล็ก (25% / 50% / สูงสุด)
  static const chip = ObsidianSurface(
    radius: 10,
    gradient: LinearGradient(begin: _down, end: _up, colors: [ObsidianColors.darkTop, ObsidianColors.darkBottom]),
    topHighlight: Color(0x1FFFFFFF),
  );

  /// แผงย้อมสีตามโทน (คำเตือน / สถานะ) — โปร่ง ไม่มีเงา
  static ObsidianSurface tinted(Color tone, {double radius = 18}) => ObsidianSurface(
    radius: radius,
    gradient: LinearGradient(
      begin: _down,
      end: _up,
      colors: [tone.withValues(alpha: 0.13), tone.withValues(alpha: 0.03)],
    ),
    topHighlight: const Color(0x14FFFFFF),
    ring: tone.withValues(alpha: 0.32),
  );
}
