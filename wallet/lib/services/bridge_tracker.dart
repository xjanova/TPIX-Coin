/// TPIX Wallet — ติดตามรายการของสะพาน (เก็บในเครื่อง + ถามสถานะเป็นรอบ)
///
/// แบบเดียวกับรายการใน localStorage ของหน้าเว็บ:
///   - ส่งแล้วจด tx hash ทันที → ปิดหน้า/ปิดแอปแล้วกลับมาก็ติดตามต่อได้
///   - ถามเซิร์ฟเวอร์ทุก 10 วินาทีเฉพาะรายการที่ยังไม่จบ · จบหมด = หยุดตั้งเวลา
///   - สถานะล่าสุดเก็บลงเครื่องด้วย — รายการที่จบแล้วไม่ต้องถามซ้ำทุกครั้งที่เปิดหน้า
///   - แต่ละรายการผูกกับกระเป๋าที่ส่ง — สลับกระเป๋าแล้วไม่โชว์ของใบอื่น
///   - เซิร์ฟเวอร์จำกัด 30 ครั้ง/นาที → ถามไม่เกิน [maxPerRound] รายการต่อรอบ (วนคิว) · โดน 429 = พักรอบนี้
///
/// เครื่องเก็บข้อมูลเป็นแค่ความสะดวก — แหล่งความจริงคือเชน (ตัวสแกนของเซิร์ฟเวอร์อ่านจากเชนเอง)
///
/// Developed by Xman Studio
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'bridge_rules.dart';
import 'bridge_service.dart';
import 'db_service.dart';

/// ถามสถานะของหนึ่งรายการ (เทสต์ใส่ตัวปลอมได้)
typedef BridgeStatusFetcher = Future<BridgeStatusView> Function(TrackedTransfer entry);

/// อัปเดตสถานะแถวในประวัติธุรกรรมของแอป (ส่งจากแอปนี้) — 'confirmed' / 'failed'
typedef BridgeHistorySync = Future<void> Function(String txHash, String status);

class BridgeTracker extends ChangeNotifier {
  BridgeTracker({
    required this.wtpix,
    BridgeStatusFetcher? fetcher,
    BridgeHistorySync? historySync,
    this.interval = const Duration(seconds: 10),
    this.maxPerRound = 4,
  })  : _fetcher = fetcher ?? (wtpix ? _fetchWtpix : _fetchUsdt),
        _historySync = historySync ?? DbService.updateTxStatus;

  /// true = สะพาน TPIX ⇄ wTPIX · false = สะพาน USDT
  final bool wtpix;
  final Duration interval;
  final int maxPerRound;
  final BridgeStatusFetcher _fetcher;
  final BridgeHistorySync _historySync;

  String get storageKey => wtpix ? 'bridge_tracked_wtpix_v1' : 'bridge_tracked_usdt_v1';
  Set<String> get _kinds => wtpix ? wtpixTrackKinds : usdtTrackKinds;

  static Future<BridgeStatusView> _fetchUsdt(TrackedTransfer e) => e.kind == usdtWithdraw
      ? BridgeService.fetchWithdrawal(e.txHash)
      : BridgeService.fetchStatus(wtpix: false, chainId: e.chainId, txHash: e.txHash);

  static Future<BridgeStatusView> _fetchWtpix(TrackedTransfer e) =>
      BridgeService.fetchStatus(wtpix: true, chainId: e.chainId, txHash: e.txHash);

  List<TrackedTransfer> _all = [];
  String? _owner;
  bool _loaded = false;
  Future<void>? _inflight;
  bool _disposed = false;
  int _cursor = 0;
  Timer? _timer;

  /// แถวประวัติที่อัปเดตไปแล้วในรอบนี้ (กันเขียนฐานข้อมูลซ้ำทุก 10 วินาที)
  final Set<String> _historySynced = {};

  /// รายการที่ผู้ใช้ลบในรอบนี้ — ตอนรวมกับของในเครื่องต้องไม่ดึงกลับมา
  final Set<String> _removed = {};

