import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as p;
import '../../../core/engine_resolver.dart';
import '../../../core/providers.dart';
import '../../../core/python_bridge.dart';
import '../../../utils/yaml_config_parser.dart';
import '../models/movie_review_model.dart';

final movieReviewProvider = StateNotifierProvider<MovieReviewController, MovieReviewState>((ref) {
  return MovieReviewController(ref);
});

class MovieReviewController extends StateNotifier<MovieReviewState> {
  final Ref? _ref;
  Process? _activeProcess;
  Player? _ttsPlayer;

  MovieReviewController([this._ref]) : super(const MovieReviewState());

  MovieReviewState get currentState => state;
  Process? get activeProcess => _activeProcess;

  void selectVideoFromProject({
    required String projectName,
    required String videoPath,
    String? videoName,
    double? duration,
    String? apiKey,
    String? aiModel,
  }) {
    final vName = videoName ?? p.basename(videoPath);
    String resolvedApiKey = (apiKey != null && apiKey.isNotEmpty) ? apiKey : state.apiKey;
    String resolvedModel = (aiModel != null && aiModel.isNotEmpty) ? aiModel : state.aiModel;

    // Đồng bộ activeProjectProvider để configProvider nạp đúng config.yaml của project này
    if (_ref != null) {
      final currentActiveProj = _ref.read(activeProjectProvider);
      if (currentActiveProj != projectName) {
        _ref.read(activeProjectProvider.notifier).state = projectName;
      }
    }

    try {
      final vFile = File(videoPath);
      final projDir = vFile.parent.parent;
      final projConfigFile = File(p.join(projDir.path, 'config.yaml'));
      if (projConfigFile.existsSync()) {
        final yamlStr = projConfigFile.readAsStringSync();
        final parsed = YamlConfigParser.parse(yamlStr);
        if (parsed.translatorApiKey.isNotEmpty) {
          resolvedApiKey = parsed.translatorApiKey;
        }
        if (parsed.translatorModel.isNotEmpty) {
          resolvedModel = parsed.translatorModel;
        }
      }
    } catch (_) {}

    final vDur = duration ?? 0.0;
    int targetDur = state.targetDurationSec;
    if (vDur > 0 && (targetDur == 360 || targetDur == 0)) {
      targetDur = WordBudget.calculateOptimalDuration(vDur);
    }

    state = state.copyWith(
      projectName: projectName,
      videoPath: videoPath,
      videoName: vName,
      videoDuration: vDur,
      targetDurationSec: targetDur,
      apiKey: resolvedApiKey,
      aiModel: resolvedModel,
      statusMessage: 'Đã chọn video: $vName',
      outputVideoPath: null,
      segments: [],
      availableScenes: [],
    );
    checkAndRestoreCache();
  }

  void checkAndRestoreCache() {
    final scriptFile = File(p.join(_workspacePath, 'review_script.json'));
    final scenesFile = File(p.join(_workspacePath, 'scenes_meta.json'));
    if (scriptFile.existsSync() && scenesFile.existsSync()) {
      _loadGeneratedData();
      state = state.copyWith(
        hasCachedData: true,
        statusMessage: 'Đã nạp lại kịch bản từ bản lưu trước đó',
      );
      _addLog('[CACHE] Đã nạp thành công kịch bản đã lưu tại: $_workspacePath');
    } else {
      state = state.copyWith(hasCachedData: false);
    }
  }

  void setGenre(MovieGenre genre) {
    state = state.copyWith(
      genre: genre,
      targetDurationSec: genre.defaultDurationSec,
    );
  }

  void setReviewStyle(ReviewStyle style) {
    state = state.copyWith(
      reviewStyle: style,
      actConfig: state.actConfig.resetToDefault(style),
    );
  }

  void setTargetDuration(int durationSec) {
    state = state.copyWith(targetDurationSec: durationSec);
  }

  void setTtsSpeed(double speed) {
    state = state.copyWith(ttsSpeed: speed);
  }

