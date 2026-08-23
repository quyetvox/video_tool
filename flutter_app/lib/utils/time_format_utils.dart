class TimeFormatUtils {
  /// Format seconds into subtitle timecode: 00:01:23,450
  static String formatSubtitleTime(double sec) {
    if (sec.isNaN || sec < 0) return '00:00:00,000';
    final int totalSec = sec.floor();
    final int hrs = totalSec ~/ 3600;
    final int mins = (totalSec % 3600) ~/ 60;
    final int secs = totalSec % 60;
    final int ms = ((sec - totalSec) * 1000).round().clamp(0, 999);

    final hStr = hrs.toString().padLeft(2, '0');
    final mStr = mins.toString().padLeft(2, '0');
    final sStr = secs.toString().padLeft(2, '0');
    final msStr = ms.toString().padLeft(3, '0');

    return '$hStr:$mStr:$sStr,$msStr';
  }

  /// Parse timecode string (00:01:23,450 or 01:23.45 or 83.45) into seconds
  static double parseTimecodeToSeconds(String str) {
    final s = str.trim().replaceAll(',', '.');
    if (s.isEmpty) return 0.0;

    if (s.contains(':')) {
      final parts = s.split(':');
      if (parts.length == 3) {
        final h = double.tryParse(parts[0]) ?? 0.0;
        final m = double.tryParse(parts[1]) ?? 0.0;
        final sec = double.tryParse(parts[2]) ?? 0.0;
        return (h * 3600 + m * 60 + sec).clamp(0.0, double.infinity);
      } else if (parts.length == 2) {
        final m = double.tryParse(parts[0]) ?? 0.0;
        final sec = double.tryParse(parts[1]) ?? 0.0;
        return (m * 60 + sec).clamp(0.0, double.infinity);
      }
    }

    final f = double.tryParse(s);
    return (f ?? 0.0).clamp(0.0, double.infinity);
  }

  /// Format seconds into player duration display: 01:23 or 01:23:45
  static String formatDuration(double sec) {
    if (sec.isNaN || sec < 0) return '00:00';
    final int totalSec = sec.floor();
    final int hrs = totalSec ~/ 3600;
    final int mins = (totalSec % 3600) ~/ 60;
    final int secs = totalSec % 60;

    final mStr = mins.toString().padLeft(2, '0');
    final sStr = secs.toString().padLeft(2, '0');

    if (hrs > 0) {
      final hStr = hrs.toString().padLeft(2, '0');
      return '$hStr:$mStr:$sStr';
    }
    return '$mStr:$sStr';
  }

  /// Format bytes into human readable size: 12.4 MB
  static String formatFileSize(int bytes) {
    if (bytes <= 0) return '0 B';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}
