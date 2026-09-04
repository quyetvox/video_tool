import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'python_bridge.dart';

class AiEnvironmentService {
  static const String manifestUrl =
      'https://raw.githubusercontent.com/quyetvox/Sub-Video/v-flutter/releases/ai/ai_runtime_manifest.json';
  
  static const String defaultWinUrl =
      'https://github.com/quyetvox/Sub-Video/releases/download/v1.0.1/SubVideo-AI-Runtime-Win64.zip';
  
  static const String defaultMacUrl =
      'https://github.com/quyetvox/Sub-Video/releases/download/v1.0.1/SubVideo-AI-Runtime-macOS-arm64.zip';

  /// Directory where the On-Demand AI runtime packages reside
  static Directory get aiRuntimeDir {
    final home = Platform.isWindows
        ? (Platform.environment['LOCALAPPDATA'] ??
            Platform.environment['USERPROFILE'] ??
            Platform.environment['HOME'] ??
            '')
        : (Platform.environment['HOME'] ?? '');

    if (Platform.isMacOS) {
      return Directory(p.join(home, 'Library', 'Application Support', 'SubVideo', 'ai_runtime'));
    }
    return Directory(p.join(home, '.subvideo', 'ai_runtime'));
  }

  /// Site-packages directory for imported Python AI libraries
  static Directory get sitePackagesDir {
    return Directory(p.join(aiRuntimeDir.path, 'site-packages'));
  }

  /// Check if AI runtime libraries (PyTorch, Demucs, Whisper) are available
  static Future<bool> isAiReady() async {
    // 1. Check local on-demand folder
    final sitePackages = sitePackagesDir;
    if (sitePackages.existsSync()) {
      final hasDemucs = Directory(p.join(sitePackages.path, 'demucs')).existsSync();
      final hasTorch = Directory(p.join(sitePackages.path, 'torch')).existsSync();
      final hasMlxWhisper = Directory(p.join(sitePackages.path, 'mlx_whisper')).existsSync();
      final hasWhisper = Directory(p.join(sitePackages.path, 'whisper')).existsSync();
      if (hasDemucs || hasTorch || hasMlxWhisper || hasWhisper) {
        return true;
      }
    }

    // 2. Fallback check: test if python currently has demucs installed (e.g. dev venv)
    try {
      final res = await PythonBridge.runCode('import demucs; print("AI_OK")');
      if (res.exitCode == 0 && res.stdout.toString().contains('AI_OK')) {
        return true;
      }
    } catch (_) {}

    return false;
  }

  /// Get download URL appropriate for current operating system
  static String getDownloadUrl() {
    if (Platform.isWindows) {
      return defaultWinUrl;
    }
    return defaultMacUrl;
  }

  /// Download and install AI Runtime from GitHub Releases
  static Future<bool> downloadAndInstall({
    required void Function(double progress, String message) onProgress,
  }) async {
    final client = http.Client();
    try {
      var url = getDownloadUrl();

      // Attempt to read latest manifest if available
      try {
        final manifestRes = await client.get(Uri.parse(manifestUrl)).timeout(const Duration(seconds: 4));
        if (manifestRes.statusCode == 200) {
          final data = jsonDecode(manifestRes.body);
          if (Platform.isWindows && data['win64']?['url'] != null) {
            url = data['win64']['url'];
          } else if (Platform.isMacOS && data['macos_arm64']?['url'] != null) {
            url = data['macos_arm64']['url'];
          }
        }
      } catch (_) {
        // Fall back to default URL
      }

      onProgress(0.05, 'Đang kết nối đến máy chủ tải gói AI...');
      final request = http.Request('GET', Uri.parse(url));
      final response = await client.send(request);

      if (response.statusCode != 200) {
        throw Exception('Máy chủ phản hồi mã lỗi HTTP ${response.statusCode}');
      }

      final contentLength = response.contentLength ?? 0;
      final bytes = <int>[];
      int received = 0;

      await for (final chunk in response.stream) {
        bytes.addAll(chunk);
        received += chunk.length;
        if (contentLength > 0) {
          final p = (received / contentLength) * 0.7; // 0.05 -> 0.75
          final mb = (received / (1024 * 1024)).toStringAsFixed(1);
          final totalMb = (contentLength / (1024 * 1024)).toStringAsFixed(1);
          onProgress(0.05 + p, 'Đang tải gói AI: $mb MB / $totalMb MB (${((received / contentLength) * 100).toInt()}%)');
        } else {
          final mb = (received / (1024 * 1024)).toStringAsFixed(1);
          onProgress(0.4, 'Đang tải gói AI: $mb MB...');
        }
      }

      onProgress(0.80, 'Đang giải nén và thiết lập thư viện AI...');
      return await _extractAndInstallBytes(bytes, onProgress: onProgress);
    } catch (e) {
      onProgress(0.0, 'Lỗi cài đặt: $e');
      return false;
    } finally {
      client.close();
    }
  }

  /// Install AI runtime directly from a local zip file (Offline mode)
  static Future<bool> installFromLocalZip(
    File zipFile, {
    required void Function(double progress, String message) onProgress,
  }) async {
    try {
      if (!zipFile.existsSync()) {
        throw Exception('File zip không tồn tại: ${zipFile.path}');
      }
      onProgress(0.1, 'Đang đọc file zip ngoại tuyến...');
      final bytes = await zipFile.readAsBytes();
      onProgress(0.4, 'Đang giải nén và tích hợp gói AI...');
      return await _extractAndInstallBytes(bytes, onProgress: onProgress);
    } catch (e) {
      onProgress(0.0, 'Lỗi cài đặt từ file: $e');
      return false;
    }
  }

  static Future<bool> _extractAndInstallBytes(
    List<int> bytes, {
    required void Function(double progress, String message) onProgress,
  }) async {
    final targetDir = aiRuntimeDir;
    if (!targetDir.existsSync()) {
      targetDir.createSync(recursive: true);
    }

    final archive = ZipDecoder().decodeBytes(bytes);
    final totalFiles = archive.length;
    int processed = 0;

    for (final file in archive) {
      final filename = file.name;
      if (filename.startsWith('__MACOSX') || filename.contains('/.')) {
        processed++;
        continue;
      }

      final outPath = p.join(targetDir.path, filename);
      if (file.isFile) {
        final data = file.content as List<int>;
        final outFile = File(outPath);
        outFile.parent.createSync(recursive: true);
        outFile.writeAsBytesSync(data, flush: true);
      } else {
        Directory(outPath).createSync(recursive: true);
      }

      processed++;
      if (processed % 50 == 0 || processed == totalFiles) {
        final pct = 0.80 + (processed / totalFiles) * 0.20;
        onProgress(pct, 'Đang giải nén: $processed / $totalFiles tệp...');
      }
    }

    onProgress(1.0, 'Hoàn tất cài đặt Gói AI Nâng Cao!');
    return true;
  }

  /// Remove AI runtime to free space
  static Future<void> deleteAiRuntime() async {
    final dir = aiRuntimeDir;
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
  }
}
