import 'package:flutter/material.dart';

/// Robust color parsing utility supporting ASS Subtitle BGR format, CSS Hex, and named colors.
class ColorParserUtils {
  /// Parses any color string into a Flutter Color
  static Color parse(String colorStr) {
    final s = colorStr.trim();
    if (s.isEmpty || s.toLowerCase() == 'none' || s.toLowerCase() == 'transparent') {
      return Colors.transparent;
    }

    final lower = s.toLowerCase();
    switch (lower) {
      case 'black':
        return Colors.black;
      case 'white':
        return Colors.white;
      case 'yellow':
        return const Color(0xFFFFFF00);
      case 'cyan':
        return const Color(0xFF00FFFF);
      case 'red':
        return const Color(0xFFFF0000);
      case '#1e1e1e':
        return const Color(0xFF1E1E1E);
      case '#0f172a':
        return const Color(0xFF0F172A);
      case '#334155':
        return const Color(0xFF334155);
    }

    // Check ASS subtitle format: &H[AA]BBGGRR or &HBBGGRR
    if (s.startsWith('&H') || s.startsWith('&h')) {
      final raw = s.substring(2).replaceAll('&', '').trim();
      if (raw.length == 8) {
        // &HAABBGGRR -> ASS Alpha: &H00 = 100% opaque, &HFF = transparent
        final a = int.tryParse(raw.substring(0, 2), radix: 16) ?? 0;
        final b = int.tryParse(raw.substring(2, 4), radix: 16) ?? 255;
        final g = int.tryParse(raw.substring(4, 6), radix: 16) ?? 255;
        final r = int.tryParse(raw.substring(6, 8), radix: 16) ?? 255;
        final alpha = (255 - a).clamp(0, 255);
        return Color.fromARGB(alpha, r, g, b);
      } else if (raw.length == 6) {
        // &HBBGGRR
        final b = int.tryParse(raw.substring(0, 2), radix: 16) ?? 255;
        final g = int.tryParse(raw.substring(2, 4), radix: 16) ?? 255;
        final r = int.tryParse(raw.substring(4, 6), radix: 16) ?? 255;
        return Color.fromARGB(255, r, g, b);
      }
    }

    // Check Hex CSS format: #RRGGBB or #AARRGGBB
    String cleanHex = s.startsWith('#') ? s.substring(1) : s;
    if (cleanHex.length == 6) {
      final val = int.tryParse(cleanHex, radix: 16);
      if (val != null) return Color(0xFF000000 | val);
    } else if (cleanHex.length == 8) {
      final val = int.tryParse(cleanHex, radix: 16);
      if (val != null) return Color(val);
    }

    return const Color(0xFF64748B);
  }

  /// Converts a Flutter Color to ASS Subtitle BGR format: &HAABBGGRR
  static String toAssString(Color color, {bool includeAlpha = true}) {
    // In ASS: &HAABBGGRR where Alpha: 00 = opaque, FF = transparent
    final assAlpha = (255 - color.alpha).toRadixString(16).padLeft(2, '0').toUpperCase();
    final r = color.red.toRadixString(16).padLeft(2, '0').toUpperCase();
    final g = color.green.toRadixString(16).padLeft(2, '0').toUpperCase();
    final b = color.blue.toRadixString(16).padLeft(2, '0').toUpperCase();

    if (includeAlpha && color.alpha < 255) {
      return '&H$assAlpha$b$g$r';
    }
    return '&H00$b$g$r';
  }

  /// Converts a Flutter Color to CSS Hex string: #RRGGBB or #AARRGGBB
  static String toHexString(Color color, {bool includeAlpha = false}) {
    final r = color.red.toRadixString(16).padLeft(2, '0').toUpperCase();
    final g = color.green.toRadixString(16).padLeft(2, '0').toUpperCase();
    final b = color.blue.toRadixString(16).padLeft(2, '0').toUpperCase();
    if (includeAlpha || color.alpha < 255) {
      final a = color.alpha.toRadixString(16).padLeft(2, '0').toUpperCase();
      return '#$a$r$g$b';
    }
    return '#$r$g$b';
  }
}

class ColorPreset {
  final String label;
  final String code;
  final Color previewColor;

  const ColorPreset({
    required this.label,
    required this.code,
    required this.previewColor,
  });
}
