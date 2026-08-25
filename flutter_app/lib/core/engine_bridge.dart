import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:video_engine/video_engine.dart';
import 'engine_resolver.dart';
import 'python_bridge.dart';

class EngineBridge {
  static final Map<String, Process> _runningProcesses = {};

  /// Runs the video translation pipeline dynamically using the Sidecar Engine (Hot-Patch capable).
  static Future<JobResult> runNativePipeline(
    String videoPath, {
    String? jobId,
    String? projectId,
    Map<String, dynamic>? configOverride,
    bool? isOcrOnly,
    bool? isVoice,
  }) async {
    final rootDirStr = PythonBridge.resolveRootDir();
    final projectPaths = ProjectManager.resolveProjectPaths(videoPath, rootDirOverride: Directory(rootDirStr));
    final resolvedVideo = ProjectManager.resolveSourceVideo(videoPath, projectDir: projectPaths.projectDir);
    final actualJobId = jobId ?? ProjectManager.getJobId(resolvedVideo.path);

    final target = EngineResolver.resolveEngine();
    _logToFlutterBridge(actualJobId, 'system-info', '🚀 [Sidecar Engine] Nguồn: ${target.source} (${target.executable})');
    _logToFlutterBridge(actualJobId, 'system-info', '📁 Video: ${resolvedVideo.absolute.path}');
    _logToFlutterBridge(actualJobId, 'system-info', '📂 Dự án: ${projectPaths.projectDir.path}');

    // If external process is available, execute via Process.start
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

      final stdoutLines = <String>[];
      final stderrLines = <String>[];

      try {
        final process = await Process.start(
          target.executable,
          args,
          environment: {
            'PYTHONUNBUFFERED': '1',
            'PYTHONIOENCODING': 'utf-8',
            'DYLD_LIBRARY_PATH': EngineResolver.hotPatchDir.path,
          },
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
            } else if (type == 'job_completed') {
              _logToFlutterBridge(actualJobId, 'system-success', '🎉 Hoàn tất Job: ${json['job_id']}');
            } else if (type == 'error') {
              _logToFlutterBridge(actualJobId, 'system-error', '❌ Lỗi: ${json['message']}');
            }
          } catch (_) {
            _logToFlutterBridge(actualJobId, 'stdout', line);
          }
        });

        process.stderr
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen((line) {
          stderrLines.add(line);
          _logToFlutterBridge(actualJobId, 'stderr', line);
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
        _logToFlutterBridge(actualJobId, 'system-info', '⚠️ Lỗi khởi chạy tiến trình bên ngoài ($e). Tự động chuyển sang In-Process Direct Engine...');
      }
    }

    // ── FALLBACK: IN-PROCESS DIRECT DART ENGINE EXECUTION (ZERO CRASH) ────────
    return _runInProcessPipeline(
      videoPath: videoPath,
      actualJobId: actualJobId,
      projectPaths: projectPaths,
      configOverride: configOverride,
      isOcrOnly: isOcrOnly,
      isVoice: isVoice,
    );
  }

  static Future<JobResult> _runInProcessPipeline({
    required String videoPath,
    required String actualJobId,
    required ProjectPaths projectPaths,
    Map<String, dynamic>? configOverride,
    bool? isOcrOnly,
    bool? isVoice,
  }) async {
    final stdoutLines = <String>[];
    final stderrLines = <String>[];
    final config = projectPaths.loadConfig();

    if (configOverride != null) {
      config.deepMerge(configOverride);
    }
    if (isVoice == true) {
      config['ocr_only'] = false;
    } else if (isOcrOnly == true) {
      config['ocr_only'] = true;
    }

    final jobState = JobState(
      workspace: projectPaths.workspaceDir,
      jobId: actualJobId,
      inputVideo: File(videoPath).absolute.path,
      config: config.toMap(),
    );

    final steps = <StepBase>[
      StepProbe(),
      StepDemux(),
      StepSubtitleDetect(),
      StepAudioSeparate(),
      StepASR(),
      StepGenderDetect(),
      StepOCR(),
      StepTranscriptMerge(),
      StepTranslation(),
      StepMetadataGen(),
      StepTiming(),
      StepSubtitleGen(),
      StepInpaint(),
      StepSubtitleRender(),
      StepTTS(),
      StepAudioMix(),
      StepEncode(),
    ];

    final runner = PipelineRunner(
      steps: steps,
      onLog: (stepId, message, {type = 'info'}) {
        final line = '[$stepId] $message';
        stdoutLines.add(line);
        final logType = type == 'error' ? 'stderr' : (type == 'success' ? 'system-success' : 'system-info');
        _logToFlutterBridge(actualJobId, logType, line);
      },
      onStepStatus: (stepId, status, progress) {
        _logToFlutterBridge(actualJobId, 'system-info', '→ [$stepId] Tiến độ: $status');
      },
    );

    try {
      final success = await runner.run(jobState, config);
      return JobResult(
        jobId: actualJobId,
        exitCode: success ? 0 : 1,
        success: success,
        error: success ? null : (stderrLines.isNotEmpty ? stderrLines.join('\n') : 'Pipeline execution failed'),
        stdoutLines: stdoutLines,
        stderrLines: stderrLines,
      );
    } catch (e, st) {
      final errorMsg = 'Lỗi thực thi Engine: $e';
      stderrLines.add(errorMsg);
      stderrLines.add(st.toString());
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

  /// Convenience alias for translateVideo matching GUI calling conventions
  static Future<JobResult> translateVideo(
    String videoPath, {
    bool? ocrOnly,
    bool? voice,
    String? jobId,
    String? projectId,
    Map<String, dynamic>? configOverride,
  }) =>
      runNativePipeline(
        videoPath,
        jobId: jobId,
        projectId: projectId,
        configOverride: configOverride,
        isOcrOnly: ocrOnly,
        isVoice: voice,
      );

  /// Convenience alias for resumeJob matching GUI calling conventions
  static Future<JobResult> resumeJob(
    String videoPathOrJobId, {
    String? projectId,
    Map<String, dynamic>? configOverride,
  }) =>
      runNativePipeline(
        videoPathOrJobId,
        projectId: projectId,
        configOverride: configOverride,
      );

  /// Cancels an active running job process
  static void cancelJob(String jobId) {
    final proc = _runningProcesses.remove(jobId);
    if (proc != null) {
      proc.kill(ProcessSignal.sigterm);
    }
  }

  static void _logToFlutterBridge(String jobId, String type, String message) {
    PythonBridge.addLog(jobId, type, message);
  }
}
