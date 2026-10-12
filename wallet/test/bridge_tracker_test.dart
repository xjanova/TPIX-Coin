/// TPIX Wallet — เทสต์ตัวติดตามรายการของสะพาน
///
/// สิ่งที่ต้องกันพลาด:
///   - ส่งแล้วต้องจด hash ไว้ในเครื่องเสมอ (ปิดหน้า/ปิดแอปแล้วกลับมาติดตามต่อได้ — แม้หน้าถูกปิดระหว่างส่ง)
///   - ถามเฉพาะรายการที่ยังไม่จบ · จบหมด = หยุดตั้งเวลา (ไม่ยิงเซิร์ฟเวอร์ทิ้งไปเรื่อยๆ)
///   - สลับกระเป๋าแล้วไม่โชว์รายการของใบอื่น
///   - โดนจำกัดความถี่ (429) = พักรอบนี้ · ลบรายการระหว่างถาม = ไม่ถูกใส่กลับ
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tpix_wallet/services/bridge_rules.dart';
import 'package:tpix_wallet/services/bridge_service.dart';
import 'package:tpix_wallet/services/bridge_tracker.dart';

const _a = '0xaaaa000000000000000000000000000000001111';
const _b = '0xbbbb000000000000000000000000000000002222';
String hashOf(int i) => '0x${i.toRadixString(16).padLeft(64, '0')}';

