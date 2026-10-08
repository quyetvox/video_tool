import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../../core/providers.dart';
import '../../../../core/python_bridge.dart';
import '../../../../core/engine_resolver.dart';
import '../../../../models/app_config.dart';
import '../../../../models/subtitle_segment.dart';
import '../models/lecture_illustrator_model.dart';

final lectureIllustratorProvider =
    StateNotifierProvider<LectureIllustratorController, LectureIllustratorState>(
        (ref) => LectureIllustratorController(ref));

class LectureIllustratorController extends StateNotifier<LectureIllustratorState> {
  final Ref _ref;
  Process? _activeProcess;

  LectureIllustratorController(this._ref) : super(const LectureIllustratorState());

  String get _workspacePath {
    final root = PythonBridge.resolveRootDir();
    final pName = (state.projectName != null && state.projectName!.isNotEmpty)
        ? state.projectName!
        : 'default';
    final vName = (state.videoName != null && state.videoName!.isNotEmpty)
        ? state.videoName!
        : (state.videoPath != null ? p.basename(state.videoPath!) : 'default_video');
    final safeName = p.withoutExtension(vName).replaceAll(RegExp(r'[^\w\-]+'), '_');
    return p.join(root, 'resources', pName, 'workspace', 'lecture_illustrator', safeName);
  }

  String get _projectJsonPath => p.join(_workspacePath, 'lecture_project.json');

  void selectVideoFromProject({
    required String projectName,
    required String videoPath,
    required String videoName,
  }) {
    state = state.copyWith(
      projectName: projectName,
      videoPath: videoPath,
      videoName: videoName,
      progress: 0.0,
      statusMessage: null,
      lastError: null,
    );
    final hasLoaded = _tryLoadExistingProject();
    if (!hasLoaded) {
      _syncFromGlobalConfig();
    }
  }

  void _syncFromGlobalConfig() {
    try {
      syncFromConfig(_ref.read(configProvider));
    } catch (_) {}
  }

