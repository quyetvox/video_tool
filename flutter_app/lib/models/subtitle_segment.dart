class SubtitleSegment {
  final int id;
  final double start;
  final double end;
  final String text;
  final String textVi;
  final String translatedText;
  final String textSecondary;
  final String speaker;
  final String gender;
  final Map<String, dynamic> extra;

  const SubtitleSegment({
    required this.id,
    required this.start,
    required this.end,
    this.text = '',
    this.textVi = '',
    this.translatedText = '',
    this.textSecondary = '',
    this.speaker = '',
    this.gender = '',
    this.extra = const {},
  });

  String get displayText {
    if (textVi.trim().isNotEmpty) return textVi.trim();
    if (translatedText.trim().isNotEmpty) return translatedText.trim();
    return text.trim();
  }

  SubtitleSegment copyWith({
    int? id,
    double? start,
    double? end,
    String? text,
    String? textVi,
    String? translatedText,
    String? textSecondary,
    String? speaker,
    String? gender,
    Map<String, dynamic>? extra,
  }) {
    final effectiveVi = textVi ?? translatedText ?? this.textVi;
    return SubtitleSegment(
      id: id ?? this.id,
      start: start ?? this.start,
      end: end ?? this.end,
      text: text ?? this.text,
      textVi: effectiveVi,
      translatedText: effectiveVi,
      textSecondary: textSecondary ?? this.textSecondary,
      speaker: speaker ?? this.speaker,
      gender: gender ?? this.gender,
      extra: extra ?? this.extra,
    );
  }

  factory SubtitleSegment.fromJson(Map<String, dynamic> json, int defaultId) {
    final start = (json['start'] as num?)?.toDouble() ?? (json['start_time'] as num?)?.toDouble() ?? 0.0;
    final end = (json['end'] as num?)?.toDouble() ?? (json['end_time'] as num?)?.toDouble() ?? (start + 2.0);

    final rawVi = json['text_vi'] as String? ??
        json['translated_text'] as String? ??
        json['vi'] as String? ??
        json['translation'] as String? ??
        '';

    final rawSec = json['text_secondary'] as String? ??
        json['secondary'] as String? ??
        json['secondary_text'] as String? ??
        json['en'] as String? ??
        '';

    return SubtitleSegment(
      id: (json['id'] as num?)?.toInt() ?? defaultId,
      start: start,
      end: end,
      text: json['text'] as String? ?? '',
      textVi: rawVi,
      translatedText: rawVi,
      textSecondary: rawSec,
      speaker: json['speaker'] as String? ?? '',
      gender: json['gender'] as String? ?? '',
      extra: json,
    );
  }

  Map<String, dynamic> toJson() {
    final map = Map<String, dynamic>.from(extra);
    map['id'] = id;
    map['start'] = double.parse(start.toStringAsFixed(3));
    map['end'] = double.parse(end.toStringAsFixed(3));
    if (text.isNotEmpty) map['text'] = text;

    // Primary Subtitle (Vi) - always keep in 100% sync
    final primaryText = textVi.isNotEmpty ? textVi : translatedText;
    if (primaryText.isNotEmpty) {
      map['text_vi'] = primaryText;
      map['translated_text'] = primaryText;
      if (map.containsKey('translation')) map['translation'] = primaryText;
      if (map.containsKey('vi')) map['vi'] = primaryText;
    }

    // Secondary Subtitle (En / Song ngữ) - always keep in 100% sync
    map['text_secondary'] = textSecondary;
    if (map.containsKey('secondary')) map['secondary'] = textSecondary;
    if (map.containsKey('secondary_text')) map['secondary_text'] = textSecondary;
    if (map.containsKey('en')) map['en'] = textSecondary;

    if (speaker.isNotEmpty) map['speaker'] = speaker;
    if (gender.isNotEmpty) map['gender'] = gender;
    return map;
  }
}
