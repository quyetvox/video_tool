/// Model đại diện cho một giọng đọc tuyển chọn
class TtsVoice {
  final String id;
  final String name;
  final String lang; // 'vi' | 'en'
  final String region; // 'VN' | 'US' | 'GB' | 'AU'
  final String gender; // 'female' | 'male'
  final String desc;
  final String engine; // 'edge' | 'gtts'

  const TtsVoice({
    required this.id,
    required this.name,
    required this.lang,
    required this.region,
    required this.gender,
    required this.desc,
    required this.engine,
  });

  factory TtsVoice.fromJson(Map<String, dynamic> json) {
    return TtsVoice(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      lang: json['lang'] as String? ?? 'en',
      region: json['region'] as String? ?? 'US',
      gender: json['gender'] as String? ?? 'female',
      desc: json['desc'] as String? ?? '',
      engine: json['engine'] as String? ?? 'edge',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'lang': lang,
        'region': region,
        'gender': gender,
        'desc': desc,
        'engine': engine,
      };

  String get flagEmoji {
    switch (region.toUpperCase()) {
      case 'VN':
        return '🇻🇳';
      case 'US':
        return '🇺🇸';
      case 'GB':
        return '🇬🇧';
      case 'AU':
        return '🇦🇺';
      default:
        return '🌐';
    }
  }

  String get genderLabel => gender == 'female' ? 'Nữ' : 'Nam';

  /// Danh mục các giọng đọc tuyển chọn chuẩn xác
  static const List<TtsVoice> defaultVoices = [
    // --- Tiếng Việt ---
    TtsVoice(
      id: 'vi-VN-HoaiMyNeural',
      name: 'Hoài My',
      lang: 'vi',
      region: 'VN',
      gender: 'female',
      desc: 'Nữ miền Bắc truyền cảm, tự nhiên',
      engine: 'edge',
    ),
    TtsVoice(
      id: 'vi-VN-NamMinhNeural',
      name: 'Nam Minh',
      lang: 'vi',
      region: 'VN',
      gender: 'male',
      desc: 'Nam miền Bắc ấm áp, đĩnh đạc',
      engine: 'edge',
    ),
    TtsVoice(
      id: 'gtts_vi',
      name: 'Ban Mai',
      lang: 'vi',
      region: 'VN',
      gender: 'female',
      desc: 'Nữ giọng phổ thông quen thuộc',
      engine: 'gtts',
    ),
    // --- Tiếng Anh (US) ---
    TtsVoice(
      id: 'en-US-JennyNeural',
      name: 'Jenny (US)',
      lang: 'en',
      region: 'US',
      gender: 'female',
      desc: 'Nữ Mỹ tự nhiên, thân thiện, diễn cảm',
      engine: 'edge',
    ),
    TtsVoice(
      id: 'en-US-GuyNeural',
      name: 'Guy (US)',
      lang: 'en',
      region: 'US',
      gender: 'male',
      desc: 'Nam Mỹ tự nhiên, phóng khoáng (podcast)',
      engine: 'edge',
    ),
    TtsVoice(
      id: 'en-US-AriaNeural',
      name: 'Aria (US)',
      lang: 'en',
      region: 'US',
      gender: 'female',
      desc: 'Nữ Mỹ trang trọng, dẫn chuyện (kể chuyện, sách)',
      engine: 'edge',
    ),
    TtsVoice(
      id: 'en-US-ChristopherNeural',
      name: 'Christopher (US)',
      lang: 'en',
      region: 'US',
      gender: 'male',
      desc: 'Nam Mỹ trầm ấm, uy quyền',
      engine: 'edge',
    ),
    // --- Tiếng Anh (UK) ---
    TtsVoice(
      id: 'en-GB-SoniaNeural',
      name: 'Sonia (UK)',
      lang: 'en',
      region: 'GB',
      gender: 'female',
      desc: 'Nữ Anh London sắc sảo, tự nhiên',
      engine: 'edge',
    ),
    TtsVoice(
      id: 'en-GB-RyanNeural',
      name: 'Ryan (UK)',
      lang: 'en',
      region: 'GB',
      gender: 'male',
      desc: 'Nam Anh chuẩn giọng truyền cảm',
      engine: 'edge',
    ),
    // --- Tiếng Anh (AU) ---
    TtsVoice(
      id: 'en-AU-NatashaNeural',
      name: 'Natasha (AU)',
      lang: 'en',
      region: 'AU',
      gender: 'female',
      desc: 'Nữ Úc hiện đại, trong trẻo',
      engine: 'edge',
    ),
    TtsVoice(
      id: 'en-AU-WilliamNeural',
      name: 'William (AU)',
      lang: 'en',
      region: 'AU',
      gender: 'male',
      desc: 'Nam Úc tự nhiên, đĩnh đạc',
      engine: 'edge',
    ),
  ];
}

/// Model đại diện cho một phân đoạn câu thoại trong kịch bản
class TtsSegmentItem {
  final int id;
  final String text;
  final String? voice; // null = kế thừa defaultVoice
  final double? speed; // null = kế thừa defaultSpeed
  final double? effectiveSpeed; // Tốc độ hiệu dụng thực tế (đã tính theo timeline)
  final bool isBoosted; // Có được tự động tăng tốc vượt trần hay không
  final int? pitch; // null = kế thừa defaultPitch
  final double duration; // Thời lượng vật lý (giây)
  final double startSec; // Mốc bắt đầu (giây)
  final double endSec; // Mốc kết thúc (giây)
  final int wordCount; // Số lượng từ
  final String? audioPath;
  final bool isSynthesizing;
  final bool isPlaying;