  void setTtsVoice(String voice) {
    state = state.copyWith(ttsVoice: voice);
  }

  void setAspectRatio(String ratio) {
    state = state.copyWith(aspectRatio: ratio);
  }

  void setApiKey(String key) {
    state = state.copyWith(apiKey: key);
  }

  void setAiModel(String model) {
    state = state.copyWith(aiModel: model);
  }

  void setCustomPrompt(String prompt) {
    state = state.copyWith(customPrompt: prompt);
  }

  void setTtsVolume(double vol) {
    state = state.copyWith(ttsVolume: vol.clamp(0.0, 1.0));
  }

  void setOriginalAudioVolume(double vol) {
    state = state.copyWith(originalAudioVolume: vol.clamp(0.0, 1.0));
  }

  void setBgmVolume(double vol) {
    state = state.copyWith(bgmVolume: vol.clamp(0.0, 1.0));
  }

  void setActConfig(ActStructureConfig config) {
    state = state.copyWith(actConfig: config);
  }

  void updateActPct(String act, double newPct) {
    state = state.copyWith(actConfig: state.actConfig.updateActPct(act, newPct));
  }

  void toggleAct(String act, bool enabled) {
    state = state.copyWith(actConfig: state.actConfig.toggleAct(act, enabled, state.reviewStyle));
  }

  void toggleChapter(int chapterId) {
    state = state.copyWith(actConfig: state.actConfig.toggleChapter(chapterId));
  }

  void selectAllChapters(bool selectAll) {
    state = state.copyWith(actConfig: state.actConfig.selectAllChapters(selectAll));
  }

  void resetActRatios() {
    state = state.copyWith(actConfig: state.actConfig.resetToDefault(state.reviewStyle));
  }

  void setTargetLang(String lang) {
    state = state.copyWith(targetLang: lang);
  }

  void setBurnSubtitles(bool val) {
    state = state.copyWith(burnSubtitles: val);
  }

  void setEnableInpaint(bool val) {
    state = state.copyWith(enableInpaint: val);
  }

  void setActiveTab(String tab) {
    state = state.copyWith(activeSectionTab: tab);
  }

  void setContentDriven(bool value) {
    state = state.copyWith(isContentDriven: value);
  }

  void updateSegmentText(int id, String text) {
    final updated = state.segments.map((seg) {
      if (seg.id == id) {
        return seg.copyWith(voiceoverText: text);
      }
      return seg;
    }).toList();
    state = state.copyWith(segments: updated);
  }

  void addSceneToSegment(int segmentId, SceneMeta scene) {
    final updated = state.segments.map((seg) {
      if (seg.id == segmentId) {
        final current = List<SceneMeta>.from(seg.scenesToUse);
        current.add(scene);
        return seg.copyWith(scenesToUse: current);
      }
      return seg;
    }).toList();
    state = state.copyWith(segments: updated);
  }

  void removeSceneFromSegment(int segmentId, int sceneId) {
    final updated = state.segments.map((seg) {
      if (seg.id == segmentId) {
        final current = seg.scenesToUse.where((s) => s.sceneId != sceneId).toList();
        return seg.copyWith(scenesToUse: current);
      }
      return seg;
    }).toList();
    state = state.copyWith(segments: updated);
  }

  void swapSceneInSegment(int segmentId, int oldSceneId, SceneMeta newScene) {
    final updated = state.segments.map((seg) {
      if (seg.id == segmentId) {
        final current = seg.scenesToUse.map((s) {
          return s.sceneId == oldSceneId ? newScene : s;
        }).toList();
        return seg.copyWith(scenesToUse: current);
      }
      return seg;
    }).toList();
    state = state.copyWith(segments: updated);
  }

  void deleteSegment(int segmentId) {
    final updated = state.segments.where((seg) => seg.id != segmentId).toList();
    state = state.copyWith(segments: updated);
  }

