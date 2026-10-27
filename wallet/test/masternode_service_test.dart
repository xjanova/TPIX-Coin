/// TPIX Wallet — เทสต์ระบบสเตคมาสเตอร์โหนด (ไม่มี widget)
///
/// สิ่งที่ต้องกันพลาด:
///   - calldata ต้องตรงกับที่ ethers v6 เข้ารหัส (ค่าคาดหวังทั้งหมดในไฟล์นี้ได้จาก ethers จริง
///     ไม่ได้คำนวณด้วยโค้ดของเราเอง — ไม่งั้นบั๊กเดียวกันจะผ่านเทสต์ตัวเอง)
///   - tier ที่ส่งเข้าสัญญา = เลข enum (Guardian=0 … Validator=3) ไม่ใช่ลำดับการ์ดบนจอ
///   - ปุ่มที่กดไม่ได้ต้องมีเหตุผลที่ถูกต้อง (ปิดรับ/เต็ม/ล็อก/กองรางวัลว่าง/ยอดไม่พอ)
///   - เว็บยังไม่มีสัญญา / ที่อยู่ไม่มีโค้ด / เว็บล่ม — แยกออกจากกันชัดเจน
///   - bytecode ของสัญญาต้องตรงกับที่ตรึงไว้ (ไฟล์ test/support/node_registry_v2_026f5f9.hex
///     คือ eth_getCode จริงของ 0x9c36…2A2B — hash ที่คาดหวังคำนวณด้วย ethers.keccak256 ไม่ใช่โค้ดเรา)
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tpix_wallet/services/masternode_service.dart';
import 'package:tpix_wallet/services/rpc_client.dart';
import 'package:web3dart/crypto.dart' show bytesToHex;

// ── ค่าจาก ethers v6.16 (Interface.encodeFunctionData / encodeFunctionResult) ──

const _operator = '0x1234567890abcdef1234567890abcdef12345678';

/// runtime bytecode จริงของ NodeRegistryV2 ที่ deploy แล้ว (TPIX-Coin 026f5f9)
final _liveCode = File('test/support/node_registry_v2_026f5f9.hex').readAsStringSync().trim();

/// ethers.keccak256(_liveCode)
const _liveCodeHash = '0x127979541deea4d4cd468271bea206277d593660634fc78197c5354782c76ce3';

/// สัญญาอื่นที่มีโค้ด (ตอบ ABI เหมือนกันได้ แต่ไม่ใช่ build ที่ตรวจแล้ว)
const _otherCode = '0x6080604052';

/// getNodeInfo → (operator, tier=1, status=1, 100000 TPIX, registeredAt=1760000000,
/// unlockAt=1767776000, lastRewardAt=1760000500, totalRewards=12.5, uptime=9850,
/// nodeId=0xabab…, endpoint="203.0.113.10:8545", rewardDebt=0, pendingUnclaimed=3)
const _nodeRet =
    '0x0000000000000000000000000000000000000000000000000000000000000020'
    '0000000000000000000000001234567890abcdef1234567890abcdef12345678'
    '0000000000000000000000000000000000000000000000000000000000000001'
    '0000000000000000000000000000000000000000000000000000000000000001'
    '00000000000000000000000000000000000000000000152d02c7e14af6800000'
    '0000000000000000000000000000000000000000000000000000000068e77800'
    '00000000000000000000000000000000000000000000000000000000695e1f00'
    '0000000000000000000000000000000000000000000000000000000068e779f4'
    '000000000000000000000000000000000000000000000000ad78ebc5ac620000'
    '000000000000000000000000000000000000000000000000000000000000267a'
    'abababababababababababababababababababababababababababababababab'
    '00000000000000000000000000000000000000000000000000000000000001a0'
    '0000000000000000000000000000000000000000000000000000000000000000'
    '00000000000000000000000000000000000000000000000029a2241af62c0000'
    '0000000000000000000000000000000000000000000000000000000000000011'
    '3230332e302e3131332e31303a38353435000000000000000000000000000000';

/// getNodeInfo ของกระเป๋าที่ไม่เคยลงทะเบียน (ทุกช่องเป็น 0, endpoint = "")
final _emptyNodeRet = '0x${'0' * 62}20'
    '${'0' * 64 * 10}'
    '${'0' * 61}1a0'
    '${'0' * 64 * 2}'
    '${'0' * 64}';

/// getTierInfo → (100000 TPIX, max 500, active 12, lock 90, slash 1000, share 2000)
const _tierRet =
    '0x00000000000000000000000000000000000000000000152d02c7e14af6800000'
    '00000000000000000000000000000000000000000000000000000000000001f4'
    '000000000000000000000000000000000000000000000000000000000000000c'
    '000000000000000000000000000000000000000000000000000000000000005a'
    '00000000000000000000000000000000000000000000000000000000000003e8'
    '00000000000000000000000000000000000000000000000000000000000007d0';

final _tpix = BigInt.from(10).pow(18);
BigInt _t(int n) => BigInt.from(n) * _tpix;

String _hex(List<int> b) => bytesToHex(b, include0x: true);

// ── ตัวช่วยสร้าง snapshot ──

MnTierInfo _tier(
  MnTier tier, {
  BigInt? minStake,
  int maxNodes = 100,
  int active = 0,
  int lockDays = 30,
  int? aprCapBps,
}) =>
    MnTierInfo(
      tier: tier,
      minStake: minStake ?? _t(1000),
      maxNodes: BigInt.from(maxNodes),
      activeNodes: BigInt.from(active),
      lockDays: BigInt.from(lockDays),
      slashPercentBps: BigInt.from(1000),
      rewardShareBps: BigInt.from(2500),
      aprCapBps: aprCapBps,
    );