  bool get loaded => _loaded;

  /// รายการของกระเป๋าที่ใช้อยู่ (ใหม่สุดก่อน)
  List<TrackedTransfer> get entries =>
      _owner == null ? const [] : _all.where((e) => e.owner == _owner).toList();

  bool _done(BridgeStatusView? s) =>
      s != null && (wtpix ? wtpixStateBadge(s.state) : stateBadge(s.state)).done;

  /// ยังมีรายการที่รอผลอยู่ไหม
  bool get hasActive => entries.any((e) => !_done(e.status));

  /// timer ทำงานอยู่ไหม (ไว้ตรวจในเทสต์)
  @visibleForTesting
  bool get isTicking => _timer != null;

  /// อ่านรายการจากเครื่อง — อ่านไม่ได้ = รายการว่าง (ไม่พัง)
  Future<void> load() async {
    String? raw;
    try {
      raw = (await SharedPreferences.getInstance()).getString(storageKey);
    } catch (e) {
      debugPrint('BridgeTracker.load: ${e.runtimeType}');
    }
    if (_disposed) return;
    // รายการที่เพิ่มระหว่างรออ่าน (ไม่น่าเกิด) ต้องไม่หาย
    var merged = decodeTracked(raw, _kinds);
    for (final e in _all.reversed) {
      merged = addTracked(merged, e);
    }
    _all = merged;
    _loaded = true;
    _notify();
    _reschedule();
    if (hasActive) unawaited(pollOnce());
  }

  /// กระเป๋าที่ใช้อยู่ (สลับกระเป๋า = โชว์/ถามเฉพาะของใบใหม่)
  void setOwner(String? owner) {
    final next = owner?.toLowerCase();
    if (next == _owner) return;
    _owner = next;
    _cursor = 0;
    _notify();
    _reschedule();
    if (_loaded && hasActive) unawaited(pollOnce());
  }

  /// เพิ่มรายการ (ซ้ำ = ย้ายขึ้นบนสุด) แล้วถามสถานะทันที
  ///
  /// ★ ธุรกรรมที่ส่งไปแล้วต้องถูกจดเสมอ — แม้ผู้ใช้ออกจากหน้าไประหว่างรอเชนตอบ (ตัวนี้ถูก dispose แล้ว)
  ///   ก็ยังเขียนลงเครื่อง เปิดหน้าใหม่จะติดตามต่อได้
  Future<void> add(TrackedTransfer entry) async {
    if (_disposed) {
      await persistDetached(entry);
      return;
    }
    _removed.remove(entry.key);
    _all = addTracked(_all, entry);
    await _save();
    if (_disposed) return;
    _notify();
    _reschedule();
    unawaited(pollOnce());
  }

