import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import 'package:video_engine/video_engine.dart';

void main() {
  group('Pipeline Parity & Invariants Tests', () {
    late Directory tempDir;
    late JobState jobState;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('parity_test_');
      jobState = JobState(workspace: tempDir, jobId: 'job_test');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('s08c_timing guarantees End > Start and enforces max_gap_fill', () async {
      final s08File = File('${jobState.jobDir.path}/s08_translation.json');
      final rawSegments = [
        {
          'id': 0,
          'start': 0.5,
          'end': 1.0,
          'text': 'Tại sao nói ly hôn lại',
          'translated_text': 'Tại sao nói ly hôn lại',
          'text_secondary': 'Why is it said that divorce',
        },
        {
          'id': 1,
          'start': 1.2,
          'end': 2.0,
          'text': 'cần xem xét nhân phẩm hơn cả kết hôn?',
          'translated_text': 'cần xem xét nhân phẩm hơn cả kết hôn?',
          'text_secondary': 'requires more character than marriage?',
        },
        {
          'id': 2,
          'start': 5.0,
          'end': 7.0,
          'text': 'Ly hôn xem trọng nhân cách hơn là thật',
          'translated_text': 'Ly hôn xem trọng nhân cách hơn là thật',
          'text_secondary': "divorce reveals character even more, that's true.",
        }
      ];
      s08File.writeAsStringSync(jsonEncode(rawSegments));

      jobState.setStepStatus('s08_translation', 'completed', output: {
        'translation_file': s08File.path,
        'segment_count': rawSegments.length,
      });

      final stepTiming = StepTiming();
      final config = {
        'subtitle_char_rate': 0.07,
        'subtitle_safety_margin': 0.15,
        'subtitle_fill_gap': true,
        'subtitle_max_gap_fill': 0.8,
      };

      final result = await stepTiming.run(jobState.jobDir, config, jobState);
      expect(result['segment_count'], 3);

      final timingFile = File(result['timing_file'] as String);
      expect(timingFile.existsSync(), isTrue);

      final optimized = jsonDecode(timingFile.readAsStringSync()) as List;
      for (final seg in optimized) {
        final start = double.parse(seg['start'].toString());
        final end = double.parse(seg['end'].toString());
        // Invariant: End MUST be strictly greater than start
        expect(end, greaterThan(start));
        expect(end - start, greaterThanOrEqualTo(0.5));
      }

      // Test Gap-Fill: Gap between seg 0 end and seg 1 start is (1.2 - 1.0) = 0.2s <= 0.8s
      // -> Seg 0 end should be extended up to (1.2 - 0.15) = 1.05s
      final seg0End = double.parse(optimized[0]['end'].toString());
      expect(seg0End, greaterThanOrEqualTo(1.05));
    });

    test('s09_subtitle_gen generates valid ASS with box_gap and multi-line stacking', () async {
      final s08cFile = File('${jobState.jobDir.path}/s08c_timing.json');
      final timingSegments = [
        {
          'id': 0,
          'start': 0.5,
          'end': 2.5,
          'text': 'Tại sao nói ly hôn lại',
          'translated_text': 'Tại sao nói ly hôn lại',
          'text_secondary': 'Why is it said that divorce',
        }
      ];
      s08cFile.writeAsStringSync(jsonEncode(timingSegments));

      jobState.setStepStatus('s01_probe', 'completed', output: {
        'width': 1080,
        'height': 1920,
      });
      jobState.setStepStatus('s03_subtitle_detect', 'completed', output: {
        'burnin_region': [0.60, 0.05, 0.70, 0.95],
      });
      jobState.setStepStatus('s08c_timing', 'completed', output: {
        'timing_file': s08cFile.path,
        'segment_count': 1,
      });

      final stepSubGen = StepSubtitleGen();
      final config = {
        'app': {'secondary_lang': 'en'},
        'subtitle': {
          'show': true,
          'font_name': 'Arial',
          'font_size': 35,
          'order': 'primary_top',
          'box_split': false,
          'box_gap': 8,
          'secondary': {
            'font_name': 'PingFang SC, Arial, Heiti SC',
            'font_size_scale': 0.75,
          }
        },
        'inpaint': {
          'show_box': true,
          'engine': 'box_color',
        }
      };

      final result = await stepSubGen.run(jobState.jobDir, config, jobState);
      expect(result['segment_count'], 1);

      final assFile = File(result['ass_file'] as String);
      expect(assFile.existsSync(), isTrue);

      final content = assFile.readAsStringSync();
      expect(content, contains('Dialogue: 0,')); // SubBox
      expect(content, contains('Dialogue: 1,')); // SubText
      expect(content, contains('Tại sao nói ly hôn lại'));
      expect(content, contains('Why is it said that divorce'));
      expect(content, contains(r'\an5\pos('));
    });
  });
}
