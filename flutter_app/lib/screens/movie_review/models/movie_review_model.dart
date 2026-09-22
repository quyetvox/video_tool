
enum MovieGenre {
  linearAction,
  complexPsychological,
  shorts,
  custom,
}

extension MovieGenreExt on MovieGenre {
  String get id {
    switch (this) {
      case MovieGenre.linearAction:
        return 'linear_action';
      case MovieGenre.complexPsychological:
        return 'complex_psychological';
      case MovieGenre.shorts:
        return 'shorts';
      case MovieGenre.custom:
        return 'custom';
    }
  }

  String get label {
    switch (this) {
      case MovieGenre.linearAction:
        return 'Tuyến tính / Hành động';
      case MovieGenre.complexPsychological:
        return 'Phức tạp / Tâm lý / Twist';
      case MovieGenre.shorts:
        return 'Video Ngắn (Shorts/TikTok)';
      case MovieGenre.custom:
        return 'Tùy chỉnh thời lượng';
    }
  }

  String get description {
    switch (this) {
      case MovieGenre.linearAction:
        return 'Gợi ý 5-8 phút. Tập trung cảnh hành động mãn nhãn, bỏ qua tiểu tiết.';
      case MovieGenre.complexPsychological:
        return 'Gợi ý 10-15 phút. Giải thích luật chơi, phân tích diễn biến tâm lý & cú Twist.';
      case MovieGenre.shorts:
        return 'Gợi ý 1-3 phút. Tập trung 1 tình huống éo le hoặc 1 cú twist đỉnh nhất.';
      case MovieGenre.custom:
        return 'Tự do lựa chọn thời lượng theo định hướng của bạn.';
    }
  }

  int get defaultDurationSec {
    switch (this) {
      case MovieGenre.linearAction:
        return 360; // 6 phút
      case MovieGenre.complexPsychological:
        return 720; // 12 phút
      case MovieGenre.shorts:
        return 120; // 2 phút
      case MovieGenre.custom:
        return 360;
    }
  }

  String get recommendedRange {
    switch (this) {
      case MovieGenre.linearAction:
        return '5 - 8 phút';
      case MovieGenre.complexPsychological:
        return '10 - 15 phút';
      case MovieGenre.shorts:
        return '1 - 3 phút';
      case MovieGenre.custom:
        return 'Tùy chỉnh';
    }
  }
}

enum ReviewStyle {
  storyReview,
  critique,
}

extension ReviewStyleExt on ReviewStyle {
  String get id {
    switch (this) {
      case ReviewStyle.storyReview:
        return 'story_review';
      case ReviewStyle.critique:
        return 'critique';
    }
  }

  String get label {
    switch (this) {
      case ReviewStyle.storyReview:
        return 'Kể Chuyện Kịch Tính (Triệu View)';
      case ReviewStyle.critique:
        return 'Phê Bình Tác Phẩm (Chiều Sâu)';
    }
  }

  String get description {
    switch (this) {
      case ReviewStyle.storyReview:
        return 'Kể chuyện gay cấn, nhịp nhanh, cuốn hút, chuẩn giải trí YouTube/TikTok.';
      case ReviewStyle.critique:
        return 'Phân tích luận điểm sâu sắc, mổ xẻ tâm lý, triết lý và nghệ thuật điện ảnh.';
    }
  }
}


class ActStructureConfig {
  final bool enableHook;
  final bool enableStory;
  final bool enableReview;
  final bool enableOutro;
  final double hookPct;
  final double storyPct;
  final double reviewPct;
  final double outroPct;
  final List<int> selectedChapterIds;
  final List<Map<String, dynamic>> availableChapters;

  const ActStructureConfig({
    this.enableHook = true,
    this.enableStory = true,
    this.enableReview = true,
    this.enableOutro = true,
    this.hookPct = 0.10,
    this.storyPct = 0.75,
    this.reviewPct = 0.10,
    this.outroPct = 0.05,
    this.selectedChapterIds = const [],
    this.availableChapters = const [],
  });

  factory ActStructureConfig.defaultFor(ReviewStyle style) {
    if (style == ReviewStyle.critique) {
      return const ActStructureConfig(
        enableHook: true,
        enableStory: true,
        enableReview: true,
        enableOutro: true,
        hookPct: 0.15,
        storyPct: 0.45,
        reviewPct: 0.30,
        outroPct: 0.10,
      );
    }
    return const ActStructureConfig(
      enableHook: true,
      enableStory: true,
      enableReview: true,
      enableOutro: true,
      hookPct: 0.10,
      storyPct: 0.75,
      reviewPct: 0.10,
      outroPct: 0.05,
    );
  }

