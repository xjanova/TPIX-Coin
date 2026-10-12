/// TPIX Wallet — เทสต์บริการสะพาน (ไม่มี widget, ไม่ยิงเน็ตจริง)
///
/// สิ่งที่ต้องกันพลาด:
///   - calldata ต้องตรงกับที่ ethers v6.17 เข้ารหัส (ค่าคาดหวังได้จาก ethers จริง ไม่ได้คำนวณด้วยโค้ดเรา)
///   - fail-closed: เว็บบอกเปิดแต่ที่อยู่สัญญาไม่ครบ/ผิดรูป/เชนไม่ตรง = ไม่เปิดฟอร์ม
///   - ด่านก่อนเซ็น: chain id ของ RPC · ทศนิยมจริงของโทเค็น · ยอด · จำลองธุรกรรม · แก๊ส
///   - ส่งจริงผ่านตัวเซ็นตัวเดียวของแอป (WalletService) ไปเชนที่ถูก + บันทึกประวัติเป็น "USDT"
library;

import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tpix_wallet/models/chain_config.dart';
import 'package:tpix_wallet/services/bridge_rules.dart';
import 'package:tpix_wallet/services/bridge_service.dart';
import 'package:tpix_wallet/services/db_service.dart';
import 'package:tpix_wallet/services/rpc_client.dart';
import 'package:tpix_wallet/services/wallet_service.dart';
import 'package:web3dart/crypto.dart' show bytesToHex;

import 'support/fake_rpc.dart';
import 'support/isolated_db.dart';

// ── ค่าจาก ethers v6.17 (Interface.encodeFunctionData) ──
const _refBridgeBurn25To56 =
    '0x9f434051'
    '00000000000000000000000000000000000000000000000000000000017d7840'
    '0000000000000000000000000000000000000000000000000000000000000038'
    '0000000000000000000000000000000000000000000000000000000000000060'
    '000000000000000000000000000000000000000000000000000000000000002a'
    '3078663436313331433832383139643736323131363346343832623366653838'
    '6132323841373830376300000000000000000000000000000000000000000000';
const _refBridgeBurn2_5To42161 =
    '0x9f434051'
    '00000000000000000000000000000000000000000000000000000000002625a0'
    '000000000000000000000000000000000000000000000000000000000000a4b1'
    '0000000000000000000000000000000000000000000000000000000000000060'
    '000000000000000000000000000000000000000000000000000000000000002a'
    '3078313131313131313131313131313131313131313131313131313131313131'
    '3131313131313131313100000000000000000000000000000000000000000000';
const _refTransferBsc =
    '0xa9059cbb'
    '000000000000000000000000f46131c82819d7621163f482b3fe88a228a7807c'
    '000000000000000000000000000000000000000000000000ab54a8bb155ae000';
const _refBurn200 = '0x42966c6800000000000000000000000000000000000000000000000ad78ebc5ac6200000';

const _vault = '0xf46131c82819d7621163f482b3fe88a228a7807c';
const _usdtTpix = '0x0a4ee87551ef041f3eecfbbfdcffc1b46a4878f1';
const _bscUsdt = '0x55d398326f99059fF775485246999027B3197955';
const _owner = '0x1111111111111111111111111111111111111111';
final _e18 = BigInt.from(10).pow(18);

Map<String, dynamic> usdtPayload({
  bool enabled = true,
  Object? vault = _vault,
  int tpixChainId = 4289,
  Object? usdtTpix = _usdtTpix,
  int usdtDecimals = 6,
  List<Map<String, dynamic>>? chains,
}) =>
    {
      'enabled': enabled,
      'installed': true,
      'vault_address': vault,
      'tpix': {'chain_id': tpixChainId, 'usdt_tpix': usdtTpix, 'usdt_decimals': usdtDecimals, 'explorer': 'https://explorer.tpix.online'},
      'chains': chains ??
          [
            {'chain_id': 56, 'name': 'BNB Smart Chain', 'native': 'BNB', 'enabled': true, 'usdt_address': _bscUsdt, 'usdt_decimals': 18, 'usdt_symbol': 'USDT', 'explorer': 'https://bscscan.com', 'withdraw_fee': '0.3', 'eta_minutes': 2},
            {'chain_id': 42161, 'name': 'Arbitrum One', 'native': 'ETH', 'enabled': true, 'usdt_address': '0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9', 'usdt_decimals': 6, 'usdt_symbol': 'USD₮0', 'explorer': 'https://arbiscan.io', 'withdraw_fee': '0.3', 'eta_minutes': 20},
          ],
      'limits': {'min_deposit': '1', 'max_deposit_per_tx': '1000', 'min_withdraw': '2', 'max_withdraw_per_tx': '1000'},
    };

