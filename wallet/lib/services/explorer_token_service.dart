import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/explorer_token_list.dart';
import 'token_list_service.dart';
import 'tpix_dex_service.dart';

/// ผลตรวจ verify ของสัญญาหนึ่งตัว
enum ExplorerVerdict {
  /// is_verified=true · is_scam=false · is_contract=true
  pass,

  /// explorer ตอบชัดว่าไม่ผ่าน (ไม่ verify / scam / ไม่ใช่สัญญา / 404) → ตัดทิ้งทันที
  fail,

  /// ตรวจไม่ได้ (ล่ม / หมดเวลา / JSON เสีย / ฟิลด์หาย) → ไม่ผ่าน แต่ตัวที่เคยผ่านใช้ต่อได้จนหมดอายุ
  unknown,
}

/// หน้าหนึ่งของ /api/v2/tokens ที่ตรวจแล้ว
class ExplorerTokenPage {
  final List<ExplorerToken> items;

  /// พารามิเตอร์หน้าถัดไป — null = หน้าสุดท้าย (หรือพารามิเตอร์ผิดรูป → หยุดแค่นี้)
  final Map<String, String>? next;

  const ExplorerTokenPage(this.items, this.next);
}

/// รายการเหรียญที่ยืนยันแล้วจาก https://explorer.tpix.online/tokens
/// — แหล่งเดียวของรายการ "โทเค็นบน TPIX Chain" ในหน้าเพิ่มโทเค็น
///
/// กฎ: อยู่ใน /api/v2/tokens (ไล่ครบทุกหน้า, ERC-20) และ /api/v2/addresses/{ที่อยู่}
///     ตอบ is_verified=true, is_scam=false, is_contract=true — ขาดข้อใด = ไม่ขึ้นรายการ
///
/// - fail closed: ตรวจไม่ได้ ≠ ผ่าน · ตัวที่เคยผ่านใช้ต่อได้ไม่เกิน [maxAge] นับจากที่ตรวจผ่านล่าสุด
///   ตัวที่ explorer ตอบชัดว่าไม่ผ่าน → ตัดทิ้งทันทีแม้เคยผ่าน
/// - ดึงหน้า /tokens หน้าใดไม่ได้ → ไม่แตะชุดเดิม (ไม่รู้ว่าครบไหม)
/// - ค่าจาก explorer เชื่อไม่ได้: ตรวจที่อยู่ (checksum), ชื่อ/สัญลักษณ์ผ่านตัวทำความสะอาดเดียวกับ
///   ข้อมูลบนเชน, โลโก้ https เท่านั้น, ไม่เก็บทศนิยม (ตอนเพิ่มอ่านจากสัญญาเสมอ)
/// - พูล TPIX DEX ชื่อ "TPIX LP Token" ซ้ำกันทุกพูล → พิสูจน์บนเชนด้วย [poolProver] ได้ธง dexPool
///   (ไม่โดนนับเป็นของเลียนแบบกันเอง) · ตรวจไม่ได้ = ใช้ผลรอบก่อน ไม่เคยผ่าน = ไม่ใช่พูล
/// - จำกัด [maxPages] หน้า · [maxTokens] เหรียญ · ขนาด body · ถามรายสัญญาพร้อมกัน [concurrency] ตัว
/// - แคชลงเครื่อง ภายใน [ttl] ไม่ยิง explorer ซ้ำ · ไม่มีเมธอดไหน throw
class ExplorerTokenService {
  static const baseUrl = 'https://explorer.tpix.online';

  /// อายุของชุดที่ดึงครบ — ภายในนี้เปิดหน้าเพิ่มโทเค็นกี่ครั้งก็ไม่ยิง explorer
  static const ttl = Duration(hours: 1);

  /// ตัวที่ตรวจผ่านแล้ว ใช้ต่อได้นานเท่านี้ตอน explorer ใช้ไม่ได้ — เกินนี้ถือว่าไม่ผ่าน
  static const maxAge = Duration(hours: 24);

  /// ดึงไม่สำเร็จแล้ว รอเท่านี้ก่อนลองเองอีก (ปุ่มลองใหม่ข้ามได้)
  static const retryAfterFailure = Duration(minutes: 2);

  /// กดลองใหม่รัวๆ → ยิงจริงไม่ถี่กว่านี้
  static const minForceInterval = Duration(seconds: 5);