  ActStructureConfig copyWith({
    bool? enableHook,
    bool? enableStory,
    bool? enableReview,
    bool? enableOutro,
    double? hookPct,
    double? storyPct,
    double? reviewPct,
    double? outroPct,
    List<int>? selectedChapterIds,
    List<Map<String, dynamic>>? availableChapters,
  }) {
    return ActStructureConfig(
      enableHook: enableHook ?? this.enableHook,
      enableStory: enableStory ?? this.enableStory,
      enableReview: enableReview ?? this.enableReview,
      enableOutro: enableOutro ?? this.enableOutro,
      hookPct: hookPct ?? this.hookPct,
      storyPct: storyPct ?? this.storyPct,
      reviewPct: reviewPct ?? this.reviewPct,
      outroPct: outroPct ?? this.outroPct,
      selectedChapterIds: selectedChapterIds ?? this.selectedChapterIds,
      availableChapters: availableChapters ?? this.availableChapters,
    );
  }

  /// Cập nhật tỷ lệ % cho một hồi với cơ chế Story-Anchor Auto-Balancing
  ActStructureConfig updateActPct(String act, double newPct) {
    final clamped = (newPct * 100).round() / 100.0;
    switch (act.toLowerCase()) {
      case 'hook':
        if (!enableHook) return this;
        final maxH = (1.0 - (enableReview ? reviewPct : 0.0) - (enableOutro ? outroPct : 0.0) - 0.20).clamp(0.05, 0.40);
        final validH = clamped.clamp(0.05, maxH);
        final newStory = enableStory ? (1.0 - validH - (enableReview ? reviewPct : 0.0) - (enableOutro ? outroPct : 0.0)) : 0.0;
        return copyWith(hookPct: validH, storyPct: double.parse(newStory.toStringAsFixed(2)));

      case 'review':
        if (!enableReview) return this;
        final maxR = (1.0 - (enableHook ? hookPct : 0.0) - (enableOutro ? outroPct : 0.0) - 0.20).clamp(0.05, 0.50);
        final validR = clamped.clamp(0.05, maxR);
        final newStory = enableStory ? (1.0 - (enableHook ? hookPct : 0.0) - validR - (enableOutro ? outroPct : 0.0)) : 0.0;
        return copyWith(reviewPct: validR, storyPct: double.parse(newStory.toStringAsFixed(2)));

      case 'outro':
        if (!enableOutro) return this;
        final maxO = (1.0 - (enableHook ? hookPct : 0.0) - (enableReview ? reviewPct : 0.0) - 0.20).clamp(0.02, 0.25);
        final validO = clamped.clamp(0.02, maxO);
        final newStory = enableStory ? (1.0 - (enableHook ? hookPct : 0.0) - (enableReview ? reviewPct : 0.0) - validO) : 0.0;
        return copyWith(outroPct: validO, storyPct: double.parse(newStory.toStringAsFixed(2)));

      case 'story':
        if (!enableStory) return this;
        final validS = clamped.clamp(0.20, 0.90);
        final remain = 1.0 - validS;
        final otherTotal = (enableHook ? hookPct : 0.0) + (enableReview ? reviewPct : 0.0) + (enableOutro ? outroPct : 0.0);
        if (otherTotal > 0) {
          final scale = remain / otherTotal;
          return copyWith(
            storyPct: validS,
            hookPct: enableHook ? double.parse((hookPct * scale).toStringAsFixed(2)) : 0.0,
            reviewPct: enableReview ? double.parse((reviewPct * scale).toStringAsFixed(2)) : 0.0,
            outroPct: enableOutro ? double.parse((outroPct * scale).toStringAsFixed(2)) : 0.0,
          );
        }
        return copyWith(storyPct: validS);

      default:
        return this;
    }
  }

