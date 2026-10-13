/// TPIX Wallet — เทสต์ TpixDexService (สวอปบนเชน TPIX ผ่าน TPIX DEX)
///
/// สิ่งที่ห้ามพัง:
///   - ที่อยู่สัญญามาจาก /dex/config เท่านั้น · ไม่พร้อม/ผิดเชน/ผิดรูป = ปิด (fail-closed)
///   - รายการเหรียญ: TPIX ต้องเป็นเนทีฟ · USDT ต้องตรงทะเบียน · ไม่มี WTPIX · ชื่อซ้ำ = ตัดทิ้ง
///   - decimals ยืนยันกับเชนเสมอ · ยอดอ่านไม่ได้ = null (ไม่ใช่ 0)
///   - คณิต BigInt: impact เพดาน 10% แบบเศษส่วนตรง · minOut จาก slippage bps แบบเว็บ
///   - TPIX เนทีฟวิ่งเป็น WTPIX · TPIX ↔ WTPIX ไม่ใช่สวอป
///   - calldata: approve เท่ายอดพอดี · swapExactETHForTokens แนบ value · minOut ผูกกับ quote
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:tpix_wallet/models/chain_config.dart';
import 'package:tpix_wallet/services/rpc_client.dart';
import 'package:tpix_wallet/services/tpix_dex_service.dart';
import 'package:web3dart/crypto.dart' show bytesToHex;

import 'support/fake_dex.dart';

const _zero = '0x0000000000000000000000000000000000000000';
final _owner = '0x${'4c' * 20}';

Matcher _dexError(TpixDexError code) =>
    throwsA(isA<TpixDexException>().having((e) => e.code, 'code', code));

