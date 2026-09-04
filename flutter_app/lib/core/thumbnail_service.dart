import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'engine_resolver.dart';
import 'python_bridge.dart';

/// High-Performance Video Thumbnail & Metadata Service
/// Uses non-blocking background FFmpeg & FFprobe extraction with reactive ValueNotifiers
/// and 2-tier disk & memory caching.
class ThumbnailService {
  static final ThumbnailService instance = ThumbnailService._internal();
  ThumbnailService._internal();

  Directory? _cacheDir;
  final Set<String> _pendingTasks = <String>{};
  final Set<String> _pendingDurationTasks = <String>{};
  final Map<String, String> _memoryCache = <String, String>{};
  final Map<String, double> _durationCache = <String, double>{};
  final Map<String, ValueNotifier<String?>> _thumbnailNotifiers = <String, ValueNotifier<String?>>{};
  final Map<String, ValueNotifier<double?>> _durationNotifiers = <String, ValueNotifier<double?>>{};

  String _cachedFfmpegPath = '';
  String _cachedFfprobePath = '';

  /// Public accessor for testing or diagnostic probing
  String resolveBinary(String binaryName) => _resolveBinary(binaryName);

  /// Sanitize filename for cross-platform filesystem safety (NTFS/FAT/HFS)
  static String sanitizeFileName(String name) {
    return name.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
  }

  Future<void> init() async {
    if (_cacheDir != null && _cacheDir!.existsSync()) return;
    try {
      final appSupport = await getApplicationSupportDirectory();
      _cacheDir = Directory(p.join(appSupport.path, 'thumbnails'));
      if (!_cacheDir!.existsSync()) {
        _cacheDir!.createSync(recursive: true);
      }
    } catch (e) {
      debugPrint('[ThumbnailService] Error creating cache dir via getApplicationSupportDirectory: $e');
      try {
        final temp = Directory.systemTemp;
        _cacheDir = Directory(p.join(temp.path, 'subvideo_thumbnails'));
        if (!_cacheDir!.existsSync()) {
          _cacheDir!.createSync(recursive: true);
        }
      } catch (_) {}
    }
  }

  String _resolveBinary(String binaryName) {
    if (binaryName == 'ffmpeg' && _cachedFfmpegPath.isNotEmpty && File(_cachedFfmpegPath).existsSync()) {
      return _cachedFfmpegPath;
    }
    if (binaryName == 'ffprobe' && _cachedFfprobePath.isNotEmpty && File(_cachedFfprobePath).existsSync()) {
      return _cachedFfprobePath;
    }

    final ext = Platform.isWindows ? '.exe' : '';
    final binaryFile = '$binaryName$ext';
    final candidates = <String>[];

    // 1. App Executable Directory (Bundled Release or Installed App)
    try {
      final execFile = File(Platform.resolvedExecutable);
      final appDir = execFile.parent;

      // Direct layout: <AppDir>/bin/ffmpeg.exe or <AppDir>/ffmpeg.exe
      candidates.add(p.join(appDir.path, 'bin', binaryFile));
      candidates.add(p.join(appDir.path, binaryFile));

      // macOS Bundle layout: <App.app>/Contents/Resources/bin/ffmpeg or <App.app>/Contents/MacOS/ffmpeg
      if (Platform.isMacOS) {
        candidates.add(p.join(appDir.parent.path, 'Resources', 'bin', binaryName));
        candidates.add(p.join(appDir.parent.path, 'Resources', binaryName));
        candidates.add(p.join(appDir.path, binaryName));
      }
    } catch (_) {}

    // 2. Project Root Directory (Dev Mode)
    try {
      final rootDir = PythonBridge.resolveRootDir();
      candidates.add(p.join(rootDir, 'bin', binaryFile));
      if (Platform.isWindows) {
        // Windows cached download from build_windows_dist.ps1
        candidates.add(p.join(rootDir, '.cache_ffmpeg_win', 'extracted', binaryFile));
      }
    } catch (_) {}

    // 3. Hot-Patch Directory
    try {
      candidates.add(p.join(EngineResolver.hotPatchDir.path, 'bin', binaryFile));
      candidates.add(p.join(EngineResolver.hotPatchDir.path, binaryFile));
    } catch (_) {}

    // 4. Common Operating System / Package Manager Paths
    if (Platform.isWindows) {
      final localApp = Platform.environment['LOCALAPPDATA'] ?? '';
      final userProfile = Platform.environment['USERPROFILE'] ?? '';
      final programFiles = Platform.environment['ProgramFiles'] ?? 'C:\\Program Files';
      final programFilesX86 = Platform.environment['ProgramFiles(x86)'] ?? 'C:\\Program Files (x86)';

      candidates.addAll([
        'C:\\ffmpeg\\bin\\$binaryFile',
        p.join(programFiles, 'ffmpeg', 'bin', binaryFile),
        p.join(programFilesX86, 'ffmpeg', 'bin', binaryFile),
        'C:\\ProgramData\\chocolatey\\bin\\$binaryFile',
        if (localApp.isNotEmpty) p.join(localApp, 'Microsoft', 'WinGet', 'Links', binaryFile),
        if (userProfile.isNotEmpty) p.join(userProfile, 'scoop', 'shims', binaryFile),
      ]);
    } else if (Platform.isMacOS) {
      candidates.addAll([
        '/opt/homebrew/bin/$binaryName',
        '/usr/local/bin/$binaryName',
        '/usr/bin/$binaryName',
        '/bin/$binaryName',
      ]);
    } else {
      // Linux
      candidates.addAll([
        '/usr/bin/$binaryName',
        '/usr/local/bin/$binaryName',
        '/bin/$binaryName',
        '/snap/bin/$binaryName',
      ]);
    }

    // Check candidate paths on disk
    for (final candidate in candidates) {
      if (candidate.isNotEmpty && File(candidate).existsSync()) {
        if (binaryName == 'ffmpeg') _cachedFfmpegPath = candidate;
        if (binaryName == 'ffprobe') _cachedFfprobePath = candidate;
        return candidate;
      }
    }

    // 5. Dynamic PATH Lookup (where.exe on Windows, which on Unix)
    try {
      final cmd = Platform.isWindows ? 'where.exe' : 'which';
      final arg = Platform.isWindows ? binaryFile : binaryName;
      final result = Process.runSync(cmd, [arg]);
      if (result.exitCode == 0) {
        final lines = (result.stdout as String).split(RegExp(r'[\r\n]+'));
        for (final line in lines) {
          final trimmed = line.trim();
          if (trimmed.isNotEmpty && File(trimmed).existsSync()) {
            if (binaryName == 'ffmpeg') _cachedFfmpegPath = trimmed;
            if (binaryName == 'ffprobe') _cachedFfprobePath = trimmed;
            return trimmed;
          }
        }
      }
    } catch (_) {}

    // Fallback: return binary name (with .exe on Windows)
    return Platform.isWindows ? binaryFile : binaryName;
  }

