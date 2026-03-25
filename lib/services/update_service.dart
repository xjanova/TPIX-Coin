import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

/// TPIX Wallet — Auto-Update Service
/// Checks GitHub Releases for new versions and prompts install
/// Developed by Xman Studio
class UpdateService {
  static const String _owner = 'xjanova';
  static const String _repo = 'TPIX-Coin';
  static const String _apiUrl =
      'https://api.github.com/repos/$_owner/$_repo/releases/latest';

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
    headers: {'Accept': 'application/vnd.github.v3+json'},
  ));

  /// Current app version
  Future<String> getCurrentVersion() async {
    final info = await PackageInfo.fromPlatform();
    return info.version; // e.g. "1.0.0"
  }

  /// Fetch latest release from GitHub
  Future<ReleaseInfo?> getLatestRelease() async {
    try {
      final response = await _dio.get(_apiUrl);
      if (response.statusCode == 200) {
        return ReleaseInfo.fromJson(response.data);
      }
    } catch (e) {
      debugPrint('Update check failed: $e');
    }
    return null;
  }

  /// Check if update is available
  Future<UpdateResult> checkForUpdate() async {
    try {
      final currentVersion = await getCurrentVersion();
      final release = await getLatestRelease();

      if (release == null) {
        return UpdateResult(
          available: false,
          currentVersion: currentVersion,
        );
      }

      final isNewer = _isNewerVersion(currentVersion, release.version);
      return UpdateResult(
        available: isNewer,
        currentVersion: currentVersion,
        latestVersion: release.version,
        releaseNotes: release.body,
        downloadUrl: release.apkDownloadUrl,
        releaseDate: release.publishedAt,
      );
    } catch (e) {
      debugPrint('Update check error: $e');
      return UpdateResult(available: false, currentVersion: 'unknown');
    }
  }

  /// Compare semantic versions: returns true if remote > current
  bool _isNewerVersion(String current, String remote) {
    final currentParts = current.replaceAll('v', '').split('.');
    final remoteParts = remote.replaceAll('v', '').split('.');

    for (int i = 0; i < 3; i++) {
      final c = i < currentParts.length ? int.tryParse(currentParts[i]) ?? 0 : 0;
      final r = i < remoteParts.length ? int.tryParse(remoteParts[i]) ?? 0 : 0;
      if (r > c) return true;
      if (r < c) return false;
    }
    return false;
  }

  /// Download APK and install
  Future<void> downloadAndInstall(
    String downloadUrl,
    Function(double) onProgress,
  ) async {
    // Request storage permission on Android
    if (Platform.isAndroid) {
      final status = await Permission.requestInstallPackages.request();
      if (!status.isGranted) {
        throw Exception('Install permission denied');
      }
    }

    final dir = await getTemporaryDirectory();
    final filePath = '${dir.path}/tpix_wallet_update.apk';

    // Download with progress
    await _dio.download(
      downloadUrl,
      filePath,
      onReceiveProgress: (received, total) {
        if (total > 0) {
          onProgress(received / total);
        }
      },
      options: Options(
        responseType: ResponseType.bytes,
        followRedirects: true,
        receiveTimeout: const Duration(minutes: 5),
      ),
    );

    // Open APK for install
    final result = await OpenFilex.open(filePath);
    if (result.type != ResultType.done) {
      throw Exception('Failed to open APK: ${result.message}');
    }
  }

  /// Show update dialog
  static Future<void> showUpdateDialog(
    BuildContext context,
    UpdateResult result,
    UpdateService service,
  ) async {
    double progress = 0;
    bool isDownloading = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          backgroundColor: const Color(0xFF1A1F2E),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: Color(0xFF00BCD4), width: 0.5),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF00BCD4).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.system_update,
                    color: Color(0xFF00BCD4), size: 24),
              ),
              const SizedBox(width: 12),
              const Text('Update Available',
                  style: TextStyle(color: Colors.white, fontSize: 18)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Version info
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Current: v${result.currentVersion}',
                            style: const TextStyle(
                                color: Colors.grey, fontSize: 12)),
                        Text('New: v${result.latestVersion}',
                            style: const TextStyle(
                                color: Color(0xFF00BCD4),
                                fontSize: 14,
                                fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const Icon(Icons.arrow_forward,
                        color: Color(0xFF00BCD4), size: 20),
                  ],
                ),
              ),

              if (result.releaseNotes != null &&
                  result.releaseNotes!.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text("What's new:",
                    style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Container(
                  constraints: const BoxConstraints(maxHeight: 100),
                  child: SingleChildScrollView(
                    child: Text(result.releaseNotes!,
                        style: const TextStyle(
                            color: Colors.grey, fontSize: 11)),
                  ),
                ),
              ],

              // Download progress
              if (isDownloading) ...[
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: progress,
                    backgroundColor: Colors.white.withOpacity(0.1),
                    valueColor: const AlwaysStoppedAnimation<Color>(
                        Color(0xFF00BCD4)),
                    minHeight: 8,
                  ),
                ),
                const SizedBox(height: 4),
                Text('${(progress * 100).toInt()}%',
                    style: const TextStyle(
                        color: Color(0xFF00BCD4), fontSize: 12)),
              ],
            ],
          ),
          actions: [
            if (!isDownloading)
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child:
                    const Text('Later', style: TextStyle(color: Colors.grey)),
              ),
            if (!isDownloading && result.downloadUrl != null)
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00BCD4),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () async {
                  setState(() => isDownloading = true);
                  try {
                    await service.downloadAndInstall(
                      result.downloadUrl!,
                      (p) => setState(() => progress = p),
                    );
                    if (ctx.mounted) Navigator.pop(ctx);
                  } catch (e) {
                    setState(() => isDownloading = false);
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        SnackBar(content: Text('Download failed: $e')),
                      );
                    }
                  }
                },
                child: const Text('Update Now',
                    style: TextStyle(color: Colors.white)),
              ),
          ],
        ),
      ),
    );
  }
}

/// Release info from GitHub
class ReleaseInfo {
  final String version;
  final String? body;
  final String? apkDownloadUrl;
  final String? publishedAt;

  ReleaseInfo({
    required this.version,
    this.body,
    this.apkDownloadUrl,
    this.publishedAt,
  });

  factory ReleaseInfo.fromJson(Map<String, dynamic> json) {
    // Find APK asset
    String? apkUrl;
    final assets = json['assets'] as List? ?? [];
    for (final asset in assets) {
      final name = (asset['name'] as String? ?? '').toLowerCase();
      if (name.endsWith('.apk')) {
        apkUrl = asset['browser_download_url'] as String?;
        break;
      }
    }

    return ReleaseInfo(
      version: (json['tag_name'] as String? ?? '').replaceAll('v', ''),
      body: json['body'] as String?,
      apkDownloadUrl: apkUrl,
      publishedAt: json['published_at'] as String?,
    );
  }
}

/// Update check result
class UpdateResult {
  final bool available;
  final String currentVersion;
  final String? latestVersion;
  final String? releaseNotes;
  final String? downloadUrl;
  final String? releaseDate;

  UpdateResult({
    required this.available,
    required this.currentVersion,
    this.latestVersion,
    this.releaseNotes,
    this.downloadUrl,
    this.releaseDate,
  });
}
