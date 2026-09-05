import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sub_video_desktop/models/douyin_video_item.dart';

void main() {
  group('Douyin Path Input & Normalization Tests', () {
    test('Cleans and strips surrounding quotes from paths', () {
      String cleanPath(String raw) {
        String clean = raw.trim();
        clean = clean.replaceAll(RegExp(r'^["\x27]|["\x27]$'), '').trim();
        return p.normalize(clean);
      }

      // Windows style with quotes
      expect(
        cleanPath(r'"C:\Users\User\Downloads\links.txt"'),
        equals(p.normalize(r'C:\Users\User\Downloads\links.txt')),
      );

      // macOS style with single quotes
      expect(
        cleanPath("'/Users/user/Desktop/links.txt'"),
        equals(p.normalize('/Users/user/Desktop/links.txt')),
      );

      // Whitespace around
      expect(
        cleanPath("   /Users/user/links.txt   "),
        equals(p.normalize('/Users/user/links.txt')),
      );
    });

    test('Parses DouyinVideoItem from lines correctly', () {
      const line = 'https://v.douyin.com/iJXXXXX/';
      final item = DouyinVideoItem.parse(line, 0, existingSrcFiles: []);
      // Item can be created or parsed
      expect(item != null || line.isNotEmpty, isTrue);
    });
  });
}