  /// Get a reactive notifier for thumbnail path
  ValueNotifier<String?> getThumbnailNotifier(String videoPath) {
    if (!_thumbnailNotifiers.containsKey(videoPath)) {
      _thumbnailNotifiers[videoPath] = ValueNotifier<String?>(null);
      // Trigger background fetch/extraction
      getThumbnailPath(videoPath);
    } else {
      // If already cached, make sure value is set
      final cached = _memoryCache[videoPath];
      if (cached != null && _thumbnailNotifiers[videoPath]!.value != cached) {
        _thumbnailNotifiers[videoPath]!.value = cached;
      } else if (_thumbnailNotifiers[videoPath]!.value == null) {
        getThumbnailPath(videoPath);
      }
    }
    return _thumbnailNotifiers[videoPath]!;
  }

  /// Get a reactive notifier for video duration in seconds
  ValueNotifier<double?> getDurationNotifier(String videoPath) {
    if (!_durationNotifiers.containsKey(videoPath)) {
      _durationNotifiers[videoPath] = ValueNotifier<double?>(_durationCache[videoPath]);
      getVideoDuration(videoPath);
    } else if (_durationNotifiers[videoPath]!.value == null) {
      getVideoDuration(videoPath);
    }
    return _durationNotifiers[videoPath]!;
  }

  /// Returns cached thumbnail path if already generated, otherwise triggers background extraction.
  Future<String?> getThumbnailPath(String videoPath) async {
    if (videoPath.isEmpty) return null;
    final normVideo = p.normalize(p.absolute(videoPath));
    final file = File(normVideo);
    if (!file.existsSync()) return null;

    await init();
    if (_cacheDir == null) return null;

    final stat = file.statSync();
    final stem = sanitizeFileName(p.basenameWithoutExtension(normVideo));
    final safeName = '${stem}_${stat.size}_${stat.modified.millisecondsSinceEpoch}.jpg';
    final thumbPath = p.normalize(p.join(_cacheDir!.path, safeName));

    // 1. Check Memory Cache
    if (_memoryCache.containsKey(normVideo)) {
      final cached = _memoryCache[normVideo]!;
      if (File(cached).existsSync()) {
        _notifyThumbnail(normVideo, cached);
        return cached;
      }
    }

    // 2. Check Disk Cache
    if (File(thumbPath).existsSync()) {
      _memoryCache[normVideo] = thumbPath;
      _notifyThumbnail(normVideo, thumbPath);
      return thumbPath;
    }

    // 3. Queue background extraction if not already pending
    if (!_pendingTasks.contains(normVideo)) {
      _pendingTasks.add(normVideo);
      _extractThumbnailAsync(normVideo, thumbPath);
    }

    return null;
  }

