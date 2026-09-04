import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sub_video_desktop/core/thumbnail_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ThumbnailService Tests', () {
    test('sanitizeFileName removes illegal NTFS/FAT/HFS characters', () {
      const input = 'video:title?with*illegal<chars>and|quote"name.mp4';
      final cleaned = ThumbnailService.sanitizeFileName(input);

      expect(cleaned, isNot(contains(':')));
      expect(cleaned, isNot(contains('?')));
      expect(cleaned, isNot(contains('*')));
      expect(cleaned, isNot(contains('<')));
      expect(cleaned, isNot(contains('>')));
      expect(cleaned, isNot(contains('|')));
      expect(cleaned, isNot(contains('"')));
      expect(cleaned, equals('video_title_with_illegal_chars_and_quote_name.mp4'));
    });

    test('formatDuration formats seconds accurately', () {
      expect(ThumbnailService.formatDuration(null), equals('--:--'));
      expect(ThumbnailService.formatDuration(0), equals('--:--'));
      expect(ThumbnailService.formatDuration(-1.0), equals('--:--'));
      expect(ThumbnailService.formatDuration(45.2), equals('00:45'));
      expect(ThumbnailService.formatDuration(125.0), equals('02:05'));
      expect(ThumbnailService.formatDuration(3665.0), equals('01:01:05'));
    });

    test('resolveBinary discovers ffmpeg and ffprobe on current platform', () {
      final ffmpeg = ThumbnailService.instance.resolveBinary('ffmpeg');
      final ffprobe = ThumbnailService.instance.resolveBinary('ffprobe');

      expect(ffmpeg, isNotEmpty);
      expect(ffprobe, isNotEmpty);

      // On Unix / macOS dev machine, it should resolve to an existing executable
      if (Platform.isMacOS || Platform.isLinux) {
        expect(File(ffmpeg).existsSync(), isTrue, reason: 'Expected ffmpeg to exist at $ffmpeg');
        expect(File(ffprobe).existsSync(), isTrue, reason: 'Expected ffprobe to exist at $ffprobe');
      }
    });

    test('getStripNotifier handles edge cases and calculates correct frame count', () {
      final emptyNotifier = ThumbnailService.instance.getStripNotifier('', 10.0, 300.0);
      expect(emptyNotifier.value, isEmpty);

      final zeroDurNotifier = ThumbnailService.instance.getStripNotifier('/test/dummy.mp4', 0.0, 300.0);
      expect(zeroDurNotifier.value, isEmpty);

      // 300px width / 60px cellWidth = 5 frames
      final notifier = ThumbnailService.instance.getStripNotifier('/test/dummy.mp4', 15.0, 300.0, startSec: 5.0);
      expect(notifier.value.length, equals(5));
      expect(notifier.value.every((elem) => elem == null), isTrue); // initially all null before async extraction
    });
  });
}
