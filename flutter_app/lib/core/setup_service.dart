import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models_status.dart';
import 'python_bridge.dart';

class SetupService {
  static const String _keyProjectsDir = 'subvideo_projects_dir';
  static const String _keyModelsDir = 'subvideo_models_dir';
  static const String _keyProjectRoot = 'subvideo_project_root';
  static const String _keyPythonPath = 'subvideo_python_path';
  static const String _keyGcsKeyPath = 'subvideo_gcs_key_path';

  /// Get configured GCS Service Account Key JSON path (default: <projectRoot>/assets/gcs-key.json)
  static Future<String> getGcsKeyPath() async {
    final prefs = await SharedPreferences.getInstance();
    final custom = prefs.getString(_keyGcsKeyPath);
    if (custom != null && custom.isNotEmpty && File(custom).existsSync()) {
      return custom;
    }
    final rootDir = PythonBridge.resolveRootDir();
    final defaultKey = p.join(rootDir, 'assets', 'gcs-key.json');
    return defaultKey;
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
    final defaultAssets = p.join(rootDir, 'assets');
    return defaultAssets;
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

  /// Check status of all AI models and python environment
  static Future<ModelsStatus> checkModels() async {
    final rootDir = PythonBridge.resolveRootDir();
    final modelsDir = await getModelsDir();
    final pythonBin = PythonBridge.resolvePythonBin();

    bool pythonFound = File(pythonBin).existsSync() ||
        (Platform.isWindows ? pythonBin == 'python.exe' : pythonBin == 'python3');

    // Run python verification script
    const pyCode = '''
import json, sys, os, pathlib

models_dir = pathlib.Path(sys.argv[1])
root_dir = pathlib.Path(sys.argv[2])
home_dir = pathlib.Path.home()

def has_files(d):
    try:
        return d.exists() and any(d.iterdir())
    except Exception:
        return False

def check_patterns(base_dirs, keywords):
    for b in base_dirs:
        if not b.exists():
            continue
        try:
            for item in b.iterdir():
                name = item.name.lower()
                for kw in keywords:
                    if kw.lower() in name:
                        return True
        except Exception:
            pass
    return False

hf_hub_dirs = [
    models_dir / "huggingface" / "hub",
    home_dir / ".cache" / "huggingface" / "hub",
]

whisper_dirs = [
    models_dir / "mlx_models",
    models_dir / "whisper",
    home_dir / ".cache" / "whisper",
    home_dir / ".cache" / "mlx-whisper",
]

demucs_dirs = [
    models_dir / "demucs",
    home_dir / ".cache" / "torch" / "hub" / "checkpoints",
]

paddle_dirs = [
    models_dir / "paddleocr",
    home_dir / ".paddleocr",
]

whisper_found = any(has_files(d) for d in whisper_dirs) or check_patterns(hf_hub_dirs, ["whisper", "mlx-community"])
demucs_found = any(has_files(d) for d in demucs_dirs) or check_patterns(hf_hub_dirs, ["demucs", "adefossez"])
paddle_found = any(has_files(d) for d in paddle_dirs) or check_patterns(hf_hub_dirs, ["paddle", "paddlepaddle", "uvdoc"])

status = {
    "models_dir": str(models_dir),
    "whisper_found": bool(whisper_found),
    "demucs_found": bool(demucs_found),
    "paddleocr_found": bool(paddle_found),
    "python_found": True,
}
print(json.dumps(status))
''';

    try {
      final res = await PythonBridge.runCode(pyCode, extraArgs: [modelsDir, rootDir]);
      if (res.exitCode == 0) {
        final text = res.stdout.toString().trim();
        final lines = text.split('\n');
        final lastLine = lines.isNotEmpty ? lines.last : '{}';
        final data = jsonDecode(lastLine) as Map<String, dynamic>;
        return ModelsStatus(
          modelsDir: modelsDir,
          venvPath: pythonBin,
          pythonFound: true,
          whisperFound: data['whisper_found'] as bool? ?? false,
          demucsFound: data['demucs_found'] as bool? ?? false,
          paddleOcrFound: data['paddleocr_found'] as bool? ?? false,
        );
      }
    } catch (_) {}

    // Fallback file-based check in Dart
    final home = Platform.environment['HOME'] ?? '';
    final hfHub = Directory(p.join(home, '.cache', 'huggingface', 'hub'));
    final hfLocal = Directory(p.join(modelsDir, 'huggingface', 'hub'));

    bool checkAnyPattern(List<String> keywords) {
      final dirsToCheck = [hfHub, hfLocal, Directory(modelsDir)];
      for (final d in dirsToCheck) {
        if (!d.existsSync()) continue;
        try {
          final entries = d.listSync();
          for (final entry in entries) {
            final name = p.basename(entry.path).toLowerCase();
            for (final kw in keywords) {
              if (name.contains(kw.toLowerCase())) return true;
            }
          }
        } catch (_) {}
      }
      return false;
    }

    final whisperFound = Directory(p.join(modelsDir, 'mlx_models')).existsSync() ||
        checkAnyPattern(['whisper', 'mlx-community']);
    final demucsFound = Directory(p.join(modelsDir, 'demucs')).existsSync() ||
        checkAnyPattern(['demucs', 'adefossez']);
    final paddleFound = Directory(p.join(modelsDir, 'paddleocr')).existsSync() ||
        Directory(p.join(home, '.paddleocr')).existsSync() ||
        checkAnyPattern(['paddle', 'paddlepaddle']);

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
