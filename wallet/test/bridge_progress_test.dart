/// TPIX Wallet — สถานะสะพาน → ขั้นตอน 3 ขั้นบนจอ (ธีม Obsidian)
///
/// สิ่งที่ห้ามพัง:
///   - ห้ามโชว์ว่า "เสร็จ" ก่อนเซิร์ฟเวอร์ยืนยันว่าส่งมอบแล้วจริง
///   - ห้ามเดาเปอร์เซ็นต์การยืนยันบล็อก (เซิร์ฟเวอร์ไม่บอกว่าต้องรอกี่บล็อก) — เต็มแถบเมื่อถึง finality เท่านั้น
///   - สถานะที่แอปไม่รู้จัก → ไม่ทำเป็นว่าเสร็จหรือล้ม
///   - ข้อความแต่ละขั้นมาจากสถานะจริง (จำนวนบล็อก / ป้ายจากเซิร์ฟเวอร์ / ยอดที่ส่งมอบ)
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:tpix_wallet/core/locale_provider.dart';
import 'package:tpix_wallet/services/bridge_rules.dart';
import 'package:tpix_wallet/widgets/bridge_obsidian.dart';
import 'package:tpix_wallet/widgets/bridge_progress.dart';
import 'package:tpix_wallet/widgets/bridge_widgets.dart';
import 'package:tpix_wallet/widgets/obsidian/obsidian_step_tracker.dart';

const done = ObsidianStepState.done;
const active = ObsidianStepState.active;
const idle = ObsidianStepState.idle;
const warn = ObsidianStepState.warning;
const fail = ObsidianStepState.failed;

BridgeStatusView s(String state, {int? confirmations, bool isFinal = false}) =>
    BridgeStatusView(state: state, confirmations: confirmations, isFinal: isFinal);

