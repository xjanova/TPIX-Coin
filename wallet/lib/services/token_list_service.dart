import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/token_list.dart';
import 'wallet_service.dart';

/// รายการโทเค็นที่ยืนยันแล้วของ TPIX Chain (https://tpix.online/tokenlist.json)
///
/// - มีแต่โทเค็นที่แอดมินอนุมัติ → ใช้ตัดสินว่า "ยืนยันแล้ว" + ใช้โลโก้/ชื่อจากที่นี่
/// - ทุกค่าตรวจก่อนใช้ (chainId 4289, ที่อยู่, ทศนิยม 0..36, ความยาวชื่อ/สัญลักษณ์,
///   โลโก้ https เท่านั้น, จำนวนไม่เกิน [maxTokens]) — ตัวที่ผิดรูปถูกข้ามทิ้ง ไม่เดา
/// - แคชลงเครื่อง [ttl] ชั่วโมง — ออฟไลน์ก็ใช้ชุดที่แคชไว้ได้
/// - ดึงไม่ได้ (404 / หมดเวลา / JSON เสีย) → คงชุดเดิมไว้ ถ้าไม่มีเลย = null
///   ผู้เรียกถอยไปใช้ของเดิม (คู่เทรด DEX + ค่าในตัวแอป)
/// - ไม่มีเมธอดไหน throw และไม่มีอะไรต้องรอเน็ตก่อนวาดหน้าจอ ([current] อ่านได้ทันที)
class TokenListService {
  static const url = 'https://tpix.online/tokenlist.json';
  static const chainId = 4289;

  /// อายุของชุดที่ดึงมา — เกินนี้ค่อยดึงใหม่ (ระหว่างนั้นใช้ชุดเดิมไปก่อน)
  static const ttl = Duration(hours: 6);

  /// ดึงไม่สำเร็จแล้ว รอเท่านี้ก่อนลองใหม่ — กันยิงเซิร์ฟเวอร์ถี่ตอนเน็ตไม่ดี
  static const retryAfterFailure = Duration(minutes: 5);

  static const maxTokens = 1000;
  static const maxBodyBytes = 1024 * 1024; // 1000 โทเค็น ≈ 300KB
  static const maxSymbolLength = 20;
  static const maxNameLength = 60;
  static const maxLogoUrlLength = 512;
  static const _prefsKey = 'tokenlist_4289_v1';

  /// เทสต์เปลี่ยนเป็น MockClient ได้
  @visibleForTesting
  static http.Client Function() clientFactory = http.Client.new;

  /// เทสต์เลื่อนเวลาได้ (TTL)
  @visibleForTesting
  static DateTime Function() clock = DateTime.now;

  /// เวลารอทั้งหมดต่อการดึงหนึ่งครั้ง (เทสต์ย่อให้สั้นได้)
  @visibleForTesting
  static Duration timeout = const Duration(seconds: 8);

  static TokenList? _current;
  static DateTime? _fetchedAt;
  static DateTime? _lastFailureAt;
  static bool _cacheLoaded = false;
  static Future<TokenList?>? _inflight;

  /// ชุดล่าสุดที่มีในหน่วยความจำ (null = ยังไม่มี / ใช้ไม่ได้) — อ่านได้ทันที ไม่รอเน็ต
  static TokenList? get current => _current;

  /// เวลาที่ดึงชุดปัจจุบันมาจากเซิร์ฟเวอร์ (รวมชุดที่โหลดจากแคช)
  static DateTime? get fetchedAt => _fetchedAt;

  /// โหลดรายการ: แคชในเครื่องก่อน → ถ้าเก่ากว่า [ttl] ค่อยดึงใหม่
  ///
  /// เรียกพร้อมกันหลายที่ = ยิงเน็ตครั้งเดียว · ไม่ throw · คืน [current] หลังโหลด
  static Future<TokenList?> load({bool forceRefresh = false}) {
    final running = _inflight;
    if (running != null) return running;
    final future = _load(forceRefresh);
    _inflight = future;
    return future.whenComplete(() => _inflight = null);
  }

  static Future<TokenList?> _load(bool forceRefresh) async {
    try {
      if (!_cacheLoaded) {
        _cacheLoaded = true;
        await _loadFromCache();
      }
      final now = clock();
      if (!forceRefresh) {
        if (_isWithin(_fetchedAt, now, ttl)) return _current;
        if (_isWithin(_lastFailureAt, now, retryAfterFailure)) return _current;
      }

      final fetched = await _fetch();
      if (fetched != null) {
        _current = fetched;
        _fetchedAt = now;
        _lastFailureAt = null;
        await _saveToCache(fetched, now);
      } else {
        _lastFailureAt = now;
      }
    } catch (e) {
      debugPrint('TokenListService.load: ${e.runtimeType}');
    }
    return _current;
  }

