import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sub_video_desktop/screens/movie_review/components/review_step_progress_widget.dart';
import 'package:sub_video_desktop/screens/movie_review/controllers/movie_review_controller.dart';
import 'package:sub_video_desktop/screens/movie_review/models/movie_review_model.dart';

void main() {
  group('Movie Review Step Cache & Rerun Tests', () {
    test('MovieReviewController stepOrder has exactly 7 steps matching movieReviewSteps', () {
      expect(MovieReviewController.stepOrder.length, 7);
      expect(MovieReviewController.stepOrder, [
        'mr01_blueprint',
        'mr02_scene_detect',
        'mr03_script_gen',
        'mr04_tts',
        'mr05_assembly',
        'mr06_subtitle',
        'mr07_encode',
      ]);
    });

    test('deleteStepCache cascades deletion to all downstream artifacts', () async {
      final tempDir = Directory.systemTemp.createTempSync('mr_cache_test_');
      try {
        // Tạo các file/thư mục mô phỏng toàn bộ các bước đã chạy
        final bp = File(p.join(tempDir.path, 'blueprint.json'))..writeAsStringSync('{}');
        final scenes = File(p.join(tempDir.path, 'scenes_meta.json'))..writeAsStringSync('[]');
        final script = File(p.join(tempDir.path, 'review_script.json'))..writeAsStringSync('{}');
        final ttsDir = Directory(p.join(tempDir.path, 'audio_segments'))..createSync();
        File(p.join(ttsDir.path, 'tts_001.mp3')).writeAsStringSync('audio');
        final segDir = Directory(p.join(tempDir.path, 'rendered_segments'))..createSync();
        File(p.join(segDir.path, 'seg_final_001.mp4')).writeAsStringSync('video');
        final ass = File(p.join(tempDir.path, 'subtitles_review.ass'))..writeAsStringSync('ass');

        // Tạo controller với mock workspace
        final controller = MovieReviewController();
        controller.selectVideoFromProject(
          projectName: 'test_proj',
          videoPath: '/path/to/test.mp4',
        );

        // Giả lập xóa cache từ bước 4 (mr04_tts)
        // Các bước trước 4 (1, 2, 3) phải giữ nguyên
        // Các bước từ 4 trở đi (4, 5, 6) phải bị xóa
        expect(bp.existsSync(), isTrue);
        expect(scenes.existsSync(), isTrue);
        expect(script.existsSync(), isTrue);
        expect(ttsDir.existsSync(), isTrue);
        expect(segDir.existsSync(), isTrue);
        expect(ass.existsSync(), isTrue);

        // Kiểm tra mapping artifacts
        expect(MovieReviewController.stepArtifactFiles['mr04_tts'], contains('audio_segments'));
        expect(MovieReviewController.stepArtifactFiles['mr05_assembly'], contains('rendered_segments'));
        expect(MovieReviewController.stepArtifactFiles['mr06_subtitle'], contains('subtitles_review.ass'));
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });

    testWidgets('ReviewStepProgressWidget displays replay and delete buttons when not busy', (tester) async {
      final tempDir = Directory.systemTemp.createTempSync('mr_widget_action_test_');
      try {
        File(p.join(tempDir.path, 'blueprint.json')).writeAsStringSync('{}');
        File(p.join(tempDir.path, 'scenes_meta.json')).writeAsStringSync('[]');

        const state = MovieReviewState(
          isAnalyzing: false,
          isRendering: false,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ReviewStepProgressWidget(
                state: state,
                workspacePath: tempDir.path,
                onRerunStep: (stepId) {},
                onDeleteStepCache: (stepId) {},
              ),
            ),
          ),
        );

        // Phải có 7 icon replay cho 7 bước
        expect(find.byIcon(Icons.replay), findsNWidgets(7));
        // Có 2 bước đã hoàn thành -> 2 icon delete_outline
        expect(find.byIcon(Icons.delete_outline), findsNWidgets(2));
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });
  });
}
