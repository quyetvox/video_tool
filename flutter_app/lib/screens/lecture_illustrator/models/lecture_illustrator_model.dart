import 'package:flutter/foundation.dart';

@immutable
class BatchActiveAsset {
  final String filePath;
  final String type; // 'image', 'video', 'diagram'
  final String source; // 'none', 'user_import', 'ai_generated'
  final String layout; // 'pip', 'full', 'split', 'custom'
  final bool locked;

  const BatchActiveAsset({
    this.filePath = '',
    this.type = 'image',
    this.source = 'none',
    this.layout = 'pip',
    this.locked = false,
  });

  BatchActiveAsset copyWith({
    String? filePath,
    String? type,
    String? source,
    String? layout,
    bool? locked,
  }) {
    return BatchActiveAsset(
      filePath: filePath ?? this.filePath,
      type: type ?? this.type,
      source: source ?? this.source,
      layout: layout ?? this.layout,
      locked: locked ?? this.locked,
    );
  }

  Map<String, dynamic> toJson() => {
        'file_path': filePath,
        'type': type,
        'source': source,
        'layout': layout,
        'locked': locked,
      };

  factory BatchActiveAsset.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const BatchActiveAsset();
    return BatchActiveAsset(
      filePath: json['file_path']?.toString() ?? '',
      type: json['type']?.toString() ?? 'image',
      source: json['source']?.toString() ?? 'none',
      layout: json['layout']?.toString() ?? 'pip',
      locked: json['locked'] == true,
    );
  }
}

@immutable
class BatchPrompts {
  final String imagePrompt;
  final String diagramMermaid;
  final String animationConcept;
  final String codeAnimation;

  const BatchPrompts({
    this.imagePrompt = '',
    this.diagramMermaid = '',
    this.animationConcept = '',
    this.codeAnimation = '',
  });

  BatchPrompts copyWith({
    String? imagePrompt,
    String? diagramMermaid,
    String? animationConcept,
    String? codeAnimation,
  }) {
    return BatchPrompts(
      imagePrompt: imagePrompt ?? this.imagePrompt,
      diagramMermaid: diagramMermaid ?? this.diagramMermaid,
      animationConcept: animationConcept ?? this.animationConcept,
      codeAnimation: codeAnimation ?? this.codeAnimation,
    );
  }

  Map<String, dynamic> toJson() => {
        'image_prompt': imagePrompt,
        'diagram_mermaid': diagramMermaid,
        'animation_concept': animationConcept,
        'code_animation': codeAnimation,
      };

  factory BatchPrompts.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const BatchPrompts();
    return BatchPrompts(
      imagePrompt: json['image_prompt']?.toString() ?? '',
      diagramMermaid: json['diagram_mermaid']?.toString() ?? '',
      animationConcept: json['animation_concept']?.toString() ?? '',
      codeAnimation: json['code_animation']?.toString() ?? '',
    );
  }
}

@immutable
class LectureBatch {
  final String id;
  final double startSec;
  final double endSec;
  final String transcriptOriginal;
  final String transcriptTranslated;
  final String educationalIntent;
  final String visualPriority;
  final BatchPrompts prompts;
  final BatchActiveAsset? activeAsset;
  final List<Map<String, dynamic>> sentences;
  final Map<String, dynamic> scene;
  final List<double> stepStarts;
  final double sceneDuration;
  final String sceneVideo;

  const LectureBatch({
    required this.id,
    required this.startSec,
    required this.endSec,
    required this.transcriptOriginal,
    this.transcriptTranslated = '',
    this.educationalIntent = 'CONCEPT',
    this.visualPriority = 'HIGH',
    this.prompts = const BatchPrompts(),
    this.activeAsset,
    this.sentences = const [],
    this.scene = const {},
    this.stepStarts = const [],
    this.sceneDuration = 0.0,
    this.sceneVideo = '',
  });

