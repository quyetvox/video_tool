import 'package:flutter_test/flutter_test.dart';
import 'package:sub_video_desktop/utils/time_format_utils.dart';

void main() {
  group('TimeFormatUtils Tests', () {
    test('formatSubtitleTime converts seconds to standard SRT/ASS timecode', () {
      expect(TimeFormatUtils.formatSubtitleTime(0.0), '00:00:00,000');
      expect(TimeFormatUtils.formatSubtitleTime(65.450), '00:01:05,450');
      expect(TimeFormatUtils.formatSubtitleTime(3661.123), '01:01:01,123');
    });

    test('parseTimecodeToSeconds handles various formats', () {
      expect(TimeFormatUtils.parseTimecodeToSeconds('00:01:05,450'), closeTo(65.45, 0.001));
      expect(TimeFormatUtils.parseTimecodeToSeconds('01:05.45'), closeTo(65.45, 0.001));
      expect(TimeFormatUtils.parseTimecodeToSeconds('65.45'), closeTo(65.45, 0.001));
      expect(TimeFormatUtils.parseTimecodeToSeconds('01:01:01.123'), closeTo(3661.123, 0.001));
      expect(TimeFormatUtils.parseTimecodeToSeconds('invalid'), 0.0);
    });

    test('formatDuration formats mm:ss and hh:mm:ss', () {
      expect(TimeFormatUtils.formatDuration(45), '00:45');
      expect(TimeFormatUtils.formatDuration(125), '02:05');
      expect(TimeFormatUtils.formatDuration(3665), '01:01:05');
    });

    test('formatFileSize formats byte amounts correctly', () {
      expect(TimeFormatUtils.formatFileSize(0), '0 B');
      expect(TimeFormatUtils.formatFileSize(512), '512 B');
      expect(TimeFormatUtils.formatFileSize(1024 * 500), '500.0 KB');
      expect(TimeFormatUtils.formatFileSize(1024 * 1024 * 15), '15.0 MB');
      expect(TimeFormatUtils.formatFileSize(1024 * 1024 * 1024 * 2), '2.00 GB');
    });
  });
}
