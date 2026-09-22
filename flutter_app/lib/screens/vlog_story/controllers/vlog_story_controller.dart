import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as p;
import '../../../core/engine_resolver.dart';
import '../../../core/python_bridge.dart';
import '../../../core/providers.dart';
import '../../../models/app_config.dart';
import '../../../models/subtitle_segment.dart';
import '../models/vlog_segment_model.dart';

class VlogStoryState {
  final String projectName;
  final String videoPath;
  final String videoName;
  final double duration;
  final bool isGeneratingScript;
  final bool isRenderingVideo;
  final double progress;
  final String statusMessage;
  final VlogStoryStyle style;
  final bool isAutoMode;
  final String customPrompt;
  final VlogStoryEngine engine;
  final String voice;
  final double ttsSpeed;
  final String? bgmPath;
  final double bgmVolume;
  final bool burnSubtitles;
  final bool enableInpaint;
  final double ttsVolume;
  final List<VlogSegment> segments;
  final int? currentlyPlayingSegmentId;
  final String? outputVideoPath;
  final List<String> logs;
  final String metaTitle;
  final String metaDesc;
  final List<String> metaHashtags;

  const VlogStoryState({
    this.projectName = '',
    this.videoPath = '',
    this.videoName = '',
    this.duration = 0.0,
    this.isGeneratingScript = false,
    this.isRenderingVideo = false,
    this.progress = 0.0,
    this.statusMessage = '',
    this.style = VlogStoryStyle.dailyChill,
    this.isAutoMode = false,
    this.customPrompt = '',
    this.engine = VlogStoryEngine.gemini,
    this.voice = 'hoai_my',
    this.ttsSpeed = 1.0,
    this.bgmPath,
    this.bgmVolume = 0.15,
    this.burnSubtitles = true,
    this.enableInpaint = false,
    this.ttsVolume = 1.0,
    this.segments = const [],
    this.currentlyPlayingSegmentId,
    this.outputVideoPath,
    this.logs = const [],
    this.metaTitle = '',
    this.metaDesc = '',
    this.metaHashtags = const [],
  });

  bool get isProcessing => isGeneratingScript || isRenderingVideo;

  VlogStoryState copyWith({
    String? projectName,
    String? videoPath,
    String? videoName,
    double? duration,
    bool? isGeneratingScript,
    bool? isRenderingVideo,
    double? progress,
    String? statusMessage,
    VlogStoryStyle? style,
    bool? isAutoMode,
    String? customPrompt,
    VlogStoryEngine? engine,
    String? voice,
    double? ttsSpeed,
    String? bgmPath,
    bool clearBgm = false,
    double? bgmVolume,
    bool? burnSubtitles,
    bool? enableInpaint,
    double? ttsVolume,
    List<VlogSegment>? segments,
    int? currentlyPlayingSegmentId,
    bool clearPlayingId = false,
    String? outputVideoPath,
    List<String>? logs,
    String? metaTitle,
    String? metaDesc,
    List<String>? metaHashtags,
  }) {
    return VlogStoryState(
      projectName: projectName ?? this.projectName,
      videoPath: videoPath ?? this.videoPath,
      videoName: videoName ?? this.videoName,
      duration: duration ?? this.duration,
      isGeneratingScript: isGeneratingScript ?? this.isGeneratingScript,
      isRenderingVideo: isRenderingVideo ?? this.isRenderingVideo,
      progress: progress ?? this.progress,
      statusMessage: statusMessage ?? this.statusMessage,
      style: style ?? this.style,
      isAutoMode: isAutoMode ?? this.isAutoMode,
      customPrompt: customPrompt ?? this.customPrompt,
      engine: engine ?? this.engine,
      voice: voice ?? this.voice,
      ttsSpeed: ttsSpeed ?? this.ttsSpeed,
      bgmPath: clearBgm ? null : (bgmPath ?? this.bgmPath),
      bgmVolume: bgmVolume ?? this.bgmVolume,
      burnSubtitles: burnSubtitles ?? this.burnSubtitles,
      enableInpaint: enableInpaint ?? this.enableInpaint,
      ttsVolume: ttsVolume ?? this.ttsVolume,
      segments: segments ?? this.segments,
      currentlyPlayingSegmentId: clearPlayingId ? null : (currentlyPlayingSegmentId ?? this.currentlyPlayingSegmentId),
      outputVideoPath: outputVideoPath ?? this.outputVideoPath,
      logs: logs ?? this.logs,
      metaTitle: metaTitle ?? this.metaTitle,
      metaDesc: metaDesc ?? this.metaDesc,
      metaHashtags: metaHashtags ?? this.metaHashtags,
    );
  }
}

