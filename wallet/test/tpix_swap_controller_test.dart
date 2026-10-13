/// TPIX Wallet — เทสต์ TpixSwapController (สวอปบนเชน TPIX ผ่านตัวเซ็นจริงของแอป)
///
/// สิ่งที่ห้ามพัง:
///   - ธุรกรรมที่เซ็นออกไป: chainId 4289 · gasPrice 0 · ส่งถึง router จากทะเบียน · minOut จาก quote
///   - approve เท่ากับยอดของไม้นี้พอดี แล้วรอยืนยันก่อนให้กดสวอป
///   - บันทึกไม้กับเซิร์ฟเวอร์แบบแอป TRADE: POST /swap/execute · fee 0 · chain_id 4289
///   - ล้มบนเชน = แจ้ง reverted และไม่บันทึก · impact เกิน 10% = ไม่มีอะไรถูกเซ็น
///   - ผล quote ที่มาช้าของจำนวนเก่า ไม่ทับจำนวนใหม่ · สลับกระเป๋า = ล้างยอดเดิมทิ้ง
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tpix_wallet/providers/tpix_swap_controller.dart';
import 'package:tpix_wallet/providers/wallet_provider.dart';
import 'package:tpix_wallet/services/db_service.dart';
import 'package:tpix_wallet/services/rpc_client.dart';
import 'package:tpix_wallet/services/tpix_dex_service.dart';
import 'package:tpix_wallet/services/wallet_auth_service.dart';

import 'support/fake_dex.dart';
import 'support/isolated_db.dart';

const _zero = '0x0000000000000000000000000000000000000000';

