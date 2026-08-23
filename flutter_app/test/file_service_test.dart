import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sub_video_desktop/core/file_service.dart';

void main() {
  group('FileService Tests', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('subvideo_test_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('createProject and listProjects in custom projects directory', () {
      final projectsDir = p.join(tempDir.path, 'custom_assets');
      
      // Create projects
      final ok1 = FileService.createProject(projectsDir, 'project_alpha');
      final ok2 = FileService.createProject(projectsDir, 'project_beta');

      expect(ok1, isTrue);
      expect(ok2, isTrue);

      // Verify directories created
      expect(Directory(p.join(projectsDir, 'project_alpha', 'src')).existsSync(), isTrue);
      expect(Directory(p.join(projectsDir, 'project_alpha', 'output')).existsSync(), isTrue);
      expect(Directory(p.join(projectsDir, 'project_beta', 'src')).existsSync(), isTrue);

      // List projects
      final list = FileService.listProjects(projectsDir);
      expect(list.length, equals(2));
      expect(list.map((p) => p.name), containsAll(['project_alpha', 'project_beta']));
    });

    test('listProjectVideos correctly categorizes files', () {
      final projectsDir = p.join(tempDir.path, 'custom_assets');
      FileService.createProject(projectsDir, 'demo');

      final srcDir = Directory(p.join(projectsDir, 'demo', 'src'));
      final dummyVideo = File(p.join(srcDir.path, 'video_test.mp4'));
      dummyVideo.writeAsStringSync('dummy video data');

      final outputDir = Directory(p.join(projectsDir, 'demo', 'output'));
      final dummyOut = File(p.join(outputDir.path, 'video_test_vi.mp4'));
      dummyOut.writeAsStringSync('dummy output data');

      final map = FileService.listProjectVideos(projectsDir, 'demo');
      expect(map['srcFiles']!.length, equals(1));
      expect(map['srcFiles']!.first.basename, equals('video_test.mp4'));
      expect(map['srcFiles']!.first.stem, equals('video_test'));
      expect(map['outputFiles']!.length, equals(1));
      expect(map['outputFiles']!.first.basename, equals('video_test_vi.mp4'));
      expect(map['outputFiles']!.first.stem, equals('video_test'));
    });
  });
}