Map<String, dynamic> wtpixPayload({bool enabled = true, int bscChainId = 56, Object? minter = '0x7a17000000000000000000000000000000000003', int decimals = 18}) => {
      'asset': 'tpix',
      'enabled': enabled,
      'installed': true,
      'tpix': {'chain_id': 4289, 'name': 'TPIX Chain', 'vault_address': '0x7a17000000000000000000000000000000000001', 'explorer': 'https://explorer.tpix.online', 'rpc': 'https://evil.test', 'eta_minutes': 3},
      'bsc': {'chain_id': bscChainId, 'name': 'BNB Smart Chain', 'wtpix_address': '0x7a17000000000000000000000000000000000002', 'minter_address': minter, 'explorer': 'https://bscscan.com', 'rpc': 'https://evil.test', 'eta_minutes': 2},
      'token': {'symbol': 'wTPIX', 'decimals': decimals, 'logo': 'https://tpix.online/images/brand/tpix-coin.png?v=2'},
      'limits': {'min_lock': '10', 'max_lock_per_tx': '100000', 'lock_fee': '1', 'min_burn': '10', 'max_burn_per_tx': '100000', 'burn_fee': '0'},
      'vault': {'min_lock': '10', 'max_lock': '100000', 'max_per_tx': '100000', 'daily_cap': '500000', 'remaining_today': '500000', 'paused': false},
      'minter': {'max_per_tx': '100000', 'daily_cap': '500000', 'remaining_today': '500000', 'paused': false},
    };

/// RPC ของ BSC ที่ทุกอย่างผ่าน — แก้ทีละช่องในแต่ละเทสต์
Map<String, FakeRpcHandler> bscHappy({
  String chainId = '0x38',
  int decimals = 18,
  BigInt? tokenBalance,
  BigInt? nativeBalance,
  Object? Function(List<dynamic>)? estimate,
}) =>
    {
      'eth_chainId': (_) => chainId,
      'eth_call': FakeRpc.ethCall({
        selDecimals: (to, data) => abiUint(BigInt.from(decimals)),
        selBalanceOf: (to, data) => abiUint(tokenBalance ?? BigInt.from(100) * _e18),
      }),
      'eth_estimateGas': estimate ?? (_) => '0xc350', // 50,000
      'eth_gasPrice': (_) => hexQty(BigInt.from(1000000000)), // 1 gwei
      'eth_getBalance': (_) => hexQty(nativeBalance ?? _e18),
    };

/// คำตอบ JSON แบบที่เว็บส่ง (UTF-8)
http.Response jsonResponse(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: const {'content-type': 'application/json; charset=utf-8'});

