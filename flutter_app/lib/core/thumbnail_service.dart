import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

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

  Future<void> init() async {
    if (_cacheDir != null) return;
    try {
      final appSupport = await getApplicationSupportDirectory();
      _cacheDir = Directory(p.join(appSupport.path, 'thumbnails'));
      if (!_cacheDir!.existsSync()) {
        _cacheDir!.createSync(recursive: true);
      }
    } catch (e) {
      debugPrint('[ThumbnailService] Error creating cache dir: $e');
    }
  }

  String _resolveBinary(String binaryName) {
    if (binaryName == 'ffmpeg' && _cachedFfmpegPath.isNotEmpty) {
      return _cachedFfmpegPath;
    }
    if (binaryName == 'ffprobe' && _cachedFfprobePath.isNotEmpty) {
      return _cachedFfprobePath;
    }

    final possiblePaths = [
      '/opt/homebrew/bin/$binaryName',
      '/usr/local/bin/$binaryName',
      '/usr/bin/$binaryName',
    ];
    for (final pth in possiblePaths) {
      if (File(pth).existsSync()) {
        if (binaryName == 'ffmpeg') _cachedFfmpegPath = pth;
        if (binaryName == 'ffprobe') _cachedFfprobePath = pth;
        return pth;
      }
    }

    return binaryName;
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
    final file = File(videoPath);
    if (!file.existsSync()) return null;

    await init();
    if (_cacheDir == null) return null;

    final stat = file.statSync();
    final safeName = '${p.basenameWithoutExtension(videoPath)}_${stat.size}_${stat.modified.millisecondsSinceEpoch}.jpg';
    final thumbPath = p.join(_cacheDir!.path, safeName);

    // 1. Check Memory Cache
    if (_memoryCache.containsKey(videoPath)) {
      final cached = _memoryCache[videoPath]!;
      if (File(cached).existsSync()) {
        _notifyThumbnail(videoPath, cached);
        return cached;
      }
    }

    // 2. Check Disk Cache
    if (File(thumbPath).existsSync()) {
      _memoryCache[videoPath] = thumbPath;
      _notifyThumbnail(videoPath, thumbPath);
      return thumbPath;
    }

    // 3. Queue background extraction if not already pending
    if (!_pendingTasks.contains(videoPath)) {
      _pendingTasks.add(videoPath);
      _extractThumbnailAsync(videoPath, thumbPath);
    }

    return null;
  }

  /// Get video duration in seconds using ffprobe with caching
  Future<double?> getVideoDuration(String videoPath) async {
    if (videoPath.isEmpty) return null;
    if (_durationCache.containsKey(videoPath)) {
      return _durationCache[videoPath];
    }

    final file = File(videoPath);
    if (!file.existsSync()) return null;

    if (!_pendingDurationTasks.contains(videoPath)) {
      _pendingDurationTasks.add(videoPath);
      _probeDurationAsync(videoPath);
    }

    return _durationCache[videoPath];
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

      // Fast seek 0.5s, 1 frame, scale to 240px width, low CPU cost (~20ms)
      final process = await Process.start(
        ffmpegPath,
        [
          '-ss', '00:00:00.5',
          '-i', videoPath,
          '-vframes', '1',
          '-q:v', '3',
          '-vf', 'scale=240:-1',
          targetThumbPath,
          '-y',
        ],
        mode: ProcessStartMode.normal,
      );

      final code = await process.exitCode;

      if (code == 0 && File(targetThumbPath).existsSync()) {
        _memoryCache[videoPath] = targetThumbPath;
        _notifyThumbnail(videoPath, targetThumbPath);
      } else {
        // Fallback seek to 0s if 0.5s failed
        final retry = await Process.start(
          ffmpegPath,
          [
            '-i', videoPath,
            '-vframes', '1',
            '-q:v', '3',
            '-vf', 'scale=240:-1',
            targetThumbPath,
            '-y',
          ],
          mode: ProcessStartMode.normal,
        );
        await retry.exitCode;
        if (File(targetThumbPath).existsSync()) {
          _memoryCache[videoPath] = targetThumbPath;
          _notifyThumbnail(videoPath, targetThumbPath);
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

      final result = await Process.run(
        ffprobePath,
        [
          '-v', 'error',
          '-show_entries', 'format=duration',
          '-of', 'default=noprint_wrappers=1:nokey=1',
          videoPath,
        ],
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
