/// TPIX Wallet — เทสต์กติกาของสะพาน (พอร์ตเคสจากเว็บ ThaiXTrade)
///
/// ที่มาของเคส:
///   tests/js/utils/bridge.test.js            — สะพาน USDT (ทุกเคสพอร์ตมาตรงๆ)
///   tests/js/components/BridgeWtpix.test.js  — วงเงิน/เพดานบนสัญญาของสะพาน wTPIX
/// เงินคำนวณเป็น BigInt ทั้งหมด — เทสต์ชุดนี้กันไม่ให้มีใครแอบเปลี่ยนไปใช้ double
/// (1 USDT บน BSC = 1e18 · 0.1 + 0.2 ≠ 0.3)
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:tpix_wallet/services/bridge_rules.dart';
import 'package:tpix_wallet/services/rpc_client.dart';
import 'package:tpix_wallet/services/wallet_service.dart';

BigInt b(Object v) => BigInt.parse(v.toString());
final e18 = BigInt.from(10).pow(18);

/// info ของ /api/v1/bridge/info?asset=tpix — ค่าเดียวกับเทสต์หน้าเว็บ
Map<String, dynamic> tpixInfo() => {
      'limits': {
        'min_lock': '10',
        'max_lock_per_tx': '100000',
        'max_lock_per_address_daily': '200000',
        'lock_fee': '1',
        'min_burn': '10',
        'max_burn_per_tx': '100000',
        'max_burn_per_address_daily': '200000',
        'burn_fee': '0',
      },
      'vault': {
        'min_lock': '10',
        'max_lock': '100000',
        'max_per_tx': '100000',
        'daily_cap': '500000',
        'remaining_today': '500000',
        'paused': false,
      },
    };

