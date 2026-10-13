/// TPIX Wallet — เทสต์ตรรกะหน้า "กิจกรรม" (ชนิด / เชน / ตัวกรอง / กลุ่มวัน / จำนวน)
///
/// หลักที่ล็อกไว้: อนุมานจากข้อมูลจริงเท่านั้น — ไม่แน่ใจต้องเป็น null ไม่ใช่เดาว่าเป็น TPIX
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:tpix_wallet/models/chain_config.dart';
import 'package:tpix_wallet/models/token_info.dart';
import 'package:tpix_wallet/models/tx_record.dart';
import 'package:tpix_wallet/services/bridge_rules.dart';
import 'package:tpix_wallet/services/bridge_tracker.dart';
import 'package:tpix_wallet/utils/activity_feed.dart';

const _me = '0xd2ea4b1c9f3e7a8b5d6c0f2a1e9b8c7d4f3a67d7';
const _bob = '0x4e7d0c1b2a3f4e5d6c7b8a9f0e1d2c3b4a5f19ba';
const _bscUsdt = '0x55d398326f99059fF775485246999027B3197955';
const _myToken = '0x1111111111111111111111111111111111111111';

String _h(String b) => '0x${b * 32}';

TxRecord _tx({
  String hash = 'aa',
  String from = _me,
  String to = _bob,
  String value = '1000000000000000000',
  String direction = 'sent',
  String status = 'confirmed',
  int? ts = 1760000000,
  String? token,
  String? symbol,
  int? decimals,
}) =>
    TxRecord(
      txHash: _h(hash),
      fromAddress: from,
      toAddress: to,
      value: value,
      direction: direction,
      status: status,
      timestamp: ts,
      tokenAddress: token,
      tokenSymbol: symbol,
      tokenDecimals: decimals,
    );

