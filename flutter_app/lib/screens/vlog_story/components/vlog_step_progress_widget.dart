import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../../../../core/app_colors.dart';
import '../controllers/vlog_story_controller.dart';

const List<Map<String, String>> vlogStorySteps = [
  {
    'id': 'vs01_vision',
    'label': '1. Phân Tích Thị Giác',
    'desc': 'Trích xuất keyframes & gửi Gemini Files/Vision AI',
  },
  {
    'id': 'vs02_script',
    'label': '2. Soạn Kịch Bản Vlog',
    'desc': 'Sinh lời thoại phân cảnh (vlog_script.json)',
  },
  {
    'id': 'vs03_tts',
    'label': '3. Lồng Tiếng TTS',
    'desc': 'Tổng hợp giọng đọc diễn cảm (tts_segments)',
  },
  {
    'id': 'vs04_audio_mix',
    'label': '4. Hòa Âm & Ducking',
    'desc': 'Trộn nhạc nền BGM & Smart Ducking (mixed_audio.wav)',
  },
  {
    'id': 'vs05_subtitle',
    'label': '5. Phụ Đề & Inpaint',
    'desc': 'Tạo phụ đề ASS nhịp điệu & khử sub cũ',
  },
  {
    'id': 'vs06_encode',
    'label': '6. Xuất Video Thành Phẩm',
    'desc': 'Render hoàn chỉnh xuất bản (*_vlog_story.mp4)',
  },
];

class VlogStepProgressWidget extends StatelessWidget {
  final VlogStoryState state;
  final String workspacePath;
  final String? outputVideoPath;

  const VlogStepProgressWidget({
    super.key,
    required this.state,
    required this.workspacePath,
    this.outputVideoPath,
  });

  Set<String> _resolveCompletedSteps() {
    final completed = <String>{};
    final wsDir = Directory(workspacePath);
    if (!wsDir.existsSync()) return completed;

    try {
      final wsItems = wsDir.listSync();
      final names = wsItems.map((f) => p.basename(f.path)).toSet();

      // Step 1 & 2: script
      if (names.contains('vlog_script.json')) {
        completed.add('vs01_vision');
        completed.add('vs02_script');
      }

      // Step 3: TTS
      if (names.contains('tts_segments')) {
        final ttsDir = Directory(p.join(workspacePath, 'tts_segments'));
        if (ttsDir.existsSync() && ttsDir.listSync().isNotEmpty) {
          completed.add('vs03_tts');
        }
      }

      // Step 4: Mixed Audio
      if (names.contains('mixed_audio.wav')) {
        completed.add('vs04_audio_mix');
      }

      // Step 5: Subtitles / rendered video
      if (names.contains('subtitles_vlog.ass') || names.contains('rendered_video.mp4')) {
        completed.add('vs05_subtitle');
      }

      // Step 6: Final Output
      if (outputVideoPath != null && File(outputVideoPath!).existsSync()) {
        completed.add('vs06_encode');
      }
    } catch (_) {}

    return completed;
  }

  String? _resolveCurrentRunningStep(Set<String> completed) {
    if (state.isGeneratingScript) {
      if (!completed.contains('vs01_vision')) return 'vs01_vision';
      return 'vs02_script';
    }
    if (state.isRenderingVideo) {
      if (!completed.contains('vs03_tts')) return 'vs03_tts';
      if (!completed.contains('vs04_audio_mix')) return 'vs04_audio_mix';
      if (!completed.contains('vs05_subtitle')) return 'vs05_subtitle';
      return 'vs06_encode';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final completedSteps = _resolveCompletedSteps();
    final runningStep = _resolveCurrentRunningStep(completedSteps);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.account_tree_outlined, size: 15, color: AppColors.primary),
              const SizedBox(width: 8),
              const Text(
                'Tiến Trình 6 Bước Kể Chuyện Vlog',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.white),
              ),
              const Spacer(),
              Text(
                '${completedSteps.length}/${vlogStorySteps.length} hoàn tất',
                style: TextStyle(fontSize: 10.5, color: c.textMuted),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...vlogStorySteps.map((step) {
            final stepId = step['id']!;
            final isCompleted = completedSteps.contains(stepId);
            final isRunning = runningStep == stepId;

            return Container(
              margin: const EdgeInsets.only(bottom: 5),
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
              decoration: BoxDecoration(
                color: c.surfaceLight,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: isCompleted
                      ? AppColors.statusCompleted.withOpacity(0.4)
                      : (isRunning ? AppColors.primary.withOpacity(0.5) : c.border),
                  width: isCompleted || isRunning ? 1.0 : 0.6,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    isCompleted
                        ? Icons.check_circle_rounded
                        : (isRunning ? Icons.hourglass_top_rounded : Icons.radio_button_unchecked),
                    size: 14,
                    color: isCompleted
                        ? AppColors.statusCompleted
                        : (isRunning ? AppColors.primary : c.textMuted),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          step['label']!,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: isRunning || isCompleted ? FontWeight.w600 : FontWeight.normal,
                            color: isCompleted
                                ? Colors.white
                                : (isRunning ? AppColors.primary : c.textSecondary),
                          ),
                        ),
                        Text(
                          step['desc']!,
                          style: TextStyle(fontSize: 9.5, color: c.textMuted),
                        ),
                      ],
                    ),
                  ),
                  if (isRunning) ...[
                    const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 1.5, color: AppColors.primary),
                    ),
                  ],
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