  /// Đồng bộ các cấu hình từ AppConfig (Cụm 1 SubtitleInspector) vào LectureProjectConfig
  void syncFromConfig(AppConfig appCfg) {
    try {
      String voice = state.config.ttsVoice;
      if (appCfg.ttsVoice.isNotEmpty) {
        final vLow = appCfg.ttsVoice.toLowerCase();
        if (vLow.contains('hoaimy') || vLow.contains('hoai_my')) {
          voice = 'hoai_my';
        } else if (vLow.contains('namminh') || vLow.contains('nam_minh')) {
          voice = 'nam_minh';
        } else {
          voice = appCfg.ttsVoice;
        }
      }

      final cur = state.config;
      final updated = cur.copyWith(
        targetLang: appCfg.targetLang.isNotEmpty ? appCfg.targetLang : cur.targetLang,
        secondaryLang: appCfg.secondaryLang.isNotEmpty ? appCfg.secondaryLang : cur.secondaryLang,
        pronounMode: appCfg.pronounMode.isNotEmpty ? appCfg.pronounMode : cur.pronounMode,
        ttsVoice: voice,
        ttsSpeed: appCfg.ttsSpeed > 0 ? appCfg.ttsSpeed : cur.ttsSpeed,
        bgmVolume: appCfg.musicVol >= 0 ? appCfg.musicVol : cur.bgmVolume,
        voiceVolume: appCfg.ttsVol > 0 ? appCfg.ttsVol : cur.voiceVolume,
        burnSubtitles: appCfg.showSubtitle,
        subtitleMode: appCfg.subtitleSecondaryShow ? 'bilingual' : 'single',
        subtitleSecondaryShow: appCfg.subtitleSecondaryShow,
        subtitleOrder: appCfg.subtitleOrder.isNotEmpty ? appCfg.subtitleOrder : cur.subtitleOrder,
        fontName: appCfg.fontName.isNotEmpty ? appCfg.fontName : cur.fontName,
        secondaryFontName: appCfg.subtitleSecondaryFontName.isNotEmpty ? appCfg.subtitleSecondaryFontName : cur.secondaryFontName,
        fontSize: appCfg.fontSize.isNotEmpty ? appCfg.fontSize : cur.fontSize,
        fontColor: appCfg.fontColor.isNotEmpty ? appCfg.fontColor : cur.fontColor,
        outlineColor: appCfg.outlineColor.isNotEmpty ? appCfg.outlineColor : cur.outlineColor,
        secondaryFontColor: appCfg.subtitleSecondaryFontColor.isNotEmpty ? appCfg.subtitleSecondaryFontColor : cur.secondaryFontColor,
        secondaryScale: appCfg.subtitleSecondaryFontScale > 0 ? appCfg.subtitleSecondaryFontScale : cur.secondaryScale,
        videoBitrate: appCfg.videoBitrate.isNotEmpty ? appCfg.videoBitrate : cur.videoBitrate,
        watermarkEnabled: appCfg.watermarkEnabled,
        watermarkPath: appCfg.watermarkImage.isNotEmpty ? appCfg.watermarkImage : cur.watermarkPath,
        enableInpaint: appCfg.inpaintShowBox,
        inpaintEngine: appCfg.inpaintEngine.isNotEmpty ? appCfg.inpaintEngine : cur.inpaintEngine,
        inpaintBlurRadius: appCfg.inpaintBlurRadius > 0 ? appCfg.inpaintBlurRadius : cur.inpaintBlurRadius,
        boxBgColor: appCfg.boxBgColor.isNotEmpty ? appCfg.boxBgColor : cur.boxBgColor,
        boxOpacity: appCfg.boxBgOpacity > 0 ? appCfg.boxBgOpacity : cur.boxOpacity,
        inpaintMethod: appCfg.inpaintMethod.isNotEmpty ? appCfg.inpaintMethod : cur.inpaintMethod,
        inpaintRegion: appCfg.inpaintRegion != null && appCfg.inpaintRegion!.length == 4 ? appCfg.inpaintRegion! : cur.inpaintRegion,
      );

      state = state.copyWith(config: updated);
    } catch (_) {}
  }

  bool _tryLoadExistingProject() {
    bool loadedProject = false;
    try {
      final file = File(_projectJsonPath);
      if (file.existsSync()) {
        final content = file.readAsStringSync();
        final raw = jsonDecode(content) as Map<String, dynamic>;
        final loaded = LectureIllustratorState.fromJson(raw);
        state = state.copyWith(
          config: loaded.config,
          batches: loaded.batches,
          videoDuration: loaded.videoDuration,
          videoWidth: loaded.videoWidth,
          videoHeight: loaded.videoHeight,
          statusMessage: 'Đã nạp ${loaded.batches.length} phân đoạn bài giảng.',
        );
        loadedProject = true;
      }
    } catch (e) {
      // Ignore load error
    }

    // Đọc thêm lecture_metadata.json nếu có
    try {
      final metaFile = File(p.join(_workspacePath, 'lecture_metadata.json'));
      if (metaFile.existsSync()) {
        final rawMeta = jsonDecode(metaFile.readAsStringSync()) as Map<String, dynamic>;
        final t = rawMeta['title']?.toString() ?? '';
        final d = rawMeta['description']?.toString() ?? '';
        final h = (rawMeta['hashtags'] as List?)?.map((e) => e.toString()).toList() ?? [];
        state = state.copyWith(
          metaTitle: t.isNotEmpty ? t : state.metaTitle,
          metaDesc: d.isNotEmpty ? d : state.metaDesc,
          metaHashtags: h.isNotEmpty ? h : state.metaHashtags,
        );
      }
    } catch (_) {}

    return loadedProject;
  }

  void _saveMetadataToDisk() {
    try {
      final metaFile = File(p.join(_workspacePath, 'lecture_metadata.json'));
      final data = {
        'title': state.metaTitle,
        'description': state.metaDesc,
        'hashtags': state.metaHashtags,
      };
      metaFile.writeAsStringSync(jsonEncode(data));
    } catch (_) {}
  }

