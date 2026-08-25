import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import '../core/job_state.dart';
import '../core/step_base.dart';
import '../ffi/audio_dsp_bindings.dart';

class StepGenderDetect extends StepBase {
  @override
  String get stepId => 's05b_gender_detect';

  @override
  List<String> get dependsOn => const ['s04_audio_separate', 's05_asr'];

  @override
  List<String> get stepConfigKeys => const ['enable_gender_tts', 'ocr_only'];

  @override
  Future<Map<String, dynamic>> run(
    Directory workspace,
    Map<String, dynamic> config,
    JobState jobState,
  ) async {
    final outFile = File(p.join(workspace.path, 's05b_gender.json'));

    final isOcrOnly = config['ocr_only'] == true;
    final enableGender = config['enable_gender_tts'] == true;

    if (isOcrOnly || !enableGender) {
      outFile.writeAsStringSync('{}');
      return {
        'skipped': true,
        'gender_file': outFile.path,
      };
    }

    final asrInfo = jobState.getStepOutput('s05_asr') ?? {};
    final audioInfo = jobState.getStepOutput('s04_audio_separate') ?? {};

    final voicePath = audioInfo['voice'] as String?;
    final transcriptFile = asrInfo['transcript_file'] as String?;

    if (voicePath == null || transcriptFile == null || !File(voicePath).existsSync() || !File(transcriptFile).existsSync()) {
      outFile.writeAsStringSync('{}');
      return {'skipped': true, 'gender_file': outFile.path};
    }

    final segments = (jsonDecode(File(transcriptFile).readAsStringSync()) as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    final genderMap = <String, Map<String, dynamic>>{};

    for (int i = 0; i < segments.length; i++) {
      final seg = segments[i];
      final start = double.tryParse(seg['start']?.toString() ?? '0.0') ?? 0.0;
      final end = double.tryParse(seg['end']?.toString() ?? '${start + 1.0}') ?? (start + 1.0);
      final segId = seg['id']?.toString() ?? i.toString();

      final gender = AudioDspBindings.estimateGender(
        audioPath: voicePath,
        startSec: start,
        endSec: end,
      );

      genderMap[segId] = {
        'id': segId,
        'start': start,
        'end': end,
        'gender': gender,
      };
    }

    outFile.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(genderMap),
      flush: true,
    );

    return {
      'gender_file': outFile.path,
      'detected_count': genderMap.length,
    };
  }
}
