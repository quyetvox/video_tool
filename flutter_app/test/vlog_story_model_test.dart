import 'package:flutter_test/flutter_test.dart';
import 'package:sub_video_desktop/screens/vlog_story/models/vlog_segment_model.dart';

void main() {
  group('VlogSegment Model & Word-Budget Tests', () {
    test('Khởi tạo VlogSegment và tính toán duration chuẩn xác', () {
      const seg = VlogSegment(
        id: 1,
        start: 0.0,
        end: 4.5,
        visualDesc: 'Cảnh pha cà phê buổi sáng',
        text: 'Một buổi sáng bình yên bắt đầu.',
        maxWords: 10,
      );

      expect(seg.id, 1);
      expect(seg.start, 0.0);
      expect(seg.end, 4.5);
      expect(seg.duration, 4.5);
      expect(seg.wordCount, 7);
      expect(seg.isOverBudget, isFalse);
      expect(seg.isMusicBreak, isFalse);
      expect(seg.formatTimeRange(), '00:00.0 → 00:04.5');
    });

    test('Phát hiện câu vượt ngân sách từ (Over Budget)', () {
      const segOver = VlogSegment(
        id: 2,
        start: 4.5,
        end: 7.0,
        visualDesc: 'Cảnh rót nước sôi',
        text: 'Nước sôi được rót nhẹ nhàng từ từ vào chiếc phin nhôm cổ điển của người Việt Nam.',
        maxWords: 8,
      );

      expect(segOver.duration, 2.5);
      expect(segOver.wordCount, 18);
      expect(segOver.isOverBudget, isTrue);
    });

    test('Khoảng thở âm nhạc (Music Break) khi text rỗng', () {
      const segBreak = VlogSegment(
        id: 3,
        start: 7.0,
        end: 9.5,
        visualDesc: 'Cảnh ngắm thành phố từ trên cao',
        text: '   ',
        maxWords: 6,
      );

      expect(segBreak.wordCount, 0);
      expect(segBreak.isMusicBreak, isTrue);
      expect(segBreak.isOverBudget, isFalse);
    });

    test('Tuần tự hóa và giải mã JSON 2 chiều', () {
      const segOriginal = VlogSegment(
        id: 4,
        start: 10.2,
        end: 15.8,
        visualDesc: 'Mèo con nằm sưởi nắng bên hiên',
        text: 'Chú mèo nhỏ lười biếng tận hưởng ánh nắng ban mai.',
        maxWords: 12,
      );

      final jsonMap = segOriginal.toJson();
      expect(jsonMap['start'], 10.2);
      expect(jsonMap['end'], 15.8);
      expect(jsonMap['max_words'], 12);
      expect(jsonMap['word_count'], 11);

      final parsed = VlogSegment.fromJson(jsonMap);
      expect(parsed.id, 4);
      expect(parsed.start, 10.2);
      expect(parsed.end, 15.8);
      expect(parsed.text, segOriginal.text);
      expect(parsed.maxWords, 12);
    });

    test('Kiểm tra các Preset phong cách kể chuyện Vlog', () {
      expect(VlogStoryStyle.dailyChill.id, 'daily_chill');
      expect(VlogStoryStyle.cinematic.id, 'cinematic');
      expect(VlogStoryStyle.humorous.id, 'humorous');
      expect(VlogStoryStyle.auto.id, 'auto');

      expect(VlogStoryEngine.gemini.id, 'gemini');
      expect(VlogStoryEngine.ollama.id, 'ollama');
    });
  });
}