  static const maxPages = 10; // หน้าละ 50 → 500 เหรียญ
  static const maxTokens = 300;
  static const concurrency = 4;
  static const maxPageBytes = 512 * 1024; // 50 เหรียญ ≈ 20KB
  static const maxAddressBytes = 64 * 1024; // ≈ 1KB

  /// เท่ากับ TokenService.fetchTokenInfo — ชื่อจาก explorer เทียบกับชื่อบนสัญญาได้ตรงๆ
  static const maxNameLength = 64;
  static const maxSymbolLength = 32;

  /// ชื่อ/สัญลักษณ์ตายตัวของพูล TPIX DEX (contracts/src/dex/amm/TPIXDEXPair.sol) — ตรงทั้งคู่จึงพิสูจน์บนเชน
  static const lpName = 'TPIX LP Token';
  static const lpSymbol = 'TPIX-LP';

  /// พิสูจน์พูลได้ไม่เกินเท่านี้ต่อรอบ (ตัวละ 3 eth_call) — ที่เกินใช้ผลรอบก่อน
  static const maxPoolChecks = 20;

  /// พิสูจน์ว่าเป็นพูลของ TPIX DEX บนเชน — เทสต์เปลี่ยนได้
  @visibleForTesting
  static Future<bool?> Function(String address) poolProver = TpixDexService.isDexPool;

  static const _prefsKey = 'explorer_tokens_4289_v1';
  static final _epoch = DateTime.fromMillisecondsSinceEpoch(0);

  /// เทสต์เปลี่ยนเป็น MockClient ได้
  @visibleForTesting
  static http.Client Function() clientFactory = http.Client.new;

  /// เทสต์เลื่อนเวลาได้ (TTL / อายุ)
  @visibleForTesting
  static DateTime Function() clock = DateTime.now;

  /// เวลารอต่อคำขอ
  @visibleForTesting
  static Duration timeout = const Duration(seconds: 8);

  /// เวลารวมทั้งรอบ (ไล่หน้า + ถามรายสัญญา) — ไล่หน้าไม่ทัน = ดึงไม่สำเร็จ
  /// ถามรายสัญญาไม่ทัน = ตัวที่เหลือตรวจไม่ได้
  @visibleForTesting
  static Duration budget = const Duration(seconds: 45);

  static ExplorerTokenList? _all; // รวมตัวที่หมดอายุแล้ว (กรองตอนอ่าน)
  static DateTime? _listAt; // ดึงหน้า /tokens ครบล่าสุด
  static DateTime? _fetchedAt; // ดึงครบ + ตรวจได้ครบทุกตัวล่าสุด
  static DateTime? _lastAttemptAt;
  static DateTime? _lastFailureAt;
  static bool _stale = false;
  static bool _cacheLoaded = false;
  static Future<ExplorerTokenList?>? _inflight;

  // ชุดที่ใช้ได้ (กรองอายุแล้ว) — คำนวณใหม่เมื่อชุดเปลี่ยนหรือมีตัวหมดอายุ
  static ExplorerTokenList? _usable;
  static ExplorerTokenList? _usableFrom;
  static DateTime? _usableAt;
  static DateTime? _usableUntil;

  /// ชุดที่ใช้ได้ตอนนี้ (ตัดตัวที่หมดอายุแล้ว) — null = ไม่มีชุดที่ใช้ได้ (ต้องบอกผู้ใช้)
  /// อ่านได้ทันที ไม่รอเน็ต
  static ExplorerTokenList? get current {
    final all = _all, listAt = _listAt;
    if (all == null || listAt == null) return null;
    final now = clock();
    if (!_isWithin(listAt, now, maxAge)) return null;
    final until = _usableUntil, at = _usableAt;
    if (!identical(all, _usableFrom) ||
        until == null ||
        at == null ||
        !now.isBefore(until) ||
        now.isBefore(at)) {
      final usable = all.within(now, maxAge);
      var expires = listAt.add(maxAge);
      for (final t in usable.tokens) {
        final e = t.checkedAt.add(maxAge);
        if (e.isBefore(expires)) expires = e;
      }
      // เคยมีแต่หมดอายุหมด = ไม่มีชุดที่ใช้ได้ (ไม่ใช่ "explorer ไม่มีเหรียญ")
      _usable = all.tokens.isNotEmpty && usable.isEmpty ? null : usable;
      _usableFrom = all;
      _usableAt = now;
      _usableUntil = expires;
    }
    return _usable;
  }

