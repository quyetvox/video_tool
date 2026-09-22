import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sub_video_desktop/screens/movie_review/components/review_step_progress_widget.dart';
import 'package:sub_video_desktop/screens/movie_review/models/movie_review_model.dart';

void main() {
  group('Movie Review Step Progress Widget Tests', () {
    test('movieReviewSteps contains 7 distinct steps in logical order', () {
      expect(movieReviewSteps.length, 7);
      expect(movieReviewSteps[0]['id'], 'mr01_blueprint');
      expect(movieReviewSteps[1]['id'], 'mr02_scene_detect');
      expect(movieReviewSteps[2]['id'], 'mr03_script_gen');
      expect(movieReviewSteps[3]['id'], 'mr04_tts');
      expect(movieReviewSteps[4]['id'], 'mr05_assembly');
      expect(movieReviewSteps[5]['id'], 'mr06_subtitle');
      expect(movieReviewSteps[6]['id'], 'mr07_encode');
    });

    testWidgets('ReviewStepProgressWidget renders all 7 steps with proper status', (tester) async {
      final tempDir = Directory.systemTemp.createTempSync('review_steps_test_');
      try {
        // Tạo các file mô phỏng bước 1, 2, 3 hoàn thành
        File(p.join(tempDir.path, 'blueprint.json')).writeAsStringSync('{}');
        File(p.join(tempDir.path, 'scenes_meta.json')).writeAsStringSync('[]');
        File(p.join(tempDir.path, 'review_script.json')).writeAsStringSync('{}');

        const state = MovieReviewState(
          isRendering: true,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ReviewStepProgressWidget(
                state: state,
                workspacePath: tempDir.path,
              ),
            ),
          ),
        );

        expect(find.text('Tiến Trình 7 Bước Review Phim'), findsOneWidget);
        expect(find.text('3/7 hoàn tất'), findsOneWidget);
        expect(find.text('1. Phân Tích Blueprint'), findsOneWidget);
        expect(find.text('2. Quét Cảnh Phim'), findsOneWidget);
        expect(find.text('3. Sinh Kịch Bản AI'), findsOneWidget);
        expect(find.text('4. Lồng Tiếng TTS'), findsOneWidget);
        expect(find.text('5. Ghép Cảnh Phim'), findsOneWidget);
        expect(find.text('6. Xóa Sub & Phụ Đề'), findsOneWidget);
        expect(find.text('7. Hòa Âm & Render'), findsOneWidget);

        // 3 bước hoàn thành -> 3 icon check_circle
        expect(find.byIcon(Icons.check_circle), findsNWidgets(3));
        // Đang rendering -> bước 4 (chưa xong) có icon sync
        expect(find.byIcon(Icons.sync), findsOneWidget);
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });
  });
}
