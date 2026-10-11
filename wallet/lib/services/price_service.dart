import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// A price data point for charting
class PricePoint {
  final double price;
  final int timestamp; // unix seconds (เวลาเปิดแท่ง)
  PricePoint({required this.price, required this.timestamp});
}

/// ราคา TPIX/USD หนึ่งครั้งที่ได้จากเซิร์ฟเวอร์จริง
class PriceQuote {
  final double price;
  final double? change24h;

  /// แหล่งราคาที่เซิร์ฟเวอร์บอก: 'dex' (พูลบนเชน) / 'trades' / 'admin'
  final String? source;

  /// เวลาที่แอปได้ราคานี้มา — ใช้บอกผู้ใช้ว่าราคาเก่าแค่ไหนเมื่อดึงใหม่ไม่ได้
  final DateTime fetchedAt;

  const PriceQuote({
    required this.price,
    this.change24h,
    this.source,
    required this.fetchedAt,
  });

  Map<String, dynamic> toJson() => {
        'price': price,
        'change24h': change24h,
        'source': source,
        'fetchedAt': fetchedAt.millisecondsSinceEpoch,
      };

  static PriceQuote? fromJson(Map<String, dynamic> json) {
    final price = (json['price'] as num?)?.toDouble();
    final at = json['fetchedAt'];
    if (price == null || price <= 0 || at is! int) return null;
    return PriceQuote(
      price: price,
      change24h: (json['change24h'] as num?)?.toDouble(),
      source: json['source'] as String?,
      fetchedAt: DateTime.fromMillisecondsSinceEpoch(at),
    );
  }
}

/// ช่วงเวลาของกราฟ → interval/limit ของ API แท่งเทียน
enum ChartRange {
  day(1, '15m', 96),
  week(7, '1h', 168),
  month(30, '4h', 180),
  quarter(90, '1d', 90);

  const ChartRange(this.days, this.interval, this.limit);
  final int days;
  final String interval;
  final int limit;

  static ChartRange fromDays(int days) =>
      ChartRange.values.firstWhere((r) => r.days == days, orElse: () => ChartRange.week);
}

/// ราคา TPIX/USD + กราฟ — จากเซิร์ฟเวอร์ TPIX เท่านั้น
///
/// ★ ห้ามแต่งราคา/กราฟเองเด็ดขาด
///   ของเดิมเรียก /api/price (ไม่มีอยู่จริง → 404 ตลอด) แล้วถอยไปใช้ $0.18 ที่ฮาร์ดโค้ด
///   + สุ่มกราฟ 7 วันขึ้นมาเองตอนติดตั้งครั้งแรก — ผู้ใช้เห็นราคาและกราฟปลอมมาตลอด
///   ตอนนี้: ดึงไม่ได้ = บอกว่า "ไม่พร้อมใช้งาน" / ใช้ราคาล่าสุดที่ได้จริงพร้อมป้ายว่าไม่อัปเดต
class PriceService {
  static const priceUrl = 'https://tpix.online/api/v1/tpix/price';

  /// แท่งเทียนของคู่ TPIX-USDT บน TPIX DEX — สร้างจากราคาพูลจริงที่บันทึกทุกนาที
  /// (ไม่ใช้ /api/v1/tpix/klines เพราะเมื่อยังไม่มีข้อมูล ปลายทางนั้น "สร้างแท่งราคาคงที่"
  ///  ขึ้นมาแทน ซึ่งก็คือกราฟปลอมอีกแบบ)
  static const klinesUrl = 'https://tpix.online/api/v1/dex/klines/TPIX-USDT';

  static const _prefsKey = 'tpix_price_last_v2';
  static const _timeout = Duration(seconds: 8);

  /// เทสต์เปลี่ยนเป็น MockClient ได้
  @visibleForTesting
  static http.Client Function() clientFactory = http.Client.new;

  static PriceQuote? _last;

  /// ราคาจริงล่าสุดที่เคยได้ (null = ยังไม่เคยได้เลย)
  static PriceQuote? get lastQuote => _last;

