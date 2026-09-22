import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/app_colors.dart';
import '../../../../core/providers.dart';
import '../../../../widgets/video_player_widget.dart';
import '../../../../widgets/video_gizmo_toolbar.dart';
import '../controllers/movie_review_controller.dart';
import '../models/movie_review_model.dart';

/// Khung hiển thị Video Canvas tương tác Gizmo 4 Lớp ở Cột Giữa
class ReviewVideoCanvasView extends ConsumerStatefulWidget {
  final MovieReviewState state;
  final MovieReviewController controller;
  final int activeSidebarTab;
  final VoidCallback? onBackToStoryboard;

  const ReviewVideoCanvasView({
    super.key,
    required this.state,
    required this.controller,
    this.activeSidebarTab = 0,
    this.onBackToStoryboard,
  });

  @override
  ConsumerState<ReviewVideoCanvasView> createState() => _ReviewVideoCanvasViewState();
}

class _ReviewVideoCanvasViewState extends ConsumerState<ReviewVideoCanvasView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(isGizmoActiveProvider.notifier).state = true;
      _syncGizmoLayerWithTab(widget.activeSidebarTab);
    });
  }

  @override
  void didUpdateWidget(covariant ReviewVideoCanvasView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.activeSidebarTab != oldWidget.activeSidebarTab) {
      _syncGizmoLayerWithTab(widget.activeSidebarTab);
    }
  }

  void _syncGizmoLayerWithTab(int tabIndex) {
    if (tabIndex == 1) {
      // Tab Kiểu Dáng Sub -> Kích hoạt Layer Sub Chính
      ref.read(activeGizmoLayerProvider.notifier).state = FrameLayerType.primarySub;
    } else if (tabIndex == 2) {
      // Tab Xóa Sub & Logo -> Kích hoạt Layer Inpaint Sub Cũ
      ref.read(activeGizmoLayerProvider.notifier).state = FrameLayerType.inpaint;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final state = widget.state;
    final videoPath = state.videoPath;
    final hasVideo = videoPath != null && videoPath.isNotEmpty;

    return Container(
      color: c.surfaceDark,
      child: Column(
        children: [
          // ── 1. TOP CANVAS ACTION & 4-LAYER SWITCHER BAR ──
          VideoGizmoToolbar(
            enabled: hasVideo,
            leading: widget.onBackToStoryboard != null
                ? InkWell(
                    onTap: widget.onBackToStoryboard,
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: c.surfaceLight,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: c.border),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.arrow_back, size: 14, color: Colors.white70),
                          const SizedBox(width: 6),
                          Text(
                            'Xem Kịch Bản',
                            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: c.textPrimary),
                          ),
                        ],
                      ),
                    ),
                  )
                : null,
          ),

          // ── 2. VIDEO PLAYER BODY WITH 4-LAYER GIZMO OVERLAY HOẶC PLACEHOLDER ──
          Expanded(
            child: hasVideo
                ? VideoPlayerWidget(
                    key: ValueKey(videoPath),
                    videoPath: videoPath,
                    isFullscreen: false,
                    forcedAspectRatio: state.aspectRatio == '9:16' ? 9 / 16 : 16 / 9,
                  )
                : Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.movie_filter_outlined, size: 48, color: c.textMuted),
                        const SizedBox(height: 12),
                        Text(
                          'Chọn phim từ danh sách bên trái để bắt đầu',
                          style: TextStyle(fontSize: 13, color: c.textSecondary),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Dùng tab Tải Video nếu bạn muốn tải phim từ liên kết Internet',
                          style: TextStyle(fontSize: 11, color: c.textMuted),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
