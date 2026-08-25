import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import '../core/job_state.dart';
import '../core/step_base.dart';

class StepTranscriptMerge extends StepBase {
  @override
  String get stepId => 's07_transcript_merge';

  @override
  List<String> get dependsOn => const ['s05_asr', 's06_ocr'];

  @override
  List<String> get stepConfigKeys => const [];

  @override
  Future<Map<String, dynamic>> run(
    Directory workspace,
    Map<String, dynamic> config,
    JobState jobState,
  ) async {
    final outFile = File(p.join(workspace.path, 's07_transcript.json'));

    final asrInfo = jobState.getStepOutput('s05_asr') ?? {};
    final ocrInfo = jobState.getStepOutput('s06_ocr') ?? {};

    final asrFile = asrInfo['transcript_file'] as String?;
    final ocrFile = ocrInfo['ocr_file'] as String?;

    List<dynamic> asrSegments = [];
    List<dynamic> ocrSegments = [];

    if (asrFile != null && File(asrFile).existsSync()) {
      try {
        asrSegments = jsonDecode(File(asrFile).readAsStringSync()) as List? ?? [];
      } catch (_) {}
    }

    if (ocrFile != null && File(ocrFile).existsSync()) {
      try {
        ocrSegments = jsonDecode(File(ocrFile).readAsStringSync()) as List? ?? [];
      } catch (_) {}
    }

    final isOcrOnly = config['ocr_only'] == true;
    List<Map<String, dynamic>> finalSegments = [];

    if (isOcrOnly || asrSegments.isEmpty) {
      finalSegments = ocrSegments.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } else {
      // Primary: ASR segments
      finalSegments = asrSegments.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }

    // 1. Sort by start time, then by longer duration
    finalSegments.sort((a, b) {
      final sa = double.tryParse(a['start']?.toString() ?? '0.0') ?? 0.0;
      final sb = double.tryParse(b['start']?.toString() ?? '0.0') ?? 0.0;
      if (sa != sb) return sa.compareTo(sb);
      final ea = double.tryParse(a['end']?.toString() ?? '0.0') ?? 0.0;
      final eb = double.tryParse(b['end']?.toString() ?? '0.0') ?? 0.0;
      return eb.compareTo(ea);
    });

    // 2. Smart Deduplication & Overlap Cleaning
    final cleanedSegments = _cleanAndDeduplicate(finalSegments);

    // 3. Re-index segment IDs
    for (int i = 0; i < cleanedSegments.length; i++) {
      cleanedSegments[i]['id'] = i;
    }

    outFile.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(cleanedSegments),
      flush: true,
    );

    return {
      'transcript_file': outFile.path,
      'segment_count': cleanedSegments.length,
    };
  }

  List<Map<String, dynamic>> _cleanAndDeduplicate(List<Map<String, dynamic>> list) {
    if (list.isEmpty) return [];

    final result = <Map<String, dynamic>>[];

    for (int i = 0; i < list.length; i++) {
      final cur = Map<String, dynamic>.from(list[i]);
      final curText = (cur['text'] ?? '').toString().trim();
      if (curText.isEmpty) continue;

      double curStart = double.tryParse(cur['start']?.toString() ?? '0.0') ?? 0.0;
      double curEnd = double.tryParse(cur['end']?.toString() ?? '${curStart + 1.0}') ?? (curStart + 1.0);

      if (result.isNotEmpty) {
        final prev = result.last;
        final prevText = (prev['text'] ?? '').toString().trim();
        double prevStart = double.tryParse(prev['start']?.toString() ?? '0.0') ?? 0.0;
        double prevEnd = double.tryParse(prev['end']?.toString() ?? '${prevStart + 1.0}') ?? (prevStart + 1.0);

        final normCur = curText.toLowerCase().replaceAll(RegExp(r'\s+'), '');
        final normPrev = prevText.toLowerCase().replaceAll(RegExp(r'\s+'), '');

        // Case A: Exact duplicate text within close timestamp -> extend previous
        if (normCur == normPrev && (curStart <= prevEnd + 0.8)) {
          prev['end'] = curEnd > prevEnd ? curEnd : prevEnd;
          continue;
        }

        // Case B: Substring / Typing effect overlap (e.g. "Làm sao" then "Làm sao để biết", "等你长大了" then "等你长大了 山#")
        if ((normCur.contains(normPrev) || normPrev.contains(normCur)) && (curStart <= prevEnd + 0.6)) {
          if (curText.length > prevText.length) {
            prev['text'] = curText;
          }
          prev['end'] = curEnd > prevEnd ? curEnd : prevEnd;
          continue;
        }

        // Case C: Micro-noise filter (single-char fragments with short duration)
        if (curText.length <= 2 && (curEnd - curStart) < 0.6) {
          continue;
        }

        // Case D: Distinct segments overlap in time -> clamp prevEnd to avoid double sub flash
        if (prevEnd > curStart) {
          prev['end'] = curStart > prevStart + 0.3 ? curStart : (prevStart + 0.3);
        }
      }

      cur['start'] = double.parse(curStart.toStringAsFixed(3));
      cur['end'] = double.parse(curEnd.toStringAsFixed(3));
      result.add(cur);
    }

    return result;
  }
}
