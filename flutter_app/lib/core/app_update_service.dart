import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'app_constants.dart';

class AppUpdateRelease {
  final String tagName;
  final String version;
  final String releaseNotes;
  final String htmlUrl;
  final DateTime publishedAt;
  final String? assetDownloadUrl;
  final String? assetName;
  final int assetSizeBytes;

  const AppUpdateRelease({
    required this.tagName,
    required this.version,
    required this.releaseNotes,
    required this.htmlUrl,
    required this.publishedAt,
    this.assetDownloadUrl,
    this.assetName,
    this.assetSizeBytes = 0,
  });

  factory AppUpdateRelease.fromJson(Map<String, dynamic> json) {
    final tag = json['tag_name']?.toString() ?? 'v1.0.0';
    final cleanVer = tag.replaceAll(RegExp(r'[^0-9.]'), '');
    final notes = json['body']?.toString() ?? 'Bản cập nhật mới với nhiều cải tiến và vá lỗi.';
    final html = json['html_url']?.toString() ?? '';
    final pubAt = DateTime.tryParse(json['published_at']?.toString() ?? '') ?? DateTime.now();

    String? matchedUrl;
    String? matchedName;
    int matchedSize = 0;

    final assets = json['assets'] as List<dynamic>? ?? [];
    for (final asset in assets) {
      if (asset is Map<String, dynamic>) {
        final name = asset['name']?.toString() ?? '';
        final url = asset['browser_download_url']?.toString() ?? '';
        final size = (asset['size'] as num?)?.toInt() ?? 0;

        if (Platform.isWindows) {
          // Prefer Inno Setup .exe, fallback to .zip
          if (name.endsWith('.exe')) {
            matchedUrl = url;
            matchedName = name;
            matchedSize = size;
            break;
          } else if (name.endsWith('.zip') && matchedUrl == null) {
            matchedUrl = url;
            matchedName = name;
            matchedSize = size;
          }
        } else if (Platform.isMacOS) {
          if (name.endsWith('.dmg')) {
            matchedUrl = url;
            matchedName = name;
            matchedSize = size;
            break;
          }
        }
      }
    }

    return AppUpdateRelease(
      tagName: tag,
      version: cleanVer.isEmpty ? '1.0.0' : cleanVer,
      releaseNotes: notes,
      htmlUrl: html,
      publishedAt: pubAt,
      assetDownloadUrl: matchedUrl,
      assetName: matchedName,
      assetSizeBytes: matchedSize,
    );
  }
}

class AppUpdateService {
  static const String repoOwner = 'quyetvox';
  static const String repoName = 'Sub-Video';
  static const String githubApiUrl = 'https://api.github.com/repos/$repoOwner/$repoName/releases/latest';

  /// Compare SemVer (e.g. 1.0.1 > 1.0.0)
  static int compareSemVer(String v1, String v2) {
    final clean1 = v1.replaceAll(RegExp(r'[^0-9.]'), '');
    final clean2 = v2.replaceAll(RegExp(r'[^0-9.]'), '');
    final p1 = clean1.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final p2 = clean2.split('.').map((e) => int.tryParse(e) ?? 0).toList();

    for (int i = 0; i < 3; i++) {
      final n1 = i < p1.length ? p1[i] : 0;
      final n2 = i < p2.length ? p2[i] : 0;
      if (n1 != n2) return n1.compareTo(n2);
    }
    return 0;
  }

  /// Checks if a newer App release is available on GitHub
  static Future<AppUpdateRelease?> checkAppUpdate() async {
    try {
      final response = await http
          .get(
            Uri.parse(githubApiUrl),
            headers: {'Accept': 'application/vnd.github.v3+json'},
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        final release = AppUpdateRelease.fromJson(data);

        // Compare with current App version
        const currentVer = AppConstants.appVersion;
        if (compareSemVer(release.version, currentVer) > 0) {
          return release;
        }
      }
    } catch (_) {}
    return null;
  }

  /// Downloads the release installer (.exe on Windows, .dmg on macOS) and launches installer
  static Future<bool> downloadAndInstallUpdate(
    AppUpdateRelease release, {
    Function(double progress, String status)? onProgress,
  }) async {
    if (release.assetDownloadUrl == null || release.assetDownloadUrl!.isEmpty) {
      throw Exception('Không tìm thấy tệp cài đặt phù hợp cho hệ điều hành hiện tại.');
    }

    final downloadUrl = release.assetDownloadUrl!;
    final fileName = release.assetName ?? (Platform.isWindows ? 'SubVideo_Setup.exe' : 'SubVideo.dmg');

    onProgress?.call(0.05, 'Đang chuẩn bị thư mục tải xuống...');
    final tempDir = await getTemporaryDirectory();
    final targetFile = File(p.join(tempDir.path, fileName));

    if (targetFile.existsSync()) {
      targetFile.deleteSync();
    }

    onProgress?.call(0.1, 'Đang kết nối tới máy chủ GitHub...');
    final client = http.Client();
    final request = http.Request('GET', Uri.parse(downloadUrl));
    final response = await client.send(request);

    if (response.statusCode != 200) {
      throw Exception('Tải bản cập nhật thất bại (HTTP ${response.statusCode})');
    }

    final contentLength = response.contentLength ?? release.assetSizeBytes;
    final sink = targetFile.openWrite();
    int received = 0;

    await for (final chunk in response.stream) {
      sink.add(chunk);
      received += chunk.length;
      if (contentLength > 0) {
        final pct = received / contentLength;
        onProgress?.call(0.1 + pct * 0.85, 'Đang tải bản cập nhật: ${(pct * 100).toStringAsFixed(0)}%');
      }
    }
    await sink.flush();
    await sink.close();

    onProgress?.call(1.0, 'Đã tải xong! Đang khởi động trình cài đặt...');

    // Launch Installer based on Platform
    if (Platform.isWindows) {
      // Inno Setup supports /SILENT /CLOSEAPPLICATIONS
      await Process.start(
        targetFile.path,
        ['/SILENT', '/CLOSEAPPLICATIONS', '/RESTARTAPPLICATIONS'],
        mode: ProcessStartMode.detached,
      );
    } else if (Platform.isMacOS) {
      // Open DMG for user
      await Process.run('open', [targetFile.path]);
    }

    return true;
  }
}