final vlogStoryProvider = StateNotifierProvider<VlogStoryController, VlogStoryState>((ref) {
  return VlogStoryController(ref);
});

class VlogStoryController extends StateNotifier<VlogStoryState> {
  final Ref? _ref;
  Process? _activeProcess;
  Player? _ttsPlayer;

  VlogStoryController([this._ref]) : super(const VlogStoryState());

  VlogStoryState get currentState => state;

  /// Đồng bộ các cấu hình từ config.yaml vào state khi khởi tạo
  void syncFromConfig(AppConfig config) {
    state = state.copyWith(
      voice: config.ttsVoice.isNotEmpty ? config.ttsVoice : state.voice,
      ttsSpeed: config.ttsSpeed > 0 ? config.ttsSpeed : state.ttsSpeed,
      bgmVolume: config.musicVol > 0 ? config.musicVol : state.bgmVolume,
      burnSubtitles: config.showSubtitle,
      enableInpaint: config.inpaintShowBox,
      ttsVolume: config.audioTtsVoiceVolume > 0 ? config.audioTtsVoiceVolume : state.ttsVolume,
      engine: config.translatorType == 'ollama' ? VlogStoryEngine.ollama : state.engine,
    );
  }

  void setProjectName(String name) {
    state = state.copyWith(projectName: name);
  }

  void selectVideo({
    required String projectName,
    required String videoPath,
    String? videoName,
    double? duration,
  }) {
    final vName = videoName ?? p.basename(videoPath);
    final vDur = duration ?? 0.0;

    state = state.copyWith(
      projectName: projectName,
      videoPath: videoPath,
      videoName: vName,
      duration: vDur,
      statusMessage: 'Đã nạp video: $vName',
      progress: 0.0,
      outputVideoPath: null,
      segments: const [],
    );

    // Tự động kiểm tra kịch bản cũ đã lưu trong workspace
    _tryLoadExistingScript();
  }

  void setDuration(double dur) {
    if (dur > 0 && (state.duration - dur).abs() > 0.5) {
      state = state.copyWith(duration: dur);
    }
  }

  // ── Session-only fields (Lưu trong memory/session) ──
  void setStyle(VlogStoryStyle style) => state = state.copyWith(style: style);
  void setAutoMode(bool auto) => state = state.copyWith(isAutoMode: auto);
  void setCustomPrompt(String prompt) => state = state.copyWith(customPrompt: prompt);
  void setBgmPath(String? path) => state = state.copyWith(bgmPath: path, clearBgm: path == null);

  // ── Config fields (Lưu xuống config.yaml của dự án) ──
  void setEngine(VlogStoryEngine engine) {
    state = state.copyWith(engine: engine);
    _ref?.read(configProvider.notifier).setField(
      (c) => c.copyWith(translatorType: engine == VlogStoryEngine.ollama ? 'ollama' : 'gemini'),
    );
    _ref?.read(configProvider.notifier).save();
  }

  void setVoice(String voice) {
    state = state.copyWith(voice: voice);
    _ref?.read(configProvider.notifier).setField((c) => c.copyWith(ttsVoice: voice));
    _ref?.read(configProvider.notifier).save();
  }

  void setTtsSpeed(double speed) {
    state = state.copyWith(ttsSpeed: speed);
    _ref?.read(configProvider.notifier).setField((c) => c.copyWith(ttsSpeed: speed));
    _ref?.read(configProvider.notifier).save();
  }

  void setBgmVolume(double vol) {
    state = state.copyWith(bgmVolume: vol);
    _ref?.read(configProvider.notifier).setField((c) => c.copyWith(musicVol: vol));
    _ref?.read(configProvider.notifier).save();
  }