  /// ดึงรอบล่าสุดไม่สำเร็จหรือตรวจได้ไม่ครบ — ชุดที่โชว์อาจไม่ล่าสุด
  static bool get isStale => _stale;

  /// กำลังดึงจาก explorer อยู่
  static bool get isLoading => _inflight != null;

  /// โหลดรายการ: แคชในเครื่องก่อน → ถ้าเก่ากว่า [ttl] ค่อยดึงใหม่
  ///
  /// เรียกพร้อมกันหลายที่ = ยิงเน็ตชุดเดียว · ไม่ throw · คืน [current] หลังโหลด
  static Future<ExplorerTokenList?> load({bool forceRefresh = false}) {
    final running = _inflight;
    if (running != null) return running;
    final future = _load(forceRefresh);
    _inflight = future;
    return future.whenComplete(() => _inflight = null);
  }

  static Future<ExplorerTokenList?> _load(bool forceRefresh) async {
    try {
      if (!_cacheLoaded) {
        _cacheLoaded = true;
        await _loadFromCache();
      }
      final now = clock();
      if (forceRefresh) {
        if (_isWithin(_lastAttemptAt, now, minForceInterval)) return current;
      } else {
        if (_isWithin(_fetchedAt, now, ttl)) return current;
        if (_isWithin(_lastFailureAt, now, retryAfterFailure)) return current;
      }
      _lastAttemptAt = now;
      await _refresh(now);
    } catch (e) {
      debugPrint('ExplorerTokenService.load: ${e.runtimeType}');
    }
    return current;
  }

  /// [at] อยู่ในช่วง [window] ก่อน [now] — เวลาในอนาคต (นาฬิกาเครื่องถูกย้อน) = ไม่นับ
  static bool _isWithin(DateTime? at, DateTime now, Duration window) {
    if (at == null) return false;
    final age = now.difference(at);
    return !age.isNegative && age < window;
  }

  static Future<void> _refresh(DateTime now) async {
    final client = clientFactory();
    final watch = Stopwatch()..start();
    try {
      final candidates = await _fetchAllPages(client, watch);
      if (candidates == null) {
        // หน้าใดหน้าหนึ่งดึงไม่ได้ → คงชุดเดิม (แต่ละตัวหมดอายุตามเวลาที่ตรวจผ่าน)
        _lastFailureAt = now;
        _stale = true;
        return;
      }
      final verdicts = await _checkAll(client, candidates, watch);
      final previous = _all;
      final tokens = <ExplorerToken>[];
      var unknown = 0;
      for (final c in candidates) {
        switch (verdicts[c.key] ?? ExplorerVerdict.unknown) {
          case ExplorerVerdict.pass:
            tokens.add(c.copyWith(checkedAt: now));
          case ExplorerVerdict.fail:
            break;
          case ExplorerVerdict.unknown:
            unknown++;
            // เคยผ่าน → ใช้ข้อมูลใหม่แต่อายุเดิม (หมดอายุตามรอบที่ตรวจผ่านจริง) · ไม่เคยผ่าน = ไม่ขึ้น
            final old = previous?.byAddress(c.key);
            if (old != null) tokens.add(c.copyWith(checkedAt: old.checkedAt));
        }
      }
      // พูลของ TPIX DEX ชื่อซ้ำกันทุกพูล — พิสูจน์บนเชนว่าตัวไหนเป็นพูลจริง
      final pools = await _provePools(tokens, previous, watch);
      _all = ExplorerTokenList([for (final t in tokens) t.copyWith(dexPool: pools.contains(t.key))]);
      _listAt = now;
      if (unknown == 0) {
        _fetchedAt = now;
        _lastFailureAt = null;
        _stale = false;
      } else {
        _lastFailureAt = now;
        _stale = true;
      }
      await _saveToCache();
    } finally {
      client.close();
    }
  }