void main() {
  group('bridgeProgressOf', () {
    test('ยังไม่เคยถามได้ / รอลงบล็อก → ขั้นแรกกำลังทำ', () {
      expect(bridgeProgressOf(null).steps, [active, idle, idle]);
      expect(bridgeProgressOf(s('pending')).steps, [active, idle, idle]);
    });

    test('ไม่พบบนเชน / อ่านไม่ได้ → ขั้นแรก "ต้องดู" (อาจยังไม่แพร่ถึงโหนด ไม่ใช่ล้ม)', () {
      expect(bridgeProgressOf(s('not_found')).steps, [warn, idle, idle]);
      expect(bridgeProgressOf(s('unknown')).steps, [warn, idle, idle]);
    });

    test('ธุรกรรมต้นทางล้ม/ไม่ใช่รายการสะพาน → ขั้นแรกล้ม', () {
      for (final st in ['failed', 'not_a_deposit', 'not_a_withdrawal', 'not_a_lock', 'not_a_burn', 'unsupported_chain']) {
        expect(bridgeProgressOf(s(st)).steps, [fail, idle, idle], reason: st);
      }
    });

    test('รอ finality → แถบไม่ระบุสัดส่วน · ถึง finality แล้วค่อยเต็มแถบ', () {
      final waiting = bridgeProgressOf(s('confirming', confirmations: 11));
      expect(waiting.steps, [done, active, idle]);
      expect(waiting.showConfirmBar, isTrue);
      expect(waiting.confirmProgress, isNull, reason: 'ห้ามเดาเปอร์เซ็นต์');

      final finalized = bridgeProgressOf(s('confirming', confirmations: 15, isFinal: true));
      expect(finalized.confirmProgress, 1);
    });

    test('ฝั่งปลายทางกำลังทำ / รอคน / ปฏิเสธ', () {
      for (final st in ['queued', 'minting', 'sending', 'releasing']) {
        expect(bridgeProgressOf(s(st)).steps, [done, done, active], reason: st);
      }
      for (final st in ['review', 'awaiting_liquidity']) {
        expect(bridgeProgressOf(s(st)).steps, [done, done, warn], reason: st);
      }
      for (final st in ['rejected', 'ignored', 'below_fee']) {
        expect(bridgeProgressOf(s(st)).steps, [done, done, fail], reason: st);
      }
    });

    test('ส่งมอบแล้วจริงเท่านั้นถึงเสร็จทั้ง 3 ขั้น', () {
      for (final st in ['minted', 'paid', 'released']) {
        final p = bridgeProgressOf(s(st));
        expect(p.steps, [done, done, done], reason: st);
        expect(p.complete, isTrue);
      }
      expect(bridgeProgressOf(s('minting')).complete, isFalse);
    });

    test('สถานะใหม่ที่แอปไม่รู้จัก → ไม่เดา', () {
      final p = bridgeProgressOf(s('some_future_state'));
      expect(p.steps, [warn, idle, idle]);
      expect(p.complete, isFalse);
    });

    test('ทุกสถานะที่แอปรู้จักมีขั้นตอนครบ 3 ขั้น และ "เสร็จ" ตรงกับสถานะจบแบบสำเร็จเท่านั้น', () {
      for (final st in {...usdtTerminalStates, ...wtpixTerminalStates, 'pending', 'confirming', 'queued'}) {
        final p = bridgeProgressOf(s(st));
        expect(p.steps, hasLength(3));
        expect(p.complete, ['minted', 'paid', 'released'].contains(st), reason: st);
      }
    });
  });

  group('bridgeObsSteps (ข้อความ)', () {
    final l = LocaleProvider();
    const text = BridgeObsStepText(send: 'A', confirm: 'B', deliver: 'C');

    test('รอ finality: ขั้น 2 บอกจำนวนบล็อกจริง', () {
      final steps = bridgeObsSteps(l, status: s('confirming', confirmations: 11), text: text, badgeLabel: 'x');
      expect(steps.map((e) => e.title), ['A', 'B', 'C']);
      expect(steps[0].sub, l.t('obs.bridge.step.inChain'));
      expect(steps[1].sub, bridgeT(l, 'bridge.confirmations', {'n': '11'}));
      expect(steps[1].showBar, isTrue);
      expect(steps[1].progress, isNull);
      expect(steps[2].sub, l.t('obs.bridge.step.waitPrev'));
    });

    test('ถึง finality: ใช้ข้อความ "จะเข้าคิวเร็ว ๆ นี้"', () {
      final steps = bridgeObsSteps(l, status: s('confirming', isFinal: true), text: text, badgeLabel: 'x');
      expect(steps[1].sub, l.t('bridge.finalSoon'));
      expect(steps[1].progress, 1);
    });

    test('ยังไม่มีสถานะ → "กำลังถามสถานะ"', () {
      final steps = bridgeObsSteps(l, status: null, text: text, badgeLabel: null);
      expect(steps[0].state, active);
      expect(steps[0].sub, l.t('obs.bridge.step.checking'));
    });

    test('ติดที่ขั้นปลายทาง → ป้ายจากเซิร์ฟเวอร์อยู่ที่ขั้นนั้น', () {
      final steps = bridgeObsSteps(l, status: s('review'), text: text, badgeLabel: 'รอทีมงานตรวจสอบ');
      expect(steps[2].state, warn);
      expect(steps[2].sub, 'รอทีมงานตรวจสอบ');
      expect(steps[0].sub, l.t('obs.bridge.step.inChain'));
    });

    test('ส่งมอบแล้ว → บอกยอดที่ได้', () {
      final steps = bridgeObsSteps(l, status: s('minted'), text: text, badgeLabel: 'ok', delivered: '250 USDT');
      expect(steps[2].sub, '${l.t('obs.bridge.step.delivered')} · 250 USDT');
    });
  });

  test('ชื่อเชนสั้นบนการ์ดเส้นทาง — เชนที่ไม่รู้จักใช้ชื่อจากเซิร์ฟเวอร์', () {
    expect(bridgeChainShortName(56, 'BNB Smart Chain'), 'BNB Chain');
    expect(bridgeChainShortName(999, 'Some Chain'), 'Some Chain');
  });

  test('วงเงินจากเซิร์ฟเวอร์: ตัวเลขใส่จุลภาค · ไม่มีค่า = ขีด · ข้อความอื่นคงเดิม', () {
    expect(bridgeObsLimit('1000'), '1,000');
    expect(bridgeObsLimit('2500.5'), '2,500.5');
    expect(bridgeObsLimit('0.3'), '0.3');
    expect(bridgeObsLimit(5000), '5,000');
    expect(bridgeObsLimit(null), '—');
    expect(bridgeObsLimit(''), '—');
    expect(bridgeObsLimit('n/a'), 'n/a');
  });
}
