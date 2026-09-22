import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import '../models/media_link_info.dart';
import 'engine_resolver.dart';
import 'python_bridge.dart';

class MediaLinkService {
  static Process? _activeDownloadProcess;

  /// Resolve absolute path to media_link_tool.py
  static String resolveToolScript() {
    final resolved = EngineResolver.resolveScript('media_link_tool.py');
    if (resolved != null && resolved.existsSync()) {
      return resolved.path;
    }
    final root = PythonBridge.resolveRootDir();
    final candidate = File(p.join(root, 'py_engine', 'tools', 'media_link_tool.py'));
    if (candidate.existsSync()) {
      return candidate.path;
    }
    return p.join(root, 'py_engine', 'tools', 'media_link_tool.py');
  }

  /// Probe URL metadata and direct playable CDN stream URL
  static Future<MediaLinkInfo> probeUrl(String url) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty || !trimmed.startsWith('http')) {
      return MediaLinkInfo.error(trimmed, 'URL không hợp lệ (cần bắt đầu bằng http:// hoặc https://)');
    }

    final rootDir = PythonBridge.resolveRootDir();
    final pythonBin = PythonBridge.resolvePythonBin();
    final scriptPath = resolveToolScript();

    try {
      final env = PythonBridge.buildEnvironment(rootDir: rootDir, pythonBin: pythonBin);
      final result = await Process.run(
        pythonBin,
        [scriptPath, 'probe', trimmed],
        workingDirectory: rootDir,
        environment: env,
      ).timeout(const Duration(seconds: 15));

      final output = result.stdout.toString().trim();
      if (output.isEmpty) {
        final err = result.stderr.toString().trim();
        return MediaLinkInfo.error(trimmed, err.isNotEmpty ? err : 'Không nhận được dữ liệu phản hồi');
      }

      // Find JSON line in output
      for (final line in LineSplitter.split(output)) {
        final lineTrimmed = line.trim();
        if (lineTrimmed.startsWith('{') && lineTrimmed.endsWith('}')) {
          try {
            final json = jsonDecode(lineTrimmed) as Map<String, dynamic>;
            return MediaLinkInfo.fromJson(json);
          } catch (_) {}
        }
      }

      return MediaLinkInfo.error(trimmed, 'Phản hồi từ engine không đúng định dạng JSON: $output');
    } on TimeoutException {
      return MediaLinkInfo.error(trimmed, 'Kiểm tra link quá hạn (Timeout sau 15 giây)');
    } catch (e) {
      return MediaLinkInfo.error(trimmed, 'Lỗi kết nối probe: $e');
    }
  }

  /// Download video with realtime progress streaming
  static Future<void> downloadVideo({
    required String url,
    required String targetDir,
    String? customFilename,
    required void Function(double progress, String statusText) onProgress,
    required void Function(String savedFilePath) onCompleted,
    required void Function(String error) onError,
  }) async {
    // Cancel existing active download if any
    cancelDownload();

    final trimmed = url.trim();
    final rootDir = PythonBridge.resolveRootDir();
    final pythonBin = PythonBridge.resolvePythonBin();
    final scriptPath = resolveToolScript();

    final args = [
      scriptPath,
      'download',
      trimmed,
      '--out-dir',
      targetDir,
      if (customFilename != null && customFilename.isNotEmpty) ...['--filename', customFilename],
    ];

    try {
      final env = PythonBridge.buildEnvironment(rootDir: rootDir, pythonBin: pythonBin);
      final proc = await Process.start(
        pythonBin,
        args,
        workingDirectory: rootDir,
        environment: env,
      );
      _activeDownloadProcess = proc;

      String? completedPath;
      String? errorMessage;

      proc.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
        final l = line.trim();
        if (l.isEmpty) return;

        if (l.startsWith('PROGRESS:')) {
          // Format: PROGRESS: 45.2% | SPEED: 4.8MB/s | ETA: 00:15
          final content = l.substring(9).trim();
          final parts = content.split('|');
          if (parts.isNotEmpty) {
            final pctStr = parts[0].replaceAll('%', '').trim();
            final pct = double.tryParse(pctStr);
            if (pct != null) {
              final normProgress = (pct / 100.0).clamp(0.0, 1.0);
              onProgress(normProgress, content);
            }
          }
        } else if (l.startsWith('COMPLETED:')) {
          completedPath = l.substring(10).trim();
        } else if (l.startsWith('ERROR:')) {
          final cleanErr = l.substring(6).trim();
          errorMessage = cleanErr.replaceFirst(RegExp(r'^(?:ERROR:\s*)+'), '');
        }
      });

      proc.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
        final err = line.trim();
        if (err.isNotEmpty && errorMessage == null) {
          // Ignore harmless download progress and warnings from yt-dlp
          if (err.startsWith('[download]') || err.startsWith('WARNING:') || err.startsWith('[info]')) {
            return;
          }
          if (err.contains('Error') || err.contains('ERROR') || err.contains('error')) {
            errorMessage = err.replaceFirst(RegExp(r'^(?:ERROR:\s*)+'), '');
          }
        }
      });

      final exitCode = await proc.exitCode;
      _activeDownloadProcess = null;

      if (exitCode == 0 && completedPath != null && File(completedPath!).existsSync()) {
        onProgress(1.0, 'Tải hoàn tất 100%');
        onCompleted(completedPath!);
      } else {
        var cleanMsg = errorMessage ?? 'Quá trình tải thất bại (mã thoát: $exitCode)';
        cleanMsg = cleanMsg.replaceFirst(RegExp(r'^(?:ERROR:\s*)+'), '');
        cleanMsg = cleanMsg.replaceFirst(RegExp(r'^(?:Lỗi tải video:\s*)+'), '');
        onError(cleanMsg);
      }
    } catch (e) {
      _activeDownloadProcess = null;
      onError('Lỗi ngoại lệ khi tải video: $e');
    }
  }

  /// Cancel active download process
  static void cancelDownload() {
    if (_activeDownloadProcess != null) {
      try {
        _activeDownloadProcess?.kill(ProcessSignal.sigterm);
      } catch (_) {}
      _activeDownloadProcess = null;
    }
  }
}
