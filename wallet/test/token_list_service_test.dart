/// TPIX Wallet — เทสต์รายการโทเค็นที่ยืนยันแล้ว (https://tpix.online/tokenlist.json)
///
/// ตรวจข้อมูลทุกช่องก่อนใช้, แคช 6 ชม., ออฟไลน์ใช้ชุดในเครื่อง,
/// 404/หมดเวลา/JSON เสีย → ถอยไปของเดิม (ไม่มีเน็ตจริงในเทสต์)
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tpix_wallet/models/chain_config.dart';
import 'package:tpix_wallet/services/token_list_service.dart';

const _idtc = '0x5fbdb2315678afecb367f032d93f642f64180aa3';
const _idtcLogo = 'https://tpix.online/storage/tokens/idtc.png';

/// ที่อยู่ไม่ซ้ำ (ตัวเล็กล้วน = ไม่ต้องมี checksum)
String _addr(int i) => '0x${i.toRadixString(16).padLeft(40, '0')}';

/// อักขระที่มองไม่เห็น — สร้างจากรหัส (ไม่ใส่ตัวจริงลงในซอร์ส)
final _zeroWidth = String.fromCharCode(0x200B);
final _rtlOverride = String.fromCharCode(0x202E);

Map<String, dynamic> _entry({
  String address = _idtc,
  Object? chainId = 4289,
  Object? name = 'IDTC Token',
  Object? symbol = 'IDTC',
  Object? decimals = 18,
  Object? logo = _idtcLogo,
}) =>
    {
      'chainId': chainId,
      'address': address,
      'name': name,
      'symbol': symbol,
      'decimals': decimals,
      'logoURI': ?logo,
    };

String _listBody(List<Object?> tokens) => jsonEncode({
      'name': 'TPIX Token List',
      'timestamp': '2026-10-11T00:00:00.000Z',
      'version': {'major': 1, 'minor': 2, 'patch': 3},
      'tokens': tokens,
    });

