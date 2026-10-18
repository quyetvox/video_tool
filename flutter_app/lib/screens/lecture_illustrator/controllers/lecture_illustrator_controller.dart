import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../../core/providers.dart';
import '../../../../core/python_bridge.dart';
import '../../../../core/engine_resolver.dart';
import '../../../../models/app_config.dart';
import '../../../../models/subtitle_segment.dart';
import '../models/lecture_illustrator_model.dart';

final lectureIllustratorProvider = StateNotifierProvider<
    LectureIllustratorController,
    LectureIllustratorState>((ref) => LectureIllustratorController(ref));

class LectureIllustratorController
    extends StateNotifier<LectureIllustratorState> {
  final Ref _ref;
  Process? _activeProcess;
  List<SubtitleSegment> _fallbackSubtitles = [];

  LectureIllustratorController(this._ref)
      : super(const LectureIllustratorState());

  String get _workspacePath {
    final root = PythonBridge.resolveRootDir();
    final pName = (state.projectName != null && state.projectName!.isNotEmpty)
        ? state.projectName!
        : 'default';
    final vName = (state.videoName != null && state.videoName!.isNotEmpty)
        ? state.videoName!
        : (state.videoPath != null
            ? p.basename(state.videoPath!)
            : 'default_video');
    final safeName =
        p.withoutExtension(vName).replaceAll(RegExp(r'[^\w\-]+'), '_');
    return p.join(
        root, 'resources', pName, 'workspace', 'lecture_illustrator', safeName);
  }

  String get workspacePath => _workspacePath;
  LectureProjectConfig get currentConfig => state.config;
  LectureIllustratorState get currentState => state;
  String get _projectJsonPath => p.join(_workspacePath, 'lecture_project.json');

  void selectVideoFromProject({
    required String projectName,
    required String videoPath,
    required String videoName,
  }) {
    _fallbackSubtitles = [];
    state = state.copyWith(
      projectName: projectName,
      videoPath: videoPath,
      videoName: videoName,
      batches: [],
      selectedBatchId: null,
      metaTitle: '',
      metaDesc: '',
      metaHashtags: [],
      progress: 0.0,
      statusMessage: null,
      lastError: null,
    );
    final hasLoaded = _tryLoadExistingProject();
    if (!hasLoaded) {
      _tryLoadPipelineSubtitles();
      _syncFromGlobalConfig();
    }
  }

  void _tryLoadPipelineSubtitles() {
    try {
      final root = PythonBridge.resolveRootDir();
      final pName = state.projectName ?? 'default';
      final vName = state.videoName ??
          (state.videoPath != null ? p.basename(state.videoPath!) : '');
      final clean = p.withoutExtension(vName).replaceAll(RegExp(r'_vi$'), '');
      final jobId = 'job_${clean.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_')}';
      final jobDir = p.join(root, 'resources', pName, 'workspace', jobId);

      final timingFile = File(p.join(jobDir, 's08c_timing.json'));
      final subFile = File(p.join(jobDir, 's08_translation.json'));
      final asrFile = File(p.join(jobDir, 's05_asr.json'));

      File? targetFile;
      if (timingFile.existsSync()) {
        targetFile = timingFile;
      } else if (subFile.existsSync()) {
        targetFile = subFile;
      } else if (asrFile.existsSync()) {
        targetFile = asrFile;
      }

      if (targetFile != null) {
        final content = targetFile.readAsStringSync();
        final List<dynamic> data = jsonDecode(content);
        _fallbackSubtitles = data
            .asMap()
            .entries
            .map((e) => SubtitleSegment.fromJson(e.value, e.key))
            .toList();
      }
    } catch (_) {
      _fallbackSubtitles = [];
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
        } else if (vLow.contains('banmai') ||
            vLow.contains('ban_mai') ||
            vLow == 'vi') {
          voice = 'ban_mai';
        } else {
          voice = appCfg.ttsVoice;
        }
      }

      final cur = state.config;
      final updated = cur.copyWith(
        targetLang:
            appCfg.targetLang.isNotEmpty ? appCfg.targetLang : cur.targetLang,
        secondaryLang: appCfg.secondaryLang.isNotEmpty
            ? appCfg.secondaryLang
            : cur.secondaryLang,
        pronounMode: appCfg.pronounMode.isNotEmpty
            ? appCfg.pronounMode
            : cur.pronounMode,
        ttsVoice: voice,
        ttsSpeed: appCfg.ttsSpeed > 0 ? appCfg.ttsSpeed : cur.ttsSpeed,
        bgmVolume: appCfg.musicVol >= 0 ? appCfg.musicVol : cur.bgmVolume,
        voiceVolume: appCfg.ttsVol > 0 ? appCfg.ttsVol : cur.voiceVolume,
        burnSubtitles: appCfg.showSubtitle,
        subtitleMode: appCfg.subtitleSecondaryShow ? 'bilingual' : 'single',
        subtitleSecondaryShow: appCfg.subtitleSecondaryShow,
        subtitleOrder: appCfg.subtitleOrder.isNotEmpty
            ? appCfg.subtitleOrder
            : cur.subtitleOrder,
        fontName: appCfg.fontName.isNotEmpty ? appCfg.fontName : cur.fontName,
        secondaryFontName: appCfg.subtitleSecondaryFontName.isNotEmpty
            ? appCfg.subtitleSecondaryFontName
            : cur.secondaryFontName,
        fontSize: appCfg.fontSize.isNotEmpty ? appCfg.fontSize : cur.fontSize,
        fontColor:
            appCfg.fontColor.isNotEmpty ? appCfg.fontColor : cur.fontColor,
        outlineColor: appCfg.outlineColor.isNotEmpty
            ? appCfg.outlineColor
            : cur.outlineColor,
        secondaryFontColor: appCfg.subtitleSecondaryFontColor.isNotEmpty
            ? appCfg.subtitleSecondaryFontColor
            : cur.secondaryFontColor,
        secondaryScale: appCfg.subtitleSecondaryFontScale > 0
            ? appCfg.subtitleSecondaryFontScale
            : cur.secondaryScale,
        videoBitrate: appCfg.videoBitrate.isNotEmpty
            ? appCfg.videoBitrate
            : cur.videoBitrate,
        watermarkEnabled: appCfg.watermarkEnabled,
        watermarkPath: appCfg.watermarkImage.isNotEmpty
            ? appCfg.watermarkImage
            : cur.watermarkPath,
        enableInpaint: appCfg.inpaintShowBox,
        inpaintEngine: appCfg.inpaintEngine.isNotEmpty
            ? appCfg.inpaintEngine
            : cur.inpaintEngine,
        inpaintBlurRadius: appCfg.inpaintBlurRadius > 0
            ? appCfg.inpaintBlurRadius
            : cur.inpaintBlurRadius,
        boxBgColor:
            appCfg.boxBgColor.isNotEmpty ? appCfg.boxBgColor : cur.boxBgColor,
        boxOpacity:
            appCfg.boxBgOpacity > 0 ? appCfg.boxBgOpacity : cur.boxOpacity,
        inpaintMethod: appCfg.inpaintMethod.isNotEmpty
            ? appCfg.inpaintMethod
            : cur.inpaintMethod,
        inpaintRegion:
            appCfg.inpaintRegion != null && appCfg.inpaintRegion!.length == 4
                ? appCfg.inpaintRegion!
                : cur.inpaintRegion,
        subtitleRegion:
            appCfg.subtitleRegion != null && appCfg.subtitleRegion!.length == 4
                ? appCfg.subtitleRegion!
                : cur.subtitleRegion,
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
        final rawMeta =
            jsonDecode(metaFile.readAsStringSync()) as Map<String, dynamic>;
        final t = rawMeta['title']?.toString() ?? '';
        final d = rawMeta['description']?.toString() ?? '';
        final h =
            (rawMeta['hashtags'] as List?)?.map((e) => e.toString()).toList() ??
                [];
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
    final resolved =
        EngineResolver.resolveScript('lecture_illustrator_orchestrator.py');
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
    final safeName = p
        .withoutExtension(state.videoName!)
        .replaceAll(RegExp(r'[^\w\-]+'), '_');
    final outPath = p.join(
        root, 'resources', pName, 'output', '${safeName}_illustrated.mp4');
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
      '--mode',
      'analyze',
      '--input',
      state.videoPath!,
      '--workspace',
      _workspacePath,
      '--project-name',
      state.projectName ?? 'default',
      '--project-file',
      _projectJsonPath,
      '--source-lang',
      state.config.sourceLang,
      '--target-lang',
      state.config.targetLang,
      '--secondary-lang',
      state.config.secondaryLang,
      '--pronoun-mode',
      state.config.pronounMode,
      '--voice-mode',
      state.config.voiceMode,
      '--tts-voice',
      state.config.ttsVoice,
      '--tts-speed',
      state.config.ttsSpeed.toString(),
      '--bgm-volume',
      state.config.bgmVolume.toString(),
      '--voice-volume',
      state.config.voiceVolume.toString(),
      '--burn-subtitles',
      state.config.burnSubtitles.toString(),
      '--subtitle-mode',
      state.config.subtitleMode,
      '--subtitle-secondary-show',
      state.config.subtitleSecondaryShow.toString(),
      '--subtitle-order',
      state.config.subtitleOrder,
      '--font-name',
      state.config.fontName,
      if (state.config.secondaryFontName != null &&
          state.config.secondaryFontName!.isNotEmpty) ...[
        '--secondary-font-name',
        state.config.secondaryFontName!,
      ],
      '--font-size',
      state.config.fontSize,
      '--font-color',
      state.config.fontColor,
      '--outline-color',
      state.config.outlineColor,
      '--secondary-font-color',
      state.config.secondaryFontColor,
      '--secondary-scale',
      state.config.secondaryScale.toString(),
      '--video-bitrate',
      state.config.videoBitrate,
      '--watermark-enabled',
      state.config.watermarkEnabled.toString(),
      if (state.config.watermarkPath.isNotEmpty) ...[
        '--watermark-path',
        state.config.watermarkPath,
      ],
      '--enable-inpaint',
      state.config.enableInpaint.toString(),
      '--inpaint-engine',
      state.config.inpaintEngine,
      '--inpaint-blur-radius',
      state.config.inpaintBlurRadius.toString(),
      '--box-bg-color',
      state.config.boxBgColor,
      '--box-opacity',
      state.config.boxOpacity.toString(),
      '--inpaint-method',
      state.config.inpaintMethod,
      if (state.config.subtitleRegion != null &&
          state.config.subtitleRegion!.length == 4) ...[
        '--subtitle-region',
        state.config.subtitleRegion!.join(','),
      ],
      '--layout-preset',
      state.config.visualLayoutPreset,
      '--aspect-ratio',
      state.config.aspectRatio,
      '--ai-authored',
      state.config.aiAuthored.toString(),
      if (state.config.htmlAuthorModel != null &&
          state.config.htmlAuthorModel!.isNotEmpty) ...[
        '--html-author-model',
        state.config.htmlAuthorModel!,
      ],
      if (state.config.htmlAuthorBaseUrl != null &&
          state.config.htmlAuthorBaseUrl!.isNotEmpty) ...[
        '--html-author-base-url',
        state.config.htmlAuthorBaseUrl!,
      ],
      if (state.config.htmlAuthorApiKey != null &&
          state.config.htmlAuthorApiKey!.isNotEmpty) ...[
        '--html-author-api-key',
        state.config.htmlAuthorApiKey!,
      ],
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
      final env =
          PythonBridge.buildEnvironment(rootDir: rootDir, pythonBin: pythonBin);
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
    final safeName =
        p.withoutExtension(vName).replaceAll(RegExp(r'[^\w\-]+'), '_');
    final outVideoPath = p.join(
        root, 'resources', pName, 'output', '${safeName}_illustrated.mp4');

    final globalConfig = _ref.read(configProvider);
    syncFromConfig(globalConfig);

    final args = [
      scriptPath,
      '--mode',
      'render',
      '--project-file',
      _projectJsonPath,
      '--workspace',
      _workspacePath,
      '--output',
      outVideoPath,
      if (state.config.htmlAuthorModel != null &&
          state.config.htmlAuthorModel!.isNotEmpty) ...[
        '--html-author-model',
        state.config.htmlAuthorModel!,
      ],
      if (state.config.htmlAuthorBaseUrl != null &&
          state.config.htmlAuthorBaseUrl!.isNotEmpty) ...[
        '--html-author-base-url',
        state.config.htmlAuthorBaseUrl!,
      ],
      if (state.config.htmlAuthorApiKey != null &&
          state.config.htmlAuthorApiKey!.isNotEmpty) ...[
        '--html-author-api-key',
        state.config.htmlAuthorApiKey!,
      ],
      if (globalConfig.translatorApiKey.isNotEmpty) ...[
        '--api-key',
        globalConfig.translatorApiKey,
      ],
      if (globalConfig.translatorModel.isNotEmpty) ...[
        '--model',
        globalConfig.translatorModel,
      ],
      if (globalConfig.translatorBaseUrl.isNotEmpty) ...[
        '--base-url',
        globalConfig.translatorBaseUrl,
      ],
    ];

    try {
      final env =
          PythonBridge.buildEnvironment(rootDir: root, pythonBin: pythonBin);
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

  void toggleSelectBatch(String batchId) {
    final cur = Set<String>.from(state.selectedBatchIds);
    if (cur.contains(batchId)) {
      cur.remove(batchId);
    } else {
      cur.add(batchId);
    }
    state = state.copyWith(selectedBatchIds: cur);
  }

  void selectAllBatches(bool selectAll) {
    if (selectAll) {
      final allIds = state.batches.map((b) => b.id).toSet();
      state = state.copyWith(selectedBatchIds: allIds);
    } else {
      state = state.copyWith(selectedBatchIds: const {});
    }
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

  @visibleForTesting
  void setBatchesForTesting(List<LectureBatch> batches) {
    state = state.copyWith(batches: batches);
  }

  // --- CONFIG SETTERS ---

  void updateConfig(
      LectureProjectConfig Function(LectureProjectConfig) updater) {
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

  void setAspectRatio(String ratio) {
    updateConfig((c) => c.copyWith(aspectRatio: ratio));
  }

  void setAiAuthored(bool enabled) {
    updateConfig((c) => c.copyWith(aiAuthored: enabled));
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
        final a16k = File(p.join(_workspacePath, 'lecture_audio_16k.wav'));
        if (a16k.existsSync()) a16k.deleteSync();
      }

      if (clearScenes) {
        final scenesDir = Directory(p.join(_workspacePath, 'scenes'));
        if (scenesDir.existsSync()) {
          scenesDir.deleteSync(recursive: true);
        }
        final asrFile = File(p.join(_workspacePath, 's05_asr.json'));
        if (asrFile.existsSync()) asrFile.deleteSync();
        final metaFile = File(p.join(_workspacePath, 'lecture_metadata.json'));
        if (metaFile.existsSync()) metaFile.deleteSync();
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

  /// Xóa toàn bộ cache và bắt đầu phân tích lại toàn bộ bài giảng từ đầu
  Future<void> reanalyzeWithCleanCache() async {
    await clearProjectCache(clearAll: true);
    await startAnalysis();
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
    if (state.batches.isEmpty && _fallbackSubtitles.isNotEmpty) {
      return _fallbackSubtitles;
    }
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
            textVi:
                s['translated']?.toString() ?? s['text_vi']?.toString() ?? '',
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
          transcriptTranslated: fullTranslated.isNotEmpty
              ? fullTranslated
              : b.transcriptTranslated,
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

  /// Tái tạo cảnh HTML cho 1 batch đơn lẻ thông qua AI và render lại video clip
  Future<bool> reauthorBatchWithAi({
    required String batchId,
    required String feedback,
  }) async {
    final vPath = state.videoPath;
    if (vPath == null || vPath.isEmpty) return false;

    state = state.copyWith(
        statusMessage: 'AI đang thiết kế lại cảnh cho $batchId...',
        lastError: null);
    PythonBridge.addLog('lecture_illustrator', 'info',
        'Bắt đầu gửi lệnh tái tạo AI cho $batchId với yêu cầu: $feedback');

    final pythonBin = PythonBridge.resolvePythonBin();
    final scriptPath = _resolveOrchestratorScript();
    final root = PythonBridge.resolveRootDir();
    final globalConfig = _ref.read(configProvider);
    syncFromConfig(globalConfig);

    final List<String> args = [
      scriptPath,
      '--mode',
      'reauthor_batch',
      '--project-file',
      _projectJsonPath,
      '--batch-id',
      batchId,
      '--feedback',
      feedback,
      if (state.config.htmlAuthorModel != null &&
          state.config.htmlAuthorModel!.isNotEmpty) ...[
        '--html-author-model',
        state.config.htmlAuthorModel!,
      ],
      if (state.config.htmlAuthorBaseUrl != null &&
          state.config.htmlAuthorBaseUrl!.isNotEmpty) ...[
        '--html-author-base-url',
        state.config.htmlAuthorBaseUrl!,
      ],
      if (state.config.htmlAuthorApiKey != null &&
          state.config.htmlAuthorApiKey!.isNotEmpty) ...[
        '--html-author-api-key',
        state.config.htmlAuthorApiKey!,
      ],
      if (globalConfig.translatorType.isNotEmpty) ...[
        '--translator-type',
        globalConfig.translatorType,
      ],
      if (globalConfig.translatorApiKey.isNotEmpty) ...[
        '--api-key',
        globalConfig.translatorApiKey,
      ],
      if (globalConfig.translatorModel.isNotEmpty) ...[
        '--model',
        globalConfig.translatorModel,
      ],
      if (globalConfig.translatorBaseUrl.isNotEmpty) ...[
        '--base-url',
        globalConfig.translatorBaseUrl,
      ],
    ];

    String? lastFailureReason;

    try {
      final env =
          PythonBridge.buildEnvironment(rootDir: root, pythonBin: pythonBin);
      final process = await Process.start(
        pythonBin,
        args,
        workingDirectory: root,
        environment: env,
      );

      process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        PythonBridge.addLog('lecture_illustrator', 'stdout', line);
        if (line.trim().startsWith('{') && line.trim().endsWith('}')) {
          try {
            final obj = jsonDecode(line.trim());
            if (obj['type'] == 'log') {
              PythonBridge.addLog('lecture_illustrator', obj['level'] ?? 'info',
                  obj['message'] ?? '');
              if (obj['level'] == 'error' || obj['level'] == 'warn') {
                lastFailureReason = obj['message']?.toString();
              }
            } else if (obj['type'] == 'result' && obj['status'] == 'failed') {
              final errs = obj['errors'] as List<dynamic>?;
              if (errs != null && errs.isNotEmpty) {
                lastFailureReason = errs.first.toString();
              }
            }
          } catch (_) {}
        }
      });

      process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((err) {
        PythonBridge.addLog('lecture_illustrator', 'stderr', err);
      });

      final exitCode = await process.exitCode;
      if (exitCode == 0) {
        _tryLoadExistingProject();
        state = state.copyWith(
            statusMessage: 'Đã hoàn tất tái tạo AI cho $batchId!',
            lastError: null);
        return true;
      } else {
        final reason = lastFailureReason ??
            'Mã lỗi exit code: $exitCode (vui lòng kiểm tra API Key hoặc Console)';
        state = state.copyWith(lastError: reason);
        return false;
      }
    } catch (e) {
      state = state.copyWith(lastError: 'Lỗi tiến trình: $e');
      return false;
    }
  }

  /// Gộp 1 batch với batch tiếp theo:
  /// - Tự động vá các câu bị cắt ngang dở dang (dấu phẩy, liên từ)
  /// - Tính toán lại timeline chuẩn xác (step_starts, scene_duration, start_sec, end_sec)
  /// - Gọi AI thiết kế lại HTML cho toàn bộ cụm tri thức mới gộp và render lại video clip xem trước
  Future<bool> mergeBatchWithNext({
    required String batchId,
    String? mergeWithId,
    String feedback = 'Gộp hai phân cảnh thành một cụm tri thức hoàn chỉnh liền mạch.',
  }) async {
    final vPath = state.videoPath;
    if (vPath == null || vPath.isEmpty) return false;

    state = state.copyWith(
        statusMessage: 'Đang gộp phân cảnh $batchId với phân cảnh tiếp theo...',
        lastError: null);
    PythonBridge.addLog('lecture_illustrator', 'info',
        'Bắt đầu gửi lệnh gộp phân cảnh cho $batchId${mergeWithId != null ? ' với $mergeWithId' : ''}');

    final pythonBin = PythonBridge.resolvePythonBin();
    final scriptPath = _resolveOrchestratorScript();
    final root = PythonBridge.resolveRootDir();
    final globalConfig = _ref.read(configProvider);
    syncFromConfig(globalConfig);

    final List<String> args = [
      scriptPath,
      '--mode',
      'merge_batches',
      '--project-file',
      _projectJsonPath,
      '--batch-id',
      batchId,
      if (mergeWithId != null && mergeWithId.isNotEmpty) ...[
        '--merge-with-id',
        mergeWithId,
      ],
      '--feedback',
      feedback,
      if (state.config.htmlAuthorModel != null &&
          state.config.htmlAuthorModel!.isNotEmpty) ...[
        '--html-author-model',
        state.config.htmlAuthorModel!,
      ],
      if (state.config.htmlAuthorBaseUrl != null &&
          state.config.htmlAuthorBaseUrl!.isNotEmpty) ...[
        '--html-author-base-url',
        state.config.htmlAuthorBaseUrl!,
      ],
      if (state.config.htmlAuthorApiKey != null &&
          state.config.htmlAuthorApiKey!.isNotEmpty) ...[
        '--html-author-api-key',
        state.config.htmlAuthorApiKey!,
      ],
      if (globalConfig.translatorType.isNotEmpty) ...[
        '--translator-type',
        globalConfig.translatorType,
      ],
      if (globalConfig.translatorApiKey.isNotEmpty) ...[
        '--api-key',
        globalConfig.translatorApiKey,
      ],
      if (globalConfig.translatorModel.isNotEmpty) ...[
        '--model',
        globalConfig.translatorModel,
      ],
      if (globalConfig.translatorBaseUrl.isNotEmpty) ...[
        '--base-url',
        globalConfig.translatorBaseUrl,
      ],
    ];

    String? lastFailureReason;

    try {
      final env =
          PythonBridge.buildEnvironment(rootDir: root, pythonBin: pythonBin);
      final process = await Process.start(
        pythonBin,
        args,
        workingDirectory: root,
        environment: env,
      );

      process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        PythonBridge.addLog('lecture_illustrator', 'stdout', line);
        if (line.trim().startsWith('{') && line.trim().endsWith('}')) {
          try {
            final obj = jsonDecode(line.trim());
            if (obj['type'] == 'log') {
              PythonBridge.addLog('lecture_illustrator', obj['level'] ?? 'info',
                  obj['message'] ?? '');
              if (obj['level'] == 'error' || obj['level'] == 'warn') {
                lastFailureReason = obj['message']?.toString();
              }
            } else if (obj['type'] == 'result' && obj['status'] == 'failed') {
              final errs = obj['errors'] as List<dynamic>?;
              if (errs != null && errs.isNotEmpty) {
                lastFailureReason = errs.first.toString();
              }
            }
          } catch (_) {}
        }
      });

      process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((err) {
        PythonBridge.addLog('lecture_illustrator', 'stderr', err);
      });

      final exitCode = await process.exitCode;
      if (exitCode == 0) {
        _tryLoadExistingProject();
        state = state.copyWith(
            statusMessage: 'Đã hoàn tất gộp phân cảnh $batchId!',
            lastError: null);
        return true;
      } else {
        final reason = lastFailureReason ??
            'Mã lỗi exit code: $exitCode (vui lòng kiểm tra Console)';
        state = state.copyWith(lastError: reason);
        return false;
      }
    } catch (e) {
      state = state.copyWith(lastError: 'Lỗi tiến trình gộp batch: $e');
      return false;
    }
  }

  /// Import file HTML ngoài (từ ChatGPT / Gemini / Claude) vào 1 batch,
  /// tự động cân chỉnh tốc độ và render lại video clip xem trước khớp TTS + Sub.
  Future<bool> importBatchHtml({
    required String batchId,
    required String htmlFilePath,
  }) async {
    final vPath = state.videoPath;
    if (vPath == null || vPath.isEmpty) return false;

    state = state.copyWith(
        statusMessage:
            'Đang cân chỉnh thời gian & render cảnh HTML cho $batchId...',
        lastError: null);
    PythonBridge.addLog('lecture_illustrator', 'info',
        'Import HTML ngoài cho $batchId từ: $htmlFilePath');

    final pythonBin = PythonBridge.resolvePythonBin();
    final scriptPath = _resolveOrchestratorScript();
    final root = PythonBridge.resolveRootDir();

    final List<String> args = [
      scriptPath,
      '--mode',
      'import_batch_html',
      '--project-file',
      _projectJsonPath,
      '--batch-id',
      batchId,
      '--html-file',
      htmlFilePath,
    ];

    String? lastFailureReason;

    try {
      final env =
          PythonBridge.buildEnvironment(rootDir: root, pythonBin: pythonBin);
      final process = await Process.start(
        pythonBin,
        args,
        workingDirectory: root,
        environment: env,
      );

      process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        PythonBridge.addLog('lecture_illustrator', 'stdout', line);
        if (line.trim().startsWith('{') && line.trim().endsWith('}')) {
          try {
            final obj = jsonDecode(line.trim());
            if (obj['type'] == 'log') {
              PythonBridge.addLog('lecture_illustrator', obj['level'] ?? 'info',
                  obj['message'] ?? '');
              if (obj['level'] == 'error' || obj['level'] == 'warn') {
                lastFailureReason = obj['message']?.toString();
              }
            } else if (obj['type'] == 'result' && obj['status'] == 'failed') {
              final errs = obj['errors'] as List<dynamic>?;
              if (errs != null && errs.isNotEmpty) {
                lastFailureReason = errs.first.toString();
              }
            }
          } catch (_) {}
        }
      });

      process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((err) {
        PythonBridge.addLog('lecture_illustrator', 'stderr', err);
      });

      final exitCode = await process.exitCode;
      if (exitCode == 0) {
        _tryLoadExistingProject();
        state = state.copyWith(
            statusMessage:
                'Đã nhập và cân chỉnh cảnh HTML cho $batchId thành công!',
            lastError: null);
        return true;
      } else {
        final reason = lastFailureReason ??
            'Mã lỗi exit code: $exitCode (không thể import HTML)';
        state = state.copyWith(lastError: reason);
        return false;
      }
    } catch (e) {
      state = state.copyWith(lastError: 'Lỗi tiến trình import HTML: $e');
      return false;
    }
  }

  /// Nhập mã HTML trực tiếp từ chuỗi văn bản (dán code) cho một batch
  Future<bool> importBatchHtmlCode({
    required String batchId,
    required String htmlContent,
  }) async {
    final vPath = state.videoPath;
    if (vPath == null || vPath.isEmpty) return false;

    try {
      final scenesDir = Directory(p.join(_workspacePath, 'scenes'));
      if (!scenesDir.existsSync()) {
        scenesDir.createSync(recursive: true);
      }
      final tempHtml = File(p.join(scenesDir.path, '$batchId.html'));
      tempHtml.writeAsStringSync(htmlContent.trim());

      return await importBatchHtml(
        batchId: batchId,
        htmlFilePath: tempHtml.path,
      );
    } catch (e) {
      state = state.copyWith(lastError: 'Lỗi ghi mã HTML: $e');
      return false;
    }
  }

  /// Định dạng khối thông tin input của một phân đoạn (Scene/Batch)
  String formatBatchInputBlock(LectureBatch batch, {int? index}) {
    final isPortrait = state.config.aspectRatio == '9:16';
    final aspectDesc =
        isPortrait ? '9:16 Portrait (1080x1920)' : '16:9 Landscape (1920x1080)';
    final dur = batch.sceneDuration > 0
        ? batch.sceneDuration
        : (batch.endSec - batch.startSec);
    final durText = '${dur.toStringAsFixed(2)}s';

    final title = (batch.scene['title'] != null &&
            batch.scene['title'].toString().isNotEmpty)
        ? batch.scene['title'].toString()
        : (state.projectName ?? 'Bài Giảng Chuyên Đề');

    final stepsBuffer = StringBuffer();
    final sentences = batch.sentences;
    final stepStarts = batch.stepStarts;

    if (sentences.isNotEmpty) {
      for (int i = 0; i < sentences.length; i++) {
        final sMap = sentences[i];
        final st = i < stepStarts.length ? stepStarts[i] : (i * 2.0);
        final tText = sMap['text']?.toString().trim() ?? '';
        final oText = sMap['text_orig']?.toString().trim() ?? '';
        final txt = tText.isNotEmpty
            ? tText
            : (oText.isNotEmpty ? oText : 'Nội dung ý ${i + 1}');
        stepsBuffer.writeln(
            '  - Ý ${i + 1} (bắt đầu tại giây t=${st.toStringAsFixed(2)}s): "$txt"');
      }
    } else {
      final txt = batch.transcriptTranslated.isNotEmpty
          ? batch.transcriptTranslated
          : batch.transcriptOriginal;
      stepsBuffer.writeln('  - Ý 1 (bắt đầu tại giây t=0.00s): "$txt"');
    }

    final header = index != null
        ? '--- BATCH $index (${batch.id}) ---\nBATCH: #$index (${batch.id})'
        : 'BATCH: ${batch.id}';

    return '''$header
TITLE: $title
ASPECT RATIO: $aspectDesc
SCENE DURATION: $durText
SENTENCES & TIMESTAMPS:
${stepsBuffer.toString().trimRight()}''';
  }

  /// Trích xuất toàn bộ khối dữ liệu phân đoạn của tất cả các batch để sao chép vào Clipboard
  String generateAllBatchesInputData() {
    if (state.batches.isEmpty) return '';
    final buffer = StringBuffer();
    for (int i = 0; i < state.batches.length; i++) {
      final batch = state.batches[i];
      buffer.writeln(formatBatchInputBlock(batch, index: i + 1));
      if (i < state.batches.length - 1) {
        buffer.writeln();
      }
    }
    return buffer.toString().trimRight();
  }

  /// Tạo nội dung Master Prompt đã điền sẵn thông tin ngữ cảnh của batch để sao chép
  String generatePromptForBatch(LectureBatch batch) {
    final root = PythonBridge.resolveRootDir();
    final promptFile = File(p.join(root, 'py_engine', 'lecture_illustrator',
        'prompts', 'master_handdrawn_animation_prompt.md'));
    String template = '';
    if (promptFile.existsSync()) {
      try {
        template = promptFile.readAsStringSync();
      } catch (_) {}
    }

    final isPortrait = state.config.aspectRatio == '9:16';
    final aspectDesc =
        isPortrait ? '9:16 Portrait (1080x1920)' : '16:9 Landscape (1920x1080)';
    final dur = batch.sceneDuration > 0
        ? batch.sceneDuration
        : (batch.endSec - batch.startSec);
    final durText = '${dur.toStringAsFixed(2)}s';

    final title = (batch.scene['title'] != null &&
            batch.scene['title'].toString().isNotEmpty)
        ? batch.scene['title'].toString()
        : (state.projectName ?? 'Bài Giảng Chuyên Đề');

    final stepsBuffer = StringBuffer();
    final sentences = batch.sentences;
    final stepStarts = batch.stepStarts;

    if (sentences.isNotEmpty) {
      for (int i = 0; i < sentences.length; i++) {
        final sMap = sentences[i];
        final st = i < stepStarts.length ? stepStarts[i] : (i * 2.0);
        final tText = sMap['text']?.toString().trim() ?? '';
        final oText = sMap['text_orig']?.toString().trim() ?? '';
        final txt = tText.isNotEmpty
            ? tText
            : (oText.isNotEmpty ? oText : 'Nội dung ý ${i + 1}');
        stepsBuffer.writeln(
            '  - Ý ${i + 1} (bắt đầu tại giây t=${st.toStringAsFixed(2)}s): "$txt"');
      }
    } else {
      final txt = batch.transcriptTranslated.isNotEmpty
          ? batch.transcriptTranslated
          : batch.transcriptOriginal;
      stepsBuffer.writeln('  - Ý 1 (bắt đầu tại giây t=0.00s): "$txt"');
    }

    final inputDataSection = '''
DỮ LIỆU ĐẦU VÀO CHO SCENE NÀY (${batch.id}):
--------------------------------------------------
TITLE: $title
ASPECT RATIO: $aspectDesc
SCENE DURATION: $durText
SENTENCES & TIMESTAMPS:
${stepsBuffer.toString().trimRight()}
--------------------------------------------------''';

    if (template.isNotEmpty) {
      return '''$inputDataSection

$template
''';
    } else {
      return '''$inputDataSection
YÊU CẦU: Hãy tạo một trang HTML SVG vẽ tay tự chứa 100% (không cần thư viện ngoài), nền giấy kem #f4efe3, viền mực #26323d, điểm nhấn đỏ #b5533c, font PatrickHand.
Có hàm window.__renderAt(t, stepStarts) tua theo các mốc giây trên và vòng lặp tự động autoPlayLoop.''';
    }
  }

  /// Thêm một phân cảnh mới vào kịch bản, tự động gọi TTS đo thời lượng và dồn timeline
  Future<bool> addNewBatch({required String text, int? insertIndex}) async {
    final vPath = state.videoPath;
    if ((vPath == null || vPath.isEmpty) && !File(_projectJsonPath).existsSync()) {
      state = state.copyWith(lastError: 'Không tìm thấy file kịch bản lecture_project.json.');
      return false;
    }

    state = state.copyWith(statusMessage: 'Đang tạo phân cảnh mới & tổng hợp giọng đọc...', lastError: null);
    final pythonBin = PythonBridge.resolvePythonBin();
    final scriptPath = _resolveOrchestratorScript();
    final root = PythonBridge.resolveRootDir();

    final globalConfig = _ref.read(configProvider);
    syncFromConfig(globalConfig);
    _saveProjectToDisk();

    final List<String> args = [
      scriptPath,
      '--mode',
      'sync_batch_audio',
      '--project-file',
      _projectJsonPath,
      '--action',
      'create',
      '--text',
      text,
      if (insertIndex != null) ...['--insert-at', insertIndex.toString()],
      if (state.config.ttsVoice.isNotEmpty) ...['--tts-voice', state.config.ttsVoice],
      '--tts-speed',
      state.config.ttsSpeed.toString(),
      if (state.config.targetLang.isNotEmpty) ...['--target-lang', state.config.targetLang],
      if (state.config.secondaryLang.isNotEmpty) ...['--secondary-lang', state.config.secondaryLang],
      if (globalConfig.translatorApiKey.isNotEmpty) ...['--api-key', globalConfig.translatorApiKey],
      if (globalConfig.translatorModel.isNotEmpty) ...['--model', globalConfig.translatorModel],
      if (globalConfig.translatorBaseUrl.isNotEmpty) ...['--base-url', globalConfig.translatorBaseUrl],
    ];

    String? lastFailureReason;
    try {
      final env = PythonBridge.buildEnvironment(rootDir: root, pythonBin: pythonBin);
      final process = await Process.start(pythonBin, args, workingDirectory: root, environment: env);

      process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        PythonBridge.addLog('lecture_illustrator', 'stdout', line);
        if (line.trim().startsWith('{') && line.trim().endsWith('}')) {
          try {
            final obj = jsonDecode(line.trim());
            if (obj['type'] == 'log') {
              PythonBridge.addLog('lecture_illustrator', obj['level'] ?? 'info', obj['message'] ?? '');
              if (obj['level'] == 'error' || obj['level'] == 'warn') {
                lastFailureReason = obj['message']?.toString();
              }
            } else if (obj['type'] == 'result' && obj['status'] == 'failed') {
              final errs = obj['errors'] as List<dynamic>?;
              if (errs != null && errs.isNotEmpty) {
                lastFailureReason = errs.first.toString();
              }
            }
          } catch (_) {}
        }
      });

      process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        PythonBridge.addLog('lecture_illustrator', 'stderr', line);
        if (lastFailureReason == null && line.trim().isNotEmpty) {
          lastFailureReason = line.trim();
        }
      });

      final exitCode = await process.exitCode;
      if (exitCode == 0) {
        _tryLoadExistingProject();
        state = state.copyWith(statusMessage: 'Đã thêm phân cảnh mới thành công!', lastError: null);
        return true;
      }
      state = state.copyWith(
        lastError: lastFailureReason ?? 'Tạo phân cảnh thất bại (Exit code: $exitCode)',
      );
      return false;
    } catch (e) {
      state = state.copyWith(lastError: 'Lỗi tạo phân cảnh: $e');
      return false;
    }
  }

  /// Đồng bộ nội dung thoại mới và gọi TTS tạo lại audio, cập nhật lại timeline
  Future<bool> syncBatchAudioAndText(String batchId, String newText) async {
    final vPath = state.videoPath;
    if ((vPath == null || vPath.isEmpty) && !File(_projectJsonPath).existsSync()) {
      state = state.copyWith(lastError: 'Không tìm thấy file kịch bản lecture_project.json.');
      return false;
    }

    state = state.copyWith(statusMessage: 'Đang cập nhật thoại & giọng đọc cho $batchId...', lastError: null);
    final pythonBin = PythonBridge.resolvePythonBin();
    final scriptPath = _resolveOrchestratorScript();
    final root = PythonBridge.resolveRootDir();

    final globalConfig = _ref.read(configProvider);
    syncFromConfig(globalConfig);
    _saveProjectToDisk();

    final List<String> args = [
      scriptPath,
      '--mode',
      'sync_batch_audio',
      '--project-file',
      _projectJsonPath,
      '--action',
      'update',
      '--batch-id',
      batchId,
      '--text',
      newText,
      if (state.config.ttsVoice.isNotEmpty) ...['--tts-voice', state.config.ttsVoice],
      '--tts-speed',
      state.config.ttsSpeed.toString(),
      if (state.config.targetLang.isNotEmpty) ...['--target-lang', state.config.targetLang],
      if (state.config.secondaryLang.isNotEmpty) ...['--secondary-lang', state.config.secondaryLang],
      if (globalConfig.translatorApiKey.isNotEmpty) ...['--api-key', globalConfig.translatorApiKey],
      if (globalConfig.translatorModel.isNotEmpty) ...['--model', globalConfig.translatorModel],
      if (globalConfig.translatorBaseUrl.isNotEmpty) ...['--base-url', globalConfig.translatorBaseUrl],
    ];

    String? lastFailureReason;
    try {
      final env = PythonBridge.buildEnvironment(rootDir: root, pythonBin: pythonBin);
      final process = await Process.start(pythonBin, args, workingDirectory: root, environment: env);

      process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        PythonBridge.addLog('lecture_illustrator', 'stdout', line);
        if (line.trim().startsWith('{') && line.trim().endsWith('}')) {
          try {
            final obj = jsonDecode(line.trim());
            if (obj['type'] == 'log') {
              PythonBridge.addLog('lecture_illustrator', obj['level'] ?? 'info', obj['message'] ?? '');
              if (obj['level'] == 'error' || obj['level'] == 'warn') {
                lastFailureReason = obj['message']?.toString();
              }
            } else if (obj['type'] == 'result' && obj['status'] == 'failed') {
              final errs = obj['errors'] as List<dynamic>?;
              if (errs != null && errs.isNotEmpty) {
                lastFailureReason = errs.first.toString();
              }
            }
          } catch (_) {}
        }
      });

      process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        PythonBridge.addLog('lecture_illustrator', 'stderr', line);
        if (lastFailureReason == null && line.trim().isNotEmpty) {
          lastFailureReason = line.trim();
        }
      });

      final exitCode = await process.exitCode;
      if (exitCode == 0) {
        _tryLoadExistingProject();
        state = state.copyWith(statusMessage: 'Đã đồng bộ thoại & giọng đọc cho $batchId!', lastError: null);
        return true;
      }
      state = state.copyWith(
        lastError: lastFailureReason ?? 'Đồng bộ thất bại (Exit code: $exitCode)',
      );
      return false;
    } catch (e) {
      state = state.copyWith(lastError: 'Lỗi đồng bộ giọng đọc: $e');
      return false;
    }
  }

  /// Xóa một phân cảnh khỏi kịch bản và dồn lại timeline
  Future<bool> deleteBatch(String batchId) async {
    final vPath = state.videoPath;
    if ((vPath == null || vPath.isEmpty) && !File(_projectJsonPath).existsSync()) {
      state = state.copyWith(lastError: 'Không tìm thấy file kịch bản lecture_project.json.');
      return false;
    }

    if (state.batches.length <= 1) {
      state = state.copyWith(lastError: 'Không thể xóa phân cảnh duy nhất còn lại của bài giảng.');
      return false;
    }

    state = state.copyWith(statusMessage: 'Đang xóa phân cảnh $batchId...', lastError: null);
    final pythonBin = PythonBridge.resolvePythonBin();
    final scriptPath = _resolveOrchestratorScript();
    final root = PythonBridge.resolveRootDir();

    final List<String> args = [
      scriptPath,
      '--mode',
      'sync_batch_audio',
      '--project-file',
      _projectJsonPath,
      '--action',
      'delete',
      '--batch-id',
      batchId,
    ];

    String? lastFailureReason;
    try {
      final env = PythonBridge.buildEnvironment(rootDir: root, pythonBin: pythonBin);
      final process = await Process.start(pythonBin, args, workingDirectory: root, environment: env);

      process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        PythonBridge.addLog('lecture_illustrator', 'stdout', line);
        if (line.trim().startsWith('{') && line.trim().endsWith('}')) {
          try {
            final obj = jsonDecode(line.trim());
            if (obj['type'] == 'log') {
              PythonBridge.addLog('lecture_illustrator', obj['level'] ?? 'info', obj['message'] ?? '');
              if (obj['level'] == 'error' || obj['level'] == 'warn') {
                lastFailureReason = obj['message']?.toString();
              }
            } else if (obj['type'] == 'result' && obj['status'] == 'failed') {
              final errs = obj['errors'] as List<dynamic>?;
              if (errs != null && errs.isNotEmpty) {
                lastFailureReason = errs.first.toString();
              }
            }
          } catch (_) {}
        }
      });

      process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        PythonBridge.addLog('lecture_illustrator', 'stderr', line);
        if (lastFailureReason == null && line.trim().isNotEmpty) {
          lastFailureReason = line.trim();
        }
      });

      final exitCode = await process.exitCode;
      if (exitCode == 0) {
        final curSelected = Set<String>.from(state.selectedBatchIds)..remove(batchId);
        state = state.copyWith(selectedBatchIds: curSelected);
        _tryLoadExistingProject();
        state = state.copyWith(statusMessage: 'Đã xóa phân cảnh $batchId thành công!', lastError: null);
        return true;
      }
      state = state.copyWith(
        lastError: lastFailureReason ?? 'Xóa phân cảnh thất bại (Exit code: $exitCode)',
      );
      return false;
    } catch (e) {
      state = state.copyWith(lastError: 'Lỗi xóa phân cảnh: $e');
      return false;
    }
  }

  /// Xóa toàn bộ các phân cảnh đang được chọn
  Future<bool> deleteSelectedBatches() async {
    final toDelete = List<String>.from(state.selectedBatchIds);
    if (toDelete.isEmpty) return false;

    if (toDelete.length >= state.batches.length) {
      state = state.copyWith(lastError: 'Không thể xóa toàn bộ phân cảnh. Dự án cần tối thiểu 1 phân cảnh.');
      return false;
    }

    bool allOk = true;
    for (final bid in toDelete) {
      final ok = await deleteBatch(bid);
      if (!ok) allOk = false;
    }
    state = state.copyWith(selectedBatchIds: const {});
    return allOk;
  }

  /// Tái tạo đồng thời các phân cảnh đã chọn thông qua worker đa luồng của Python
  Future<bool> reauthorSelectedBatches() async {
    final selected = state.selectedBatchIds.toList();
    if (selected.isEmpty) return false;

    state = state.copyWith(
      isBatchReauthoring: true,
      batchReauthorProgress: 0.0,
      statusMessage: 'Đang tái tạo ${selected.length} phân cảnh với đa worker...',
      lastError: null,
    );

    final pythonBin = PythonBridge.resolvePythonBin();
    final scriptPath = _resolveOrchestratorScript();
    final root = PythonBridge.resolveRootDir();
    final globalConfig = _ref.read(configProvider);
    syncFromConfig(globalConfig);

    final List<String> args = [
      scriptPath,
      '--mode',
      'reauthor_batch_multi',
      '--project-file',
      _projectJsonPath,
      '--batch-ids',
      selected.join(','),
      if (state.config.htmlAuthorModel != null && state.config.htmlAuthorModel!.isNotEmpty) ...[
        '--html-author-model',
        state.config.htmlAuthorModel!,
      ],
      if (state.config.htmlAuthorBaseUrl != null && state.config.htmlAuthorBaseUrl!.isNotEmpty) ...[
        '--html-author-base-url',
        state.config.htmlAuthorBaseUrl!,
      ],
      if (state.config.htmlAuthorApiKey != null && state.config.htmlAuthorApiKey!.isNotEmpty) ...[
        '--html-author-api-key',
        state.config.htmlAuthorApiKey!,
      ],
      if (globalConfig.translatorType.isNotEmpty) ...['--translator-type', globalConfig.translatorType],
      if (globalConfig.translatorApiKey.isNotEmpty) ...['--api-key', globalConfig.translatorApiKey],
      if (globalConfig.translatorModel.isNotEmpty) ...['--model', globalConfig.translatorModel],
      if (globalConfig.translatorBaseUrl.isNotEmpty) ...['--base-url', globalConfig.translatorBaseUrl],
    ];

    try {
      final env = PythonBridge.buildEnvironment(rootDir: root, pythonBin: pythonBin);
      final process = await Process.start(pythonBin, args, workingDirectory: root, environment: env);

      process.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
        PythonBridge.addLog('lecture_illustrator', 'stdout', line);
        if (line.trim().startsWith('{') && line.trim().endsWith('}')) {
          try {
            final obj = jsonDecode(line.trim());
            if (obj['type'] == 'progress' && obj['action'] == 'reauthor_batch_multi') {
              final done = (obj['completed'] as num?)?.toInt() ?? 0;
              final total = (obj['total'] as num?)?.toInt() ?? selected.length;
              if (total > 0) {
                state = state.copyWith(batchReauthorProgress: done / total);
              }
            }
          } catch (_) {}
        }
      });

      process.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen((err) {
        PythonBridge.addLog('lecture_illustrator', 'stderr', err);
      });

      final exitCode = await process.exitCode;
      _tryLoadExistingProject();
      state = state.copyWith(
        isBatchReauthoring: false,
        selectedBatchIds: const {},
        statusMessage: exitCode == 0 ? 'Đã hoàn tất tái tạo các phân cảnh đã chọn!' : 'Quá trình tái tạo gặp một số cảnh lỗi.',
      );
      return exitCode == 0;
    } catch (e) {
      state = state.copyWith(
        isBatchReauthoring: false,
        lastError: 'Lỗi tái tạo hàng loạt: $e',
      );
      return false;
    }
  }

  /// Tinh chỉnh phẫu thuật từ mã HTML đã sinh hiện tại theo yêu cầu người dùng
  Future<bool> refineBatchHtmlWithAi({
    required String batchId,
    required String feedback,
  }) async {
    final vPath = state.videoPath;
    if (vPath == null || vPath.isEmpty) return false;

    state = state.copyWith(
      statusMessage: 'AI đang tinh chỉnh mã HTML cho $batchId...',
      lastError: null,
    );
    PythonBridge.addLog('lecture_illustrator', 'info',
        'Bắt đầu AI tinh chỉnh HTML cho $batchId với phản hồi: $feedback');

    final pythonBin = PythonBridge.resolvePythonBin();
    final scriptPath = _resolveOrchestratorScript();
    final root = PythonBridge.resolveRootDir();
    final globalConfig = _ref.read(configProvider);
    syncFromConfig(globalConfig);

    final List<String> args = [
      scriptPath,
      '--mode',
      'reauthor_batch',
      '--project-file',
      _projectJsonPath,
      '--batch-id',
      batchId,
      '--feedback',
      feedback,
      '--refine',
      if (state.config.htmlAuthorModel != null && state.config.htmlAuthorModel!.isNotEmpty) ...[
        '--html-author-model',
        state.config.htmlAuthorModel!,
      ],
      if (state.config.htmlAuthorBaseUrl != null && state.config.htmlAuthorBaseUrl!.isNotEmpty) ...[
        '--html-author-base-url',
        state.config.htmlAuthorBaseUrl!,
      ],
      if (state.config.htmlAuthorApiKey != null && state.config.htmlAuthorApiKey!.isNotEmpty) ...[
        '--html-author-api-key',
        state.config.htmlAuthorApiKey!,
      ],
      if (globalConfig.translatorType.isNotEmpty) ...['--translator-type', globalConfig.translatorType],
      if (globalConfig.translatorApiKey.isNotEmpty) ...['--api-key', globalConfig.translatorApiKey],
      if (globalConfig.translatorModel.isNotEmpty) ...['--model', globalConfig.translatorModel],
      if (globalConfig.translatorBaseUrl.isNotEmpty) ...['--base-url', globalConfig.translatorBaseUrl],
    ];

    try {
      final env = PythonBridge.buildEnvironment(rootDir: root, pythonBin: pythonBin);
      final process = await Process.start(pythonBin, args, workingDirectory: root, environment: env);
      final exitCode = await process.exitCode;
      if (exitCode == 0) {
        _tryLoadExistingProject();
        state = state.copyWith(
          statusMessage: 'Đã hoàn tất tinh chỉnh AI cho $batchId!',
          lastError: null,
        );
        return true;
      }
      return false;
    } catch (e) {
      state = state.copyWith(lastError: 'Lỗi tinh chỉnh HTML: $e');
      return false;
    }
  }
}