  void addSegment(String section) {
    final maxId = state.segments.isEmpty
        ? 0
        : state.segments.map((s) => s.id).reduce((a, b) => a > b ? a : b);
    final newSeg = ScriptSegment(
      id: maxId + 1,
      section: section,
      voiceoverText: '',
      scenesToUse: state.availableScenes.isNotEmpty ? [state.availableScenes.first] : [],
    );
    state = state.copyWith(segments: [...state.segments, newSeg]);
  }

  void toggleFlipHorizontal() {
    state = state.copyWith(flipHorizontal: !state.flipHorizontal);
  }

  void toggleCropZoom() {
    state = state.copyWith(cropZoom: !state.cropZoom);
  }

  void toggleMuteMovieAudio() {
    state = state.copyWith(muteMovieAudio: !state.muteMovieAudio);
  }

  void splitSegment(int segmentId) {
    final idx = state.segments.indexWhere((s) => s.id == segmentId);
    if (idx == -1) return;
    final seg = state.segments[idx];
    final text = seg.voiceoverText.trim();
    if (text.isEmpty) return;

    final sentences = text.split(RegExp(r'(?<=[.?!])\s+'));
    String part1 = '';
    String part2 = '';
    if (sentences.length >= 2) {
      final mid = (sentences.length / 2).ceil();
      part1 = sentences.sublist(0, mid).join(' ');
      part2 = sentences.sublist(mid).join(' ');
    } else {
      final words = text.split(RegExp(r'\s+'));
      final mid = (words.length / 2).ceil();
      part1 = words.sublist(0, mid).join(' ');
      part2 = words.sublist(mid).join(' ');
    }

    final scenes = seg.scenesToUse;
    final scenesPart1 = scenes.isNotEmpty ? [scenes.first] : <SceneMeta>[];
    final scenesPart2 = scenes.length > 1 ? scenes.sublist(1) : scenesPart1;

    final seg1 = seg.copyWith(voiceoverText: part1, scenesToUse: scenesPart1);
    final maxId = state.segments.map((s) => s.id).reduce((a, b) => a > b ? a : b);
    final seg2 = ScriptSegment(
      id: maxId + 1,
      section: seg.section,
      voiceoverText: part2,
      scenesToUse: scenesPart2,
    );

    final updated = List<ScriptSegment>.from(state.segments);
    updated[idx] = seg1;
    updated.insert(idx + 1, seg2);
    state = state.copyWith(segments: updated);
    _addLog('[STORYBOARD] Đã tách phân cảnh #${seg.id} thành 2 phân cảnh.');
  }

  void mergeWithNextSegment(int segmentId) {
    final idx = state.segments.indexWhere((s) => s.id == segmentId);
    if (idx == -1 || idx >= state.segments.length - 1) return;
    final seg1 = state.segments[idx];
    final seg2 = state.segments[idx + 1];

    final mergedScenes = [...seg1.scenesToUse];
    for (final s in seg2.scenesToUse) {
      if (!mergedScenes.any((m) => m.sceneId == s.sceneId)) {
        mergedScenes.add(s);
      }
    }

    final mergedSeg = seg1.copyWith(
      voiceoverText: '${seg1.voiceoverText.trim()} ${seg2.voiceoverText.trim()}'.trim(),
      scenesToUse: mergedScenes,
    );

    final updated = List<ScriptSegment>.from(state.segments);
    updated[idx] = mergedSeg;
    updated.removeAt(idx + 1);
    state = state.copyWith(segments: updated);
    _addLog('[STORYBOARD] Đã gộp phân cảnh #${seg1.id} và #${seg2.id}.');
  }

