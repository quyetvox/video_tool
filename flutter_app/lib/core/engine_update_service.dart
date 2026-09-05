import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'app_constants.dart';
import 'engine_resolver.dart';
import 'license_service.dart';

class EngineUpdateInfo {
  final String version;
  final String releaseNotes;
  final String downloadUrl; // Can be HTTP URL or Local File/Directory Path
  final int sizeBytes;
  final DateTime publishedAt;
  final bool isLocalSource;

  const EngineUpdateInfo({
    required this.version,
    required this.releaseNotes,
    required this.downloadUrl,
    required this.sizeBytes,
    required this.publishedAt,
    this.isLocalSource = false,
  });

  factory EngineUpdateInfo.fromJson(Map<String, dynamic> json, {bool isLocal = false}) {
    return EngineUpdateInfo(
      version: json['version']?.toString() ?? '1.0.0',
      releaseNotes: json['release_notes']?.toString() ?? 'Cập nhật và vá lỗi logic video engine.',
      downloadUrl: json['download_url']?.toString() ?? '',
      sizeBytes: (json['size_bytes'] as num?)?.toInt() ?? 0,
      publishedAt: DateTime.tryParse(json['published_at']?.toString() ?? '') ?? DateTime.now(),
      isLocalSource: isLocal,
    );
  }
}

class ActiveEngineInfo {
  final String source; // 'hot_patch', 'dev_source', or 'bundled'
  final String executablePath;
  final String version;
  final DateTime? lastModified;
  final int sizeBytes;

  const ActiveEngineInfo({
    required this.source,
    required this.executablePath,
    required this.version,
    this.lastModified,
    required this.sizeBytes,
  });
}

class EngineUpdateService {
  static const String _defaultManifestUrl = 'https://raw.githubusercontent.com/quyetvox/Sub-Video/main/dist/engine_manifest.json';
  static const String _prefManifestUrlKey = 'engine_update_manifest_url';
  static const String _prefInstalledVersionKey = 'engine_hot_patch_version';