  void _saveProjectToDisk() {
    try {
      final dir = Directory(_workspacePath);
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final file = File(_projectJsonPath);
      final jsonStr = jsonEncode(state.toJson());
      file.writeAsStringSync(jsonStr);
    } catch (_) {}
  }

  String _resolveOrchestratorScript() {
    final resolved = EngineResolver.resolveScript('lecture_illustrator_orchestrator.py');
    if (resolved != null && resolved.existsSync()) {
      return resolved.path;
    }
    final rootDir = PythonBridge.resolveRootDir();
    return p.join(rootDir, 'py_engine', 'lecture_illustrator_orchestrator.py');
  }

  String? get outputVideoPath {
    if (state.projectName == null || state.videoName == null) return null;
    final root = PythonBridge.resolveRootDir();
    final pName = state.projectName!;
    final safeName = p.withoutExtension(state.videoName!).replaceAll(RegExp(r'[^\w\-]+'), '_');
    final outPath = p.join(root, 'resources', pName, 'output', '${safeName}_illustrated.mp4');
    if (File(outPath).existsSync()) return outPath;
    return null;
  }

  Future<void> startAnalysis() async {
    if (state.videoPath == null || state.videoPath!.isEmpty) return;
    state = state.copyWith(
      isAnalyzing: true,
      progress: 0.05,
      statusMessage: 'Bắt đầu phân tích bài giảng...',
      lastError: null,
    );

    _saveProjectToDisk();

    final pythonBin = PythonBridge.resolvePythonBin();
    final scriptPath = _resolveOrchestratorScript();
    final config = _ref.read(configProvider);
    syncFromConfig(config);

    final args = [
      scriptPath,
      '--mode', 'analyze',
      '--input', state.videoPath!,
      '--workspace', _workspacePath,
      '--project-name', state.projectName ?? 'default',
      '--project-file', _projectJsonPath,
      '--source-lang', state.config.sourceLang,
      '--target-lang', state.config.targetLang,
      '--secondary-lang', state.config.secondaryLang,
      '--pronoun-mode', state.config.pronounMode,
      '--voice-mode', state.config.voiceMode,
      '--tts-voice', state.config.ttsVoice,
      '--tts-speed', state.config.ttsSpeed.toString(),
      '--bgm-volume', state.config.bgmVolume.toString(),
      '--voice-volume', state.config.voiceVolume.toString(),
      '--burn-subtitles', state.config.burnSubtitles.toString(),
      '--subtitle-mode', state.config.subtitleMode,
      '--subtitle-secondary-show', state.config.subtitleSecondaryShow.toString(),
      '--subtitle-order', state.config.subtitleOrder,
      '--font-name', state.config.fontName,
      if (state.config.secondaryFontName != null && state.config.secondaryFontName!.isNotEmpty) ...[
        '--secondary-font-name', state.config.secondaryFontName!,
      ],
      '--font-size', state.config.fontSize,
      '--font-color', state.config.fontColor,
      '--outline-color', state.config.outlineColor,
      '--secondary-font-color', state.config.secondaryFontColor,
      '--secondary-scale', state.config.secondaryScale.toString(),
      '--video-bitrate', state.config.videoBitrate,
      '--watermark-enabled', state.config.watermarkEnabled.toString(),
      if (state.config.watermarkPath.isNotEmpty) ...[
        '--watermark-path', state.config.watermarkPath,
      ],
      '--enable-inpaint', state.config.enableInpaint.toString(),
      '--inpaint-engine', state.config.inpaintEngine,
      '--inpaint-blur-radius', state.config.inpaintBlurRadius.toString(),
      '--box-bg-color', state.config.boxBgColor,
      '--box-opacity', state.config.boxOpacity.toString(),
      '--inpaint-method', state.config.inpaintMethod,
      '--layout-preset', state.config.visualLayoutPreset,
    ];

    if (config.translatorType.isNotEmpty) {
      args.addAll(['--translator-type', config.translatorType]);
    }
    if (config.translatorApiKey.isNotEmpty) {
      args.addAll(['--api-key', config.translatorApiKey]);
    }
    if (config.translatorModel.isNotEmpty) {
      args.addAll(['--model', config.translatorModel]);
    }
    if (config.translatorBaseUrl.isNotEmpty) {
      args.addAll(['--base-url', config.translatorBaseUrl]);
    }

    final rootDir = PythonBridge.resolveRootDir();

    try {
      final env = PythonBridge.buildEnvironment(rootDir: rootDir, pythonBin: pythonBin);
      _activeProcess = await Process.start(
        pythonBin,
        args,
        workingDirectory: rootDir,
        environment: env,
      );
      _activeProcess!.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(_handleProcessOutput);

      _activeProcess!.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((err) {
        if (err.trim().isNotEmpty) {
          PythonBridge.addLog('lecture_illustrator', 'stderr', err);
        }
      });

      final exitCode = await _activeProcess!.exitCode;
      _activeProcess = null;

      if (exitCode == 0) {
        _tryLoadExistingProject();
        state = state.copyWith(
          isAnalyzing: false,
          progress: 1.0,
          statusMessage: 'Phân tích bài giảng hoàn tất!',
        );
      } else {
        state = state.copyWith(
          isAnalyzing: false,
          statusMessage: 'Phân tích thất bại (Exit code: $exitCode)',
          lastError: 'Quá trình phân tích bài giảng gặp lỗi.',
        );
      }
    } catch (e) {
      state = state.copyWith(
        isAnalyzing: false,
        statusMessage: 'Lỗi khởi chạy: $e',
        lastError: e.toString(),
      );
    }
  }

