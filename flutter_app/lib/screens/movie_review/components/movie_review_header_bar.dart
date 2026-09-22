import 'package:flutter/material.dart';
import '../../../../core/app_colors.dart';
import '../../../../widgets/app_kit.dart';
import '../../../../widgets/tool_header_toolbar.dart';
import '../controllers/movie_review_controller.dart';
import '../models/movie_review_model.dart';

/// Thanh công cụ Sub-Header 44px chuẩn mực dành riêng cho Tab AI Review Phim.
/// Cung cấp truy cập trực tiếp các nút cốt lõi: Phân tích kịch bản, Dựng & Xuất video, Dừng tiến trình.
class MovieReviewHeaderBar extends StatelessWidget {
  final MovieReviewState state;
  final MovieReviewController controller;

  const MovieReviewHeaderBar({
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
        Icons.local_movies_outlined,
        size: 15,
        color: c.primary,
      ),
      title: 'AI Review Phim & Tóm Tắt',
      breadcrumb: (state.videoName != null && state.videoName!.isNotEmpty)
          ? state.videoName!
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
                    state.isAnalyzing ? 'Đang phân tích kịch bản...' : 'Đang dựng video...',
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
                '${state.genre.label} • ~${(state.targetDurationSec / 60).toStringAsFixed(1)}p',
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
            onPressed: controller.cancelProcess,
          ),
          const SizedBox(width: 8),
        ],

        // ✨ Nút Phân Tích Kịch Bản (Tím Accent mờ tinh tế)
        AppButton.accent(
          icon: Icons.auto_awesome,
          label: 'Phân Tích AI',
          onPressed: hasVideo && !isBusy ? () => controller.startAnalysis() : null,
        ),

        const SizedBox(width: 6),

        // 🎬 Nút Dựng & Xuất Video (Vàng Amber Primary nổi bật)
        AppButton.primary(
          icon: Icons.movie_filter_rounded,
          label: 'Dựng Video',
          onPressed: hasVideo && !isBusy ? () => controller.startRender() : null,
        ),
      ],
    );
  }
}