  static Future<String> getManifestUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefManifestUrlKey) ?? _defaultManifestUrl;
  }

  static Future<void> setManifestUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefManifestUrlKey, url.trim());
  }

  static Future<ActiveEngineInfo> getActiveEngineInfo() async {
    final target = EngineResolver.resolveEngine();
    final file = File(target.executable);
    DateTime? lastMod;
    int size = 0;

    if (file.existsSync()) {
      try {
        final stat = file.statSync();
        lastMod = stat.modified;
        size = stat.size;
      } catch (_) {}
    }

    final prefs = await SharedPreferences.getInstance();
    String? manifestVer;

    // Check hot patch manifest first
    final hpManifest = File(p.join(EngineResolver.hotPatchDir.path, 'engine_manifest.json'));
    if (hpManifest.existsSync()) {
      try {
        final data = jsonDecode(hpManifest.readAsStringSync());
        if (data is Map && data['version'] != null) {
          manifestVer = 'v${data['version']}';
        }
      } catch (_) {}
    }

    // Check project dist/engine_patch manifest
    if (manifestVer == null) {
      final home = Platform.environment['HOME'] ?? '';
      final distManifest = File(p.join(home, 'Documents', 'projects', 'video', 'Sub-Video', 'dist', 'engine_patch', 'engine_manifest.json'));
      if (distManifest.existsSync()) {
        try {
          final data = jsonDecode(distManifest.readAsStringSync());
          if (data is Map && data['version'] != null) {
            manifestVer = 'v${data['version']}';
          }
        } catch (_) {}
      }
    }

    final savedVersion = prefs.getString(_prefInstalledVersionKey);
    String ver = manifestVer ?? savedVersion ?? (target.source == 'hot_patch' ? 'v1.0.4 (Hot-Patch)' : 'v1.0.0 (Mặc định)');
    if (target.source == 'dev_source' && manifestVer == null) {
      ver = 'Developer JIT Mode';
    }

    return ActiveEngineInfo(
      source: target.source,
      executablePath: target.executable,
      version: ver,
      lastModified: lastMod,
      sizeBytes: size,
    );
  }

  /// Checks either local directory/file or cloud URL for available hot patches
  static Future<EngineUpdateInfo?> checkUpdate({String? customSource}) async {
    final source = customSource ?? await getManifestUrl();
    if (source.isEmpty) return null;

    final prefs = await SharedPreferences.getInstance();
    final currentVer = prefs.getString(_prefInstalledVersionKey) ?? '1.0.0';

    // ── 1. LOCAL DIRECTORY OR LOCAL MANIFEST FILE CHECK ──────────────────────
    if (!source.startsWith('http://') && !source.startsWith('https://')) {
      final localDir = Directory(source);
      final localFile = File(source);

      // A. If source is a local manifest JSON file or a folder containing engine_manifest.json
      File? manifestFile;
      if (localFile.existsSync() && source.endsWith('.json')) {
        manifestFile = localFile;
      } else if (localDir.existsSync()) {
        final candidate = File(p.join(localDir.path, 'engine_manifest.json'));
        if (candidate.existsSync()) {
          manifestFile = candidate;
        }
      }

      if (manifestFile != null) {
        try {
          final json = jsonDecode(manifestFile.readAsStringSync()) as Map<String, dynamic>;
          final info = EngineUpdateInfo.fromJson(json, isLocal: true);
          return info;
        } catch (_) {}
      }

      // B. If source is a local folder containing sub_video_engine binary directly
      if (localDir.existsSync()) {
        final engineBin = File(p.join(localDir.path, 'sub_video_engine'));
        if (engineBin.existsSync()) {
          return EngineUpdateInfo(
            version: 'Local Build (${DateTime.now().hour}:${DateTime.now().minute.toString().padLeft(2, '0')})',
            releaseNotes: 'Bản vá cục bộ từ thư mục: ${localDir.path}',
            downloadUrl: localDir.path,
            sizeBytes: engineBin.lengthSync(),
            publishedAt: engineBin.lastModifiedSync(),
            isLocalSource: true,
          );
        }
      }

      // C. If source is a local .zip file
      if (localFile.existsSync() && source.endsWith('.zip')) {
        return EngineUpdateInfo(
          version: 'Local Zip (${p.basename(source)})',
          releaseNotes: 'Bản vá từ file zip: ${localFile.path}',
          downloadUrl: localFile.path,
          sizeBytes: localFile.lengthSync(),
          publishedAt: localFile.lastModifiedSync(),
          isLocalSource: true,
        );
      }

      return null;
    }

    // ── 2. CLOUD HTTP/HTTPS CHECK ────────────────────────────────────────────
    // Ưu tiên kiểm tra API Backend Admin do Super Admin điều phối trước
    if (source == _defaultManifestUrl || source.contains('githubusercontent.com')) {
      try {
        final machineId = await LicenseService.getMachineId();
        final apiUri = Uri.parse('${AppConstants.defaultApiBaseUrl}/patches/latest');
        final apiRes = await http.get(apiUri).timeout(const Duration(seconds: 4));
        if (apiRes.statusCode == 200) {
          final json = jsonDecode(utf8.decode(apiRes.bodyBytes)) as Map<String, dynamic>;
          var downloadUrl = json['download_url']?.toString() ?? '';
          if (downloadUrl.isNotEmpty) {
            downloadUrl += '&machine_id=$machineId';
            json['download_url'] = downloadUrl;
          }
          final info = EngineUpdateInfo.fromJson(json, isLocal: false);
          if (info.version != currentVer && info.downloadUrl.isNotEmpty) {
            return info;
          }
        }
      } catch (_) {
        // Fallback về nguồn manifest tĩnh bên dưới nếu backend offline
      }
    }

    final response = await http.get(Uri.parse(source)).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw Exception('Không thể kết nối máy chủ cập nhật (HTTP ${response.statusCode})');
    }

    final json = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final info = EngineUpdateInfo.fromJson(json, isLocal: false);

    if (info.version != currentVer && info.downloadUrl.isNotEmpty) {
      return info;
    }
    return null;
  }

  /// Downloads or copies patch from Source (Local or Cloud) to the Hot-Patch folder
  static Future<bool> applyPatch(
    EngineUpdateInfo updateInfo, {
    Function(double progress, String status)? onProgress,
  }) async {
    final patchDir = EngineResolver.hotPatchDir;
    if (!patchDir.existsSync()) {
      patchDir.createSync(recursive: true);
    }

    // ── CASE 1: LOCAL DIRECTORY COPY ─────────────────────────────────────────
    if (updateInfo.isLocalSource && Directory(updateInfo.downloadUrl).existsSync()) {
      onProgress?.call(0.2, 'Đang sao chép các tệp bản vá từ thư mục cục bộ...');
      final srcDir = Directory(updateInfo.downloadUrl);
      _copyDirectoryRecursive(srcDir, patchDir);
      onProgress?.call(1.0, 'Đã sao chép và nạp bản vá cục bộ thành công!');
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefInstalledVersionKey, updateInfo.version);
      return true;
    }

    // ── CASE 2: LOCAL ZIP FILE COPY & EXTRACT ────────────────────────────────
    if (updateInfo.isLocalSource && File(updateInfo.downloadUrl).existsSync() && updateInfo.downloadUrl.endsWith('.zip')) {
      onProgress?.call(0.3, 'Đang giải nén file zip cục bộ...');
      final zipBytes = File(updateInfo.downloadUrl).readAsBytesSync();
      await _applyZipBytes(zipBytes, version: updateInfo.version);
      onProgress?.call(1.0, 'Đã giải nén và nạp bản vá thành công!');
      return true;
    }

    // ── CASE 3: CLOUD HTTP/HTTPS DOWNLOAD ────────────────────────────────────
    onProgress?.call(0.1, 'Đang kết nối máy chủ Cloud...');
    final client = http.Client();
    final request = http.Request('GET', Uri.parse(updateInfo.downloadUrl));
    final response = await client.send(request);

    if (response.statusCode != 200) {
      throw Exception('Tải bản vá từ Cloud thất bại (HTTP ${response.statusCode})');
    }

    final contentLength = response.contentLength ?? 0;
    final bytes = <int>[];
    int received = 0;

    await for (final chunk in response.stream) {
      bytes.addAll(chunk);
      received += chunk.length;
      if (contentLength > 0) {
        final pct = received / contentLength;
        onProgress?.call(0.1 + pct * 0.6, 'Đang tải bản vá: ${(pct * 100).toStringAsFixed(0)}%');
      }
    }

    onProgress?.call(0.75, 'Đang giải nén và nạp bản vá...');
    await _applyZipBytes(bytes, version: updateInfo.version);
    onProgress?.call(1.0, 'Đã hoàn tất cài đặt bản vá!');
    return true;
  }

  /// Applies a local patch zip file selected by user via FilePicker
  static Future<bool> applyLocalZipPatch(String localZipPath, {String? version}) async {
    final zipFile = File(localZipPath);
    if (!zipFile.existsSync()) {
      throw Exception('File zip không tồn tại: $localZipPath');
    }
    final bytes = zipFile.readAsBytesSync();
    return _applyZipBytes(bytes, version: version ?? p.basenameWithoutExtension(localZipPath));
  }

  /// Rolls back hot-patch, deleting the folder and restoring bundled engine
  static Future<void> rollbackPatch() async {
    final patchDir = EngineResolver.hotPatchDir;
    if (patchDir.existsSync()) {
      patchDir.deleteSync(recursive: true);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefInstalledVersionKey);
  }

  static Future<bool> _applyZipBytes(List<int> bytes, {String? version}) async {
    final archive = ZipDecoder().decodeBytes(bytes);
    final patchDir = EngineResolver.hotPatchDir;
    if (patchDir.existsSync()) {
      try {
        for (final entity in patchDir.listSync()) {
          entity.deleteSync(recursive: true);
        }
      } catch (_) {}
    } else {
      patchDir.createSync(recursive: true);
    }

    for (final file in archive) {
      final filename = file.name;
      if (filename.startsWith('__MACOSX') || filename.contains('/.')) continue;
      
      final outPath = p.join(patchDir.path, filename);
      if (file.isFile) {
        final data = file.content as List<int>;
        final outFile = File(outPath);
        outFile.parent.createSync(recursive: true);
        outFile.writeAsBytesSync(data, flush: true);
        _setPermissions(outFile.path);
      } else {
        Directory(outPath).createSync(recursive: true);
      }
    }

    if (version != null) {
      final prefs = await SharedPreferences.getInstance();
      final currentVer = prefs.getString(_prefInstalledVersionKey) ?? '1.0.0';
      await prefs.setString(_prefInstalledVersionKey, version);

      // Bắn telemetry ghi nhận cập nhật lõi thành công lên Super Admin
      try {
        final machineId = await LicenseService.getMachineId();
        final telemetryUri = Uri.parse('${AppConstants.defaultApiBaseUrl}/telemetry/update_success');
        http.post(
          telemetryUri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'machineId': machineId,
            'fromVersion': currentVer,
            'toVersion': version,
            'platform': Platform.isMacOS ? 'MACOS_ARM64' : 'WINDOWS_X64',
            'updateType': 'CORE_PATCH',
          }),
        ).timeout(const Duration(seconds: 4)).then((_) {}).catchError((_) {});
      } catch (_) {}
    }

    return true;
  }

  static void _copyDirectoryRecursive(Directory source, Directory destination) {
    destination.createSync(recursive: true);
    for (final entity in source.listSync(recursive: false)) {
      final newPath = p.join(destination.path, p.basename(entity.path));
      if (entity is Directory) {
        _copyDirectoryRecursive(entity, Directory(newPath));
      } else if (entity is File) {
        final destFile = File(newPath);
        entity.copySync(destFile.path);
        _setPermissions(destFile.path);
      }
    }
  }

  static void _setPermissions(String filePath) {
    if (Platform.isMacOS || Platform.isLinux) {
      try {
        Process.runSync('chmod', ['+x', filePath]);
      } catch (_) {}
      if (Platform.isMacOS) {
        try {
          Process.runSync('xattr', ['-d', 'com.apple.quarantine', filePath]);
        } catch (_) {}
      }
    }
  }
}
