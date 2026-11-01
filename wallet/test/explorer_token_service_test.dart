/// TPIX Wallet — เทสต์รายการเหรียญจาก explorer: กฎ verify/scam, ไล่หลายหน้า, fail closed,
/// แคชที่มีอายุ, จำกัดหน้า/ขนาด/คำขอพร้อมกัน
///
/// ไม่มีเน็ตจริง: explorer เป็น MockClient ทั้งหมด
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tpix_wallet/services/explorer_token_service.dart';

String _hex(int i) => '0x${i.toRadixString(16).padLeft(40, '0')}';

/// explorer ปลอม: หน้า /api/v2/tokens (แบ่งหน้าแบบ Blockscout) + /api/v2/addresses/{ที่อยู่}
class _Explorer {
  /// รายการทั้งหมด (ตามลำดับ) — แบ่งหน้าละ [pageSize] เท่า Blockscout
  final List<Map<String, Object?>> items = [];
  static const pageSize = 50;

  /// ผลตรวจรายสัญญา (ตัวเล็ก) — ไม่ระบุ = verify แล้ว ไม่ scam
  final Map<String, FutureOr<http.Response> Function(String address)> address = {};

  bool down = false;
  http.Response Function()? pageOverride;
  Duration addressDelay = const Duration(milliseconds: 2);
  final requests = <Uri>[];
  int inFlight = 0;
  int maxInFlight = 0;

  int get pageRequests => requests.where((u) => u.path == '/api/v2/tokens').length;
  int get addressRequests => requests.where((u) => u.path.startsWith('/api/v2/addresses/')).length;

  void add(String addr, {String? name, String? symbol, String type = 'ERC-20', Object? icon}) => items.add({
        'address': addr,
        'name': name ?? 'Coin $addr',
        'symbol': symbol ?? 'C${items.length}',
        'decimals': '18',
        'type': type,
        'icon_url': icon,
        'holders': '1',
      });

  void verdict(String addr, {bool verified = true, bool scam = false, bool contract = true}) =>
      address[addr.toLowerCase()] = (a) => _addressBody(a, verified: verified, scam: scam, contract: contract);

  http.Client client() => MockClient((req) async {
        requests.add(req.url);
        if (down) throw http.ClientException('offline');
        if (req.url.path == '/api/v2/tokens') {
          if (pageOverride != null) return pageOverride!();
          expect(req.url.queryParameters['type'], 'ERC-20');
          final offset = int.tryParse(req.url.queryParameters['items_count'] ?? '0') ?? 0;
          final slice = items.skip(offset).take(pageSize).toList();
          final end = offset + slice.length;
          return http.Response(
            jsonEncode({
              'items': slice,
              // รูปแบบเดียวกับ Blockscout จริง: มีค่า null / false / ตัวเลขปน
              'next_page_params': end < items.length
                  ? {
                      'contract_address_hash': slice.last['address'],
                      'holders_count': 1,
                      'is_name_null': false,
                      'items_count': end,
                      'market_cap': null,
                      'name': slice.last['name'],
                    }
                  : null,
            }),
            200,
          );
        }
        if (req.url.path.startsWith('/api/v2/addresses/')) {
          inFlight++;
          maxInFlight = math.max(maxInFlight, inFlight);
          try {
            await Future<void>.delayed(addressDelay);
            final a = req.url.pathSegments.last;
            final custom = address[a.toLowerCase()];
            return custom != null ? await custom(a) : _addressBody(a);
          } finally {
            inFlight--;
          }
        }
        return http.Response('not found', 404);
      });
}

http.Response _addressBody(String a, {bool verified = true, bool scam = false, bool contract = true}) =>
    http.Response(
      jsonEncode({
        'hash': a,
        'is_verified': verified,
        'is_scam': scam,
        'is_contract': contract,
        'name': 'Contract',
        'coin_balance': '0',
      }),
      200,
    );