  /// ไล่ทุกหน้า — null = หน้าใดดึงไม่ได้/ผิดรูป/เกินเวลารวม (ไม่รู้ว่าครบไหม)
  /// เพดานหน้า/เหรียญ หรือเซิร์ฟเวอร์ส่งหน้าเดิมวนซ้ำ → หยุด ใช้เท่าที่ได้ (ทุกตัวยังต้องตรวจ verify)
  static Future<List<ExplorerToken>?> _fetchAllPages(http.Client client, Stopwatch watch) async {
    final out = <ExplorerToken>[];
    final seen = <String>{};
    final seenParams = <String>{};
    var params = const <String, String>{};
    for (var page = 0; page < maxPages; page++) {
      if (watch.elapsed >= budget) return null;
      final res = await _get(client, tokensUri(params), maxPageBytes);
      if (res.status != 200 || res.body == null) return null;
      final parsed = parseTokensPage(res.body!);
      if (parsed == null) return null;
      for (final t in parsed.items) {
        if (out.length >= maxTokens) return out;
        if (seen.add(t.key)) out.add(t);
      }
      final next = parsed.next;
      if (next == null) return out;
      final sig = (next.entries.toList()..sort((a, b) => a.key.compareTo(b.key)))
          .map((e) => '${e.key}=${e.value}')
          .join('&');
      if (!seenParams.add(sig)) return out;
      params = next;
    }
    return out;
  }

  /// ที่อยู่ของหน้ารายการ — พารามิเตอร์หน้าถัดไปส่งกลับตามที่ได้ (แบบเดียวกับหน้าเว็บ Blockscout)
  /// แต่ type ล็อกเป็น ERC-20 เสมอ
  @visibleForTesting
  static Uri tokensUri(Map<String, String> params) => Uri.parse('$baseUrl/api/v2/tokens')
      .replace(queryParameters: {...params, 'type': 'ERC-20'});

  /// ถามรายสัญญา พร้อมกันไม่เกิน [concurrency] ตัว · เกิน [budget] แล้วตัวที่เหลือ = ตรวจไม่ได้
  static Future<Map<String, ExplorerVerdict>> _checkAll(
    http.Client client,
    List<ExplorerToken> candidates,
    Stopwatch watch,
  ) async {
    final out = <String, ExplorerVerdict>{};
    var next = 0;
    Future<void> worker() async {
      while (next < candidates.length) {
        final t = candidates[next++];
        out[t.key] = watch.elapsed >= budget ? ExplorerVerdict.unknown : await _check(client, t.address);
      }
    }

    await Future.wait([for (var i = 0; i < concurrency; i++) worker()]);
    return out;
  }

  /// พิสูจน์เฉพาะตัวที่ชื่อ+สัญลักษณ์ตรงกับพูล TPIX DEX · พร้อมกันไม่เกิน [concurrency] ตัว
  /// ตรวจไม่ได้ / เกิน [maxPoolChecks] / เกินเวลารวม → ใช้ผลรอบก่อน (ไม่เคยพิสูจน์ผ่าน = ไม่ใช่พูล)
  /// เชนตอบชัดว่าไม่ใช่ → ไม่ใช่ทันทีแม้เคยผ่าน
  static Future<Set<String>> _provePools(
    List<ExplorerToken> tokens,
    ExplorerTokenList? previous,
    Stopwatch watch,
  ) async {
    final candidates = tokens.where(looksLikePool).toList();
    final out = <String>{};
    var next = 0;
    Future<void> worker() async {
      while (next < candidates.length) {
        final i = next++;
        final t = candidates[i];
        bool? proof;
        if (i < maxPoolChecks && watch.elapsed < budget) {
          try {
            proof = await poolProver(t.address).timeout(timeout * 3);
          } catch (e) {
            debugPrint('ExplorerTokenService.pool: ${e.runtimeType}');
          }
        }
        if (proof ?? previous?.byAddress(t.key)?.dexPool ?? false) out.add(t.key);
      }
    }

    await Future.wait([for (var i = 0; i < concurrency; i++) worker()]);
    return out;
  }

  /// ชื่อ+สัญลักษณ์ตรงกับพูล TPIX DEX — แค่ "หน้าตา" ยังไม่ใช่หลักฐาน (ต้องผ่าน [poolProver])
  static bool looksLikePool(ExplorerToken t) => t.name == lpName && t.symbol == lpSymbol;

  static Future<ExplorerVerdict> _check(http.Client client, String address) async {
    final res = await _get(client, Uri.parse('$baseUrl/api/v2/addresses/$address'), maxAddressBytes);
    if (res.status == 404) return ExplorerVerdict.fail; // explorer ไม่รู้จักที่อยู่นี้
    if (res.status != 200 || res.body == null) return ExplorerVerdict.unknown;
    try {
      return parseAddressCheck(address, jsonDecode(res.body!));
    } on FormatException {
      return ExplorerVerdict.unknown;
    }
  }

