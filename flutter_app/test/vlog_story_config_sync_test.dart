import 'package:flutter_test/flutter_test.dart';
import 'package:sub_video_desktop/models/app_config.dart';
import 'package:sub_video_desktop/screens/vlog_story/controllers/vlog_story_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('VlogStoryController Config & Session Sync Tests', () {
    test('Khởi tạo mặc định có enableInpaint = false và ttsVolume = 1.0', () {
      final controller = VlogStoryController();
      expect(controller.currentState.enableInpaint, isFalse);
      expect(controller.currentState.ttsVolume, 1.0);
    });

    test('syncFromConfig đồng bộ chính xác inpaintShowBox và audioTtsVoiceVolume', () {
      final controller = VlogStoryController();

      final testConfig = AppConfig.defaults().copyWith(
        inpaintShowBox: true,
        audioTtsVoiceVolume: 1.35,
        musicVol: 0.25,
        ttsSpeed: 1.2,
        ttsVoice: 'vi-VN-BanMai',
        showSubtitle: true,
      );

      controller.syncFromConfig(testConfig);

      expect(controller.currentState.enableInpaint, isTrue);
      expect(controller.currentState.ttsVolume, 1.35);
      expect(controller.currentState.bgmVolume, 0.25);
      expect(controller.currentState.ttsSpeed, 1.2);
      expect(controller.currentState.voice, 'vi-VN-BanMai');
      expect(controller.currentState.burnSubtitles, isTrue);
    });

    test('setEnableInpaint và setTtsVolume cập nhật state chính xác', () {
      final controller = VlogStoryController();

      controller.setEnableInpaint(true);
      expect(controller.currentState.enableInpaint, isTrue);

      controller.setEnableInpaint(false);
      expect(controller.currentState.enableInpaint, isFalse);

      controller.setTtsVolume(1.4);
      expect(controller.currentState.ttsVolume, 1.4);
    });
  });
}
