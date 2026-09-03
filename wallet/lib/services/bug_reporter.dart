/// TPIX Wallet — ตัวรายงานบั๊กไปยังระบบกลางของ xman studio
///
/// เจ้าของสั่ง: "ทำระบบ bug report หลังบ้านไว้สำหรับรายงานข้อผิดพลาดจากแอพและโปรแกรม
/// ทั้งหมด เพื่อให้ตรวจสอบได้ทันที ไม่เดา"
///
/// ส่งเข้า https://xman4289.com/api/v1/bug-reports (ระบบกลางที่ทุกแอปในบ้านใช้อยู่แล้ว)
/// ไฟล์นี้เหมือนกับของ TPIX Trade ทุกบรรทัด ต่างกันแค่ product ที่ส่งตอน install()
///
/// สามอย่างที่ทำ:
///  1. จับ error ที่ไม่มีใครดัก (FlutterError / PlatformDispatcher / zone) → รายงาน crash
///  2. breadcrumb — เหตุการณ์สำคัญ 40 รายการล่าสุด แนบไปกับทุกรายงาน
///  3. ผู้ใช้กด "รายงานปัญหา" เอง → ข้อความ + สภาพแอปตอนนั้น + breadcrumb
///
/// ความปลอดภัย: ล้างข้อมูลลับก่อนส่งเสมอ (กุญแจ 64 hex, ลายเซ็น, mnemonic, โทเคน)
/// นี่คือแอปกระเป๋า — ห้ามใส่ mnemonic/private key ลง breadcrumb เด็ดขาด ตัวล้างเป็นแค่กันเหนียว
///
/// Developed by Xman Studio
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BugReporter {
  BugReporter._();
  static final BugReporter I = BugReporter._();

  static const _endpoint = 'https://xman4289.com/api/v1/bug-reports';
  static const _queueKey = 'bug_reports_queue_v1';
  static const _deviceKey = 'bug_reports_device_id_v1';
  static const _maxQueue = 30;
  static const _maxCrumbs = 40;
  static const _dedupeWindow = Duration(hours: 1);
  static const _timeout = Duration(seconds: 10);

  String product = 'tpix-app';
  String version = '0';
  String build = '0';
  String? deviceId;

  bool _installed = false;
  bool _flushing = false;
  final List<String> _crumbs = [];
  final Map<String, DateTime> _recent = {};
  final List<Map<String, dynamic>> _queue = [];

  /// สภาพแอปตอนรายงาน — ผู้เรียกตั้งให้ (ปลดล็อกไหม เชน ที่อยู่ย่อ) ห้ามใส่ความลับ
  Map<String, dynamic> Function()? snapshot;

  bool get installed => _installed;

  Future<void> install({required String product}) async {
    if (_installed) return;
    _installed = true;
    this.product = product;

    try {
      final info = await PackageInfo.fromPlatform();
      version = info.version;
      build = info.buildNumber;
    } catch (_) {}

    try {
      final prefs = await SharedPreferences.getInstance();
      deviceId = prefs.getString(_deviceKey);
      if (deviceId == null || deviceId!.isEmpty) {
        deviceId = _randomId();
        await prefs.setString(_deviceKey, deviceId!);
      }
      final raw = prefs.getString(_queueKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          _queue.addAll(decoded.whereType<Map>().map((m) => Map<String, dynamic>.from(m)));
        }
      }
    } catch (_) {}

    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      previous?.call(details);
      unawaited(reportError(
        details.exception,
        details.stack,
        context: 'FlutterError ${details.library ?? ''}'.trim(),
      ));
    };

    final previousDispatcher = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (error, stack) {
      unawaited(reportError(error, stack, context: 'PlatformDispatcher', fatal: true));
      return previousDispatcher?.call(error, stack) ?? true;
    };

    breadcrumb('app start $product v$version+$build ${_os()}');
    unawaited(flush());
  }

  void breadcrumb(String text) {
    final line = '${DateTime.now().toIso8601String().substring(11, 19)} ${_scrub(text)}';
    _crumbs.add(line.length > 200 ? '${line.substring(0, 200)}…' : line);
    if (_crumbs.length > _maxCrumbs) _crumbs.removeAt(0);
    if (kDebugMode) debugPrint('[crumb] $line');
  }

  List<String> get breadcrumbs => List.unmodifiable(_crumbs);

  Future<void> reportError(
    Object error,
    StackTrace? stack, {
    String? context,
    bool fatal = false,
  }) {
    final message = _scrub(error.toString());
    return report(
      title: '${context != null ? '[$context] ' : ''}${_firstLine(message)}',
      description: message,
      type: 'crash',
      severity: fatal ? 'critical' : 'major',
      priority: fatal ? 'high' : 'medium',
      stack: stack?.toString(),
      metadata: {'context': context, 'fatal': fatal},
    );
  }

  Future<void> report({
    required String title,
    required String description,
    String type = 'bug',
    String severity = 'moderate',
    String priority = 'medium',
    Map<String, dynamic>? metadata,
    String? stack,
    bool dedupe = true,
  }) async {
    if (!_installed) return;

    final cleanTitle = _clip(_scrub(title), 250);
    final cleanDescription = _clip(_scrub(description), 20000);
    final cleanStack = stack == null ? null : _clip(_scrub(stack), 12000);

    final fingerprint = '$type|$cleanTitle|${cleanStack != null ? _firstLine(cleanStack) : ''}';
    if (dedupe) {
      final last = _recent[fingerprint];
      if (last != null && DateTime.now().difference(last) < _dedupeWindow) return;
    }
    _recent[fingerprint] = DateTime.now();

    Map<String, dynamic> state = const {};
    try {
      state = snapshot?.call() ?? const {};
    } catch (_) {}

    final body = <String, dynamic>{
      'product_name': product,
      'product_version': version,
      'app_version': _clip(version, 20),
      'os_version': _clip(_os(), 100),
      'device_id': deviceId,
      'report_type': type,
      'title': cleanTitle,
      'description': cleanStack == null
          ? cleanDescription
          : '$cleanDescription\n\n--- stack ---\n$cleanStack',
      'stack_trace': cleanStack,
      'priority': priority,
      'severity': severity,
      'metadata': {
        'build': build,
        'platform': Platform.operatingSystem,
        'state': _scrubMap(state),
        'breadcrumbs': List<String>.from(_crumbs),
        'reported_at': DateTime.now().toIso8601String(),
        ..._scrubMap(metadata ?? const {}),
      },
    };

    _queue.add(body);
    if (_queue.length > _maxQueue) _queue.removeAt(0);
    await _persist();
    unawaited(flush());
  }

  Future<void> flush() async {
    if (_flushing || _queue.isEmpty) return;
    _flushing = true;
    try {
      while (_queue.isNotEmpty) {
        final item = _queue.first;
        final ok = await _send(item);
        if (!ok) break;
        _queue.removeAt(0);
        await _persist();
      }
    } finally {
      _flushing = false;
    }
  }

  Future<bool> _send(Map<String, dynamic> body) async {
    try {
      final res = await http
          .post(
            Uri.parse(_endpoint),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              'User-Agent': '$product/$version ($build)',
            },
            body: jsonEncode(body),
          )
          .timeout(_timeout);
      if (res.statusCode == 201 || res.statusCode == 200) return true;
      if (res.statusCode == 422) {
        debugPrint('BugReporter: rejected ${res.body.length > 200 ? res.body.substring(0, 200) : res.body}');
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('BugReporter.send: ${e.runtimeType}');
      return false;
    }
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_queue.isEmpty) {
        await prefs.remove(_queueKey);
      } else {
        await prefs.setString(_queueKey, jsonEncode(_queue));
      }
    } catch (_) {}
  }

  static final _hex64 = RegExp(r'(?<![0-9a-fA-F])(0x)?[0-9a-fA-F]{64}(?![0-9a-fA-F])');
  static final _hexSig = RegExp(r'0x[0-9a-fA-F]{130}');
  static final _bearer = RegExp(r'(Bearer\s+)[A-Za-z0-9._\-]{8,}', caseSensitive: false);
  static final _mnemonic = RegExp(r'\b(?:[a-z]{3,8}\s+){11,23}[a-z]{3,8}\b');

  static String _scrub(String input) {
    var out = input;
    out = out.replaceAllMapped(_hexSig, (m) => '${m.group(0)!.substring(0, 10)}…[sig]');
    out = out.replaceAll(_hex64, '[secret-64hex]');
    out = out.replaceAllMapped(_bearer, (m) => '${m.group(1)}[token]');
    out = out.replaceAll(_mnemonic, '[mnemonic?]');
    return out;
  }

  static Map<String, dynamic> _scrubMap(Map<String, dynamic> map) {
    final out = <String, dynamic>{};
    map.forEach((k, v) {
      final key = k.toLowerCase();
      if (key.contains('mnemonic') || key.contains('private') || key.contains('secret') || key.contains('pin') || key.contains('seed')) {
        out[k] = '[redacted]';
      } else if (v is String) {
        out[k] = _scrub(v);
      } else if (v is Map) {
        out[k] = _scrubMap(Map<String, dynamic>.from(v));
      } else if (v is List) {
        out[k] = v.map((e) => e is String ? _scrub(e) : e).toList();
      } else {
        out[k] = v;
      }
    });
    return out;
  }

  static String _firstLine(String s) {
    final i = s.indexOf('\n');
    return (i == -1 ? s : s.substring(0, i)).trim();
  }

  static String _clip(String s, int max) => s.length <= max ? s : '${s.substring(0, max)}…';

  static String _os() {
    try {
      return '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';
    } catch (_) {
      return 'unknown';
    }
  }

  static String _randomId() {
    final rng = Random.secure();
    return List<int>.generate(16, (_) => rng.nextInt(256))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }
}