void main() {
  late _Explorer explorer;
  late DateTime now;

  void serve() => ExplorerTokenService.clientFactory = explorer.client;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ExplorerTokenService.resetForTest();
    now = DateTime(2026, 11, 1, 12);
    ExplorerTokenService.clock = () => now;
    explorer = _Explorer();
    serve();
  });

  tearDown(ExplorerTokenService.resetForTest);

  /// จำลองการปิดแล้วเปิดแอปใหม่: หน่วยความจำหาย แต่ SharedPreferences ยังอยู่
  void restartApp() {
    ExplorerTokenService.resetForTest();
    ExplorerTokenService.clock = () => now;
    serve();
  }

  List<String> symbols() => ExplorerTokenService.current!.tokens.map((t) => t.symbol).toList();

  group('parse — ค่าจาก explorer เชื่อไม่ได้', () {
    test('ข้ามตัวที่ไม่ใช่ ERC-20 / ที่อยู่ผิด / checksum ผิด / ไม่มีชื่อ · ทำความสะอาดชื่อ · โลโก้ https เท่านั้น', () {
      const zw = '​';
      final page = ExplorerTokenService.parseTokensPage(jsonEncode({
        'items': [
          {'address': _hex(1), 'name': 'Good', 'symbol': 'GOOD', 'type': 'ERC-20', 'icon_url': 'https://x.test/a.png'},
          {'address': _hex(2), 'name': 'NFT', 'symbol': 'NFT', 'type': 'ERC-721'},
          {'address': '0x123', 'name': 'Short', 'symbol': 'S', 'type': 'ERC-20'},
          // ตัวพิมพ์ผสมแต่ checksum ผิด (EIP-55)
          {'address': '0x0a4EE87551eF041f3EecFBBfdcfFC1B46a4878f1', 'name': 'Bad', 'symbol': 'BAD', 'type': 'ERC-20'},
          {'address': '0x0000000000000000000000000000000000000000', 'name': 'Zero', 'symbol': 'Z', 'type': 'ERC-20'},
          {'address': _hex(3), 'name': null, 'symbol': 'NONAME', 'type': 'ERC-20'},
          {'address': _hex(4), 'name': 'US${zw}DT  Coin', 'symbol': 'US${zw}DT', 'type': 'ERC-20', 'icon_url': 'http://x.test/a.png'},
          {'address_hash': _hex(5), 'name': 'New API', 'symbol': 'NEW', 'type': 'ERC-20', 'icon_url': 'javascript:alert(1)'},
          'not a map',
        ],
        'next_page_params': null,
      }))!;
      expect(page.items.map((t) => t.symbol), ['GOOD', 'USDT', 'NEW']);
      expect(page.items[0].logoUri, 'https://x.test/a.png');
      expect(page.items[1].name, 'USDT Coin', reason: 'ตัดอักขระซ่อน + ยุบช่องว่าง');
      expect(page.items[1].logoUri, isNull, reason: 'http ไม่ได้');
      expect(page.items[2].logoUri, isNull);
      expect(page.next, isNull);
    });

    test('body ไม่ใช่รายการ → null (ไม่เดา)', () {
      for (final body in ['<html>502</html>', '', '[]', '{}', '{"items":"x"}']) {
        expect(ExplorerTokenService.parseTokensPage(body), isNull, reason: body);
      }
    });

    test('next_page_params: null/false ส่งเป็นข้อความ · ซ้อนกัน/คีย์แปลก = หยุด', () {
      String body(Object? next) => jsonEncode({'items': [], 'next_page_params': next});
      expect(
        ExplorerTokenService.parseTokensPage(body({'market_cap': null, 'is_name_null': false, 'items_count': 50}))!.next,
        {'market_cap': 'null', 'is_name_null': 'false', 'items_count': '50'},
      );
      expect(ExplorerTokenService.parseTokensPage(body({'a': {'b': 1}}))!.next, isNull);
      expect(ExplorerTokenService.parseTokensPage(body({'A-B': '1'}))!.next, isNull);
      expect(ExplorerTokenService.parseTokensPage(body({'a': 'x' * 300}))!.next, isNull);
      expect(ExplorerTokenService.parseTokensPage(body([]))!.next, isNull);
    });

    test('type ล็อกเป็น ERC-20 แม้พารามิเตอร์หน้าถัดไปจะพยายามเปลี่ยน', () {
      final uri = ExplorerTokenService.tokensUri({'type': 'ERC-721', 'items_count': '50'});
      expect(uri.queryParameters, {'type': 'ERC-20', 'items_count': '50'});
      expect(uri.host, 'explorer.tpix.online');
    });

    test('ผลตรวจรายสัญญา: ผ่านเฉพาะ verify + ไม่ scam + เป็นสัญญา + ที่อยู่ตรงกัน', () {
      final a = _hex(9);
      Map<String, Object?> body({Object? verified = true, Object? scam = false, Object? contract = true, Object? hash}) =>
          {'hash': hash ?? a, 'is_verified': verified, 'is_scam': scam, 'is_contract': contract};
      ExplorerVerdict check(Object? decoded) => ExplorerTokenService.parseAddressCheck(a, decoded);
      expect(check(body()), ExplorerVerdict.pass);
      expect(check(body(hash: a.toUpperCase().replaceFirst('0X', '0x'))), ExplorerVerdict.pass);
      expect(check(body(verified: false)), ExplorerVerdict.fail);
      expect(check(body(scam: true)), ExplorerVerdict.fail);
      expect(check(body(contract: false)), ExplorerVerdict.fail);
      // ฟิลด์หาย / ผิดชนิด / คนละที่อยู่ = ตรวจไม่ได้ (ไม่ใช่ผ่าน)
      expect(check(body(scam: null)), ExplorerVerdict.unknown);
      expect(check(body(verified: 'true')), ExplorerVerdict.unknown);
      expect(check(body(hash: _hex(8))), ExplorerVerdict.unknown);
      expect(check({'is_verified': true, 'is_scam': false, 'is_contract': true}), ExplorerVerdict.unknown);
      expect(check([]), ExplorerVerdict.unknown);
    });
  });

  group('load — กฎ verify', () {
    test('ไม่ verify ไม่ขึ้น · scam ไม่ขึ้น · ไม่ใช่สัญญาไม่ขึ้น · 404 ไม่ขึ้น · ผ่านขึ้น', () async {
      explorer
        ..add(_hex(1), symbol: 'OK')
        ..add(_hex(2), symbol: 'UNV')
        ..add(_hex(3), symbol: 'SCAM')
        ..add(_hex(4), symbol: 'EOA')
        ..add(_hex(5), symbol: 'GONE')
        ..verdict(_hex(2), verified: false)
        ..verdict(_hex(3), scam: true)
        ..verdict(_hex(4), contract: false);
      explorer.address[_hex(5)] = (_) => http.Response('{"message":"Not found"}', 404);

      final list = await ExplorerTokenService.load();
      expect(list!.tokens.map((t) => t.symbol), ['OK']);
      expect(list.byAddress(_hex(1))!.checkedAt, now);
      expect(ExplorerTokenService.isStale, isFalse, reason: 'ทุกตัวตอบชัด = ตรวจครบ');
    });

    test('หลายหน้าได้ครบทุกหน้า (ส่งพารามิเตอร์หน้าถัดไปกลับตามที่ได้)', () async {
      for (var i = 1; i <= 120; i++) {
        explorer.add(_hex(i), symbol: 'T$i');
      }
      final list = await ExplorerTokenService.load();
      expect(list!.tokens, hasLength(120));
      expect(list.tokens.first.symbol, 'T1');
      expect(list.tokens.last.symbol, 'T120');
      expect(explorer.pageRequests, 3);
      final second = explorer.requests.where((u) => u.path == '/api/v2/tokens').elementAt(1);
      expect(second.queryParameters, containsPair('market_cap', 'null'));
      expect(second.queryParameters, containsPair('is_name_null', 'false'));
      expect(second.queryParameters, containsPair('items_count', '50'));
    });

    test('verify ตรวจไม่ได้ (500 / 429 / หมดเวลา / JSON เสีย / ฟิลด์หาย) = ไม่ผ่าน', () async {
      ExplorerTokenService.timeout = const Duration(milliseconds: 50);
      explorer
        ..add(_hex(1), symbol: 'OK')
        ..add(_hex(2), symbol: 'E500')
        ..add(_hex(3), symbol: 'E429')
        ..add(_hex(4), symbol: 'SLOW')
        ..add(_hex(5), symbol: 'JUNK')
        ..add(_hex(6), symbol: 'NOSCAMFIELD');
      explorer.address[_hex(2)] = (_) => http.Response('oops', 500);
      explorer.address[_hex(3)] = (_) => http.Response('slow down', 429);
      explorer.address[_hex(5)] = (_) => http.Response('<html>', 200);
      explorer.address[_hex(6)] = (a) => http.Response(jsonEncode({'hash': a, 'is_verified': true, 'is_contract': true}), 200);
      final slow = Completer<void>();
      explorer.address[_hex(4)] = (a) async {
        await slow.future; // ไม่ตอบจนหมดเวลา
        return _addressBody(a);
      };

      final list = await ExplorerTokenService.load();
      slow.complete();
      expect(list!.tokens.map((t) => t.symbol), ['OK']);
      expect(ExplorerTokenService.isStale, isTrue, reason: 'มีตัวที่ตรวจไม่ได้ = อาจไม่ครบ');
    });

    test('เกินเวลารวมระหว่างไล่หน้า → ดึงไม่สำเร็จ (ไม่มีรายการครึ่งๆ กลางๆ)', () async {
      ExplorerTokenService.budget = Duration.zero;
      explorer.add(_hex(1));
      expect(await ExplorerTokenService.load(), isNull);
      expect(explorer.requests, isEmpty);
      expect(ExplorerTokenService.isStale, isTrue);
    });

    test('เกินเวลารวมระหว่างถามรายสัญญา → ตัวที่ยังไม่ได้ถาม = ตรวจไม่ได้ (ไม่ผ่าน)', () async {
      ExplorerTokenService.budget = const Duration(milliseconds: 300);
      explorer.addressDelay = const Duration(milliseconds: 400);
      for (var i = 1; i <= 12; i++) {
        explorer.add(_hex(i));
      }
      final list = await ExplorerTokenService.load();
      expect(list!.tokens, hasLength(ExplorerTokenService.concurrency), reason: 'รอบแรก 4 ตัวทันเวลา');
      expect(explorer.addressRequests, ExplorerTokenService.concurrency);
      expect(ExplorerTokenService.isStale, isTrue);
    });

    test('ถามรายสัญญาพร้อมกันไม่เกิน 4 ตัว', () async {
      explorer.addressDelay = const Duration(milliseconds: 10);
      for (var i = 1; i <= 12; i++) {
        explorer.add(_hex(i));
      }
      final list = await ExplorerTokenService.load();
      expect(list!.tokens, hasLength(12));
      expect(explorer.maxInFlight, lessThanOrEqualTo(ExplorerTokenService.concurrency));
      expect(explorer.maxInFlight, greaterThan(1), reason: 'ขนานกันจริง ไม่ใช่ทีละตัว');
    });
  });

  group('load — แคช / อายุ / ล่ม', () {
    setUp(() {
      explorer
        ..add(_hex(1), symbol: 'AAA')
        ..add(_hex(2), symbol: 'BBB');
    });

    test('ภายใน 1 ชม. ไม่ยิงซ้ำ · เรียกพร้อมกัน = ยิงชุดเดียว', () async {
      final results = await Future.wait([
        ExplorerTokenService.load(),
        ExplorerTokenService.load(),
        ExplorerTokenService.load(),
      ]);
      expect(results.every((r) => identical(r, results.first)), isTrue);
      expect(explorer.pageRequests, 1);
      expect(explorer.addressRequests, 2);

      now = now.add(const Duration(minutes: 59));
      restartApp(); // เปิดหน้าใหม่ / เปิดแอปใหม่ ภายใน TTL → ใช้แคช
      expect((await ExplorerTokenService.load())!.tokens, hasLength(2));
      expect(explorer.pageRequests, 1);
    });

    test('explorer ล่ม + มีแคชที่เคยผ่าน → ใช้แคช (บอกว่าอาจไม่ล่าสุด) จนหมดอายุ 24 ชม.', () async {
      await ExplorerTokenService.load();
      restartApp();
      explorer.down = true;
      now = now.add(const Duration(hours: 2));
      final cached = await ExplorerTokenService.load();
      expect(cached!.tokens.map((t) => t.symbol), ['AAA', 'BBB']);
      expect(ExplorerTokenService.isStale, isTrue);

      now = now.add(const Duration(hours: 22, minutes: 1)); // ตรวจผ่านล่าสุดเกิน 24 ชม.
      expect(ExplorerTokenService.current, isNull, reason: 'เก่าเกินอายุ = ไม่ผ่าน');
      expect(await ExplorerTokenService.load(), isNull);
    });

    test('explorer ล่มและไม่มีแคช → null (หน้าจอต้องบอก + ให้ลองใหม่)', () async {
      explorer.down = true;
      expect(await ExplorerTokenService.load(), isNull);
      expect(ExplorerTokenService.current, isNull);
      expect(ExplorerTokenService.isStale, isTrue);
    });

    test('หน้า /tokens ล่ม/ใหญ่เกิน → ไม่แตะชุดเดิม', () async {
      await ExplorerTokenService.load();
      final before = ExplorerTokenService.current;
      now = now.add(const Duration(hours: 2));
      explorer.pageOverride = () => http.Response('x' * (ExplorerTokenService.maxPageBytes + 1), 200);
      expect(identical(await ExplorerTokenService.load(), before), isTrue);
      expect(ExplorerTokenService.isStale, isTrue);
    });

    test('ตรวจไม่ได้รอบใหม่ → ตัวที่เคยผ่านอยู่ต่อตามอายุเดิม · ตอบชัดว่าไม่ผ่าน → ตัดทันที', () async {
      await ExplorerTokenService.load();
      final firstCheck = now;
      now = now.add(const Duration(hours: 2));
      explorer.address[_hex(1)] = (_) => http.Response('down', 503); // AAA ตรวจไม่ได้
      explorer.verdict(_hex(2), scam: true); // BBB ถูกทำเครื่องหมาย scam
      final list = await ExplorerTokenService.load();
      expect(list!.tokens.map((t) => t.symbol), ['AAA']);
      expect(list.byAddress(_hex(1))!.checkedAt, firstCheck, reason: 'ไม่ต่ออายุให้ตัวที่ตรวจไม่ได้');

      now = firstCheck.add(const Duration(hours: 24, minutes: 1));
      expect(ExplorerTokenService.current, isNull);
    });

    test('หลุดจากหน้า /tokens → หายจากรายการ (แม้ยังไม่หมดอายุ)', () async {
      await ExplorerTokenService.load();
      explorer.items.removeAt(0);
      now = now.add(const Duration(hours: 2));
      expect(symbols(), ['AAA', 'BBB']);
      await ExplorerTokenService.load();
      expect(symbols(), ['BBB']);
    });

    test('ล่มแล้วไม่ยิงถี่ (รอ 2 นาที) · ปุ่มลองใหม่ข้ามได้แต่ไม่ถี่กว่า 5 วิ', () async {
      explorer.down = true;
      await ExplorerTokenService.load();
      await ExplorerTokenService.load();
      expect(explorer.pageRequests, 1);

      await ExplorerTokenService.load(forceRefresh: true); // กดลองใหม่ทันที
      expect(explorer.pageRequests, 1);
      now = now.add(const Duration(seconds: 6));
      explorer.down = false;
      expect((await ExplorerTokenService.load(forceRefresh: true))!.tokens, hasLength(2));
      expect(explorer.pageRequests, 2);
      expect(ExplorerTokenService.isStale, isFalse);
    });

    test('แคชในเครื่องถูกแก้ → ตัวที่ผิดรูป/เวลาอนาคตไม่ถูกใช้', () async {
      SharedPreferences.setMockInitialValues({
        'explorer_tokens_4289_v1': jsonEncode({
          'listAt': now.millisecondsSinceEpoch,
          'fetchedAt': now.millisecondsSinceEpoch,
          'tokens': [
            {'address': _hex(1), 'name': 'Good', 'symbol': 'GOOD', 'checkedAt': now.millisecondsSinceEpoch},
            {'address': '0xBAD', 'name': 'Bad', 'symbol': 'BAD', 'checkedAt': now.millisecondsSinceEpoch},
            {
              'address': _hex(3),
              'name': 'Future',
              'symbol': 'FUT',
              'checkedAt': now.add(const Duration(days: 30)).millisecondsSinceEpoch,
            },
            {'address': _hex(4), 'name': 'Logo', 'symbol': 'LOGO', 'logo': 'http://x/a.png', 'checkedAt': now.millisecondsSinceEpoch},
          ],
        }),
      });
      restartApp();
      final list = await ExplorerTokenService.load();
      expect(explorer.requests, isEmpty, reason: 'แคชยังไม่หมด TTL');
      expect(list!.tokens.map((t) => t.symbol), ['GOOD', 'LOGO']);
      expect(list.byAddress(_hex(4))!.logoUri, isNull);
    });
  });

  group('load — เพดาน', () {
    test('หน้าไม่จบ → หยุดที่ 10 หน้า · หน้าเดิมวนซ้ำ → หยุดทันที', () async {
      var n = 0;
      explorer.pageOverride = () {
        n++;
        return http.Response(
          jsonEncode({
            'items': [
              {'address': _hex(n), 'name': 'P$n', 'symbol': 'P$n', 'type': 'ERC-20'},
            ],
            'next_page_params': {'items_count': n},
          }),
          200,
        );
      };
      final list = await ExplorerTokenService.load();
      expect(explorer.pageRequests, ExplorerTokenService.maxPages);
      expect(list!.tokens, hasLength(ExplorerTokenService.maxPages));

      SharedPreferences.setMockInitialValues({});
      restartApp();
      explorer.requests.clear();
      explorer.pageOverride = () => http.Response(
            jsonEncode({
              'items': [
                {'address': _hex(1), 'name': 'Loop', 'symbol': 'LOOP', 'type': 'ERC-20'},
              ],
              'next_page_params': {'items_count': 1},
            }),
            200,
          );
      expect((await ExplorerTokenService.load())!.tokens, hasLength(1));
      expect(explorer.pageRequests, 2, reason: 'หน้าแรก + หน้าที่ซ้ำ แล้วหยุด');
    });

    test('ไม่เกิน 300 เหรียญ', () async {
      for (var i = 1; i <= 350; i++) {
        explorer.add(_hex(i));
      }
      explorer.addressDelay = Duration.zero;
      final list = await ExplorerTokenService.load();
      expect(list!.tokens, hasLength(ExplorerTokenService.maxTokens));
      expect(explorer.addressRequests, ExplorerTokenService.maxTokens);
    });
  });

  // ทุกพูลชื่อ "TPIX LP Token" — ธง dexPool มาจากการพิสูจน์บนเชนเท่านั้น
  group('load — พูล TPIX DEX', () {
    late Map<String, bool?> proofs;
    late List<String> asked;

    void addLp(String addr) =>
        explorer.add(addr, name: ExplorerTokenService.lpName, symbol: ExplorerTokenService.lpSymbol);
    bool pool(String addr) => ExplorerTokenService.current!.byAddress(addr)!.dexPool;

    setUp(() {
      proofs = {};
      asked = [];
      ExplorerTokenService.poolProver = (a) async {
        asked.add(a.toLowerCase());
        return proofs[a.toLowerCase()];
      };
    });

    test('พิสูจน์เฉพาะตัวที่หน้าตาเป็นพูล · พูลจริงได้ธง · ของปลอมชื่อเดียวกันไม่ได้', () async {
      addLp(_hex(1));
      addLp(_hex(2));
      explorer
        ..add(_hex(3), name: ExplorerTokenService.lpName, symbol: 'LP2') // ชื่อตรงแต่สัญลักษณ์ไม่ตรง
        ..add(_hex(4), symbol: 'AAA');
      proofs[_hex(1)] = true;
      proofs[_hex(2)] = false;
      await ExplorerTokenService.load();
      expect(asked..sort(), [_hex(1), _hex(2)]);
      expect([for (var i = 1; i <= 4; i++) pool(_hex(i))], [true, false, false, false]);
    });

    test('ตรวจไม่ได้ (null / throw / หมดเวลา) → ใช้ผลรอบก่อน · ไม่เคยผ่าน = ไม่ใช่พูล', () async {
      ExplorerTokenService.timeout = const Duration(milliseconds: 50);
      addLp(_hex(1));
      addLp(_hex(2));
      proofs[_hex(1)] = true;
      await ExplorerTokenService.load();
      expect([pool(_hex(1)), pool(_hex(2))], [true, false]);

      for (final broken in <Future<bool?> Function(String)>[
        (_) async => null,
        (_) async => throw StateError('rpc'),
        (_) => Completer<bool?>().future, // ค้าง
      ]) {
        ExplorerTokenService.poolProver = broken;
        now = now.add(const Duration(hours: 2));
        await ExplorerTokenService.load();
        expect([pool(_hex(1)), pool(_hex(2))], [true, false]);
      }
    });

    test('เชนตอบชัดว่าไม่ใช่พูล → ตัดธงทันทีแม้เคยผ่าน', () async {
      addLp(_hex(1));
      proofs[_hex(1)] = true;
      await ExplorerTokenService.load();
      expect(pool(_hex(1)), isTrue);
      proofs[_hex(1)] = false;
      now = now.add(const Duration(hours: 2));
      await ExplorerTokenService.load();
      expect(pool(_hex(1)), isFalse);
    });

    test('ธงอยู่ในแคช (เปิดแอปใหม่ได้ทันทีไม่ต้องรอเชน) · แคชถูกแก้ให้เหรียญอื่นเป็นพูลไม่ได้', () async {
      addLp(_hex(1));
      proofs[_hex(1)] = true;
      await ExplorerTokenService.load();
      restartApp();
      ExplorerTokenService.poolProver = (_) async => fail('ภายใน TTL ต้องไม่ถามเชน');
      expect((await ExplorerTokenService.load())!.byAddress(_hex(1))!.dexPool, isTrue);

      SharedPreferences.setMockInitialValues({
        'explorer_tokens_4289_v1': jsonEncode({
          'listAt': now.millisecondsSinceEpoch,
          'fetchedAt': now.millisecondsSinceEpoch,
          'tokens': [
            {'address': _hex(5), 'name': 'Tether USD', 'symbol': 'USDT', 'pool': true, 'checkedAt': now.millisecondsSinceEpoch},
          ],
        }),
      });
      restartApp();
      ExplorerTokenService.poolProver = (_) async => fail('ภายใน TTL ต้องไม่ถามเชน');
      expect((await ExplorerTokenService.load())!.byAddress(_hex(5))!.dexPool, isFalse);
    });

    test('ถามเชนไม่เกิน 20 ตัวต่อรอบ — ตัวที่เกินใช้ผลรอบก่อน', () async {
      for (var i = 1; i <= 25; i++) {
        addLp(_hex(i));
        proofs[_hex(i)] = true;
      }
      explorer.addressDelay = Duration.zero;
      await ExplorerTokenService.load();
      expect(asked, hasLength(ExplorerTokenService.maxPoolChecks));
      final flagged = ExplorerTokenService.current!.tokens.where((t) => t.dexPool).length;
      expect(flagged, ExplorerTokenService.maxPoolChecks);
    });
  });
}