void main() {
  group('ชนิดรายการ', () {
    final ctx = ActivityContext.build();

    test('ส่ง/รับ TPIX ปกติ → send/receive บน TPIX Chain', () {
      final s = describeActivity(_tx(), ctx);
      expect(s.kind, ActivityKind.send);
      expect(s.chainId, 4289);
      final r = describeActivity(_tx(direction: 'received', from: _bob, to: _me), ctx);
      expect(r.kind, ActivityKind.receive);
      expect(r.counterparty, _bob);
    });

    test('ส่งเข้า router ของ DEX → แลก + เชนของ router (ไม่ใช่ "ส่งให้ 0x10ED…")', () {
      final it = describeActivity(
        _tx(to: ChainConfig.bsc.dexRouterAddress!, symbol: 'BNB', decimals: 18, value: '0'),
        ctx,
      );
      expect(it.kind, ActivityKind.swap);
      expect(it.chainId, 56);
      expect(it.hasAmount, isFalse, reason: 'แลกโทเค็น→x บันทึกมูลค่า 0 — ห้ามโชว์ "−0 BNB"');
    });

    test('มูลค่า 0 ไม่ใช่โทเค็น (approve) → contract ไม่ใช่ "ส่ง 0 BNB"', () {
      final it = describeActivity(_tx(to: _bscUsdt, symbol: 'BNB', decimals: 18, value: '0'), ctx);
      expect(it.kind, ActivityKind.contract);
      expect(it.chainId, 56);
    });

    test('tx hash ที่หน้าบริดจ์จดไว้ → บริดจ์ + เชนต้นทาง ชนะกฎอื่น', () {
      final c = ActivityContext.build(bridges: {
        _h('bb'): const ActivityBridgeHint(kind: usdtDeposit, fromChainId: 56, toChainId: 4289, confirmations: 9),
      });
      final it = describeActivity(
        _tx(hash: 'bb', token: _bscUsdt, symbol: 'USDT', decimals: 18, value: '250000000000000000000'),
        c,
      );
      expect(it.kind, ActivityKind.bridge);
      expect(it.chainId, 56);
      expect(it.bridge!.asset, 'USDT');
      expect(it.inProgress, isTrue, reason: 'ต้นทางผ่านแล้ว แต่สะพานยังไม่จ่ายปลายทาง');
    });

    test('สะพานจบแล้ว → ไม่อยู่ในกลุ่มกำลังดำเนินการ · ต้นทางล้ม = จบ', () {
      final done = ActivityContext.build(bridges: {
        _h('bb'): const ActivityBridgeHint(kind: usdtDeposit, fromChainId: 56, toChainId: 4289, done: true),
      });
      expect(describeActivity(_tx(hash: 'bb'), done).inProgress, isFalse);
      final open = ActivityContext.build(bridges: {
        _h('bb'): const ActivityBridgeHint(kind: usdtDeposit, fromChainId: 56, toChainId: 4289),
      });
      expect(describeActivity(_tx(hash: 'bb', status: 'failed'), open).inProgress, isFalse);
      expect(describeActivity(_tx(hash: 'cc', status: 'pending'), open).inProgress, isTrue);
    });
  });

  group('เชน', () {
    test('โทเค็นที่อยู่ในรายการของผู้ใช้ → เชนของโทเค็นนั้น', () {
      final ctx = ActivityContext.build(tokens: [
        TokenInfo(contractAddress: _myToken, name: 'X', symbol: 'X', decimals: 18, walletSlot: 1, chainId: 137),
      ]);
      final it = describeActivity(_tx(token: _myToken.toUpperCase().replaceFirst('0X', '0x'), symbol: 'X'), ctx);
      expect(it.chainId, 137);
    });

    test('โทเค็นที่แอปรู้จักในตัว (USDT บน BSC) → 56', () {
      final it = describeActivity(_tx(token: _bscUsdt, symbol: 'USDT', decimals: 18), ActivityContext.build());
      expect(it.chainId, 56);
    });

    test('โทเค็นที่ไม่รู้จัก → null (ไม่เดาว่าเป็น TPIX)', () {
      final it = describeActivity(_tx(token: _myToken, symbol: 'ZZZ'), ActivityContext.build());
      expect(it.chainId, isNull);
      expect(activityMatches(it, ActivityFilter.all, 4289), isFalse);
      expect(activityMatches(it, ActivityFilter.all, null), isTrue);
    });

    test('explorer ใช้เชนของรายการ — BNB ไม่ไปเปิดบน explorer ของ TPIX', () {
      final bnb = describeActivity(_tx(symbol: 'BNB', decimals: 18), ActivityContext.build());
      expect(activityExplorerUrl(bnb), 'https://bscscan.com/tx/${_h('aa')}');
      final unknown = describeActivity(_tx(token: _myToken, symbol: 'ZZZ'), ActivityContext.build());
      expect(activityExplorerUrl(unknown), startsWith(ChainConfig.tpix.explorerUrl));
    });
  });

  test('ชื่อของอีกฝั่งจากกระเป๋าตัวเอง/ผู้ติดต่อ (ไม่สนตัวพิมพ์)', () {
    final ctx = ActivityContext.build(names: {_bob.toUpperCase().replaceFirst('0X', '0x'): 'Savings'});
    expect(describeActivity(_tx(), ctx).counterpartyName, 'Savings');
    expect(describeActivity(_tx(to: _myToken), ctx).counterpartyName, isNull);
  });

  test('ตัวกรองชนิด', () {
    final ctx = ActivityContext.build();
    final send = describeActivity(_tx(), ctx);
    final recv = describeActivity(_tx(direction: 'received'), ctx);
    expect(activityMatches(send, ActivityFilter.send, null), isTrue);
    expect(activityMatches(send, ActivityFilter.receive, null), isFalse);
    expect(activityMatches(recv, ActivityFilter.receive, 4289), isTrue);
    expect(activityMatches(recv, ActivityFilter.swap, null), isFalse);
    expect(activityMatches(recv, ActivityFilter.receive, 56), isFalse);
  });

  test('เรียงใหม่สุดก่อน + แบ่งวันตามเวลาท้องถิ่น', () {
    final now = DateTime(2026, 10, 13, 15);
    int s(DateTime d) => d.millisecondsSinceEpoch ~/ 1000;
    final feed = buildActivityFeed([
      _tx(hash: 'a1', ts: s(DateTime(2026, 10, 12, 9))),
      _tx(hash: 'a2', ts: s(DateTime(2026, 10, 13, 14))),
      _tx(hash: 'a3', ts: s(DateTime(2026, 10, 13, 8))),
      _tx(hash: 'a4', ts: s(DateTime(2025, 12, 31, 23))),
    ], ActivityContext.build());
    expect(feed.map((e) => e.tx.txHash), [_h('a2'), _h('a3'), _h('a1'), _h('a4')]);
    final days = groupActivityByDay(feed);
    expect(days, hasLength(3));
    expect(days.first.items, hasLength(2));
    String label(DateTime d, bool th) =>
        activityDayLabel(d, now, thai: th, today: 'วันนี้', yesterday: 'เมื่อวาน');
    expect(label(days[0].day, true), 'วันนี้');
    expect(label(days[1].day, true), 'เมื่อวาน');
    expect(label(days[2].day, true), '31 ธ.ค. 2568', reason: 'ปีอื่นใช้ พ.ศ.');
    expect(label(days[2].day, false), 'Dec 31, 2025');
    expect(label(DateTime(2026, 10, 1), false), 'Oct 1');
    expect(activityClock(DateTime(2026, 1, 2, 9, 5)), '09:05');
  });

  test('จำนวน: คั่นหลักพัน ตัดเศษไม่ปัดขึ้น ไม่ผ่าน double', () {
    final e18 = BigInt.from(10).pow(18);
    expect(formatActivityAmount(BigInt.from(1500) * e18, 18), '1,500');
    expect(formatActivityAmount(BigInt.parse('120000000000000000'), 18), '0.12');
    expect(formatActivityAmount(BigInt.from(20000000), 6), '20');
    expect(formatActivityAmount(BigInt.parse('1234567899999999999999'), 18), '1,234.5678');
    expect(formatActivityAmount(BigInt.one, 18), '<0.000001');
    expect(formatActivityAmount(BigInt.zero, 18), '0');
    // ค่าที่ double แสดงเพี้ยน (0.1+0.2) ต้องตรงทุกหลัก
    expect(formatActivityAmount(BigInt.parse('300000000000000000'), 18), '0.3');
  });

  test('คีย์ที่เก็บรายการบริดจ์ตรงกับ BridgeTracker', () {
    final u = BridgeTracker(wtpix: false);
    final w = BridgeTracker(wtpix: true);
    addTearDown(u.dispose);
    addTearDown(w.dispose);
    expect(activityUsdtBridgeKey, u.storageKey);
    expect(activityWtpixBridgeKey, w.storageKey);
  });

  test('bridgeHintsFrom: เฉพาะกระเป๋าที่ใช้อยู่ + ทิศของแต่ละสะพาน', () {
    final hints = bridgeHintsFrom([
      TrackedTransfer(kind: usdtDeposit, chainId: 56, txHash: _h('d1'), owner: _me),
      TrackedTransfer(kind: usdtWithdraw, chainId: 4289, txHash: _h('d2'), targetChainId: 137, owner: _me),
      TrackedTransfer(kind: wtpixToBsc, chainId: 4289, txHash: _h('d3'), owner: _me),
      TrackedTransfer(kind: wtpixToTpix, chainId: 56, txHash: _h('d4')),
      TrackedTransfer(kind: usdtDeposit, chainId: 56, txHash: _h('d5'), owner: _bob),
    ], _me.toUpperCase().replaceFirst('0X', '0x'));
    expect(hints.keys, containsAll([_h('d1'), _h('d2'), _h('d3'), _h('d4')]));
    expect(hints.containsKey(_h('d5')), isFalse, reason: 'ของกระเป๋าใบอื่นห้ามโผล่');
    expect((hints[_h('d1')]!.fromChainId, hints[_h('d1')]!.toChainId), (56, 4289));
    expect((hints[_h('d2')]!.fromChainId, hints[_h('d2')]!.toChainId), (4289, 137));
    expect((hints[_h('d3')]!.fromChainId, hints[_h('d3')]!.toChainId), (4289, 56));
    expect(hints[_h('d4')]!.asset, 'TPIX');
    expect(hints[_h('d1')]!.done, isFalse);
  });
}
