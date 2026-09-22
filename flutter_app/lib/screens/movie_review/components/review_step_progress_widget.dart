import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../../../../core/app_colors.dart';
import '../../../../widgets/confirm_dialog.dart';
import '../models/movie_review_model.dart';

const List<Map<String, String>> movieReviewSteps = [
  {
    'id': 'mr01_blueprint',
    'label': '1. Phân Tích Blueprint',
    'desc': 'Khung kịch bản & mốc thời gian AI (blueprint.json)',
    'file': 'blueprint.json',
  },
  {
    'id': 'mr02_scene_detect',
    'label': '2. Quét Cảnh Phim',
    'desc': 'Nhận diện shots & keyframes (scenes_meta.json)',
    'file': 'scenes_meta.json',
  },
  {
    'id': 'mr03_script_gen',
    'label': '3. Sinh Kịch Bản AI',
    'desc': 'Kịch bản phân cảnh 4 phần (review_script.json)',
    'file': 'review_script.json',
  },
  {
    'id': 'mr04_tts',
    'label': '4. Lồng Tiếng TTS',
    'desc': 'Sinh giọng đọc Dual-Engine (audio_tts)',
    'file': 'audio_tts',
  },
  {
    'id': 'mr05_assembly',
    'label': '5. Ghép Cảnh Phim',
    'desc': 'Cắt ghép video khớp Audio-Anchor (segments)',
    'file': 'segments',
  },
  {
    'id': 'mr06_subtitle',
    'label': '6. Xóa Sub & Phụ Đề',
    'desc': 'Inpaint Boxblur & Subtitle ASS (subtitles_review.ass)',
    'file': 'subtitles_review.ass',
  },
  {
    'id': 'mr07_encode',
    'label': '7. Hòa Âm & Render',
    'desc': 'Audio mix stereo & MP4 xuất bản (*_review_*.mp4)',
    'file': 'output_video',
  },
];

class ReviewStepProgressWidget extends StatelessWidget {
  final MovieReviewState state;
  final String workspacePath;
  final String? outputVideoPath;
  final Function(String stepId)? onRerunStep;
  final Function(String stepId)? onDeleteStepCache;

  const ReviewStepProgressWidget({
    super.key,
    required this.state,
    required this.workspacePath,
    this.outputVideoPath,
    this.onRerunStep,
    this.onDeleteStepCache,
  });

  Set<String> _resolveCompletedSteps() {
    final completed = <String>{};
    final wsDir = Directory(workspacePath);
    if (!wsDir.existsSync()) return completed;

    try {
      final wsItems = wsDir.listSync();
      final names = wsItems.map((f) => p.basename(f.path)).toSet();

      if (names.contains('blueprint.json')) completed.add('mr01_blueprint');
      if (names.contains('scenes_meta.json') || names.contains('scenes')) completed.add('mr02_scene_detect');
      if (names.contains('review_script.json')) completed.add('mr03_script_gen');

      // TTS step: folder audio_tts hoặc audio_segments
      if (names.contains('audio_tts') || names.contains('audio_segments')) {
        final ttsDir = Directory(p.join(workspacePath, 'audio_tts'));
        final segAudioDir = Directory(p.join(workspacePath, 'audio_segments'));
        if ((ttsDir.existsSync() && ttsDir.listSync().isNotEmpty) ||
            (segAudioDir.existsSync() && segAudioDir.listSync().isNotEmpty)) {
          completed.add('mr04_tts');
        }
      }

      // Segments step: folder segments hoặc rendered_segments
      if (names.contains('segments') || names.contains('rendered_segments')) {
        final segDir = Directory(p.join(workspacePath, 'segments'));
        final rendDir = Directory(p.join(workspacePath, 'rendered_segments'));
        if ((segDir.existsSync() && segDir.listSync().isNotEmpty) ||
            (rendDir.existsSync() && rendDir.listSync().isNotEmpty)) {
          completed.add('mr05_assembly');
        }
      }

      if (names.contains('subtitles_review.ass')) completed.add('mr06_subtitle');

      // Step 7: output video
      if (outputVideoPath != null && File(outputVideoPath!).existsSync()) {
        completed.add('mr07_encode');
      }
    } catch (_) {}

    return completed;
  }

  String? _resolveCurrentRunningStep(Set<String> completed) {
    if (state.isAnalyzing) {
      if (!completed.contains('mr01_blueprint')) return 'mr01_blueprint';
      if (!completed.contains('mr02_scene_detect')) return 'mr02_scene_detect';
      return 'mr03_script_gen';
    }
    if (state.isRendering) {
      if (!completed.contains('mr04_tts')) return 'mr04_tts';
      if (!completed.contains('mr05_assembly')) return 'mr05_assembly';
      if (!completed.contains('mr06_subtitle')) return 'mr06_subtitle';
      return 'mr07_encode';
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
                'Tiến Trình 7 Bước Review Phim',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.white),
              ),
              const Spacer(),
              Text(
                '${completedSteps.length}/${movieReviewSteps.length} hoàn tất',
                style: TextStyle(fontSize: 10.5, color: c.textMuted),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...movieReviewSteps.map((step) {
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
                        ? Icons.check_circle
                        : (isRunning ? Icons.sync : Icons.radio_button_unchecked),
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
                            fontWeight: isCompleted ? FontWeight.bold : FontWeight.w500,
                            color: isCompleted ? Colors.white : c.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          step['desc']!,
                          style: TextStyle(fontSize: 9.5, color: c.textMuted),
                        ),
                      ],
                    ),
                  ),
                  if (!state.isAnalyzing && !state.isRendering) ...[
                    IconButton(
                      icon: const Icon(Icons.replay, size: 14, color: AppColors.primary),
                      tooltip: 'Chạy lại từ bước này',
                      splashRadius: 16,
                      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                      padding: EdgeInsets.zero,
                      onPressed: () async {
                        final ok = await ConfirmDialog.show(
                          context,
                          title: 'Chạy Lại Từ ${step['label']}',
                          message: 'Bạn có chắc muốn xóa cache và chạy lại từ "${step['label']}" đến khi hoàn tất video không?\nCác file kết quả của bước này và các bước sau sẽ được làm mới.',
                          confirmText: 'Chạy lại',
                        );
                        if (ok == true) {
                          onRerunStep?.call(stepId);
                        }
                      },
                    ),
                    if (isCompleted)
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 14, color: AppColors.statusFailed),
                        tooltip: 'Xóa cache bước này & các bước sau',
                        splashRadius: 16,
                        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                        padding: EdgeInsets.zero,
                        onPressed: () async {
                          final ok = await ConfirmDialog.show(
                            context,
                            title: 'Xóa Cache ${step['label']}',
                            message: 'Bạn có chắc muốn xóa cache của "${step['label']}" và các bước sau không?\nDữ liệu đã xử lý sẽ được dọn sạch để bạn thiết lập lại.',
                            confirmText: 'Xóa cache',
                            isDestructive: true,
                          );
                          if (ok == true) {
                            onDeleteStepCache?.call(stepId);
                          }
                        },
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

