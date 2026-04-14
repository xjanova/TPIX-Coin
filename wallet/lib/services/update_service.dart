import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/locale_provider.dart';

/// TPIX Wallet — Auto-Update Service
/// Downloads APK directly from GitHub Releases and installs in-app.
/// Falls back to opening browser if direct install fails.
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
    return info.version;
  }

  /// Fetch latest release from GitHub
  Future<ReleaseInfo?> getLatestRelease() async {
    try {
      final response = await _dio.get(_apiUrl);
      if (response.statusCode == 200) {
        return ReleaseInfo.fromJson(response.data);
      }
    } catch (e) {
      debugPrint('Update check failed: ${e.runtimeType}');
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
        apkDownloadUrl: release.apkDownloadUrl,
        apkSize: release.apkSize,
      );
    } catch (e) {
      debugPrint('Update check error: ${e.runtimeType}');
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

  /// Download APK from GitHub and install it
  /// Returns true if download+install was initiated, false if fallback needed
  /// [expectedSize] from GitHub API asset metadata for integrity verification
  Future<bool> downloadAndInstall(
    String downloadUrl,
    String version, {
    int? expectedSize,
    void Function(int received, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    try {
      final dir = await getTemporaryDirectory();
      final filePath = '${dir.path}/TPIX-Wallet-v$version.apk';

      // Clean up old APKs
      final oldFile = File(filePath);
      if (oldFile.existsSync()) {
        oldFile.deleteSync();
      }

      // Download APK with progress
      await Dio().download(
        downloadUrl,
        filePath,
        onReceiveProgress: onProgress,
        cancelToken: cancelToken,
        options: Options(
          receiveTimeout: const Duration(minutes: 5),
          headers: {'Accept': 'application/octet-stream'},
        ),
      );

      // Verify file exists and has content
      final file = File(filePath);
      if (!file.existsSync() || file.lengthSync() < 1024) {
        return false;
      }

      // Verify file size matches GitHub API metadata to detect truncation/tampering
      if (expectedSize != null && file.lengthSync() != expectedSize) {
        debugPrint('APK size mismatch: expected $expectedSize, got ${file.lengthSync()}');
        file.deleteSync();
        return false;
      }

      // Trigger Android package installer
      final result = await OpenFilex.open(filePath);
      return result.type == ResultType.done;
    } catch (e) {
      if (e is DioException && e.type == DioExceptionType.cancel) {
        rethrow; // Let caller handle cancellation
      }
      debugPrint('Download/install failed: ${e.runtimeType}');
      return false;
    }
  }

  /// Fallback: open tpix.online in browser
  Future<void> openDownloadPage() async {
    final uri = Uri.parse(_downloadPageUrl);
    try {
      final launched =
          await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched) throw Exception('launchUrl returned false');
    } catch (_) {
      final fallback =
          Uri.parse('https://github.com/$_owner/$_repo/releases/latest');
      final ok =
          await launchUrl(fallback, mode: LaunchMode.externalApplication);
      if (!ok) {
        throw Exception('Could not open $_downloadPageUrl');
      }
    }
  }

  /// Show update dialog with direct download
  static Future<void> showUpdateDialog(
    BuildContext context,
    UpdateResult result,
    UpdateService service,
  ) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _UpdateDialog(
        result: result,
        service: service,
      ),
    );
  }
}

/// Stateful update dialog with download progress
class _UpdateDialog extends StatefulWidget {
  final UpdateResult result;
  final UpdateService service;

  const _UpdateDialog({required this.result, required this.service});

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  bool _downloading = false;
  double _progress = 0;
  String _statusText = '';
  CancelToken? _cancelToken;

  @override
  void dispose() {
    _cancelToken?.cancel();
    super.dispose();
  }

