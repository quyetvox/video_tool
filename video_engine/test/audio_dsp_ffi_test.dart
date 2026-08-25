import 'dart:io';
import 'package:test/test.dart';
import 'package:video_engine/ffi/audio_dsp_bindings.dart';
import 'package:path/path.dart' as p;

void main() {
  group('AudioDspBindings Native FFI Tests', () {
    setUpAll(() {
      final dylibPath = p.join(Directory.current.path, '..', 'rust_native', 'target', 'release', 'libsub_video_audio_dsp.dylib');
      AudioDspBindings.initialize(File(dylibPath).existsSync() ? dylibPath : null);
    });

    test('AudioDspBindings isAvailable after init', () {
      expect(AudioDspBindings.isAvailable, isTrue);
    });

    test('refineTimestamps handles empty or dummy segments cleanly', () {
      final segments = [
        {'id': 0, 'start': 1.0, 'end': 3.0, 'text': 'Xin chao'}
      ];

      // Non-existent audio should gracefully return original segments
      final result = AudioDspBindings.refineTimestamps(
        audioPath: 'non_existent_file.wav',
        segments: segments,
      );

      expect(result.length, equals(1));
      expect(result[0]['text'], equals('Xin chao'));
    });

    test('estimateGender returns unknown on non-existent file', () {
      final gender = AudioDspBindings.estimateGender(
        audioPath: 'non_existent.wav',
        startSec: 0.0,
        endSec: 2.0,
      );
      expect(gender, equals('unknown'));
    });
  });
}