  LectureBatch copyWith({
    String? id,
    double? startSec,
    double? endSec,
    String? transcriptOriginal,
    String? transcriptTranslated,
    String? educationalIntent,
    String? visualPriority,
    BatchPrompts? prompts,
    BatchActiveAsset? activeAsset,
    bool clearActiveAsset = false,
    List<Map<String, dynamic>>? sentences,
    Map<String, dynamic>? scene,
    List<double>? stepStarts,
    double? sceneDuration,
    String? sceneVideo,
  }) {
    return LectureBatch(
      id: id ?? this.id,
      startSec: startSec ?? this.startSec,
      endSec: endSec ?? this.endSec,
      transcriptOriginal: transcriptOriginal ?? this.transcriptOriginal,
      transcriptTranslated: transcriptTranslated ?? this.transcriptTranslated,
      educationalIntent: educationalIntent ?? this.educationalIntent,
      visualPriority: visualPriority ?? this.visualPriority,
      prompts: prompts ?? this.prompts,
      activeAsset: clearActiveAsset ? null : (activeAsset ?? this.activeAsset),
      sentences: sentences ?? this.sentences,
      scene: scene ?? this.scene,
      stepStarts: stepStarts ?? this.stepStarts,
      sceneDuration: sceneDuration ?? this.sceneDuration,
      sceneVideo: sceneVideo ?? this.sceneVideo,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'start_sec': startSec,
        'end_sec': endSec,
        'transcript_original': transcriptOriginal,
        'transcript_translated': transcriptTranslated,
        'educational_intent': educationalIntent,
        'visual_priority': visualPriority,
        'prompts': prompts.toJson(),
        'active_asset': activeAsset?.toJson(),
        'sentences': sentences,
        'scene': scene,
        'step_starts': stepStarts,
        'scene_duration': sceneDuration,
        'scene_video': sceneVideo,
      };

  factory LectureBatch.fromJson(Map<String, dynamic> json) {
    return LectureBatch(
      id: json['id']?.toString() ?? '',
      startSec: (json['start_sec'] as num?)?.toDouble() ?? 0.0,
      endSec: (json['end_sec'] as num?)?.toDouble() ?? 0.0,
      transcriptOriginal: json['transcript_original']?.toString() ?? '',
      transcriptTranslated: json['transcript_translated']?.toString() ?? '',
      educationalIntent: json['educational_intent']?.toString() ?? 'CONCEPT',
      visualPriority: json['visual_priority']?.toString() ?? 'HIGH',
      prompts: BatchPrompts.fromJson(json['prompts'] as Map<String, dynamic>?),
      activeAsset: json['active_asset'] != null
          ? BatchActiveAsset.fromJson(json['active_asset'] as Map<String, dynamic>?)
          : null,
      sentences: (json['sentences'] as List<dynamic>?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          const [],
      scene: (json['scene'] as Map<String, dynamic>?) ?? const {},
      stepStarts: (json['step_starts'] as List<dynamic>?)
              ?.map((e) => (e as num).toDouble())
              .toList() ??
          const [],
      sceneDuration: (json['scene_duration'] as num?)?.toDouble() ?? 0.0,
      sceneVideo: json['scene_video']?.toString() ?? '',
    );
  }
}

@immutable
class LectureProjectConfig {
  final String sourceLang;
  final String targetLang;
  final String secondaryLang;
  final String pronounMode;
  final String voiceMode; // 'original' | 'tts_dub'
  final String ttsVoice;
  final double ttsSpeed;
  final double bgmVolume;
  final double voiceVolume;
  final bool burnSubtitles;
  final String subtitleMode; // 'single' | 'bilingual'
  final bool subtitleSecondaryShow;
  final String subtitleOrder; // 'primary_top' | 'primary_bottom'
  final String fontName;
  final String? secondaryFontName;
  final String fontSize;
  final String fontColor;
  final String outlineColor;
  final String secondaryFontColor;
  final double secondaryScale;
  final String videoBitrate;
  final bool watermarkEnabled;
  final String watermarkPath;
  final bool enableInpaint;
  final String inpaintEngine; // 'ffmpeg_blur' | 'box_color' | 'apple_vision_inpaint' | 'opencv'
  final int inpaintBlurRadius;
  final String boxBgColor;
  final double boxOpacity;
  final String inpaintMethod;
  final List<double> inpaintRegion;
  final String visualLayoutPreset; // 'pip', 'full', 'split'

  const LectureProjectConfig({
    this.sourceLang = 'auto',
    this.targetLang = 'vi',
    this.secondaryLang = 'en',
    this.pronounMode = 'formal',
    this.voiceMode = 'tts_dub',
    this.ttsVoice = 'ban_mai',
    this.ttsSpeed = 1.15,
    this.bgmVolume = 0.10,
    this.voiceVolume = 1.0,
    this.burnSubtitles = true,
    this.subtitleMode = 'bilingual',
    this.subtitleSecondaryShow = true,
    this.subtitleOrder = 'primary_top',
    this.fontName = 'Be Vietnam Pro',
    this.secondaryFontName,
    this.fontSize = '26',
    this.fontColor = '&H00FFFFFF',
    this.outlineColor = '&H00000000',
    this.secondaryFontColor = '&H00E7E1DC',
    this.secondaryScale = 0.70,
    this.videoBitrate = '6000k',
    this.watermarkEnabled = false,
    this.watermarkPath = '',
    this.enableInpaint = false,
    this.inpaintEngine = 'ffmpeg_blur',
    this.inpaintBlurRadius = 20,
    this.boxBgColor = '#000000',
    this.boxOpacity = 0.85,
    this.inpaintMethod = 'vertical_gradient',
    this.inpaintRegion = const [0.82, 0.10, 0.92, 0.90],
    this.visualLayoutPreset = 'pip',
  });

  LectureProjectConfig copyWith({
    String? sourceLang,
    String? targetLang,
    String? secondaryLang,
    String? pronounMode,
    String? voiceMode,
    String? ttsVoice,
    double? ttsSpeed,
    double? bgmVolume,
    double? voiceVolume,
    bool? burnSubtitles,
    String? subtitleMode,
    bool? subtitleSecondaryShow,
    String? subtitleOrder,
    String? fontName,
    String? secondaryFontName,
    String? fontSize,
    String? fontColor,
    String? outlineColor,
    String? secondaryFontColor,
    double? secondaryScale,
    String? videoBitrate,
    bool? watermarkEnabled,
    String? watermarkPath,
    bool? enableInpaint,
    String? inpaintEngine,
    int? inpaintBlurRadius,
    String? boxBgColor,
    double? boxOpacity,
    String? inpaintMethod,
    List<double>? inpaintRegion,
    String? visualLayoutPreset,
  }) {
    return LectureProjectConfig(
      sourceLang: sourceLang ?? this.sourceLang,
      targetLang: targetLang ?? this.targetLang,
      secondaryLang: secondaryLang ?? this.secondaryLang,
      pronounMode: pronounMode ?? this.pronounMode,
      voiceMode: voiceMode ?? this.voiceMode,
      ttsVoice: ttsVoice ?? this.ttsVoice,
      ttsSpeed: ttsSpeed ?? this.ttsSpeed,
      bgmVolume: bgmVolume ?? this.bgmVolume,
      voiceVolume: voiceVolume ?? this.voiceVolume,
      burnSubtitles: burnSubtitles ?? this.burnSubtitles,
      subtitleMode: subtitleMode ?? this.subtitleMode,
      subtitleSecondaryShow: subtitleSecondaryShow ?? this.subtitleSecondaryShow,
      subtitleOrder: subtitleOrder ?? this.subtitleOrder,
      fontName: fontName ?? this.fontName,
      secondaryFontName: secondaryFontName ?? this.secondaryFontName,
      fontSize: fontSize ?? this.fontSize,
      fontColor: fontColor ?? this.fontColor,
      outlineColor: outlineColor ?? this.outlineColor,
      secondaryFontColor: secondaryFontColor ?? this.secondaryFontColor,
      secondaryScale: secondaryScale ?? this.secondaryScale,
      videoBitrate: videoBitrate ?? this.videoBitrate,
      watermarkEnabled: watermarkEnabled ?? this.watermarkEnabled,
      watermarkPath: watermarkPath ?? this.watermarkPath,
      enableInpaint: enableInpaint ?? this.enableInpaint,
      inpaintEngine: inpaintEngine ?? this.inpaintEngine,
      inpaintBlurRadius: inpaintBlurRadius ?? this.inpaintBlurRadius,
      boxBgColor: boxBgColor ?? this.boxBgColor,
      boxOpacity: boxOpacity ?? this.boxOpacity,
      inpaintMethod: inpaintMethod ?? this.inpaintMethod,
      inpaintRegion: inpaintRegion ?? this.inpaintRegion,
      visualLayoutPreset: visualLayoutPreset ?? this.visualLayoutPreset,
    );
  }

  Map<String, dynamic> toJson() => {
        'source_lang': sourceLang,
        'target_lang': targetLang,
        'secondary_lang': secondaryLang,
        'pronoun_mode': pronounMode,
        'voice_mode': voiceMode,
        'tts_voice': ttsVoice,
        'tts_speed': ttsSpeed,
        'bgm_volume': bgmVolume,
        'voice_volume': voiceVolume,
        'burn_subtitles': burnSubtitles,
        'subtitle_mode': subtitleMode,
        'subtitle_secondary_show': subtitleSecondaryShow,
        'subtitle_order': subtitleOrder,
        'font_name': fontName,
        if (secondaryFontName != null) 'secondary_font_name': secondaryFontName,
        'font_size': fontSize,
        'font_color': fontColor,
        'outline_color': outlineColor,
        'secondary_font_color': secondaryFontColor,
        'secondary_scale': secondaryScale,
        'video_bitrate': videoBitrate,
        'watermark_enabled': watermarkEnabled,
        'watermark_path': watermarkPath,
        'enable_inpaint': enableInpaint,
        'inpaint_engine': inpaintEngine,
        'inpaint_blur_radius': inpaintBlurRadius,
        'box_bg_color': boxBgColor,
        'box_opacity': boxOpacity,
        'inpaint_method': inpaintMethod,
        'inpaint_region': inpaintRegion,
        'visual_layout_preset': visualLayoutPreset,
      };

  factory LectureProjectConfig.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const LectureProjectConfig();
    final regRaw = json['inpaint_region'];
    List<double> region = const [0.82, 0.10, 0.92, 0.90];
    if (regRaw is List && regRaw.length == 4) {
      region = regRaw.map((e) => (e as num).toDouble()).toList();
    }
    return LectureProjectConfig(
      sourceLang: json['source_lang']?.toString() ?? 'auto',
      targetLang: json['target_lang']?.toString() ?? 'vi',
      secondaryLang: json['secondary_lang']?.toString() ?? 'en',
      pronounMode: json['pronoun_mode']?.toString() ?? 'formal',
      voiceMode: json['voice_mode']?.toString() ?? 'tts_dub',
      ttsVoice: json['tts_voice']?.toString() ?? 'ban_mai',
      ttsSpeed: (json['tts_speed'] as num?)?.toDouble() ?? 1.15,
      bgmVolume: (json['bgm_volume'] as num?)?.toDouble() ?? 0.10,
      voiceVolume: (json['voice_volume'] as num?)?.toDouble() ?? 1.0,
      burnSubtitles: json['burn_subtitles'] != false,
      subtitleMode: json['subtitle_mode']?.toString() ?? 'bilingual',
      subtitleSecondaryShow: json['subtitle_secondary_show'] != false,
      subtitleOrder: json['subtitle_order']?.toString() ?? 'primary_top',
      fontName: json['font_name']?.toString() ?? 'Be Vietnam Pro',
      secondaryFontName: json['secondary_font_name']?.toString(),
      fontSize: json['font_size']?.toString() ?? '26',
      fontColor: json['font_color']?.toString() ?? '&H00FFFFFF',
      outlineColor: json['outline_color']?.toString() ?? '&H00000000',
      secondaryFontColor: json['secondary_font_color']?.toString() ?? '&H00E7E1DC',
      secondaryScale: (json['secondary_scale'] as num?)?.toDouble() ?? 0.70,
      videoBitrate: json['video_bitrate']?.toString() ?? '6000k',
      watermarkEnabled: json['watermark_enabled'] == true,
      watermarkPath: json['watermark_path']?.toString() ?? '',
      enableInpaint: json['enable_inpaint'] == true,
      inpaintEngine: json['inpaint_engine']?.toString() ?? 'ffmpeg_blur',
      inpaintBlurRadius: (json['inpaint_blur_radius'] as num?)?.toInt() ?? 20,
      boxBgColor: json['box_bg_color']?.toString() ?? '#000000',
      boxOpacity: (json['box_opacity'] as num?)?.toDouble() ?? 0.85,
      inpaintMethod: json['inpaint_method']?.toString() ?? 'vertical_gradient',
      inpaintRegion: region,
      visualLayoutPreset: json['visual_layout_preset']?.toString() ?? 'pip',
    );
  }
}

@immutable
class LectureIllustratorState {
  final String? projectName;
  final String? videoPath;
  final String? videoName;
  final double videoDuration;
  final int videoWidth;
  final int videoHeight;
  final LectureProjectConfig config;
  final List<LectureBatch> batches;
  final String? selectedBatchId;
  final bool isAnalyzing;
  final bool isRendering;
  final double progress;
  final String? statusMessage;
  final String? lastError;
  final String metaTitle;
  final String metaDesc;
  final List<String> metaHashtags;

