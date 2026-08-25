import 'dart:math';

class AssUtils {
  /// Converts standard color names or hex strings (#RRGGBB / #AARRGGBB) to ASS format (&HAABBGGRR).
  /// Optional [opacity] (0.0 = transparent, 1.0 = fully opaque) adjusts the ASS Alpha channel.
  static String toAssColor(
    String? colorStr, {
    String defaultColor = '&H00FFFFFF',
    double? opacity,
  }) {
    String res = defaultColor;
    if (colorStr != null && colorStr.trim().isNotEmpty) {
      final c = colorStr.trim();
      if (c.startsWith('&H') || c.startsWith('&h')) {
        res = c.toUpperCase();
      } else {
        final namedColors = <String, String>{
          'white': '&H00FFFFFF',
          'yellow': '&H0000FFFF', // ASS is BGR: 00 (alpha) FF (blue) FF (green) 00 (red)
          'cyan': '&H00FFFF00',
          'red': '&H000000FF',
          'green': '&H0000FF00',
          'black': '&H00000000',
          'gold': '&H0000D7FF',
          'orange': '&H0000A5FF',
          'transparent': '&HFF000000',
          'lightgray': '&H00D0D0D0',
          'gray': '&H00808080',
        };

        final lower = c.toLowerCase();
        if (namedColors.containsKey(lower)) {
          res = namedColors[lower]!;
        } else if (c.startsWith('#') && c.length == 7) {
          // Hex #RRGGBB -> &H00BBGGRR
          final r = c.substring(1, 3);
          final g = c.substring(3, 5);
          final b = c.substring(5, 7);
          res = '&H00${b}${g}${r}'.toUpperCase();
        } else if (c.startsWith('#') && c.length == 9) {
          // Hex #AARRGGBB
          final a = c.substring(1, 3);
          final r = c.substring(3, 5);
          final g = c.substring(5, 7);
          final b = c.substring(7, 9);
          res = '&H${a}${b}${g}${r}'.toUpperCase();
        }
      }
    }

    // Apply explicit opacity if specified
    if (opacity != null && res.startsWith('&H') && res.length >= 10) {
      final clamped = opacity.clamp(0.0, 1.0);
      final alphaVal = ((1.0 - clamped) * 255.0).round();
      final alphaHex = alphaVal.toRadixString(16).padLeft(2, '0').toUpperCase();
      res = '&H$alphaHex${res.substring(4)}';
    }

    return res;
  }

  /// Generates ASS vector drawing commands for a rounded rectangle path.
  static String makeBoxPath(int width, int height, int radius) {
    final r = max(0, min(radius, min(height ~/ 2, width ~/ 2)));
    if (r <= 0) {
      return 'm 0 0 l $width 0 l $width $height l 0 $height';
    }
    return 'm $r 0 l ${width - r} 0 b $width 0 $width 0 $width $r l $width ${height - r} b $width $height $width $height ${width - r} $height l $r $height b 0 $height 0 $height 0 ${height - r} l 0 $r b 0 0 0 0 $r 0';
  }

  /// Formats seconds into standard ASS timestamp string (H:MM:SS.CC).
  static String formatAssTime(double seconds) {
    if (seconds < 0) seconds = 0;
    final totalHundredths = (seconds * 100).round();
    final hundredths = totalHundredths % 100;
    final totalSeconds = totalHundredths ~/ 100;
    final s = totalSeconds % 60;
    final totalMinutes = totalSeconds ~/ 60;
    final m = totalMinutes % 60;
    final h = totalMinutes ~/ 60;

    return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}.${hundredths.toString().padLeft(2, '0')}';
  }

  /// Automatically breaks long sentences into balanced, readable lines using ASS \\N.
  static String autoWrapText(String text, {int maxCharsPerLine = 28}) {
    final clean = text.trim();
    if (clean.length <= maxCharsPerLine || clean.contains(r'\N') || clean.contains('\n')) {
      return clean.replaceAll('\n', r'\N');
    }

    final words = clean.split(RegExp(r'\s+'));
    if (words.length <= 3) return clean;

    final lines = <String>[];
    String currentLine = '';

    for (final word in words) {
      if (currentLine.isEmpty) {
        currentLine = word;
      } else if (currentLine.length + 1 + word.length <= maxCharsPerLine) {
        currentLine += ' $word';
      } else {
        lines.add(currentLine);
        currentLine = word;
      }
    }
    if (currentLine.isNotEmpty) {
      lines.add(currentLine);
    }

    return lines.join(r'\N');
  }
}
