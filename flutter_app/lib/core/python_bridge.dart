import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import '../models/job_info.dart';
import '../utils/ansi_strip_utils.dart';
import 'ai_environment_service.dart';
import 'engine_resolver.dart';

class JobResult {
  final String jobId;
  final int exitCode;
  final bool success;
  final String? error;
  final List<String> stdoutLines;
  final List<String> stderrLines;

  const JobResult({
    required this.jobId,
    required this.exitCode,
    required this.success,
    this.error,
    this.stdoutLines = const [],
    this.stderrLines = const [],
  });

  String get output => stdoutLines.join('\n');
  String get message => error ?? (stderrLines.isNotEmpty ? stderrLines.join('\n') : output);
}

class PythonBridge {
  static final Map<String, Process> _activeProcesses = {};
  static final Map<String, StreamController<LogEntry>> _jobLogControllers = {};
  static final StreamController<LogEntry> _globalLogController = StreamController<LogEntry>.broadcast();
  static final Map<String, Queue<LogEntry>> _logBuffers = {};
  static const int maxBufferLines = 1000;

  static String? customRootDir;
  static String? customPythonPath;

  /// Global log broadcast stream
  static Stream<LogEntry> get globalLogStream => _globalLogController.stream;

  /// Job specific log broadcast stream
  static Stream<LogEntry> streamLogs(String jobId) {
    if (!_jobLogControllers.containsKey(jobId)) {
      _jobLogControllers[jobId] = StreamController<LogEntry>.broadcast();
    }
    return _jobLogControllers[jobId]!.stream;
  }

  /// Get cached buffered logs for a jobId or 'global'
  static List<LogEntry> getBufferedLogs(String jobId) {
    return _logBuffers[jobId]?.toList() ?? [];
  }

  /// Resolve project root directory
  static String resolveRootDir() {
    if (customRootDir != null && customRootDir!.isNotEmpty && Directory(customRootDir!).existsSync()) {
      return customRootDir!;
    }

    bool isSubVideoRoot(Directory d) {
      final hasMain = File(p.join(d.path, 'py_engine', 'main.py')).existsSync() ||
          File(p.join(d.path, 'py_engine', 'main.pyc')).existsSync() ||
          File(p.join(d.path, 'main.py')).existsSync() ||
          File(p.join(d.path, 'main.pyc')).existsSync();
      final hasEngine = Directory(p.join(d.path, 'py_engine')).existsSync() ||
          Directory(p.join(d.path, 'video_engine')).existsSync() ||
          Directory(p.join(d.path, 'lib')).existsSync();
      final hasData = Directory(p.join(d.path, 'assets')).existsSync() ||
          Directory(p.join(d.path, 'models')).existsSync();
      return (hasMain || hasEngine) && hasData;
    }

    // 1. Check Platform.resolvedExecutable parent hierarchy
    try {
      var execDir = File(Platform.resolvedExecutable).parent;
      for (int i = 0; i < 10; i++) {
        if (isSubVideoRoot(execDir)) {
          return execDir.path;
        }
        final parent = execDir.parent;
        if (parent.path == execDir.path) break;
        execDir = parent;
      }
    } catch (_) {}

    // 2. Auto-detect project root by walking up from current directory
    var current = Directory.current.absolute;
    for (int i = 0; i < 10; i++) {
      if (isSubVideoRoot(current)) {
        return current.path;
      }
      final parent = current.parent;
      if (parent.path == current.path) break;
      current = parent;
    }

    // 3. Fallback known standard locations if present
    final standardPaths = [
      '/Users/voquyt/Documents/projects/video/Sub-Video',
      p.join(Platform.environment['HOME'] ?? '', 'Documents', 'projects', 'video', 'Sub-Video'),
    ];
    for (final sp in standardPaths) {
      if (sp.isNotEmpty && Directory(sp).existsSync() && isSubVideoRoot(Directory(sp))) {
        return sp;
      }
    }

    return Directory.current.absolute.path;
  }

  /// Resolve python executable path
  static String resolvePythonBin() {
    if (customPythonPath != null && customPythonPath!.isNotEmpty && File(customPythonPath!).existsSync()) {
      return customPythonPath!;
    }
    return EngineResolver.findPythonBinary();
  }