  /// GET แบบจำกัดขนาด + หมดเวลา — status 0 = ติดต่อไม่ได้ · body null = อ่านไม่ได้/ใหญ่เกิน
  static Future<({int status, String? body})> _get(http.Client client, Uri uri, int maxBytes) async {
    try {
      return await () async {
        final req = http.Request('GET', uri)
          ..headers.addAll(const {
            'Accept': 'application/json',
            'User-Agent': 'TPIX-Wallet (Flutter)',
          });
        final res = await client.send(req);
        if (res.statusCode != 200) return (status: res.statusCode, body: null);
        final declared = res.contentLength;
        if (declared != null && declared > maxBytes) return (status: 200, body: null);
        final bytes = <int>[];
        await for (final chunk in res.stream) {
          bytes.addAll(chunk);
          if (bytes.length > maxBytes) return (status: 200, body: null);
        }
        return (status: 200, body: utf8.decode(bytes));
      }()
          .timeout(timeout);
    } catch (e) {
      // หมดเวลา / เน็ตหลุด / ไม่ใช่ UTF-8
      debugPrint('ExplorerTokenService.get: ${e.runtimeType}');
      return (status: 0, body: null);
    }
  }

  // ================================================================
  // ตรวจ/แปลงข้อมูล (pure — เทสต์ได้)
  // ================================================================

