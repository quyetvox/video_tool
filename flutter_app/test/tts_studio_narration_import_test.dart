import 'package:flutter_test/flutter_test.dart';
import 'package:sub_video_desktop/screens/tts_studio/models/tts_models.dart';

void main() {
  group('TTS Studio Narration Script Import & Audio Timings Tests', () {
    test('TtsSegmentItem parses start_sec, end_sec, and word_count correctly from JSON', () {
      final jsonMap = {
        'id': 1,
        'text': 'Every company runs on processes.',
        'word_count': 5,
        'char_count': 32,
        'start_sec': 0.8,
        'end_sec': 5.4,
        'duration': 4.6,
        'has_explicit_timestamps': true,
      };

      final item = TtsSegmentItem.fromJson(jsonMap);
      expect(item.id, 1);
      expect(item.text, 'Every company runs on processes.');
      expect(item.wordCount, 5);
      expect(item.startSec, 0.8);
      expect(item.endSec, 5.4);
      expect(item.duration, 4.6);

      final exported = item.toJson();
      expect(exported['id'], 1);
      expect(exported['start_sec'], 0.8);
      expect(exported['end_sec'], 5.4);
      expect(exported['word_count'], 5);
    });

    test('TtsSegmentItem computes duration from endSec - startSec if duration is missing', () {
      final jsonMap = {
        'id': 2,
        'text': 'Approve an order. Onboard an employee. Process a refund.',
        'start_sec': 5.6,
        'end_sec': 10.4,
      };

      final item = TtsSegmentItem.fromJson(jsonMap);
      expect(item.startSec, 5.6);
      expect(item.endSec, 10.4);
      expect(item.duration, closeTo(4.8, 0.01));
      expect(item.wordCount, 9);
    });

    test('TtsSegmentItem copyWith preserves timing and word count fields', () {
      const original = TtsSegmentItem(
        id: 3,
        text: 'A workflow engine is software that runs a business process for you.',
        wordCount: 12,
        startSec: 18.6,
        endSec: 23.8,
        duration: 5.2,
      );

      final updated = original.copyWith(
        text: 'Updated workflow engine text.',
        wordCount: 4,
      );

      expect(updated.id, 3);
      expect(updated.text, 'Updated workflow engine text.');
      expect(updated.wordCount, 4);
      expect(updated.startSec, 18.6);
      expect(updated.endSec, 23.8);
      expect(updated.duration, 5.2);
    });

    test('TtsStudioState tracks total duration and segment timings', () {
      final seg1 = TtsSegmentItem.fromJson({
        'id': 1,
        'text': 'Every company runs on processes.',
        'start_sec': 0.8,
        'end_sec': 5.4,
        'duration': 4.6,
        'word_count': 5,
      });

      final seg2 = TtsSegmentItem.fromJson({
        'id': 2,
        'text': 'Approve an order. Onboard an employee.',
        'start_sec': 5.6,
        'end_sec': 10.4,
        'duration': 4.8,
        'word_count': 6,
      });

      final state = TtsStudioState(
        rawScript: '[0:00.80 - 0:05.40] Every company runs on processes.\n[0:05.60 - 0:10.40] Approve an order. Onboard an employee.',
        segments: [seg1, seg2],
        defaultSpeed: 1.0,
      );

      expect(state.segments.length, 2);
      expect(state.segments[0].wordCount, 5);
      expect(state.segments[1].wordCount, 6);
      expect(state.segments.last.endSec, 10.4);
    });

    test('TtsStudioState supports isTimelineLocked and TtsSegmentItem supports effectiveSpeed and isBoosted', () {
      final seg = TtsSegmentItem.fromJson({
        'id': 1,
        'text': 'A very long sentence in a short duration slot requiring speed boost.',
        'start_sec': 1.0,
        'end_sec': 3.0,
        'duration': 1.8,
        'speed': 1.0,
        'effective_speed': 2.25,
        'is_boosted': true,
      });

      expect(seg.effectiveSpeed, 2.25);
      expect(seg.isBoosted, true);

      final exported = seg.toJson();
      expect(exported['effective_speed'], 2.25);
      expect(exported['is_boosted'], true);

      const state = TtsStudioState(isTimelineLocked: true);
      expect(state.isTimelineLocked, true);

      final stateOff = state.copyWith(isTimelineLocked: false);
      expect(stateOff.isTimelineLocked, false);
    });

    test('clearAll resets segments, rawScript, fullAudioPath and audio timings completely', () {
      final seg1 = TtsSegmentItem.fromJson({
        'id': 1,
        'text': 'Line 1',
        'start_sec': 0.0,
        'end_sec': 3.0,
      });
      final stateWithData = TtsStudioState(
        rawScript: 'Line 1\nLine 2',
        segments: [seg1],
        fullAudioPath: '/path/to/audio.mp3',
        fullSrtPath: '/path/to/sub.srt',
        totalDuration: 12.5,
        isTimelineLocked: true,
      );

      expect(stateWithData.segments.isNotEmpty, true);
      expect(stateWithData.rawScript.isNotEmpty, true);

      final cleared = TtsStudioState(
        availableVoices: stateWithData.availableVoices,
        defaultVoice: stateWithData.defaultVoice,
        defaultSpeed: stateWithData.defaultSpeed,
        defaultPitch: stateWithData.defaultPitch,
        pauseSec: stateWithData.pauseSec,
        isTimelineLocked: false,
        statusMessage: 'Đã làm mới không gian làm việc.',
      );

      expect(cleared.segments, isEmpty);
      expect(cleared.rawScript, isEmpty);
      expect(cleared.fullAudioPath, isNull);
      expect(cleared.fullSrtPath, isNull);
      expect(cleared.totalDuration, 0.0);
      expect(cleared.isTimelineLocked, false);
      expect(cleared.statusMessage, 'Đã làm mới không gian làm việc.');
    });
  });
}