MnNodeInfo _node({
  MnStatus status = MnStatus.inactive,
  BigInt? staked,
  DateTime? unlock,
  BigInt? pendingUnclaimed,
  int tierId = 0,
}) =>
    MnNodeInfo(
      operator: _operator,
      tierId: tierId,
      status: status,
      stakedAmount: staked ?? BigInt.zero,
      registeredAt: BigInt.zero,
      unlockAt: BigInt.from((unlock ?? DateTime(2020)).millisecondsSinceEpoch ~/ 1000),
      totalRewards: BigInt.zero,
      uptimeBps: BigInt.from(10000),
      endpoint: '',
      pendingUnclaimed: pendingUnclaimed ?? BigInt.zero,
    );

MnSnapshot _snap({
  MnNodeInfo? node,
  List<MnTierInfo>? tiers,
  bool paused = false,
  BigInt? pending,
  BigInt? claimable,
  BigInt? funds,
}) =>
    MnSnapshot(
      registry: '0x00000000000000000000000000000000000000aa',
      owner: _operator,
      registrationPaused: paused,
      tiers: tiers ??
          [
            _tier(MnTier.guardian, minStake: _t(100000)),
            _tier(MnTier.sentinel, minStake: _t(10000)),
            _tier(MnTier.light, minStake: _t(1000)),
            _tier(MnTier.validator, minStake: _t(1000000)),
          ],
      node: node ?? _node(),
      pendingReward: pending ?? BigInt.zero,
      claimableNow: claimable ?? BigInt.zero,
      availableFunds: funds ?? BigInt.zero,
    );

// ── RPC ปลอม ──

String _word(BigInt v) => v.toRadixString(16).padLeft(64, '0');

http.Response _rpcOk(dynamic result) =>
    http.Response(jsonEncode({'jsonrpc': '2.0', 'id': 1, 'result': result}), 200);

http.Response _rpcRevert(String msg) => http.Response(
    jsonEncode({
      'jsonrpc': '2.0',
      'id': 1,
      'error': {'code': 3, 'message': 'execution reverted: $msg'},
    }),
    200);

/// เชนปลอม: ตอบ eth_call ตาม selector — [optionalSupported]=false จำลองสัญญารุ่นเก่า
RpcClient _fakeChain({
  bool optionalSupported = true,
  bool paused = false,
  String? code,
  bool unreachable = false,
}) {
  final mock = MockClient((req) async {
    if (unreachable) throw const SocketException('offline');
    final body = jsonDecode(req.body) as Map<String, dynamic>;
    final method = body['method'] as String;
    final params = body['params'] as List;
    if (method == 'eth_getCode') return _rpcOk(code ?? _liveCode);
    if (method != 'eth_call') return _rpcOk('0x0');
    final data = (params.first as Map)['data'] as String;
    final selector = data.substring(0, 10);
    switch (selector) {
      case '0x7ed85ff3': // getTierInfo(uint8) — minStake ต่างกันตาม tier id
        final id = int.parse(data.substring(data.length - 2), radix: 16);
        final min = [_t(100000), _t(10000), _t(1000), _t(1000000)][id];
        return _rpcOk('0x${_word(min)}${_word(BigInt.from(500))}${_word(BigInt.from(12))}'
            '${_word(BigInt.from(90))}${_word(BigInt.from(1000))}${_word(BigInt.from(2000))}');
      case '0xf8bc005d': // tierAprCapBps(uint8)
        if (!optionalSupported) return _rpcRevert('');
        return _rpcOk('0x${_word(BigInt.from(1200))}');
      case '0x9abbbd3b': // registrationPaused()
        if (!optionalSupported) return _rpcRevert('');
        return _rpcOk('0x${_word(paused ? BigInt.one : BigInt.zero)}');
      case '0x582115fb': // getNodeInfo(address)
        return _rpcOk(_nodeRet);
      case '0xf40f0f52': // pendingReward(address)
        return _rpcOk('0x${_word(_t(3))}');
      case '0x9a78ea4a': // claimableNow(address)
        return _rpcOk('0x${_word(BigInt.zero)}');
      case '0xd0377094': // availableRewardFunds()
        return _rpcOk('0x${_word(BigInt.zero)}');
    }
    return _rpcRevert('unknown selector $selector');
  });
  return RpcClient(['https://rpc.test'], httpClient: mock, timeout: const Duration(seconds: 2));
}

http.Client _configClient(int status, Object body) =>
    MockClient((_) async => http.Response(body is String ? body : jsonEncode(body), status));

Map<String, dynamic> _config({
  String address = '0x00000000000000000000000000000000000000aa',
  bool live = true,
  int chainId = 4289,
  bool paused = false,
}) =>
    {
      'success': true,
      'data': {
        'registry_address': address,
        'registry_live': live,
        'kyc_contract': '',
        'registration_paused': paused,
        'chain_id': chainId,
        'rpc_url': 'https://rpc.evil.example',
        'explorer_url': 'https://explorer.tpix.online',
      },
    };