  Future<void> startRender() async {
    if (state.batches.isEmpty) return;
    state = state.copyWith(
      isRendering: true,
      progress: 0.10,
      statusMessage: 'Bắt đầu biên tập & render video...',
      lastError: null,
    );

    try {
      syncFromConfig(_ref.read(configProvider));
    } catch (_) {}

    _saveProjectToDisk();

    final pythonBin = PythonBridge.resolvePythonBin();
    final scriptPath = _resolveOrchestratorScript();
    final root = PythonBridge.resolveRootDir();
    final pName = state.projectName ?? 'default';
    final vName = state.videoName ?? 'lecture_illustrated';
    final safeName = p.withoutExtension(vName).replaceAll(RegExp(r'[^\w\-]+'), '_');
    final outVideoPath = p.join(root, 'resources', pName, 'output', '${safeName}_illustrated.mp4');

    final args = [
      scriptPath,
      '--mode', 'render',
      '--project-file', _projectJsonPath,
      '--workspace', _workspacePath,
      '--output', outVideoPath,
    ];

    try {
      final env = PythonBridge.buildEnvironment(rootDir: root, pythonBin: pythonBin);
      _activeProcess = await Process.start(
        pythonBin,
        args,
        workingDirectory: root,
        environment: env,
      );
      _activeProcess!.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(_handleProcessOutput);

      _activeProcess!.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((err) {
        if (err.trim().isNotEmpty) {
          PythonBridge.addLog('lecture_illustrator', 'stderr', err);
        }
      });

      final exitCode = await _activeProcess!.exitCode;
      _activeProcess = null;

      if (exitCode == 0) {
        state = state.copyWith(
          isRendering: false,
          progress: 1.0,
          statusMessage: 'Xuất video hoàn chỉnh thành công!',
        );
        _ref.invalidate(projectVideosProvider);
      } else {
        state = state.copyWith(
          isRendering: false,
          statusMessage: 'Render thất bại (Exit code: $exitCode)',
          lastError: 'Quá trình render FFmpeg gặp lỗi.',
        );
      }
    } catch (e) {
      state = state.copyWith(
        isRendering: false,
        statusMessage: 'Lỗi xuất video: $e',
        lastError: e.toString(),
      );
    }
  }