  void setTtsVolume(double vol) {
    state = state.copyWith(ttsVolume: vol);
    _ref?.read(configProvider.notifier).setField((c) => c.copyWith(audioTtsVoiceVolume: vol));
    _ref?.read(configProvider.notifier).save();
  }

  void setBurnSubtitles(bool burn) {
    state = state.copyWith(burnSubtitles: burn);
    _ref?.read(configProvider.notifier).setField((c) => c.copyWith(showSubtitle: burn));
    _ref?.read(configProvider.notifier).save();
  }

  void setEnableInpaint(bool val) {
    state = state.copyWith(enableInpaint: val);
    _ref?.read(configProvider.notifier).setField((c) => c.copyWith(inpaintShowBox: val));
    _ref?.read(configProvider.notifier).save();
  }

  void updateSegmentText(int segmentId, String newText) {
    final updated = state.segments.map((seg) {
      if (seg.id == segmentId) {
        return seg.copyWith(text: newText);
      }
      return seg;
    }).toList();
    state = state.copyWith(segments: updated);
    _saveScriptToDisk();
  }

  void updateSegmentTime(int segmentId, double newStart, double newEnd) {
    if (newEnd < newStart) return;
    final updated = state.segments.map((seg) {
      if (seg.id == segmentId) {
        return seg.copyWith(start: newStart, end: newEnd);
      }
      return seg;
    }).toList();
    state = state.copyWith(segments: updated);
    _saveScriptToDisk();
  }

  void addSegment() {
    final lastEnd = state.segments.isNotEmpty ? state.segments.last.end : 0.0;
    final newStart = lastEnd;
    final newEnd = (lastEnd + 4.0 <= state.duration) ? (lastEnd + 4.0) : state.duration;
    if (newStart >= state.duration) return;

    final newSeg = VlogSegment(
      id: state.segments.length + 1,
      start: newStart,
      end: newEnd,
      visualDesc: 'Cảnh bổ sung',
      text: '',
      maxWords: 10,
    );
    state = state.copyWith(segments: [...state.segments, newSeg]);
    _saveScriptToDisk();
  }

  void removeSegment(int segmentId) {
    final filtered = state.segments.where((s) => s.id != segmentId).toList();
    // Đánh lại ID
    final reindexed = List.generate(filtered.length, (i) => filtered[i].copyWith(id: i + 1));
    state = state.copyWith(segments: reindexed);
    _saveScriptToDisk();
  }

  void saveScriptToDisk() {
    _saveScriptToDisk();
    state = state.copyWith(statusMessage: 'Đã lưu kịch bản vào workspace.');
  }

  void syncSegmentsFromSubtitles(List<SubtitleSegment> subs) {
    final updated = subs.map((s) {
      return VlogSegment(
        id: s.id,
        start: s.start,
        end: s.end,
        visualDesc: s.extra['visualDesc']?.toString() ?? '',
        text: s.displayText,
        maxWords: (s.extra['maxWords'] as num?)?.toInt() ?? 10,
      );
    }).toList();
    state = state.copyWith(segments: updated);
    _saveScriptToDisk();
  }

  List<SubtitleSegment> toSubtitleSegments() {
    return state.segments.map((seg) {
      return SubtitleSegment(
        id: seg.id,
        start: seg.start,
        end: seg.end,
        text: seg.text,
        textVi: seg.text,
        extra: {
          'visualDesc': seg.visualDesc,
          'maxWords': seg.maxWords,
        },
      );
    }).toList();
  }

  String get _workspacePath {
    final root = PythonBridge.resolveRootDir();
    final pName = state.projectName.isNotEmpty ? state.projectName : 'default';
    final vName = state.videoName.isNotEmpty ? state.videoName : p.basename(state.videoPath);
    final safeName = p.withoutExtension(vName).replaceAll(RegExp(r'[^\w\-]+'), '_');
    return p.join(root, 'resources', pName, 'workspace', 'vlog_story', safeName);
  }

