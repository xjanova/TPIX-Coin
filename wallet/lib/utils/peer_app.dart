/// TPIX Wallet — Peer App Discovery
/// ตรวจว่า TPIX Trade ติดตั้งอยู่บนเครื่องเดียวกันไหม
/// ใช้ canLaunchUrl() + package visibility จาก AndroidManifest
///
/// Developed by Xman Studio

import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

class PeerApp {
  PeerApp._();

  static const String _tradeScheme = 'tpixtrade';
  static const String _tradeInstallUrl = 'https://tpix.online/trade';

  // Cache — ถ้าเพิ่งตรวจไปภายใน 5 นาที ใช้ผลเดิม
  static bool? _cachedInstalled;
  static DateTime? _cachedAt;
  static const _cacheTtl = Duration(minutes: 5);

  /// ตรวจว่า TPIX Trade ติดตั้งอยู่ในเครื่องไหม
  static Future<bool> isTradeInstalled({bool forceRefresh = false}) async {
    if (!forceRefresh && _cachedInstalled != null && _cachedAt != null) {
      if (DateTime.now().difference(_cachedAt!) < _cacheTtl) {
        return _cachedInstalled!;
      }
    }

    try {
      final uri = Uri.parse('$_tradeScheme://ping');
      final installed = await canLaunchUrl(uri);
      _cachedInstalled = installed;
      _cachedAt = DateTime.now();
      return installed;
    } catch (e) {
      debugPrint('PeerApp.isTradeInstalled: ${e.runtimeType}');
      return false;
    }
  }

  /// เปิด TPIX Trade พร้อมส่ง wallet address (optional)
  /// params: {address: "0x...", chain: "4289", pair: "BTC-USDT"}
  static Future<bool> openTrade({
    String path = 'open',
    Map<String, String>? params,
  }) async {
    try {
      final uri = Uri(
        scheme: _tradeScheme,
        host: path,
        queryParameters: params,
      );
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('PeerApp.openTrade: ${e.runtimeType}');
      return false;
    }
  }

  /// เปิดหน้าดาวน์โหลด Trade (ถ้ายังไม่ได้ติดตั้ง)
  static Future<void> openTradeInstallPage() async {
    try {
      await launchUrl(
        Uri.parse(_tradeInstallUrl),
        mode: LaunchMode.externalApplication,
      );
    } catch (e) {
      debugPrint('PeerApp.openTradeInstallPage: ${e.runtimeType}');
    }
  }

  /// Clear cache (สำหรับตอน pull-to-refresh)
  static void clearCache() {
    _cachedInstalled = null;
    _cachedAt = null;
  }
}