  /// แปลงหน้ารายการ — โครงสร้างผิด = null, เหรียญที่ผิดรูป = ข้าม
  @visibleForTesting
  static ExplorerTokenPage? parseTokensPage(String body) {
    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      return null;
    }
    if (decoded is! Map) return null;
    final rawItems = decoded['items'];
    if (rawItems is! List) return null;
    final items = <ExplorerToken>[];
    for (final raw in rawItems) {
      final t = _parseItem(raw);
      if (t != null) items.add(t);
    }
    return ExplorerTokenPage(items, _parseNext(decoded['next_page_params']));
  }

  static ExplorerToken? _parseItem(Object? raw) {
    if (raw is! Map) return null;
    if (raw['type'] != 'ERC-20') return null; // กระเป๋าเพิ่มได้เฉพาะ ERC-20
    // Blockscout รุ่นใหม่เปลี่ยนชื่อฟิลด์ address → address_hash
    final address = raw['address_hash'] is String ? raw['address_hash'] : raw['address'];
    if (address is! String || !TokenListService.isValidListAddress(address)) return null;
    final name = raw['name'], symbol = raw['symbol'];
    final cleanName = name is String ? TokenListService.sanitizeOnChainText(name, maxNameLength) : null;
    final cleanSymbol =
        symbol is String ? TokenListService.sanitizeOnChainText(symbol, maxSymbolLength) : null;
    if (cleanName == null || cleanSymbol == null) return null;
    return ExplorerToken(
      address: address,
      name: cleanName,
      symbol: cleanSymbol,
      logoUri: TokenListService.cleanLogoUrl(raw['icon_url']),
      checkedAt: _epoch, // ยังไม่ได้ตรวจ verify
    );
  }

  static final _paramKey = RegExp(r'^[a-z0-9_]{1,40}$');

  /// next_page_params: แผนที่ค่าเดี่ยวไม่เกิน 12 คีย์ — ค่า null/false ส่งเป็นข้อความ
  /// (หน้าเว็บ Blockscout ทำแบบเดียวกัน) · ผิดรูป = null (หยุดที่หน้านี้)
  static Map<String, String>? _parseNext(Object? raw) {
    if (raw is! Map || raw.isEmpty || raw.length > 12) return null;
    final out = <String, String>{};
    for (final e in raw.entries) {
      final k = e.key, v = e.value;
      if (k is! String || !_paramKey.hasMatch(k)) return null;
      final String s;
      if (v == null) {
        s = 'null';
      } else if (v is String) {
        s = v;
      } else if (v is num || v is bool) {
        s = '$v';
      } else {
        return null;
      }
      if (s.length > 200) return null;
      out[k] = s;
    }
    return out;
  }

  /// ผลของ /api/v2/addresses/{ที่อยู่}: ต้องเป็นที่อยู่เดียวกัน และมีครบสามฟิลด์เป็น bool
  @visibleForTesting
  static ExplorerVerdict parseAddressCheck(String address, Object? decoded) {
    if (decoded is! Map) return ExplorerVerdict.unknown;
    final hash = decoded['hash'];
    if (hash is! String || hash.toLowerCase() != address.toLowerCase()) return ExplorerVerdict.unknown;
    final verified = decoded['is_verified'];
    final scam = decoded['is_scam'];
    final contract = decoded['is_contract'];
    // ฟิลด์หาย/ผิดชนิด = ตรวจไม่ได้ (ไม่ใช่ผ่าน)
    if (verified is! bool || scam is! bool || contract is! bool) return ExplorerVerdict.unknown;
    return verified && !scam && contract ? ExplorerVerdict.pass : ExplorerVerdict.fail;
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
      final listAt = decoded['listAt'], fetchedAt = decoded['fetchedAt'], rawTokens = decoded['tokens'];
      if (listAt is! int || rawTokens is! List) return;
      final now = clock();
      // ข้อมูลในเครื่องแก้ได้ (เครื่องที่ root) → ผ่านตัวตรวจชุดเดียวกับข้อมูลจากเน็ต
      final seen = <String>{};
      final tokens = <ExplorerToken>[];
      for (final r in rawTokens) {
        if (tokens.length >= maxTokens) break;
        if (r is! Map) continue;
        final t = _parseItem({...r, 'type': 'ERC-20', 'icon_url': r['logo']});
        final at = r['checkedAt'];
        if (t == null || at is! int) continue;
        final checkedAt = DateTime.fromMillisecondsSinceEpoch(at);
        if (checkedAt.isAfter(now)) continue; // เวลาในอนาคต = แคชเพี้ยน
        // ธงพูลรับเฉพาะตัวที่หน้าตาเป็นพูล — แก้แคชให้เหรียญอื่นเป็น "พูล" ไม่ได้
        final pool = r['pool'] == true && looksLikePool(t);
        if (seen.add(t.key)) tokens.add(t.copyWith(checkedAt: checkedAt, dexPool: pool));
      }
      _all ??= ExplorerTokenList(tokens);
      _listAt ??= DateTime.fromMillisecondsSinceEpoch(listAt);
      if (fetchedAt is int) _fetchedAt ??= DateTime.fromMillisecondsSinceEpoch(fetchedAt);
    } catch (e) {
      debugPrint('ExplorerTokenService.cache: ${e.runtimeType}');
    }
  }

  static Future<void> _saveToCache() async {
    final all = _all, listAt = _listAt;
    if (all == null || listAt == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _prefsKey,
        jsonEncode({
          'listAt': listAt.millisecondsSinceEpoch,
          if (_fetchedAt != null) 'fetchedAt': _fetchedAt!.millisecondsSinceEpoch,
          'tokens': all.toJson(),
        }),
      );
    } catch (e) {
      debugPrint('ExplorerTokenService.saveCache: ${e.runtimeType}');
    }
  }

  /// ล้างสถานะในหน่วยความจำ (เทสต์ — จำลองการเปิดแอปใหม่)
  @visibleForTesting
  static void resetForTest() {
    _all = null;
    _listAt = null;
    _fetchedAt = null;
    _lastAttemptAt = null;
    _lastFailureAt = null;
    _stale = false;
    _cacheLoaded = false;
    _inflight = null;
    _usable = null;
    _usableFrom = null;
    _usableAt = null;
    _usableUntil = null;
    clientFactory = http.Client.new;
    poolProver = TpixDexService.isDexPool;
    clock = DateTime.now;
    timeout = const Duration(seconds: 8);
    budget = const Duration(seconds: 45);
  }

  /// ใส่รายการตรงๆ (เทสต์วิดเจ็ต — ไม่แตะเน็ต/ดิสก์) · checkedAt ของแต่ละตัวยังมีผลเรื่องอายุ
  @visibleForTesting
  static void setForTest(ExplorerTokenList? list, {DateTime? fetchedAt}) {
    final at = fetchedAt ?? clock();
    _all = list;
    _listAt = list == null ? null : at;
    _fetchedAt = list == null ? null : at;
    _cacheLoaded = true;
  }
}
