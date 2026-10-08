import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../../../../core/app_colors.dart';
import '../controllers/lecture_illustrator_controller.dart';
import '../models/lecture_illustrator_model.dart';

const List<Map<String, String>> lectureIllustratorSteps = [
  {
    'id': 'li01_asr',
    'label': '1. Nhận Diện Giọng Nói (ASR)',
    'desc': 'Trích xuất câu thoại & timestamps Whisper (s05_asr.json)',
  },
  {
    'id': 'li02_translate',
    'label': '2. Dịch Thuật & Tri Thức',
    'desc': 'Dịch song ngữ & Phân tích ý đồ sư phạm (lecture_project.json)',
  },
  {
    'id': 'li03_tts',
    'label': '3. Lồng Tiếng TTS Audio-Anchor',
    'desc': 'Sinh giọng đọc AI theo tốc độ thật (thư mục tts/)',
  },
  {
    'id': 'li04_scenes',
    'label': '4. Soạn Kịch Bản Hoạt Cảnh',
    'desc': 'Lập layout HTML/CSS, Mermaid & Motion Concept',
  },
  {
    'id': 'li05_subtitle',
    'label': '5. Phụ Đề ASS & Inpaint',
    'desc': 'Sinh phụ đề song ngữ và áp dụng xóa sub cũ',
  },
  {
    'id': 'li06_encode',
    'label': '6. Xuất Video Thành Phẩm',
    'desc': 'Biên tập composite video & hòa âm (*_illustrated.mp4)',
  },
];

class LectureStepProgressWidget extends StatelessWidget {
  final LectureIllustratorState state;
  final String workspacePath;
  final String? outputVideoPath;
  final LectureIllustratorController? controller;

  const LectureStepProgressWidget({
    super.key,
    required this.state,
    required this.workspacePath,
    this.outputVideoPath,
    this.controller,
  });

  Set<String> _resolveCompletedSteps() {
    final completed = <String>{};
    final wsDir = Directory(workspacePath);
    if (!wsDir.existsSync()) return completed;

    try {
      final wsItems = wsDir.listSync();
      final names = wsItems.map((f) => p.basename(f.path)).toSet();

      // Step 1: ASR
      if (names.contains('s05_asr.json')) {
        completed.add('li01_asr');
      }

      // Step 2 & 4: Project JSON có batches và scenes
      if (names.contains('lecture_project.json') && state.batches.isNotEmpty) {
        completed.add('li02_translate');
        completed.add('li04_scenes');
      }

      // Step 3: TTS
      if (names.contains('tts')) {
        final ttsDir = Directory(p.join(workspacePath, 'tts'));
        if (ttsDir.existsSync() && ttsDir.listSync().isNotEmpty) {
          completed.add('li03_tts');
        }
      }

      // Step 5: Subtitle
      if (names.contains('subtitles_lecture.ass') ||
          names.contains('rendered_batches') ||
          names.contains('clean_video.mp4')) {
        completed.add('li05_subtitle');
      }

      // Step 6: Final Output
      if (outputVideoPath != null && File(outputVideoPath!).existsSync()) {
        completed.add('li06_encode');
      }
    } catch (_) {}

    return completed;
  }

  String? _resolveCurrentRunningStep(Set<String> completed) {
    if (state.isAnalyzing) {
      if (!completed.contains('li01_asr')) return 'li01_asr';
      if (!completed.contains('li02_translate')) return 'li02_translate';
      if (!completed.contains('li03_tts')) return 'li03_tts';
      return 'li04_scenes';
    }
    if (state.isRendering) {
      if (!completed.contains('li05_subtitle')) return 'li05_subtitle';
      return 'li06_encode';
    }
    return null;
  }

  Future<void> _showClearCacheDialog(BuildContext context) async {
    if (controller == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.of(context).surface,
        title: const Row(
          children: [
            Icon(Icons.delete_sweep_rounded, color: AppColors.statusFailed, size: 18),
            SizedBox(width: 8),
            Text('Xóa Bộ Nhớ Đệm Bài Giảng', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Thao tác này sẽ xóa sạch các tệp âm thanh (TTS) và các cảnh hoạt cảnh đã xuất trong thư mục đệm của bài giảng.',
              style: TextStyle(fontSize: 12),
            ),
            SizedBox(height: 8),
            Text(
              '• Kịch bản phân đoạn và câu dịch sẽ được giữ nguyên.\n• Cho phép bạn xuất lại video hoặc đổi giọng đọc mới tinh.',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.statusFailed,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.delete_forever, size: 14),
            label: const Text('Xóa Bộ Đệm (Cache)', style: TextStyle(fontSize: 12)),
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      final success = await controller!.clearProjectCache(clearAudio: true, clearScenes: true);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success ? '🧹 Đã xóa bộ nhớ đệm âm thanh & cảnh bài giảng!' : 'Có lỗi khi xóa bộ nhớ đệm.'),
            backgroundColor: success ? AppColors.statusCompleted : AppColors.statusFailed,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
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
                'Tiến Trình 6 Bước Minh Họa Bài Giảng',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.white),
              ),
              const Spacer(),
              if (controller != null && !state.isAnalyzing && !state.isRendering) ...[
                Tooltip(
                  message: 'Xóa bộ nhớ đệm âm thanh TTS và cảnh hoạt họa',
                  child: InkWell(
                    onTap: () => _showClearCacheDialog(context),
                    borderRadius: BorderRadius.circular(4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
                      decoration: BoxDecoration(
                        color: AppColors.statusFailed.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: AppColors.statusFailed.withOpacity(0.4), width: 0.7),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.delete_sweep_outlined, size: 11, color: AppColors.statusFailed),
                          SizedBox(width: 3),
                          Text(
                            'Xóa Cache',
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.statusFailed),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Text(
                '${completedSteps.length}/${lectureIllustratorSteps.length} hoàn tất',
                style: TextStyle(fontSize: 10.5, color: c.textMuted),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...lectureIllustratorSteps.map((step) {
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
                        : (isRunning ? Icons.hourglass_top_rounded : Icons.radio_button_unchecked_rounded),
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
                            fontWeight: isRunning ? FontWeight.bold : FontWeight.w500,
                            color: isCompleted
                                ? AppColors.statusCompleted
                                : (isRunning ? AppColors.primary : c.textPrimary),
                          ),
                        ),
                        const SizedBox(height: 1.5),
                        Text(
                          step['desc']!,
                          style: TextStyle(
                            fontSize: 9.5,
                            color: isRunning ? c.textPrimary : c.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isRunning) ...[
                    const SizedBox(width: 6),
                    const SizedBox(
                      width: 10,
                      height: 10,
                      child: CircularProgressIndicator(strokeWidth: 1.5),
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
