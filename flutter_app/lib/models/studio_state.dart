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

class StudioAudioTrack {
  final String id;
  final String name;
  final bool muted;
  final int volume; // 0..200

  const StudioAudioTrack({
    required this.id,
    required this.name,
    this.muted = false,
    this.volume = 100,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'muted': muted,
        'volume': volume,
      };

  factory StudioAudioTrack.fromJson(Map<String, dynamic> json) => StudioAudioTrack(
        id: json['id'] as String,
        name: json['name'] as String,
        muted: json['muted'] as bool? ?? false,
        volume: (json['volume'] as num?)?.toInt() ?? 100,
      );

  StudioAudioTrack copyWith({String? name, bool? muted, int? volume}) {
    return StudioAudioTrack(
      id: id,
      name: name ?? this.name,
      muted: muted ?? this.muted,
      volume: volume ?? this.volume,
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

  factory AudioClip.fromJson(Map<String, dynamic> json) {
    final rawVol = json['volume'] as int? ?? 100;
    // Auto-normalize legacy draft hardcoded defaults (60 for sfx, 80 for music) to 100
    final vol = (rawVol == 60 || rawVol == 80) ? 100 : rawVol;
    var trId = json['trackId'] as String? ?? 'track-au-1';
    if (trId == 'music') trId = 'track-au-1';
    if (trId == 'sfx') trId = 'track-au-2';
    return AudioClip(
      id: json['id'] as String,
      trackId: trId,
      name: json['name'] as String,
      fullPath: json['fullPath'] as String,
      start: (json['start'] as num).toDouble(),
      end: (json['end'] as num).toDouble(),
      volume: vol,
      muted: json['muted'] as bool? ?? false,
    );
  }

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
  final String text; // Tiếng gốc (alias textOrig)
  final String textVi; // Tiếng dịch (alias textTrans)
  final String textSecondary;
  final String speaker;
  final String gender;

  SubtitleClip({
    required this.id,
    required this.start,
    required this.end,
    String text = '',
    String textVi = '',
    this.textSecondary = '',
    this.speaker = '',
    this.gender = '',
    String? textOrig,
    String? textTrans,
  })  : text = (text.isNotEmpty ? text : (textOrig ?? '')),
        textVi = (textVi.isNotEmpty ? textVi : (textTrans ?? ''));

  String get textOrig => text;
  String get textTrans => textVi;

  String get displayText {
    if (textVi.trim().isNotEmpty) return textVi.trim();
    if (text.trim().isNotEmpty) return text.trim();
    return textSecondary.trim();
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'start': double.parse(start.toStringAsFixed(3)),
        'end': double.parse(end.toStringAsFixed(3)),
        'text': text,
        'text_vi': textVi,
        'text_secondary': textSecondary,
        'speaker': speaker,
        'gender': gender,
        // Backward-compat dual mapping
        'textOrig': text,
        'textTrans': textVi,
      };

  factory SubtitleClip.fromJson(Map<String, dynamic> json) {
    final rawOrig = json['text'] as String? ??
        json['textOrig'] as String? ??
        json['orig_text'] as String? ??
        '';
    final rawTrans = json['text_vi'] as String? ??
        json['translated_text'] as String? ??
        json['textTrans'] as String? ??
        '';
    final rawSec = json['text_secondary'] as String? ??
        json['secondary'] as String? ??
        '';
    final rawSpeaker = json['speaker'] as String? ?? '';
    final rawGender = json['gender'] as String? ?? '';
    final rawId = json['id']?.toString() ?? 'sub_${DateTime.now().millisecondsSinceEpoch}';

    return SubtitleClip(
      id: rawId,
      start: (json['start'] as num?)?.toDouble() ?? 0.0,
      end: (json['end'] as num?)?.toDouble() ?? 2.0,
      text: rawOrig,
      textVi: rawTrans,
      textSecondary: rawSec,
      speaker: rawSpeaker,
      gender: rawGender,
    );
  }

  SubtitleClip copyWith({
    String? id,
    double? start,
    double? end,
    String? text,
    String? textVi,
    String? textSecondary,
    String? speaker,
    String? gender,
    String? textOrig,
    String? textTrans,
  }) {
    return SubtitleClip(
      id: id ?? this.id,
      start: start ?? this.start,
      end: end ?? this.end,
      text: text ?? textOrig ?? this.text,
      textVi: textVi ?? textTrans ?? this.textVi,
      textSecondary: textSecondary ?? this.textSecondary,
      speaker: speaker ?? this.speaker,
      gender: gender ?? this.gender,
    );
  }
}


class StudioInpaintConfig {
  final bool enabled;
  final List<double> region; // [ymin, xmin, ymax, xmax] (0..1)
  final String mode; // 'box_color' | 'blur'
  final String color; // hex '#000000'
  final double opacity; // 0.0..1.0
  final String engine; // 'box_color' | 'ffmpeg_blur' | 'apple_vision_inpaint' | 'opencv'
  final int blurRadius; // 5..40
  final String method; // 'vertical_gradient' | 'navier_stokes' | 'telea'
  final String borderColor;
  final int borderWidth;
  final int borderRadius;
  final double paddingY;
  final double boxLeadIn;
  final double boxLeadOut;
  final bool watermarkEnabled;
  final String watermarkImagePath;
  final List<double> watermarkRegion;
  final double watermarkOpacity;

  const StudioInpaintConfig({
    this.enabled = false,
    this.region = const [0.72, 0.05, 0.88, 0.95],
    this.mode = 'box_color',
    this.color = '#000000',
    this.opacity = 1.0,
    this.engine = 'box_color',
    this.blurRadius = 15,
    this.method = 'vertical_gradient',
    this.borderColor = '#40ffffff',
    this.borderWidth = 1,
    this.borderRadius = 8,
    this.paddingY = 0.02,
    this.boxLeadIn = 0.25,
    this.boxLeadOut = 0.15,
    this.watermarkEnabled = false,
    this.watermarkImagePath = '',
    this.watermarkRegion = const [0.02, 0.85, 0.05, 0.95],
    this.watermarkOpacity = 1.0,
  });

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'region': region,
        'mode': mode,
        'color': color,
        'opacity': opacity,
        'engine': engine,
        'blur_radius': blurRadius,
        'method': method,
        'border_color': borderColor,
        'border_width': borderWidth,
        'border_radius': borderRadius,
        'padding_y': paddingY,
        'box_lead_in': boxLeadIn,
        'box_lead_out': boxLeadOut,
        'watermark_enabled': watermarkEnabled,
        'watermark_image_path': watermarkImagePath,
        'watermark_region': watermarkRegion,
        'watermark_opacity': watermarkOpacity,
      };

  factory StudioInpaintConfig.fromJson(Map<String, dynamic> json) {
    return StudioInpaintConfig(
      enabled: json['enabled'] as bool? ?? false,
      region: (json['region'] as List<dynamic>?)
              ?.map((e) => (e as num).toDouble())
              .toList() ??
          const [0.72, 0.05, 0.88, 0.95],
      mode: json['mode'] as String? ?? 'box_color',
      color: json['color'] as String? ?? '#000000',
      opacity: (json['opacity'] as num?)?.toDouble() ?? 1.0,
      engine: json['engine'] as String? ?? (json['mode'] == 'blur' ? 'ffmpeg_blur' : 'box_color'),
      blurRadius: (json['blur_radius'] as num?)?.toInt() ?? 15,
      method: json['method'] as String? ?? 'vertical_gradient',
      borderColor: json['border_color'] as String? ?? '#40ffffff',
      borderWidth: (json['border_width'] as num?)?.toInt() ?? 1,
      borderRadius: (json['border_radius'] as num?)?.toInt() ?? 8,
      paddingY: (json['padding_y'] as num?)?.toDouble() ?? 0.02,
      boxLeadIn: (json['box_lead_in'] as num?)?.toDouble() ?? 0.25,
      boxLeadOut: (json['box_lead_out'] as num?)?.toDouble() ?? 0.15,
      watermarkEnabled: json['watermark_enabled'] as bool? ?? false,
      watermarkImagePath: json['watermark_image_path'] as String? ?? '',
      watermarkRegion: (json['watermark_region'] as List<dynamic>?)
              ?.map((e) => (e as num).toDouble())
              .toList() ??
          const [0.02, 0.85, 0.05, 0.95],
      watermarkOpacity: (json['watermark_opacity'] as num?)?.toDouble() ?? 1.0,
    );
  }

  StudioInpaintConfig copyWith({
    bool? enabled,
    List<double>? region,
    String? mode,
    String? color,
    double? opacity,
    String? engine,
    int? blurRadius,
    String? method,
    String? borderColor,
    int? borderWidth,
    int? borderRadius,
    double? paddingY,
    double? boxLeadIn,
    double? boxLeadOut,
    bool? watermarkEnabled,
    String? watermarkImagePath,
    List<double>? watermarkRegion,
    double? watermarkOpacity,
  }) {
    return StudioInpaintConfig(
      enabled: enabled ?? this.enabled,
      region: region ?? this.region,
      mode: mode ?? this.mode,
      color: color ?? this.color,
      opacity: opacity ?? this.opacity,
      engine: engine ?? this.engine,
      blurRadius: blurRadius ?? this.blurRadius,
      method: method ?? this.method,
      borderColor: borderColor ?? this.borderColor,
      borderWidth: borderWidth ?? this.borderWidth,
      borderRadius: borderRadius ?? this.borderRadius,
      paddingY: paddingY ?? this.paddingY,
      boxLeadIn: boxLeadIn ?? this.boxLeadIn,
      boxLeadOut: boxLeadOut ?? this.boxLeadOut,
      watermarkEnabled: watermarkEnabled ?? this.watermarkEnabled,
      watermarkImagePath: watermarkImagePath ?? this.watermarkImagePath,
      watermarkRegion: watermarkRegion ?? this.watermarkRegion,
      watermarkOpacity: watermarkOpacity ?? this.watermarkOpacity,
    );
  }
}

class SubStyle {
  final String fontFamily;
  final String secondaryFontFamily;
  final int fontSize;
  final int secondaryFontSize;
  final String fontColor;
  final String origColor;
  final bool showMainSub;
  final bool showSubSub;
  final bool showSubBox;
  final String boxBgColor;
  final double boxOpacity;
  final double boxBorderRadius;
  final String boxBorderColor;
  final double boxBorderWidth;
  final double boxPaddingX;
  final double boxPaddingY;
  final double boxGap;
  final bool boxSplit;
  final bool separateSecPos;
  final double secPosX;
  final double secPosY;
  final double secBoxWidthPct;
  final bool isBold;
  final bool isItalic;
  final bool hasDropShadow;
  final double posX; // % from left (default center 50%)
  final double posY; // % from top (default bottom 85%)
  final double boxWidthPct; // % width of canvas (default 90%)
  final String alignment; // 'bottom' | 'center' | 'top'
  final List<double>? subtitleRegion; // [ymin, xmin, ymax, xmax] (0..1)
  final List<double>? subtitleSecondaryRegion; // [ymin, xmin, ymax, xmax] (0..1)

  const SubStyle({
    this.fontFamily = 'Be Vietnam Pro',
    this.secondaryFontFamily = '',
    this.fontSize = 22,
    this.secondaryFontSize = 18,
    this.fontColor = '#facc15',
    this.origColor = '#ffffff',
    this.showMainSub = true,
    this.showSubSub = true,
    this.showSubBox = true,
    this.boxBgColor = '#000000',
    this.boxOpacity = 0.75,
    this.boxBorderRadius = 6.0,
    this.boxBorderColor = '#40ffffff',
    this.boxBorderWidth = 0.0,
    this.boxPaddingX = 10.0,
    this.boxPaddingY = 6.0,
    this.boxGap = 8.0,
    this.boxSplit = false,
    this.separateSecPos = false,
    this.secPosX = 50.0,
    this.secPosY = 15.0,
    this.secBoxWidthPct = 90.0,
    this.isBold = true,
    this.isItalic = false,
    this.hasDropShadow = true,
    this.posX = 50.0,
    this.posY = 85.0,
    this.boxWidthPct = 90.0,
    this.alignment = 'bottom',
    this.subtitleRegion,
    this.subtitleSecondaryRegion,
  });

  /// Effective region for primary subtitle [ymin, xmin, ymax, xmax] (0..1)
  List<double> get effectiveSubtitleRegion {
    if (subtitleRegion != null && subtitleRegion!.length == 4) {
      return subtitleRegion!;
    }
    final w = (boxWidthPct / 100.0).clamp(0.1, 1.0);
    final xmin = ((posX / 100.0) - w / 2).clamp(0.0, 1.0 - w);
    final ymin = (posY / 100.0).clamp(0.0, 0.95);
    final ymax = (ymin + 0.10).clamp(ymin + 0.02, 1.0);
    final xmax = (xmin + w).clamp(xmin + 0.02, 1.0);
    return [
      double.parse(ymin.toStringAsFixed(3)),
      double.parse(xmin.toStringAsFixed(3)),
      double.parse(ymax.toStringAsFixed(3)),
      double.parse(xmax.toStringAsFixed(3)),
    ];
  }

  /// Effective region for secondary subtitle [ymin, xmin, ymax, xmax] (0..1)
  List<double> get effectiveSubtitleSecondaryRegion {
    if (subtitleSecondaryRegion != null && subtitleSecondaryRegion!.length == 4) {
      return subtitleSecondaryRegion!;
    }
    final w = (secBoxWidthPct / 100.0).clamp(0.1, 1.0);
    final xmin = ((secPosX / 100.0) - w / 2).clamp(0.0, 1.0 - w);
    final ymin = (secPosY / 100.0).clamp(0.0, 0.95);
    final ymax = (ymin + 0.08).clamp(ymin + 0.02, 1.0);
    final xmax = (xmin + w).clamp(xmin + 0.02, 1.0);
    return [
      double.parse(ymin.toStringAsFixed(3)),
      double.parse(xmin.toStringAsFixed(3)),
      double.parse(ymax.toStringAsFixed(3)),
      double.parse(xmax.toStringAsFixed(3)),
    ];
  }

  SubStyle copyWith({
    String? fontFamily,
    String? secondaryFontFamily,
    int? fontSize,
    int? secondaryFontSize,
    String? fontColor,
    String? origColor,
    bool? showMainSub,
    bool? showSubSub,
    bool? showSubBox,
    String? boxBgColor,
    double? boxOpacity,
    double? boxBorderRadius,
    String? boxBorderColor,
    double? boxBorderWidth,
    double? boxPaddingX,
    double? boxPaddingY,
    double? boxGap,
    bool? boxSplit,
    bool? separateSecPos,
    double? secPosX,
    double? secPosY,
    double? secBoxWidthPct,
    bool? isBold,
    bool? isItalic,
    bool? hasDropShadow,
    double? posX,
    double? posY,
    double? boxWidthPct,
    String? alignment,
    List<double>? subtitleRegion,
    bool setSubtitleRegionNull = false,
    List<double>? subtitleSecondaryRegion,
    bool setSubtitleSecondaryRegionNull = false,
  }) {
    return SubStyle(
      fontFamily: fontFamily ?? this.fontFamily,
      secondaryFontFamily: secondaryFontFamily ?? this.secondaryFontFamily,
      fontSize: fontSize ?? this.fontSize,
      secondaryFontSize: secondaryFontSize ?? this.secondaryFontSize,
      fontColor: fontColor ?? this.fontColor,
      origColor: origColor ?? this.origColor,
      showMainSub: showMainSub ?? this.showMainSub,
      showSubSub: showSubSub ?? this.showSubSub,
      showSubBox: showSubBox ?? this.showSubBox,
      boxBgColor: boxBgColor ?? this.boxBgColor,
      boxOpacity: boxOpacity ?? this.boxOpacity,
      boxBorderRadius: boxBorderRadius ?? this.boxBorderRadius,
      boxBorderColor: boxBorderColor ?? this.boxBorderColor,
      boxBorderWidth: boxBorderWidth ?? this.boxBorderWidth,
      boxPaddingX: boxPaddingX ?? this.boxPaddingX,
      boxPaddingY: boxPaddingY ?? this.boxPaddingY,
      boxGap: boxGap ?? this.boxGap,
      boxSplit: boxSplit ?? this.boxSplit,
      separateSecPos: separateSecPos ?? this.separateSecPos,
      secPosX: secPosX ?? this.secPosX,
      secPosY: secPosY ?? this.secPosY,
      secBoxWidthPct: secBoxWidthPct ?? this.secBoxWidthPct,
      isBold: isBold ?? this.isBold,
      isItalic: isItalic ?? this.isItalic,
      hasDropShadow: hasDropShadow ?? this.hasDropShadow,
      posX: posX ?? this.posX,
      posY: posY ?? this.posY,
      boxWidthPct: boxWidthPct ?? this.boxWidthPct,
      alignment: alignment ?? this.alignment,
      subtitleRegion: setSubtitleRegionNull ? null : (subtitleRegion ?? this.subtitleRegion),
      subtitleSecondaryRegion: setSubtitleSecondaryRegionNull
          ? null
          : (subtitleSecondaryRegion ?? this.subtitleSecondaryRegion),
    );
  }

  Map<String, dynamic> toJson() => {
        'fontFamily': fontFamily,
        'secondaryFontFamily': secondaryFontFamily,
        'fontSize': fontSize,
        'secondaryFontSize': secondaryFontSize,
        'fontColor': fontColor,
        'origColor': origColor,
        'showMainSub': showMainSub,
        'showSubSub': showSubSub,
        'showSubBox': showSubBox,
        'boxBgColor': boxBgColor,
        'boxOpacity': boxOpacity,
        'boxBorderRadius': boxBorderRadius,
        'boxBorderColor': boxBorderColor,
        'boxBorderWidth': boxBorderWidth,
        'boxPaddingX': boxPaddingX,
        'boxPaddingY': boxPaddingY,
        'boxGap': boxGap,
        'boxSplit': boxSplit,
        'separateSecPos': separateSecPos,
        'secPosX': secPosX,
        'secPosY': secPosY,
        'secBoxWidthPct': secBoxWidthPct,
        'isBold': isBold,
        'isItalic': isItalic,
        'hasDropShadow': hasDropShadow,
        'posX': posX,
        'posY': posY,
        'boxWidthPct': boxWidthPct,
        'alignment': alignment,
        'subtitleRegion': subtitleRegion,
        'subtitleSecondaryRegion': subtitleSecondaryRegion,
      };

  factory SubStyle.fromJson(Map<String, dynamic> json) {
    // Parse legacy rgba string if present
    String rawColor = json['boxBgColor'] as String? ?? '#000000';
    double parsedOpacity = (json['boxOpacity'] as num?)?.toDouble() ?? 0.75;
    if (rawColor.startsWith('rgba(')) {
      rawColor = '#000000';
      parsedOpacity = 0.75;
    }

    final mainFs = json['fontSize'] as int? ?? 22;
    final secFs = json['secondaryFontSize'] as int? ?? (mainFs - 4).clamp(10, 48);

    List<double>? parsedSubRegion;
    if (json['subtitleRegion'] != null && json['subtitleRegion'] is List) {
      parsedSubRegion = (json['subtitleRegion'] as List)
          .map((e) => (e as num).toDouble())
          .toList();
    }

    List<double>? parsedSubSecRegion;
    if (json['subtitleSecondaryRegion'] != null && json['subtitleSecondaryRegion'] is List) {
      parsedSubSecRegion = (json['subtitleSecondaryRegion'] as List)
          .map((e) => (e as num).toDouble())
          .toList();
    }

    return SubStyle(
      fontFamily: json['fontFamily'] as String? ?? 'Be Vietnam Pro',
      secondaryFontFamily: json['secondaryFontFamily'] as String? ?? '',
      fontSize: mainFs,
      secondaryFontSize: secFs,
      fontColor: json['fontColor'] as String? ?? '#facc15',
      origColor: json['origColor'] as String? ?? '#ffffff',
      showMainSub: json['showMainSub'] as bool? ?? true,
      showSubSub: json['showSubSub'] as bool? ?? true,
      showSubBox: json['showSubBox'] as bool? ?? true,
      boxBgColor: rawColor,
      boxOpacity: parsedOpacity,
      boxBorderRadius: (json['boxBorderRadius'] as num?)?.toDouble() ?? 6.0,
      boxBorderColor: json['boxBorderColor'] as String? ?? '#40ffffff',
      boxBorderWidth: (json['boxBorderWidth'] as num?)?.toDouble() ?? 0.0,
      boxPaddingX: (json['boxPaddingX'] as num?)?.toDouble() ?? 10.0,
      boxPaddingY: (json['boxPaddingY'] as num?)?.toDouble() ?? 6.0,
      boxGap: (json['boxGap'] as num?)?.toDouble() ?? 8.0,
      boxSplit: json['boxSplit'] as bool? ?? false,
      separateSecPos: json['separateSecPos'] as bool? ?? false,
      secPosX: (json['secPosX'] as num?)?.toDouble() ?? 50.0,
      secPosY: (json['secPosY'] as num?)?.toDouble() ?? 15.0,
      secBoxWidthPct: (json['secBoxWidthPct'] as num?)?.toDouble() ?? 90.0,
      isBold: json['isBold'] as bool? ?? true,
      isItalic: json['isItalic'] as bool? ?? false,
      hasDropShadow: json['hasDropShadow'] as bool? ?? true,
      posX: (json['posX'] as num?)?.toDouble() ?? 50.0,
      posY: (json['posY'] as num?)?.toDouble() ?? 85.0,
      boxWidthPct: (json['boxWidthPct'] as num?)?.toDouble() ?? 90.0,
      alignment: json['alignment'] as String? ?? 'bottom',
      subtitleRegion: parsedSubRegion,
      subtitleSecondaryRegion: parsedSubSecRegion,
    );
  }
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
  final List<StudioAudioTrack> audioTracks;
  final List<AudioClip> audioClips;
  final List<SubtitleClip> subtitles;
  final double currentJunkStart;
  final double currentJunkEnd;
  final bool showCutBox;
  final SubStyle subStyle;
  final StudioInpaintConfig inpaintConfig;
  final AudioMixState mixState;
  final double videoSpeed;
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
    this.audioTracks = const [
      StudioAudioTrack(id: 'track-au-1', name: 'Âm thanh 1')
    ],
    this.audioClips = const [],
    this.subtitles = const [],
    this.currentJunkStart = 5.0,
    this.currentJunkEnd = 15.0,
    this.showCutBox = true,
    this.subStyle = const SubStyle(),
    this.inpaintConfig = const StudioInpaintConfig(),
    this.mixState = const AudioMixState(),
    this.videoSpeed = 1.0,
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
        'audioTracks': audioTracks.map((t) => t.toJson()).toList(),
        'audioClips': audioClips.map((a) => a.toJson()).toList(),
        'subtitles': subtitles.map((s) => s.toJson()).toList(),
        'currentJunkStart': currentJunkStart,
        'currentJunkEnd': currentJunkEnd,
        'showCutBox': showCutBox,
        'subStyle': subStyle.toJson(),
        'inpaint': inpaintConfig.toJson(),
        'mixState': mixState.toJson(),
        'videoSpeed': videoSpeed,
        'selectedClipId': selectedClipId,
        'selectedTrackId': selectedTrackId,
      };

  factory StudioSnapshot.fromJson(Map<String, dynamic> json) {
    final parsedAudioTracks = (json['audioTracks'] as List<dynamic>?)
            ?.map((e) => StudioAudioTrack.fromJson(e as Map<String, dynamic>))
            .toList() ??
        const [StudioAudioTrack(id: 'track-au-1', name: 'Âm thanh 1')];
    final parsedAudioClips = (json['audioClips'] as List<dynamic>?)
            ?.map((e) => AudioClip.fromJson(e as Map<String, dynamic>))
            .toList() ??
        const [];
    final effectiveAudioTracks = List<StudioAudioTrack>.from(parsedAudioTracks);
    if (parsedAudioClips.any((c) => c.trackId == 'track-au-2') &&
        !effectiveAudioTracks.any((t) => t.id == 'track-au-2')) {
      effectiveAudioTracks.add(const StudioAudioTrack(id: 'track-au-2', name: 'Âm thanh 2'));
    }

    return StudioSnapshot(
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
      audioTracks: effectiveAudioTracks,
      audioClips: parsedAudioClips,
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
      inpaintConfig: json['inpaint'] != null
          ? StudioInpaintConfig.fromJson(json['inpaint'] as Map<String, dynamic>)
          : const StudioInpaintConfig(),
      mixState: json['mixState'] != null
          ? AudioMixState.fromJson(json['mixState'] as Map<String, dynamic>)
          : const AudioMixState(),
      videoSpeed: (json['videoSpeed'] as num?)?.toDouble() ?? 1.0,
      selectedClipId: json['selectedClipId'] as String?,
      selectedTrackId: json['selectedTrackId'] as String?,
    );
  }

  StudioSnapshot copyWith({
    String? id,
    String? label,
    String? time,
    List<CutSegment>? cutSegments,
    List<SplitSegment>? splitSegments,
    List<MergeItem>? mergePlaylist,
    List<OverlayTrack>? overlayTracks,
    List<OverlayClip>? overlayClips,
    List<StudioAudioTrack>? audioTracks,
    List<AudioClip>? audioClips,
    List<SubtitleClip>? subtitles,
    double? currentJunkStart,
    double? currentJunkEnd,
    bool? showCutBox,
    SubStyle? subStyle,
    StudioInpaintConfig? inpaintConfig,
    AudioMixState? mixState,
    double? videoSpeed,
    String? selectedClipId,
    bool clearSelectedClip = false,
    String? selectedTrackId,
    bool clearSelectedTrack = false,
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
      audioTracks: audioTracks ?? this.audioTracks,
      audioClips: audioClips ?? this.audioClips,
      subtitles: subtitles ?? this.subtitles,
      currentJunkStart: currentJunkStart ?? this.currentJunkStart,
      currentJunkEnd: currentJunkEnd ?? this.currentJunkEnd,
      showCutBox: showCutBox ?? this.showCutBox,
      subStyle: subStyle ?? this.subStyle,
      inpaintConfig: inpaintConfig ?? this.inpaintConfig,
      mixState: mixState ?? this.mixState,
      videoSpeed: videoSpeed ?? this.videoSpeed,
      selectedClipId: clearSelectedClip ? null : (selectedClipId ?? this.selectedClipId),
      selectedTrackId: clearSelectedTrack ? null : (selectedTrackId ?? this.selectedTrackId),
    );
  }
}
