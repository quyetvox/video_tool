import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sub_video_desktop/models/app_config.dart';
import 'package:sub_video_desktop/screens/lecture_illustrator/models/lecture_illustrator_model.dart';
import 'package:sub_video_desktop/screens/lecture_illustrator/controllers/lecture_illustrator_controller.dart';

void main() {
  group('Lecture Illustrator Models Test', () {
    test('LectureProjectConfig default and copyWith', () {
      const cfg = LectureProjectConfig();
      expect(cfg.sourceLang, 'auto');
      expect(cfg.targetLang, 'vi');
      expect(cfg.voiceMode, 'tts_dub');
      expect(cfg.burnSubtitles, true);
      expect(cfg.subtitleMode, 'bilingual');
      expect(cfg.visualLayoutPreset, 'pip');

      final updated = cfg.copyWith(
        sourceLang: 'en',
        targetLang: 'vi',
        pronounMode: 'teacher_student',
        voiceMode: 'tts_dub',
        ttsVoice: 'hoai_my',
        ttsSpeed: 1.25,
        bgmVolume: 0.15,
        burnSubtitles: true,
        subtitleMode: 'single',
        fontName: 'Montserrat',
        fontSize: '30',
        fontColor: '&H0000FFFF',
        outlineColor: '&H00333333',
        secondaryFontColor: '&H00FFCC00',
        secondaryScale: 0.85,
        videoBitrate: '4000k',
        watermarkEnabled: true,
        watermarkPath: '/path/to/logo.png',
        enableInpaint: true,
        inpaintEngine: 'box_color',
        inpaintBlurRadius: 35,
        boxBgColor: '#0f172a',
        boxOpacity: 0.95,
        inpaintMethod: 'telea',
        inpaintRegion: [0.80, 0.05, 0.95, 0.95],
        visualLayoutPreset: 'split',
      );
      expect(updated.sourceLang, 'en');
      expect(updated.targetLang, 'vi');
      expect(updated.pronounMode, 'teacher_student');
      expect(updated.voiceMode, 'tts_dub');
      expect(updated.ttsVoice, 'hoai_my');
      expect(updated.ttsSpeed, 1.25);
      expect(updated.bgmVolume, 0.15);
      expect(updated.burnSubtitles, true);
      expect(updated.subtitleMode, 'single');
      expect(updated.fontName, 'Montserrat');
      expect(updated.fontSize, '30');
      expect(updated.fontColor, '&H0000FFFF');
      expect(updated.outlineColor, '&H00333333');
      expect(updated.secondaryFontColor, '&H00FFCC00');
      expect(updated.secondaryScale, 0.85);
      expect(updated.videoBitrate, '4000k');
      expect(updated.watermarkEnabled, true);
      expect(updated.watermarkPath, '/path/to/logo.png');
      expect(updated.enableInpaint, true);
      expect(updated.inpaintEngine, 'box_color');
      expect(updated.inpaintBlurRadius, 35);
      expect(updated.boxBgColor, '#0f172a');
      expect(updated.boxOpacity, 0.95);
      expect(updated.inpaintMethod, 'telea');
      expect(updated.inpaintRegion, [0.80, 0.05, 0.95, 0.95]);
      expect(updated.visualLayoutPreset, 'split');

      final json = updated.toJson();
      expect(json.length, 30, reason: 'LectureProjectConfig phải serialize đủ 30 trường!');
      final fromJson = LectureProjectConfig.fromJson(json);
      expect(fromJson.sourceLang, 'en');
      expect(fromJson.targetLang, 'vi');
      expect(fromJson.pronounMode, 'teacher_student');
      expect(fromJson.voiceMode, 'tts_dub');
      expect(fromJson.ttsVoice, 'hoai_my');
      expect(fromJson.ttsSpeed, 1.25);
      expect(fromJson.bgmVolume, 0.15);
      expect(fromJson.burnSubtitles, true);
      expect(fromJson.subtitleMode, 'single');
      expect(fromJson.fontName, 'Montserrat');
      expect(fromJson.fontSize, '30');
      expect(fromJson.fontColor, '&H0000FFFF');
      expect(fromJson.outlineColor, '&H00333333');
      expect(fromJson.secondaryFontColor, '&H00FFCC00');
      expect(fromJson.secondaryScale, 0.85);
      expect(fromJson.videoBitrate, '4000k');
      expect(fromJson.watermarkEnabled, true);
      expect(fromJson.watermarkPath, '/path/to/logo.png');
      expect(fromJson.enableInpaint, true);
      expect(fromJson.inpaintEngine, 'box_color');
      expect(fromJson.inpaintBlurRadius, 35);
      expect(fromJson.boxBgColor, '#0f172a');
      expect(fromJson.boxOpacity, 0.95);
      expect(fromJson.inpaintMethod, 'telea');
      expect(fromJson.inpaintRegion, [0.80, 0.05, 0.95, 0.95]);
      expect(fromJson.visualLayoutPreset, 'split');
    });

    test('LectureBatch and BatchPrompts serialization', () {
      const prompts = BatchPrompts(
        imagePrompt: 'Photosynthesis chloroplast diagram, 16:9',
        diagramMermaid: 'graph TD; Light-->Chlorophyll;',
        animationConcept: 'Photon absorption animation',
        codeAnimation: 'function photosynthesis() { return energy; }',
      );

      const batch = LectureBatch(
        id: 'batch_001',
        startSec: 10.0,
        endSec: 25.5,
        transcriptOriginal: 'Light energy is captured by chlorophyll.',
        transcriptTranslated: 'Năng lượng ánh sáng được diệp lục hấp thụ.',
        educationalIntent: 'PROCESS',
        prompts: prompts,
        activeAsset: BatchActiveAsset(
          filePath: '/path/to/image.png',
          type: 'image',
          source: 'user_import',
          layout: 'pip',
          locked: true,
        ),
      );

      final json = batch.toJson();
      final restored = LectureBatch.fromJson(json);

      expect(restored.id, 'batch_001');
      expect(restored.startSec, 10.0);
      expect(restored.endSec, 25.5);
      expect(restored.transcriptTranslated, 'Năng lượng ánh sáng được diệp lục hấp thụ.');
      expect(restored.prompts.imagePrompt, 'Photosynthesis chloroplast diagram, 16:9');
      expect(restored.prompts.codeAnimation, 'function photosynthesis() { return energy; }');
      expect(restored.activeAsset?.filePath, '/path/to/image.png');
      expect(restored.activeAsset?.locked, true);
    });

    test('toSubtitleSegments and syncSegmentsFromSubtitles parity', () {
      final container = ProviderContainer();
      final controller = container.read(lectureIllustratorProvider.notifier);

      const batch = LectureBatch(
        id: 'batch_test_1',
        startSec: 0.0,
        endSec: 5.0,
        transcriptOriginal: 'Hello world',
        transcriptTranslated: 'Xin chào thế giới',
        sentences: [
          {
            'start_sec': 0.0,
            'end_sec': 5.0,
            'text': 'Hello world',
            'translated': 'Xin chào thế giới',
            'secondary': 'Hello world',
          }
        ],
      );

      controller.state = controller.state.copyWith(batches: [batch]);
      final subs = controller.toSubtitleSegments();

      expect(subs.length, 1);
      expect(subs.first.start, 0.0);
      expect(subs.first.end, 5.0);
      expect(subs.first.textVi, 'Xin chào thế giới');

      // Edit subtitle and sync back
      final modifiedSubs = [
        subs.first.copyWith(textVi: 'Xin chào các bạn đã đến với bài giảng'),
      ];
      controller.syncSegmentsFromSubtitles(modifiedSubs);

      expect(controller.state.batches.first.transcriptTranslated,
          'Xin chào các bạn đã đến với bài giảng');
      expect(controller.state.batches.first.sentences.first['translated'],
          'Xin chào các bạn đã đến với bài giảng');
    });

    test('syncFromConfig applies Cluster 1 AppConfig to LectureProjectConfig with 100% parity', () {
      final container = ProviderContainer();
      final controller = container.read(lectureIllustratorProvider.notifier);

      final customAppConfig = AppConfig.defaults().copyWith(
        targetLang: 'vi',
        secondaryLang: 'ja',
        ttsVoice: 'hoai_my',
        ttsSpeed: 1.35,
        ttsVol: 0.90,
        musicVol: 0.25,
        showSubtitle: true,
        subtitleSecondaryShow: true,
        subtitleOrder: 'primary_bottom',
        fontName: 'Inter',
        subtitleSecondaryFontName: 'Noto Sans JP',
        fontSize: '28',
        fontColor: '&H00FFFFFF',
        outlineColor: '&H00000000',
        subtitleSecondaryFontColor: '&H0000FFFF',
        subtitleSecondaryFontScale: 0.80,
        videoBitrate: '8000k',
        watermarkEnabled: true,
        watermarkImage: '/assets/logo.png',
        inpaintShowBox: true,
        inpaintEngine: 'ffmpeg_blur',
        inpaintBlurRadius: 25,
        boxBgColor: '#1e293b',
        boxBgOpacity: 0.90,
        inpaintMethod: 'vertical_gradient',
        inpaintRegion: [0.85, 0.12, 0.94, 0.88],
      );

      controller.syncFromConfig(customAppConfig);
      final cfg = controller.state.config;

      expect(cfg.targetLang, 'vi');
      expect(cfg.secondaryLang, 'ja');
      expect(cfg.ttsVoice, 'hoai_my');
      expect(cfg.ttsSpeed, 1.35);
      expect(cfg.voiceVolume, 0.90);
      expect(cfg.bgmVolume, 0.25);
      expect(cfg.burnSubtitles, true);
      expect(cfg.subtitleMode, 'bilingual');
      expect(cfg.subtitleSecondaryShow, true);
      expect(cfg.subtitleOrder, 'primary_bottom');
      expect(cfg.fontName, 'Inter');
      expect(cfg.secondaryFontName, 'Noto Sans JP');
      expect(cfg.fontSize, '28');
      expect(cfg.fontColor, '&H00FFFFFF');
      expect(cfg.outlineColor, '&H00000000');
      expect(cfg.secondaryFontColor, '&H0000FFFF');
      expect(cfg.secondaryScale, 0.80);
      expect(cfg.videoBitrate, '8000k');
      expect(cfg.watermarkEnabled, true);
      expect(cfg.watermarkPath, '/assets/logo.png');
      expect(cfg.enableInpaint, true);
      expect(cfg.inpaintEngine, 'ffmpeg_blur');
      expect(cfg.inpaintBlurRadius, 25);
      expect(cfg.boxBgColor, '#1e293b');
      expect(cfg.boxOpacity, 0.90);
      expect(cfg.inpaintMethod, 'vertical_gradient');
      expect(cfg.inpaintRegion, [0.85, 0.12, 0.94, 0.88]);
    });
  });
}