  String _resolveOrchestratorScript() {
    final resolved = EngineResolver.resolveScript('movie_review_orchestrator.py');
    if (resolved != null && resolved.existsSync()) {
      return resolved.path;
    }
    final rootDir = PythonBridge.resolveRootDir();
    final candidates = [
      p.join(rootDir, 'py_engine', 'movie_review_orchestrator.py'),
      p.join(rootDir, 'py_engine', 'movie_review_orchestrator.pyc'),
      p.join(rootDir, 'movie_review_orchestrator.py'),
      p.join(rootDir, 'movie_review_orchestrator.pyc'),
    ];
    for (final c in candidates) {
      if (File(c).existsSync()) return c;
    }
    return p.join(rootDir, 'py_engine', 'movie_review_orchestrator.py');
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
    final tempAudioPath = p.join(_workspacePath, 'preview_tts_$segmentId.mp3');

    final args = [
      scriptPath,
      '--action', 'test_tts',
      '--text', trimmed,
      '--voice', state.ttsVoice,
      '--speed', state.ttsSpeed.toStringAsFixed(2),
      '--output', tempAudioPath,
    ];

    try {
      final env = PythonBridge.buildEnvironment(rootDir: rootDir, pythonBin: pythonBin);
      final res = await Process.run(pythonBin, args, environment: env);
      if (res.exitCode == 0 && File(tempAudioPath).existsSync()) {
        _ttsPlayer ??= Player();
        _ttsPlayer!.stream.completed.listen((completed) {
          if (completed && state.currentlyPlayingSegmentId == segmentId) {
            state = state.copyWith(clearPlayingId: true);
          }
        });
        await _ttsPlayer!.open(Media(tempAudioPath));
        state = state.copyWith(statusMessage: 'Đang phát thử câu #$segmentId');
      } else {
        state = state.copyWith(
          clearPlayingId: true,
          statusMessage: 'Không thể tạo giọng đọc thử: ${res.stderr}',
        );
      }
    } catch (e) {
      state = state.copyWith(
        clearPlayingId: true,
        statusMessage: 'Lỗi phát thử TTS: $e',
      );
    }
  }

  String get _workspacePath {
    final root = PythonBridge.resolveRootDir();
    final pName = state.projectName ?? 'default';
    final vName = state.videoName ?? 'project';
    final safeName = p.withoutExtension(vName).replaceAll(RegExp(r'[^\w\-]+'), '_');
    return p.join(root, 'resources', pName, 'workspace', 'movie_review', safeName);
  }

  String get workspacePath => _workspacePath;

  String get _outputMp4Path {
    final root = PythonBridge.resolveRootDir();
    final pName = state.projectName ?? 'default';
    final vName = state.videoName ?? 'project';
    final safeName = p.withoutExtension(vName).replaceAll(RegExp(r'[^\w\-]+'), '_');
    final ratioSuffix = state.aspectRatio == '9:16' ? 'vertical' : 'landscape';
    return p.join(root, 'resources', pName, 'output', '${safeName}_review_$ratioSuffix.mp4');
  }

  String get outputMp4Path => _outputMp4Path;

  static const List<String> stepOrder = [
    'mr01_blueprint',
    'mr02_scene_detect',
    'mr03_script_gen',
    'mr04_tts',
    'mr05_assembly',
    'mr06_subtitle',
    'mr07_encode',
  ];

  static const Map<String, List<String>> stepArtifactFiles = {
    'mr01_blueprint': ['blueprint.json'],
    'mr02_scene_detect': ['scenes_meta.json', 'keyframes', 'scenes'],
    'mr03_script_gen': ['review_script.json', 'review_script_synced.json'],
    'mr04_tts': ['audio_segments', 'audio_tts'],
    'mr05_assembly': ['rendered_segments', 'segments', 'concat_review.txt', 'temp_concat_review.mp4'],
    'mr06_subtitle': ['subtitles_review.ass'],
    'mr07_encode': [],
  };