  const LectureIllustratorState({
    this.projectName,
    this.videoPath,
    this.videoName,
    this.videoDuration = 0.0,
    this.videoWidth = 1920,
    this.videoHeight = 1080,
    this.config = const LectureProjectConfig(),
    this.batches = const [],
    this.selectedBatchId,
    this.isAnalyzing = false,
    this.isRendering = false,
    this.progress = 0.0,
    this.statusMessage,
    this.lastError,
    this.metaTitle = '',
    this.metaDesc = '',
    this.metaHashtags = const [],
  });

  LectureIllustratorState copyWith({
    String? projectName,
    String? videoPath,
    String? videoName,
    double? videoDuration,
    int? videoWidth,
    int? videoHeight,
    LectureProjectConfig? config,
    List<LectureBatch>? batches,
    String? selectedBatchId,
    bool? isAnalyzing,
    bool? isRendering,
    double? progress,
    String? statusMessage,
    String? lastError,
    String? metaTitle,
    String? metaDesc,
    List<String>? metaHashtags,
  }) {
    return LectureIllustratorState(
      projectName: projectName ?? this.projectName,
      videoPath: videoPath ?? this.videoPath,
      videoName: videoName ?? this.videoName,
      videoDuration: videoDuration ?? this.videoDuration,
      videoWidth: videoWidth ?? this.videoWidth,
      videoHeight: videoHeight ?? this.videoHeight,
      config: config ?? this.config,
      batches: batches ?? this.batches,
      selectedBatchId: selectedBatchId ?? this.selectedBatchId,
      isAnalyzing: isAnalyzing ?? this.isAnalyzing,
      isRendering: isRendering ?? this.isRendering,
      progress: progress ?? this.progress,
      statusMessage: statusMessage ?? this.statusMessage,
      lastError: lastError,
      metaTitle: metaTitle ?? this.metaTitle,
      metaDesc: metaDesc ?? this.metaDesc,
      metaHashtags: metaHashtags ?? this.metaHashtags,
    );
  }