  /// Bật / Tắt một hồi. Nếu tắt, % chuyển về 0 và dồn vào storyPct. Nếu bật, lấy lại % chuẩn.
  ActStructureConfig toggleAct(String act, bool enabled, [ReviewStyle style = ReviewStyle.storyReview]) {
    final def = ActStructureConfig.defaultFor(style);
    switch (act.toLowerCase()) {
      case 'hook':
        if (!enabled) {
          return copyWith(
            enableHook: false,
            hookPct: 0.0,
            storyPct: enableStory ? double.parse((storyPct + hookPct).toStringAsFixed(2)) : 0.0,
          );
        } else {
          final restorePct = def.hookPct;
          final newStory = enableStory ? (storyPct - restorePct).clamp(0.20, 1.0) : 0.0;
          return copyWith(
            enableHook: true,
            hookPct: restorePct,
            storyPct: double.parse(newStory.toStringAsFixed(2)),
          );
        }

      case 'story':
        if (!enabled) {
          return copyWith(
            enableStory: false,
            storyPct: 0.0,
            reviewPct: enableReview ? double.parse((reviewPct + storyPct * 0.7).toStringAsFixed(2)) : reviewPct,
            hookPct: enableHook ? double.parse((hookPct + storyPct * 0.3).toStringAsFixed(2)) : hookPct,
          );
        } else {
          final restorePct = def.storyPct;
          return copyWith(
            enableStory: true,
            storyPct: restorePct,
            reviewPct: def.reviewPct,
            hookPct: def.hookPct,
            outroPct: def.outroPct,
          );
        }

      case 'review':
        if (!enabled) {
          return copyWith(
            enableReview: false,
            reviewPct: 0.0,
            storyPct: enableStory ? double.parse((storyPct + reviewPct).toStringAsFixed(2)) : 0.0,
          );
        } else {
          final restorePct = def.reviewPct;
          final newStory = enableStory ? (storyPct - restorePct).clamp(0.20, 1.0) : 0.0;
          return copyWith(
            enableReview: true,
            reviewPct: restorePct,
            storyPct: double.parse(newStory.toStringAsFixed(2)),
          );
        }

      case 'outro':
        if (!enabled) {
          return copyWith(
            enableOutro: false,
            outroPct: 0.0,
            storyPct: enableStory ? double.parse((storyPct + outroPct).toStringAsFixed(2)) : 0.0,
          );
        } else {
          final restorePct = def.outroPct;
          final newStory = enableStory ? (storyPct - restorePct).clamp(0.20, 1.0) : 0.0;
          return copyWith(
            enableOutro: true,
            outroPct: restorePct,
            storyPct: double.parse(newStory.toStringAsFixed(2)),
          );
        }

      default:
        return this;
    }
  }

  /// Toggle chapter selection
  ActStructureConfig toggleChapter(int chapterId) {
    final cur = List<int>.from(selectedChapterIds);
    if (cur.contains(chapterId)) {
      cur.remove(chapterId);
    } else {
      cur.add(chapterId);
      cur.sort();
    }
    return copyWith(selectedChapterIds: cur);
  }

  /// Select all chapters
  ActStructureConfig selectAllChapters(bool selectAll) {
    if (selectAll) {
      final allIds = availableChapters.map((c) => c['chapter_id'] as int? ?? 0).where((id) => id > 0).toList();
      return copyWith(selectedChapterIds: allIds);
    } else {
      return copyWith(selectedChapterIds: const []);
    }
  }

  /// Reset to defaults
  ActStructureConfig resetToDefault(ReviewStyle style) {
    return ActStructureConfig.defaultFor(style).copyWith(
      availableChapters: availableChapters,
      selectedChapterIds: selectedChapterIds,
    );
  }

  Map<String, dynamic> toJson() => {
    'hook': enableHook,
    'story': enableStory,
    'review': enableReview,
    'outro': enableOutro,
    'hook_pct': hookPct,
    'story_pct': storyPct,
    'review_pct': reviewPct,
    'outro_pct': outroPct,
    'selected_chapters': selectedChapterIds,
  };
}

class WordBudget {
  final int totalWords;
  final int hookWords;
  final int storyWords;
  final int reviewWords;
  final int outroWords;
  final int wordsPerMin;
  final int numChapters;
  final int chapterWords;

  const WordBudget({
    required this.totalWords,
    required this.hookWords,
    required this.storyWords,
    required this.reviewWords,
    required this.outroWords,
    required this.wordsPerMin,
    this.numChapters = 0,
    this.chapterWords = 0,
  });

  static int calculateOptimalDuration(double movieDurationSec) {
    if (movieDurationSec <= 1200) {
      return 180; // 3 phút
    } else if (movieDurationSec <= 3600) {
      final raw = (movieDurationSec * 0.12 / 60.0).round() * 60;
      return raw.clamp(300, 480);
    } else if (movieDurationSec <= 9000) {
      final raw = (movieDurationSec * 0.08 / 60.0).round() * 60;
      return raw.clamp(480, 720);
    } else {
      return 900; // Cap 15 phút (900s)
    }
  }

