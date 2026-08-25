import 'dart:io';
import 'package:path/path.dart' as p;
import 'python_bridge.dart';

class FontOption {
  final String name;
  final bool isCustom;
  final String? filePath;

  const FontOption({
    required this.name,
    this.isCustom = false,
    this.filePath,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FontOption && runtimeType == other.runtimeType && name == other.name;

  @override
  int get hashCode => name.hashCode;
}

class FontDiscoveryService {
  static const List<String> systemFonts = [
    'Arial',
    'SF Pro Display',
    'Helvetica',
    'Montserrat',
    'Be Vietnam Pro',
    'Roboto',
    'Times New Roman',
    'Impact',
    'Courier New',
    'Verdana',
    'Georgia',
  ];

  /// Scans configured fontsDir and returns unique font options
  static List<FontOption> getAvailableFonts({String? fontsDir, String? projectDir}) {
    final Map<String, FontOption> result = {};

    // 1. Scan configured fontsDir
    final candidateDirs = <Directory>[];

    if (fontsDir != null && fontsDir.trim().isNotEmpty) {
      final dir = Directory(fontsDir.trim());
      if (dir.isAbsolute && dir.existsSync()) {
        candidateDirs.add(dir);
      } else {
        // Relative to projectDir or rootDir
        if (projectDir != null && Directory(projectDir).existsSync()) {
          final pDir = Directory(p.join(projectDir, fontsDir.trim()));
          if (pDir.existsSync()) candidateDirs.add(pDir);
        }
        final rootDir = PythonBridge.resolveRootDir();
        final rDir = Directory(p.join(rootDir, fontsDir.trim()));
        if (rDir.existsSync()) candidateDirs.add(rDir);
      }
    }

    // Default resources/fonts or assets/fonts fallback
    final rootDir = PythonBridge.resolveRootDir();
    final defaultResFonts = Directory(p.join(rootDir, 'resources', 'fonts'));
    final defaultAssetsFonts = Directory(p.join(rootDir, 'assets', 'fonts'));
    if (defaultResFonts.existsSync() && !candidateDirs.any((d) => d.path == defaultResFonts.path)) {
      candidateDirs.add(defaultResFonts);
    } else if (defaultAssetsFonts.existsSync() && !candidateDirs.any((d) => d.path == defaultAssetsFonts.path)) {
      candidateDirs.add(defaultAssetsFonts);
    }

    // Scan found directories
    for (final dir in candidateDirs) {
      try {
        final entities = dir.listSync().whereType<File>();
        for (final file in entities) {
          final ext = p.extension(file.path).toLowerCase();
          if (ext == '.ttf' || ext == '.otf' || ext == '.ttc') {
            final stem = p.basenameWithoutExtension(file.path);
            final cleanName = _cleanFontName(stem);
            if (cleanName.isNotEmpty) {
              result[cleanName] = FontOption(
                name: cleanName,
                isCustom: true,
                filePath: file.path,
              );
            }
          }
        }
      } catch (_) {}
    }

    // 2. Merge with system fonts
    for (final sysFont in systemFonts) {
      if (!result.containsKey(sysFont)) {
        result[sysFont] = FontOption(name: sysFont, isCustom: false);
      }
    }

    return result.values.toList();
  }

  static String _cleanFontName(String stem) {
    // e.g. BeVietnamPro-Bold -> Be Vietnam Pro
    // Roboto-Regular -> Roboto
    var s = stem.replaceAll(RegExp(r'[-_](Bold|Regular|Italic|Light|Medium|Black|SemiBold|Thin|ExtraBold)', caseSensitive: false), '');
    // Insert spaces between camelCase if not present
    s = s.replaceAllMapped(RegExp(r'([a-z])([A-Z])'), (m) => '${m[1]} ${m[2]}');
    s = s.replaceAll('_', ' ').replaceAll('-', ' ').trim();
    return s.isNotEmpty ? s : stem;
  }
}
