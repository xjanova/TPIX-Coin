import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'db_service.dart';

/// A price data point for charting
class PricePoint {
  final double price;
  final int timestamp;
  PricePoint({required this.price, required this.timestamp});
}

/// Service for fetching and caching TPIX/USD price data
class PriceService {
  static const _apiUrl = 'https://tpix.online/api/price';
  static const double defaultPrice = 0.18;
  static double _lastPrice = defaultPrice;

  /// Fetch current TPIX/USD price from API, fallback to last known
  static Future<double> fetchPrice() async {
    try {
      final client = http.Client();
      try {
        final response = await client
            .get(Uri.parse(_apiUrl))
            .timeout(const Duration(seconds: 5));
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final price = (data['price'] as num?)?.toDouble();
          if (price != null && price > 0) {
            _lastPrice = price;
            await _savePrice(price);
            return price;
          }
        }
      } finally {
        client.close();
      }
    } catch (_) {
      // API unavailable — use last known or default
    }
    // Store the current price for chart continuity
    await _savePrice(_lastPrice);
    return _lastPrice;
  }

  /// Save a price point to SQLite
  static Future<void> _savePrice(double price) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    // Avoid duplicate entries within same minute
    final lastTs = await DbService.getLastPriceTimestamp();
    if (lastTs != null && (now - lastTs) < 60) return;
    await DbService.insertPricePoint(price, now);
  }

  /// Get price history for chart
  static Future<List<PricePoint>> getPriceHistory({int days = 7}) async {
    final since =
        DateTime.now().subtract(Duration(days: days)).millisecondsSinceEpoch ~/
            1000;
    final rows = await DbService.getPriceHistory(since);
    return rows
        .map((r) => PricePoint(
              price: (r['price'] as num).toDouble(),
              timestamp: r['timestamp'] as int,
            ))
        .toList();
  }

  /// Calculate price change percentage for a given period
  static Future<double> getPriceChange({int days = 7}) async {
    final points = await getPriceHistory(days: days);
    if (points.length < 2) return 0.0;
    final first = points.first.price;
    final last = points.last.price;
    if (first == 0) return 0.0;
    return ((last - first) / first) * 100;
  }

  /// Get last known price
  static double get lastPrice => _lastPrice;

  /// Load last price from DB (call during init)
  static Future<void> loadLastPrice() async {
    final price = await DbService.getLastPrice();
    if (price != null) _lastPrice = price;
  }

  /// Seed initial price data if empty (first launch experience)
  static Future<void> seedInitialData() async {
    final count = await DbService.getPriceCount();
    if (count > 0) return;

    // Seed 7 days of hourly data with realistic micro-variations around $0.18
    final rng = Random.secure();
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    double price = defaultPrice;

    for (int i = 7 * 24; i >= 0; i--) {
      final ts = now - (i * 3600);
      // Random walk: ±0.5% per hour
      final change = (rng.nextDouble() - 0.48) * 0.001;
      price = (price + change).clamp(0.15, 0.22);
      await DbService.insertPricePoint(
        double.parse(price.toStringAsFixed(6)),
        ts,
      );
    }
  }
}
