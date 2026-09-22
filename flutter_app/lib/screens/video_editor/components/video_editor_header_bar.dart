import 'package:flutter/material.dart';
import '../../../../core/app_colors.dart';
import '../../../../models/video_file.dart';
import '../../../../widgets/app_kit.dart';
import '../../../../widgets/tool_header_toolbar.dart';

/// Thanh công cụ Sub-Header chuẩn mực dành riêng cho Tab Video Editor (Biên Tập & Dịch Video).
/// Chứa breadcrumb tệp video đang chọn và các nút kích hoạt quy trình cốt lõi: Voice, Sub, Resume.
class VideoEditorHeaderBar extends StatelessWidget {
  final VideoFile? selectedVideo;
  final bool isProcessing;
  final VoidCallback onTriggerVoice;
  final VoidCallback onTriggerSub;
  final VoidCallback onTriggerResume;
  final VoidCallback? onStop;

  const VideoEditorHeaderBar({
    super.key,
    required this.selectedVideo,
    required this.isProcessing,
    required this.onTriggerVoice,
    required this.onTriggerSub,
    required this.onTriggerResume,
    this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final hasVideo = selectedVideo != null;
    final isOutput = selectedVideo?.category == VideoCategory.output;

    return ToolHeaderToolbar(
      icon: Icon(
        Icons.movie_creation_outlined,
        size: 15,
        color: c.primary,
      ),
      title: 'Biên Tập & Dịch Video',
      breadcrumb: selectedVideo?.basename ?? 'Chưa chọn video',
      badge: isProcessing
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: c.statusProcessingBg,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: c.statusProcessing.withOpacity(0.5),
                  width: 0.8,
                ),
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
                    'Đang xử lý...',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: c.statusProcessing,
                    ),
                  ),
                ],
              ),
            )
          : (selectedVideo != null
              ? Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: isOutput
                        ? c.statusCompletedBg
                        : c.surfaceLight.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: isOutput
                          ? c.statusCompleted.withOpacity(0.4)
                          : c.border.withOpacity(0.5),
                      width: 0.8,
                    ),
                  ),
                  child: Text(
                    isOutput ? '✓ Đã xuất video' : 'Gốc',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: isOutput
                          ? c.statusCompleted
                          : c.textSecondary,
                    ),
                  ),
                )
              : null),
      actions: [
        // ⏹️ Nút Dừng khi đang xử lý
        if (isProcessing && onStop != null) ...[
          AppButton.danger(
            icon: Icons.stop_rounded,
            label: 'Dừng',
            onPressed: onStop,
          ),
          const SizedBox(width: 8),
        ],

        // 🎙️ Voice Button (Vàng Amber Primary - CTA dịch lồng tiếng chính)
        AppButton.primary(
          icon: Icons.mic,
          label: 'Voice',
          onPressed: hasVideo && !isProcessing ? onTriggerVoice : null,
        ),

        const SizedBox(width: 6),

        // ⚡ Sub Button (Tím Accent mờ tinh tế - Dịch phụ đề AI)
        AppButton.accent(
          icon: Icons.subtitles,
          label: 'Sub',
          onPressed: hasVideo && !isProcessing ? onTriggerSub : null,
        ),

        const SizedBox(width: 6),

        // ▶️ Resume Button (Vàng Secondary tint - Khôi phục tiến trình)
        AppButton.secondary(
          icon: Icons.play_arrow,
          label: 'Resume',
          onPressed: hasVideo && !isProcessing ? onTriggerResume : null,
        ),
      ],
    );
  }
}
