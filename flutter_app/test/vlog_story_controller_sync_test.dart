import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:flutter_test/flutter_test.dart';
import 'package:sub_video_desktop/core/python_bridge.dart';
import 'package:sub_video_desktop/models/app_config.dart';
import 'package:sub_video_desktop/screens/vlog_story/controllers/vlog_story_controller.dart';
import 'package:sub_video_desktop/screens/vlog_story/models/vlog_segment_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('VlogStoryController Config & Session Tests', () {
    void cleanTestWorkspace() {
      try {
        final root = PythonBridge.resolveRootDir();
        final testDir = Directory(p.join(root, 'resources', 'test_project', 'workspace', 'vlog_story', 'unique_test_vlog_no_script'));
        if (testDir.existsSync()) {
          testDir.deleteSync(recursive: true);
        }
      } catch (_) {}
    }

    setUp(cleanTestWorkspace);
    tearDown(cleanTestWorkspace);

    test('Khởi tạo trạng thái mặc định an toàn', () {
      final controller = VlogStoryController();
      final state = controller.currentState;

      expect(state.videoPath, isEmpty);
      expect(state.segments, isEmpty);
      expect(state.voice, 'hoai_my');
      expect(state.ttsSpeed, 1.0);
      expect(state.burnSubtitles, isTrue);
      expect(state.style, VlogStoryStyle.dailyChill);
      expect(state.isAutoMode, isFalse);
    });

    test('Đồng bộ các trường từ AppConfig vào state', () {
      final controller = VlogStoryController();
      final testConfig = AppConfig.defaults().copyWith(
        ttsVoice: 'ban_mai',
        ttsSpeed: 1.25,
        musicVol: 0.35,
        showSubtitle: false,
        translatorType: 'ollama',
      );

      controller.syncFromConfig(testConfig);
      final state = controller.currentState;

      expect(state.voice, 'ban_mai');
      expect(state.ttsSpeed, 1.25);
      expect(state.bgmVolume, 0.35);
      expect(state.burnSubtitles, isFalse);
      expect(state.engine, VlogStoryEngine.ollama);
    });

    test('Cập nhật các trường session (Style, Prompt, BGM)', () {
      final controller = VlogStoryController();
      
      controller.setStyle(VlogStoryStyle.cinematic);
      controller.setAutoMode(true);
      controller.setCustomPrompt('Kể về chuyến đi săn mây');
      controller.setBgmPath('/music/chill_vibes.mp3');

      final state = controller.currentState;
      expect(state.style, VlogStoryStyle.cinematic);
      expect(state.isAutoMode, isTrue);
      expect(state.customPrompt, 'Kể về chuyến đi săn mây');
      expect(state.bgmPath, '/music/chill_vibes.mp3');
    });

    test('Thao tác sửa đổi phân đoạn phụ đề và timing', () {
      final controller = VlogStoryController();
      controller.selectVideo(
        projectName: 'test_project',
        videoPath: '/path/to/unique_test_vlog_no_script.mp4',
        videoName: 'unique_test_vlog_no_script.mp4',
        duration: 30.0,
      );

      expect(controller.currentState.segments, isEmpty);

      // Thêm segment mới
      controller.addSegment();
      expect(controller.currentState.segments.length, 1);
      final first = controller.currentState.segments.first;
      expect(first.start, 0.0);
      expect(first.end, 4.0);

      // Sửa nội dung
      controller.updateSegmentText(first.id, 'Lời mở đầu ấm áp cho ngày mới.');
      expect(controller.currentState.segments.first.text, 'Lời mở đầu ấm áp cho ngày mới.');

      // Sửa timing
      controller.updateSegmentTime(first.id, 0.5, 5.0);
      expect(controller.currentState.segments.first.start, 0.5);
      expect(controller.currentState.segments.first.end, 5.0);

      // Thêm segment thứ 2 và xóa
      controller.addSegment();
      expect(controller.currentState.segments.length, 2);
      final secondId = controller.currentState.segments.last.id;
      controller.removeSegment(secondId);
      expect(controller.currentState.segments.length, 1);
    });

    test('Cập nhật duration khi player thông báo mốc thời gian', () {
      final controller = VlogStoryController();
      expect(controller.currentState.duration, 0.0);

      controller.setDuration(45.2);
      expect(controller.currentState.duration, 45.2);

      // Bỏ qua nếu chênh lệch không đáng kể (< 0.5s)
      controller.setDuration(45.3);
      expect(controller.currentState.duration, 45.2);
    });
  });
}