/// รอจนเงื่อนไขจริง (งานเบื้องหลังของตัวควบคุมเป็น async จริง ไม่ใช่ fake time)
Future<void> _until(bool Function() cond, {String reason = ''}) async {
  for (var i = 0; i < 400; i++) {
    if (cond()) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('timeout: $reason');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeDexSite site;
  late FakeDexChain chain;
  late WalletProvider wallet;
  late TpixSwapController c;

  setUpAll(() => useIsolatedTestDb('tpix_swap_controller'));

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    TpixDexService.resetCache();
    WalletAuthService.clearSession();
    site = FakeDexSite();
    chain = FakeDexChain();
    TpixDexService.clientFactory = site.client;
    WalletAuthService.clientFactory = site.client;
    RpcClient.overrideForChain(4289, chain.rpc.client);

    wallet = WalletProvider();
    await wallet.importFromPrivateKey('0x${'4c' * 32}');
    c = TpixSwapController(
      wallet: wallet,
      quoteDebounce: Duration.zero,
      pollInterval: const Duration(milliseconds: 1),
      maxPolls: 5,
    );
  });

  tearDown(() {
    c.dispose();
    TpixDexService.clientFactory = http.Client.new;
    WalletAuthService.clientFactory = http.Client.new;
    RpcClient.overrideForChain(4289, null);
  });

  Future<void> ready() async {
    await c.load();
    await _until(() => c.balanceIn != null && !c.loadingBalance, reason: 'balance');
  }

  Future<void> quoted(String amount) async {
    c.setAmount(amount);
    await _until(() => !c.quoting && (c.quote != null || c.quoteError != null), reason: 'quote');
  }

  test('โหลดแล้ว: TPIX → USDT เป็นคู่เริ่มต้น · ยอดอ่านจากเชน TPIX', () async {
    await ready();
    expect(c.phase, TpixSwapPhase.ready);
    expect(c.from!.isNative, isTrue);
    expect(c.to!.address, dexUsdt);
    expect(c.balanceIn, BigInt.from(5000) * e18);
    expect(c.block, TpixSwapBlock.enterAmount);
  });

  test('จ่าย TPIX: เซ็นด้วย chainId 4289 · gasPrice 0 · value = จำนวน · minOut จาก quote + บันทึกไม้ fee 0', () async {
    await ready();
    await quoted('1000');
    expect(c.block, TpixSwapBlock.none);
    final q = c.quote!;

    final result = await c.swap(quote: q, slippagePct: 0.5);
    expect(result, isNotNull);
    expect(result!.confirmed, isTrue);

    expect(chain.rawTxs, hasLength(1));
    final tx = decodeLegacyTx(chain.rawTxs.single);
    expect(tx.chainId, 4289);
    expect(tx.gasPrice, BigInt.zero);
    expect(tx.to, dexRouter);
    expect(tx.value, BigInt.from(1000) * e18);
    expect(tx.selector, selSwapEthForTokens);
    expect(tx.word(0), q.amountOut * BigInt.from(9950) ~/ BigInt.from(10000), reason: 'minOut');
    expect(chain.calls, isNot(contains('eth_gasPrice')), reason: 'เชน TPIX ไม่ถามราคาแก๊ส');
    expect(chain.calls, contains('eth_chainId'), reason: 'ตรวจว่า RPC เป็นเชน 4289 ก่อนเซ็น');

    await _until(() => site.recorded.isNotEmpty, reason: 'record');
    final body = site.recorded.single;
    expect(body['chain_id'], 4289);
    expect(body['fee_amount'], 0);
    expect(body['from_token'], _zero);
    expect(body['to_token'], dexUsdt);
    expect(body['tx_hash'], result.txHash);
    expect(body['wallet_address'], wallet.address!.toLowerCase());
    expect(body['from_amount'], 1000);

    expect(c.amountText, isEmpty, reason: 'สวอปเสร็จล้างจำนวน');
  });

  test('จ่าย USDT: approve เท่ายอดพอดี → รอยืนยัน → swapExactTokensForETH · ประวัติโชว์ "25 USDT"', () async {
    chain.tokenBalances[dexUsdt] = BigInt.from(50) * e6;
    await ready();
    c.flip();
    await _until(() => c.balanceIn != null && !c.loadingBalance, reason: 'usdt balance');
    expect(c.from!.address, dexUsdt);
    await quoted('25');
    expect(c.block, TpixSwapBlock.needsApproval);

    await c.approve();
    final approve = decodeLegacyTx(chain.rawTxs.single);
    expect(approve.to, dexUsdt);
    expect(approve.chainId, 4289);
    expect(approve.gasPrice, BigInt.zero);
    expect(approve.selector, selApprove);
    expect(approve.word(0), BigInt.parse(dexRouter.substring(2), radix: 16));
    expect(approve.word(1), BigInt.from(25) * e6, reason: 'ไม่ใช่ไม่จำกัด');
    expect(c.block, TpixSwapBlock.none);

    final result = await c.swap(quote: c.quote!, slippagePct: 1);
    final swap = decodeLegacyTx(chain.rawTxs.last);
    expect(swap.selector, selSwapTokensForEth);
    expect(swap.value, BigInt.zero);
    expect(swap.word(0), BigInt.from(25) * e6);

    final rows = await DbService.getTxForSlot(wallet.activeSlot);
    final row = rows.firstWhere((r) => r.txHash == result!.txHash);
    expect(row.symbol, 'USDT');
    expect(row.value, (BigInt.from(25) * e6).toString());
    expect(row.decimals, 6);
  });

  test('ล้มบนเชน → reverted และไม่บันทึกกับเซิร์ฟเวอร์', () async {
    chain.receiptStatus = '0x0';
    await ready();
    await quoted('10');
    await expectLater(
      c.swap(quote: c.quote!, slippagePct: 0.5),
      throwsA(isA<TpixDexException>().having((e) => e.code, 'code', TpixDexError.reverted)),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(site.recorded, isEmpty);
    expect(c.swapping, isFalse);
  });

  test('impact เกิน 10% → ปุ่มบล็อก และ swap ไม่เซ็นอะไรเลย', () async {
    chain.nativeBalance = BigInt.from(300000) * e18;
    await ready();
    await quoted('200000');
    expect(c.block, TpixSwapBlock.impactTooHigh);
    await expectLater(
      c.swap(quote: c.quote!, slippagePct: 0.5),
      throwsA(isA<TpixDexException>().having((e) => e.code, 'code', TpixDexError.impactTooHigh)),
    );
    expect(chain.rawTxs, isEmpty);
  });

  test('ยอดไม่พอ / ทศนิยมเกิน / จำนวนผิด → บอกเหตุผลแยกกัน', () async {
    await ready();
    c.setAmount('6000');
    expect(c.block, TpixSwapBlock.insufficient);
    c.flip();
    await _until(() => !c.loadingBalance, reason: 'usdt balance');
    c.setAmount('1.1234567'); // USDT 6 ตำแหน่ง
    expect(c.block, TpixSwapBlock.tooManyDecimals);
    c.setAmount('1.2.3');
    expect(c.block, TpixSwapBlock.invalidAmount);
  });

  test('ผล quote ที่มาช้าของจำนวนเก่าถูกทิ้ง ไม่ทับจำนวนใหม่', () async {
    await ready();
    await quoted('1');
    final stale = c.refreshQuote(); // ยังไม่กลับ
    c.setAmount('2');
    await stale;
    await _until(() => !c.quoting && c.quote != null, reason: 'quote 2');
    expect(c.quote!.amountIn, BigInt.from(2) * e18);
  });

  test('สลับกระเป๋าระหว่างเปิดหน้า → ล้างยอดเดิม แล้วอ่านของใบใหม่', () async {
    await ready();
    final before = wallet.address;
    await wallet.importFromPrivateKey('0x${'5d' * 32}');
    expect(wallet.address, isNot(before));
    expect(c.balanceIn, isNull, reason: 'ยอดของใบเก่าห้ามใช้ต่อ');
    await _until(() => c.balanceIn != null, reason: 'new balance');
    final balanceCalls = chain.rpc.params
        .where((p) => p.isNotEmpty && p.first is String && (p.first as String).toLowerCase() == wallet.address!.toLowerCase());
    expect(balanceCalls, isNotEmpty);
  });

  test('ทะเบียนไม่พร้อม → unavailable · เชนติดต่อไม่ได้ → unreachable', () async {
    site.config = dexConfig(ready: false);
    await c.load();
    expect(c.phase, TpixSwapPhase.unavailable);
    expect(c.block, TpixSwapBlock.enterAmount);

    TpixDexService.resetCache();
    site.config = dexConfig();
    site.down = true;
    await c.load(force: true);
    expect(c.phase, TpixSwapPhase.unreachable);
  });
}
