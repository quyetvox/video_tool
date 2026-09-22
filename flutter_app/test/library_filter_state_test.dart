import 'package:flutter_test/flutter_test.dart';
import 'package:sub_video_desktop/core/library_filter_state.dart';
import 'package:sub_video_desktop/models/video_file.dart';

void main() {
  group('LibraryFilterX Tests', () {
    test('fromId correctly parses string identifiers', () {
      expect(LibraryFilterX.fromId('src'), equals(LibraryFilter.src));
      expect(LibraryFilterX.fromId('SRC'), equals(LibraryFilter.src));
      expect(LibraryFilterX.fromId('cut'), equals(LibraryFilter.cut));
      expect(LibraryFilterX.fromId('merge'), equals(LibraryFilter.merge));
      expect(LibraryFilterX.fromId('output'), equals(LibraryFilter.output));
      expect(LibraryFilterX.fromId('all'), equals(LibraryFilter.all));
      expect(LibraryFilterX.fromId('unknown'), equals(LibraryFilter.all));
      expect(LibraryFilterX.fromId(null), equals(LibraryFilter.all));
    });

    test('id property returns correct string identifier', () {
      expect(LibraryFilter.all.id, equals('all'));
      expect(LibraryFilter.src.id, equals('src'));
      expect(LibraryFilter.cut.id, equals('cut'));
      expect(LibraryFilter.merge.id, equals('merge'));
      expect(LibraryFilter.output.id, equals('output'));
    });

    VideoFile createMockFile(String name, VideoCategory cat) {
      return VideoFile(
        name: name,
        basename: name,
        relPath: name,
        fullPath: '/path/$name',
        sizeBytes: 1024,
        mtime: 123456.0,
        category: cat,
      );
    }

    final mockData = <String, List<VideoFile>>{
      'srcFiles': [createMockFile('src_01.mp4', VideoCategory.src)],
      'cutFiles': [createMockFile('cut_01.mp4', VideoCategory.cut)],
      'mergeFiles': [createMockFile('merge_01.mp4', VideoCategory.merge)],
      'outputFiles': [
        createMockFile('out_01.mp4', VideoCategory.output),
        createMockFile('out_02.mp4', VideoCategory.output),
      ],
    };

    test('filterVideos returns appropriate list per filter', () {
      final all = LibraryFilter.all.filterVideos(mockData);
      expect(all.length, equals(5));

      final src = LibraryFilter.src.filterVideos(mockData);
      expect(src.length, equals(1));
      expect(src.first.name, equals('src_01.mp4'));

      final cut = LibraryFilter.cut.filterVideos(mockData);
      expect(cut.length, equals(1));
      expect(cut.first.name, equals('cut_01.mp4'));

      final merge = LibraryFilter.merge.filterVideos(mockData);
      expect(merge.length, equals(1));
      expect(merge.first.name, equals('merge_01.mp4'));

      final output = LibraryFilter.output.filterVideos(mockData);
      expect(output.length, equals(2));
      expect(output.map((f) => f.name), containsAll(['out_01.mp4', 'out_02.mp4']));
    });

    test('filterVideos gracefully handles null or empty map', () {
      expect(LibraryFilter.all.filterVideos(null), isEmpty);
      expect(LibraryFilter.src.filterVideos({}), isEmpty);
    });

    test('isVideoToolTab accurately classifies nav indices', () {
      // Tool tabs with video workspaces
      expect(isVideoToolTab(0), isTrue); // Video Editor
      expect(isVideoToolTab(1), isTrue); // Video Studio
      expect(isVideoToolTab(7), isTrue); // AI Review Phim
      expect(isVideoToolTab(8), isTrue); // AI Kể Chuyện Vlog

      // Non-video tabs (cloud, system, download)
      expect(isVideoToolTab(2), isFalse); // Douyin Downloader
      expect(isVideoToolTab(3), isFalse); // Cloud GCS
      expect(isVideoToolTab(4), isFalse); // Config YAML
      expect(isVideoToolTab(5), isFalse); // Logs Console
      expect(isVideoToolTab(6), isFalse); // Setup
    });
  });
}
