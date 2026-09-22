import 'package:flutter/material.dart';

enum VlogStoryStyle {
  dailyChill,
  cinematic,
  humorous,
  auto,
}

extension VlogStoryStyleExt on VlogStoryStyle {
  String get id {
    switch (this) {
      case VlogStoryStyle.dailyChill:
        return 'daily_chill';
      case VlogStoryStyle.cinematic:
        return 'cinematic';
      case VlogStoryStyle.humorous:
        return 'humorous';
      case VlogStoryStyle.auto:
        return 'auto';
    }
  }

  String get label {
    switch (this) {
      case VlogStoryStyle.dailyChill:
        return 'Vlog Chill / Đời Thường';
      case VlogStoryStyle.cinematic:
        return 'Thuyết Minh Điện Ảnh';
      case VlogStoryStyle.humorous:
        return 'Hài Hước / Bắt Trend';
      case VlogStoryStyle.auto:
        return 'AI Tự Động Thích Ứng';
    }
  }

  String get description {
    switch (this) {
      case VlogStoryStyle.dailyChill:
        return 'Ngôi thứ nhất "mình/tôi", ấm áp, tâm sự gần gũi, thư thái.';
      case VlogStoryStyle.cinematic:
        return 'Ngôi thứ ba, giọng văn sâu lắng, triết lý, mở rộng không gian.';
      case VlogStoryStyle.humorous:
        return 'Hóm hỉnh, chơi chữ, năng lượng tích cực, chuẩn TikTok/Reels.';
      case VlogStoryStyle.auto:
        return 'AI tự quan sát ánh sáng, hành động và bối cảnh để chọn phong cách tốt nhất.';
    }
  }

  IconData get icon {
    switch (this) {
      case VlogStoryStyle.dailyChill:
        return Icons.coffee_rounded;
      case VlogStoryStyle.cinematic:
        return Icons.movie_filter_rounded;
      case VlogStoryStyle.humorous:
        return Icons.sentiment_very_satisfied_rounded;
      case VlogStoryStyle.auto:
        return Icons.auto_awesome_rounded;
    }
  }
}

enum VlogStoryEngine {
  gemini,
  ollama,
}

extension VlogStoryEngineExt on VlogStoryEngine {
  String get id => this == VlogStoryEngine.gemini ? 'gemini' : 'ollama';
  String get label => this == VlogStoryEngine.gemini ? 'Google Gemini 1-Pass (~20s)' : 'Ollama Vision Local (Offline)';
}

class VlogSegment {
  final int id;
  final double start;
  final double end;
  final String visualDesc;
  final String text;
  final int maxWords;

  const VlogSegment({
    required this.id,
    required this.start,
    required this.end,
    this.visualDesc = '',
    this.text = '',
    this.maxWords = 10,
  });

  double get duration => (end - start) > 0 ? (end - start) : 0.0;

  int get wordCount {
    final t = text.trim();
    if (t.isEmpty) return 0;
    return t.split(RegExp(r'\s+')).length;
  }

  bool get isMusicBreak => text.trim().isEmpty;

  bool get isOverBudget => maxWords > 0 && wordCount > maxWords;

  bool get isWarningBudget => maxWords > 0 && wordCount > (maxWords * 0.9).round() && !isOverBudget;

  String formatTimeRange() {
    String formatSec(double s) {
      final mins = (s ~/ 60).toString().padLeft(2, '0');
      final secs = (s % 60).toStringAsFixed(1).padLeft(4, '0');
      return '$mins:$secs';
    }
    return '${formatSec(start)} → ${formatSec(end)}';
  }

  VlogSegment copyWith({
    int? id,
    double? start,
    double? end,
    String? visualDesc,
    String? text,
    int? maxWords,
  }) {
    return VlogSegment(
      id: id ?? this.id,
      start: start ?? this.start,
      end: end ?? this.end,
      visualDesc: visualDesc ?? this.visualDesc,
      text: text ?? this.text,
      maxWords: maxWords ?? this.maxWords,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'start': start,
      'end': end,
      'duration': duration,
      'visual_desc': visualDesc,
      'text': text,
      'max_words': maxWords,
      'word_count': wordCount,
    };
  }

  factory VlogSegment.fromJson(Map<String, dynamic> json) {
    final s = (json['start'] as num?)?.toDouble() ?? 0.0;
    final e = (json['end'] as num?)?.toDouble() ?? (s + 4.0);
    return VlogSegment(
      id: json['id'] as int? ?? 1,
      start: s,
      end: e,
      visualDesc: json['visual_desc'] as String? ?? '',
      text: json['text'] as String? ?? '',
      maxWords: json['max_words'] as int? ?? 10,
    );
  }
}