  Future<void> deleteStepCache(String stepId) async {
    final idx = stepOrder.indexOf(stepId);
    if (idx == -1) return;

    final wsDir = Directory(_workspacePath);
    if (wsDir.existsSync()) {
      for (int i = idx; i < stepOrder.length; i++) {
        final currentStep = stepOrder[i];
        final artifacts = stepArtifactFiles[currentStep] ?? [];
        for (final art in artifacts) {
          final f = File(p.join(_workspacePath, art));
          if (f.existsSync()) {
            try { f.deleteSync(); } catch (_) {}
          }
          final d = Directory(p.join(_workspacePath, art));
          if (d.existsSync()) {
            try { d.deleteSync(recursive: true); } catch (_) {}
          }
        }
      }
    }

    final outVideo = File(_outputMp4Path);
    if (outVideo.existsSync()) {
      try { outVideo.deleteSync(); } catch (_) {}
    }

    _addLog('🧹 [CACHE] Đã dọn sạch cache từ bước $stepId đến bước cuối cùng.');

    if (idx <= stepOrder.indexOf('mr02_scene_detect')) {
      state = state.copyWith(availableScenes: []);
    }
    if (idx <= stepOrder.indexOf('mr03_script_gen')) {
      state = state.copyWith(segments: [], hasCachedData: false);
    }
    if (idx <= stepOrder.indexOf('mr07_encode')) {
      state = state.copyWith(outputVideoPath: null);
    }

    checkAndRestoreCache();
  }

  Future<bool> rerunFromStep(String stepId) async {
    if (state.videoPath == null || state.isAnalyzing || state.isRendering) return false;

    final wsDir = Directory(_workspacePath);
    if (!wsDir.existsSync()) {
      _addLog('⚠️ [RERUN] Thư mục workspace chưa được khởi tạo.');
      return false;
    }

    final bpFile = File(p.join(_workspacePath, 'blueprint.json'));
    final scenesFile = File(p.join(_workspacePath, 'scenes_meta.json'));
    final scriptFile = File(p.join(_workspacePath, 'review_script.json'));

    if (stepId == 'mr02_scene_detect' && !bpFile.existsSync()) {
      _addLog('⚠️ [RERUN] Thiếu blueprint.json để chạy lại từ Bước 2. Hãy chạy từ Bước 1.');
      return false;
    }
    if (stepId == 'mr03_script_gen' && (!bpFile.existsSync() || !scenesFile.existsSync())) {
      _addLog('⚠️ [RERUN] Thiếu blueprint.json hoặc scenes_meta.json để sinh kịch bản. Hãy chạy từ Bước 1 hoặc 2.');
      return false;
    }
    if ((stepId == 'mr04_tts' || stepId == 'mr05_assembly' || stepId == 'mr06_subtitle' || stepId == 'mr07_encode') && !scriptFile.existsSync()) {
      _addLog('⚠️ [RERUN] Thiếu review_script.json để tiếp tục. Hãy chạy từ Bước 3 (Sinh kịch bản).');
      return false;
    }

    // 1. Dọn dẹp cache từ stepId đến cuối
    await deleteStepCache(stepId);

    // 2. Kích hoạt luồng chạy tương ứng
    final idx = stepOrder.indexOf(stepId);
    if (idx <= stepOrder.indexOf('mr03_script_gen')) {
      await startAnalysis(fromStep: stepId);
    } else {
      await startRender(fromStep: stepId);
    }
    return true;
  }

