import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'engine_resolver.dart';
import 'project_manager.dart';
import 'python_bridge.dart';
import 'license_service.dart';



class EngineBridge {
  static final Map<String, Process> _runningProcesses = {};
  static final StreamController<Map<String, dynamic>> _longVideoEvents = StreamController<Map<String, dynamic>>.broadcast();

  /// Stream to listen for Long Video orchestration events (initialized, progress, completed)
  static Stream<Map<String, dynamic>> get longVideoEvents => _longVideoEvents.stream;

  /// Runs the video translation pipeline dynamically using the Sidecar Engine (Hot-Patch capable).
  static Future<JobResult> runNativePipeline(
    String videoPath, {
    String? jobId,
    String? projectId,
    Map<String, dynamic>? configOverride,
    bool? isOcrOnly,
    bool? isVoice,
    bool? forceRetranslate,
    bool? longVideo,
    double? chunkDurationMin,
  }) async {
    PythonBridge.onStopExternalJob = cancelJob;
    final rootDirStr = PythonBridge.resolveRootDir();
    final projectPaths = ProjectManager.resolveProjectPaths(videoPath, rootDirOverride: Directory(rootDirStr));
    final resolvedVideo = ProjectManager.resolveSourceVideo(videoPath, projectDir: projectPaths.projectDir);
    final actualJobId = jobId ?? ProjectManager.getJobId(resolvedVideo.path);

    final target = EngineResolver.resolveEngine();
    _logToFlutterBridge(actualJobId, 'system-info', '🚀 [Sidecar Engine] Nguồn: ${target.source} (${target.executable})');
    _logToFlutterBridge(actualJobId, 'system-info', '📁 Video: ${resolvedVideo.absolute.path}');
    _logToFlutterBridge(actualJobId, 'system-info', '📂 Dự án: ${projectPaths.projectDir.path}');

    if (target.isProcess && target.executable.isNotEmpty && (target.source == 'dev_source' || File(target.executable).existsSync())) {
      final args = <String>[
        ...target.defaultPrefixArgs,
        'translate',
        projectPaths.projectDir.path,
        resolvedVideo.absolute.path,
        '--json',
      ];

      if (isVoice == true) {
        args.add('--voice');
      } else if (isOcrOnly == true) {
        args.add('--ocr-only');
      }

      if (forceRetranslate == true) {
        args.add('--force-translate');
      }

      if (longVideo == true) {
        final currentLicense = await LicenseService.loadSavedLicense();
        if (currentLicense.canUseLongVideoChunking) {
          args.add('--force-chunk');
          if (chunkDurationMin != null && chunkDurationMin > 0) {
            args.addAll(['--chunk-mins', chunkDurationMin.toStringAsFixed(1)]);
          }
        } else {
          _logToFlutterBridge(
            actualJobId,
            'warning',
            '⚠️ [License Gating] Gói Creator không hỗ trợ phân đoạn video siêu dài. Chuyển sang chế độ dịch đơn khối thông thường.',
          );
        }
      }

      final stdoutLines = <String>[];
      final stderrLines = <String>[];

      try {
        final env = PythonBridge.buildEnvironment(
          rootDir: rootDirStr,
          pythonBin: target.executable,
        );
        final process = await Process.start(
          target.executable,
          args,
          environment: env,
        );

        _runningProcesses[actualJobId] = process;

        final completer = Completer<int>();

        process.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen((line) {
          stdoutLines.add(line);
          try {
            final json = jsonDecode(line) as Map<String, dynamic>;
            final type = json['type']?.toString();
            if (type == 'log') {
              final level = json['level'] ?? 'info';
              final logType = level == 'error' ? 'stderr' : (level == 'success' ? 'system-success' : 'system-info');
              _logToFlutterBridge(actualJobId, logType, '[${json['step_id']}] ${json['message']}');
            } else if (type == 'progress' || type == 'step_status') {
              _logToFlutterBridge(actualJobId, 'system-info', '→ [${json['step_id']}] Tiến độ: ${json['status'] ?? json['progress']}');
            } else if (type == 'job_started') {
              _logToFlutterBridge(actualJobId, 'system-info', '🎬 Bắt đầu Job: ${json['job_id']}');
            } else if (type == 'long_video_initialized') {
              _longVideoEvents.add(json);
              _logToFlutterBridge(actualJobId, 'system-info', '🧩 [Chế Độ Phân Đoạn Thông Minh] Video dài (${json['total_duration_sec']}s) được chia thành ${json['total_chunks']} đoạn để chống tràn RAM & bảo toàn tiến trình.');
            } else if (type == 'long_video_progress' || (type == 'progress' && json.containsKey('chunk_id'))) {
              _longVideoEvents.add(json);
              _logToFlutterBridge(actualJobId, 'system-info', '⚡ [Đoạn ${json['chunk_id']}/${json['total_chunks']}] ${json['current_step']} (${json['chunk_progress']}%) • Tiến độ tổng: ${json['overall_progress']}%');
            } else if (type == 'long_video_completed') {
              _longVideoEvents.add(json);
              _logToFlutterBridge(actualJobId, 'system-success', '🎉 [Hoàn Tất Video Dài] Toàn bộ ${json['total_chunks']} đoạn đã được dịch và ghép nối thành công!');
            } else if (type == 'job_completed') {
              _logToFlutterBridge(actualJobId, 'system-success', '🎉 Hoàn tất Job: ${json['job_id']}');
            } else if (type == 'error') {
              _logToFlutterBridge(actualJobId, 'system-error', '❌ Lỗi: ${json['message']}');
            }
          } catch (_) {
            _logToFlutterBridge(actualJobId, 'stdout', line);
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

          _logToFlutterBridge(actualJobId, isHarmless ? 'system-info' : 'stderr', line);
        });

        process.exitCode.then((code) {
          _runningProcesses.remove(actualJobId);
          completer.complete(code);
        });

        final exitCode = await completer.future;
        final success = exitCode == 0;

        return JobResult(
          jobId: actualJobId,
          exitCode: exitCode,
          success: success,
          error: success ? null : (stderrLines.isNotEmpty ? stderrLines.join('\n') : 'Engine CLI exited with code $exitCode'),
          stdoutLines: stdoutLines,
          stderrLines: stderrLines,
        );
      } catch (e) {
        _runningProcesses.remove(actualJobId);
        final errorMsg = 'Lỗi khởi chạy Engine: $e';
        _logToFlutterBridge(actualJobId, 'system-error', errorMsg);
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

    final errorMsg = 'Không tìm thấy Engine thực thi (${target.executable})';
    _logToFlutterBridge(actualJobId, 'system-error', errorMsg);
    return JobResult(
      jobId: actualJobId,
      exitCode: -1,
      success: false,
      error: errorMsg,
    );
  }

  /// Convenience alias for translateVideo matching GUI calling conventions
  static Future<JobResult> translateVideo(
    String videoPath, {
    bool? ocrOnly,
    bool? voice,
    String? jobId,
    String? projectId,
    Map<String, dynamic>? configOverride,
    bool? longVideo,
    double? chunkDurationMin,
  }) =>
      runNativePipeline(
        videoPath,
        jobId: jobId,
        projectId: projectId,
        configOverride: configOverride,
        isOcrOnly: ocrOnly,
        isVoice: voice,
        longVideo: longVideo,
        chunkDurationMin: chunkDurationMin,
      );

  /// Convenience alias for resumeJob matching GUI calling conventions
  static Future<JobResult> resumeJob(
    String videoPathOrJobId, {
    String? jobId,
    String? projectId,
    Map<String, dynamic>? configOverride,
    bool? forceRetranslate,
  }) =>
      runNativePipeline(
        videoPathOrJobId,
        jobId: jobId,
        projectId: projectId,
        configOverride: configOverride,
        forceRetranslate: forceRetranslate,
      );

  /// Merges long video chunks and master subtitles from manifest
  static Future<JobResult> mergeLongVideo(
    String videoPath, {
    String? projectId,
  }) async {
    final rootDirStr = PythonBridge.resolveRootDir();
    final projectPaths = ProjectManager.resolveProjectPaths(videoPath, rootDirOverride: Directory(rootDirStr));
    final resolvedVideo = ProjectManager.resolveSourceVideo(videoPath, projectDir: projectPaths.projectDir);
    final target = EngineResolver.resolveEngine();
    final jobId = 'merge_${ProjectManager.getJobId(resolvedVideo.path)}';

    _logToFlutterBridge(jobId, 'system-info', '🔗 Đang ghép nối các đoạn video dài: ${resolvedVideo.path}');

    if (target.isProcess && target.executable.isNotEmpty && (target.source == 'dev_source' || File(target.executable).existsSync())) {
      final args = <String>[
        ...target.defaultPrefixArgs,
        'merge-long',
        projectPaths.projectDir.path,
        resolvedVideo.absolute.path,
        '--json',
      ];

      try {
        final process = await Process.start(
          target.executable,
          args,
          environment: {'PYTHONUNBUFFERED': '1'},
        );
        _runningProcesses[jobId] = process;

        process.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
          if (line.trim().isEmpty) return;
          try {
            final json = jsonDecode(line) as Map<String, dynamic>;
            _logToFlutterBridge(jobId, json['type'] ?? 'info', json['message'] ?? line);
          } catch (_) {
            _logToFlutterBridge(jobId, 'stdout', line);
          }
        });

        process.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
          if (line.trim().isEmpty) return;
          _logToFlutterBridge(jobId, 'stderr', line);
        });

        final exitCode = await process.exitCode;
        _runningProcesses.remove(jobId);
        final success = exitCode == 0;
        return JobResult(
          jobId: jobId,
          exitCode: exitCode,
          success: success,
          error: success ? null : 'Merge exited with code $exitCode',
        );
      } catch (e) {
        _runningProcesses.remove(jobId);
        return JobResult(jobId: jobId, exitCode: 1, success: false, error: e.toString());
      }
    }
    return JobResult(jobId: jobId, exitCode: 1, success: false, error: 'Sidecar engine not available');
  }

  /// Cancels an active running job process and all its subprocess tree
  static void cancelJob(String jobId) {
    final proc = _runningProcesses.remove(jobId);
    if (proc != null) {
      _logToFlutterBridge(jobId, 'system-error', '🛑 Đang gửi tín hiệu dừng tiến trình $jobId...');
      try {
        if (Platform.isWindows) {
          Process.runSync('taskkill', ['/F', '/T', '/PID', '${proc.pid}']);
        } else {
          try {
            Process.runSync('pkill', ['-TERM', '-P', '${proc.pid}']);
          } catch (_) {}
          proc.kill(ProcessSignal.sigterm);

          Future.delayed(const Duration(milliseconds: 600), () {
            try {
              Process.runSync('pkill', ['-KILL', '-P', '${proc.pid}']);
            } catch (_) {}
            try {
              proc.kill(ProcessSignal.sigkill);
            } catch (_) {}
          });
        }
      } catch (e) {
        try {
          proc.kill(ProcessSignal.sigkill);
        } catch (_) {}
      }
      _logToFlutterBridge(jobId, 'system-error', '🛑 Đã dừng tiến trình $jobId thành công.');
    }
  }

  /// Cancels all currently running engine processes
  static void cancelAll() {
    final ids = _runningProcesses.keys.toList();
    for (final id in ids) {
      cancelJob(id);
    }
  }

  static void _logToFlutterBridge(String jobId, String type, String message) {
    PythonBridge.addLog(jobId, type, message);
  }
}
