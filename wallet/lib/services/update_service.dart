import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// TPIX Wallet — Auto-Update Service
/// Checks GitHub Releases for new versions and redirects to tpix.online
/// Developed by Xman Studio
class UpdateService {
  static const String _owner = 'xjanova';
  static const String _repo = 'TPIX-Coin';
  static const String _apiUrl =
      'https://api.github.com/repos/$_owner/$_repo/releases/latest';
  static const String _downloadPageUrl = 'https://tpix.online';

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
    headers: {'Accept': 'application/vnd.github.v3+json'},
  ));

  /// Current app version
  Future<String> getCurrentVersion() async {
    final info = await PackageInfo.fromPlatform();
    return info.version; // e.g. "1.1.2"
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
      final c =
          i < currentParts.length ? int.tryParse(currentParts[i]) ?? 0 : 0;
      final r =
          i < remoteParts.length ? int.tryParse(remoteParts[i]) ?? 0 : 0;
      if (r > c) return true;
      if (r < c) return false;
    }
    return false;
  }

  /// Open tpix.online download page in browser
  /// Falls back to direct GitHub release page if browser launch fails
  Future<void> openDownloadPage() async {
    final uri = Uri.parse(_downloadPageUrl);
    try {
      final launched =
          await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched) throw Exception('launchUrl returned false');
    } catch (_) {
      // Fallback: open GitHub releases page directly
      final fallback = Uri.parse(
          'https://github.com/$_owner/$_repo/releases/latest');
      final ok =
          await launchUrl(fallback, mode: LaunchMode.externalApplication);
      if (!ok) {
        throw Exception('Could not open $_downloadPageUrl');
      }
    }
  }

  /// Show update dialog
  static Future<void> showUpdateDialog(
    BuildContext context,
    UpdateResult result,
    UpdateService service,
  ) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
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
            const Expanded(
              child: Text('Update Available',
                  style: TextStyle(color: Colors.white, fontSize: 18)),
            ),
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
                      style:
                          const TextStyle(color: Colors.grey, fontSize: 11)),
                ),
              ),
            ],

            const SizedBox(height: 16),
            // Info text
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF00BCD4).withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: const Color(0xFF00BCD4).withOpacity(0.2)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.open_in_browser,
                      color: Color(0xFF00BCD4), size: 16),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Download from tpix.online',
                      style: TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Later', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.download, color: Colors.white, size: 18),
            label: const Text('Download',
                style: TextStyle(color: Colors.white)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00BCD4),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () async {
              try {
                await service.openDownloadPage();
                if (ctx.mounted) Navigator.pop(ctx);
              } catch (e) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(
                      content: Text('Could not open browser: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
          ),
        ],
      ),
    );
  }
}

/// Release info from GitHub
class ReleaseInfo {
  final String version;
  final String? body;
  final String? publishedAt;

  ReleaseInfo({
    required this.version,
    this.body,
    this.publishedAt,
  });

  factory ReleaseInfo.fromJson(Map<String, dynamic> json) {
    return ReleaseInfo(
      version: (json['tag_name'] as String? ?? '').replaceAll('v', ''),
      body: json['body'] as String?,
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
  final String? releaseDate;

  UpdateResult({
    required this.available,
    required this.currentVersion,
    this.latestVersion,
    this.releaseNotes,
    this.releaseDate,
  });
}