  /// Build unified cross-platform environment with AI runtime injection
  static Map<String, String> buildEnvironment({required String rootDir, required String pythonBin}) {
    final env = Map<String, String>.from(Platform.environment);
    env['PYTHONUNBUFFERED'] = '1';
    env['PAGER'] = 'cat';
    env['PYTHONIOENCODING'] = 'utf-8';

    final pathSep = Platform.isWindows ? ';' : ':';
    final pyEnginePath = p.join(rootDir, 'py_engine');
    final aiPackagesPath = AiEnvironmentService.sitePackagesDir.path;

    var pythonPath = pyEnginePath;
    if (Directory(aiPackagesPath).existsSync()) {
      pythonPath = '$aiPackagesPath$pathSep$pythonPath';
    }
    env['PYTHONPATH'] = '$pythonPath$pathSep${env['PYTHONPATH'] ?? ''}';

    final currentPath = env['PATH'] ?? '';
    if (Platform.isWindows) {
      final binDir = p.join(rootDir, 'bin');
      final pyBin = p.dirname(pythonBin);
      final torchLib = p.join(aiPackagesPath, 'torch', 'lib');
      final torchLibPart = Directory(torchLib).existsSync() ? '$torchLib$pathSep' : '';
      env['PATH'] = '$binDir$pathSep$pyBin$pathSep$torchLibPart$currentPath';
    } else {
      env['PATH'] = '/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin:$currentPath';
      env['DYLD_LIBRARY_PATH'] = EngineResolver.hotPatchDir.path;
    }

    return env;
  }

  /// Add log entry and broadcast to subscribers / buffer
  static void addLog(String jobId, String type, String rawText) {
    final clean = AnsiStripUtils.stripAnsi(rawText).trimRight();
    if (clean.isEmpty) return;

    final now = DateTime.now();
    final timeStr = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
    final entry = LogEntry(
      id: '${now.millisecondsSinceEpoch}_${now.microsecond}',
      jobId: jobId,
      type: type,
      text: clean,
      time: timeStr,
    );

    // 1. Add to buffer
    _logBuffers.putIfAbsent(jobId, () => Queue<LogEntry>());
    final buf = _logBuffers[jobId]!;
    if (buf.length >= maxBufferLines) {
      buf.removeFirst();
    }
    buf.add(entry);

    // Add to global buffer
    _logBuffers.putIfAbsent('global', () => Queue<LogEntry>());
    final globalQueue = _logBuffers['global']!;
    globalQueue.addLast(entry);
    if (globalQueue.length > maxBufferLines) globalQueue.removeFirst();

    // 2. Emit to job stream if active
    if (_jobLogControllers.containsKey(jobId) && !_jobLogControllers[jobId]!.isClosed) {
      _jobLogControllers[jobId]!.add(entry);
    }

    // 3. Emit to global stream
    if (!_globalLogController.isClosed) {
      _globalLogController.add(entry);
    }
  }

  static void _addLog(String jobId, String type, String rawLine) => addLog(jobId, type, rawLine);

  /// Execute a Python script with real-time log streaming
  static Future<JobResult> runScript(
    String script,
    List<String> args, {
    String? jobId,
    String? rootDirOverride,
    void Function(int percent)? onProgress,
  }) async {
    final actualJobId = jobId ?? 'job_${DateTime.now().millisecondsSinceEpoch}';
    final rootDir = rootDirOverride ?? resolveRootDir();
    final pythonBin = resolvePythonBin();
    
    String scriptPath;
    if (p.isAbsolute(script)) {
      scriptPath = script;
    } else {
      final inPyEngine = p.join(rootDir, 'py_engine', script);
      if (File(inPyEngine).existsSync()) {
        scriptPath = inPyEngine;
      } else {
        scriptPath = p.join(rootDir, script);
      }
    }

    _addLog(actualJobId, 'system-info', '🚀 Khởi chạy: $script ${args.join(" ")}');

    final stdoutLines = <String>[];
    final stderrLines = <String>[];

    try {
      final env = buildEnvironment(rootDir: rootDir, pythonBin: pythonBin);

      final process = await Process.start(
        pythonBin,
        [scriptPath, ...args],
        workingDirectory: rootDir,
        environment: env,
      );

      _activeProcesses[actualJobId] = process;

      // Handle stdout line by line — intercept PROGRESS:N for callback
      process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        if (line.startsWith('PROGRESS:') && onProgress != null) {
          final pct = int.tryParse(line.substring(9).trim());
          if (pct != null) onProgress(pct);
        } else {
          stdoutLines.add(line);
          _addLog(actualJobId, 'stdout', line);
        }
      });


      bool isInsideHarmlessTraceback = false;
      process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        stderrLines.add(line);
        final trimmed = line.trim();
        final lower = trimmed.toLowerCase();

        if (lower.contains('resource_tracker') ||
            lower.contains('loky-') ||
            lower.contains('cache[rtype].remove') ||
            lower.contains('userwarning: resource_tracker') ||
            lower.contains('warnings.warn') ||
            lower.contains('unclosed file') ||
            lower.contains('keyerror: \'/loky-')) {
          isInsideHarmlessTraceback = true;
        }