  Future<void> startAnalysis({String? fromStep}) async {
    if (state.videoPath == null || state.isAnalyzing) return;

    state = state.copyWith(
      isAnalyzing: true,
      progress: 0.05,
      statusMessage: 'Bắt đầu phân tích AI Two-Stage...',
      consoleLogs: ['[AI Review] Khởi động bộ điều phối phân tích...'],
    );

    final rootDir = PythonBridge.resolveRootDir();
    final pythonBin = PythonBridge.resolvePythonBin();
    final scriptPath = _resolveOrchestratorScript();

    _addLog('🚀 [ENGINE] Khởi chạy phân tích video với: ${p.basename(scriptPath)}');
    _addLog('🔍 [PATH] Script path: $scriptPath');
    _addLog('🐍 [PYTHON] $pythonBin');

    if (!File(scriptPath).existsSync()) {
      state = state.copyWith(
        isAnalyzing: false,
        statusMessage: 'Không tìm thấy file script phân tích: $scriptPath',
      );
      _addLog('❌ [ERROR] File script $scriptPath không tồn tại trên hệ thống!');
      return;
    }

    final actsJson = jsonEncode(state.actConfig.toJson());
    final args = [
      scriptPath,
      '--action', 'analyze',
      '--video', state.videoPath!,
      '--workspace', _workspacePath,
      '--genre', state.genre.id,
      if (!state.isContentDriven) ...['--duration', state.targetDurationSec.toString()],
      '--speed', state.ttsSpeed.toStringAsFixed(2),
      '--voice', state.ttsVoice,
      '--style', state.reviewStyle.id,
      '--ratio', state.aspectRatio,
      '--lang', state.targetLang,
      '--acts-config', actsJson,
      if (state.customPrompt.trim().isNotEmpty) ...['--prompt', state.customPrompt.trim()],
      if (fromStep != null) ...['--from-step', fromStep],
    ];

    if (state.apiKey.isNotEmpty) {
      args.addAll(['--api-key', state.apiKey]);
    }
    if (state.aiModel.isNotEmpty) {
      args.addAll(['--model', state.aiModel]);
    }

    try {
      final env = PythonBridge.buildEnvironment(rootDir: rootDir, pythonBin: pythonBin);
      _activeProcess = await Process.start(pythonBin, args, environment: env);

      _activeProcess!.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        _handleProcessLine(line);
      });

