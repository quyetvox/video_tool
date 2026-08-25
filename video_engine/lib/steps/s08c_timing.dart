import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import '../core/job_state.dart';
import '../core/step_base.dart';

class StepTiming extends StepBase {
  @override
  String get stepId => 's08c_timing';

  @override
  List<String> get dependsOn => const ['s08_translation'];

  @override
  List<String> get stepConfigKeys => const [
        'subtitle_char_rate',
        'subtitle_safety_margin',
        'subtitle_fill_gap',
        'subtitle_max_gap_fill',
        'target_lang',
        'secondary_lang',
      ];

  @override
  Future<Map<String, dynamic>> run(
    Directory workspace,
    Map<String, dynamic> config,
    JobState jobState,
  ) async {
    final transInfo = jobState.getStepOutput('s08_translation') ?? {};
    final transFile = transInfo['translation_file'] as String?;
    final outFile = File(p.join(workspace.path, 's08c_timing.json'));

    if (transFile == null || !File(transFile).existsSync()) {
      outFile.writeAsStringSync('[]');
      return {'timing_file': outFile.path, 'segment_count': 0};
    }

    final segments = (jsonDecode(File(transFile).readAsStringSync()) as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    if (segments.isEmpty) {
      outFile.writeAsStringSync('[]');
      return {'timing_file': outFile.path, 'segment_count': 0};
    }

    final charRate = double.tryParse(config['subtitle_char_rate']?.toString() ?? '0.07') ?? 0.07;
    final safetyMargin = double.tryParse(config['subtitle_safety_margin']?.toString() ?? '0.15') ?? 0.15;
    final fillGap = config['subtitle_fill_gap'] != false;
    final maxGapFill = double.tryParse(config['subtitle_max_gap_fill']?.toString() ?? '0.8') ?? 0.8;

    final optimized = _optimize(
      segments: segments,
      charRate: charRate,
      safetyMargin: safetyMargin,
      fillGap: fillGap,
      maxGapFill: maxGapFill,
    );

    outFile.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(optimized),
      flush: true,
    );

    return {
      'timing_file': outFile.path,
      'segment_count': optimized.length,
    };
  }

  List<Map<String, dynamic>> _optimize({
    required List<Map<String, dynamic>> segments,
    required double charRate,
    required double safetyMargin,
    required bool fillGap,
    required double maxGapFill,
  }) {
    final n = segments.length;
    if (n == 0) return segments;

    final result = segments.map((e) => Map<String, dynamic>.from(e)).toList();

    // Sort chronologically by start timestamp
    result.sort((a, b) {
      final sa = double.tryParse(a['start']?.toString() ?? '0') ?? 0.0;
      final sb = double.tryParse(b['start']?.toString() ?? '0') ?? 0.0;
      return sa.compareTo(sb);
    });

    for (int i = 0; i < n; i++) {
      final cur = result[i];
      final start = double.tryParse(cur['start']?.toString() ?? '0.0') ?? 0.0;
      final originalEnd = double.tryParse(cur['end']?.toString() ?? '${start + 1.0}') ?? (start + 1.0);

      final text = (cur['translated_text'] ?? cur['text_vi'] ?? cur['text'] ?? '').toString();
      final secText = (cur['text_secondary'] ?? cur['secondary_text'] ?? '').toString();
      final effectiveLen = text.length > secText.length ? text.length : secText.length;
      final minDuration = effectiveLen * charRate;
      final idealEnd = start + (minDuration < 1.0 ? 1.0 : minDuration);

      double? cap;
      double? gap;

      if (i < n - 1) {
        final nextStart = double.tryParse(result[i + 1]['start']?.toString() ?? '0.0') ?? 0.0;
        if (nextStart > start) {
          cap = nextStart - safetyMargin;
          if (cap <= start) {
            cap = nextStart - 0.03; // Minimal headroom when gap is extremely tight
          }
          gap = nextStart - originalEnd;
        } else {
          // If collision or overlapping source timestamps
          cap = nextStart;
          gap = 0.0;
        }
      }

      if (cap != null && originalEnd >= cap) {
        // Source segment already touches or exceeds cap: clamp cleanly to avoid overlap
        final finalEnd = (cap > start) ? cap : (start + 0.1);
        cur['end'] = ((finalEnd * 1000.0).round()) / 1000.0;
        continue;
      }

      double candidate;
      if (fillGap && cap != null) {
        if (gap != null && gap > 0 && gap <= maxGapFill) {
          candidate = cap; // Seamlessly fill short pauses
        } else {
          candidate = idealEnd < cap ? idealEnd : cap;
        }
      } else {
        candidate = (cap != null && idealEnd > cap) ? cap : idealEnd;
      }

      double newEnd = originalEnd > candidate ? originalEnd : candidate;
      if (cap != null && newEnd > cap) {
        newEnd = cap;
      }

      // Ensure newEnd is always strictly greater than start
      if (newEnd <= start) {
        newEnd = (cap != null && cap > start) ? cap : (start + 0.2);
      }

      cur['end'] = ((newEnd * 1000.0).round()) / 1000.0;
    }

    return result;
  }
}
