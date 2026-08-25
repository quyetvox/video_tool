class RepetitionCleaner {
  /// Cleans repetition hallucinations commonly produced by Whisper models.
  static List<Map<String, dynamic>> cleanSegments(List<dynamic> rawSegments) {
    if (rawSegments.isEmpty) return [];

    final cleaned = <Map<String, dynamic>>[];
    String? prevText;

    for (final raw in rawSegments) {
      if (raw is! Map) continue;
      final seg = Map<String, dynamic>.from(raw);
      String text = (seg['text']?.toString() ?? '').trim();

      if (text.isEmpty) continue;

      // 1. Remove obvious phrase loops inside the text (e.g. "xinchao xinchao xinchao")
      final words = text.split(RegExp(r'\s+'));
      if (words.length >= 6) {
        final half = words.length ~/ 2;
        final firstHalf = words.sublist(0, half).join(' ');
        final secondHalf = words.sublist(half, half * 2).join(' ');
        if (firstHalf == secondHalf) {
          text = firstHalf;
          seg['text'] = text;
        }
      }

      // 2. Skip direct duplicates with identical consecutive text
      final normalized = text.toLowerCase().replaceAll(RegExp(r'[\s\p{P}\p{S}]+', unicode: true), '');
      if (normalized.isNotEmpty && prevText != null && prevText == normalized) {
        continue;
      }

      if (normalized.isNotEmpty) {
        prevText = normalized;
      }
      cleaned.add(seg);
    }

    return cleaned;
  }
}
