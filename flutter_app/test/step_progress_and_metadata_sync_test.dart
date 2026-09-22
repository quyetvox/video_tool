import 'package:flutter_test/flutter_test.dart';
import 'package:sub_video_desktop/models/video_file.dart';
import 'package:sub_video_desktop/widgets/step_progress_indicator.dart';
import 'package:sub_video_desktop/screens/vlog_story/components/vlog_step_progress_widget.dart';
import 'package:sub_video_desktop/screens/movie_review/components/review_step_progress_widget.dart';

void main() {
  group('VideoFile.jobId Sanitization Tests', () {
    test('jobId correctly sanitizes spaces and special characters to match Python get_job_id', () {
      const video1 = VideoFile(
        name: 'my video 01.mp4',
        basename: 'my video 01.mp4',
        relPath: 'src/my video 01.mp4',
        fullPath: '/path/to/src/my video 01.mp4',
        sizeBytes: 1000,
        mtime: 0,
        category: VideoCategory.src,
      );
      expect(video1.jobId, equals('job_my_video_01'));

      const videoWithAccents = VideoFile(
        name: 'video (1).mp4',
        basename: 'video (1).mp4',
        relPath: 'src/video (1).mp4',
        fullPath: '/path/to/src/video (1).mp4',
        sizeBytes: 1000,
        mtime: 0,
        category: VideoCategory.src,
      );
      expect(videoWithAccents.jobId, equals('job_video__1_'));

      const outputVideo = VideoFile(
        name: 'demo-001_vi.mp4',
        basename: 'demo-001_vi.mp4',
        relPath: 'output/demo-001_vi.mp4',
        fullPath: '/path/to/output/demo-001_vi.mp4',
        sizeBytes: 1000,
        mtime: 0,
        category: VideoCategory.output,
      );
      expect(outputVideo.jobId, equals('job_demo-001'));
    });
  });

  group('Pipeline Steps & Tool Steps Tests', () {
    test('Video Editor pipelineSteps has 17 items with modern labels', () {
      expect(pipelineSteps.length, equals(17));
      final step6 = pipelineSteps.firstWhere((s) => s['id'] == 's06_ocr');
      expect(step6['label'], contains('Apple Vision OCR'));

      final step12 = pipelineSteps.firstWhere((s) => s['id'] == 's12_tts');
      expect(step12['label'], contains('Thuyết Minh TTS'));
    });

    test('Movie Review has 7 steps', () {
      expect(movieReviewSteps.length, equals(7));
      expect(movieReviewSteps.map((s) => s['id']).toList(), [
        'mr01_blueprint',
        'mr02_scene_detect',
        'mr03_script_gen',
        'mr04_tts',
        'mr05_assembly',
        'mr06_subtitle',
        'mr07_encode',
      ]);
    });

    test('Vlog Story has 6 steps', () {
      expect(vlogStorySteps.length, equals(6));
      expect(vlogStorySteps.map((s) => s['id']).toList(), [
        'vs01_vision',
        'vs02_script',
        'vs03_tts',
        'vs04_audio_mix',
        'vs05_subtitle',
        'vs06_encode',
      ]);
    });
  });
}