      _activeProcess!.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        if (line.trim().isNotEmpty) {
          _addLog('[STDERR] $line');
        }
      });

      final exitCode = await _activeProcess!.exitCode;
      _activeProcess = null;

      if (exitCode == 0) {
        _loadGeneratedData();
        state = state.copyWith(
          isAnalyzing: false,
          hasCachedData: true,
          progress: 1.0,
          statusMessage: 'Đã sinh kịch bản thành công! Hãy kiểm tra & chỉnh sửa.',
        );
      } else {
        state = state.copyWith(
          isAnalyzing: false,
          statusMessage: 'Lỗi khi phân tích video (Mã lỗi: $exitCode).',
        );
      }
    } catch (e) {
      _activeProcess = null;
      state = state.copyWith(
        isAnalyzing: false,
        statusMessage: 'Ngoại lệ: $e',
      );
      _addLog('[ERROR] $e');
    }
  }

  Future<void> startRender({String? fromStep}) async {
    if (state.videoPath == null || state.isRendering || state.segments.isEmpty) return;

    state = state.copyWith(
      isRendering: true,
      progress: 0.0,
      statusMessage: 'Bắt đầu dựng & xuất video review...',
    );

    // Tự động lưu cấu hình mới nhất từ configProvider xuống config.yaml
    if (_ref != null) {
      try {
        await _ref.read(configProvider.notifier).save();
        _addLog('💾 [CONFIG] Đã tự động lưu cấu hình mới nhất vào config.yaml trước khi render.');
      } catch (e) {
        _addLog('⚠️ [CONFIG] Không thể tự động lưu config.yaml: $e');
      }
    }

    // Lưu lại review_script.json đã chỉnh sửa vào workspace
    final scriptFile = File(p.join(_workspacePath, 'review_script.json'));
    final scriptJson = {
      'title': state.videoName ?? 'Movie Review',
      'genre': state.genre.id,
      'style': state.reviewStyle.id,
      'target_duration_sec': state.targetDurationSec,
      'total_word_count': state.currentWordCount,
      'script': state.segments.map((s) => s.toJson()).toList(),
    };
    await scriptFile.parent.create(recursive: true);
    await scriptFile.writeAsString(jsonEncode(scriptJson));

    final rootDir = PythonBridge.resolveRootDir();
    final pythonBin = PythonBridge.resolvePythonBin();
    final scriptPath = _resolveOrchestratorScript();
    final outMp4 = _outputMp4Path;

    _addLog('🚀 [ENGINE] Bắt đầu dựng video review với: ${p.basename(scriptPath)}');
    _addLog('📁 [OUTPUT] File đích: $outMp4');
    _addLog('🔍 [PATH] Script path: $scriptPath');
    _addLog('🐍 [PYTHON] $pythonBin');

    if (!File(scriptPath).existsSync()) {
      state = state.copyWith(
        isRendering: false,
        statusMessage: 'Không tìm thấy file script dựng video: $scriptPath',
      );
      _addLog('❌ [ERROR] File script $scriptPath không tồn tại trên hệ thống!');
      return;
    }

    // Đảm bảo thư mục output tồn tại
    final outParent = File(outMp4).parent;
    if (!outParent.existsSync()) {
      await outParent.create(recursive: true);
    }

    final args = [
      scriptPath,
      '--action', 'render',
      '--video', state.videoPath!,
      '--workspace', _workspacePath,
      '--output', outMp4,
      '--voice', state.ttsVoice,
      '--speed', state.ttsSpeed.toStringAsFixed(2),
      '--ratio', state.aspectRatio,
      '--tts-volume', state.ttsVolume.toStringAsFixed(2),
      '--original-audio-volume', state.originalAudioVolume.toStringAsFixed(2),
      '--bgm-volume', state.bgmVolume.toStringAsFixed(2),
      if (state.burnSubtitles) '--burn-subtitles' else '--no-subtitles',
      if (state.enableInpaint) '--enable-inpaint' else '--no-inpaint',
      if (state.flipHorizontal) '--flip-horizontal',
      if (state.cropZoom) '--crop-zoom',
      if (state.muteMovieAudio) '--mute-movie-audio',
      if (fromStep != null) ...['--from-step', fromStep],
    ];

    if (state.apiKey.isNotEmpty) {
      args.addAll(['--api-key', state.apiKey]);
    }
    if (state.aiModel.isNotEmpty) {
      args.addAll(['--model', state.aiModel]);
    }

    try {
      final env = PythonBridge.buildEnvironment(rootDir: rootDir, pythonBin: pythonBin);
      _activeProcess = await Process.start(pythonBin, args, environment: env);

      _activeProcess!.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        _handleProcessLine(line);
      });

      _activeProcess!.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        if (line.trim().isNotEmpty) {
          _addLog('[STDERR] $line');
        }
      });

      final exitCode = await _activeProcess!.exitCode;
      _activeProcess = null;

      if (exitCode == 0 && File(outMp4).existsSync()) {
        state = state.copyWith(
          isRendering: false,
          progress: 1.0,
          outputVideoPath: outMp4,
          statusMessage: 'Xuất video review thành công!',
        );
      } else {
        state = state.copyWith(
          isRendering: false,
          statusMessage: 'Lỗi khi dựng video (Mã lỗi: $exitCode).',
        );
      }
    } catch (e) {
      _activeProcess = null;
      state = state.copyWith(
        isRendering: false,
        statusMessage: 'Ngoại lệ: $e',
      );
      _addLog('❌ [ERROR] Lỗi ngoại lệ khi dựng video: $e');
    }
  }

  void cancelProcess() {
    _activeProcess?.kill();
    _activeProcess = null;
    state = state.copyWith(
      isAnalyzing: false,
      isRendering: false,
      statusMessage: 'Đã hủy tiến trình.',
    );
  }

  void _handleProcessLine(String line) {
    if (line.trim().isEmpty) return;
    try {
      final json = jsonDecode(line) as Map<String, dynamic>;
      final type = json['type'] as String?;

      if (type == 'progress') {
        final prog = (json['progress'] as num?)?.toDouble() ?? state.progress;
        final status = json['status'] as String? ?? state.statusMessage;
        state = state.copyWith(progress: prog, statusMessage: status);
      } else if (type == 'log') {
        final msg = json['message'] as String? ?? '';
        final level = json['level'] as String? ?? 'info';
        _addLog('[$level] $msg');
      } else if (type == 'blueprint_ready') {
        final bpData = json['data'] as Map<String, dynamic>?;
        final rawCh = bpData?['chapters'] as List? ?? [];
        final chapters = rawCh.whereType<Map<String, dynamic>>().toList();
        if (chapters.isNotEmpty) {
          state = state.copyWith(
            statusMessage: 'Đã xong dàn ý 5 hồi, đang quét cảnh...',
            actConfig: state.actConfig.copyWith(availableChapters: chapters),
          );
        } else {
          state = state.copyWith(statusMessage: 'Đã xong dàn ý 5 hồi, đang quét cảnh...');
        }
      } else if (type == 'script_ready') {
        state = state.copyWith(statusMessage: 'Đã nhận kịch bản từ Gemini!');
      }
    } catch (_) {
      _addLog(line);
    }
  }

  void _addLog(String message) {
    final updatedLogs = List<String>.from(state.consoleLogs)..add(message);
    if (updatedLogs.length > 500) {
      updatedLogs.removeAt(0);
    }
    final isErr = message.contains('[ERROR]') || message.contains('[STDERR]');
    state = state.copyWith(consoleLogs: updatedLogs);
    PythonBridge.addLog('movie_review', isErr ? 'stderr' : 'stdout', message);
  }

  void _loadGeneratedData() {
    try {
      final scenesFile = File(p.join(_workspacePath, 'scenes_meta.json'));
      final scriptFile = File(p.join(_workspacePath, 'review_script.json'));
      //final bpFile = File(p.join(_workspacePath, 'blueprint.json'));

      List<SceneMeta> scenes = [];
      if (scenesFile.existsSync()) {
        final raw = jsonDecode(scenesFile.readAsStringSync()) as List;
        scenes = raw.map((s) => SceneMeta.fromJson(s as Map<String, dynamic>)).toList();
      }

      List<ScriptSegment> segments = [];
      int? updatedDurationSec;
      if (scriptFile.existsSync()) {
        final raw = jsonDecode(scriptFile.readAsStringSync()) as Map<String, dynamic>;
        final scriptList = raw['script'] as List? ?? [];
        segments = scriptList
            .map((s) => ScriptSegment.fromJson(s as Map<String, dynamic>, scenes))
            .toList();
        final rawDur = raw['target_duration_sec'] as num?;
        if (rawDur != null && rawDur > 0) {
          updatedDurationSec = rawDur.toInt();
        }
      }

      List<Map<String, dynamic>> chapters = [];
      final metaFile = File(p.join(_workspacePath, 'metadata.json'));
      String loadedTitle = '';
      String loadedDesc = '';
      List<String> loadedHashtags = [];
      if (metaFile.existsSync()) {
        try {
          final metaRaw = jsonDecode(metaFile.readAsStringSync()) as Map<String, dynamic>;
          loadedTitle = metaRaw['title']?.toString() ?? '';
          loadedDesc = metaRaw['description']?.toString() ?? '';
          final rawTags = metaRaw['hashtags'] as List? ?? [];
          loadedHashtags = rawTags.map((e) => e.toString()).toList();
        } catch (_) {}
      }

      final newActConfig = chapters.isNotEmpty
          ? state.actConfig.copyWith(availableChapters: chapters)
          : state.actConfig;

      state = state.copyWith(
        availableScenes: scenes,
        segments: segments,
        targetDurationSec: updatedDurationSec ?? state.targetDurationSec,
        actConfig: newActConfig,
        metaTitle: loadedTitle.isNotEmpty ? loadedTitle : state.metaTitle,
        metaDesc: loadedDesc.isNotEmpty ? loadedDesc : state.metaDesc,
        metaHashtags: loadedHashtags.isNotEmpty ? loadedHashtags : state.metaHashtags,
      );
    } catch (e) {
      _addLog('[ERROR] Không thể đọc dữ liệu workspace: $e');
    }
  }
}
