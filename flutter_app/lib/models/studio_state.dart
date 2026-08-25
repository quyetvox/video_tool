enum StudioToolMode {
  cut,
  split,
  merge,
  composite,
}

class CutSegment {
  final String id;
  final double start;
  final double end;

  const CutSegment({
    required this.id,
    required this.start,
    required this.end,
  });

  CutSegment copyWith({double? start, double? end}) {
    return CutSegment(
      id: id,
      start: start ?? this.start,
      end: end ?? this.end,
    );
  }

  Map<String, dynamic> toJson() => {'id': id, 'start': start, 'end': end};
  factory CutSegment.fromJson(Map<String, dynamic> json) => CutSegment(
        id: json['id'] as String,
        start: (json['start'] as num).toDouble(),
        end: (json['end'] as num).toDouble(),
      );
}

class SplitSegment {
  final String id;
  final String name;
  final double start;
  final double end;

  const SplitSegment({
    required this.id,
    required this.name,
    required this.start,
    required this.end,
  });

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'start': start, 'end': end};
  factory SplitSegment.fromJson(Map<String, dynamic> json) => SplitSegment(
        id: json['id'] as String,
        name: json['name'] as String,
        start: (json['start'] as num).toDouble(),
        end: (json['end'] as num).toDouble(),
      );
}

class MergeItem {
  final String id;
  final String name;
  final String fullPath;
  final int sizeBytes;
  final double duration;

  const MergeItem({
    required this.id,
    required this.name,
    required this.fullPath,
    required this.sizeBytes,
    this.duration = 0.0,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'fullPath': fullPath,
        'sizeBytes': sizeBytes,
        'duration': duration,
      };

  factory MergeItem.fromJson(Map<String, dynamic> json) => MergeItem(
        id: json['id'] as String,
        name: json['name'] as String,
        fullPath: json['fullPath'] as String,
        sizeBytes: json['sizeBytes'] as int? ?? 0,
        duration: (json['duration'] as num?)?.toDouble() ?? 0.0,
      );
}

class OverlayTrack {
  final String id;
  final String name;
  final bool visible;
  final bool locked;

  const OverlayTrack({
    required this.id,
    required this.name,
    this.visible = true,
    this.locked = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'visible': visible,
        'locked': locked,
      };

  factory OverlayTrack.fromJson(Map<String, dynamic> json) => OverlayTrack(
        id: json['id'] as String,
        name: json['name'] as String,
        visible: json['visible'] as bool? ?? true,
        locked: json['locked'] as bool? ?? false,
      );

  OverlayTrack copyWith({String? name, bool? visible, bool? locked}) {
    return OverlayTrack(
      id: id,
      name: name ?? this.name,
      visible: visible ?? this.visible,
      locked: locked ?? this.locked,
    );
  }
}

class OverlayClip {
  final String id;
  final String trackId;
  final String name;
  final String imagePath;
  final double start;
  final double end;
  final double x; // % on player (0..100)
  final double y; // % on player (0..100)
  final double width; // % width (5..80)
  final double height; // % height
  final double opacity; // 0.1..1.0
  final double borderRadius;

