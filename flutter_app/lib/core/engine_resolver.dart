import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;

class EngineExecutionTarget {
  final String executable;
  final List<String> defaultPrefixArgs;
  final String source; // 'hot_patch', 'bundled', 'dev_source', or 'fallback'
  final bool isProcess;
  final String version;

  const EngineExecutionTarget({
    required this.executable,
    this.defaultPrefixArgs = const [],
    required this.source,
    this.isProcess = true,
    this.version = '1.0.0',
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

  static int compareSemVer(String v1, String v2) {
    final clean1 = v1.replaceAll(RegExp(r'[^0-9.]'), '');
    final clean2 = v2.replaceAll(RegExp(r'[^0-9.]'), '');
    final parts1 = clean1.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final parts2 = clean2.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    for (int i = 0; i < 3; i++) {
      final p1 = i < parts1.length ? parts1[i] : 0;
      final p2 = i < parts2.length ? parts2[i] : 0;
      if (p1 != p2) return p1.compareTo(p2);
    }
    return 0;
  }

  static String readEngineVersion(Directory dir) {
    try {
      final verFile = File(p.join(dir.path, 'VERSION'));
      if (verFile.existsSync()) return verFile.readAsStringSync().trim();
      final verFile2 = File(p.join(dir.path, 'py_engine', 'VERSION'));
      if (verFile2.existsSync()) return verFile2.readAsStringSync().trim();
      final manifest = File(p.join(dir.path, 'engine_manifest.json'));
      if (manifest.existsSync()) {
        final json = jsonDecode(manifest.readAsStringSync());
        if (json is Map && json['version'] != null) return json['version'].toString().trim();
      }
    } catch (_) {}
    return '0.0.0';
  }

  static File? _findMainFile(String basePath) {
    final candidates = [
      p.join(basePath, 'py_engine', 'main.py'),
      p.join(basePath, 'py_engine', 'main.pyc'),
      p.join(basePath, 'main.py'),
      p.join(basePath, 'main.pyc'),
    ];
    for (final path in candidates) {
      final f = File(path);
      if (f.existsSync()) return f;
    }
    return null;
  }

  /// Resolves the Python Engine execution target with SemVer priority:
  /// - If Hot-Patch version > (Bundled or Dev version): uses hot_patch.
  /// - Otherwise: uses dev_source (in development) or bundled (in release).
  static EngineExecutionTarget resolveEngine() {
    final pythonBin = findPythonBinary();

    // 1. Probe Dev Source
    final projectRoot = _findProjectRoot();
    File? devMain;
    String devVer = '0.0.0';
    if (projectRoot != null) {
      final candidate = _findMainFile(projectRoot.path);
      if (candidate != null) {
        devMain = candidate;
        devVer = readEngineVersion(Directory(p.join(projectRoot.path, 'py_engine')));
      }
    }

    // 2. Probe App Bundle Directory
    File? bundledMain;
    String bundledVer = '0.0.0';
    try {
      final execFile = File(Platform.resolvedExecutable);
      final appDir = execFile.parent;
      final resourcesDir = Platform.isMacOS ? appDir.parent.uri.resolve('Resources').toFilePath() : appDir.path;

      final bMain = _findMainFile(resourcesDir) ?? _findMainFile(appDir.path);
      if (bMain != null) {
        bundledMain = bMain;
        bundledVer = readEngineVersion(Directory(bMain.parent.path));
      }
    } catch (_) {}

    // 3. Probe Hot-Patch Directory
    File? patchMain;
    String patchVer = '0.0.0';
    final pMain = _findMainFile(hotPatchDir.path);
    if (pMain != null) {
      patchMain = pMain;
      patchVer = readEngineVersion(hotPatchDir);
    }

    // ── SEMVER-AWARE RESOLUTION ──
    // In Dev Mode: Dev source is authoritative unless HotPatch is strictly newer
    if (devMain != null) {
      if (patchMain != null && compareSemVer(patchVer, devVer) > 0) {
        return EngineExecutionTarget(
          executable: pythonBin,
          defaultPrefixArgs: [patchMain.path],
          source: 'hot_patch',
          version: patchVer,
        );
      }
      return EngineExecutionTarget(
        executable: pythonBin,
        defaultPrefixArgs: [devMain.path],
        source: 'dev_source',
        version: devVer,
      );
    }

    // In Bundled App Mode: Bundled resources authoritative unless HotPatch is strictly newer
    if (bundledMain != null) {
      if (patchMain != null && compareSemVer(patchVer, bundledVer) > 0) {
        return EngineExecutionTarget(
          executable: pythonBin,
          defaultPrefixArgs: [patchMain.path],
          source: 'hot_patch',
          version: patchVer,
        );
      }
      return EngineExecutionTarget(
        executable: pythonBin,
        defaultPrefixArgs: [bundledMain.path],
        source: 'bundled',
        version: bundledVer,
      );
    }

    // Fallback to Hot-Patch if available
    if (patchMain != null) {
      return EngineExecutionTarget(
        executable: pythonBin,
        defaultPrefixArgs: [patchMain.path],
        source: 'hot_patch',
        version: patchVer,
      );
    }

    // Default fallback
    final fallbackScript = File('py_engine/main.pyc').existsSync() ? 'py_engine/main.pyc' : 'py_engine/main.py';
    return EngineExecutionTarget(
      executable: pythonBin,
      defaultPrefixArgs: [fallbackScript],
      source: 'fallback',
      isProcess: true,
      version: '1.0.0',
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