  Map<String, dynamic> toJson() => {
        'project_name': projectName,
        'video_path': videoPath,
        'video_duration': videoDuration,
        'video_width': videoWidth,
        'video_height': videoHeight,
        'config': config.toJson(),
        'batches': batches.map((b) => b.toJson()).toList(),
        'meta_title': metaTitle,
        'meta_desc': metaDesc,
        'meta_hashtags': metaHashtags,
      };

  factory LectureIllustratorState.fromJson(Map<String, dynamic> json) {
    final cfgRaw = json['config'] as Map<String, dynamic>?;
    final batchesRaw = (json['batches'] as List?) ?? [];
    final tagsRaw = (json['meta_hashtags'] as List?) ?? [];
    return LectureIllustratorState(
      projectName: json['project_name']?.toString(),
      videoPath: json['video_path']?.toString(),
      videoDuration: (json['video_duration'] as num?)?.toDouble() ?? 0.0,
      videoWidth: (json['video_width'] as num?)?.toInt() ?? 1920,
      videoHeight: (json['video_height'] as num?)?.toInt() ?? 1080,
      config: LectureProjectConfig.fromJson(cfgRaw),
      batches: batchesRaw
          .whereType<Map<String, dynamic>>()
          .map((b) => LectureBatch.fromJson(b))
          .toList(),
      metaTitle: json['meta_title']?.toString() ?? '',
      metaDesc: json['meta_desc']?.toString() ?? '',
      metaHashtags: tagsRaw.map((e) => e.toString()).toList(),
    );
  }
}