  const OverlayClip({
    required this.id,
    required this.trackId,
    required this.name,
    required this.imagePath,
    required this.start,
    required this.end,
    this.x = 10.0,
    this.y = 10.0,
    this.width = 25.0,
    this.height = 25.0,
    this.opacity = 1.0,
    this.borderRadius = 4.0,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'trackId': trackId,
        'name': name,
        'imagePath': imagePath,
        'start': start,
        'end': end,
        'x': x,
        'y': y,
        'width': width,
        'height': height,
        'opacity': opacity,
        'borderRadius': borderRadius,
      };

  factory OverlayClip.fromJson(Map<String, dynamic> json) => OverlayClip(
        id: json['id'] as String,
        trackId: json['trackId'] as String,
        name: json['name'] as String,
        imagePath: json['imagePath'] as String,
        start: (json['start'] as num).toDouble(),
        end: (json['end'] as num).toDouble(),
        x: (json['x'] as num?)?.toDouble() ?? 10.0,
        y: (json['y'] as num?)?.toDouble() ?? 10.0,
        width: (json['width'] as num?)?.toDouble() ?? 25.0,
        height: (json['height'] as num?)?.toDouble() ?? 25.0,
        opacity: (json['opacity'] as num?)?.toDouble() ?? 1.0,
        borderRadius: (json['borderRadius'] as num?)?.toDouble() ?? 4.0,
      );

  OverlayClip copyWith({
    String? trackId,
    String? name,
    String? imagePath,
    double? start,
    double? end,
    double? x,
    double? y,
    double? width,
    double? height,
    double? opacity,
    double? borderRadius,
  }) {
    return OverlayClip(
      id: id,
      trackId: trackId ?? this.trackId,
      name: name ?? this.name,
      imagePath: imagePath ?? this.imagePath,
      start: start ?? this.start,
      end: end ?? this.end,
      x: x ?? this.x,
      y: y ?? this.y,
      width: width ?? this.width,
      height: height ?? this.height,
      opacity: opacity ?? this.opacity,
      borderRadius: borderRadius ?? this.borderRadius,
    );
  }
}

class AudioClip {
  final String id;
  final String trackId; // 'music' | 'sfx'
  final String name;
  final String fullPath;
  final double start;
  final double end;
  final int volume; // 0..200
  final bool muted;

  const AudioClip({
    required this.id,
    required this.trackId,
    required this.name,
    required this.fullPath,
    required this.start,
    required this.end,
    this.volume = 100,
    this.muted = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'trackId': trackId,
        'name': name,
        'fullPath': fullPath,
        'start': start,
        'end': end,
        'volume': volume,
        'muted': muted,
      };

  factory AudioClip.fromJson(Map<String, dynamic> json) => AudioClip(
        id: json['id'] as String,
        trackId: json['trackId'] as String,
        name: json['name'] as String,
        fullPath: json['fullPath'] as String,
        start: (json['start'] as num).toDouble(),
        end: (json['end'] as num).toDouble(),
        volume: json['volume'] as int? ?? 100,
        muted: json['muted'] as bool? ?? false,
      );

  AudioClip copyWith({
    String? trackId,
    String? name,
    String? fullPath,
    double? start,
    double? end,
    int? volume,
    bool? muted,
  }) {
    return AudioClip(
      id: id,
      trackId: trackId ?? this.trackId,
      name: name ?? this.name,
      fullPath: fullPath ?? this.fullPath,
      start: start ?? this.start,
      end: end ?? this.end,
      volume: volume ?? this.volume,
      muted: muted ?? this.muted,
    );
  }
}

class SubtitleClip {
  final String id;
  final double start;
  final double end;
  final String textOrig;
  final String textTrans;

  const SubtitleClip({
    required this.id,
    required this.start,
    required this.end,
    this.textOrig = '',
    this.textTrans = '',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'start': start,
        'end': end,
        'textOrig': textOrig,
        'textTrans': textTrans,
      };

  factory SubtitleClip.fromJson(Map<String, dynamic> json) => SubtitleClip(
        id: json['id'] as String,
        start: (json['start'] as num).toDouble(),
        end: (json['end'] as num).toDouble(),
        textOrig: json['textOrig'] as String? ?? '',
        textTrans: json['textTrans'] as String? ?? '',
      );

  SubtitleClip copyWith({
    double? start,
    double? end,
    String? textOrig,
    String? textTrans,
  }) {
    return SubtitleClip(
      id: id,
      start: start ?? this.start,
      end: end ?? this.end,
      textOrig: textOrig ?? this.textOrig,
      textTrans: textTrans ?? this.textTrans,
    );
  }
}

class SubStyle {
  final String fontFamily;
  final int fontSize;
  final String fontColor;
  final String origColor;
  final bool showMainSub;
  final bool showSubSub;
  final bool showSubBox;
  final String boxBgColor;
  final bool isBold;
  final bool isItalic;
  final bool hasDropShadow;
  final double posX; // % from left (default center 50%)
  final double posY; // % from top (default bottom 85%)
  final double boxWidthPct; // % width of canvas (default 90%)
  final String alignment; // 'bottom' | 'center' | 'top'