void main() {
  group('parseAmountToUnits', () {
    test("แปลงเป็นหน่วยเล็กสุดแบบเป๊ะ รวม USDT บน BSC ที่มี 18 ทศนิยม", () {
      expect(parseAmountToUnits('12.345678', 18), b('12345678000000000000'));
      expect(parseAmountToUnits('0.1', 6), b(100000));
      expect(parseAmountToUnits('1000', 6), b(1000000000));
      expect(parseAmountToUnits('1,000.5', 6), b(1000500000));
    });

    test('ทศนิยมเกิน 6 ตำแหน่ง → ไม่รับ แม้เชนต้นทางมี 18 (เศษจะเป็นฝุ่นค้างใน vault)', () {
      expect(parseAmountToUnits('1.1234567', 18), isNull);
      expect(parseAmountToUnits('1.1234567', 6), isNull);
    });

    test('อะไรที่ไม่ใช่ตัวเลขบวกธรรมดา → null', () {
      for (final bad in ['', 'abc', '-1', '1e6', '0x10', '1.2.3', ' . ', null]) {
        expect(parseAmountToUnits(bad, 6), isNull, reason: '$bad');
      }
    });
  });

  group('formatUnitsPlain', () {
    test('ไม่มีเศษ float', () {
      expect(formatUnitsPlain(b('24700000000000000000'), 18), '24.7');
      expect(formatUnitsPlain(BigInt.one, 6), '0.000001');
      expect(formatUnitsPlain(BigInt.zero, 6), '0');
      expect(formatUnitsPlain(b(-300000), 6), '-0.3');
    });
  });

  group('withdrawReceiveUnits', () {
    test('หักค่าธรรมเนียมคงที่ของเชน และไม่ติดลบ', () {
      expect(withdrawReceiveUnits(b(25000000), '0.3'), b(24700000));
      expect(withdrawReceiveUnits(b(1000000), '1'), BigInt.zero);
      expect(withdrawReceiveUnits(b(500000), '1'), BigInt.zero);
    });
  });

  group('toUsdt6', () {
    test('18 ทศนิยม (BSC) หารลงเป็น 6 · 6 ทศนิยมคงเดิม', () {
      expect(toUsdt6(b('25000000000000000000'), 18), b(25000000));
      expect(toUsdt6(b(25000000), 6), b(25000000));
      expect(toUsdt6(b(25), 0), b(25000000));
    });
  });

  group('checkDepositAmount', () {
    final limits = {'min_deposit': '1', 'max_deposit_per_tx': '1000'};

    test('ต่ำกว่าขั้นต่ำ → ห้ามส่ง (จะไม่ถูก mint)', () {
      final r = checkDepositAmount(b(500000), limits);
      expect(r.error, 'bridge.errBelowMin');
      expect(r.params, {'min': '1'});
      expect(checkDepositAmount(BigInt.zero, limits).error, 'bridge.errAmountInvalid');
      expect(checkDepositAmount(null, limits).error, 'bridge.errAmountInvalid');
    });

    test('เกินวงเงินต่อครั้ง → ส่งได้แต่เตือน (รอทีมงานตรวจ)', () {
      final r = checkDepositAmount(b(1500000000), limits);
      expect(r.error, isNull);
      expect(r.warning, 'bridge.errAboveMax');
      expect(r.warningParams, {'max': '1000'});
    });

    test('ยอดปกติผ่าน', () {
      final r = checkDepositAmount(b(25000000), limits);
      expect(r.error, isNull);
      expect(r.warning, isNull);
    });

    test('ไม่มีวงเงินจากเซิร์ฟเวอร์ → ขั้นต่ำ 1 USDT แบบเว็บ', () {
      expect(checkDepositAmount(b(999999), null).error, 'bridge.errBelowMin');
      expect(checkDepositAmount(b(1000000), null).blocked, isFalse);
    });
  });

  group('checkWithdrawAmount', () {
    final limits = {'min_withdraw': '2', 'max_withdraw_per_tx': '1000'};

    test('ลำดับเดียวกับเว็บ: ผิดรูป → ไม่เกินค่าธรรมเนียม → ต่ำกว่าขั้นต่ำ → ยอดไม่พอ', () {
      expect(checkWithdrawAmount(null, fee: '0.3', limits: limits).error, 'bridge.errAmountInvalid');
      expect(checkWithdrawAmount(b(300000), fee: '0.3', limits: limits).error, 'bridge.errFeeTooHigh');
      final belowMin = checkWithdrawAmount(b(1500000), fee: '0.3', limits: limits);
      expect(belowMin.error, 'bridge.errBelowMinWithdraw');
      expect(belowMin.params, {'min': '2'});
      expect(
        checkWithdrawAmount(b(5000000), fee: '0.3', limits: limits, balance: b(4000000)).error,
        'bridge.errInsufficient',
      );
      expect(checkWithdrawAmount(b(5000000), fee: '0.3', limits: limits, balance: b(5000000)).blocked, isFalse);
    });

    test('อ่านยอดไม่ได้ (null) ≠ ศูนย์ — ไม่บล็อกตรงนี้', () {
      expect(checkWithdrawAmount(b(5000000), fee: '0.3', limits: limits).blocked, isFalse);
    });
  });

  group('isValidEvmAddress', () {
    test('ตัวเล็กล้วน และ checksum ที่ถูกต้อง → ผ่าน', () {
      expect(isValidEvmAddress('0xf46131c82819d7621163f482b3fe88a228a7807c'), isTrue);
      expect(isValidEvmAddress('0xf46131C82819d7621163F482b3fe88a228A7807c'), isTrue);
    });

    test('พิมพ์ผิดที่ checksum จับได้ / ที่อยู่ศูนย์ / รูปแบบอื่น → ไม่ผ่าน', () {
      expect(isValidEvmAddress('0xF46131C82819d7621163F482b3fe88a228A7807c'), isFalse);
      expect(isValidEvmAddress('0x0000000000000000000000000000000000000000'), isFalse);
      expect(isValidEvmAddress('TXYZ1234567890abcdef'), isFalse);
      expect(isValidEvmAddress('0x123'), isFalse);
      expect(isValidEvmAddress(null), isFalse);
    });
  });

  group('stateBadge', () {
    test('สถานะที่จบแล้ว = done → เลิกถาม', () {
      final minted = stateBadge('minted');
      expect(minted.tone, BridgeTone.success);
      expect(minted.done, isTrue);
      expect(minted.labelKey, 'bridge.state.minted');
      expect(stateBadge('paid').done, isTrue);
      expect(stateBadge('confirming').done, isFalse);
      final review = stateBadge('review');
      expect(review.tone, BridgeTone.warning);
      expect(review.done, isFalse);
    });

    test('สถานะที่ไม่รู้จัก → โทนกลาง ยังถามต่อ', () {
      expect(stateBadge('something_new').tone, BridgeTone.muted);
      expect(stateBadge('something_new').done, isFalse);
    });

    test('ชื่อสถานะในตารางประวัติ → สถานะสาธารณะ (เหมือนหน้าเว็บ)', () {
      expect(usdtDepositRowState('needs_review'), 'review');
      expect(usdtDepositRowState('confirmed'), 'queued');
      expect(usdtDepositRowState('minted'), 'minted');
      expect(usdtWithdrawalRowState('pending'), 'queued');
      expect(usdtWithdrawalRowState('ignored'), 'below_fee');
      expect(usdtWithdrawalRowState('paid'), 'paid');
    });
  });

  group('explorer links', () {
    test('สร้างลิงก์ tx และทนเครื่องหมาย / ท้าย', () {
      expect(explorerTx('https://bscscan.com/', '0xabc'), 'https://bscscan.com/tx/0xabc');
      expect(explorerTx('', '0xabc'), isNull);
      expect(explorerTx(null, '0xabc'), isNull);
    });

    test('เปิดได้เฉพาะ https ที่มีโฮสต์ (ลิงก์มาจากเซิร์ฟเวอร์)', () {
      expect(safeHttpsUrl('https://bscscan.com/tx/0x1'), 'https://bscscan.com/tx/0x1');
      for (final bad in ['http://bscscan.com/tx/0x1', 'javascript:alert(1)', 'https://user:pw@evil.test/x', 'https://', 42, null]) {
        expect(safeHttpsUrl(bad), isNull, reason: '$bad');
      }
    });
  });

  group('tracked transfers', () {
    final hash = '0x${'a' * 64}';

    test('เก็บแล้วอ่านกลับได้ และกันซ้ำรายการเดียวกัน (ตัวพิมพ์ต่างกันก็ถือว่าซ้ำ)', () {
      var list = addTracked([], TrackedTransfer(kind: usdtDeposit, chainId: 56, txHash: '0x${'A' * 64}'));
      list = addTracked(list, TrackedTransfer(kind: usdtDeposit, chainId: 56, txHash: hash));
      expect(list, hasLength(1));
      expect(list.first.txHash, hash);

      final back = decodeTracked(encodeTracked(list), usdtTrackKinds);
      expect(back, hasLength(1));
      expect(back.first.key, list.first.key);
    });

    test('แถวผิดรูปถูกทิ้ง และข้อมูลเสียไม่ทำให้พัง', () {
      expect(
        decodeTracked('[{"kind":"deposit","chainId":1,"txHash":"nope"},{"kind":"x","chainId":1,"txHash":"$hash"}]', usdtTrackKinds),
        isEmpty,
      );
      expect(decodeTracked('{not json', usdtTrackKinds), isEmpty);
      expect(decodeTracked('{"a":1}', usdtTrackKinds), isEmpty);
      expect(decodeTracked(null, usdtTrackKinds), isEmpty);
      // ชนิดของสะพานอีกตัวไม่ปนกัน
      expect(decodeTracked('[{"kind":"to_bsc","chainId":4289,"txHash":"$hash"}]', usdtTrackKinds), isEmpty);
      expect(decodeTracked('[{"kind":"to_bsc","chainId":4289,"txHash":"$hash"}]', wtpixTrackKinds), hasLength(1));
    });

    test('ติดตามซ้ำ = ย้ายขึ้นบนสุด ไม่งอก และไม่ทิ้งสถานะที่รู้แล้ว', () {
      final other = '0x${'b' * 64}';
      var list = addTracked([], TrackedTransfer(kind: wtpixToBsc, chainId: 4289, txHash: hash)
          .withStatus(const BridgeStatusView(state: 'minted')));
      list = addTracked(list, TrackedTransfer(kind: wtpixToBsc, chainId: 4289, txHash: other));
      list = addTracked(list, TrackedTransfer(kind: wtpixToBsc, chainId: 4289, txHash: hash));
      expect(list.map((e) => e.txHash), [hash, other]);
      expect(list.first.status?.state, 'minted');
    });

    test('เก็บได้ไม่เกิน $trackLimit รายการ', () {
      var list = <TrackedTransfer>[];
      for (var i = 0; i < trackLimit + 5; i++) {
        list = addTracked(list, TrackedTransfer(kind: usdtDeposit, chainId: 1, txHash: '0x${i.toRadixString(16).padLeft(64, '0')}'));
      }
      expect(list, hasLength(trackLimit));
    });

    test('สถานะที่เก็บไว้ผ่านด่านตรวจซ้ำตอนอ่านกลับ (ลิงก์ http ถูกทิ้ง)', () {
      final raw = '[{"kind":"withdraw","chainId":4289,"txHash":"$hash","status":{"state":"paid",'
          '"rows":[{"amount":"24.7","url":"http://evil.test/x"},{"amount":"1","url":"https://bscscan.com/tx/0x1"}]}}]';
      final list = decodeTracked(raw, usdtTrackKinds);
      expect(list.single.status?.state, 'paid');
      expect(list.single.status?.rows.first.url, isNull);
      expect(list.single.status?.rows.last.url, 'https://bscscan.com/tx/0x1');
    });
  });

  group('BridgeStatusView.fromServer', () {
    test('ฝาก: แถว mint + ลิงก์', () {
      final v = BridgeStatusView.fromServer({
        'state': 'minted',
        'deposits': [
          {'mint_amount': '25', 'mint_url': 'https://explorer.tpix.online/tx/0x1', 'status': 'minted'},
        ],
      });
      expect(v.state, 'minted');
      expect(v.rows.single.amount, '25');
      expect(v.rows.single.url, 'https://explorer.tpix.online/tx/0x1');
    });

    test('ถอน: ยอดจ่าย + ที่อยู่/เชนปลายทาง', () {
      final v = BridgeStatusView.fromServer({
        'state': 'paid',
        'withdrawals': [
          {'payout_amount': '24.7', 'payout_url': 'https://bscscan.com/tx/0x2', 'target_chain_id': 56, 'target_address': '0xf46131c82819d7621163f482b3fe88a228a7807c'},
        ],
      });
      expect(v.rows.single.targetChainId, 56);
      expect(v.rows.single.targetAddress, '0xf46131c82819d7621163f482b3fe88a228a7807c');
    });

    test('รอยืนยัน: ยอด + บล็อกยืนยัน + final', () {
      final v = BridgeStatusView.fromServer({'state': 'confirming', 'amount': '500', 'confirmations': 1, 'final': false, 'transfers': []});
      expect(v.amount, '500');
      expect(v.confirmations, 1);
      expect(v.isFinal, isFalse);
    });

    test('ค่าผิดรูปจากเซิร์ฟเวอร์ถูกทิ้ง ไม่เดา', () {
      final v = BridgeStatusView.fromServer({
        'state': '<script>',
        'amount': 'lots',
        'transfers': [
          {'receive_amount': '1e9', 'dest_url': 'javascript:x', 'direction': 'sideways'},
        ],
      });
      expect(v.state, 'unknown');
      expect(v.amount, isNull);
      expect(v.rows.single.amount, isNull);
      expect(v.rows.single.url, isNull);
      expect(v.rows.single.direction, isNull);
    });
  });

  group('bridgeErrorKey', () {
    test('ไม่มีวันโชว์ exception ดิบ', () {
      expect(bridgeErrorKey(const RpcException('execution reverted: insufficient balance')), 'bridge.errInsufficient');
      expect(bridgeErrorKey(const RpcException('Pausable: paused')), 'bridge.errPausedOnChain');
      expect(bridgeErrorKey(const RpcUnavailableException(2)), 'bridge.errNetwork');
      expect(bridgeErrorKey(const InsufficientGasException()), 'bridge.errGas');
      expect(bridgeErrorKey(const WalletChangedException()), 'send.errWalletChanged');
      expect(bridgeErrorKey(const BridgeCheckException('bridge.errWrongChain')), 'bridge.errWrongChain');
      expect(bridgeErrorKey(Exception('random RPC html blob')), 'bridge.errTxFailed');
    });
  });

  // ══════════════════════ สะพาน wTPIX ══════════════════════

  group('parseTpixAmount / formatTpix', () {
    test('18 ทศนิยมเต็ม ไม่ผ่าน double', () {
      expect(parseTpixAmount('500'), BigInt.from(500) * e18);
      expect(parseTpixAmount('0.000000000000000001'), BigInt.one);
      expect(parseTpixAmount('1,000.5'), b('1000500000000000000000'));
      expect(formatTpix(BigInt.from(499) * e18), '499');
      expect(formatTpix(b('1500000000000000001')), '1.500000000000000001');
    });

    test('เกิน 18 ทศนิยม / เลขเต็มเกิน 15 หลัก / ไม่ใช่ตัวเลข → null', () {
      expect(parseTpixAmount('0.0000000000000000001'), isNull);
      expect(parseTpixAmount('1234567890123456'), isNull);
      for (final bad in ['', '-1', '1e3', 'abc', null]) {
        expect(parseTpixAmount(bad), isNull, reason: '$bad');
      }
    });

    test('ข้อความจาก API: ว่าง/null → null · ตัวเลข → wei', () {
      expect(tpixTextToWei(null), isNull);
      expect(tpixTextToWei(''), isNull);
      expect(tpixTextToWei('100000'), BigInt.from(100000) * e18);
      expect(tpixTextToWei(0), BigInt.zero);
    });

    test('ยอดที่ได้อีกฝั่ง = จำนวน − ค่าธรรมเนียม (ไม่ติดลบ)', () {
      expect(receiveWei(BigInt.from(500) * e18, '1'), BigInt.from(499) * e18);
      expect(receiveWei(BigInt.from(200) * e18, '0'), BigInt.from(200) * e18);
      expect(receiveWei(e18, '1'), BigInt.zero);
    });
  });

  group('checkWtpixAmount', () {
    test('ล็อก 500 ผ่าน (ได้ 499 หลังหักค่าธรรมเนียม 1)', () {
      final r = checkWtpixAmount(BigInt.from(500) * e18, wtpixToBsc, tpixInfo());
      expect(r.error, isNull);
      expect(r.warning, isNull);
    });

    test('ต่ำกว่าขั้นต่ำ 10 TPIX → ห้ามกด', () {
      final r = checkWtpixAmount(BigInt.from(5) * e18, wtpixToBsc, tpixInfo());
      expect(r.error, 'bridge.wtpix.errBelowMin');
      expect(r.params, {'min': '10'});
    });

    test('ล็อกเกิน maxLock บนสัญญา → ห้ามกด (revert แน่นอน)', () {
      final r = checkWtpixAmount(BigInt.from(100001) * e18, wtpixToBsc, tpixInfo());
      expect(r.error, 'bridge.wtpix.errAboveContractMax');
      expect(r.params, {'max': '100000'});
    });

    test('เผาเกินเพดานปล่อยต่อครั้งของคลัง → ห้ามกด (depositId จ่ายได้ครั้งเดียว ปล่อยไม่ได้ตลอดไป)', () {
      final r = checkWtpixAmount(BigInt.from(150000) * e18, wtpixToTpix, tpixInfo());
      expect(r.error, 'bridge.wtpix.errAboveContractMax');
      expect(r.params, {'max': '100000'});
    });

    test('เผา 200 ผ่าน (ค่าธรรมเนียม 0)', () {
      expect(checkWtpixAmount(BigInt.from(200) * e18, wtpixToTpix, tpixInfo()).blocked, isFalse);
    });

    test('ยอดไม่เกินค่าธรรมเนียม → ห้ามกด', () {
      final r = checkWtpixAmount(e18, wtpixToBsc, tpixInfo());
      expect(r.error, 'bridge.wtpix.errFeeTooHigh');
      expect(r.params, {'fee': '1'});
    });

    test('ขั้นต่ำบนสัญญาสูงกว่าวงเงินเว็บ → ใช้ตัวที่สูงกว่า', () {
      final info = tpixInfo();
      (info['vault'] as Map<String, dynamic>)['min_lock'] = '50';
      final r = checkWtpixAmount(BigInt.from(20) * e18, wtpixToBsc, info);
      expect(r.error, 'bridge.wtpix.errBelowMin');
      expect(r.params, {'min': '50'});
    });

    test('เกินวงเงินเว็บแต่ไม่เกินเพดานสัญญา → เตือน (รอทีมงานตรวจ)', () {
      final info = tpixInfo();
      (info['limits'] as Map<String, dynamic>)['max_lock_per_tx'] = '1000';
      final r = checkWtpixAmount(BigInt.from(2000) * e18, wtpixToBsc, info);
      expect(r.error, isNull);
      expect(r.warning, 'bridge.wtpix.warnAboveMax');
      expect(r.warningParams, {'max': '1000'});
    });

    test('ศูนย์ / null → จำนวนไม่ถูกต้อง', () {
      expect(checkWtpixAmount(BigInt.zero, wtpixToBsc, tpixInfo()).error, 'bridge.wtpix.errAmountInvalid');
      expect(checkWtpixAmount(null, wtpixToTpix, tpixInfo()).error, 'bridge.wtpix.errAmountInvalid');
    });
  });

  group('wtpixStateBadge', () {
    test('minted/released จบแล้ว · releasing ยังไม่จบ · ข้อความแยกจากสะพาน USDT', () {
      expect(wtpixStateBadge('released').done, isTrue);
      expect(wtpixStateBadge('released').tone, BridgeTone.success);
      expect(wtpixStateBadge('minted').labelKey, 'bridge.wtpix.state.minted');
      expect(wtpixStateBadge('releasing').done, isFalse);
      expect(wtpixStateBadge('not_a_burn').tone, BridgeTone.danger);
      expect(wtpixStateBadge('not_a_burn').done, isTrue);
    });
  });
}
