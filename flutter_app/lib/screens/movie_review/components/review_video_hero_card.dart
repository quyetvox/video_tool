import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/app_colors.dart';
import '../../../../core/providers.dart';
import '../../../../models/app_config.dart';
import '../../../../widgets/app_kit.dart';
import '../../../../widgets/region_picker_dialog.dart';
import '../../../../widgets/video_thumbnail_widget.dart';
import '../controllers/movie_review_controller.dart';
import '../models/movie_review_model.dart';

class ReviewVideoHeroCard extends ConsumerWidget {
  final MovieReviewState state;
  final MovieReviewController controller;

  const ReviewVideoHeroCard({
    super.key,
    required this.state,
    required this.controller,
  });

  String _formatFileSize(String path) {
    try {
      final bytes = File(path).lengthSync();
      if (bytes < 1024 * 1024) {
        return '${(bytes / 1024).toStringAsFixed(1)} KB';
      } else if (bytes < 1024 * 1024 * 1024) {
        return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
      } else {
        return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
      }
    } catch (_) {
      return '-- MB';
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = AppColors.of(context);
    final config = ref.watch(configProvider);
    final videoPath = state.videoPath!;
    final videoName = state.videoName ?? 'video';
    final fileSize = _formatFileSize(videoPath);
    final budget = WordBudget.calculate(state.targetDurationSec, state.ttsSpeed);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
        child: Container(
          width: 580,
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: c.border, width: 1.2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 16,
                offset: const Offset(0, 6),
              )
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Header with Video Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: c.surfaceLight,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
                  border: Border(bottom: BorderSide(color: c.border)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.movie_filter_outlined, size: 20, color: AppColors.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            videoName,
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Text(
                                'Dung lượng: $fileSize',
                                style: TextStyle(fontSize: 11, color: c.textMuted),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                width: 3,
                                height: 3,
                                decoration: BoxDecoration(color: c.textMuted, shape: BoxShape.circle),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Tỷ lệ: ${state.aspectRatio}',
                                style: TextStyle(fontSize: 11, color: c.textMuted),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.statusProcessing.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppColors.statusProcessing.withOpacity(0.3)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.pending_outlined, size: 12, color: AppColors.statusProcessing),
                          SizedBox(width: 4),
                          Text(
                            'Chưa phân tích',
                            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: AppColors.statusProcessing),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // 2. Big Video Thumbnail 16:9 Preview
              Padding(
                padding: const EdgeInsets.all(16),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        VideoThumbnailWidget(
                          videoPath: videoPath,
                          showDuration: true,
                        ),
                        // Visual Region Gizmo Overlay (Inpaint & Subtitle)
                        _buildRegionVisualGizmo(context, ref, config, c),
                        // Dark gradient overlay
                        Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                Colors.black.withOpacity(0.6),
                              ],
                            ),
                          ),
                        ),
                        // Bottom overlay info
                        Positioned(
                          left: 12,
                          bottom: 12,
                          right: 12,
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.black87,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: AppColors.primary, width: 0.8),
                                ),
                                child: Text(
                                  'SOP: ${state.genre.label}',
                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.primary),
                                ),
                              ),
                              const Spacer(),
                              Text(
                                'Mục tiêu: ~${(state.targetDurationSec / 60).toStringAsFixed(1)} phút (${budget.totalWords} từ)',
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // 3. Golden Ratio SOP Blueprint Preview
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: c.surfaceLight,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: c.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.auto_awesome, size: 14, color: AppColors.primary),
                          SizedBox(width: 6),
                          Text(
                            'Kịch Bản Tỷ Lệ Vàng 4 Hồi Dự Kiến (Two-Stage AI):',
                            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          _buildRatioBadge('🪝 Hook 5%', '${budget.hookWords} từ', AppColors.statusProcessing),
                          const SizedBox(width: 6),
                          _buildRatioBadge('📖 Story 70%', '${budget.storyWords} từ', AppColors.primary),
                          const SizedBox(width: 6),
                          _buildRatioBadge('🔍 Review 20%', '${budget.reviewWords} từ', const Color(0xFF38BDF8)),
                          const SizedBox(width: 6),
                          _buildRatioBadge('🎬 Outro 5%', '${budget.outroWords} từ', AppColors.statusCompleted),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              // 4. Hero Call To Action Button
              Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  height: 46,
                  child: AppButton.primary(
                    icon: Icons.rocket_launch,
                    label: '🚀 PHÂN TÍCH & TẠO KỊCH BẢN CHO ${videoName.toUpperCase()}',
                    isLoading: state.isAnalyzing,
                    onPressed: state.isAnalyzing ? null : () => controller.startAnalysis(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRatioBadge(String title, String words, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withOpacity(0.35), width: 0.8),
        ),
        child: Column(
          children: [
            Text(
              title,
              style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: color),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              words,
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRegionVisualGizmo(
    BuildContext context,
    WidgetRef ref,
    AppConfig config,
    AppColorTokens c,
  ) {
    final region = config.inpaintRegion ?? const [0.58, 0.08, 0.64, 0.94];
    final subRegion = config.subtitleRegion;

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;

        final top = (region[0] * h).clamp(0.0, h);
        final left = (region[1] * w).clamp(0.0, w);
        final bottom = (region[2] * h).clamp(0.0, h);
        final right = (region[3] * w).clamp(0.0, w);
        final boxW = (right - left).clamp(4.0, w);
        final boxH = (bottom - top).clamp(4.0, h);

        return Stack(
          children: [
            // 1. Inpaint Bounding Box (Xanh Neon)
            if (state.enableInpaint)
              Positioned(
                top: top,
                left: left,
                width: boxW,
                height: boxH,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(
                      sigmaX: ((config.inpaintBlurRadius) * 0.45).clamp(2.0, 30.0),
                      sigmaY: ((config.inpaintBlurRadius) * 0.45).clamp(2.0, 30.0),
                    ),
                    child: Container(
                      decoration: BoxDecoration(
                        color: config.inpaintEngine == 'box_color'
                            ? AppColors.primary.withOpacity(0.25)
                            : Colors.transparent,
                        border: Border.all(color: AppColors.primary, width: 1.5),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      alignment: Alignment.center,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.8),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          '🟦 VÙNG CHE SUB CŨ (INPAINT)',
                          style: TextStyle(
                            fontSize: 8.5,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

            // 2. Subtitle Preview Bar (Vàng / Trắng)
            if (state.burnSubtitles)
              Positioned(
                left: 16,
                right: 16,
                bottom: subRegion != null && subRegion.length == 4
                    ? ((1.0 - subRegion[2]) * h).clamp(8.0, h - 30)
                    : 14.0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: const Color(0xFFFACC15).withOpacity(0.7), width: 1.0),
                  ),
                  child: Text(
                    '🟨 [Demo Sub] Một đứa trẻ ba tuổi rưỡi đi lạc giữa rừng sâu...',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: config.fontName.isNotEmpty ? config.fontName : 'Arial',
                      fontSize: ((double.tryParse(config.fontSize) ?? 34.0) * 0.35).clamp(10.0, 15.0),
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      shadows: const [
                        Shadow(color: Colors.black, blurRadius: 4, offset: Offset(1, 1)),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),

            // 3. Quick Action: Button Căn Chỉnh Vùng Trực Tiếp Trên Video
            Positioned(
              top: 8,
              right: 8,
              child: Material(
                color: Colors.black.withOpacity(0.75),
                borderRadius: BorderRadius.circular(6),
                child: InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: () async {
                    final res = await RegionPickerDialog.show(
                      context,
                      title: 'Căn Chỉnh Vùng Inpaint Xóa Sub Cũ',
                      initialRegion: config.inpaintRegion,
                    );
                    if (res != null) {
                      ref.read(configProvider.notifier).setField(
                            (s) => s.copyWith(inpaintRegion: res),
                          );
                    }
                  },
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.crop, size: 12, color: AppColors.primary),
                        SizedBox(width: 4),
                        Text(
                          'Căn chỉnh vùng',
                          style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