  const SubStyle({
    this.fontFamily = 'Be Vietnam Pro',
    this.fontSize = 22,
    this.fontColor = '#facc15',
    this.origColor = '#ffffff',
    this.showMainSub = true,
    this.showSubSub = true,
    this.showSubBox = true,
    this.boxBgColor = 'rgba(0, 0, 0, 0.75)',
    this.isBold = true,
    this.isItalic = false,
    this.hasDropShadow = true,
    this.posX = 50.0,
    this.posY = 85.0,
    this.boxWidthPct = 90.0,
    this.alignment = 'bottom',
  });

  SubStyle copyWith({
    String? fontFamily,
    int? fontSize,
    String? fontColor,
    String? origColor,
    bool? showMainSub,
    bool? showSubSub,
    bool? showSubBox,
    String? boxBgColor,
    bool? isBold,
    bool? isItalic,
    bool? hasDropShadow,
    double? posX,
    double? posY,
    double? boxWidthPct,
    String? alignment,
  }) {
    return SubStyle(
      fontFamily: fontFamily ?? this.fontFamily,
      fontSize: fontSize ?? this.fontSize,
      fontColor: fontColor ?? this.fontColor,
      origColor: origColor ?? this.origColor,
      showMainSub: showMainSub ?? this.showMainSub,
      showSubSub: showSubSub ?? this.showSubSub,
      showSubBox: showSubBox ?? this.showSubBox,
      boxBgColor: boxBgColor ?? this.boxBgColor,
      isBold: isBold ?? this.isBold,
      isItalic: isItalic ?? this.isItalic,
      hasDropShadow: hasDropShadow ?? this.hasDropShadow,
      posX: posX ?? this.posX,
      posY: posY ?? this.posY,
      boxWidthPct: boxWidthPct ?? this.boxWidthPct,
      alignment: alignment ?? this.alignment,
    );
  }

  Map<String, dynamic> toJson() => {
        'fontFamily': fontFamily,
        'fontSize': fontSize,
        'fontColor': fontColor,
        'origColor': origColor,
        'showMainSub': showMainSub,
        'showSubSub': showSubSub,
        'showSubBox': showSubBox,
        'boxBgColor': boxBgColor,
        'isBold': isBold,
        'isItalic': isItalic,
        'hasDropShadow': hasDropShadow,
        'posX': posX,
        'posY': posY,
        'boxWidthPct': boxWidthPct,
        'alignment': alignment,
      };

  factory SubStyle.fromJson(Map<String, dynamic> json) => SubStyle(
        fontFamily: json['fontFamily'] as String? ?? 'Be Vietnam Pro',
        fontSize: json['fontSize'] as int? ?? 22,
        fontColor: json['fontColor'] as String? ?? '#facc15',
        origColor: json['origColor'] as String? ?? '#ffffff',
        showMainSub: json['showMainSub'] as bool? ?? true,
        showSubSub: json['showSubSub'] as bool? ?? true,
        showSubBox: json['showSubBox'] as bool? ?? true,
        boxBgColor: json['boxBgColor'] as String? ?? 'rgba(0, 0, 0, 0.75)',
        isBold: json['isBold'] as bool? ?? true,
        isItalic: json['isItalic'] as bool? ?? false,
        hasDropShadow: json['hasDropShadow'] as bool? ?? true,
        posX: (json['posX'] as num?)?.toDouble() ?? 50.0,
        posY: (json['posY'] as num?)?.toDouble() ?? 85.0,
        boxWidthPct: (json['boxWidthPct'] as num?)?.toDouble() ?? 90.0,
        alignment: json['alignment'] as String? ?? 'bottom',
      );
}

class AudioMixState {
  final int origVolume; // 0..200
  final int musicVolume;
  final int sfxVolume;
  final bool origMuted;
  final bool musicMuted;
  final bool sfxMuted;