void main() {
  group('ABI (เทียบกับ ethers v6.17)', () {
    test('bridgeBurn(uint256,uint256,string) — ที่อยู่ปลายทางเป็นสตริงตามที่พิมพ์', () {
      expect(bytesToHex(BridgeTx.encodeBridgeBurn(BigInt.from(25000000), 56, '0xf46131C82819d7621163F482b3fe88a228A7807c'), include0x: true),
          _refBridgeBurn25To56);
      expect(bytesToHex(BridgeTx.encodeBridgeBurn(BigInt.from(2500000), 42161, _owner), include0x: true), _refBridgeBurn2_5To42161);
    });

    test('transfer(vault, 12.345678 USDT บน BSC = 18 ทศนิยม)', () {
      expect(bytesToHex(BridgeTx.encodeTransfer(_vault, BigInt.parse('12345678000000000000')), include0x: true), _refTransferBsc);
    });

    test('lock() และ burn(200 wTPIX)', () {
      expect(bytesToHex(BridgeTx.encodeLock(), include0x: true), '0xf83d08ba');
      expect(bytesToHex(BridgeTx.encodeBurn(BigInt.from(200) * _e18), include0x: true), _refBurn200);
    });
  });

  group('UsdtBridgeInfo — fail-closed', () {
    test('เว็บเปิด + ที่อยู่ครบ → เปิดฟอร์ม · เชน BSC 18 ทศนิยม ฝากได้', () {
      final info = UsdtBridgeInfo.fromServer(usdtPayload());
      expect(info.open, isTrue);
      final bsc = info.chain(56)!;
      expect(bsc.usdtDecimals, 18);
      expect(bsc.depositable, isTrue);
      expect(bsc.withdrawable, isTrue);
      expect(info.chain(42161)!.depositable, isTrue, reason: 'Arbitrum มี RPC ตรึงในแอป');
    });

    test('เว็บปิด → ไม่เปิด แม้ที่อยู่ครบ', () {
      expect(UsdtBridgeInfo.fromServer(usdtPayload(enabled: false)).open, isFalse);
    });

    test('เว็บบอกเปิด แต่ vault ศูนย์/ผิด checksum/หาย → ไม่เปิด', () {
      for (final bad in ['0x0000000000000000000000000000000000000000', '0xF46131C82819d7621163F482b3fe88a228A7807c', '', null, 42]) {
        expect(UsdtBridgeInfo.fromServer(usdtPayload(vault: bad)).open, isFalse, reason: '$bad');
      }
      expect(UsdtBridgeInfo.fromServer(usdtPayload(usdtTpix: null)).open, isFalse);
    });

    test('เชน TPIX ไม่ใช่ 4289 หรือ USDT_TPIX ไม่ใช่ 6 ทศนิยม → ไม่เปิด', () {
      expect(UsdtBridgeInfo.fromServer(usdtPayload(tpixChainId: 4290)).open, isFalse);
      expect(UsdtBridgeInfo.fromServer(usdtPayload(usdtDecimals: 18)).open, isFalse);
    });

    test('เชนที่แอปไม่รู้จัก / สัญญาผิดรูป / ค่าธรรมเนียมอ่านไม่ออก → เลือกไม่ได้ (เชนอื่นยังใช้ได้)', () {
      final info = UsdtBridgeInfo.fromServer(usdtPayload(chains: [
        {'chain_id': 999, 'name': 'Unknown', 'enabled': true, 'usdt_address': _bscUsdt, 'usdt_decimals': 6, 'withdraw_fee': '0.3'},
        {'chain_id': 56, 'name': 'BSC', 'enabled': true, 'usdt_address': '0x55D398326f99059fF775485246999027B3197955', 'usdt_decimals': 18, 'withdraw_fee': '0.3'},
        {'chain_id': 1, 'name': 'Ethereum', 'enabled': true, 'usdt_address': '0xdAC17F958D2ee523a2206206994597C13D831ec7', 'usdt_decimals': 6, 'withdraw_fee': 'abc'},
      ]));
      expect(info.open, isTrue);
      expect(info.chain(999)!.appSupported, isFalse);
      expect(info.chain(999)!.depositable, isFalse);
      expect(info.chain(56)!.depositable, isFalse, reason: 'checksum ผิด = ห้ามใช้');
      expect(info.chain(1)!.depositable, isTrue);
      expect(info.chain(1)!.withdrawable, isFalse, reason: 'ค่าธรรมเนียมอ่านไม่ออก ห้ามเดาเป็น 0');
    });
  });

  group('WtpixBridgeInfo — fail-closed', () {
    test('ครบ → เปิด และไม่ใช้ RPC ที่เว็บส่งมา', () {
      final info = WtpixBridgeInfo.fromServer(wtpixPayload());
      expect(info.open, isTrue);
      expect(info.bscChainId, 56);
      expect(info.vault['max_per_tx'], '100000');
    });

    test('BSC ไม่ใช่ 56 (เช่น testnet 97) / ไม่มีตัว mint / ทศนิยมไม่ใช่ 18 / เว็บปิด → ไม่เปิด', () {
      expect(WtpixBridgeInfo.fromServer(wtpixPayload(bscChainId: 97)).open, isFalse);
      expect(WtpixBridgeInfo.fromServer(wtpixPayload(minter: null)).open, isFalse);
      expect(WtpixBridgeInfo.fromServer(wtpixPayload(decimals: 6)).open, isFalse);
      expect(WtpixBridgeInfo.fromServer(wtpixPayload(enabled: false)).open, isFalse);
    });
  });

  group('BridgeService — HTTP', () {
    final requests = <http.Request>[];
    late http.Response Function(http.Request) respond;

    setUp(() {
      requests.clear();
      BridgeService.clientFactory = () => MockClient((req) async {
            requests.add(req);
            return respond(req);
          });
    });

    tearDown(() => BridgeService.clientFactory = http.Client.new);

    test('info ของสะพาน USDT / wTPIX (asset=tpix) + มี User-Agent (Cloudflare)', () async {
      respond = (req) =>
          jsonResponse({'success': true, 'data': req.url.queryParameters['asset'] == 'tpix' ? wtpixPayload() : usdtPayload()});
      expect((await BridgeService.fetchUsdtInfo()).open, isTrue);
      expect((await BridgeService.fetchWtpixInfo()).open, isTrue);
      expect(requests[0].url.toString(), 'https://tpix.online/api/v1/bridge/info');
      expect(requests[1].url.toString(), 'https://tpix.online/api/v1/bridge/info?asset=tpix');
      expect(requests[0].headers['User-Agent'], isNotEmpty);
    });

    test('หน้า HTML / success=false / 5xx → BridgeUnavailableException · 429 → จำกัดความถี่', () async {
      respond = (_) => http.Response('<!DOCTYPE html><html></html>', 200);
      await expectLater(BridgeService.fetchUsdtInfo(), throwsA(isA<BridgeUnavailableException>()));
      respond = (_) => jsonResponse({'success': false, 'error': {'code': 'X'}});
      await expectLater(BridgeService.fetchUsdtInfo(), throwsA(isA<BridgeUnavailableException>()));
      respond = (_) => http.Response('down', 503);
      await expectLater(BridgeService.fetchUsdtInfo(), throwsA(isA<BridgeUnavailableException>()));
      respond = (_) => http.Response('slow down', 429);
      await expectLater(
          BridgeService.fetchStatus(wtpix: false, chainId: 56, txHash: '0x${'a' * 64}'), throwsA(isA<BridgeRateLimitedException>()));
    });

    test('สถานะ: ฝาก = /status/{chain}/{hash} · ถอน = /withdrawals/{hash} · wTPIX = asset=tpix', () async {
      respond = (_) => jsonResponse({'success': true, 'data': {'state': 'confirming', 'amount': '25', 'confirmations': 3}});
      final hash = '0x${'AB' * 32}';
      final s = await BridgeService.fetchStatus(wtpix: false, chainId: 56, txHash: hash);
      await BridgeService.fetchWithdrawal(hash);
      await BridgeService.fetchStatus(wtpix: true, chainId: 4289, txHash: hash);
      expect(s.state, 'confirming');
      expect(s.confirmations, 3);
      expect(requests[0].url.path, '/api/v1/bridge/status/56/0x${'ab' * 32}');
      expect(requests[1].url.path, '/api/v1/bridge/withdrawals/0x${'ab' * 32}');
      expect(requests[2].url.toString(), 'https://tpix.online/api/v1/bridge/status/4289/0x${'ab' * 32}?asset=tpix');
    });

    test('hash ผิดรูป → ไม่ยิงเน็ตเลย', () async {
      respond = (_) => http.Response('{}', 200);
      await expectLater(BridgeService.fetchWithdrawal('0x123'), throwsA(isA<BridgeUnavailableException>()));
      expect(requests, isEmpty);
    });

    test('ประวัติ USDT: แปลงชื่อสถานะในตารางเป็นสถานะสาธารณะ', () async {
      respond = (_) => jsonResponse({
            'success': true,
            'data': {
              'deposits': [
                {'source_chain_id': 56, 'amount': '25', 'status': 'needs_review', 'tx_hash': '0x${'a' * 64}'},
              ],
              'withdrawals': [
                {'target_chain_id': 1, 'amount': '10', 'status': 'ignored', 'tx_hash': '0x${'b' * 64}'},
              ],
            }
          });
      final rows = await BridgeService.fetchUsdtHistory(_owner);
      expect(rows.map((r) => (r.kind, r.state, r.chainId, r.amount)), [
        (usdtDeposit, 'review', 56, '25'),
        (usdtWithdraw, 'below_fee', 1, '10'),
      ]);
    });
  });

  group('BridgeTx.prepare — ด่านก่อนเซ็น (ยังไม่มีอะไรถูกส่ง)', () {
    tearDown(() {
      RpcClient.overrideForChain(56, null);
      RpcClient.overrideForChain(4289, null);
      BridgeChains.overrideExtraRpc(42161, null);
    });

    Future<BridgeTxPlan> prepareDeposit({BigInt? amount}) => BridgeTx.prepare(
          chainId: 56,
          from: _owner,
          to: _bscUsdt,
          data: BridgeTx.encodeTransfer(_vault, amount ?? BigInt.from(25) * _e18),
          spend: (token: _bscUsdt, amount: amount ?? BigInt.from(25) * _e18, decimals: 18),
        );

    test('ผ่านครบ → แผนพร้อมเซ็น: แก๊สเผื่อ 20% · ราคาแก๊สจริง · RPC ของเชนนั้น', () async {
      final rpc = FakeRpc(bscHappy());
      RpcClient.overrideForChain(56, rpc.client);
      final plan = await prepareDeposit();
      expect(plan.chainId, 56);
      expect(plan.to, _bscUsdt);
      expect(plan.gasLimit, 60000);
      expect(plan.gasPrice, BigInt.from(1000000000));
      expect(plan.rpcUrl, ChainConfig.bsc.rpcUrl);
      expect(plan.nativeSymbol, 'BNB');
      expect(rpc.calls.first, 'eth_chainId', reason: 'ตรวจเชนก่อนทุกอย่าง');
      expect(rpc.calls, isNot(contains('eth_sendRawTransaction')));
    });

    test('RPC ตอบเป็นเชนอื่น → ยกเลิก', () async {
      RpcClient.overrideForChain(56, FakeRpc(bscHappy(chainId: '0x1')).client);
      await expectLater(prepareDeposit(), throwsA(isA<BridgeCheckException>().having((e) => e.key, 'key', 'bridge.errWrongChain')));
    });

    test('ทศนิยมจริงของโทเค็นไม่ตรงกับที่เว็บบอก → ยกเลิก (กันส่งผิดหลักเป็นล้านเท่า)', () async {
      RpcClient.overrideForChain(56, FakeRpc(bscHappy(decimals: 6)).client);
      await expectLater(prepareDeposit(), throwsA(isA<BridgeCheckException>().having((e) => e.key, 'key', 'bridge.errTokenMismatch')));
    });

    test('ยอดโทเค็นไม่พอ → ยกเลิก', () async {
      RpcClient.overrideForChain(56, FakeRpc(bscHappy(tokenBalance: BigInt.from(24) * _e18)).client);
      await expectLater(prepareDeposit(), throwsA(isA<BridgeCheckException>().having((e) => e.key, 'key', 'bridge.errInsufficient')));
    });

    test('สัญญาจะ revert → บอกก่อนถาม PIN · หยุดอยู่ (paused) แยกข้อความ', () async {
      RpcClient.overrideForChain(56, FakeRpc(bscHappy(estimate: (_) => throw const FakeRpcError('execution reverted'))).client);
      await expectLater(prepareDeposit(), throwsA(isA<BridgeCheckException>().having((e) => e.key, 'key', 'bridge.errWouldRevert')));
      RpcClient.overrideForChain(56, FakeRpc(bscHappy(estimate: (_) => throw const FakeRpcError('execution reverted: Pausable: paused'))).client);
      await expectLater(prepareDeposit(), throwsA(isA<BridgeCheckException>().having((e) => e.key, 'key', 'bridge.errPausedOnChain')));
    });

    test('BNB ไม่พอค่าแก๊ส → บอกจำนวนที่ต้องมี', () async {
      RpcClient.overrideForChain(56, FakeRpc(bscHappy(nativeBalance: BigInt.from(1000))).client);
      await expectLater(
        prepareDeposit(),
        throwsA(isA<BridgeCheckException>()
            .having((e) => e.key, 'key', 'bridge.errGasNeed')
            .having((e) => e.params, 'params', {'amount': '0.00006', 'symbol': 'BNB'})),
      );
    });

    test('ล็อกบนเชน TPIX: ไม่มีค่าแก๊ส (ไม่ถามราคาแก๊ส) แต่ตรวจยอด TPIX ที่แนบ', () async {
      final rpc = FakeRpc({
        'eth_chainId': (_) => '0x10c1',
        'eth_getBalance': (_) => hexQty(BigInt.from(1000) * _e18),
        'eth_estimateGas': (_) => '0x7530', // 30,000
      });
      RpcClient.overrideForChain(4289, rpc.client);
      final plan = await BridgeTx.prepare(
        chainId: 4289,
        from: _owner,
        to: '0x7a17000000000000000000000000000000000001',
        data: BridgeTx.encodeLock(),
        value: BigInt.from(500) * _e18,
      );
      expect(plan.gasPrice, BigInt.zero);
      expect(plan.value, BigInt.from(500) * _e18);
      expect(rpc.calls, isNot(contains('eth_gasPrice')));
      final estimate = rpc.params[rpc.calls.indexOf('eth_estimateGas')].first as Map;
      expect(estimate['value'], hexQty(BigInt.from(500) * _e18));
      expect(estimate['data'], '0xf83d08ba');

      await expectLater(
        BridgeTx.prepare(chainId: 4289, from: _owner, to: '0x7a17000000000000000000000000000000000001', data: BridgeTx.encodeLock(), value: BigInt.from(5000) * _e18),
        throwsA(isA<BridgeCheckException>().having((e) => e.key, 'key', 'bridge.errInsufficient')),
      );
    });

    test('เชนที่แอปไม่รู้จัก → ไม่เซ็น', () async {
      await expectLater(
        BridgeTx.prepare(chainId: 999, from: _owner, to: _bscUsdt, data: BridgeTx.encodeLock()),
        throwsA(isA<BridgeCheckException>().having((e) => e.key, 'key', 'bridge.errChainUnsupported')),
      );
    });

    test('เชนนอก ChainConfig (Arbitrum) ใช้ RPC ที่ตรึงในแอป และส่งด้วยตัวที่เพิ่งตอบ chain id ถูก', () async {
      final rpc = FakeRpc({
        ...bscHappy(chainId: '0xa4b1', decimals: 6, tokenBalance: BigInt.from(100000000)),
      });
      BridgeChains.overrideExtraRpc(42161, rpc.client);
      final plan = await BridgeTx.prepare(
        chainId: 42161,
        from: _owner,
        to: '0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9',
        data: BridgeTx.encodeTransfer(_vault, BigInt.from(25000000)),
        spend: (token: '0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9', amount: BigInt.from(25000000), decimals: 6),
      );
      expect(plan.rpcUrl, 'https://rpc.fake.test');
      expect(plan.nativeSymbol, 'ETH');
    });
  });

  group('ส่งจริงผ่านตัวเซ็นของแอป', () {
    setUpAll(() => useIsolatedTestDb('bridge_service'));

    tearDown(() => RpcClient.overrideForChain(56, null));

    test('ฝาก USDT บน BSC: ส่งไปเชน 56 ที่สัญญา USDT ด้วย calldata transfer(vault) + ประวัติโชว์ "25 USDT"', () async {
      FlutterSecureStorage.setMockInitialValues({});
      final wallet = WalletService();
      final from = await wallet.importFromPrivateKey('0x${'4c' * 32}');
      final units = BigInt.from(25) * _e18;
      final data = BridgeTx.encodeTransfer(_vault, units);
      String? raw;
      final rpc = FakeRpc({
        ...bscHappy(),
        'eth_getTransactionCount': (_) => '0x7',
        'eth_sendRawTransaction': (p) {
          raw = p.first as String;
          return '0x${'cd' * 32}';
        },
      });
      RpcClient.overrideForChain(56, rpc.client);

      final hash = await wallet.sendEvmTransaction(
        rpcUrl: ChainConfig.bsc.rpcUrl,
        chainId: 56,
        toAddress: _bscUsdt,
        data: data,
        maxGas: 60000,
        expectedFrom: from,
        historyAs: (to: _vault, value: units, tokenAddress: _bscUsdt, symbol: 'USDT', decimals: 18),
      );

      expect(hash, '0x${'cd' * 32}');
      expect(rpc.calls, isNot(contains('eth_estimateGas')), reason: 'ใช้แก๊สจากด่านตรวจ');
      expect(raw, isNotNull);
      expect(raw!.toLowerCase(), contains(_bscUsdt.substring(2).toLowerCase()));
      expect(raw!.toLowerCase(), contains(bytesToHex(data)));

      final rows = await DbService.getTxForSlot(wallet.activeSlot);
      final row = rows.firstWhere((r) => r.txHash == hash);
      expect(row.symbol, 'USDT');
      expect(row.toAddress, _vault);
      expect(row.value, units.toString());
      expect(row.decimals, 18);
    });

    test('กระเป๋าถูกสลับระหว่างยืนยัน → ไม่เซ็น ไม่ส่ง', () async {
      FlutterSecureStorage.setMockInitialValues({});
      final wallet = WalletService();
      await wallet.importFromPrivateKey('0x${'5d' * 32}');
      final rpc = FakeRpc(bscHappy());
      RpcClient.overrideForChain(56, rpc.client);
      await expectLater(
        wallet.sendEvmTransaction(
          rpcUrl: ChainConfig.bsc.rpcUrl,
          chainId: 56,
          toAddress: _bscUsdt,
          data: BridgeTx.encodeTransfer(_vault, BigInt.one),
          maxGas: 60000,
          expectedFrom: _owner,
        ),
        throwsA(isA<WalletChangedException>()),
      );
      expect(rpc.calls, isNot(contains('eth_sendRawTransaction')));
    });
  });
}
