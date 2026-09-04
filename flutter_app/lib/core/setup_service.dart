import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models_status.dart';
import 'python_bridge.dart';

class SetupService {
  static const String _keyProjectsDir = 'subvideo_projects_dir';
  static const String _keyModelsDir = 'subvideo_models_dir';
  static const String _keyFontsDir = 'subvideo_fonts_dir';
  static const String _keyProjectRoot = 'subvideo_project_root';
  static const String _keyPythonPath = 'subvideo_python_path';
  static const String _keyGcsKeyPath = 'subvideo_gcs_key_path';
  static const String _keyUseNativeEngine = 'subvideo_use_native_engine';

  /// Check if user prefers native Dart/Rust engine over Python legacy (default: true)
  static Future<bool> getUseNativeEngine() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyUseNativeEngine) ?? true;
  }

  /// Save user preference for native engine
  static Future<void> setUseNativeEngine(bool useNative) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyUseNativeEngine, useNative);
  }

  /// Get configured GCS Service Account Key JSON path (default: <projectRoot>/assets/gcs-key.json)
  static Future<String> getGcsKeyPath() async {
    final prefs = await SharedPreferences.getInstance();
    final custom = prefs.getString(_keyGcsKeyPath);
    if (custom != null && custom.isNotEmpty && File(custom).existsSync()) {
      return custom;
    }
    final rootDir = PythonBridge.resolveRootDir();
    final resKey = p.join(rootDir, 'resources', 'gcs-key.json');
    if (File(resKey).existsSync()) {
      return resKey;
    }
    final legacyKey = p.join(rootDir, 'assets', 'gcs-key.json');
    if (File(legacyKey).existsSync()) {
      return legacyKey;
    }
    return resKey;
  }

  /// Save configured GCS Service Account Key JSON path
  static Future<void> setGcsKeyPath(String keyPath) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyGcsKeyPath, keyPath);
  }

  /// Get configured projects parent directory (default: <projectRoot>/assets)
  static Future<String> getProjectsDir() async {
    final prefs = await SharedPreferences.getInstance();
    final custom = prefs.getString(_keyProjectsDir);
    if (custom != null && custom.isNotEmpty && Directory(custom).existsSync()) {
      return custom;
    }
    final rootDir = PythonBridge.resolveRootDir();
    final resDir = p.join(rootDir, 'resources');
    if (Directory(resDir).existsSync()) {
      return resDir;
    }
    return p.join(rootDir, 'assets');
  }

  /// Save configured projects parent directory
  static Future<void> setProjectsDir(String dirPath) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyProjectsDir, dirPath);
  }

  /// Get configured AI models directory (default: <projectRoot>/models)
  static Future<String> getModelsDir() async {
    final prefs = await SharedPreferences.getInstance();
    final custom = prefs.getString(_keyModelsDir);
    if (custom != null && custom.isNotEmpty && Directory(custom).existsSync()) {
      return custom;
    }
    final rootDir = PythonBridge.resolveRootDir();
    final defaultModelsDir = p.join(rootDir, 'models');
    return defaultModelsDir;
  }

  /// Save configured AI models directory
  static Future<void> setModelsDir(String dirPath) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyModelsDir, dirPath);
  }

  /// Get configured Fonts directory (default: <projectRoot>/assets/fonts)
  static Future<String> getFontsDir() async {
    final prefs = await SharedPreferences.getInstance();
    final custom = prefs.getString(_keyFontsDir);
    if (custom != null && custom.isNotEmpty && Directory(custom).existsSync()) {
      return custom;
    }
    final rootDir = PythonBridge.resolveRootDir();
    final defaultFontsDir = p.join(rootDir, 'assets', 'fonts');
    return defaultFontsDir;
  }

  /// Save configured Fonts directory
  static Future<void> setFontsDir(String dirPath) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyFontsDir, dirPath);
  }

  static Future<String?> getSavedProjectRoot() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyProjectRoot);
  }

  static Future<void> setSavedProjectRoot(String rootPath) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyProjectRoot, rootPath);
    PythonBridge.customRootDir = rootPath;
  }

  static Future<String?> getSavedPythonPath() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyPythonPath);
  }

  static Future<void> setSavedPythonPath(String pyPath) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyPythonPath, pyPath);
    PythonBridge.customPythonPath = pyPath;
  }

  /// Cross-platform user home directory
  static String get userHomeDir {
    if (Platform.isWindows) {
      return Platform.environment['USERPROFILE'] ??
          Platform.environment['LOCALAPPDATA'] ??
          Platform.environment['HOME'] ??
          '';
    }
    return Platform.environment['HOME'] ?? '';
  }

  /// Check status of all AI models and python environment using Global Auto-Discovery
  static Future<ModelsStatus> checkModels() async {
    final rootDir = PythonBridge.resolveRootDir();
    final modelsDir = await getModelsDir();
    final pythonBin = PythonBridge.resolvePythonBin();

    bool pythonFound = File(pythonBin).existsSync() ||
        (Platform.isWindows ? pythonBin == 'python.exe' : pythonBin == 'python3');

    final home = userHomeDir;
    final candidateBaseDirs = <Directory>[
      Directory(modelsDir),
      Directory(p.join(rootDir, 'models')),
      if (home.isNotEmpty) ...[
        Directory(p.join(home, '.cache')),
        Directory(p.join(home, '.cache', 'huggingface', 'hub')),
        Directory(p.join(home, '.cache', 'whisper')),
        Directory(p.join(home, '.cache', 'mlx-whisper')),
        Directory(p.join(home, '.cache', 'torch', 'hub', 'checkpoints')),
        Directory(p.join(home, '.paddleocr')),
      ],
      if (Platform.isWindows) ...[
        final localApp = Platform.environment['LOCALAPPDATA'] ?? '';
        if (localApp.isNotEmpty) ...[
          Directory(p.join(localApp, '.subvideo', 'models')),
          Directory(p.join(localApp, 'torch', 'hub', 'checkpoints')),
        ],
      ],
      if (Platform.isMacOS) ...[
        Directory(p.join(home, 'Library', 'Application Support', 'SubVideo', 'models')),
      ],
    ];

    bool hasAnyModelFile(List<String> subPaths, List<String> keywords) {
      // 1. Direct sub-paths check
      for (final base in candidateBaseDirs) {
        if (!base.existsSync()) continue;
        for (final sub in subPaths) {
          final target = Directory(p.join(base.path, sub));
          if (target.existsSync()) {
            try {
              if (target.listSync().isNotEmpty) return true;
            } catch (_) {}
          }
          final fileTarget = File(p.join(base.path, sub));
          if (fileTarget.existsSync()) return true;
        }
      }

      // 2. Keyword scan in cache directories
      for (final base in candidateBaseDirs) {
        if (!base.existsSync()) continue;
        try {
          for (final entity in base.listSync()) {
            final name = p.basename(entity.path).toLowerCase();
            for (final kw in keywords) {
              if (name.contains(kw.toLowerCase())) {
                if (entity is Directory) {
                  try {
                    if (entity.listSync().isNotEmpty) return true;
                  } catch (_) {}
                } else if (entity is File && entity.lengthSync() > 1024 * 1024) {
                  return true;
                }
              }
            }
          }
        } catch (_) {}
      }

      return false;
    }

    final whisperFound = hasAnyModelFile(
      ['whisper', 'mlx_models', 'ggml', 'base.pt', 'turbo.pt', 'small.pt', 'medium.pt', 'large-v3.pt'],
      ['whisper', 'mlx-community'],
    );

    final demucsFound = hasAnyModelFile(
      ['demucs', 'checkpoints', 'onnx', 'htdemucs.th', 'htdemucs_ft.th', 'htdemucs_2stem.onnx'],
      ['demucs', 'adefossez'],
    );

    final paddleFound = hasAnyModelFile(
      ['paddleocr', 'rapidocr'],
      ['paddle', 'paddlepaddle', 'rapidocr', 'uvdoc'],
    );

    return ModelsStatus(
      modelsDir: modelsDir,
      venvPath: pythonBin,
      pythonFound: pythonFound,
      whisperFound: whisperFound,
      demucsFound: demucsFound,
      paddleOcrFound: paddleFound,
    );
  }
}
