/// TPIX Wallet — สถานะสะพานจากเซิร์ฟเวอร์ → ขั้นตอน 3 ขั้นบนจอ (ฟังก์ชันล้วน มีเทสต์)
///
/// ทุกรายการของทั้งสองสะพานเดินแบบเดียวกัน:
///   1. ธุรกรรมต้นทางเข้าเชน   (ส่ง USDT / เผา USDT_TPIX / ล็อก TPIX / เผา wTPIX)
///   2. รอเชนต้นทางยืนยันจนถึง finality
///   3. ฝั่งปลายทางส่งมอบ       (mint USDT_TPIX / จ่าย USDT / mint wTPIX / ปล่อย TPIX)
///
/// ★ ห้ามเดาความคืบหน้า: เซิร์ฟเวอร์ไม่ได้บอกว่าต้องรอกี่บล็อก → แถบของขั้น 2 เป็นแบบ "ไม่ระบุสัดส่วน"
///   จนกว่าเซิร์ฟเวอร์บอกว่าถึง finality แล้วเท่านั้นถึงเต็มแถบ
/// ★ สถานะที่แอปรุ่นนี้ไม่รู้จัก → ไม่ทำเป็นว่าเสร็จ/ล้ม ให้ขั้นแรกเป็น "ต้องดู" พร้อมป้ายจากเซิร์ฟเวอร์
///
/// Developed by Xman Studio
library;

import 'package:flutter/foundation.dart';

import '../services/bridge_rules.dart';
import 'obsidian/obsidian_step_tracker.dart';

@immutable
class BridgeProgress {
  /// สถานะของ 3 ขั้น (ต้นทาง · ยืนยัน · ปลายทาง)
  final List<ObsidianStepState> steps;

  /// ขั้นที่ 2 กำลังรอ — โชว์แถบความคืบหน้า
  final bool showConfirmBar;

  /// 1 = ถึง finality แล้ว (เต็มแถบ) · null = ไม่รู้สัดส่วน
  final double? confirmProgress;

  const BridgeProgress(this.steps, {this.showConfirmBar = false, this.confirmProgress});

  /// ขั้นที่ควรโชว์ป้ายสถานะจากเซิร์ฟเวอร์ (ขั้นแรกที่ยังไม่เสร็จ) · -1 = เสร็จหมดแล้ว
  int get focus => steps.indexWhere((s) => s != ObsidianStepState.done);

  bool get complete => focus < 0;
}

const _done = ObsidianStepState.done;
const _active = ObsidianStepState.active;
const _idle = ObsidianStepState.idle;
const _warn = ObsidianStepState.warning;
const _fail = ObsidianStepState.failed;

/// สถานะล่าสุดของรายการ → ขั้นตอนบนจอ
///
/// [status] null = ยังไม่เคยถามได้ (เพิ่งส่ง/เพิ่งเพิ่ม) → ขั้นแรกกำลังทำ
BridgeProgress bridgeProgressOf(BridgeStatusView? status) {
  if (status == null) return const BridgeProgress([_active, _idle, _idle]);
  switch (status.state) {
    // ── ขั้น 1: ยังไม่เห็นธุรกรรมบนเชน / ยังไม่ลงบล็อก ──
    case 'pending':
      return const BridgeProgress([_active, _idle, _idle]);
    case 'unknown':
    case 'not_found':
      // อาจแค่ยังไม่แพร่ถึงโหนด — ไม่ใช่ "ล้ม" แต่ผู้ใช้ควรรู้
      return const BridgeProgress([_warn, _idle, _idle]);
    case 'failed':
    case 'not_a_deposit':
    case 'not_a_withdrawal':
    case 'not_a_lock':
    case 'not_a_burn':
    case 'unsupported_chain':
      return const BridgeProgress([_fail, _idle, _idle]);

    // ── ขั้น 2: รอ finality ──
    case 'confirming':
      return BridgeProgress(
        const [_done, _active, _idle],
        showConfirmBar: true,
        confirmProgress: status.isFinal ? 1 : null,
      );

    // ── ขั้น 3: ฝั่งปลายทาง ──
    case 'queued':
    case 'minting':
    case 'sending':
    case 'releasing':
      return const BridgeProgress([_done, _done, _active]);
    case 'review':
    case 'awaiting_liquidity':
      return const BridgeProgress([_done, _done, _warn]);
    case 'rejected':
    case 'ignored':
    case 'below_fee':
      return const BridgeProgress([_done, _done, _fail]);
    case 'minted':
    case 'paid':
    case 'released':
      return const BridgeProgress([_done, _done, _done]);
  }
  // สถานะใหม่ที่แอปรุ่นนี้ไม่รู้จัก — ไม่เดา
  return const BridgeProgress([_warn, _idle, _idle]);
}
