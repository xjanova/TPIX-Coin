/// TPIX Wallet — Update Provider
/// ตรวจสอบเวอร์ชันใหม่แบบ background + cache 6 ชม. + จำ version ที่ dismiss
/// Port จาก TPIX Trade update_provider.dart
///
/// Developed by Xman Studio

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/update_service.dart';

class UpdateProvider extends ChangeNotifier {
  final _service = UpdateService();

  UpdateResult? _result;
  bool _isChecking = false;
  DateTime? _lastChecked;
  bool _dismissed = false;

  UpdateResult? get result => _result;
  bool get isChecking => _isChecking;
  bool get hasUpdate => _result?.available == true && !_dismissed;
  DateTime? get lastChecked => _lastChecked;

  UpdateService get service => _service;

  // SharedPreferences keys — prefix tpix_wallet_ เพื่อแยกจาก TPIX Trade
  static const _keyLastChecked = 'tpix_wallet_update_last_checked';
  static const _keyDismissedVersion = 'tpix_wallet_update_dismissed';

  /// ตรวจสอบใน background — silent, ไม่ block UI
  /// เว้น 6 ชั่วโมงระหว่าง check แต่ละครั้ง (ยกเว้น force)
  Future<void> checkInBackground({bool force = false}) async {
    if (_isChecking) return;

    final prefs = await SharedPreferences.getInstance();
    final lastMs = prefs.getInt(_keyLastChecked);
    final now = DateTime.now();

    if (!force && lastMs != null) {
      final last = DateTime.fromMillisecondsSinceEpoch(lastMs);
      if (now.difference(last) < const Duration(hours: 6)) {
        _lastChecked = last;
        return; // ยังไม่ถึงเวลา check ใหม่
      }
    }

    _isChecking = true;
    notifyListeners();

    try {
      final result = await _service.checkForUpdate();
      _result = result;
      _lastChecked = now;
      await prefs.setInt(_keyLastChecked, now.millisecondsSinceEpoch);

      // เช็คว่าถูก dismiss แล้วหรือยัง
      if (result.available) {
        final dismissedVer = prefs.getString(_keyDismissedVersion);
        _dismissed = dismissedVer == result.latestVersion;
      } else {
        _dismissed = false;
      }
    } catch (e) {
      debugPrint('UpdateProvider check: ${e.runtimeType}');
    }

    _isChecking = false;
    notifyListeners();
  }

  /// ผู้ใช้กด "ไว้ทีหลัง" — จำ version นี้ไว้ ไม่แสดงอีกจนกว่าจะมี version ใหม่กว่า
  Future<void> dismiss() async {
    if (_result?.latestVersion == null) return;
    _dismissed = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyDismissedVersion, _result!.latestVersion!);
    notifyListeners();
  }

  /// Manual check (จากปุ่มใน Settings) — force, ไม่เช็คเวลา
  Future<UpdateResult?> manualCheck() async {
    await checkInBackground(force: true);
    return _result;
  }
}