        final isHarmless = isInsideHarmlessTraceback ||
            lower.contains('resource_tracker') ||
            lower.contains('userwarning') ||
            lower.contains('futurewarning') ||
            lower.contains('deprecationwarning') ||
            lower.contains('http request') ||
            lower.contains('loky-') ||
            lower.contains('ffmpeg version') ||
            lower.contains('cache[rtype]') ||
            trimmed.startsWith('Warning:') ||
            trimmed.startsWith('WARNING:') ||
            (trimmed.startsWith('Traceback (most recent call last):') && isInsideHarmlessTraceback);

        if (trimmed.isEmpty || (!lower.contains('resource_tracker') && !lower.contains('loky') && !lower.contains('traceback') && !lower.contains('cache[') && !lower.contains('keyerror') && !lower.contains('line '))) {
          isInsideHarmlessTraceback = false;
        }

        _addLog(actualJobId, isHarmless ? 'system-info' : 'stderr', line);
      });

      final exitCode = await process.exitCode;
      _activeProcesses.remove(actualJobId);

      final success = exitCode == 0;
      if (success) {
        _addLog(actualJobId, 'system-success', '🎉 Tiến trình hoàn thành thành công!');
      } else {
        _addLog(actualJobId, 'system-error', '❌ Tiến trình kết thúc với mã lỗi: $exitCode');
      }

      return JobResult(
        jobId: actualJobId,
        exitCode: exitCode,
        success: success,
        error: success ? null : (stderrLines.isNotEmpty ? stderrLines.join('\n') : 'Exit code $exitCode'),
        stdoutLines: stdoutLines,
        stderrLines: stderrLines,
      );
    } catch (e, st) {
      _activeProcesses.remove(actualJobId);
      final errorMsg = 'Lỗi không thể khởi chạy tiến trình: $e';
      _addLog(actualJobId, 'system-error', errorMsg);
      if (kDebugMode) {
        print('PythonBridge error: $e\n$st');
      }
      return JobResult(
        jobId: actualJobId,
        exitCode: -1,
        success: false,
        error: errorMsg,
        stdoutLines: stdoutLines,
        stderrLines: stderrLines,
      );
    }
  }

  /// Run a quick Python code snippet synchronously/asynchronously and return output
  static Future<ProcessResult> runCode(String pythonCode, {List<String>? extraArgs}) async {
    final rootDir = resolveRootDir();
    final pythonBin = resolvePythonBin();
    final args = ['-c', pythonCode, ...?extraArgs];

    final env = buildEnvironment(rootDir: rootDir, pythonBin: pythonBin);

    return Process.run(
      pythonBin,
      args,
      workingDirectory: rootDir,
      environment: env,
    );
  }

  static void Function(String jobId)? onStopExternalJob;

  /// Check if a job is currently running
  static bool isJobRunning(String jobId) {
    return _activeProcesses.containsKey(jobId);
  }

  /// Stop a running process by jobId
  static Future<bool> stopJob(String jobId) => stopProcess(jobId);

  /// Stop a running process (graceful SIGINT followed by SIGKILL)
  static Future<bool> stopProcess(String jobId) async {
    // Also cancel from external registered engines (e.g. EngineBridge)
    onStopExternalJob?.call(jobId);

    final process = _activeProcesses.remove(jobId);
    if (process == null) return true;

    _addLog(jobId, 'system-info', '⚠️ Đang gửi tín hiệu dừng tiến trình $jobId...');

    try {
      if (Platform.isWindows) {
        Process.runSync('taskkill', ['/F', '/T', '/PID', '${process.pid}']);
      } else {
        try {
          Process.runSync('pkill', ['-TERM', '-P', '${process.pid}']);
        } catch (_) {}
        process.kill(ProcessSignal.sigterm);
      }

      // Wait 600ms, if still alive force kill
      Future.delayed(const Duration(milliseconds: 600), () {
        try {
          Process.runSync('pkill', ['-KILL', '-P', '${process.pid}']);
        } catch (_) {}
        try {
          process.kill(ProcessSignal.sigkill);
        } catch (_) {}
      });
      return true;
    } catch (e) {
      try {
        process.kill(ProcessSignal.sigkill);
      } catch (_) {}
      return false;
    }
  }

  /// Kill all active subprocesses on app termination
  static Future<void> killAll() async {
    for (final entry in _activeProcesses.entries) {
      try {
        entry.value.kill(ProcessSignal.sigkill);
      } catch (_) {}
    }
    _activeProcesses.clear();
  }
}