  /// จดรายการลงเครื่องโดยไม่ต้องมีหน้าจอเปิดอยู่ (อ่านของเดิม → เพิ่ม → เขียนกลับ)
  Future<void> persistDetached(TrackedTransfer entry) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = addTracked(decodeTracked(prefs.getString(storageKey), _kinds), entry);
      await prefs.setString(storageKey, encodeTracked(list));
    } catch (e) {
      debugPrint('BridgeTracker.persistDetached: ${e.runtimeType}');
    }
  }

  /// ลบออกจากรายการ (แค่เลิกติดตามในเครื่อง — ไม่กระทบเงินบนเชน)
  Future<void> remove(TrackedTransfer entry) async {
    if (_disposed) return;
    _removed.add(entry.key);
    _all = _all.where((e) => e.key != entry.key).toList();
    await _save();
    if (_disposed) return;
    _notify();
    _reschedule();
  }

  /// ถามหนึ่งรอบ — กันซ้อน: กำลังถามอยู่ = รอรอบเดิมให้จบ (กดรีเฟรชระหว่าง timer ทำงาน = ไม่ยิงซ้ำ)
  Future<void> pollOnce() {
    final running = _inflight;
    if (running != null) return running;
    if (_disposed || !_loaded) return Future.value();
    final round = _pollRound();
    _inflight = round;
    return round.whenComplete(() => _inflight = null);
  }

  Future<void> _pollRound() async {
    try {
      final active = entries.where((e) => !_done(e.status)).toList();
      if (active.isEmpty) return;

      // วนคิว — รายการเยอะไม่ทำให้ตัวท้ายๆ ไม่เคยถูกถาม และไม่เกินโควตาของเซิร์ฟเวอร์
      final count = active.length < maxPerRound ? active.length : maxPerRound;
      final start = _cursor % active.length;
      _cursor = start + count;
      final batch = [for (var i = 0; i < count; i++) active[(start + i) % active.length]];

      var changed = false;
      for (final entry in batch) {
        final BridgeStatusView status;
        try {
          status = await _fetcher(entry);
        } on BridgeRateLimitedException {
          break; // โดนจำกัดความถี่ — พักไว้รอบหน้า
        } catch (_) {
          continue; // เน็ต/เซิร์ฟเวอร์สะดุด — ลองใหม่รอบหน้า (ไม่ล้างสถานะเดิม)
        }
        if (_disposed) return;
        // ระหว่างรอ ผู้ใช้อาจลบรายการนี้ไปแล้ว — ไม่ใส่กลับ
        final index = _all.indexWhere((e) => e.key == entry.key);
        if (index < 0) continue;
        _all[index] = _all[index].withStatus(status);
        changed = true;
        if (entry.sentHere) unawaited(_syncHistory(entry.txHash, status.state));
      }
      if (changed) {
        await _save();
        if (_disposed) return;
        _notify();
      }
    } finally {
      _reschedule();
    }
  }

  /// สถานะจากเซิร์ฟเวอร์บอกได้ว่าธุรกรรมต้นทางขุดแล้ว → อัปเดตแถวในประวัติของแอป
  /// (ธุรกรรมบน BSC/ETH ไม่มีตัวซิงก์จาก explorer มาเปลี่ยน "pending" ให้)
  Future<void> _syncHistory(String txHash, String state) async {
    final String status;
    switch (state) {
      case 'pending':
      case 'unknown':
      case 'not_found':
      case 'unsupported_chain':
        return; // ยังไม่รู้ผลบนเชน
      case 'failed':
        status = 'failed';
      default:
        status = 'confirmed'; // ขุดสำเร็จแล้ว (จะนับเป็นรายการสะพานหรือไม่เป็นอีกเรื่อง)
    }
    if (!_historySynced.add('$txHash:$status')) return;
    try {
      await _historySync(txHash, status);
    } catch (e) {
      debugPrint('BridgeTracker.syncHistory: ${e.runtimeType}');
    }
  }

  /// เขียนลงเครื่อง — รวมกับของที่อยู่ในเครื่องก่อน (หน้าจอรอบก่อนที่ถูกปิดไประหว่างส่ง
  /// อาจเพิ่งจดรายการใหม่ผ่าน [persistDetached]) ยกเว้นตัวที่ผู้ใช้ลบในรอบนี้
  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final known = {for (final e in _all) e.key};
      final diskOnly = decodeTracked(prefs.getString(storageKey), _kinds)
          .where((e) => !known.contains(e.key) && !_removed.contains(e.key));
      if (diskOnly.isNotEmpty) {
        _all = ([..._all, ...diskOnly]..sort((a, b) => b.addedAt.compareTo(a.addedAt)))
            .take(trackLimit)
            .toList();
      }
      await prefs.setString(storageKey, encodeTracked(_all));
    } catch (e) {
      // เขียนไม่ได้ก็แค่ไม่จำ — เงินไม่ได้หายไปไหน ตัวสแกนอ่านจากเชนเอง
      debugPrint('BridgeTracker.save: ${e.runtimeType}');
    }
  }

  /// มีรายการรอผล = ตั้งเวลาถาม · จบหมด/ไม่มีรายการ = หยุด
  void _reschedule() {
    if (_disposed) return;
    if (_loaded && hasActive) {
      _timer ??= Timer.periodic(interval, (_) => unawaited(pollOnce()));
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }
}
