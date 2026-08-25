import 'dart:io';
import 'package:path/path.dart' as p;

class EngineExecutionTarget {
  final String executable;
  final List<String> defaultPrefixArgs;
  final String source; // 'hot_patch', 'bundled', 'dev_source', or 'fallback'
  final bool isProcess;

  const EngineExecutionTarget({
    required this.executable,
    this.defaultPrefixArgs = const [],
    required this.source,
    this.isProcess = true,
  });
}

class EngineResolver {
  static String? customPythonPath;

  static Directory get hotPatchDir {
    final home = Platform.isWindows
        ? (Platform.environment['LOCALAPPDATA'] ?? Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'] ?? '')
        : (Platform.environment['HOME'] ?? '');
    if (Platform.isMacOS) {
      return Directory(p.join(home, 'Library', 'Application Support', 'SubVideo', 'engine'));
    }
    return Directory(p.join(home, '.subvideo', 'engine'));
  }

  /// Resolves the Python Engine execution target with priority:
  /// 1. Hot-Patch Python Script (`~/Library/Application Support/SubVideo/engine/py_engine/main.py`)
  /// 2. Bundled Script inside App Bundle (`<AppDir>/Contents/Resources/py_engine/main.py`)
  /// 3. Developer source mode (`<ProjectRoot>/py_engine/main.py`)
  static EngineExecutionTarget resolveEngine() {
    final pythonBin = findPythonBinary();

    // 1. Check Hot-Patch Directory for py_engine
    final patchMain = File(p.join(hotPatchDir.path, 'py_engine', 'main.py'));
    if (patchMain.existsSync()) {
      return EngineExecutionTarget(
        executable: pythonBin,
        defaultPrefixArgs: [patchMain.path],
        source: 'hot_patch',
      );
    }

    // 2. Check App Bundle Directory for py_engine
    try {
      final execFile = File(Platform.resolvedExecutable);
      final appDir = execFile.parent;
      final resourcesDir = Platform.isMacOS ? appDir.parent.uri.resolve('Resources').toFilePath() : appDir.path;
      
      final bundledMain = File(p.join(resourcesDir, 'py_engine', 'main.py'));
      if (bundledMain.existsSync()) {
        return EngineExecutionTarget(
          executable: pythonBin,
          defaultPrefixArgs: [bundledMain.path],
          source: 'bundled',
        );
      }

      final directBundled = File(p.join(appDir.path, 'py_engine', 'main.py'));
      if (directBundled.existsSync()) {
        return EngineExecutionTarget(
          executable: pythonBin,
          defaultPrefixArgs: [directBundled.path],
          source: 'bundled',
        );
      }
    } catch (_) {}

    // 3. Check Dev Source Mode (Project root detection)
    final projectRoot = _findProjectRoot();
    if (projectRoot != null) {
      final devMain = File(p.join(projectRoot.path, 'py_engine', 'main.py'));
      if (devMain.existsSync()) {
        return EngineExecutionTarget(
          executable: pythonBin,
          defaultPrefixArgs: [devMain.path],
          source: 'dev_source',
        );
      }
    }

    // 4. Fallback default
    return EngineExecutionTarget(
      executable: pythonBin,
      defaultPrefixArgs: ['py_engine/main.py'],
      source: 'fallback',
      isProcess: true,
    );
  }

  /// Finds Python binary with priority:
  /// 1. Custom configured path
  /// 2. Hot-Patch standalone python (`~/Library/Application Support/SubVideo/engine/python/bin/python3`)
  /// 3. App Bundle embedded standalone python (`Contents/Frameworks/python/bin/python3`)
  /// 4. Dev environment venv (`<ProjectRoot>/.venv/bin/python`)
  /// 5. System python3
  static String findPythonBinary() {
    if (customPythonPath != null && customPythonPath!.isNotEmpty && File(customPythonPath!).existsSync()) {
      return customPythonPath!;
    }

    final isWindows = Platform.isWindows;

    // 1. Hot-Patch Python
    final patchPy = File(p.join(
      hotPatchDir.path,
      'python',
      isWindows ? 'python.exe' : 'bin/python3',
    ));
    if (patchPy.existsSync()) {
      _ensureExecutable(patchPy.path);
      return patchPy.path;
    }

    // 2. App Bundle Embedded Python
    try {
      final execFile = File(Platform.resolvedExecutable);
      final appDir = execFile.parent;

      // macOS Frameworks layout: <App.app>/Contents/Frameworks/python/bin/python3
      if (Platform.isMacOS) {
        final fwPy = File(p.join(appDir.parent.path, 'Frameworks', 'python', 'bin', 'python3'));
        if (fwPy.existsSync()) {
          _ensureExecutable(fwPy.path);
          return fwPy.path;
        }
      }

      // Windows / Linux direct layout: <AppDir>/python/python.exe
      final directPy = File(p.join(appDir.path, 'python', isWindows ? 'python.exe' : 'bin/python3'));
      if (directPy.existsSync()) {
        _ensureExecutable(directPy.path);
        return directPy.path;
      }
    } catch (_) {}

    // 3. Dev Environment .venv
    final projectRoot = _findProjectRoot();
    if (projectRoot != null) {
      final venvPy = File(p.join(
        projectRoot.path,
        '.venv',
        isWindows ? 'Scripts/python.exe' : 'bin/python',
      ));
      if (venvPy.existsSync()) {
        return venvPy.path;
      }
    }

    // 4. System Python candidates
    final systemCandidates = isWindows
        ? ['python.exe', 'python3.exe']
        : [
            '/opt/homebrew/bin/python3',
            '/usr/local/bin/python3',
            '/usr/bin/python3',
            'python3',
            'python',
          ];

    for (final c in systemCandidates) {
      if (c.startsWith('/') && File(c).existsSync()) {
        return c;
      }
      try {
        final whichCmd = isWindows ? 'where' : 'which';
        final res = Process.runSync(whichCmd, [c]);
        if (res.exitCode == 0 && res.stdout.toString().trim().isNotEmpty) {
          final firstLine = res.stdout.toString().trim().split('\n').first.trim();
          if (File(firstLine).existsSync()) {
            return firstLine;
          }
        }
      } catch (_) {}
    }

    return isWindows ? 'python.exe' : 'python3';
  }

  static void _ensureExecutable(String filePath) {
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

  static Directory? _findProjectRoot() {
    Directory curr = Directory.current.absolute;
    for (int i = 0; i < 10; i++) {
      if ((File(p.join(curr.path, 'config.yaml')).existsSync() ||
              Directory(p.join(curr.path, 'resources')).existsSync() ||
              Directory(p.join(curr.path, 'assets')).existsSync()) &&
          Directory(p.join(curr.path, 'py_engine')).existsSync()) {
        return curr;
      }
      final parent = curr.parent;
      if (parent.path == curr.path) break;
      curr = parent;
    }

    final knownDevRoot = Directory('/Users/voquyt/Documents/projects/video/Sub-Video');
    if (knownDevRoot.existsSync()) {
      return knownDevRoot;
    }

    return null;
  }
}