  void _tryLoadExistingScript() {
    try {
      final scriptFile = File(p.join(_workspacePath, 'vlog_script.json'));
      if (scriptFile.existsSync()) {
        final content = scriptFile.readAsStringSync();
        final raw = jsonDecode(content);
        if (raw is List) {
          final loaded = raw.map((e) => VlogSegment.fromJson(Map<String, dynamic>.from(e))).toList();

          // Kiểm tra xem đã có video render hoàn tất trước đó hay chưa
          final root = PythonBridge.resolveRootDir();
          final pName = state.projectName.isNotEmpty ? state.projectName : 'default';
          final vName = state.videoName.isNotEmpty ? state.videoName : p.basename(state.videoPath);
          final safeName = p.withoutExtension(vName).replaceAll(RegExp(r'[^\w\-]+'), '_');
          final outVideo = p.join(root, 'resources', pName, 'output', '${safeName}_vlog_story.mp4');
          final hasRendered = File(outVideo).existsSync();

          final metaFile = File(p.join(_workspacePath, 'vlog_metadata.json'));
          String mTitle = '';
          String mDesc = '';
          List<String> mTags = [];
          if (metaFile.existsSync()) {
            try {
              final mJson = jsonDecode(metaFile.readAsStringSync()) as Map<String, dynamic>;
              mTitle = mJson['title']?.toString() ?? '';
              mDesc = mJson['description']?.toString() ?? '';
              final rawTags = mJson['hashtags'] as List? ?? [];
              mTags = rawTags.map((e) => e.toString()).toList();
            } catch (_) {}
          }

          state = state.copyWith(
            segments: loaded,
            outputVideoPath: hasRendered ? outVideo : state.outputVideoPath,
            statusMessage: 'Đã nạp kịch bản (${loaded.length} phân cảnh).',
            metaTitle: mTitle.isNotEmpty ? mTitle : state.metaTitle,
            metaDesc: mDesc.isNotEmpty ? mDesc : state.metaDesc,
            metaHashtags: mTags.isNotEmpty ? mTags : state.metaHashtags,
          );
        }
      }
    } catch (_) {}
  }

  void _saveScriptToDisk() {
    try {
      final dir = Directory(_workspacePath);
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final scriptFile = File(p.join(_workspacePath, 'vlog_script.json'));
      final jsonList = state.segments.map((s) => s.toJson()).toList();
      scriptFile.writeAsStringSync(jsonEncode(jsonList));
    } catch (_) {}
  }

  String _resolveOrchestratorScript() {
    final resolved = EngineResolver.resolveScript('vlog_story_orchestrator.py');
    if (resolved != null && resolved.existsSync()) {
      return resolved.path;
    }
    final rootDir = PythonBridge.resolveRootDir();
    final candidates = [
      p.join(rootDir, 'py_engine', 'vlog_story_orchestrator.py'),
      p.join(rootDir, 'py_engine', 'vlog_story_orchestrator.pyc'),
      p.join(rootDir, 'vlog_story_orchestrator.py'),
    ];
    for (final c in candidates) {
      if (File(c).existsSync()) return c;
    }
    return p.join(rootDir, 'py_engine', 'vlog_story_orchestrator.py');
  }

