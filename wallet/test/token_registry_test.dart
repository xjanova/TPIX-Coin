/// TPIX Wallet — เทสต์รายการโทเค็นบน TPIX Chain + โทเค็นที่สัญญาหายหลัง re-genesis
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tpix_wallet/models/chain_config.dart';
import 'package:tpix_wallet/models/token_info.dart';
import 'package:tpix_wallet/services/db_service.dart';
import 'package:tpix_wallet/services/rpc_client.dart';
import 'package:tpix_wallet/services/token_service.dart';
import 'support/isolated_db.dart';

/// body จริงจาก https://tpix.online/api/v1/dex/pairs (2026-10-11)
const _realPairsBody =
    '{"success":true,"data":[{"symbol":"TPIX-USDT","base_asset":"TPIX","quote_asset":"USDT",'
    '"base_address":"0x0000000000000000000000000000000000000000",'
    '"quote_address":"0x0A4Ee87551eF041f3EecFBBfdcfFC1B46a4878f1","base_decimals":18,'
    '"quote_decimals":6,"base_logo":"https:\\/\\/tpix.online\\/images\\/brand\\/tpix-coin.png",'
    '"quote_logo":"https:\\/\\/assets-cdn.trustwallet.com\\/blockchains\\/ethereum\\/assets\\/0xdAC17F958D2ee523a2206206994597C13D831ec7\\/logo.png",'
    '"pair_address":"0x3684e0ebd1bd7ef7b7783e695639badcd04bc4f0","is_active":true,"chain_id":4289}]}';

const _usdt = '0x0a4ee87551ef041f3eecfbbfdcffc1b46a4878f1';
const _staleToken = '0x1111111111111111111111111111111111111111';

Map<String, dynamic> _pair({
  String base = '0x0000000000000000000000000000000000000000',
  String quote = '0x2222222222222222222222222222222222222222',
  String symbol = 'ABC',
  dynamic decimals = 18,
  dynamic chainId = 4289,
  bool active = true,
}) =>
    {
      'base_address': base,
      'quote_address': quote,
      'quote_asset': symbol,
      'quote_decimals': decimals,
      'chain_id': chainId,
      'is_active': active,
    };

String _body(List<Map<String, dynamic>> pairs) =>
    jsonEncode({'success': true, 'data': pairs});

