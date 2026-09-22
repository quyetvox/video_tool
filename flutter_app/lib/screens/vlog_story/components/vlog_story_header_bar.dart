import 'package:flutter/material.dart';
import '../../../../core/app_colors.dart';
import '../../../../widgets/app_kit.dart';
import '../../../../widgets/tool_header_toolbar.dart';
import '../controllers/vlog_story_controller.dart';
import '../models/vlog_segment_model.dart';

/// Thanh công cụ Sub-Header 44px chuẩn mực dành riêng cho Tab Kể Chuyện Vlog.
/// Cung cấp truy cập trực tiếp các nút: Tạo kịch bản AI, Tiếp tục dựng / Xuất video, Dừng tiến trình.
class VlogStoryHeaderBar extends StatelessWidget {
  final VlogStoryState state;
  final VlogStoryController controller;

  const VlogStoryHeaderBar({
    super.key,
    required this.state,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final isBusy = state.isProcessing;
    final hasVideo = state.videoPath.isNotEmpty;

    return ToolHeaderToolbar(
      icon: Icon(
        Icons.auto_stories_outlined,
        size: 15,
        color: c.primary,
      ),
      title: 'AI Kể Chuyện Vlog',
      breadcrumb: state.videoName.isNotEmpty
          ? state.videoName
          : 'Chưa chọn video',
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
                    state.statusMessage.isNotEmpty
                        ? state.statusMessage
                        : (state.isGeneratingScript ? 'Đang tạo kịch bản...' : 'Đang dựng video...'),
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
                '${state.style.label} • ${state.segments.length} đoạn',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w500,
                  color: c.textSecondary,
                ),
              ),
            ),
      actions: [
        // ⏹️ Nút Dừng khi đang xử lý
        if (isBusy) ...[
          AppButton.danger(
            icon: Icons.stop_rounded,
            label: 'Dừng',
            onPressed: controller.cancelActiveTask,
          ),
          const SizedBox(width: 8),
        ],

        // ✨ Nút Tạo Kịch Bản AI (Tím Accent mờ tinh tế)
        AppButton.accent(
          icon: Icons.auto_awesome,
          label: 'Tạo Kịch Bản',
          onPressed: hasVideo && !isBusy ? () => controller.generateScript() : null,
        ),

        const SizedBox(width: 6),

        // 🚀 Nút Xuất Video / Resume Render (Vàng Amber Primary nổi bật)
        AppButton.primary(
          icon: Icons.movie_filter_rounded,
          label: 'Xuất Video',
          onPressed: hasVideo && !isBusy ? () => controller.renderFinalVideo() : null,
        ),
      ],
    );
  }
}