  /// Get video duration in seconds using ffprobe with caching
  Future<double?> getVideoDuration(String videoPath) async {
    if (videoPath.isEmpty) return null;
    final normVideo = p.normalize(p.absolute(videoPath));
    if (_durationCache.containsKey(normVideo)) {
      return _durationCache[normVideo];
    }

    final file = File(normVideo);
    if (!file.existsSync()) return null;

    if (!_pendingDurationTasks.contains(normVideo)) {
      _pendingDurationTasks.add(normVideo);
      _probeDurationAsync(normVideo);
    }

    return null;
  }

  /// Directly probe video duration and return seconds
  Future<double> probeVideoDuration(String videoPath) async {
    if (videoPath.isEmpty) return 10.0;
    final normVideo = p.normalize(p.absolute(videoPath));
    if (_durationCache.containsKey(normVideo)) {
      return _durationCache[normVideo]!;
    }
    try {
      final ffprobePath = _resolveBinary('ffprobe');
      final result = await Process.run(
        ffprobePath,
        [
          '-v', 'error',
          '-show_entries', 'format=duration',
          '-of', 'default=noprint_wrappers=1:nokey=1',
          normVideo,
        ],
        runInShell: !p.isAbsolute(ffprobePath) && Platform.isWindows,
      );
      if (result.exitCode == 0) {
        final out = (result.stdout as String).trim();
        final dur = double.tryParse(out);
        if (dur != null && dur > 0) {
          _durationCache[normVideo] = dur;
          _notifyDuration(normVideo, dur);
          return dur;
        }
      }
    } catch (_) {}
    return 10.0;
  }

  void _notifyThumbnail(String videoPath, String thumbPath) {
    if (_thumbnailNotifiers.containsKey(videoPath)) {
      _thumbnailNotifiers[videoPath]!.value = thumbPath;
    }
  }

  void _notifyDuration(String videoPath, double duration) {
    _durationCache[videoPath] = duration;
    if (_durationNotifiers.containsKey(videoPath)) {
      _durationNotifiers[videoPath]!.value = duration;
    }
  }

  Future<void> _extractThumbnailAsync(String videoPath, String targetThumbPath) async {
    try {
      final ffmpegPath = _resolveBinary('ffmpeg');
      final normVideo = p.normalize(p.absolute(videoPath));
      final normThumb = p.normalize(p.absolute(targetThumbPath));

      // Fast seek 0.5s, 1 frame, scale to 240px width, low CPU cost (~20ms)
      final process = await Process.start(
        ffmpegPath,
        [
          '-ss', '00:00:00.5',
          '-i', normVideo,
          '-vframes', '1',
          '-q:v', '3',
          '-vf', 'scale=240:-1',
          normThumb,
          '-y',
        ],
        mode: ProcessStartMode.normal,
        runInShell: !p.isAbsolute(ffmpegPath) && Platform.isWindows,
      );

      final code = await process.exitCode;

      if (code == 0 && File(normThumb).existsSync()) {
        _memoryCache[videoPath] = normThumb;
        _notifyThumbnail(videoPath, normThumb);
      } else {
        // Fallback seek to 0s if 0.5s failed
        final retry = await Process.start(
          ffmpegPath,
          [
            '-i', normVideo,
            '-vframes', '1',
            '-q:v', '3',
            '-vf', 'scale=240:-1',
            normThumb,
            '-y',
          ],
          mode: ProcessStartMode.normal,
          runInShell: !p.isAbsolute(ffmpegPath) && Platform.isWindows,
        );
        await retry.exitCode;
        if (File(normThumb).existsSync()) {
          _memoryCache[videoPath] = normThumb;
          _notifyThumbnail(videoPath, normThumb);
        }
      }
    } catch (e) {
      debugPrint('[ThumbnailService] Extraction failed for $videoPath: $e');
    } finally {
      _pendingTasks.remove(videoPath);
    }
  }

  Future<void> _probeDurationAsync(String videoPath) async {
    try {
      final ffprobePath = _resolveBinary('ffprobe');
      final normVideo = p.normalize(p.absolute(videoPath));

      final result = await Process.run(
        ffprobePath,
        [
          '-v', 'error',
          '-show_entries', 'format=duration',
          '-of', 'default=noprint_wrappers=1:nokey=1',
          normVideo,
        ],
        runInShell: !p.isAbsolute(ffprobePath) && Platform.isWindows,
      );

      if (result.exitCode == 0) {
        final out = (result.stdout as String).trim();
        final dur = double.tryParse(out);
        if (dur != null && dur > 0) {
          _notifyDuration(videoPath, dur);
        }
      }
    } catch (e) {
      debugPrint('[ThumbnailService] FFprobe duration failed for $videoPath: $e');
    } finally {
      _pendingDurationTasks.remove(videoPath);
    }
  }

