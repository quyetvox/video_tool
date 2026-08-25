import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:video_engine/core/config_adapter.dart';
import 'package:video_engine/core/job_state.dart';
import 'package:video_engine/steps/s07_transcript_merge.dart';
import 'package:video_engine/steps/s08c_timing.dart';
import 'package:video_engine/steps/s09_subtitle_gen.dart';
import 'package:video_engine/utils/ass_utils.dart';

void main() {
  group('AssUtils Tests', () {
    test('toAssColor converts hex and named colors correctly', () {
      expect(AssUtils.toAssColor('white'), equals('&H00FFFFFF'));
      expect(AssUtils.toAssColor('yellow'), equals('&H0000FFFF'));
      expect(AssUtils.toAssColor('#FFFFFF'), equals('&H00FFFFFF'));
      expect(AssUtils.toAssColor('#00FF00'), equals('&H0000FF00')); // BGR: blue=00, green=FF, red=00
    });

    test('makeBoxPath generates valid vector commands', () {
      final path = AssUtils.makeBoxPath(200, 100, 8);
      expect(path, startsWith('m 8 0'));
      expect(path, contains('l 192 0'));
    });

    test('formatAssTime formats correctly', () {
      expect(AssUtils.formatAssTime(0.0), equals('0:00:00.00'));
      expect(AssUtils.formatAssTime(65.25), equals('0:01:05.25'));
    });
  });

  group('Pure Dart Steps Integration Tests', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('steps_test_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('Transcript Merge + Timing + Subtitle Gen produces valid SRT and ASS files', () async {
      final jobState = JobState(workspace: tempDir, jobId: 'job_integration_test');

      // 1. Mock s05_asr output
      final asrFile = File(p.join(jobState.jobDir.path, 's05_asr.json'));
      asrFile.writeAsStringSync(jsonEncode([
        {'id': 0, 'start': 1.0, 'end': 2.0, 'text': 'Xin chào các bạn'},
        {'id': 1, 'start': 2.2, 'end': 4.0, 'text': 'Hôm nay chúng ta cùng tìm hiểu video AI'},
      ]));
      jobState.setStepStatus('s05_asr', 'done', output: {'transcript_file': asrFile.path});
      jobState.setStepStatus('s06_ocr', 'done', output: {'ocr_file': null});

      // Run s07_transcript_merge
      final s07 = StepTranscriptMerge();
      final config = ConfigDict({
        'target_lang': 'vi',
        'subtitle': {
          'font_size': 40,
          'font_name': 'Arial',
        },
      });

      final out07 = await s07.run(jobState.jobDir, config, jobState);
      jobState.setStepStatus('s07_transcript_merge', 'done', output: out07);
      expect(File(out07['transcript_file'] as String).existsSync(), isTrue);

      // Mock s08_translation (directly use Vietnamese text)
      final transFile = File(p.join(jobState.jobDir.path, 's08_translation.json'));
      transFile.writeAsStringSync(jsonEncode([
        {'id': 0, 'start': 1.0, 'end': 2.0, 'text': 'Xin chào', 'translated_text': 'Xin chào các bạn'},
        {'id': 1, 'start': 2.2, 'end': 4.0, 'text': 'AI video', 'translated_text': 'Hôm nay chúng ta cùng tìm hiểu video AI'},
      ]));
      jobState.setStepStatus('s08_translation', 'done', output: {'translation_file': transFile.path});

      // Run s08c_timing
      final s08c = StepTiming();
      final out08c = await s08c.run(jobState.jobDir, config, jobState);
      jobState.setStepStatus('s08c_timing', 'done', output: out08c);
      expect(File(out08c['timing_file'] as String).existsSync(), isTrue);

      // Run s09_subtitle_gen
      final s09 = StepSubtitleGen();
      jobState.setStepStatus('s01_probe', 'done', output: {'width': 1080, 'height': 1920});
      jobState.setStepStatus('s03_subtitle_detect', 'done', output: {'burnin_region': [0.75, 0.05, 0.95, 0.95]});

      final out09 = await s09.run(jobState.jobDir, config, jobState);
      jobState.setStepStatus('s09_subtitle_gen', 'done', output: out09);

      final srt = File(out09['srt_file'] as String);
      final ass = File(out09['ass_file'] as String);

      expect(srt.existsSync(), isTrue);
      expect(ass.existsSync(), isTrue);
      expect(srt.readAsStringSync(), contains('Xin chào các bạn'));
      expect(ass.readAsStringSync(), contains('[Events]'));
      expect(ass.readAsStringSync(), contains('SubBox'));
      expect(ass.readAsStringSync(), contains('SubText'));
    });
  });
}