  const TtsSegmentItem({
    required this.id,
    required this.text,
    this.voice,
    this.speed,
    this.effectiveSpeed,
    this.isBoosted = false,
    this.pitch,
    this.duration = 0.0,
    this.startSec = 0.0,
    this.endSec = 0.0,
    this.wordCount = 0,
    this.audioPath,
    this.isSynthesizing = false,
    this.isPlaying = false,
  });

  TtsSegmentItem copyWith({
    int? id,
    String? text,
    String? voice,
    double? speed,
    double? effectiveSpeed,
    bool? isBoosted,
    int? pitch,
    double? duration,
    double? startSec,
    double? endSec,
    int? wordCount,
    String? audioPath,
    bool? isSynthesizing,
    bool? isPlaying,
    bool clearVoice = false,
    bool clearSpeed = false,
  }) {
    return TtsSegmentItem(
      id: id ?? this.id,
      text: text ?? this.text,
      voice: clearVoice ? null : (voice ?? this.voice),
      speed: clearSpeed ? null : (speed ?? this.speed),
      effectiveSpeed: effectiveSpeed ?? this.effectiveSpeed,
      isBoosted: isBoosted ?? this.isBoosted,
      pitch: pitch ?? this.pitch,
      duration: duration ?? this.duration,
      startSec: startSec ?? this.startSec,
      endSec: endSec ?? this.endSec,
      wordCount: wordCount ?? this.wordCount,
      audioPath: audioPath ?? this.audioPath,
      isSynthesizing: isSynthesizing ?? this.isSynthesizing,
      isPlaying: isPlaying ?? this.isPlaying,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        if (voice != null) 'voice': voice,
        if (speed != null) 'speed': speed,
        if (effectiveSpeed != null) 'effective_speed': effectiveSpeed,
        if (isBoosted) 'is_boosted': isBoosted,
        if (pitch != null) 'pitch': pitch,
        if (duration > 0) 'duration': duration,
        if (startSec > 0) 'start_sec': startSec,
        if (endSec > 0) 'end_sec': endSec,
        if (wordCount > 0) 'word_count': wordCount,
      };

  factory TtsSegmentItem.fromJson(Map<String, dynamic> json) {
    final sSec = (json['start_sec'] as num?)?.toDouble() ?? (json['start'] as num?)?.toDouble() ?? 0.0;
    final eSec = (json['end_sec'] as num?)?.toDouble() ?? (json['end'] as num?)?.toDouble() ?? 0.0;
    final dur = (json['duration'] as num?)?.toDouble() ?? (eSec > sSec ? eSec - sSec : 0.0);
    final wCount = (json['word_count'] as num?)?.toInt() ?? (json['text'] as String? ?? '').trim().split(RegExp(r'\s+')).length;
    final effSpd = (json['effective_speed'] as num?)?.toDouble() ?? (json['speed'] as num?)?.toDouble();
    final boosted = json['is_boosted'] as bool? ?? false;

    return TtsSegmentItem(
      id: json['id'] as int? ?? 1,
      text: json['text'] as String? ?? '',
      voice: json['voice'] as String?,
      speed: (json['speed'] as num?)?.toDouble(),
      effectiveSpeed: effSpd,
      isBoosted: boosted,
      pitch: json['pitch'] as int?,
      duration: dur,
      startSec: sSec,
      endSec: eSec,
      wordCount: wCount,
      audioPath: json['audio_file'] as String? ?? json['audioPath'] as String?,
    );
  }
}

/// Trạng thái tổng thể của màn hình TTS Studio
class TtsStudioState {
  final String rawScript;
  final List<TtsSegmentItem> segments;
  final List<TtsVoice> availableVoices;
  final String defaultVoice;
  final double defaultSpeed;
  final int defaultPitch;
  final double pauseSec;
  final bool isTimelineLocked;
  final bool isSplitting;
  final bool isRenderingFull;
  final double progress;
  final String? fullAudioPath;
  final String? fullSrtPath;
  final double totalDuration;
  final int? currentlyPlayingSegmentId;
  final bool isPlayingFull;
  final String statusMessage;