  void cancelProcess() {
    if (_activeProcess != null) {
      _activeProcess!.kill(ProcessSignal.sigterm);
      _activeProcess = null;
      state = state.copyWith(
        isAnalyzing: false,
        isRendering: false,
        statusMessage: 'Đã hủy tiến trình.',
      );
    }
  }

  void _handleProcessOutput(String line) {
    if (line.trim().isEmpty) return;
    try {
      final json = jsonDecode(line);
      if (json is Map<String, dynamic>) {
        final type = json['type']?.toString();
        if (type == 'progress') {
          final pVal = (json['progress'] as num?)?.toDouble() ?? state.progress;
          final status = json['status']?.toString();
          state = state.copyWith(progress: pVal, statusMessage: status);
        } else if (type == 'log') {
          final msg = json['message']?.toString() ?? '';
          final level = json['level']?.toString() ?? 'info';
          PythonBridge.addLog('lecture_illustrator', level, msg);
        }
      }
    } catch (_) {
      PythonBridge.addLog('lecture_illustrator', 'stdout', line);
    }
  }

  // --- BATCH UPDATES & EDITS ---

  void selectBatch(String batchId) {
    state = state.copyWith(selectedBatchId: batchId);
  }

  void updateBatchText(String batchId, {String? original, String? translated}) {
    final updated = state.batches.map((b) {
      if (b.id == batchId) {
        return b.copyWith(
          transcriptOriginal: original ?? b.transcriptOriginal,
          transcriptTranslated: translated ?? b.transcriptTranslated,
        );
      }
      return b;
    }).toList();
    state = state.copyWith(batches: updated);
    _saveProjectToDisk();
  }

  void updateBatchTemplate(String batchId, String newTemplate) {
    final updated = state.batches.map((b) {
      if (b.id == batchId) {
        final newScene = Map<String, dynamic>.from(b.scene);
        newScene['template'] = newTemplate;
        return b.copyWith(scene: newScene);
      }
      return b;
    }).toList();
    state = state.copyWith(batches: updated);
    _saveProjectToDisk();
  }

  void assignAssetToBatch(
    String batchId, {
    required String filePath,
    String type = 'image',
    String layout = 'pip',
  }) {
    final updated = state.batches.map((b) {
      if (b.id == batchId) {
        return b.copyWith(
          activeAsset: BatchActiveAsset(
            filePath: filePath,
            type: type,
            source: 'user_import',
            layout: layout,
            locked: true,
          ),
        );
      }
      return b;
    }).toList();
    state = state.copyWith(batches: updated);
    _saveProjectToDisk();
  }

  void clearBatchAsset(String batchId) {
    final updated = state.batches.map((b) {
      if (b.id == batchId) {
        return b.copyWith(clearActiveAsset: true);
      }
      return b;
    }).toList();
    state = state.copyWith(batches: updated);
    _saveProjectToDisk();
  }

  void toggleBatchLock(String batchId) {
    final updated = state.batches.map((b) {
      if (b.id == batchId && b.activeAsset != null) {
        final curLocked = b.activeAsset!.locked;
        return b.copyWith(
          activeAsset: b.activeAsset!.copyWith(locked: !curLocked),
        );
      }
      return b;
    }).toList();
    state = state.copyWith(batches: updated);
    _saveProjectToDisk();
  }

  // --- CONFIG SETTERS ---

  void updateConfig(LectureProjectConfig Function(LectureProjectConfig) updater) {
    state = state.copyWith(config: updater(state.config));
    _saveProjectToDisk();
  }

  void setVoiceMode(String mode) {
    if (state.config.voiceMode != mode) {
      try {
        final ttsDir = Directory(p.join(_workspacePath, 'tts'));
        if (ttsDir.existsSync()) {
          ttsDir.deleteSync(recursive: true);
        }
      } catch (_) {}
    }
    updateConfig((c) => c.copyWith(voiceMode: mode));
  }

