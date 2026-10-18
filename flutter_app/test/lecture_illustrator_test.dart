import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sub_video_desktop/models/app_config.dart';
import 'package:sub_video_desktop/screens/lecture_illustrator/models/lecture_illustrator_model.dart';
import 'package:sub_video_desktop/screens/lecture_illustrator/controllers/lecture_illustrator_controller.dart';
import 'package:sub_video_desktop/screens/lecture_illustrator/components/lecture_batch_storyboard_card.dart';
import 'package:sub_video_desktop/screens/lecture_illustrator/components/lecture_storyboard_tab_card.dart';

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
      expect(json.length, 32, reason: 'LectureProjectConfig phải serialize đủ 32 trường!');
      final fromJson = LectureProjectConfig.fromJson(json);
      expect(fromJson.aspectRatio, '16:9');
      expect(fromJson.aiAuthored, true);
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
        subtitleRegion: [0.80, 0.05, 0.90, 0.95],
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
      expect(cfg.subtitleRegion, [0.80, 0.05, 0.90, 0.95]);
    });

    test('generatePromptForBatch generates properly formatted prompt payload', () {
      final container = ProviderContainer();
      final controller = container.read(lectureIllustratorProvider.notifier);

      const batch = LectureBatch(
        id: 'batch_001',
        startSec: 0.0,
        endSec: 8.5,
        transcriptOriginal: 'Introduction to Artificial Intelligence',
        transcriptTranslated: 'Giới thiệu về Trí tuệ nhân tạo',
        sentences: [
          {'text': 'Trí tuệ nhân tạo là gì', 'text_orig': 'What is AI'},
          {'text': 'Học máy và Mạng nơ-ron', 'text_orig': 'Machine Learning and Neural Networks'},
        ],
        stepStarts: [0.0, 3.5],
        sceneDuration: 8.5,
        scene: {'title': 'Khái Niệm AI Căn Bản'},
      );

      final prompt = controller.generatePromptForBatch(batch);
      expect(prompt, contains('batch_001'));
      expect(prompt, contains('TITLE: Khái Niệm AI Căn Bản'));
      expect(prompt, contains('SCENE DURATION: 8.50s'));
      expect(prompt, contains('Trí tuệ nhân tạo là gì'));
      expect(prompt, contains('Học máy và Mạng nơ-ron'));
      expect(prompt, contains('t=0.00s'));
      expect(prompt, contains('t=3.50s'));
    });
    testWidgets('LectureBatchStoryboardCard shows merge button only when not isLastBatch', (tester) async {
      final container = ProviderContainer();
      final controller = container.read(lectureIllustratorProvider.notifier);

      const batch = LectureBatch(
        id: 'batch_001',
        startSec: 0.0,
        endSec: 10.0,
        transcriptOriginal: 'Hello world',
        transcriptTranslated: 'Xin chào',
      );

      // 1. Khi isLastBatch == false: Có nút Gộp cảnh sau
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LectureBatchStoryboardCard(
              batch: batch,
              isSelected: false,
              onSelect: () {},
              controller: controller,
              isLastBatch: false,
            ),
          ),
        ),
      );
      expect(find.text('Gộp cảnh sau'), findsOneWidget);
      expect(find.byIcon(Icons.merge_type_rounded), findsOneWidget);

      // 2. Khi isLastBatch == true: Không có nút Gộp cảnh sau
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LectureBatchStoryboardCard(
              batch: batch,
              isSelected: false,
              onSelect: () {},
              controller: controller,
              isLastBatch: true,
            ),
          ),
        ),
      );
      expect(find.text('Gộp cảnh sau'), findsNothing);
      expect(find.byIcon(Icons.merge_type_rounded), findsNothing);
    });

    testWidgets('LectureBatchStoryboardCard renders batch index indicator and multiline text editing', (tester) async {
      final container = ProviderContainer();
      final controller = container.read(lectureIllustratorProvider.notifier);

      const batch = LectureBatch(
        id: 'batch_001',
        startSec: 0.0,
        endSec: 10.0,
        transcriptOriginal: 'Hello world',
        transcriptTranslated: 'Xin chào',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LectureBatchStoryboardCard(
              batch: batch,
              index: 1,
              totalBatches: 5,
              isSelected: false,
              onSelect: () {},
              controller: controller,
            ),
          ),
        ),
      );

      // Verify batch index badge #01 is rendered
      expect(find.text('#01'), findsOneWidget);

      // Verify multiline TextField is rendered with initial text
      expect(find.text('Xin chào'), findsOneWidget);

      // Enter text and verify text field updates
      await tester.enterText(find.byType(TextField), 'Xin chào các bạn học viên');
      await tester.pump();
      expect(find.text('Xin chào các bạn học viên'), findsOneWidget);
    });

    test('generateAllBatchesInputData and formatBatchInputBlock format output correctly', () {
      final container = ProviderContainer();
      final controller = container.read(lectureIllustratorProvider.notifier);

      // Trường hợp chưa có batch nào
      expect(controller.generateAllBatchesInputData(), isEmpty);

      // Tạo test batches
      const batch1 = LectureBatch(
        id: 'batch_001',
        startSec: 1.20,
        endSec: 10.50,
        sceneDuration: 9.30,
        scene: {'title': 'Load Balancing là gì?'},
        transcriptOriginal: 'Load balancing is essential',
        transcriptTranslated: 'Load balancing rất quan trọng',
        sentences: [
          {'text': 'Load Balancing là gì?', 'text_orig': 'What is load balancing?'},
          {'text': 'Cân bằng tải giữa các máy chủ.', 'text_orig': 'Balance traffic across servers.'},
        ],
        stepStarts: [1.20, 4.50],
      );

      const batch2 = LectureBatch(
        id: 'batch_002',
        startSec: 10.50,
        endSec: 25.00,
        sceneDuration: 14.50,
        scene: {'title': 'Cơ chế hoạt động'},
        transcriptOriginal: 'How it works',
        transcriptTranslated: 'Cơ chế hoạt động',
        sentences: [
          {'text': 'Yêu cầu được phân phối đều.', 'text_orig': 'Requests are evenly distributed.'},
        ],
        stepStarts: [11.00],
      );

      // Cập nhật state bằng setBatchesForTesting
      controller.setBatchesForTesting([batch1, batch2]);

      final allData = controller.generateAllBatchesInputData();
      expect(allData, contains('--- BATCH 1 (batch_001) ---'));
      expect(allData, contains('BATCH: #1 (batch_001)'));
      expect(allData, contains('TITLE: Load Balancing là gì?'));
      expect(allData, contains('ASPECT RATIO: 16:9 Landscape (1920x1080)'));
      expect(allData, contains('SCENE DURATION: 9.30s'));
      expect(allData, contains('SENTENCES & TIMESTAMPS:'));
      expect(allData, contains('- Ý 1 (bắt đầu tại giây t=1.20s): "Load Balancing là gì?"'));
      expect(allData, contains('- Ý 2 (bắt đầu tại giây t=4.50s): "Cân bằng tải giữa các máy chủ."'));

      expect(allData, contains('--- BATCH 2 (batch_002) ---'));
      expect(allData, contains('BATCH: #2 (batch_002)'));
      expect(allData, contains('TITLE: Cơ chế hoạt động'));
      expect(allData, contains('SCENE DURATION: 14.50s'));
      expect(allData, contains('- Ý 1 (bắt đầu tại giây t=11.00s): "Yêu cầu được phân phối đều."'));
    });

    testWidgets('LectureStoryboardTabCard displays Copy kịch bản button when batches exist', (tester) async {
      final container = ProviderContainer();
      final controller = container.read(lectureIllustratorProvider.notifier);

      const batch = LectureBatch(
        id: 'batch_001',
        startSec: 0.0,
        endSec: 10.0,
        transcriptOriginal: 'Intro',
        transcriptTranslated: 'Giới thiệu',
      );

      // 1. Khi chưa có batch: Không hiện nút 'Copy kịch bản'
      const emptyState = LectureIllustratorState(videoPath: '/path/test.mp4', batches: []);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LectureStoryboardTabCard(
              state: emptyState,
              controller: controller,
            ),
          ),
        ),
      );
      expect(find.text('Copy kịch bản'), findsNothing);

      // 2. Khi có video và có batch: Hiện nút 'Copy kịch bản'
      const populatedState = LectureIllustratorState(videoPath: '/path/test.mp4', batches: [batch]);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LectureStoryboardTabCard(
              state: populatedState,
              controller: controller,
            ),
          ),
        ),
      );
      expect(find.text('Copy kịch bản'), findsOneWidget);
      expect(find.byIcon(Icons.copy_all_rounded), findsOneWidget);
    });
  });
}