  /// แปลง body ของ /api/v1/tpix/price (pure — เทสต์ได้)
  /// รูปแบบ: {success:true, data:{price, change_24h, source, ...}}
  @visibleForTesting
  static PriceQuote? parsePriceResponse(String body, {DateTime? now}) {
    final dynamic decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      return null;
    }
    if (decoded is! Map || decoded['success'] != true) return null;
    final data = decoded['data'];
    if (data is! Map) return null;
    final price = _toDouble(data['price']);
    if (price == null || price <= 0 || !price.isFinite) return null;
    return PriceQuote(
      price: price,
      change24h: _toDouble(data['change_24h']),
      source: data['source'] is String ? data['source'] as String : null,
      fetchedAt: now ?? DateTime.now(),
    );
  }

  static double? _toDouble(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  /// ดึงราคาล่าสุด — คืน null เมื่อดึงไม่ได้ (ผู้เรียกใช้ [lastQuote] + ติดป้ายว่าไม่อัปเดต)
  static Future<PriceQuote?> fetchPrice() async {
    final client = clientFactory();
    try {
      final res = await client.get(Uri.parse(priceUrl), headers: const {
        'Accept': 'application/json',
        'User-Agent': 'TPIX-Wallet (Flutter)',
      }).timeout(_timeout);
      if (res.statusCode != 200) return null;
      final quote = parsePriceResponse(res.body);
      if (quote == null) return null;
      _last = quote;
      await _saveLast(quote);
      return quote;
    } catch (e) {
      debugPrint('PriceService.fetchPrice: ${e.runtimeType}');
      return null;
    } finally {
      client.close();
    }
  }

  static Future<void> _saveLast(PriceQuote quote) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, jsonEncode(quote.toJson()));
    } catch (_) {
      // บันทึกไม่ได้ก็แค่เปิดแอปครั้งหน้าไม่มีราคาเก่าให้โชว์ — ไม่ใช่เรื่องใหญ่
    }
  }

  /// โหลดราคาจริงล่าสุดที่เคยบันทึกไว้ (เรียกตอนเปิดแอป)
  ///
  /// ไม่อ่านตาราง price_history เดิม — ในนั้นมีกราฟที่สุ่มขึ้นมาเองตอนติดตั้ง
  /// และ $0.18 ที่บันทึกทุกครั้งที่ API ล่ม เชื่อถือไม่ได้ทั้งหมด
  static Future<void> loadLastPrice() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null) return;
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) _last = PriceQuote.fromJson(decoded);
    } catch (_) {
      _last = null;
    }
  }

  /// แปลง body ของ API แท่งเทียนเป็นจุดราคาปิด (pure — เทสต์ได้)
  ///
  /// แต่ละแท่ง: [openTimeMs, open, high, low, close, volume, ...]
  /// แท่งที่ผิดรูป/ราคา <= 0 → ข้ามทิ้ง (ไม่เติมเอง) · ทั้งก้อนผิดรูป → null
  @visibleForTesting
  static List<PricePoint>? parseKlines(String body) {
    final dynamic decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      return null;
    }
    if (decoded is! Map || decoded['success'] != true) return null;
    final data = decoded['data'];
    if (data is! List) return null;

    final points = <PricePoint>[];
    for (final row in data) {
      if (row is! List || row.length < 5) continue;
      final openTime = row[0];
      final close = _toDouble(row[4]);
      if (openTime is! num || close == null || close <= 0 || !close.isFinite) continue;
      points.add(PricePoint(price: close, timestamp: openTime.toInt() ~/ 1000));
    }
    points.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return points;
  }

  static final Map<ChartRange, ({List<PricePoint> points, DateTime at})> _chartCache = {};
  static const _chartCacheTtl = Duration(minutes: 1);

  /// กราฟราคาจริงของช่วงที่เลือก — null เมื่อดึงไม่ได้ (UI แสดง "ไม่พร้อมใช้งาน")
  static Future<List<PricePoint>?> fetchChart(ChartRange range) async {
    final cached = _chartCache[range];
    if (cached != null && DateTime.now().difference(cached.at) < _chartCacheTtl) {
      return cached.points;
    }
    final client = clientFactory();
    try {
      final uri = Uri.parse(klinesUrl).replace(queryParameters: {
        'interval': range.interval,
        'limit': '${range.limit}',
      });
      final res = await client.get(uri, headers: const {
        'Accept': 'application/json',
        'User-Agent': 'TPIX-Wallet (Flutter)',
      }).timeout(_timeout);
      if (res.statusCode != 200) return null;
      final points = parseKlines(res.body);
      if (points == null) return null;
      _chartCache[range] = (points: points, at: DateTime.now());
      return points;
    } catch (e) {
      debugPrint('PriceService.fetchChart: ${e.runtimeType}');
      return null;
    } finally {
      client.close();
    }
  }

  /// % เปลี่ยนแปลงจากจุดแรกถึงจุดสุดท้ายของกราฟ — ข้อมูลไม่พอ = null (ไม่ใช่ 0%)
  static double? changePercent(List<PricePoint> points) {
    if (points.length < 2) return null;
    final first = points.first.price;
    if (first <= 0) return null;
    return (points.last.price - first) / first * 100;
  }

  /// ล้างสถานะ (เทสต์)
  @visibleForTesting
  static void reset() {
    _last = null;
    _chartCache.clear();
  }
}
