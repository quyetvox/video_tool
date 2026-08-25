import 'dart:io';
import 'package:test/test.dart';
import 'package:video_engine/video_engine.dart';
import 'package:path/path.dart' as p;

void main() {
  group('Full 17 Steps Pipeline Integration Tests', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('full_pipeline_test_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('All 17 steps can be instantiated and initialized', () {
      final steps = <StepBase>[
        StepProbe(),
        StepDemux(),
        StepSubtitleDetect(),
        StepAudioSeparate(),
        StepASR(),
        StepGenderDetect(),
        StepOCR(),
        StepTranscriptMerge(),
        StepTranslation(),
        StepMetadataGen(),
        StepTiming(),
        StepSubtitleGen(),
        StepInpaint(),
        StepSubtitleRender(),
        StepTTS(),
        StepAudioMix(),
        StepEncode(),
      ];

      expect(steps.length, equals(17));
      expect(steps.map((s) => s.stepId).toSet().length, equals(17));

      final runner = PipelineRunner(steps: steps);
      expect(runner.steps.length, equals(17));
    });

    test('ModelManager local check and progress handling', () {
      final modelsDir = tempDir.path;
      expect(ModelManager.hasRequiredModels(modelsDir: modelsDir), isFalse);

      final dummyWhisper = File(p.join(modelsDir, 'ggml', 'whisper-large-v3-turbo-q5_0.bin'));
      final dummyDemucs = File(p.join(modelsDir, 'onnx', 'htdemucs_2stem.onnx'));
      dummyWhisper.createSync(recursive: true);
      dummyDemucs.createSync(recursive: true);

      expect(ModelManager.hasRequiredModels(modelsDir: modelsDir), isTrue);
    });
  });
}
