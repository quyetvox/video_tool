import 'dart:io';
import 'package:test/test.dart';
import 'package:video_engine/core/config_adapter.dart';
import 'package:video_engine/core/job_state.dart';
import 'package:video_engine/core/pipeline_runner.dart';
import 'package:video_engine/core/project_manager.dart';
import 'package:video_engine/core/step_base.dart';

class MockStep extends StepBase {
  @override
  final String stepId;
  @override
  final List<String> dependsOn;
  @override
  final List<String> stepConfigKeys;

  int runCount = 0;

  MockStep({
    required this.stepId,
    this.dependsOn = const [],
    this.stepConfigKeys = const [],
  });

  @override
  Future<Map<String, dynamic>> run(
    Directory workspace,
    Map<String, dynamic> config,
    JobState jobState,
  ) async {
    runCount++;
    return {'status': 'ok', 'step': stepId};
  }
}

void main() {
  group('ConfigDict Tests', () {
    test('Hierarchical and flat alias lookups work', () {
      const yamlStr = '''
app:
  target_lang: vi
  device: auto
audio:
  volumes:
    music: 0.5
    tts_voice: 1.0
inpaint:
  region: [0.75, 0.05, 0.95, 0.95]
  engine: box_color
subtitle:
  font_size: 44
''';

      final config = ConfigDict.fromYaml(yamlStr);

      // 1. Direct and nested
      expect(config.get('app.target_lang'), equals('vi'));
      expect(config.get('audio.volumes.music'), equals(0.5));

      // 2. Flat aliases from flatToNestedMap
      expect(config.get('target_lang'), equals('vi'));
      expect(config.get('music_volume'), equals(0.5));
      expect(config.get('tts_voice_volume'), equals(1.0));
      expect(config.get('subtitle_font_size'), equals(44));

      // 3. Special Inpaint Region & Engine
      expect(config.get('inpaint_region'), equals([0.75, 0.05, 0.95, 0.95]));
      expect(config.get('inpaint_engine'), equals('box_color'));
    });

    test('Deep merge overrides properties properly', () {
      final base = ConfigDict({'a': 1, 'b': {'c': 2, 'd': 3}});
      final overlay = {'b': {'d': 99, 'e': 100}, 'f': 5};

      base.deepMerge(overlay);
      expect(base['a'], equals(1));
      expect(base['b.c'], equals(2));
      expect(base['b.d'], equals(99));
      expect(base['b.e'], equals(100));
      expect(base['f'], equals(5));
    });
  });

  group('JobState Tests', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('sub_video_test_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('Initializes state.json and saves step statuses', () {
      final job = JobState(workspace: tempDir, jobId: 'job_test_01');
      expect(job.stateFile.existsSync(), isTrue);
      expect(job.data['status'], equals('pending'));

      job.setStepStatus('s01_probe', 'done', output: {'duration': 15.5});
      expect(job.isStepDone('s01_probe'), isTrue);
      expect(job.getStepOutput('s01_probe')?['duration'], equals(15.5));

      // Reload from disk
      final reloaded = JobState(workspace: tempDir, jobId: 'job_test_01');
      expect(reloaded.isStepDone('s01_probe'), isTrue);
      expect(reloaded.getStepOutput('s01_probe')?['duration'], equals(15.5));
    });

    test('Cascade step clearance deletes dependent steps', () {
      final job = JobState(workspace: tempDir, jobId: 'job_test_02');
      job.setStepStatus('s01_probe', 'done');
      job.setStepStatus('s02_demux', 'done');
      job.setStepStatus('s04_audio_separate', 'done');
      job.setStepStatus('s05_asr', 'done');
      job.setStepStatus('s08_translation', 'done');
      job.setStepStatus('s13_audio_mix', 'done');
      job.setStepStatus('s14_encode', 'done');

      // Invalidating s04_audio_separate should invalidate s04, s05, s05b, s07, s08... s13, s14
      final cleared = job.clearStep('s04_audio_separate');
      expect(cleared, contains('s04_audio_separate'));
      expect(cleared, contains('s05_asr'));
      expect(cleared, contains('s13_audio_mix'));
      expect(cleared, contains('s14_encode'));

      // s01 and s02 should remain done
      expect(job.isStepDone('s01_probe'), isTrue);
      expect(job.isStepDone('s02_demux'), isTrue);
      expect(job.isStepDone('s04_audio_separate'), isFalse);
      expect(job.isStepDone('s05_asr'), isFalse);
    });
  });

  group('PipelineRunner Smart Invalidation Tests', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('runner_test_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('Only invalidates relevant steps on config changes', () async {
      final s01 = MockStep(stepId: 's01_probe', stepConfigKeys: ['duration']);
      final s02 = MockStep(stepId: 's02_demux', dependsOn: ['s01_probe']);
      final s09 = MockStep(stepId: 's09_subtitle_gen', dependsOn: ['s02_demux'], stepConfigKeys: ['subtitle_font_size']);
      final s11 = MockStep(stepId: 's11_subtitle_render', dependsOn: ['s09_subtitle_gen']);

      final runner = PipelineRunner(steps: [s01, s02, s09, s11]);
      final jobState = JobState(workspace: tempDir, jobId: 'job_test_runner');

      // 1. Initial Run with font_size 28
      final config1 = ConfigDict({
        'duration': 10,
        'subtitle': {'font_size': 28},
      });

      final success1 = await runner.run(jobState, config1);
      expect(success1, isTrue);
      expect(s01.runCount, equals(1));
      expect(s02.runCount, equals(1));
      expect(s09.runCount, equals(1));
      expect(s11.runCount, equals(1));

      // 2. Second Run with SAME config -> All steps cached!
      final success2 = await runner.run(jobState, config1);
      expect(success2, isTrue);
      expect(s01.runCount, equals(1));
      expect(s02.runCount, equals(1));
      expect(s09.runCount, equals(1));
      expect(s11.runCount, equals(1));

      // 3. Third Run with font_size changed 28 -> 44
      // Only s09 and downstream s11 must re-run! s01 and s02 MUST STAY CACHED!
      final config2 = ConfigDict({
        'duration': 10,
        'subtitle': {'font_size': 44},
      });

      final success3 = await runner.run(jobState, config2);
      expect(success3, isTrue);
      expect(s01.runCount, equals(1)); // NOT re-run!
      expect(s02.runCount, equals(1)); // NOT re-run!
      expect(s09.runCount, equals(2)); // Re-run!
      expect(s11.runCount, equals(2)); // Downstream re-run!
    });
  });

  group('ProjectManager Tests', () {
    test('getJobId sanitizes video stems properly', () {
      expect(ProjectManager.getJobId('assets/foods/src/video_001.mp4'), equals('job_video_001'));
      expect(ProjectManager.getJobId('test video @ 1080p.mov'), equals('job_test_video___1080p'));
    });
  });
}