  factory WordBudget.calculate(
    int targetDurationSec,
    double speedFactor, [
    ReviewStyle style = ReviewStyle.storyReview,
    ActStructureConfig? actConfig,
  ]) {
    final speed = speedFactor.clamp(0.8, 2.0);
    final minutes = (targetDurationSec / 60.0).clamp(0.5, 60.0);
    final wpm = 140.0 * speed;
    final total = (minutes * wpm).round();

    int numChapters;
    if (actConfig != null && actConfig.selectedChapterIds.isNotEmpty) {
      numChapters = actConfig.selectedChapterIds.length;
    } else if (targetDurationSec <= 360) {
      numChapters = style == ReviewStyle.storyReview ? 4 : 0;
    } else if (targetDurationSec <= 600) {
      numChapters = 4;
    } else if (targetDurationSec <= 840) {
      numChapters = 6;
    } else {
      numChapters = 8;
    }

    if (actConfig != null) {
      final hook = actConfig.enableHook ? (total * actConfig.hookPct).round().clamp(15, 500) : 0;
      final review = actConfig.enableReview ? (total * actConfig.reviewPct).round().clamp(20, 1000) : 0;
      final outro = actConfig.enableOutro ? (total * actConfig.outroPct).round().clamp(10, 500) : 0;
      final story = actConfig.enableStory ? (total - hook - review - outro).clamp(0, 10000) : 0;
      final chWords = (numChapters > 0 && story > 0) ? (story / numChapters).round() : story;

      return WordBudget(
        totalWords: total,
        hookWords: hook,
        storyWords: story,
        reviewWords: review,
        outroWords: outro,
        wordsPerMin: wpm.round(),
        numChapters: numChapters,
        chapterWords: chWords,
      );
    } else if (style == ReviewStyle.critique) {
      final hook = (total * 0.15).round().clamp(20, 300);
      final review = (total * 0.30).round().clamp(40, 1000);
      final outro = (total * 0.10).round().clamp(20, 300);
      final story = (total - hook - review - outro).clamp(50, 10000);
      final chWords = numChapters > 0 ? (story / numChapters).round() : story;

      return WordBudget(
        totalWords: total,
        hookWords: hook,
        storyWords: story,
        reviewWords: review,
        outroWords: outro,
        wordsPerMin: wpm.round(),
        numChapters: numChapters,
        chapterWords: chWords,
      );
    } else {
      // storyReview: 10% hook, 75% story, 10% review, 5% outro
      final hook = (total * 0.10).round().clamp(15, 200);
      final review = (total * 0.10).round().clamp(20, 400);
      final outro = (total * 0.05).round().clamp(10, 200);
      final story = (total - hook - review - outro).clamp(60, 10000);
      final chWords = numChapters > 0 ? (story / numChapters).round() : story;

      return WordBudget(
        totalWords: total,
        hookWords: hook,
        storyWords: story,
        reviewWords: review,
        outroWords: outro,
        wordsPerMin: wpm.round(),
        numChapters: numChapters,
        chapterWords: chWords,
      );
    }
  }
}

class SceneMeta {
  final int sceneId;
  final double startSec;
  final double endSec;
  final double duration;
  final String imagePath;
  final String act;

  const SceneMeta({
    required this.sceneId,
    required this.startSec,
    required this.endSec,
    required this.duration,
    required this.imagePath,
    this.act = 'storytelling',
  });

  factory SceneMeta.fromJson(Map<String, dynamic> json) {
    return SceneMeta(
      sceneId: json['scene_id'] as int? ?? 0,
      startSec: (json['start_sec'] as num?)?.toDouble() ?? 0.0,
      endSec: (json['end_sec'] as num?)?.toDouble() ?? 0.0,
      duration: (json['duration'] as num?)?.toDouble() ?? 0.0,
      imagePath: json['image_path'] as String? ?? '',
      act: json['act'] as String? ?? 'storytelling',
    );
  }

  Map<String, dynamic> toJson() => {
    'scene_id': sceneId,
    'start_sec': startSec,
    'end_sec': endSec,
    'duration': duration,
    'image_path': imagePath,
    'act': act,
  };
}

class ScriptSegment {
  final int id;
  final String section; // 'hook', 'storytelling', 'review', 'outro'
  final String voiceoverText;
  final List<SceneMeta> scenesToUse;
  final String? audioFile;
  final double? audioDuration;