void main() {
  group('parse — โครงสร้าง', () {
    test('รายการปกติ → ได้ทุกช่องครบ', () {
      final list = TokenListService.parse(_listBody([
        _entry(),
        _entry(
          address: ChainConfig.tpixUsdtAddress,
          name: 'Tether USD',
          symbol: 'USDT',
          decimals: 6,
          logo: null,
        ),
      ]))!;
      expect(list.name, 'TPIX Token List');
      expect(list.version.toString(), '1.2.3');
      expect(list.tokens, hasLength(2));
      final idtc = list.byAddress(_idtc.toUpperCase().replaceFirst('0X', '0x'))!;
      expect(idtc.symbol, 'IDTC');
      expect(idtc.name, 'IDTC Token');
      expect(idtc.decimals, 18);
      expect(idtc.logoUri, _idtcLogo);
      final usdt = list.byAddress(ChainConfig.tpixUsdtAddress.toLowerCase())!;
      expect(usdt.address, ChainConfig.tpixUsdtAddress, reason: 'เก็บที่อยู่แบบ checksum ตามที่ประกาศ');
      expect(usdt.logoUri, isNull);
    });

    test('ไม่ใช่ JSON / ไม่ใช่ object / ไม่มี tokens → null (ใช้ของเดิม)', () {
      expect(TokenListService.parse('<!DOCTYPE html><html>404</html>'), isNull);
      expect(TokenListService.parse(''), isNull);
      expect(TokenListService.parse('[]'), isNull);
      expect(TokenListService.parse('{}'), isNull);
      expect(TokenListService.parse('{"tokens":"x"}'), isNull);
      expect(TokenListService.parse('{"tokens":{}}'), isNull);
    });

    test('ไม่มีชื่อ/เวอร์ชันผิดรูป → ยังใช้ได้ (ค่าเริ่มต้น / ไม่มีเวอร์ชัน)', () {
      final list = TokenListService.parse(jsonEncode({
        'version': {'major': '1', 'minor': 0, 'patch': 0},
        'tokens': [_entry()],
      }))!;
      expect(list.name, isNotEmpty);
      expect(list.version, isNull);
      expect(list.tokens, hasLength(1));
    });

    test('tokens ว่าง → รายการว่าง (ไม่ใช่ null)', () {
      final list = TokenListService.parse(_listBody([]))!;
      expect(list.isEmpty, isTrue);
    });
  });

  group('parse — ตรวจทีละรายการ (ผิดรูป = ข้าม ไม่เดา)', () {
    List<String> symbolsOf(List<Object?> tokens) =>
        TokenListService.parse(_listBody(tokens))!.tokens.map((t) => t.symbol).toList();

    test('เฉพาะ chainId 4289 ที่เป็นตัวเลข', () {
      expect(
        symbolsOf([
          _entry(address: _addr(1), symbol: 'OK'),
          _entry(address: _addr(2), symbol: 'BSC', chainId: 56),
          _entry(address: _addr(3), symbol: 'STR', chainId: '4289'),
          _entry(address: _addr(4), symbol: 'NUL', chainId: null),
        ]),
        ['OK'],
      );
    });

    test('ที่อยู่: ต้อง 0x+40 hex, ไม่ใช่ 0x000…0, ตัวพิมพ์ผสมต้องตรง checksum', () {
      final badChecksum = ChainConfig.tpixUsdtAddress.replaceFirst('0x0A4E', '0x0a4E');
      expect(
        symbolsOf([
          _entry(address: _addr(1), symbol: 'OK'),
          _entry(address: ChainConfig.tpixUsdtAddress, symbol: 'SUM'),
          _entry(address: badChecksum, symbol: 'BADSUM'),
          _entry(address: '0x1234', symbol: 'SHORT'),
          _entry(address: '${_addr(5)}00', symbol: 'LONG'),
          _entry(address: _addr(6).replaceFirst('0x', ''), symbol: 'NO0X'),
          _entry(address: '0x${'g' * 40}', symbol: 'NOTHEX'),
          _entry(address: TokenDef.nativeAddress, symbol: 'ZERO'),
        ]),
        ['OK', 'SUM'],
      );
    });

    test('ที่อยู่ซ้ำ (ต่างตัวพิมพ์) → ตัวแรกชนะ', () {
      expect(
        symbolsOf([
          _entry(address: _addr(0xabc), symbol: 'FIRST'),
          _entry(address: _addr(0xabc).toUpperCase().replaceFirst('0X', '0x'), symbol: 'SECOND'),
        ]),
        ['FIRST'],
      );
    });

    test('ทศนิยม: จำนวนเต็ม 0..36 เท่านั้น', () {
      expect(
        symbolsOf([
          _entry(address: _addr(1), symbol: 'D0', decimals: 0),
          _entry(address: _addr(2), symbol: 'D36', decimals: 36),
          _entry(address: _addr(3), symbol: 'D37', decimals: 37),
          _entry(address: _addr(4), symbol: 'DNEG', decimals: -1),
          _entry(address: _addr(5), symbol: 'DSTR', decimals: '18'),
          _entry(address: _addr(6), symbol: 'DDBL', decimals: 18.5),
          _entry(address: _addr(7), symbol: 'DNULL', decimals: null),
        ]),
        ['D0', 'D36'],
      );
    });

    test('สัญลักษณ์ ≤ 20 / ชื่อ ≤ 60 ตัวอักษร, ไม่ว่าง, ตัดช่องว่างหัวท้าย', () {
      final list = TokenListService.parse(_listBody([
        _entry(address: _addr(1), symbol: 'S' * 20, name: 'N' * 60),
        _entry(address: _addr(2), symbol: 'S' * 21),
        _entry(address: _addr(3), name: 'N' * 61),
        _entry(address: _addr(4), symbol: '   '),
        _entry(address: _addr(5), symbol: ''),
        _entry(address: _addr(6), name: null),
        _entry(address: _addr(7), symbol: 42),
        _entry(address: _addr(8), symbol: '  PAD  ', name: '  Padded  '),
        // ภาษาไทย 20 ตัวอักษรพอดี (นับเป็นตัวอักษร ไม่ใช่ไบต์)
        _entry(address: _addr(9), symbol: 'ก' * 20),
      ]))!;
      expect(list.tokens.map((t) => t.symbol), ['S' * 20, 'PAD', 'ก' * 20]);
      expect(list.byAddress(_addr(8))!.name, 'Padded');
    });

    test('อักขระซ่อน/สลับทิศ/ขึ้นบรรทัดใหม่ในชื่อหรือสัญลักษณ์ → ข้าม (กันปลอมชื่อ)', () {
      expect(
        symbolsOf([
          _entry(address: _addr(1), symbol: 'OK'),
          _entry(address: _addr(2), symbol: 'US${_zeroWidth}DT'),
          _entry(address: _addr(3), name: 'Tether ${_rtlOverride}DSU'),
          _entry(address: _addr(4), symbol: 'LINE\nBREAK'),
          _entry(address: _addr(5), symbol: 'TAB\tX'),
        ]),
        ['OK'],
      );
    });

    test('รายการที่ไม่ใช่ object ถูกข้าม', () {
      expect(symbolsOf(['oops', 42, null, [], _entry(address: _addr(1), symbol: 'OK')]), ['OK']);
    });

    test('จำกัดไม่เกิน 1000 โทเค็น', () {
      final list = TokenListService.parse(_listBody([
        for (var i = 1; i <= 1500; i++) _entry(address: _addr(i), symbol: 'T$i'),
      ]))!;
      expect(list.tokens, hasLength(TokenListService.maxTokens));
      expect(list.tokens.last.symbol, 'T1000');
    });
  });

  group('parse — logoURI (https เท่านั้น; ใช้ไม่ได้ = ทิ้งแค่โลโก้)', () {
    String? logoOf(Object? logo) =>
        TokenListService.parse(_listBody([_entry(logo: logo)]))!.tokens.single.logoUri;

    test('https → ใช้', () {
      expect(logoOf(_idtcLogo), _idtcLogo);
    });

    test('scheme ตัวใหญ่ → ปรับเป็นรูปมาตรฐาน', () {
      expect(logoOf('HTTPS://TPIX.online/a.png'), 'https://tpix.online/a.png');
    });

    test('http / ipfs / data / javascript / ไม่มีโฮสต์ / มี user:pass / ยาวเกิน / ไม่ใช่สตริง → null', () {
      expect(logoOf('http://tpix.online/a.png'), isNull);
      expect(logoOf('ipfs://QmHash'), isNull);
      expect(logoOf('data:image/png;base64,AAAA'), isNull);
      expect(logoOf('javascript:alert(1)'), isNull);
      expect(logoOf('https://'), isNull);
      expect(logoOf('https://user:pass@tpix.online/a.png'), isNull);
      expect(logoOf('https://tpix.online/${'a' * 600}.png'), isNull);
      expect(logoOf(123), isNull);
      expect(logoOf(''), isNull);
    });
  });

  group('sanitizeOnChainText — ชื่อ/สัญลักษณ์ที่อ่านจากสัญญา', () {
    test('ตัดอักขระซ่อน/สลับทิศ ยุบช่องว่าง', () {
      expect(TokenListService.sanitizeOnChainText('US${_zeroWidth}DT', 32), 'USDT');
      expect(TokenListService.sanitizeOnChainText('Tether$_rtlOverride  USD\n', 64), 'Tether USD');
    });

    test('ยาวเกิน → ตัดตามจำนวนตัวอักษร · เหลือว่าง → null', () {
      expect(TokenListService.sanitizeOnChainText('A' * 100, 32), 'A' * 32);
      expect(TokenListService.sanitizeOnChainText(_zeroWidth * 3, 32), isNull);
      expect(TokenListService.sanitizeOnChainText(null, 32), isNull);
    });
  });

  group('load — แคช / TTL / ออฟไลน์', () {
    late DateTime now;
    late int calls;
    late http.Response Function() respond;

    void serve() {
      TokenListService.clientFactory = () => MockClient((req) async {
            calls++;
            expect(req.url.toString(), TokenListService.url);
            return respond();
          });
    }

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      TokenListService.resetForTest();
      now = DateTime(2026, 10, 11, 12);
      TokenListService.clock = () => now;
      calls = 0;
      respond = () => http.Response(_listBody([_entry()]), 200);
      serve();
    });

    tearDown(TokenListService.resetForTest);

    /// จำลองการปิดแล้วเปิดแอปใหม่: หน่วยความจำหาย แต่ SharedPreferences ยังอยู่
    void restartApp() {
      final clock = TokenListService.clock;
      TokenListService.resetForTest();
      TokenListService.clock = clock;
      serve();
    }

    test('ดึงสำเร็จ → current พร้อมใช้ + ไม่ยิงซ้ำภายใน 6 ชม.', () async {
      expect(TokenListService.current, isNull);
      final list = await TokenListService.load();
      expect(list!.byAddress(_idtc)!.symbol, 'IDTC');
      expect(TokenListService.current, same(list));
      expect(calls, 1);

      now = now.add(const Duration(hours: 5, minutes: 59));
      await TokenListService.load();
      expect(calls, 1);
    });

    test('เกิน 6 ชม. → ดึงใหม่ ได้ชุดใหม่', () async {
      await TokenListService.load();
      respond = () => http.Response(_listBody([_entry(symbol: 'IDTC2')]), 200);
      now = now.add(TokenListService.ttl + const Duration(minutes: 1));
      final list = await TokenListService.load();
      expect(calls, 2);
      expect(list!.byAddress(_idtc)!.symbol, 'IDTC2');
    });

    test('forceRefresh → ดึงทันทีแม้ยังไม่หมดอายุ', () async {
      await TokenListService.load();
      await TokenListService.load(forceRefresh: true);
      expect(calls, 2);
    });

    test('เปิดแอปใหม่แบบออฟไลน์ (แคชยังไม่หมดอายุ) → ใช้ชุดในเครื่อง ไม่แตะเน็ต', () async {
      await TokenListService.load();
      restartApp();
      respond = () => throw http.ClientException('offline');
      expect(TokenListService.current, isNull, reason: 'หน่วยความจำว่างหลังเปิดใหม่');
      final list = await TokenListService.load();
      expect(list!.byAddress(_idtc)!.logoUri, _idtcLogo);
      expect(calls, 1, reason: 'ครั้งแรกตอนออนไลน์เท่านั้น');
    });

    test('แคชหมดอายุ + เซิร์ฟเวอร์ล่ม → ใช้ชุดเก่าต่อ และไม่ยิงถี่ (รอ 5 นาที)', () async {
      await TokenListService.load();
      restartApp();
      now = now.add(const Duration(hours: 7));
      respond = () => http.Response('Service Unavailable', 503);

      final stale = await TokenListService.load();
      expect(stale!.byAddress(_idtc), isNotNull, reason: 'ดึงไม่ได้ ≠ ลบรายการทิ้ง');
      expect(calls, 2);

      now = now.add(const Duration(minutes: 4));
      await TokenListService.load();
      expect(calls, 2, reason: 'ยังไม่ถึงเวลาลองใหม่');

      now = now.add(const Duration(minutes: 2));
      respond = () => http.Response(_listBody([_entry(symbol: 'NEW')]), 200);
      final fresh = await TokenListService.load();
      expect(calls, 3);
      expect(fresh!.byAddress(_idtc)!.symbol, 'NEW');
    });

    test('ยังไม่เคยมีรายการ + 404 (ไฟล์ยังไม่ขึ้นเว็บ) → null = ใช้ของเดิม (DEX + ในตัวแอป)', () async {
      respond = () => http.Response('Not Found', 404);
      expect(await TokenListService.load(), isNull);
      expect(TokenListService.current, isNull);
    });

    test('200 แต่ JSON เสีย / เป็นหน้า HTML → ไม่ทับชุดเดิม', () async {
      await TokenListService.load();
      now = now.add(const Duration(hours: 7));
      respond = () => http.Response('<!DOCTYPE html><html>Cloudflare</html>', 200);
      final list = await TokenListService.load();
      expect(list!.byAddress(_idtc), isNotNull);
      expect(calls, 2);
    });

    test('หมดเวลา → null (ไม่ค้าง)', () async {
      TokenListService.timeout = const Duration(milliseconds: 50);
      TokenListService.clientFactory = () => MockClient((_) async {
            calls++;
            await Future<void>.delayed(const Duration(seconds: 2));
            return http.Response(_listBody([_entry()]), 200);
          });
      final sw = Stopwatch()..start();
      expect(await TokenListService.load(), isNull);
      expect(sw.elapsed, lessThan(const Duration(seconds: 1)));
    });

    test('ไฟล์ใหญ่เกิน 1MB → ไม่ใช้ (ทั้งแบบบอกขนาดและแบบสตรีม)', () async {
      // JSON ถูกต้อง (ช่องว่างท้ายไฟล์ใช้ได้) — ถูกปัดทิ้งเพราะขนาดอย่างเดียว
      final valid = _listBody([_entry()]);
      expect(TokenListService.parse('$valid${' ' * 1000}'), isNotNull);
      respond = () => http.Response('$valid${' ' * TokenListService.maxBodyBytes}', 200);
      expect(await TokenListService.load(), isNull);

      // ไม่บอก content-length — ต้องหยุดอ่านเองเมื่อเกิน
      TokenListService.resetForTest();
      TokenListService.clock = () => now;
      TokenListService.clientFactory = () => MockClient.streaming((req, _) async {
            final chunk = utf8.encode(' ' * 64 * 1024);
            return http.StreamedResponse(
              Stream.fromIterable([utf8.encode(valid), ...List.filled(20, chunk)]),
              200,
            );
          });
      expect(await TokenListService.load(), isNull);
    });

    test('เรียกพร้อมกันหลายที่ → ยิงเน็ตครั้งเดียว', () async {
      final gate = Completer<void>();
      TokenListService.clientFactory = () => MockClient((_) async {
            calls++;
            await gate.future;
            return http.Response(_listBody([_entry()]), 200);
          });
      final a = TokenListService.load();
      final b = TokenListService.load();
      final c = TokenListService.load();
      gate.complete();
      final results = await Future.wait([a, b, c]);
      expect(calls, 1);
      expect(results.every((r) => r != null && r.byAddress(_idtc) != null), isTrue);
    });

    test('นาฬิกาเครื่องถูกย้อน (เวลาที่ดึงอยู่ในอนาคต) → ถือว่าหมดอายุ ดึงใหม่', () async {
      await TokenListService.load();
      now = now.subtract(const Duration(days: 1));
      await TokenListService.load();
      expect(calls, 2);
    });

    test('แคชในเครื่องถูกแก้ (เครื่อง root) → ตรวจซ้ำ รายการที่ไม่ผ่านถูกทิ้ง', () async {
      SharedPreferences.setMockInitialValues({
        'tokenlist_4289_v1': jsonEncode({
          'fetchedAt': now.millisecondsSinceEpoch,
          'list': {
            'name': 'x',
            'tokens': [
              _entry(),
              _entry(address: _addr(1), symbol: 'EVIL', logo: 'http://evil.example/a.png'),
              _entry(address: '0xnot-an-address', symbol: 'BAD'),
              _entry(address: _addr(2), symbol: 'BIG', decimals: 77),
            ],
          },
        }),
      });
      final list = await TokenListService.load();
      expect(calls, 0, reason: 'แคชยังไม่หมดอายุ');
      expect(list!.tokens.map((t) => t.symbol), ['IDTC', 'EVIL']);
      expect(list.byAddress(_addr(1))!.logoUri, isNull, reason: 'โลโก้ http ถูกทิ้ง');
    });

    test('แคชเสีย (ไม่ใช่ JSON) → ไม่สนใจ ดึงจากเน็ตแทน', () async {
      SharedPreferences.setMockInitialValues({'tokenlist_4289_v1': 'garbage{'});
      final list = await TokenListService.load();
      expect(calls, 1);
      expect(list!.byAddress(_idtc), isNotNull);
    });
  });
}