  /// [at] อยู่ในช่วง [window] ก่อน [now] — เวลาในอนาคต (นาฬิกาเครื่องถูกย้อน) = ไม่นับ
  static bool _isWithin(DateTime? at, DateTime now, Duration window) {
    if (at == null) return false;
    final age = now.difference(at);
    return !age.isNegative && age < window;
  }

  static Future<TokenList?> _fetch() async {
    final client = clientFactory();
    try {
      final bytes = await _readCapped(client).timeout(timeout);
      if (bytes == null) return null;
      return parse(utf8.decode(bytes));
    } catch (e) {
      // 404 / หมดเวลา / ไม่ใช่ UTF-8 — ถอยไปใช้ชุดเดิม
      debugPrint('TokenListService.fetch: ${e.runtimeType}');
      return null;
    } finally {
      client.close();
    }
  }

  /// อ่าน body ไม่เกิน [maxBodyBytes] — เกินก็ตัดทิ้งทั้งก้อน (กันไฟล์ใหญ่ผิดปกติ)
  static Future<List<int>?> _readCapped(http.Client client) async {
    final req = http.Request('GET', Uri.parse(url))
      ..headers.addAll(const {
        'Accept': 'application/json',
        'User-Agent': 'TPIX-Wallet (Flutter)',
      });
    final res = await client.send(req);
    if (res.statusCode != 200) {
      debugPrint('TokenListService.fetch: HTTP ${res.statusCode}');
      return null;
    }
    final declared = res.contentLength;
    if (declared != null && declared > maxBodyBytes) return null;
    final bytes = <int>[];
    await for (final chunk in res.stream) {
      bytes.addAll(chunk);
      if (bytes.length > maxBodyBytes) return null;
    }
    return bytes;
  }

  // ================================================================
  // ตรวจ/แปลงข้อมูล (pure — เทสต์ได้)
  // ================================================================