TrackedTransfer deposit(int i, {String owner = _a, bool sentHere = false}) =>
    TrackedTransfer(kind: usdtDeposit, chainId: 56, txHash: hashOf(i), owner: owner, sentHere: sentHere);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('เพิ่มแล้วจดลงเครื่องทันที — ตัวติดตามใหม่ (เปิดหน้าใหม่) อ่านกลับได้ พร้อมสถานะล่าสุด', () async {
    final t1 = BridgeTracker(wtpix: false, fetcher: (_) async => const BridgeStatusView(state: 'minted'), historySync: (_, _) async {});
    t1.setOwner(_a);
    await t1.load();
    await t1.add(deposit(1));
    await t1.pollOnce();
    t1.dispose();

    final t2 = BridgeTracker(wtpix: false, fetcher: (_) async => throw StateError('ห้ามถามซ้ำรายการที่จบแล้ว'));
    t2.setOwner(_a);
    await t2.load();
    expect(t2.entries.single.txHash, hashOf(1));
    expect(t2.entries.single.status?.state, 'minted');
    expect(t2.hasActive, isFalse);
    expect(t2.isTicking, isFalse);
    t2.dispose();
  });

  test('รายการยังไม่จบ = ตั้งเวลาถาม · จบแล้ว = หยุดตั้งเวลา', () async {
    var state = 'confirming';
    final t = BridgeTracker(wtpix: false, fetcher: (_) async => BridgeStatusView(state: state), historySync: (_, _) async {});
    t.setOwner(_a);
    await t.load();
    await t.add(deposit(1));
    await t.pollOnce();
    expect(t.entries.single.status?.state, 'confirming');
    expect(t.isTicking, isTrue);

    state = 'minted';
    await t.pollOnce();
    expect(t.entries.single.status?.state, 'minted');
    expect(t.isTicking, isFalse);
    t.dispose();
  });

  test('สลับกระเป๋า → เห็นและถามเฉพาะรายการของใบที่ใช้อยู่', () async {
    final asked = <String>[];
    final t = BridgeTracker(wtpix: false, fetcher: (e) async {
      asked.add(e.txHash);
      return const BridgeStatusView(state: 'confirming');
    });
    t.setOwner(_a);
    await t.load();
    await t.add(deposit(1, owner: _a));
    await t.add(deposit(2, owner: _b));
    await t.pollOnce();
    expect(t.entries.map((e) => e.txHash), [hashOf(1)]);
    expect(asked, isNot(contains(hashOf(2))));

    asked.clear();
    t.setOwner(_b);
    await t.pollOnce();
    expect(t.entries.map((e) => e.txHash), [hashOf(2)]);
    expect(asked, isNot(contains(hashOf(1))));
    t.dispose();
  });

  test('โดนจำกัดความถี่ (429) → พักทั้งรอบ ไม่ถามรายการที่เหลือ', () async {
    final asked = <String>[];
    final t = BridgeTracker(wtpix: false, fetcher: (e) async {
      asked.add(e.txHash);
      throw const BridgeRateLimitedException();
    });
    t.setOwner(_a);
    await t.load();
    await t.add(deposit(1));
    await t.add(deposit(2));
    await t.pollOnce(); // รอรอบที่ add สั่งไว้ให้จบก่อน
    asked.clear();
    await t.pollOnce();
    expect(asked, hasLength(1));
    expect(t.entries.every((e) => e.status == null), isTrue, reason: 'ไม่ล้าง/ไม่เดาสถานะ');
    t.dispose();
  });

  test('ถามไม่เกิน maxPerRound ต่อรอบ และวนคิวจนครบทุกรายการ', () async {
    final asked = <String>[];
    final t = BridgeTracker(wtpix: false, maxPerRound: 2, fetcher: (e) async {
      asked.add(e.txHash);
      return const BridgeStatusView(state: 'confirming');
    });
    t.setOwner(_a);
    await t.load();
    for (var i = 1; i <= 5; i++) {
      await t.add(deposit(i));
    }
    await t.pollOnce(); // รอรอบที่ add สั่งไว้ให้จบก่อน
    asked.clear();
    await t.pollOnce();
    expect(asked, hasLength(2));
    await t.pollOnce();
    await t.pollOnce();
    expect(asked.toSet(), hasLength(5));
    t.dispose();
  });

  test('ลบรายการระหว่างกำลังถาม → ไม่ถูกใส่กลับ และไม่กลับมาจากของในเครื่อง', () async {
    final gate = Completer<BridgeStatusView>();
    final t = BridgeTracker(wtpix: false, fetcher: (_) => gate.future);
    t.setOwner(_a);
    await t.load();
    await t.add(deposit(1));
    final polling = t.pollOnce();
    await t.remove(t.entries.single);
    gate.complete(const BridgeStatusView(state: 'minted'));
    await polling;
    expect(t.entries, isEmpty);
    t.dispose();

    final again = BridgeTracker(wtpix: false, fetcher: (_) async => const BridgeStatusView(state: 'minted'));
    again.setOwner(_a);
    await again.load();
    expect(again.entries, isEmpty);
    again.dispose();
  });

  test('หน้าถูกปิดระหว่างส่ง (ตัวติดตามถูก dispose แล้ว) → hash ยังถูกจดลงเครื่อง', () async {
    final t = BridgeTracker(wtpix: false, fetcher: (_) async => const BridgeStatusView(state: 'confirming'));
    t.setOwner(_a);
    await t.load();
    t.dispose();
    await t.add(deposit(9, sentHere: true));

    final reopened = BridgeTracker(wtpix: false, fetcher: (_) async => const BridgeStatusView(state: 'confirming'));
    reopened.setOwner(_a);
    await reopened.load();
    expect(reopened.entries.single.txHash, hashOf(9));
    expect(reopened.entries.single.sentHere, isTrue);
    reopened.dispose();
  });

  test('หน้าใหม่ที่เปิดอยู่ไม่เขียนทับรายการที่หน้าเก่าเพิ่งจด (รวมของในเครื่องก่อนเขียน)', () async {
    final open = BridgeTracker(wtpix: false, fetcher: (_) async => const BridgeStatusView(state: 'confirming'));
    open.setOwner(_a);
    await open.load();

    // หน้ารอบก่อน (ถูกปิดไปแล้ว) จดรายการที่เพิ่งส่งเสร็จ
    final closed = BridgeTracker(wtpix: false);
    closed.dispose();
    await closed.add(deposit(7));

    // หน้าที่เปิดอยู่เพิ่มรายการของตัวเอง → ต้องไม่ลบรายการ 7 ทิ้ง
    await open.add(deposit(8));
    expect(open.entries.map((e) => e.txHash).toSet(), {hashOf(7), hashOf(8)});
    open.dispose();
  });

  test('ส่งจากแอปนี้ → อัปเดตแถวในประวัติ: ขุดแล้ว = confirmed · ล้มบนเชน = failed · ยังไม่รู้ = ไม่แตะ', () async {
    final synced = <(String, String)>[];
    final states = {hashOf(1): 'minted', hashOf(2): 'failed', hashOf(3): 'pending', hashOf(4): 'not_a_deposit'};
    final t = BridgeTracker(
      wtpix: false,
      fetcher: (e) async => BridgeStatusView(state: states[e.txHash]!),
      historySync: (hash, status) async => synced.add((hash, status)),
    );
    t.setOwner(_a);
    await t.load();
    for (var i = 1; i <= 4; i++) {
      await t.add(deposit(i, sentHere: true));
    }
    await t.add(TrackedTransfer(kind: usdtDeposit, chainId: 56, txHash: hashOf(5), owner: _a)); // ติดตามด้วยมือ
    for (var i = 0; i < 3; i++) {
      await t.pollOnce();
    }
    await Future<void>.delayed(Duration.zero);
    expect(synced.toSet(), {(hashOf(1), 'confirmed'), (hashOf(2), 'failed'), (hashOf(4), 'confirmed')});
    t.dispose();
  });

  test('สะพาน wTPIX ใช้ป้ายของตัวเอง (released = จบ) และเก็บแยกจากสะพาน USDT', () async {
    final w = BridgeTracker(wtpix: true, fetcher: (_) async => const BridgeStatusView(state: 'released'));
    w.setOwner(_a);
    await w.load();
    await w.add(TrackedTransfer(kind: wtpixToTpix, chainId: 56, txHash: hashOf(1), owner: _a));
    await w.pollOnce();
    expect(w.hasActive, isFalse);
    w.dispose();

    final u = BridgeTracker(wtpix: false);
    u.setOwner(_a);
    await u.load();
    expect(u.entries, isEmpty);
    u.dispose();
  });
}