void main() {
  tearDown(() {
    RpcClient.overrideForChain(4289, null);
    MasterNodeService.clientFactory = http.Client.new;
    MasterNodeService.resetVerifiedRegistries();
  });

  group('ABI encode (เทียบกับ ethers)', () {
    test('ฟังก์ชันไม่มีพารามิเตอร์ = selector ล้วน', () {
      expect(_hex(MasterNodeService.encodeClaim()), '0x372500ab');
      expect(_hex(MasterNodeService.encodeDeregister()), '0x18b1c081');
      expect(_hex(MasterNodeService.encodeWithdrawSlashed()), '0x5698d04d');
    });

    test('tier enum ตรงกับสัญญา — ไม่ใช่ลำดับการ์ด', () {
      expect(MnTier.guardian.id, 0);
      expect(MnTier.sentinel.id, 1);
      expect(MnTier.light.id, 2);
      expect(MnTier.validator.id, 3);

      // การ์ดเรียงตามสเตค (Light ก่อน) — ลำดับแสดงผลเท่านั้น ไม่ใช่เลข enum
      final order = _snap().displayTiers.map((t) => t.tier).toList();
      expect(order, [MnTier.light, MnTier.sentinel, MnTier.guardian, MnTier.validator]);
    });

    test('แอปไม่มีโค้ดสร้าง registerNode — สมัครที่เว็บเท่านั้น', () {
      final src = File('lib/services/masternode_service.dart').readAsStringSync();
      expect(src.contains("_fn('registerNode')"), isFalse);
      final screen = File('lib/screens/masternode_screen.dart').readAsStringSync();
      expect(screen.contains('encodeRegister'), isFalse);
    });
  });

  group('ABI decode (ข้อมูลจาก ethers)', () {
    test('getNodeInfo — tuple ที่มี string อยู่ข้างใน', () {
      final n = MasterNodeService.decodeNodeInfo(_nodeRet);
      expect(n.operator.toLowerCase(), _operator);
      expect(n.tier, MnTier.sentinel);
      expect(n.status, MnStatus.active);
      expect(n.stakedAmount, _t(100000));
      expect(n.registeredAt, BigInt.from(1760000000));
      expect(n.unlockAt, BigInt.from(1767776000));
      expect(n.totalRewards, BigInt.parse('12500000000000000000'));
      expect(n.uptimeBps, BigInt.from(9850));
      expect(n.endpoint, '203.0.113.10:8545');
      expect(n.pendingUnclaimed, _t(3));
      expect(n.unlockTime, DateTime.fromMillisecondsSinceEpoch(1767776000 * 1000));
    });

    test('getNodeInfo ของกระเป๋าที่ไม่เคยลงทะเบียน → inactive ทุกค่าเป็น 0', () {
      final n = MasterNodeService.decodeNodeInfo(_emptyNodeRet);
      expect(n.status, MnStatus.inactive);
      expect(n.stakedAmount, BigInt.zero);
      expect(n.endpoint, '');
    });

    test('getTierInfo — tuple แบบคงที่', () {
      final t = MasterNodeService.decodeTierInfo(MnTier.light, _tierRet, aprCapBps: 600);
      expect(t.minStake, _t(100000));
      expect(t.maxNodes, BigInt.from(500));
      expect(t.activeNodes, BigInt.from(12));
      expect(t.lockDays, BigInt.from(90));
      expect(t.slashPercentBps, BigInt.from(1000));
      expect(t.rewardShareBps, BigInt.from(2000));
      expect(t.aprCapBps, 600);
    });

    test('"0x" (ไม่มีโค้ด/ไม่มีฟังก์ชัน) → MnContractMismatchException ไม่ใช่ RangeError', () {
      expect(() => MasterNodeService.decodeNodeInfo('0x'),
          throwsA(isA<MnContractMismatchException>()));
      expect(() => MasterNodeService.decodeUint('pendingReward', null),
          throwsA(isA<MnContractMismatchException>()));
      expect(() => MasterNodeService.decodeTierInfo(MnTier.light, '0x1234'),
          throwsA(isA<MnContractMismatchException>()));
    });

    test('สถานะที่แอปไม่รู้จัก → unknown (ปิดทุกปุ่ม)', () {
      expect(MnStatus.fromId(4), MnStatus.slashedWithdrawable);
      expect(MnStatus.fromId(9), MnStatus.unknown);
      expect(MnStatus.fromId(-1), MnStatus.unknown);
    });

    test('unlockAt เพี้ยนเกินช่วง DateTime → ไม่ throw', () {
      final n = MnNodeInfo(
        operator: _operator,
        tierId: 0,
        status: MnStatus.active,
        stakedAmount: BigInt.one,
        registeredAt: BigInt.zero,
        unlockAt: BigInt.two.pow(255),
        totalRewards: BigInt.zero,
        uptimeBps: BigInt.zero,
        endpoint: '',
        pendingUnclaimed: BigInt.zero,
      );
      expect(n.unlockTime.isAfter(DateTime(3000)), isTrue);
    });
  });

  group('ปุ่มสเตค (registerBlock)', () {
    final enough = _t(200000);

    test('ปกติ + ยอดพอ → กดได้', () {
      expect(_snap().registerBlock(MnTier.light, enough), isNull);
    });

    test('Validator ต้อง KYC → ไปเว็บเสมอ', () {
      expect(_snap().registerBlock(MnTier.validator, _t(10000000)),
          MnBlock.validatorWebsiteOnly);
    });

    test('ปิดรับลงทะเบียน', () {
      expect(_snap(paused: true).registerBlock(MnTier.light, enough), MnBlock.paused);
    });

    test('ระดับเต็ม (maxNodes > 0 และ active ถึงเพดาน)', () {
      final s = _snap(tiers: [
        _tier(MnTier.guardian),
        _tier(MnTier.sentinel),
        _tier(MnTier.light, maxNodes: 5, active: 5),
        _tier(MnTier.validator),
      ]);
      expect(s.registerBlock(MnTier.light, enough), MnBlock.full);
    });

    test('maxNodes = 0 คือไม่จำกัด ไม่ใช่เต็ม', () {
      final s = _snap(tiers: [
        _tier(MnTier.guardian),
        _tier(MnTier.sentinel),
        _tier(MnTier.light, maxNodes: 0, active: 9999),
        _tier(MnTier.validator),
      ]);
      expect(s.tierInfo(MnTier.light).isUnlimited, isTrue);
      expect(s.registerBlock(MnTier.light, enough), isNull);
    });

    test('minStake = 0 = ระดับยังไม่ตั้งค่า', () {
      final s = _snap(tiers: [
        _tier(MnTier.guardian, minStake: BigInt.zero),
        _tier(MnTier.sentinel),
        _tier(MnTier.light),
        _tier(MnTier.validator),
      ]);
      expect(s.registerBlock(MnTier.guardian, enough), MnBlock.unavailable);
    });

    test('มีโหนดอยู่แล้ว (active/slashed) → สเตคเพิ่มไม่ได้', () {
      expect(_snap(node: _node(status: MnStatus.active)).registerBlock(MnTier.light, enough),
          MnBlock.hasNode);
      expect(_snap(node: _node(status: MnStatus.slashed)).registerBlock(MnTier.light, enough),
          MnBlock.hasNode);
    });

    test('ถอนแล้วแต่ยังมีรางวัลค้าง + กองจ่ายได้ → ต้องรับก่อน (สัญญาเช็ก pendingUnclaimed)', () {
      final s = _snap(
          node: _node(pendingUnclaimed: _t(5)), pending: _t(5), claimable: _t(2), funds: _t(2));
      expect(s.registerBlock(MnTier.light, enough), MnBlock.claimFirst);
      expect(s.claimBlock(), isNull, reason: 'ปุ่มรับรางวัลต้องกดได้ ไม่งั้นติดตาย');
    });

    test('ถอนแล้วแต่ยังมีรางวัลค้าง + กองว่าง → บอกให้รอเติมกอง ไม่ใช่ "รับก่อน"', () {
      final s = _snap(node: _node(pendingUnclaimed: _t(5)), pending: _t(5));
      expect(s.registerBlock(MnTier.light, enough), MnBlock.restakeWaitsForPool);
      // claimRewards() ตอนกองว่างไม่ revert แต่ไม่จ่ายอะไร → ปุ่มรับปิดไว้ (ไม่ส่งธุรกรรมเปล่า)
      expect(s.claimBlock(), MnBlock.poolEmpty);
      expect(s.pendingRewardBlock, MnBlock.restakeWaitsForPool);
    });

    test('ยังไม่รู้ยอด / ยอดไม่พอ (ขาดแค่ 1 wei ก็ไม่ได้)', () {
      expect(_snap().registerBlock(MnTier.light, null), MnBlock.balanceUnknown);
      expect(_snap().registerBlock(MnTier.light, _t(1000) - BigInt.one),
          MnBlock.insufficientBalance);
      // ค่าแก๊ส 0 → ยอดเท่ากับ minStake พอดีก็พอ
      expect(_snap().registerBlock(MnTier.light, _t(1000)), isNull);
    });
  });

  group('ปุ่มรับรางวัล / ถอน', () {
    test('มีให้รับ → กดได้', () {
      expect(_snap(pending: _t(5), claimable: _t(5)).claimBlock(), isNull);
    });

    test('รางวัลสะสมแต่กองว่าง → poolEmpty (รางวัลไม่หาย)', () {
      expect(_snap(pending: _t(5), claimable: BigInt.zero).claimBlock(), MnBlock.poolEmpty);
    });

    test('ยังไม่มีรางวัล', () {
      expect(_snap().claimBlock(), MnBlock.nothingToClaim);
    });

    test('ถอนสเตค: ยังล็อก / พ้นล็อก / ไม่ active', () {
      final now = DateTime(2026, 10, 11);
      final locked = _snap(
          node: _node(status: MnStatus.active, unlock: now.add(const Duration(days: 1))));
      expect(locked.unstakeBlock(now), MnBlock.locked);
      final free = _snap(
          node: _node(status: MnStatus.active, unlock: now.subtract(const Duration(seconds: 1))));
      expect(free.unstakeBlock(now), isNull);
      expect(_snap(node: _node(status: MnStatus.slashed)).unstakeBlock(now), MnBlock.notActive);
    });

    test('ถอนสเตคที่เหลือหลังโดนปรับ — เฉพาะสถานะ Slashed (สัญญา require status == Slashed)', () {
      expect(_snap(node: _node(status: MnStatus.slashed, staked: _t(900))).canWithdrawSlashed,
          isTrue);
      expect(
          _snap(node: _node(status: MnStatus.slashedWithdrawable, staked: _t(900)))
              .canWithdrawSlashed,
          isFalse,
          reason: 'withdrawSlashedStake() จะ revert "Not slashed"');
      expect(_snap(node: _node(status: MnStatus.slashed, staked: BigInt.zero)).canWithdrawSlashed,
          isFalse);
      expect(_snap(node: _node(status: MnStatus.active, staked: _t(900))).canWithdrawSlashed,
          isFalse);
    });

    test('ถอนตอนกองจ่ายไม่ครบ → รู้ล่วงหน้าว่าจะเหลือรางวัลค้างเท่าไร', () {
      final active = _node(status: MnStatus.active);
      expect(_snap(node: active, pending: _t(5)).unpaidAfterExit, _t(5));
      expect(_snap(node: active, pending: _t(5), claimable: _t(2)).unpaidAfterExit, _t(3));
      expect(_snap(node: active, pending: _t(5), claimable: _t(5)).unpaidAfterExit, BigInt.zero);
      expect(_snap(node: active).unpaidAfterExit, BigInt.zero);
    });

    test('ยังมีโหนด active → ไม่ใช่เรื่องรางวัลค้าง (hasNode มาก่อน)', () {
      final s = _snap(
          node: _node(status: MnStatus.active, pendingUnclaimed: _t(5)), pending: _t(5));
      expect(s.pendingRewardBlock, isNull);
      expect(s.registerBlock(MnTier.light, _t(200000)), MnBlock.hasNode);
    });

    test('ไล่ตามสัญญา: ถอนตอนกองว่าง → รอเติมกอง → รับรางวัล → สเตคใหม่ได้', () {
      final enough = _t(200000);
      // 1) หลัง deregisterNode ตอนกองว่าง: status=Inactive, pendingUnclaimed=5
      final exited = _snap(node: _node(pendingUnclaimed: _t(5)), pending: _t(5));
      expect(exited.claimBlock(), MnBlock.poolEmpty);
      expect(exited.registerBlock(MnTier.light, enough), MnBlock.restakeWaitsForPool);

      // 2) มีคนเติมกอง 10 → claimableNow = min(5, 10) = 5 → ปุ่มรับรางวัลกดได้
      final funded = _snap(
          node: _node(pendingUnclaimed: _t(5)), pending: _t(5), claimable: _t(5), funds: _t(10));
      expect(funded.claimBlock(), isNull);
      expect(funded.registerBlock(MnTier.light, enough), MnBlock.claimFirst);

      // 3) รับครบแล้ว pendingUnclaimed = 0 → สเตคใหม่ได้
      final cleared = _snap(funds: _t(5));
      expect(cleared.registerBlock(MnTier.light, enough), isNull);
    });

    test('การ์ดโหนดของฉัน: มีโหนด หรือมีรางวัลค้าง', () {
      expect(_snap().hasNodeCard, isFalse);
      expect(_snap(node: _node(status: MnStatus.active)).hasNodeCard, isTrue);
      expect(_snap(pending: BigInt.one).hasNodeCard, isTrue);
    });
  });

  group('กองรางวัลว่าง — ห้ามโชว์ APR เหมือนจะได้จ่าย', () {
    List<MnTierInfo> withApr() => [
          _tier(MnTier.guardian, minStake: _t(100000), aprCapBps: 1200),
          _tier(MnTier.sentinel, minStake: _t(10000), aprCapBps: 900),
          _tier(MnTier.light, minStake: _t(1000), aprCapBps: 600),
          _tier(MnTier.validator, minStake: _t(1000000), aprCapBps: 2000),
        ];

    test('กองว่าง (0) → ไม่มี APR ให้โชว์ทุกระดับ แต่ขั้นต่ำ/ระยะล็อกยังอยู่', () {
      final s = _snap(tiers: withApr(), funds: BigInt.zero);
      expect(s.poolFunded, isFalse);
      for (final t in MnTier.values) {
        expect(s.aprCapToShow(t), isNull, reason: t.label);
      }
      expect(s.tierInfo(MnTier.light).minStake, _t(1000));
      expect(s.tierInfo(MnTier.light).lockDays, BigInt.from(30));
      // สเตคได้ตามปกติ — แค่ต้องรู้ว่ายังไม่มีรางวัลจ่ายจริง
      expect(s.registerBlock(MnTier.light, _t(200000)), isNull);
    });

    test('กองมีเงิน (แม้ 1 wei) → โชว์เพดาน APR ของระดับนั้น', () {
      final s = _snap(tiers: withApr(), funds: BigInt.one);
      expect(s.poolFunded, isTrue);
      expect(s.aprCapToShow(MnTier.guardian), 1200);
      expect(s.aprCapToShow(MnTier.light), 600);
    });

    test('สัญญาไม่มีเพดาน APR → ไม่โชว์ แม้กองมีเงิน', () {
      final s = _snap(funds: _t(1000));
      expect(s.poolFunded, isTrue);
      expect(s.aprCapToShow(MnTier.light), isNull);
    });
  });

  group('ข้อความ revert → เหตุผล', () {
    final cases = <String, MnRevert>{
      'execution reverted: Registration paused': MnRevert.paused,
      'execution reverted: Tier full': MnRevert.full,
      'execution reverted: Still locked': MnRevert.locked,
      'execution reverted: KYC not approved': MnRevert.kyc,
      'execution reverted: Insufficient stake': MnRevert.stakeMismatch,
      'execution reverted: Stake must equal tier minimum': MnRevert.stakeMismatch,
      'execution reverted: Already registered': MnRevert.alreadyRegistered,
      'execution reverted: Claim pending rewards first': MnRevert.claimFirst,
      'execution reverted: Endpoint too long': MnRevert.endpoint,
      'execution reverted: Not active': MnRevert.stateChanged,
      'insufficient funds for gas * price + value': MnRevert.insufficientFunds,
      'execution reverted': MnRevert.unknown,
    };
    cases.forEach((msg, expected) {
      test(msg, () => expect(MasterNodeService.classifyRevert(msg), expected));
    });
  });

  group('ตัวเลข', () {
    test('formatTpix: ใส่จุลภาค ตัดทศนิยมไม่ปัดขึ้น', () {
      expect(MasterNodeService.formatTpix(_t(1000000)), '1,000,000');
      expect(MasterNodeService.formatTpix(BigInt.parse('1234567899999999999999')),
          '1,234.5678');
      expect(MasterNodeService.formatTpix(BigInt.zero), '0');
      expect(MasterNodeService.formatTpix(BigInt.one, maxDecimals: 18), '0.000000000000000001');
      expect(MasterNodeService.formatTpix(BigInt.one), '0');
    });

    test('formatBps', () {
      expect(MasterNodeService.formatBps(1200), '12%');
      expect(MasterNodeService.formatBps(1250), '12.5%');
      expect(MasterNodeService.formatBps(9850), '98.5%');
      expect(MasterNodeService.formatBps(5), '0.05%');
    });

    test('gasLimit = max(ประเมิน×1.3 ปัดขึ้น, พื้น)', () {
      expect(MasterNodeService.gasLimit(367423, 600000), 600000);
      expect(MasterNodeService.gasLimit(500000, 600000), 650000);
      expect(MasterNodeService.gasLimit(158170, MasterNodeService.gasFloorClaim), 250000);
      expect(MasterNodeService.gasLimit(1000001, 0), 1300002);
    });
  });

  group('ตรึง bytecode ของสัญญา', () {
    const registry = '0x9c3662972921705FeFa9E9bF0d91190d7B514A2B';

    /// เชนปลอมที่นับจำนวนครั้งที่ถาม eth_getCode
    RpcClient countingChain(List<int> calls, http.Response Function() respond) => RpcClient(
          ['https://rpc.test'],
          timeout: const Duration(seconds: 2),
          httpClient: MockClient((req) async {
            final method = (jsonDecode(req.body) as Map)['method'];
            if (method == 'eth_getCode') calls.add(1);
            return respond();
          }),
        );

    test('keccak256 ของโค้ดจริงตรงกับค่าจาก ethers และอยู่ในรายการที่ตรึงไว้', () {
      expect(MasterNodeService.codeHash(_liveCode), _liveCodeHash);
      expect(MasterNodeService.knownRegistryCodeHashes, contains(_liveCodeHash));
      expect(MasterNodeService.isKnownRegistryCode(_liveCode), isTrue);
      // ตัวพิมพ์ใหญ่ใน hex ไม่ทำให้ hash เปลี่ยน
      expect(MasterNodeService.isKnownRegistryCode('0x${_liveCode.substring(2).toUpperCase()}'),
          isTrue);
    });

    test('build ที่จะ redeploy อยู่ในรายการ · build ที่ยังโดนแทรก slash 50% ก่อนสมัครถูกตัดออก', () {
      // ฝั่งสัญญา (contracts/test/NodeRegistryV2.test.js) เทียบ hash นี้กับที่ compile ได้จริงทุกรอบ
      expect(MasterNodeService.knownRegistryCodeHashes,
          contains('0x1c49f5e7661539977d5abfef5a268b66bcaf812735b67b20328af002a70816fb'));
      for (final superseded in [
        '0x8e14ff731f16f502264211c48cc47595f02a4016724f69b67d679c42758765a0',
        '0x7a03e6425a6779dfa0f60ba80ee569635f0618a22906a631dda2abdf28e696bf',
        '0x35a1f6779f2e6941581c4d84c8def53cd42544cdf49fc0a2b9cffb60471329f6',
      ]) {
        expect(MasterNodeService.knownRegistryCodeHashes, isNot(contains(superseded)));
      }
    });

    test('แก้แค่ไบต์เดียว / ไม่มีโค้ด / ไม่ใช่ hex → ไม่รู้จัก', () {
      final last = _liveCode.substring(_liveCode.length - 2);
      final tampered =
          '${_liveCode.substring(0, _liveCode.length - 2)}${last == '00' ? '01' : '00'}';
      expect(MasterNodeService.isKnownRegistryCode(tampered), isFalse);
      expect(MasterNodeService.isKnownRegistryCode(_otherCode), isFalse);
      expect(MasterNodeService.isKnownRegistryCode('0x'), isFalse);
      expect(MasterNodeService.isKnownRegistryCode('0x123'), isFalse);
      expect(MasterNodeService.isKnownRegistryCode('0xzz'), isFalse);
      expect(MasterNodeService.isKnownRegistryCode(null), isFalse);
    });

    test('ก่อนเขียน: ตรง → ผ่าน และจำไว้ (ครั้งต่อไปไม่ยิง RPC ซ้ำ)', () async {
      final calls = <int>[];
      RpcClient.overrideForChain(4289, countingChain(calls, () => _rpcOk(_liveCode)));
      await MasterNodeService.verifyRegistryCode(registry);
      await MasterNodeService.verifyRegistryCode(registry.toLowerCase());
      expect(calls, hasLength(1));
    });

    test('ก่อนเขียน: bytecode ไม่ตรง → MnUnknownCodeException และไม่จำว่าผ่าน', () async {
      final calls = <int>[];
      RpcClient.overrideForChain(4289, countingChain(calls, () => _rpcOk(_otherCode)));
      await expectLater(MasterNodeService.verifyRegistryCode(registry),
          throwsA(isA<MnUnknownCodeException>()));
      await expectLater(MasterNodeService.verifyRegistryCode(registry),
          throwsA(isA<MnUnknownCodeException>()));
      expect(calls, hasLength(2));
    });

    test('ก่อนเขียน: RPC ล่ม → MnUnavailableException (ไม่ถือว่าผ่าน) แล้วตรวจใหม่รอบหน้า',
        () async {
      RpcClient.overrideForChain(4289, _fakeChain(unreachable: true));
      await expectLater(MasterNodeService.verifyRegistryCode(registry),
          throwsA(isA<MnUnavailableException>()));
      // เน็ตกลับมา → ตรวจจริงแล้วผ่าน
      RpcClient.overrideForChain(4289, _fakeChain());
      await MasterNodeService.verifyRegistryCode(registry);
    });

    test('ก่อนเขียน: ที่อยู่ไม่มีโค้ด ("0x" / polygon-edge "unable to fetch code") → ไม่ผ่าน',
        () async {
      RpcClient.overrideForChain(4289, _fakeChain(code: '0x'));
      await expectLater(MasterNodeService.verifyRegistryCode(registry),
          throwsA(isA<MnContractMismatchException>()));
      RpcClient.overrideForChain(
        4289,
        countingChain(
            [],
            () => http.Response(
                jsonEncode({
                  'jsonrpc': '2.0',
                  'id': 1,
                  'error': {'code': -32600, 'message': 'unable to fetch code'},
                }),
                200)),
      );
      await expectLater(MasterNodeService.verifyRegistryCode(registry),
          throwsA(isA<MnContractMismatchException>()));
    });

    test('discover ผ่านแล้ว → ด่านก่อนเขียนใช้ผลที่จำไว้ ไม่ยิง RPC เพิ่ม', () async {
      MasterNodeService.clientFactory = () => _configClient(200, _config(address: registry));
      final calls = <int>[];
      RpcClient.overrideForChain(4289, countingChain(calls, () => _rpcOk(_liveCode)));
      expect((await MasterNodeService.discover()).availability, MnAvailability.ready);
      await MasterNodeService.verifyRegistryCode(registry);
      expect(calls, hasLength(1));
    });
  });

  group('กันโอนเข้าสัญญาสเตคตรงๆ (หน้าโอน)', () {
    const live = '0x9c3662972921705FeFa9E9bF0d91190d7B514A2B';

    RpcClient countingChain(List<int> calls, http.Response Function() respond) => RpcClient(
          ['https://rpc.test'],
          timeout: const Duration(seconds: 2),
          httpClient: MockClient((_) async {
            calls.add(1);
            return respond();
          }),
        );

    test('ที่อยู่ที่ deploy จริง — ตัวพิมพ์ไหนก็จับได้ ไม่ต้องยิงเน็ต', () async {
      final calls = <int>[];
      RpcClient.overrideForChain(4289, countingChain(calls, () => _rpcOk('0x')));
      expect(MasterNodeService.isKnownRegistryAddress(live), isTrue);
      expect(MasterNodeService.isKnownRegistryAddress(live.toLowerCase()), isTrue);
      expect(MasterNodeService.isKnownRegistryAddress(' ${live.toUpperCase().replaceFirst('0X', '0x')} '),
          isTrue);
      expect(await MasterNodeService.isRegistryRecipient(live), isTrue);
      expect(calls, isEmpty);
    });

    test('ที่อยู่ที่ discover ตรวจผ่านในรอบนี้ → นับเป็นสัญญาสเตคด้วย', () async {
      const other = '0x00000000000000000000000000000000000000aa';
      expect(MasterNodeService.isKnownRegistryAddress(other), isFalse);
      MasterNodeService.clientFactory = () => _configClient(200, _config(address: other));
      RpcClient.overrideForChain(4289, _fakeChain());
      expect((await MasterNodeService.discover()).availability, MnAvailability.ready);
      expect(MasterNodeService.isKnownRegistryAddress(other), isTrue);
    });

    test('ที่อยู่ไม่รู้จักแต่โค้ดเป็น NodeRegistryV2 (redeploy) → บล็อก', () async {
      RpcClient.overrideForChain(4289, _fakeChain());
      expect(await MasterNodeService.isRegistryRecipient(_operator), isTrue);
    });

    test('กระเป๋าธรรมดา / สัญญาอื่น / เน็ตล่ม → ไม่บล็อก', () async {
      // polygon-edge: กระเป๋าที่มียอดตอบ error แทน "0x"
      RpcClient.overrideForChain(
        4289,
        countingChain(
            [],
            () => http.Response(
                jsonEncode({
                  'jsonrpc': '2.0',
                  'id': 1,
                  'error': {'code': -32600, 'message': 'unable to fetch code'},
                }),
                200)),
      );
      expect(await MasterNodeService.isRegistryRecipient(_operator), isFalse);
      RpcClient.overrideForChain(4289, _fakeChain(code: '0x'));
      expect(await MasterNodeService.isRegistryRecipient(_operator), isFalse);
      RpcClient.overrideForChain(4289, _fakeChain(code: _otherCode));
      expect(await MasterNodeService.isRegistryRecipient(_operator), isFalse);
      RpcClient.overrideForChain(4289, _fakeChain(unreachable: true));
      expect(await MasterNodeService.isRegistryRecipient(_operator), isFalse);
    });
  });

  group('ค้นหาสัญญา (discover)', () {
    test('เว็บยังไม่มี endpoint (404) → ยังไม่เปิด', () async {
      MasterNodeService.clientFactory = () => _configClient(404, '<html>Not Found</html>');
      final r = await MasterNodeService.discover();
      expect(r.availability, MnAvailability.notDeployed);
    });

    test('registry_address ว่าง / registry_live=false → ยังไม่เปิด', () async {
      MasterNodeService.clientFactory = () => _configClient(200, _config(address: ''));
      expect((await MasterNodeService.discover()).availability, MnAvailability.notDeployed);
      MasterNodeService.clientFactory = () => _configClient(200, _config(live: false));
      expect((await MasterNodeService.discover()).availability, MnAvailability.notDeployed);
    });

    test('เว็บบอกเชนอื่น → unverified (ห้ามเขียน)', () async {
      MasterNodeService.clientFactory = () => _configClient(200, _config(chainId: 56));
      RpcClient.overrideForChain(4289, _fakeChain());
      expect((await MasterNodeService.discover()).availability, MnAvailability.unverified);
    });

    test('ที่อยู่ไม่มีโค้ดบนเชน → unverified', () async {
      MasterNodeService.clientFactory = () => _configClient(200, _config());
      RpcClient.overrideForChain(4289, _fakeChain(code: '0x'));
      expect((await MasterNodeService.discover()).availability, MnAvailability.unverified);
    });

    test('polygon-edge: EOA ที่มียอดตอบ error "unable to fetch code" → unverified ไม่ใช่ RPC ล่ม',
        () async {
      MasterNodeService.clientFactory = () => _configClient(200, _config());
      RpcClient.overrideForChain(
        4289,
        RpcClient(['https://rpc.test'],
            httpClient: MockClient((_) async => http.Response(
                jsonEncode({
                  'jsonrpc': '2.0',
                  'id': 1,
                  'error': {'code': -32600, 'message': 'unable to fetch code'},
                }),
                200))),
      );
      expect((await MasterNodeService.discover()).availability, MnAvailability.unverified);
    });

    test('bytecode ตรงกับที่ตรึงไว้ → ready (ใช้ RPC ของแอป ไม่ใช่ rpc_url จากเว็บ)', () async {
      final seenHosts = <String>[];
      MasterNodeService.clientFactory = () => _configClient(200, _config());
      RpcClient.overrideForChain(
        4289,
        RpcClient(['https://rpc.test'],
            httpClient: MockClient((req) async {
              seenHosts.add(req.url.host);
              return _rpcOk(_liveCode);
            })),
      );
      final r = await MasterNodeService.discover();
      expect(r.availability, MnAvailability.ready);
      expect(r.address, '0x00000000000000000000000000000000000000aa');
      expect(seenHosts, isNotEmpty);
      expect(seenHosts, everyElement('rpc.test'));
    });

    test('มีโค้ดแต่ไม่ใช่ build ที่ตรวจแล้ว → unknownCode (ห้ามเขียน ให้อัปเดตแอป)', () async {
      MasterNodeService.clientFactory = () => _configClient(200, _config());
      RpcClient.overrideForChain(4289, _fakeChain(code: _otherCode));
      final r = await MasterNodeService.discover();
      expect(r.availability, MnAvailability.unknownCode);
      expect(r.address, isNull);
    });

    test('Cloudflare ตอบ HTML 200 / 5xx / เน็ตหลุด → MnUnavailableException (ให้ลองใหม่)',
        () async {
      MasterNodeService.clientFactory = () => _configClient(200, '<!DOCTYPE html><html></html>');
      await expectLater(MasterNodeService.discover(), throwsA(isA<MnUnavailableException>()));
      MasterNodeService.clientFactory = () => _configClient(503, 'down');
      await expectLater(MasterNodeService.discover(), throwsA(isA<MnUnavailableException>()));
      MasterNodeService.clientFactory =
          () => MockClient((_) async => throw const SocketException('offline'));
      await expectLater(MasterNodeService.discover(), throwsA(isA<MnUnavailableException>()));
    });

    test('config ดี แต่ RPC ติดต่อไม่ได้ → MnUnavailableException', () async {
      MasterNodeService.clientFactory = () => _configClient(200, _config());
      RpcClient.overrideForChain(4289, _fakeChain(unreachable: true));
      await expectLater(MasterNodeService.discover(), throwsA(isA<MnUnavailableException>()));
    });
  });

  group('โหลด snapshot', () {
    test('อ่านครบทุกฟังก์ชัน + กองรางวัลว่าง → poolEmpty', () async {
      RpcClient.overrideForChain(4289, _fakeChain(paused: true));
      final s = await MasterNodeService.loadSnapshot(
        registry: '0x00000000000000000000000000000000000000aa',
        owner: _operator,
      );
      expect(s.registrationPaused, isTrue);
      expect(s.tierInfo(MnTier.guardian).minStake, _t(100000));
      expect(s.tierInfo(MnTier.light).minStake, _t(1000));
      expect(s.tierInfo(MnTier.light).aprCapBps, 1200);
      expect(s.node.status, MnStatus.active);
      expect(s.pendingReward, _t(3));
      expect(s.claimBlock(), MnBlock.poolEmpty);
      // availableRewardFunds = 0 → สัญญามีเพดาน 12% แต่ห้ามโชว์
      expect(s.poolFunded, isFalse);
      expect(s.aprCapToShow(MnTier.light), isNull);
    });

    test('สัญญารุ่นเก่า (ไม่มี registrationPaused/tierAprCapBps) → ใช้ค่าจากเว็บ ไม่พังทั้งหน้า',
        () async {
      RpcClient.overrideForChain(4289, _fakeChain(optionalSupported: false));
      final s = await MasterNodeService.loadSnapshot(
        registry: '0x00000000000000000000000000000000000000aa',
        owner: _operator,
        configPaused: true,
      );
      expect(s.registrationPaused, isTrue);
      expect(s.tierInfo(MnTier.light).aprCapBps, isNull);
    });

    test('RPC ล่ม → MnUnavailableException', () async {
      RpcClient.overrideForChain(4289, _fakeChain(unreachable: true));
      await expectLater(
        MasterNodeService.loadSnapshot(
          registry: '0x00000000000000000000000000000000000000aa',
          owner: _operator,
        ),
        throwsA(isA<MnUnavailableException>()),
      );
    });
  });

  test('ข้อความทุกตัวที่หน้ามาสเตอร์โหนดใช้ มีทั้งไทยและอังกฤษ', () {
    final locale = File('lib/core/locale_provider.dart').readAsStringSync();
    final screen = File('lib/screens/masternode_screen.dart').readAsStringSync();
    final keys = <String>{
      ...RegExp(r"'(mn\.[A-Za-z.]+)'").allMatches(screen).map((m) => m.group(1)!),
      // คีย์ที่ประกอบจากชื่อ enum
      for (final b in MnBlock.values) 'mn.block.${b.name}',
      for (final r in MnRevert.values)
        if (r != MnRevert.unknown) 'mn.revert.${r.name}',
      for (final s in MnStatus.values) 'mn.status.${s.name}',
    };
    final missing = <String>[];
    for (final k in keys) {
      final n = RegExp("'${RegExp.escape(k)}':").allMatches(locale).length;
      if (n != 2) missing.add('$k (พบ $n ครั้ง ต้องมี th + en = 2)');
    }
    expect(missing, isEmpty, reason: missing.join('\n'));
  });
}