  const AudioMixState({
    this.origVolume = 100,
    this.musicVolume = 80,
    this.sfxVolume = 60,
    this.origMuted = false,
    this.musicMuted = false,
    this.sfxMuted = false,
  });

  Map<String, dynamic> toJson() => {
        'origVolume': origVolume,
        'musicVolume': musicVolume,
        'sfxVolume': sfxVolume,
        'origMuted': origMuted,
        'musicMuted': musicMuted,
        'sfxMuted': sfxMuted,
      };

  factory AudioMixState.fromJson(Map<String, dynamic> json) => AudioMixState(
        origVolume: json['origVolume'] as int? ?? 100,
        musicVolume: json['musicVolume'] as int? ?? 80,
        sfxVolume: json['sfxVolume'] as int? ?? 60,
        origMuted: json['origMuted'] as bool? ?? false,
        musicMuted: json['musicMuted'] as bool? ?? false,
        sfxMuted: json['sfxMuted'] as bool? ?? false,
      );

  AudioMixState copyWith({
    int? origVolume,
    int? musicVolume,
    int? sfxVolume,
    bool? origMuted,
    bool? musicMuted,
    bool? sfxMuted,
  }) {
    return AudioMixState(
      origVolume: origVolume ?? this.origVolume,
      musicVolume: musicVolume ?? this.musicVolume,
      sfxVolume: sfxVolume ?? this.sfxVolume,
      origMuted: origMuted ?? this.origMuted,
      musicMuted: musicMuted ?? this.musicMuted,
      sfxMuted: sfxMuted ?? this.sfxMuted,
    );
  }
}

class StudioSnapshot {
  final String id;
  final String label;
  final String time;
  final List<CutSegment> cutSegments;
  final List<SplitSegment> splitSegments;
  final List<MergeItem> mergePlaylist;
  final List<OverlayTrack> overlayTracks;
  final List<OverlayClip> overlayClips;
  final List<AudioClip> audioClips;
  final List<SubtitleClip> subtitles;
  final double currentJunkStart;
  final double currentJunkEnd;
  final bool showCutBox;
  final SubStyle subStyle;
  final AudioMixState mixState;
  final String? selectedClipId;
  final String? selectedTrackId;