  const ScriptSegment({
    required this.id,
    required this.section,
    required this.voiceoverText,
    required this.scenesToUse,
    this.audioFile,
    this.audioDuration,
  });

  ScriptSegment copyWith({
    int? id,
    String? section,
    String? voiceoverText,
    List<SceneMeta>? scenesToUse,
    String? audioFile,
    double? audioDuration,
  }) {
    return ScriptSegment(
      id: id ?? this.id,
      section: section ?? this.section,
      voiceoverText: voiceoverText ?? this.voiceoverText,
      scenesToUse: scenesToUse ?? this.scenesToUse,
      audioFile: audioFile ?? this.audioFile,
      audioDuration: audioDuration ?? this.audioDuration,
    );
  }

  factory ScriptSegment.fromJson(Map<String, dynamic> json, List<SceneMeta> allScenes) {
    final rawScenes = json['scenes_to_use'] as List? ?? [];
    final parsedScenes = <SceneMeta>[];

    for (final rs in rawScenes) {
      if (rs is Map<String, dynamic>) {
        final scId = rs['scene_id'] as int? ?? 0;
        final matched = allScenes.firstWhere(
          (s) => s.sceneId == scId,
          orElse: () => SceneMeta.fromJson(rs),
        );
        parsedScenes.add(matched);
      }
    }

    return ScriptSegment(
      id: json['id'] as int? ?? 1,
      section: json['section'] as String? ?? 'storytelling',
      voiceoverText: json['voiceover_text'] as String? ?? '',
      scenesToUse: parsedScenes,
      audioFile: json['audio_file'] as String?,
      audioDuration: (json['audio_duration'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'section': section,
    'voiceover_text': voiceoverText,
    'scenes_to_use': scenesToUse.map((s) => s.toJson()).toList(),
    if (audioFile != null) 'audio_file': audioFile,
    if (audioDuration != null) 'audio_duration': audioDuration,
  };
}

class MovieReviewState {
  final String? projectName;
  final String? videoPath;
  final String? videoName;
  final double videoDuration;
  final MovieGenre genre;
  final ReviewStyle reviewStyle;
  final int targetDurationSec;
  final double ttsSpeed;
  final String ttsVoice;
  final String aspectRatio; // '16:9' or '9:16'
  final String apiKey;
  final String aiModel;
  final ActStructureConfig actConfig;
  final double ttsVolume; // 0.0 to 1.0 (default 1.0)
  final double originalAudioVolume; // 0.0 to 1.0 (default 0.15)
  final double bgmVolume; // 0.0 to 1.0 (default 0.20)
  final bool hasCachedData;
  final String targetLang; // 'vi', 'en', 'zh'
  final bool burnSubtitles;
  final bool enableInpaint;
  final bool isAnalyzing;
  final bool isRendering;
  final double progress;
  final String statusMessage;
  final String activeSectionTab; // 'all', 'hook', 'storytelling', 'review', 'outro'
  final List<SceneMeta> availableScenes;
  final List<ScriptSegment> segments;
  final String? outputVideoPath;
  final List<String> consoleLogs;
  final int? currentlyPlayingSegmentId;
  final bool flipHorizontal;
  final bool cropZoom;
  final bool muteMovieAudio;
  final bool isContentDriven;
  final String customPrompt;
  final String metaTitle;
  final String metaDesc;
  final List<String> metaHashtags;

  const MovieReviewState({
    this.projectName,
    this.videoPath,
    this.videoName,
    this.videoDuration = 0.0,
    this.genre = MovieGenre.linearAction,
    this.reviewStyle = ReviewStyle.storyReview,
    this.targetDurationSec = 360,
    this.ttsSpeed = 1.45,
    this.ttsVoice = 'hoai_my',
    this.aspectRatio = '16:9',
    this.apiKey = '',
    this.aiModel = '',
    this.actConfig = const ActStructureConfig(),
    this.ttsVolume = 1.0,
    this.originalAudioVolume = 0.15,
    this.bgmVolume = 0.20,
    this.hasCachedData = false,
    this.targetLang = 'vi',
    this.burnSubtitles = true,
    this.enableInpaint = true,
    this.isAnalyzing = false,
    this.isRendering = false,
    this.progress = 0.0,
    this.statusMessage = 'Sẵn sàng phân tích phim',
    this.activeSectionTab = 'all',
    this.availableScenes = const [],
    this.segments = const [],
    this.outputVideoPath,
    this.consoleLogs = const [],
    this.currentlyPlayingSegmentId,
    this.flipHorizontal = false,
    this.cropZoom = false,
    this.muteMovieAudio = false,
    this.isContentDriven = true,
    this.customPrompt = '',
    this.metaTitle = '',
    this.metaDesc = '',
    this.metaHashtags = const [],
  });

  WordBudget get wordBudget => WordBudget.calculate(targetDurationSec, ttsSpeed, reviewStyle, actConfig);

  int get currentWordCount {
    int count = 0;
    for (final seg in segments) {
      final words = seg.voiceoverText.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
      count += words.length;
    }
    return count;
  }

  double get estimatedDurationSec {
    final wpm = 140.0 * ttsSpeed;
    if (wpm <= 0) return 0.0;
    return (currentWordCount / wpm) * 60.0;
  }

  MovieReviewState copyWith({
    String? projectName,
    String? videoPath,
    String? videoName,
    double? videoDuration,
    MovieGenre? genre,
    ReviewStyle? reviewStyle,
    int? targetDurationSec,
    double? ttsSpeed,
    String? ttsVoice,
    String? aspectRatio,
    String? apiKey,
    String? aiModel,
    ActStructureConfig? actConfig,
    double? ttsVolume,
    double? originalAudioVolume,
    double? bgmVolume,
    bool? hasCachedData,
    String? targetLang,
    bool? burnSubtitles,
    bool? enableInpaint,
    bool? isAnalyzing,
    bool? isRendering,
    double? progress,
    String? statusMessage,
    String? activeSectionTab,
    List<SceneMeta>? availableScenes,
    List<ScriptSegment>? segments,
    String? outputVideoPath,
    List<String>? consoleLogs,
    int? currentlyPlayingSegmentId,
    bool clearPlayingId = false,
    bool? flipHorizontal,
    bool? cropZoom,
    bool? muteMovieAudio,
    bool? isContentDriven,
    String? customPrompt,
    String? metaTitle,
    String? metaDesc,
    List<String>? metaHashtags,
  }) {
    return MovieReviewState(
      projectName: projectName ?? this.projectName,
      videoPath: videoPath ?? this.videoPath,
      videoName: videoName ?? this.videoName,
      videoDuration: videoDuration ?? this.videoDuration,
      genre: genre ?? this.genre,
      reviewStyle: reviewStyle ?? this.reviewStyle,
      targetDurationSec: targetDurationSec ?? this.targetDurationSec,
      ttsSpeed: ttsSpeed ?? this.ttsSpeed,
      ttsVoice: ttsVoice ?? this.ttsVoice,
      aspectRatio: aspectRatio ?? this.aspectRatio,
      apiKey: apiKey ?? this.apiKey,
      aiModel: aiModel ?? this.aiModel,
      actConfig: actConfig ?? this.actConfig,
      ttsVolume: ttsVolume ?? this.ttsVolume,
      originalAudioVolume: originalAudioVolume ?? this.originalAudioVolume,
      bgmVolume: bgmVolume ?? this.bgmVolume,
      hasCachedData: hasCachedData ?? this.hasCachedData,
      targetLang: targetLang ?? this.targetLang,
      burnSubtitles: burnSubtitles ?? this.burnSubtitles,
      enableInpaint: enableInpaint ?? this.enableInpaint,
      isAnalyzing: isAnalyzing ?? this.isAnalyzing,
      isRendering: isRendering ?? this.isRendering,
      progress: progress ?? this.progress,
      statusMessage: statusMessage ?? this.statusMessage,
      activeSectionTab: activeSectionTab ?? this.activeSectionTab,
      availableScenes: availableScenes ?? this.availableScenes,
      segments: segments ?? this.segments,
      outputVideoPath: outputVideoPath ?? this.outputVideoPath,
      consoleLogs: consoleLogs ?? this.consoleLogs,
      currentlyPlayingSegmentId: clearPlayingId ? null : (currentlyPlayingSegmentId ?? this.currentlyPlayingSegmentId),
      flipHorizontal: flipHorizontal ?? this.flipHorizontal,
      cropZoom: cropZoom ?? this.cropZoom,
      muteMovieAudio: muteMovieAudio ?? this.muteMovieAudio,
      isContentDriven: isContentDriven ?? this.isContentDriven,
      customPrompt: customPrompt ?? this.customPrompt,
      metaTitle: metaTitle ?? this.metaTitle,
      metaDesc: metaDesc ?? this.metaDesc,
      metaHashtags: metaHashtags ?? this.metaHashtags,
    );
  }
}