  Future<void> _startDownload() async {
    final apkUrl = widget.result.apkDownloadUrl;

    // No direct APK URL found — fallback to browser
    if (apkUrl == null) {
      await _fallbackToBrowser();
      return;
    }

    setState(() {
      _downloading = true;
      _progress = 0;
      _statusText = 'Downloading...';
    });

    _cancelToken = CancelToken();

    try {
      final success = await widget.service.downloadAndInstall(
        apkUrl,
        widget.result.latestVersion ?? 'latest',
        expectedSize: widget.result.apkSize,
        onProgress: (received, total) {
          if (!mounted) return;
          if (total > 0) {
            setState(() {
              _progress = received / total;
              final mb = (received / 1024 / 1024).toStringAsFixed(1);
              final totalMb = (total / 1024 / 1024).toStringAsFixed(1);
              _statusText = '$mb / $totalMb MB';
            });
          }
        },
        cancelToken: _cancelToken,
      );

      if (!mounted) return;

      if (success) {
        Navigator.pop(context);
      } else {
        // Download succeeded but install failed — fallback
        await _fallbackToBrowser();
      }
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        if (mounted) {
          setState(() {
            _downloading = false;
            _statusText = '';
          });
        }
        return;
      }
      if (mounted) await _fallbackToBrowser();
    } catch (_) {
      if (mounted) await _fallbackToBrowser();
    }
  }

  Future<void> _fallbackToBrowser() async {
    setState(() {
      _downloading = false;
      _statusText = '';
    });

    try {
      await widget.service.openDownloadPage();
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        final l = context.read<LocaleProvider>();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l.t('common.browser_error')),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<LocaleProvider>();
    return AlertDialog(
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
          Expanded(
            child: Text(l.t('update.available'),
                style: const TextStyle(color: Colors.white, fontSize: 18)),
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
                    Text('Current: v${widget.result.currentVersion}',
                        style: const TextStyle(
                            color: Colors.grey, fontSize: 12)),
                    Text('New: v${widget.result.latestVersion}',
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

          if (widget.result.releaseNotes != null &&
              widget.result.releaseNotes!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(l.t('update.whats_new'),
                style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Container(
              constraints: const BoxConstraints(maxHeight: 100),
              child: SingleChildScrollView(
                child: Text(widget.result.releaseNotes!,
                    style:
                        const TextStyle(color: Colors.grey, fontSize: 11)),
              ),
            ),
          ],

          // Download progress
          if (_downloading) ...[
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: _progress > 0 ? _progress : null,
                backgroundColor: Colors.white.withOpacity(0.1),
                valueColor: const AlwaysStoppedAnimation<Color>(
                    Color(0xFF00BCD4)),
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_statusText,
                    style:
                        const TextStyle(color: Colors.white70, fontSize: 11)),
                if (_progress > 0)
                  Text('${(_progress * 100).toStringAsFixed(0)}%',
                      style: const TextStyle(
                          color: Color(0xFF00BCD4), fontSize: 11)),
              ],
            ),
          ],

          if (!_downloading) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF00BCD4).withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: const Color(0xFF00BCD4).withOpacity(0.2)),
              ),
              child: Row(
                children: [
                  Icon(
                    widget.result.apkDownloadUrl != null
                        ? Icons.download
                        : Icons.open_in_browser,
                    color: const Color(0xFF00BCD4),
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.result.apkDownloadUrl != null
                          ? l.t('update.auto_install')
                          : l.t('update.from_browser'),
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
      actions: [
        if (_downloading)
          TextButton(
            onPressed: () {
              _cancelToken?.cancel();
              setState(() {
                _downloading = false;
                _statusText = '';
              });
            },
            child:
                Text(l.t('common.cancel'), style: const TextStyle(color: Colors.grey)),
          )
        else ...[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child:
                Text(l.t('common.later'), style: const TextStyle(color: Colors.grey)),
          ),
          ElevatedButton.icon(
            icon:
                const Icon(Icons.download, color: Colors.white, size: 18),
            label: Text(l.t('common.download'),
                style: const TextStyle(color: Colors.white)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00BCD4),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: _startDownload,
          ),
        ],
      ],
    );
  }
}

/// Release info from GitHub
class ReleaseInfo {
  final String version;
  final String? body;
  final String? publishedAt;
  final String? apkDownloadUrl;
  final int? apkSize; // expected file size from GitHub API

  ReleaseInfo({
    required this.version,
    this.body,
    this.publishedAt,
    this.apkDownloadUrl,
    this.apkSize,
  });

  factory ReleaseInfo.fromJson(Map<String, dynamic> json) {
    // Find the .apk asset in the release
    String? apkUrl;
    int? apkSize;
    final assets = json['assets'] as List<dynamic>? ?? [];
    for (final asset in assets) {
      final name = (asset['name'] as String? ?? '').toLowerCase();
      if (name.endsWith('.apk')) {
        apkUrl = asset['browser_download_url'] as String?;
        apkSize = asset['size'] as int?;
        break;
      }
    }

    return ReleaseInfo(
      version: (json['tag_name'] as String? ?? '').replaceAll('v', ''),
      body: json['body'] as String?,
      publishedAt: json['published_at'] as String?,
      apkDownloadUrl: apkUrl,
      apkSize: apkSize,
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
  final String? apkDownloadUrl;
  final int? apkSize; // expected file size for integrity verification

  UpdateResult({
    required this.available,
    required this.currentVersion,
    this.latestVersion,
    this.releaseNotes,
    this.releaseDate,
    this.apkDownloadUrl,
    this.apkSize,
  });
}