  const StudioSnapshot({
    required this.id,
    required this.label,
    required this.time,
    this.cutSegments = const [],
    this.splitSegments = const [],
    this.mergePlaylist = const [],
    this.overlayTracks = const [
      OverlayTrack(id: 'track-ov-1', name: 'Lớp phủ 1', visible: true, locked: false)
    ],
    this.overlayClips = const [],
    this.audioClips = const [],
    this.subtitles = const [],
    this.currentJunkStart = 5.0,
    this.currentJunkEnd = 15.0,
    this.showCutBox = true,
    this.subStyle = const SubStyle(),
    this.mixState = const AudioMixState(),
    this.selectedClipId,
    this.selectedTrackId,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'time': time,
        'cutSegments': cutSegments.map((c) => c.toJson()).toList(),
        'splitSegments': splitSegments.map((s) => s.toJson()).toList(),
        'mergePlaylist': mergePlaylist.map((m) => m.toJson()).toList(),
        'overlayTracks': overlayTracks.map((t) => t.toJson()).toList(),
        'overlayClips': overlayClips.map((c) => c.toJson()).toList(),
        'audioClips': audioClips.map((a) => a.toJson()).toList(),
        'subtitles': subtitles.map((s) => s.toJson()).toList(),
        'currentJunkStart': currentJunkStart,
        'currentJunkEnd': currentJunkEnd,
        'showCutBox': showCutBox,
        'subStyle': subStyle.toJson(),
        'mixState': mixState.toJson(),
        'selectedClipId': selectedClipId,
        'selectedTrackId': selectedTrackId,
      };

  factory StudioSnapshot.fromJson(Map<String, dynamic> json) => StudioSnapshot(
        id: json['id'] as String? ?? 'snap_${DateTime.now().millisecondsSinceEpoch}',
        label: json['label'] as String? ?? 'Khôi phục bản nháp',
        time: json['time'] as String? ?? '',
        cutSegments: (json['cutSegments'] as List<dynamic>?)
                ?.map((e) => CutSegment.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        splitSegments: (json['splitSegments'] as List<dynamic>?)
                ?.map((e) => SplitSegment.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        mergePlaylist: (json['mergePlaylist'] as List<dynamic>?)
                ?.map((e) => MergeItem.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        overlayTracks: (json['overlayTracks'] as List<dynamic>?)
                ?.map((e) => OverlayTrack.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [OverlayTrack(id: 'track-ov-1', name: 'Lớp phủ 1', visible: true, locked: false)],
        overlayClips: (json['overlayClips'] as List<dynamic>?)
                ?.map((e) => OverlayClip.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        audioClips: (json['audioClips'] as List<dynamic>?)
                ?.map((e) => AudioClip.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        subtitles: (json['subtitles'] as List<dynamic>?)
                ?.map((e) => SubtitleClip.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        currentJunkStart: (json['currentJunkStart'] as num?)?.toDouble() ?? 5.0,
        currentJunkEnd: (json['currentJunkEnd'] as num?)?.toDouble() ?? 15.0,
        showCutBox: json['showCutBox'] as bool? ?? true,
        subStyle: json['subStyle'] != null
            ? SubStyle.fromJson(json['subStyle'] as Map<String, dynamic>)
            : const SubStyle(),
        mixState: json['mixState'] != null
            ? AudioMixState.fromJson(json['mixState'] as Map<String, dynamic>)
            : const AudioMixState(),
        selectedClipId: json['selectedClipId'] as String?,
        selectedTrackId: json['selectedTrackId'] as String?,
      );

  StudioSnapshot copyWith({
    String? id,
    String? label,
    String? time,
    List<CutSegment>? cutSegments,
    List<SplitSegment>? splitSegments,
    List<MergeItem>? mergePlaylist,
    List<OverlayTrack>? overlayTracks,
    List<OverlayClip>? overlayClips,
    List<AudioClip>? audioClips,
    List<SubtitleClip>? subtitles,
    double? currentJunkStart,
    double? currentJunkEnd,
    bool? showCutBox,
    SubStyle? subStyle,
    AudioMixState? mixState,
    String? selectedClipId,
    bool clearSelectedClip = false,
    String? selectedTrackId,
  }) {
    return StudioSnapshot(
      id: id ?? this.id,
      label: label ?? this.label,
      time: time ?? this.time,
      cutSegments: cutSegments ?? this.cutSegments,
      splitSegments: splitSegments ?? this.splitSegments,
      mergePlaylist: mergePlaylist ?? this.mergePlaylist,
      overlayTracks: overlayTracks ?? this.overlayTracks,
      overlayClips: overlayClips ?? this.overlayClips,
      audioClips: audioClips ?? this.audioClips,
      subtitles: subtitles ?? this.subtitles,
      currentJunkStart: currentJunkStart ?? this.currentJunkStart,
      currentJunkEnd: currentJunkEnd ?? this.currentJunkEnd,
      showCutBox: showCutBox ?? this.showCutBox,
      subStyle: subStyle ?? this.subStyle,
      mixState: mixState ?? this.mixState,
      selectedClipId: clearSelectedClip ? null : (selectedClipId ?? this.selectedClipId),
      selectedTrackId: selectedTrackId ?? this.selectedTrackId,
    );
  }
}
