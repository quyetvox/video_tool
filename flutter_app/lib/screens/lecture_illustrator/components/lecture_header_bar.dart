import 'package:flutter/material.dart';
import '../../../../core/app_colors.dart';
import '../../../../widgets/app_kit.dart';
import '../../../../widgets/tool_header_toolbar.dart';
import '../controllers/lecture_illustrator_controller.dart';
import '../models/lecture_illustrator_model.dart';

class LectureHeaderBar extends StatelessWidget {
  final LectureIllustratorState state;
  final LectureIllustratorController controller;

  const LectureHeaderBar({
    super.key,
    required this.state,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final isBusy = state.isAnalyzing || state.isRendering;
    final hasVideo = state.videoPath != null && state.videoPath!.isNotEmpty;

    return ToolHeaderToolbar(
      icon: Icon(
        Icons.school_outlined,
        size: 15,
        color: c.primary,
      ),
      title: 'AI Lecture Illustrator',
      breadcrumb: (state.videoName != null && state.videoName!.isNotEmpty)
          ? state.videoName!
          : 'Chưa chọn video bài giảng',
      badge: isBusy
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: c.statusProcessingBg,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: c.statusProcessing.withOpacity(0.5), width: 0.8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 9,
                    height: 9,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      valueColor: AlwaysStoppedAnimation<Color>(c.statusProcessing),
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    state.isAnalyzing ? 'Đang phân tích bài giảng...' : 'Đang xuất video...',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: c.statusProcessing,
                    ),
                  ),
                ],
              ),
            )
          : Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: c.surfaceLight.withOpacity(0.5),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: c.border.withOpacity(0.5), width: 0.8),
              ),
              child: Text(
                '${state.batches.length} phân đoạn • ${state.config.visualLayoutPreset.toUpperCase()}',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w500,
                  color: c.textSecondary,
                ),
              ),
            ),
      actions: [
        if (isBusy) ...[
          AppButton.danger(
            icon: Icons.stop_rounded,
            label: 'Dừng',
            onPressed: controller.cancelProcess,
          ),
          const SizedBox(width: 8),
        ],

        AppButton(
          label: 'Phân Tích Bài Giảng',
          icon: Icons.psychology_outlined,
          variant: AppButtonVariant.secondary,
          onPressed: (!hasVideo || isBusy) ? null : () => controller.startAnalysis(),
        ),

        const SizedBox(width: 8),

        AppButton(
          label: 'Xuất Video',
          icon: Icons.movie_creation_outlined,
          variant: AppButtonVariant.primary,
          onPressed: (!hasVideo || state.batches.isEmpty || isBusy)
              ? null
              : () => controller.startRender(),
        ),
      ],
    );
  }
}