void main() {
  // ฐานข้อมูลแยกของไฟล์นี้ — กันชนกับไฟล์เทสต์อื่นที่รันพร้อมกัน
  setUpAll(() => useIsolatedTestDb('token_registry'));

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    TokenService.resetCache();
    await DbService.close();
    await databaseFactory.deleteDatabase(
      '${await databaseFactory.getDatabasesPath()}/tpix_wallet.db',
    );
  });

  tearDown(() {
    TokenService.clientFactory = http.Client.new;
    RpcClient.overrideForChain(4289, null);
  });

  tearDownAll(() async => DbService.close());

  group('parseDexPairs', () {
    test('API จริงวันนี้ → USDT ตัวเดียว (6 ทศนิยม + โลโก้)', () {
      final tokens = TokenService.parseDexPairs(_realPairsBody);
      expect(tokens, hasLength(1));
      final usdt = tokens.single;
      expect(usdt.address.toLowerCase(), _usdt);
      expect(usdt.symbol, 'USDT');
      expect(usdt.decimals, 6);
      expect(usdt.logoUrl, startsWith('https://assets-cdn.trustwallet.com/'));
      expect(usdt.name, 'Tether USD', reason: 'ชื่อเต็มจากค่าในตัวแอปที่รู้จัก');
    });

    test('เอาเฉพาะฝั่ง quote ของคู่ที่ base เป็น TPIX native บนเชน 4289 ที่เปิดอยู่', () {
      final tokens = TokenService.parseDexPairs(_body([
        _pair(symbol: 'OK'),
        _pair(symbol: 'BSC', chainId: 56),
        _pair(symbol: 'OFF', active: false),
        _pair(symbol: 'NONNATIVE', base: '0x3333333333333333333333333333333333333333'),
        _pair(symbol: 'BADADDR', quote: '0x1234'),
        _pair(symbol: 'BADDEC', decimals: '6'),
        _pair(symbol: 'HUGEDEC', decimals: 99),
        _pair(symbol: 'DUP'), // ที่อยู่ซ้ำกับ OK
      ]));
      expect(tokens.map((t) => t.symbol), ['OK']);
      expect(tokens.single.name, 'OK', reason: 'ไม่รู้จัก = ใช้สัญลักษณ์ ไม่เดาชื่อ');
    });

    test('body ผิดรูป → ว่าง', () {
      expect(TokenService.parseDexPairs('<html>'), isEmpty);
      expect(TokenService.parseDexPairs('{"success":false,"data":[]}'), isEmpty);
    });
  });

  group('tpixChainTokens', () {
    test('API ใช้ได้ → ได้รายการจาก API', () async {
      TokenService.clientFactory =
          () => MockClient((_) async => http.Response(_realPairsBody, 200));
      final tokens = await TokenService.tpixChainTokens();
      expect(tokens.map((t) => t.address.toLowerCase()), [_usdt]);
    });

    test('API ล่ม → ใช้ USDT_TPIX ค่าเริ่มต้นในตัวแอป (แบบเดียวกับเชนอื่น)', () async {
      TokenService.clientFactory =
          () => MockClient((_) async => http.Response('down', 503));
      final tokens = await TokenService.tpixChainTokens();
      expect(tokens.map((t) => t.address.toLowerCase()), [_usdt]);
      expect(tokens.single.decimals, 6);
      expect(ChainConfig.tpix.knownTokens.single.address.toLowerCase(), _usdt);
    });
  });

  group('ensureDefaultTokens', () {
    test('เพิ่ม USDT ให้กระเป๋าครั้งเดียว — ผู้ใช้ลบแล้วต้องไม่โผล่กลับมาเอง', () async {
      TokenService.clientFactory =
          () => MockClient((_) async => http.Response(_realPairsBody, 200));

      await TokenService.ensureDefaultTokens(1);
      var tokens = await DbService.getTokensForSlot(1);
      expect(tokens.map((t) => t.contractAddress), [_usdt]);
      expect(tokens.single.decimals, 6);
      expect(tokens.single.logoUrl, isNotNull);

      // เรียกซ้ำ → ไม่เพิ่มซ้ำ
      await TokenService.ensureDefaultTokens(1);
      expect(await DbService.getTokensForSlot(1), hasLength(1));

      // ผู้ใช้ลบเอง → ไม่เพิ่มกลับ
      await DbService.removeToken(_usdt, 1);
      await TokenService.ensureDefaultTokens(1);
      expect(await DbService.getTokensForSlot(1), isEmpty);

      // กระเป๋าใบอื่นยังได้ของตัวเอง
      await TokenService.ensureDefaultTokens(2);
      expect(await DbService.getTokensForSlot(2), hasLength(1));
    });
  });

  group('checkContracts — โทเค็นที่สัญญาหายหลัง re-genesis', () {
    TokenInfo token(String addr) =>
        TokenInfo(contractAddress: addr, name: 'X', symbol: 'X', walletSlot: 1);

    void rpcReturns(Map<String, dynamic Function()> codeByAddress) {
      RpcClient.overrideForChain(
        4289,
        RpcClient(
          ['https://rpc.tpix.online'],
          httpClient: MockClient((req) async {
            final body = jsonDecode(req.body) as Map<String, dynamic>;
            // eth_getCode: [address, 'latest'] · eth_call: [{to, data}, 'latest']
            final first = (body['params'] as List).first;
            final addr = (first is Map ? first['to'] : first).toString().toLowerCase();
            final result = codeByAddress[addr]!();
            if (result is http.Response) return result;
            return http.Response(
                jsonEncode({'jsonrpc': '2.0', 'id': 1, 'result': result}), 200);
          }),
        ),
      );
    }

    test('getCode = "0x" (ตอบสำเร็จ) → สัญญาหาย, มี bytecode → ยังอยู่', () async {
      rpcReturns({
        _usdt: () => '0x6080604052',
        _staleToken: () => '0x',
      });
      final r = await TokenService.checkContracts([token(_usdt), token(_staleToken)]);
      expect(r.missing, {_staleToken});
      expect(r.present, {_usdt});
    });

    test('RPC ล่ม → "ไม่รู้" ห้ามติดป้ายว่าสัญญาหาย', () async {
      rpcReturns({
        _staleToken: () => http.Response('<html>blocked</html>', 403),
      });
      final r = await TokenService.checkContracts([token(_staleToken)]);
      expect(r.missing, isEmpty);
      expect(r.present, isEmpty);
    });

    test('ยอดของโทเค็นที่ดึงไม่ได้ = null ไม่ใช่ 0', () async {
      rpcReturns({
        _usdt: () => http.Response('bad gateway', 502),
      });
      expect(await TokenService.getTokenBalance(_usdt, _staleToken), isNull);
    });
  });
}
