/// TPIX Wallet — เทสต์ราคา/กราฟ: ต้องมาจากเซิร์ฟเวอร์จริงเท่านั้น
///
/// ของเดิม: เรียก /api/price (404 ตลอด) → ถอยไป $0.18 ที่ฮาร์ดโค้ด + สุ่มกราฟเอง
/// ตอนนี้: ดึงไม่ได้ = null (UI โชว์ "ไม่พร้อมใช้งาน") ห้ามมีตัวเลขที่แอปแต่งขึ้น
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tpix_wallet/services/price_service.dart';

/// body จริงจาก https://tpix.online/api/v1/tpix/price (2026-10-11)
const _realPriceBody =
    '{"success":true,"data":{"symbol":"TPIX","name":"TPIX Token","price":0.1,'
    '"change_24h":0,"volume_24h":0,"high_24h":0.1,"low_24h":0.1,"market_cap":21,'
    '"total_supply":7000000000,"circulating_supply":210,'
    '"logo":"https:\\/\\/tpix.online\\/images\\/brand\\/tpix-coin.png","chain_id":4289,'
    '"source":"dex","updated_at":"2026-10-11T10:04:22+07:00"}}';

/// body จริงจาก /api/v1/dex/klines/TPIX-USDT?interval=1d&limit=5 (รูปแบบ 12 ช่องแบบ Binance)
const _realKlinesBody =
    '{"success":true,"data":[[1791590400000,"0.10000000","0.10000000","0.10000000","0.10000000","0.00000000",1791676799999,"0.00000000",0,"0","0","0"],'
    '[1791676800000,"0.10000000","0.12000000","0.09000000","0.11000000","5.00000000",1791763199999,"0.00000000",3,"0","0","0"]]}';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PriceService.reset();
  });

  tearDown(() {
    PriceService.clientFactory = http.Client.new;
  });

  group('parsePriceResponse', () {
    test('อ่าน data.price จาก API จริง', () {
      final q = PriceService.parsePriceResponse(_realPriceBody)!;
      expect(q.price, 0.1);
      expect(q.change24h, 0);
      expect(q.source, 'dex');
    });

    test('ราคาเป็นสตริงตัวเลขก็รับ', () {
      final q = PriceService.parsePriceResponse(
          '{"success":true,"data":{"price":"0.25"}}');
      expect(q!.price, 0.25);
    });

    test('ผิดรูป/ไม่สำเร็จ/ราคา <= 0 → null (ไม่เดา)', () {
      expect(PriceService.parsePriceResponse('<!DOCTYPE html>'), isNull);
      expect(PriceService.parsePriceResponse('{"success":false}'), isNull);
      expect(PriceService.parsePriceResponse('{"success":true,"data":{"price":0}}'), isNull);
      expect(PriceService.parsePriceResponse('{"success":true,"data":{}}'), isNull);
      expect(PriceService.parsePriceResponse('{"price":0.18}'), isNull,
          reason: 'รูปแบบของ endpoint เก่า ไม่ใช่ของใหม่');
    });
  });

  group('parseKlines', () {
    test('ได้ราคาปิดของแต่ละแท่ง เรียงตามเวลา', () {
      final points = PriceService.parseKlines(_realKlinesBody)!;
      expect(points, hasLength(2));
      expect(points.first.price, 0.1);
      expect(points.last.price, 0.11);
      expect(points.first.timestamp, 1791590400);
      expect(PriceService.changePercent(points), closeTo(10.0, 1e-9));
    });

    test('แท่งผิดรูปถูกข้าม ไม่เติมเอง', () {
      final points = PriceService.parseKlines(jsonEncode({
        'success': true,
        'data': [
          [1000, '1', '1', '1', '0'], // ราคา 0
          [2000, '1', '1', '1'], // ช่องไม่ครบ
          'oops',
          [3000, '1', '1', '1', '2.5'],
        ],
      }))!;
      expect(points, hasLength(1));
      expect(points.single.price, 2.5);
    });

    test('ข้อมูลน้อยกว่า 2 จุด → ไม่มี % เปลี่ยนแปลง (ไม่ใช่ 0%)', () {
      expect(PriceService.changePercent(const []), isNull);
      expect(PriceService.changePercent([PricePoint(price: 1, timestamp: 1)]), isNull);
    });

    test('ทั้งก้อนผิดรูป → null', () {
      expect(PriceService.parseKlines('<html>'), isNull);
      expect(PriceService.parseKlines('{"success":true,"data":{}}'), isNull);
    });
  });

  group('fetchPrice', () {
    test('ยิง /api/v1/tpix/price และจำราคาจริงล่าสุดไว้', () async {
      Uri? asked;
      PriceService.clientFactory = () => MockClient((req) async {
            asked = req.url;
            return http.Response(_realPriceBody, 200);
          });
      final q = await PriceService.fetchPrice();
      expect(asked.toString(), 'https://tpix.online/api/v1/tpix/price');
      expect(q!.price, 0.1);
      expect(PriceService.lastQuote!.price, 0.1);

      // เปิดแอปใหม่ → โหลดราคาจริงล่าสุดกลับมาได้
      PriceService.reset();
      await PriceService.loadLastPrice();
      expect(PriceService.lastQuote!.price, 0.1);
    });

    test('API ล่ม → null และไม่แต่งราคาขึ้นมา (ไม่มี 0.18)', () async {
      PriceService.clientFactory =
          () => MockClient((_) async => http.Response('Not Found', 404));
      expect(await PriceService.fetchPrice(), isNull);
      expect(PriceService.lastQuote, isNull);
    });

    test('ดึงได้แล้วรอบหลังล่ม → ราคาเดิมยังอยู่ให้ UI ติดป้ายว่าเก่า', () async {
      PriceService.clientFactory =
          () => MockClient((_) async => http.Response(_realPriceBody, 200));
      await PriceService.fetchPrice();
      PriceService.clientFactory =
          () => MockClient((_) async => throw http.ClientException('offline'));
      expect(await PriceService.fetchPrice(), isNull);
      expect(PriceService.lastQuote!.price, 0.1);
    });
  });

  group('fetchChart', () {
    test('ยิง API แท่งเทียนของ DEX ตามช่วงที่เลือก', () async {
      Uri? asked;
      PriceService.clientFactory = () => MockClient((req) async {
            asked = req.url;
            return http.Response(_realKlinesBody, 200);
          });
      final points = await PriceService.fetchChart(ChartRange.quarter);
      expect(points, hasLength(2));
      expect(asked!.path, '/api/v1/dex/klines/TPIX-USDT');
      expect(asked!.queryParameters, {'interval': '1d', 'limit': '90'});
    });

    test('API ล่ม → null (UI โชว์ "ไม่พร้อมใช้งาน" ไม่วาดกราฟปลอม)', () async {
      PriceService.clientFactory =
          () => MockClient((_) async => http.Response('err', 500));
      expect(await PriceService.fetchChart(ChartRange.day), isNull);
    });
  });
}