  void setTtsVoice(String voice) {
    if (state.config.ttsVoice != voice) {
      try {
        final ttsDir = Directory(p.join(_workspacePath, 'tts'));
        if (ttsDir.existsSync()) {
          ttsDir.deleteSync(recursive: true);
        }
      } catch (_) {}
    }
    updateConfig((c) => c.copyWith(ttsVoice: voice));
  }

  /// Xóa bộ nhớ đệm (cache) trong workspace của bài giảng hiện tại
  Future<bool> clearProjectCache({
    bool clearAudio = true,
    bool clearScenes = true,
    bool clearAll = false,
  }) async {
    try {
      final wsDir = Directory(_workspacePath);
      if (!wsDir.existsSync()) return true;

      if (clearAll) {
        if (wsDir.existsSync()) {
          wsDir.deleteSync(recursive: true);
          wsDir.createSync(recursive: true);
        }
        state = state.copyWith(
          batches: [],
          statusMessage: 'Đã xóa toàn bộ bộ đệm bài giảng.',
        );
        return true;
      }

      if (clearAudio) {
        final ttsDir = Directory(p.join(_workspacePath, 'tts'));
        if (ttsDir.existsSync()) {
          ttsDir.deleteSync(recursive: true);
        }
      }

      if (clearScenes) {
        final scenesDir = Directory(p.join(_workspacePath, 'scenes'));
        if (scenesDir.existsSync()) {
          scenesDir.deleteSync(recursive: true);
        }
      }

      final assFile = File(p.join(_workspacePath, 'lecture_subtitles.ass'));
      if (assFile.existsSync()) assFile.deleteSync();
      final concatFile = File(p.join(_workspacePath, 'concat_scenes.txt'));
      if (concatFile.existsSync()) concatFile.deleteSync();

      state = state.copyWith(
        statusMessage: 'Đã xóa bộ nhớ đệm thành công.',
      );
      return true;
    } catch (e) {
      state = state.copyWith(
        lastError: 'Lỗi khi xóa cache: $e',
      );
      return false;
    }
  }
  void setTtsSpeed(double speed) =>
      updateConfig((c) => c.copyWith(ttsSpeed: speed));
  void setBgmVolume(double vol) =>
      updateConfig((c) => c.copyWith(bgmVolume: vol));
  void setBurnSubtitles(bool burn) =>
      updateConfig((c) => c.copyWith(burnSubtitles: burn));
  void setSubtitleMode(String mode) =>
      updateConfig((c) => c.copyWith(subtitleMode: mode));
  void setFontName(String font) =>
      updateConfig((c) => c.copyWith(fontName: font));
  void setFontSize(String size) =>
      updateConfig((c) => c.copyWith(fontSize: size));
  void setEnableInpaint(bool enabled) =>
      updateConfig((c) => c.copyWith(enableInpaint: enabled));
  void setInpaintEngine(String engine) =>
      updateConfig((c) => c.copyWith(inpaintEngine: engine));
  void setInpaintBlurRadius(int radius) =>
      updateConfig((c) => c.copyWith(inpaintBlurRadius: radius));
  void setBoxBgColor(String color) =>
      updateConfig((c) => c.copyWith(boxBgColor: color));
  void setBoxOpacity(double opacity) =>
      updateConfig((c) => c.copyWith(boxOpacity: opacity));
  void setInpaintMethod(String method) =>
      updateConfig((c) => c.copyWith(inpaintMethod: method));
  void setInpaintRegion(List<double> region) =>
      updateConfig((c) => c.copyWith(inpaintRegion: region));
  void setVisualLayoutPreset(String preset) =>
      updateConfig((c) => c.copyWith(visualLayoutPreset: preset));
  void setSourceLang(String lang) =>
      updateConfig((c) => c.copyWith(sourceLang: lang));
  void setTargetLang(String lang) =>
      updateConfig((c) => c.copyWith(targetLang: lang));
  void setSecondaryLang(String lang) =>
      updateConfig((c) => c.copyWith(secondaryLang: lang));
  void setPronounMode(String mode) =>
      updateConfig((c) => c.copyWith(pronounMode: mode));
  void setSubtitleSecondaryShow(bool show) =>
      updateConfig((c) => c.copyWith(subtitleSecondaryShow: show));
  void setSubtitleOrder(String order) =>
      updateConfig((c) => c.copyWith(subtitleOrder: order));
  void setVoiceVolume(double vol) =>
      updateConfig((c) => c.copyWith(voiceVolume: vol));
  void setFontColor(String color) =>
      updateConfig((c) => c.copyWith(fontColor: color));
  void setOutlineColor(String color) =>
      updateConfig((c) => c.copyWith(outlineColor: color));