  const TtsStudioState({
    this.rawScript = '',
    this.segments = const [],
    this.availableVoices = TtsVoice.defaultVoices,
    this.defaultVoice = 'en-US-JennyNeural',
    this.defaultSpeed = 1.0,
    this.defaultPitch = 0,
    this.pauseSec = 0.35,
    this.isTimelineLocked = false,
    this.isSplitting = false,
    this.isRenderingFull = false,
    this.progress = 0.0,
    this.fullAudioPath,
    this.fullSrtPath,
    this.totalDuration = 0.0,
    this.currentlyPlayingSegmentId,
    this.isPlayingFull = false,
    this.statusMessage = 'Sẵn sàng tạo giọng đọc',
  });

  TtsStudioState copyWith({
    String? rawScript,
    List<TtsSegmentItem>? segments,
    List<TtsVoice>? availableVoices,
    String? defaultVoice,
    double? defaultSpeed,
    int? defaultPitch,
    double? pauseSec,
    bool? isTimelineLocked,
    bool? isSplitting,
    bool? isRenderingFull,
    double? progress,
    String? fullAudioPath,
    String? fullSrtPath,
    double? totalDuration,
    int? currentlyPlayingSegmentId,
    bool? isPlayingFull,
    String? statusMessage,
    bool clearPlayingSegment = false,
  }) {
    return TtsStudioState(
      rawScript: rawScript ?? this.rawScript,
      segments: segments ?? this.segments,
      availableVoices: availableVoices ?? this.availableVoices,
      defaultVoice: defaultVoice ?? this.defaultVoice,
      defaultSpeed: defaultSpeed ?? this.defaultSpeed,
      defaultPitch: defaultPitch ?? this.defaultPitch,
      pauseSec: pauseSec ?? this.pauseSec,
      isTimelineLocked: isTimelineLocked ?? this.isTimelineLocked,
      isSplitting: isSplitting ?? this.isSplitting,
      isRenderingFull: isRenderingFull ?? this.isRenderingFull,
      progress: progress ?? this.progress,
      fullAudioPath: fullAudioPath ?? this.fullAudioPath,
      fullSrtPath: fullSrtPath ?? this.fullSrtPath,
      totalDuration: totalDuration ?? this.totalDuration,
      currentlyPlayingSegmentId: clearPlayingSegment
          ? null
          : (currentlyPlayingSegmentId ?? this.currentlyPlayingSegmentId),
      isPlayingFull: isPlayingFull ?? this.isPlayingFull,
      statusMessage: statusMessage ?? this.statusMessage,
    );
  }
}