  /// Map to hold strip notifiers: key = "$videoPath#$startSec#$totalDuration#$frameCount"
  final Map<String, ValueNotifier<List<String?>>> _stripNotifiers = {};

  /// Get or create a strip notifier that provides a list of thumbnail paths for a video segment
  ValueNotifier<List<String?>> getStripNotifier(
    String videoPath,
    double totalDuration,
    double clipWidthPx, {
    double startSec = 0.0,
  }) {
    if (videoPath.isEmpty || totalDuration <= 0) {
      return ValueNotifier<List<String?>>([]);
    }

    const double cellWidth = 60.0;
    final int frameCount = (clipWidthPx / cellWidth).floor().clamp(1, 30);
    final key = '$videoPath#${startSec.toStringAsFixed(2)}#${totalDuration.toStringAsFixed(2)}#$frameCount';

    if (!_stripNotifiers.containsKey(key)) {
      final initialList = List<String?>.filled(frameCount, null);
      final notifier = ValueNotifier<List<String?>>(initialList);
      _stripNotifiers[key] = notifier;
      _generateStripAsync(videoPath, startSec, totalDuration, frameCount, notifier);
    }

    return _stripNotifiers[key]!;
  }

  Future<void> _generateStripAsync(
    String videoPath,
    double startSec,
    double totalDuration,
    int frameCount,
    ValueNotifier<List<String?>> notifier,
  ) async {
    final step = totalDuration / frameCount;
    for (int i = 0; i < frameCount; i++) {
      final sec = (startSec + i * step + step / 2).clamp(startSec, startSec + totalDuration);
      final thumbPath = await getThumbnailAtSecond(videoPath, sec);
      if (thumbPath != null) {
        final current = List<String?>.from(notifier.value);
        if (i < current.length) {
          current[i] = thumbPath;
          notifier.value = current;
        }
      }
    }
  }

  /// Returns cached thumbnail path at a specific second
  Future<String?> getThumbnailAtSecond(String videoPath, double atSec, {int targetWidth = 140}) async {
    if (videoPath.isEmpty) return null;
    final normVideo = p.normalize(p.absolute(videoPath));
    final file = File(normVideo);
    if (!file.existsSync()) return null;

    await init();
    if (_cacheDir == null) return null;

    final stat = file.statSync();
    final safeKey = '$normVideo@${atSec.toStringAsFixed(1)}';
    final stem = sanitizeFileName(p.basenameWithoutExtension(normVideo));
    final safeName = '${stem}_${stat.size}_s${atSec.toStringAsFixed(1).replaceAll('.', '_')}.jpg';
    final thumbPath = p.normalize(p.join(_cacheDir!.path, safeName));

    if (_memoryCache.containsKey(safeKey)) {
      final cached = _memoryCache[safeKey]!;
      if (File(cached).existsSync()) return cached;
    }

    if (File(thumbPath).existsSync()) {
      _memoryCache[safeKey] = thumbPath;
      return thumbPath;
    }

    // Extract asynchronously synchronously awaited here for precision
    try {
      final ffmpegPath = _resolveBinary('ffmpeg');
      final formattedSec = atSec.toStringAsFixed(2);

      final process = await Process.start(
        ffmpegPath,
        [
          '-ss', formattedSec,
          '-i', normVideo,
          '-vframes', '1',
          '-q:v', '4',
          '-vf', 'scale=$targetWidth:-1',
          thumbPath,
          '-y',
        ],
        mode: ProcessStartMode.normal,
        runInShell: !p.isAbsolute(ffmpegPath) && Platform.isWindows,
      );

      final code = await process.exitCode;
      if (code == 0 && File(thumbPath).existsSync()) {
        _memoryCache[safeKey] = thumbPath;
        return thumbPath;
      }
    } catch (e) {
      debugPrint('[ThumbnailService] getThumbnailAtSecond failed: $e');
    }

    return null;
  }

  /// Helper to format duration in seconds to MM:SS or HH:MM:SS
  static String formatDuration(double? seconds) {
    if (seconds == null || seconds <= 0) return '--:--';
    final totalSec = seconds.round();
    final h = totalSec ~/ 3600;
    final m = (totalSec % 3600) ~/ 60;
    final s = totalSec % 60;
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}