  Future<void> generateScript() async {
    if (state.videoPath.isEmpty) return;
    state = state.copyWith(
      isGeneratingScript: true,
      progress: 0.05,
      statusMessage: 'Bắt đầu tạo kịch bản thị giác AI...',
    );

    final rootDir = PythonBridge.resolveRootDir();
    final pythonBin = PythonBridge.resolvePythonBin();
    final scriptPath = _resolveOrchestratorScript();

    final effectiveStyle = state.isAutoMode ? 'auto' : state.style.id;

    final args = [
      scriptPath,
      state.videoPath,
      '--action', 'generate_script',
      '--style', effectiveStyle,
      '--prompt', state.customPrompt,
      '--voice', state.voice,
      '--tts-speed', state.ttsSpeed.toStringAsFixed(2),
      '--engine', state.engine.id,
      '--json-output',
    ];

    try {
      final env = PythonBridge.buildEnvironment(rootDir: rootDir, pythonBin: pythonBin);
      final proc = await Process.start(pythonBin, args, workingDirectory: rootDir, environment: env);
      _activeProcess = proc;

      final stdoutLines = <String>[];

      proc.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) return;
        _parseIpcLine(trimmed);
        stdoutLines.add(trimmed);
      });

      proc.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
        final trimmed = line.trim();
        if (trimmed.isNotEmpty) {
          _addLog('[STDERR] $trimmed');
        }
      });

      final exitCode = await proc.exitCode;
      _activeProcess = null;

      if (exitCode == 0) {
        _tryLoadExistingScript();
        // Fallback: nếu đọc file chưa có (hoặc rỗng), duyệt tìm mảng JSON trong stdoutLines
        if (state.segments.isEmpty) {
          for (final line in stdoutLines.reversed) {
            try {
              final decoded = jsonDecode(line);
              if (decoded is List) {
                final loaded = decoded.map((e) => VlogSegment.fromJson(Map<String, dynamic>.from(e))).toList();
                if (loaded.isNotEmpty) {
                  state = state.copyWith(segments: loaded);
                  _saveScriptToDisk();
                  break;
                }
              }
            } catch (_) {}
          }
        }
        state = state.copyWith(
          isGeneratingScript: false,
          progress: 0.0,
          statusMessage: 'Đã hoàn thành phân tích kịch bản (${state.segments.length} phân cảnh)!',
        );
      } else {
        state = state.copyWith(
          isGeneratingScript: false,
          progress: 0.0,
          statusMessage: 'Lỗi tạo kịch bản (mã lỗi: $exitCode).',
        );
      }
    } catch (e) {
      state = state.copyWith(
        isGeneratingScript: false,
        statusMessage: 'Lỗi ngoại lệ: $e',
      );
    }
  }

  Future<void> previewTts(int segmentId, String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    if (state.currentlyPlayingSegmentId == segmentId) {
      await _ttsPlayer?.stop();
      state = state.copyWith(clearPlayingId: true);
      return;
    }

    state = state.copyWith(
      currentlyPlayingSegmentId: segmentId,
      statusMessage: 'Đang tạo giọng đọc thử câu #$segmentId...',
    );

    final rootDir = PythonBridge.resolveRootDir();
    final pythonBin = PythonBridge.resolvePythonBin();
    final scriptPath = _resolveOrchestratorScript();
    final tempAudio = p.join(_workspacePath, 'preview_tts_$segmentId.mp3');

    final args = [
      scriptPath,
      state.videoPath,
      '--action', 'preview_tts',
      '--preview-text', trimmed,
      '--voice', state.voice,
      '--tts-speed', state.ttsSpeed.toStringAsFixed(2),
      '--preview-out', tempAudio,
      '--json-output',
    ];

    try {
      final env = PythonBridge.buildEnvironment(rootDir: rootDir, pythonBin: pythonBin);
      final res = await Process.run(pythonBin, args, workingDirectory: rootDir, environment: env);
      if (res.exitCode == 0 && File(tempAudio).existsSync()) {
        _ttsPlayer ??= Player();
        await _ttsPlayer?.open(Media(tempAudio));
        state = state.copyWith(statusMessage: 'Đang phát câu #$segmentId');
        _ttsPlayer?.stream.completed.listen((done) {
          if (done) {
            state = state.copyWith(clearPlayingId: true);
          }
        });
      } else {
        state = state.copyWith(clearPlayingId: true, statusMessage: 'Lỗi nghe thử TTS.');
      }
    } catch (e) {
      state = state.copyWith(clearPlayingId: true, statusMessage: 'Lỗi: $e');
    }
  }

  Future<void> renderFinalVideo() async {
    if (state.videoPath.isEmpty || state.segments.isEmpty) return;

    // Lưu kịch bản trước khi render
    _saveScriptToDisk();

    // Tự động lưu cấu hình mới nhất từ configProvider xuống config.yaml
    if (_ref != null) {
      try {
        await _ref.read(configProvider.notifier).save();
        _addLog('💾 [CONFIG] Đã tự động lưu cấu hình mới nhất vào config.yaml trước khi render.');
      } catch (e) {
        _addLog('⚠️ [CONFIG] Không thể tự động lưu config.yaml: $e');
      }
    }

    state = state.copyWith(
      isRenderingVideo: true,
      progress: 0.45,
      statusMessage: 'Bắt đầu tổng hợp âm thanh & render video...',
    );

    final rootDir = PythonBridge.resolveRootDir();
    final pythonBin = PythonBridge.resolvePythonBin();
    final scriptPath = _resolveOrchestratorScript();

    final args = [
      scriptPath,
      state.videoPath,
      '--action', 'render_video',
      '--voice', state.voice,
      '--tts-speed', state.ttsSpeed.toStringAsFixed(2),
      '--tts-volume', state.ttsVolume.toStringAsFixed(2),
      '--bgm-volume', state.bgmVolume.toStringAsFixed(2),
      if (state.bgmPath != null && state.bgmPath!.isNotEmpty) ...['--bgm', state.bgmPath!],
      if (state.enableInpaint) '--enable-inpaint' else '--no-inpaint',
      if (!state.burnSubtitles) '--no-burn-sub',
      '--json-output',
    ];

    try {
      final env = PythonBridge.buildEnvironment(rootDir: rootDir, pythonBin: pythonBin);
      final proc = await Process.start(pythonBin, args, workingDirectory: rootDir, environment: env);
      _activeProcess = proc;

      String? finalOutput;

      proc.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) return;
        _parseIpcLine(trimmed);
        if (trimmed.startsWith('{') && trimmed.contains('output_video')) {
          try {
            final json = jsonDecode(trimmed);
            if (json is Map && json['output_video'] != null) {
              finalOutput = json['output_video'].toString();
            }
          } catch (_) {}
        }
      });

      proc.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
        final trimmed = line.trim();
        if (trimmed.isNotEmpty) {
          _addLog('[RENDER STDERR] $trimmed');
        }
      });

      final exitCode = await proc.exitCode;
      _activeProcess = null;

      if (exitCode == 0) {
        state = state.copyWith(
          isRenderingVideo: false,
          progress: 1.0,
          statusMessage: 'Hoàn tất! Video kể chuyện đã sẵn sàng.',
          outputVideoPath: finalOutput,
        );
      } else {
        state = state.copyWith(
          isRenderingVideo: false,
          statusMessage: 'Lỗi khi xuất video (mã: $exitCode).',
        );
      }
    } catch (e) {
      state = state.copyWith(
        isRenderingVideo: false,
        statusMessage: 'Lỗi render: $e',
      );
    }
  }

  void cancelActiveTask() {
    _activeProcess?.kill();
    _activeProcess = null;
    state = state.copyWith(
      isGeneratingScript: false,
      isRenderingVideo: false,
      statusMessage: 'Đã hủy tác vụ.',
    );
  }

  void _parseIpcLine(String line) {
    if (line.startsWith('{') && line.endsWith('}')) {
      try {
        final json = jsonDecode(line);
        if (json is Map) {
          final type = json['type'];
          if (type == 'progress') {
            final prog = (json['progress'] as num?)?.toDouble() ?? state.progress;
            final status = json['status'] as String? ?? state.statusMessage;
            state = state.copyWith(progress: prog, statusMessage: status);
          } else if (type == 'log') {
            final msg = json['message'] as String? ?? '';
            _addLog(msg);
          }
        }
      } catch (_) {}
    } else if (line.startsWith('PROGRESS:')) {
      final parts = line.substring(9).trim().split(' ');
      if (parts.isNotEmpty) {
        final prog = double.tryParse(parts[0]) ?? state.progress;
        final msg = parts.skip(1).join(' ');
        state = state.copyWith(progress: prog, statusMessage: msg);
      }
    } else {
      _addLog(line);
    }
  }

  void _addLog(String log) {
    final updated = [...state.logs, log];
    if (updated.length > 500) {
      updated.removeRange(0, updated.length - 500);
    }
    state = state.copyWith(logs: updated);

    final isErr = log.startsWith('[STDERR]') || log.startsWith('[RENDER STDERR]') || log.toLowerCase().contains('error');
    PythonBridge.addLog('vlog_story', isErr ? 'stderr' : 'stdout', log);
  }

  @override
  void dispose() {
    _ttsPlayer?.dispose();
    _activeProcess?.kill();
    super.dispose();
  }
}