void main() {
  late FakeDexSite site;
  late FakeDexChain chain;

  setUp(() {
    TpixDexService.resetCache();
    site = FakeDexSite();
    chain = FakeDexChain();
    TpixDexService.clientFactory = site.client;
    RpcClient.overrideForChain(4289, chain.rpc.client);
  });

  tearDown(() {
    TpixDexService.clientFactory = http.Client.new;
    RpcClient.overrideForChain(4289, null);
  });

  group('ทะเบียน /dex/config (fail-closed)', () {
    test('ready + ที่อยู่ครบ → ใช้ได้ (ที่อยู่เป็นตัวพิมพ์เล็กทั้งหมด)', () async {
      site.config = dexConfig(router: '0x${'A1' * 20}');
      final cfg = await TpixDexService.loadConfig();
      expect(cfg.usable, isTrue);
      expect(cfg.router, dexRouter);
      expect(cfg.wtpix, dexWtpix);
      expect(cfg.chainId, 4289);
    });

    for (final c in <String, Map<String, dynamic>>{
      'ready = false': dexConfig(ready: false),
      'chainId ไม่ใช่ 4289': dexConfig(chainId: 56),
      'router ผิดรูป': dexConfig(router: '0x1234'),
      'router เป็นศูนย์': dexConfig(router: _zero),
      'WTPIX ไม่มี': dexConfig()..remove('WTPIX'),
      'router = WTPIX': dexConfig(router: dexWtpix),
    }.entries) {
      test('${c.key} → ปิดโหมด TPIX (ไม่เดาที่อยู่)', () async {
        site.config = c.value;
        final market = await TpixDexService.loadMarket();
        expect(market.config.usable, isFalse);
        expect(market.available, isFalse);
        expect(chain.calls, isEmpty, reason: 'ทะเบียนไม่พร้อม = ไม่แตะเชนเลย');
      });
    }

    test('เว็บตอบ HTML (Cloudflare) และไม่เคยโหลดได้ → unreachable', () async {
      site.down = true;
      await expectLater(TpixDexService.loadConfig(), _dexError(TpixDexError.unreachable));
    });

    test('เคยโหลดได้แล้วเว็บล่ม → ใช้ค่าล่าสุด · เว็บบอกไม่พร้อม → ปิดทันที', () async {
      expect((await TpixDexService.loadConfig()).usable, isTrue);
      site.down = true;
      expect((await TpixDexService.loadConfig(force: true)).usable, isTrue);
      site.down = false;
      site.config = dexConfig(ready: false);
      expect((await TpixDexService.loadConfig(force: true)).usable, isFalse);
    });

    test('แคช 60 วิ + คำขอซ้อนกันยิงเว็บครั้งเดียว', () async {
      await Future.wait([TpixDexService.loadConfig(), TpixDexService.loadConfig()]);
      await TpixDexService.loadConfig();
      expect(site.configCalls, 1);
    });
  });

  group('รายการเหรียญจาก /dex/pairs', () {
    final cfg = TpixDexConfig.fromJson(dexConfig());

    String body(List<Map<String, dynamic>> pairs) => jsonEncode({'success': true, 'data': pairs});

    test('คู่จริงวันนี้ → TPIX (เนทีฟ) ตัวแรก ตามด้วย USDT ของทะเบียน', () {
      final tokens = TpixDexService.parseTokens(body(livePairs()), cfg)!;
      expect(tokens.map((t) => t.symbol), ['TPIX', 'USDT']);
      expect(tokens.first.isNative, isTrue);
      expect(tokens[1].address, dexUsdt);
      expect(tokens[1].decimals, 6);
    });

    test('USDT ปลอม / WTPIX / TPIX ที่เป็นสัญญา / คู่ปิด / คู่เชนอื่น → ไม่อยู่ในรายการ', () {
      final fakeUsdt = '0x${'99' * 20}';
      final tokens = TpixDexService.parseTokens(
        body([
          ...livePairs(),
          dexPair('USDT', fakeUsdt, 6, 'TPIX', _zero, 18),
          dexPair('WTPIX', dexWtpix, 18, 'USDT', dexUsdt, 6),
          dexPair('WRAPPED', dexWtpix, 18, 'USDT', dexUsdt, 6),
          dexPair('TPIX', '0x${'98' * 20}', 18, 'USDT', dexUsdt, 6),
          dexPair('OFF', '0x${'97' * 20}', 18, 'USDT', dexUsdt, 6, active: false),
          dexPair('BSCX', '0x${'96' * 20}', 18, 'USDT', dexUsdt, 6, chainId: 56),
        ]),
        cfg,
      )!;
      expect(tokens.map((t) => t.symbol), ['TPIX', 'USDT']);
      expect(tokens.map((t) => t.address), isNot(contains(fakeUsdt)));
    });

    test('ชื่อซ้ำคนละที่อยู่ → ตัดทิ้งทั้งคู่ (ผู้ใช้แยกไม่ออก) · เหรียญอื่นที่ถูกต้องอยู่ต่อ', () {
      final tokens = TpixDexService.parseTokens(
        body([
          ...livePairs(),
          dexPair('IDTC', dexToken, 18, 'TPIX', _zero, 18),
          dexPair('DUP', '0x${'95' * 20}', 18, 'USDT', dexUsdt, 6),
          dexPair('DUP', '0x${'94' * 20}', 18, 'USDT', dexUsdt, 6),
        ]),
        cfg,
      )!;
      expect(tokens.map((t) => t.symbol), ['TPIX', 'USDT', 'IDTC']);
    });

    test('body ไม่ใช่คำตอบของ API → null (ให้ไปใช้รายการสำรองจากทะเบียน)', () {
      expect(TpixDexService.parseTokens('<html>Cloudflare</html>', cfg), isNull);
      expect(TpixDexService.parseTokens('{"success":false}', cfg), isNull);
    });

    test('decimals ยืนยันกับเชน: เว็บบอก 18 แต่เชนบอก 6 → ใช้ 6', () async {
      site.pairs = [dexPair('TPIX', _zero, 18, 'USDT', dexUsdt, 18)];
      final market = await TpixDexService.loadMarket();
      expect(market.available, isTrue);
      expect(market.tokens[1].decimals, 6);
    });

    test('เหรียญที่ไม่ใช่สัญญา ERC-20 (decimals revert) → ตัดทิ้ง', () async {
      final ghost = '0x${'93' * 20}';
      site.pairs = [...livePairs(), dexPair('GHOST', ghost, 18, 'USDT', dexUsdt, 6)];
      final market = await TpixDexService.loadMarket();
      expect(market.tokens.map((t) => t.address), isNot(contains(ghost)));
    });

    test('โหลดคู่ไม่ได้ → TPIX + USDT จากทะเบียน (ที่อยู่มาจากเซิร์ฟเวอร์)', () async {
      await TpixDexService.loadConfig();
      site.down = true;
      final market = await TpixDexService.loadMarket();
      expect(market.tokens.map((t) => t.address), [TokenDef.nativeAddress, dexUsdt]);
    });

    test('ติดต่อเชนไม่ได้ตอนยืนยัน decimals → unreachable', () async {
      RpcClient.overrideForChain(4289, RpcClient(['https://rpc.fake.test'], httpClient: _deadHttp()));
      await expectLater(TpixDexService.loadMarket(), _dexError(TpixDexError.unreachable));
    });
  });

  group('คณิต BigInt', () {
    test('amountOutFor = สูตร UniV2 (หัก 0.3%)', () {
      final out = TpixDexMath.amountOutFor(BigInt.from(1000), BigInt.from(1000000), BigInt.from(1000000));
      expect(out, BigInt.from(996)); // 997·1e6·1000 / (1e9 + 997000) = 996.0…
      expect(TpixDexMath.amountOutFor(BigInt.zero, BigInt.one, BigInt.one), BigInt.zero);
    });

    test('impact เพดาน 10% เทียบแบบเศษส่วนตรง: 10% พอดีผ่าน · เกินนิดเดียวไม่ผ่าน', () {
      final r = BigInt.from(1000000);
      // ราคากลาง 1:1 · ได้ 900 จาก 1000 = impact 10% พอดี
      expect(TpixDexMath.exceedsImpact(amountIn: BigInt.from(1000), amountOut: BigInt.from(900), refIn: r, refOut: r), isFalse);
      expect(TpixDexMath.exceedsImpact(amountIn: BigInt.from(1000), amountOut: BigInt.from(899), refIn: r, refOut: r), isTrue);
      expect(TpixDexMath.impactBps(amountIn: BigInt.from(1000), amountOut: BigInt.from(900), refIn: r, refOut: r), 1000);
      // ได้ดีกว่าราคากลาง (ปัดเศษ) = 0 ไม่ติดลบ
      expect(TpixDexMath.impactBps(amountIn: BigInt.from(1000), amountOut: BigInt.from(1001), refIn: r, refOut: r), 0);
    });

    test('minOut = quote × (10000 − round(slippage×100)) / 10000 แบบเว็บ', () {
      final out = BigInt.from(1000000);
      expect(TpixDexMath.minOut(out, 0.5), BigInt.from(995000));
      expect(TpixDexMath.minOut(out, 1), BigInt.from(990000));
      expect(TpixDexMath.minOut(out, 50), BigInt.from(500000));
      expect(() => TpixDexMath.minOut(out, 0), throwsA(isA<TpixDexException>()));
      expect(() => TpixDexMath.minOut(out, 50.01), throwsA(isA<TpixDexException>()));
      expect(() => TpixDexMath.minOut(out, double.nan), throwsA(isA<TpixDexException>()));
    });

    test('maxAmountInForImpact: ยอดที่แนะนำไม่เกินเพดานจริง · มากกว่านั้นเกิน', () {
      final rIn = BigInt.from(1000000) * e18;
      final rOut = BigInt.from(100000) * e6;
      final x = TpixDexMath.maxAmountInForImpact(reserveIn: rIn);
      final out = TpixDexMath.amountOutFor(x, rIn, rOut);
      expect(TpixDexMath.exceedsImpact(amountIn: x, amountOut: out, refIn: rIn, refOut: rOut), isFalse);
      final big = rIn * BigInt.from(12) ~/ BigInt.from(100);
      expect(TpixDexMath.exceedsImpact(amountIn: big, amountOut: TpixDexMath.amountOutFor(big, rIn, rOut), refIn: rIn, refOut: rOut), isTrue);
    });

    test('display ตัดทศนิยม (ปัดลงเสมอ) ไม่ผ่าน double', () {
      expect(TpixDexMath.display(BigInt.parse('123456789'), 6), '123.456789');
      expect(TpixDexMath.display(BigInt.parse('1999999999999999999'), 18, maxFraction: 4), '1.9999');
      expect(TpixDexMath.display(BigInt.parse('100000000000000001'), 18, maxFraction: 4), '0.1');
      expect(TpixDexMath.display(BigInt.from(1), 18, maxFraction: 4), '0');
    });
  });

  group('quote จาก router จริง', () {
    TokenDef usdt() => TokenDef(address: dexUsdt, name: 'Tether USD', symbol: 'USDT', decimals: 6);
    final tpix = ChainConfig.tpix.nativeToken;

    test('TPIX → USDT: เส้นทาง [WTPIX, USDT] · impact จาก reserve · ส่งได้', () async {
      final q = await TpixDexService.quote(from: tpix, to: usdt(), amountIn: BigInt.from(1000) * e18);
      expect(q.path, [dexWtpix, dexUsdt]);
      expect(q.router, dexRouter);
      // 1000 TPIX ที่ราคา 0.1 ≈ 99.6 USDT (หัก 0.3% + ขยับนิดเดียว)
      expect(q.amountOut, BigInt.from(99600698));
      expect(q.impactBps, 40); // 0.3% ค่าพูล + ~0.1% ราคาขยับ (1 − 99.600698/100)
      expect(q.exceedsImpactLimit, isFalse);
      expect(q.sendable, isTrue);
      expect(q.poolFee, BigInt.from(3) * e18);
    });

    test('ไม้ใหญ่ดันราคาเกิน 10% → exceedsImpactLimit + บอกยอดสูงสุดที่สั่งได้', () async {
      final q = await TpixDexService.quote(from: tpix, to: usdt(), amountIn: BigInt.from(200000) * e18);
      expect(q.exceedsImpactLimit, isTrue);
      expect(q.sendable, isFalse);
      final max = q.maxAmountInUnderLimit!;
      expect(max, greaterThan(BigInt.from(100000) * e18));
      expect(max, lessThan(BigInt.from(110000) * e18));
    });

    test('token ↔ token ไม่มีคู่ตรง → วิ่งผ่าน WTPIX · impact จาก quote ก้อนจิ๋ว (ไม่ใช่ 0)', () async {
      chain.addPool(dexToken, dexWtpix, BigInt.from(500000) * e18, BigInt.from(500000) * e18);
      final idtc = TokenDef(address: dexToken, name: 'IDTC', symbol: 'IDTC', decimals: 18);
      final q = await TpixDexService.quote(from: idtc, to: usdt(), amountIn: BigInt.from(100) * e18);
      expect(q.path, [dexToken, dexWtpix, dexUsdt]);
      expect(q.viaWtpix, isTrue);
      expect(q.impactKnown, isTrue);
      expect(q.impactBps, greaterThan(0));
    });

    test('ไม่มีพูล → noLiquidity', () async {
      final idtc = TokenDef(address: dexToken, name: 'IDTC', symbol: 'IDTC', decimals: 18);
      await expectLater(
        TpixDexService.quote(from: idtc, to: usdt(), amountIn: e18),
        _dexError(TpixDexError.noLiquidity),
      );
    });

    test('TPIX ↔ WTPIX = สินทรัพย์เดียวกัน → sameAsset (ไม่ยิง router)', () async {
      final wtpix = TokenDef(address: dexWtpix, name: 'WTPIX', symbol: 'WTPIX', decimals: 18);
      await expectLater(
        TpixDexService.quote(from: tpix, to: wtpix, amountIn: e18),
        _dexError(TpixDexError.sameAsset),
      );
    });

    test('decimals ที่ใช้คิดจำนวนไม่ตรงเชน → tokenUnverified (ไม่ quote ด้วยค่าผิด)', () async {
      final wrong = TokenDef(address: dexUsdt, name: 'Tether USD', symbol: 'USDT', decimals: 18);
      await expectLater(
        TpixDexService.quote(from: wrong, to: tpix, amountIn: e18),
        _dexError(TpixDexError.tokenUnverified),
      );
    });

    test('ทะเบียนไม่พร้อม → notReady (ไม่แตะเชน)', () async {
      site.config = dexConfig(ready: false);
      await expectLater(
        TpixDexService.quote(from: tpix, to: usdt(), amountIn: e18),
        _dexError(TpixDexError.notReady),
      );
      expect(chain.calls, isEmpty);
    });
  });

  group('ธุรกรรม', () {
    TokenDef usdt() => TokenDef(address: dexUsdt, name: 'Tether USD', symbol: 'USDT', decimals: 6);
    final tpix = ChainConfig.tpix.nativeToken;

    test('approve = router + จำนวนของไม้นี้พอดี (ไม่ใช่ไม่จำกัด)', () {
      final amount = BigInt.from(25) * e6;
      final hex = bytesToHex(TpixDexService.approveCalldata(dexRouter, amount), include0x: true);
      expect(hex.substring(0, 10), selApprove);
      expect(hex.substring(10 + 24, 74), dexRouter.substring(2));
      expect(BigInt.parse(hex.substring(74), radix: 16), amount);
      expect(() => TpixDexService.approveCalldata(dexRouter, BigInt.zero), throwsA(isA<TpixDexException>()));
    });

    test('จ่าย TPIX → swapExactETHForTokens แนบ value = จำนวนที่จ่าย · minOut จาก quote', () async {
      final q = await TpixDexService.quote(from: tpix, to: usdt(), amountIn: BigInt.from(1000) * e18);
      final tx = TpixDexService.buildSwapTx(quote: q, slippagePct: 0.5, recipient: _owner);
      final hex = bytesToHex(tx.data, include0x: true);
      expect(tx.to, dexRouter);
      expect(hex.substring(0, 10), selSwapEthForTokens);
      expect(tx.value, BigInt.from(1000) * e18);
      expect(tx.minOut, q.amountOut * BigInt.from(9950) ~/ BigInt.from(10000));
      expect(BigInt.parse(hex.substring(10, 74), radix: 16), tx.minOut);
    });

    test('ได้ TPIX → swapExactTokensForETH ไม่แนบ value', () async {
      final q = await TpixDexService.quote(from: usdt(), to: tpix, amountIn: BigInt.from(10) * e6);
      expect(q.path, [dexUsdt, dexWtpix]);
      final tx = TpixDexService.buildSwapTx(quote: q, slippagePct: 1, recipient: _owner);
      expect(bytesToHex(tx.data, include0x: true).substring(0, 10), selSwapTokensForEth);
      expect(tx.value, isNull);
    });

    test('ด่านสุดท้าย: impact เกิน / วัดไม่ได้ / slippage ผิด → ไม่สร้างธุรกรรม', () async {
      final big = await TpixDexService.quote(from: tpix, to: usdt(), amountIn: BigInt.from(200000) * e18);
      expect(() => TpixDexService.buildSwapTx(quote: big, slippagePct: 0.5, recipient: _owner),
          throwsA(isA<TpixDexException>().having((e) => e.code, 'code', TpixDexError.impactTooHigh)));

      final unknown = TpixDexQuote(
        from: tpix,
        to: usdt(),
        amountIn: e18,
        amountOut: BigInt.from(100000),
        path: [dexWtpix, dexUsdt],
        router: dexRouter,
      );
      expect(() => TpixDexService.buildSwapTx(quote: unknown, slippagePct: 0.5, recipient: _owner),
          throwsA(isA<TpixDexException>().having((e) => e.code, 'code', TpixDexError.impactUnknown)));

      final ok = await TpixDexService.quote(from: tpix, to: usdt(), amountIn: e18);
      expect(() => TpixDexService.buildSwapTx(quote: ok, slippagePct: 0, recipient: _owner),
          throwsA(isA<TpixDexException>().having((e) => e.code, 'code', TpixDexError.badSlippage)));
    });
  });

  group('อ่านเชน', () {
    test('ยอดอ่านไม่ได้ → null ไม่ใช่ 0', () async {
      RpcClient.overrideForChain(4289, RpcClient(['https://rpc.fake.test'], httpClient: _deadHttp()));
      expect(await TpixDexService.balanceOf(ChainConfig.tpix.nativeToken, _owner), isNull);
    });

    test('RPC ตอบว่าเป็นเชนอื่น → wrongChain (ไม่ส่งธุรกรรม)', () async {
      chain.chainId = 56;
      await expectLater(TpixDexService.verifyChain(), _dexError(TpixDexError.wrongChain));
      chain.chainId = 4289;
      await TpixDexService.verifyChain();
    });
  });
}

/// http ที่ส่งไม่ถึงทุกครั้ง (โหนดล่ม/ถูกบล็อก)
http.Client _deadHttp() => _DeadClient();

class _DeadClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(Stream.value('<html>blocked</html>'.codeUnits), 403);
}