  /// แปลง body ของ tokenlist.json — โครงสร้างผิด = null, รายการที่ผิดรูป = ข้าม
  @visibleForTesting
  static TokenList? parse(String body) {
    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      return null;
    }
    return fromJson(decoded);
  }

  /// ตรวจโครงสร้างที่ decode แล้ว (ใช้ทั้งข้อมูลจากเน็ตและจากแคช — แคชก็ตรวจซ้ำ)
  static TokenList? fromJson(Object? decoded) {
    if (decoded is! Map) return null;
    final rawTokens = decoded['tokens'];
    if (rawTokens is! List) return null;

    final seen = <String>{};
    final tokens = <TokenListEntry>[];
    for (final raw in rawTokens) {
      if (tokens.length >= maxTokens) break;
      final entry = _parseEntry(raw);
      if (entry == null) continue;
      if (!seen.add(entry.key)) continue; // ที่อยู่ซ้ำ → ตัวแรกชนะ
      tokens.add(entry);
    }

    final ts = decoded['timestamp'];
    return TokenList(
      name: cleanText(decoded['name'], 100) ?? 'TPIX Token List',
      timestamp: ts is String && ts.length <= 64 ? ts : null,
      version: _parseVersion(decoded['version']),
      tokens: tokens,
    );
  }

  static TokenListEntry? _parseEntry(Object? raw) {
    if (raw is! Map) return null;
    if (raw['chainId'] != chainId) return null;

    final address = raw['address'];
    if (address is! String || !isValidListAddress(address)) return null;

    final decimals = raw['decimals'];
    if (decimals is! int || decimals < 0 || decimals > 36) return null;

    final symbol = cleanText(raw['symbol'], maxSymbolLength);
    final name = cleanText(raw['name'], maxNameLength);
    if (symbol == null || name == null) return null;

    return TokenListEntry(
      chainId: chainId,
      address: address,
      name: name,
      symbol: symbol,
      decimals: decimals,
      // โลโก้ใช้ไม่ได้ ≠ โทเค็นใช้ไม่ได้ — ทิ้งแค่โลโก้
      logoUri: cleanLogoUrl(raw['logoURI']),
    );
  }

  static TokenListVersion? _parseVersion(Object? v) {
    if (v is! Map) return null;
    final major = v['major'], minor = v['minor'], patch = v['patch'];
    if (major is! int || minor is! int || patch is! int) return null;
    if (major < 0 || minor < 0 || patch < 0) return null;
    return TokenListVersion(major, minor, patch);
  }

  /// ที่อยู่ 0x + 40 hex, ไม่ใช่ 0x000…0, ตัวพิมพ์ผสมต้องตรง checksum (EIP-55)
  static bool isValidListAddress(String address) {
    if (!WalletService.isValidAddress(address)) return false;
    return address.toLowerCase() != '0x0000000000000000000000000000000000000000';
  }

  /// อักขระควบคุม / zero-width / สลับทิศทางข้อความ — ใช้ปลอมชื่อให้ดูเหมือนตัวอื่นได้
  static final _unsafeChars = RegExp(
    r'[\u0000-\u001F\u007F-\u009F\u00AD\u200B-\u200F\u202A-\u202E\u2060-\u2064\u2066-\u2069\uFEFF]',
  );

  /// ข้อความที่ปลอดภัยสำหรับแสดงผล: ตัดช่องว่างหัวท้าย, ไม่ว่าง, ไม่ยาวเกิน,
  /// ไม่มีอักขระซ่อน — ไม่ผ่าน = null (ไม่ตัดให้สั้นลงเอง เพราะจะได้ชื่อที่ไม่มีใครตั้ง)
  static String? cleanText(Object? value, int maxLength) {
    if (value is! String) return null;
    final s = value.trim();
    if (s.isEmpty || s.runes.length > maxLength) return null;
    if (_unsafeChars.hasMatch(s)) return null;
    return s;
  }

  /// ทำความสะอาดชื่อ/สัญลักษณ์ที่อ่านจากสัญญา (ใครเขียนสัญญาก็ตั้งได้ตามใจ):
  /// ตัดอักขระซ่อน/สลับทิศ, ยุบช่องว่าง, ตัดให้ไม่เกิน [maxLength] ตัวอักษร
  /// เหลือว่าง = null — ต่างจาก [cleanText] ตรงที่ "แก้ให้ปลอดภัย" แทนการปัดทิ้ง
  /// เพราะข้อมูลบนเชนคือของจริงที่ต้องแสดง
  static String? sanitizeOnChainText(String? value, int maxLength) {
    if (value == null) return null;
    final s = value
        .replaceAll(_unsafeChars, '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (s.isEmpty) return null;
    final runes = s.runes.toList();
    if (runes.length <= maxLength) return s;
    return String.fromCharCodes(runes.take(maxLength)).trim();
  }

  /// โลโก้ต้องเป็น https และมีโฮสต์ — อย่างอื่น (http, ipfs://, data:) = null
  static String? cleanLogoUrl(Object? value) {
    if (value is! String) return null;
    final s = value.trim();
    if (s.isEmpty || s.length > maxLogoUrlLength) return null;
    final uri = Uri.tryParse(s);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return null;
    if (uri.userInfo.isNotEmpty) return null; // https://user:pass@… ไม่ใช่ลิงก์โลโก้
    return uri.toString();
  }

  // ================================================================
  // แคชในเครื่อง
  // ================================================================

  static Future<void> _loadFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final at = decoded['fetchedAt'];
      // ข้อมูลในเครื่องแก้ได้ (เครื่องที่ root) → ผ่านตัวตรวจชุดเดียวกับข้อมูลจากเน็ต
      final list = fromJson(decoded['list']);
      if (list == null || at is! int) return;
      _current ??= list;
      _fetchedAt ??= DateTime.fromMillisecondsSinceEpoch(at);
    } catch (e) {
      debugPrint('TokenListService.cache: ${e.runtimeType}');
    }
  }

  static Future<void> _saveToCache(TokenList list, DateTime at) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _prefsKey,
        jsonEncode({'fetchedAt': at.millisecondsSinceEpoch, 'list': list.toJson()}),
      );
    } catch (e) {
      debugPrint('TokenListService.saveCache: ${e.runtimeType}');
    }
  }

  /// ล้างสถานะในหน่วยความจำ (เทสต์ — จำลองการเปิดแอปใหม่)
  @visibleForTesting
  static void resetForTest() {
    _current = null;
    _fetchedAt = null;
    _lastFailureAt = null;
    _cacheLoaded = false;
    _inflight = null;
    clientFactory = http.Client.new;
    clock = DateTime.now;
    timeout = const Duration(seconds: 8);
  }

  /// ใส่รายการตรงๆ (เทสต์วิดเจ็ต — ไม่แตะเน็ต/ดิสก์)
  @visibleForTesting
  static void setForTest(TokenList? list, {DateTime? fetchedAt}) {
    _current = list;
    _fetchedAt = fetchedAt ?? clock();
    _cacheLoaded = true;
  }
}