  void setMetaTitle(String title) {
    state = state.copyWith(metaTitle: title);
    _saveMetadataToDisk();
  }

  void setMetaDesc(String desc) {
    state = state.copyWith(metaDesc: desc);
    _saveMetadataToDisk();
  }

  void setMetaHashtags(List<String> tags) {
    state = state.copyWith(metaHashtags: tags);
    _saveMetadataToDisk();
  }

  void cancelActiveTask() => cancelProcess();

  List<SubtitleSegment> toSubtitleSegments() {
    final list = <SubtitleSegment>[];
    int id = 0;
    for (final batch in state.batches) {
      if (batch.sentences.isNotEmpty) {
        for (final s in batch.sentences) {
          list.add(SubtitleSegment(
            id: id++,
            start: (s['start_sec'] as num?)?.toDouble() ?? batch.startSec,
            end: (s['end_sec'] as num?)?.toDouble() ?? batch.endSec,
            text: s['text']?.toString() ?? s['original']?.toString() ?? '',
            textVi: s['translated']?.toString() ?? s['text_vi']?.toString() ?? '',
            textSecondary: s['secondary']?.toString() ?? '',
            extra: {
              'batch_id': batch.id,
            },
          ));
        }
      } else {
        list.add(SubtitleSegment(
          id: id++,
          start: batch.startSec,
          end: batch.endSec,
          text: batch.transcriptOriginal,
          textVi: batch.transcriptTranslated,
          extra: {
            'batch_id': batch.id,
          },
        ));
      }
    }
    return list;
  }

  void syncSegmentsFromSubtitles(List<SubtitleSegment> subs) {
    final subMap = <String, List<SubtitleSegment>>{};
    for (final s in subs) {
      final batchId = s.extra['batch_id']?.toString();
      if (batchId != null) {
        subMap.putIfAbsent(batchId, () => []).add(s);
      }
    }

    final updatedBatches = state.batches.map((b) {
      final matchingSubs = subMap[b.id];
      if (matchingSubs == null || matchingSubs.isEmpty) return b;

      if (b.sentences.isNotEmpty) {
        final newSentences = <Map<String, dynamic>>[];
        for (int i = 0; i < b.sentences.length; i++) {
          final oldS = Map<String, dynamic>.from(b.sentences[i]);
          if (i < matchingSubs.length) {
            final sub = matchingSubs[i];
            oldS['text'] = sub.text;
            oldS['translated'] = sub.displayText;
            oldS['secondary'] = sub.textSecondary;
          }
          newSentences.add(oldS);
        }
        final fullTranslated = newSentences
            .map((s) => s['translated']?.toString() ?? '')
            .where((s) => s.isNotEmpty)
            .join(' ');
        return b.copyWith(
          sentences: newSentences,
          transcriptTranslated: fullTranslated.isNotEmpty ? fullTranslated : b.transcriptTranslated,
        );
      } else {
        final sub = matchingSubs.first;
        return b.copyWith(
          transcriptOriginal: sub.text,
          transcriptTranslated: sub.displayText,
        );
      }
    }).toList();

    state = state.copyWith(batches: updatedBatches);
    _saveProjectToDisk();
  }
}
