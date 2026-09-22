import 'package:flutter/material.dart';
import '../../../../core/app_colors.dart';
import '../../../../widgets/app_kit.dart';
import '../controllers/movie_review_controller.dart';
import '../models/movie_review_model.dart';
import 'review_stats_bar.dart';
import 'review_storyboard_card.dart';
import 'review_video_hero_card.dart';

class ReviewStoryboardPanel extends StatelessWidget {
  final MovieReviewState state;
  final MovieReviewController controller;

  const ReviewStoryboardPanel({
    super.key,
    required this.state,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);

    final hookCount = state.segments.where((s) => s.section == 'hook').length;
    final storyCount = state.segments.where((s) => s.section == 'storytelling').length;
    final reviewCount = state.segments.where((s) => s.section == 'review').length;
    final outroCount = state.segments.where((s) => s.section == 'outro').length;

    final filteredSegments = state.activeSectionTab == 'all'
        ? state.segments
        : state.segments.where((s) => s.section == state.activeSectionTab).toList();

    return Column(
      children: [
        // 1. Top Stats Bar
        ReviewStatsBar(state: state),

        // 2. Section Navigation Tabs
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: c.surface,
            border: Border(bottom: BorderSide(color: c.border)),
          ),
          child: Row(
            children: [
              _buildTabButton(context, 'all', 'Tất cả (${state.segments.length})'),
              const SizedBox(width: 8),
              _buildTabButton(context, 'hook', '🪝 Hook ($hookCount)'),
              const SizedBox(width: 8),
              _buildTabButton(context, 'storytelling', '📖 Story ($storyCount)'),
              const SizedBox(width: 8),
              _buildTabButton(context, 'review', '🔍 Review ($reviewCount)'),
              const SizedBox(width: 8),
              _buildTabButton(context, 'outro', '🎬 Outro ($outroCount)'),
              const Spacer(),
              if (state.segments.isNotEmpty)
                AppButton.secondary(
                  height: 26,
                  icon: Icons.add,
                  label: 'Thêm câu thoại',
                  onPressed: () {
                    final section = state.activeSectionTab == 'all' ? 'storytelling' : state.activeSectionTab;
                    controller.addSegment(section);
                  },
                ),
            ],
          ),
        ),

        // 3. Body Workspace
        Expanded(
          child: Container(
            color: c.background,
            child: state.isAnalyzing
                ? _buildAnalyzingState(context)
                : (state.segments.isEmpty
                    ? (state.videoPath != null
                        ? ReviewVideoHeroCard(state: state, controller: controller)
                        : _buildEmptyState(context))
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: filteredSegments.length,
                        itemBuilder: (context, index) {
                          final seg = filteredSegments[index];
                          return ReviewStoryboardCard(
                            key: ValueKey('seg_${seg.id}'),
                            segment: seg,
                            projectName: state.projectName ?? 'default',
                            videoName: state.videoName ?? '',
                            ttsSpeed: state.ttsSpeed,
                            availableScenes: state.availableScenes,
                            isPlayingTts: state.currentlyPlayingSegmentId == seg.id,
                            onTextChanged: (newText) => controller.updateSegmentText(seg.id, newText),
                            onAddScene: (sc) => controller.addSceneToSegment(seg.id, sc),
                            onRemoveScene: (scId) => controller.removeSceneFromSegment(seg.id, scId),
                            onDeleteSegment: () => controller.deleteSegment(seg.id),
                            onPreviewTts: () => controller.previewTts(seg.id, seg.voiceoverText),
                            onSplitSegment: () => controller.splitSegment(seg.id),
                            onMergeWithNext: () => controller.mergeWithNextSegment(seg.id),
                          );
                        },
                      )),
          ),
        ),
      ],
    );
  }

  Widget _buildTabButton(BuildContext context, String tabId, String label) {
    final c = AppColors.of(context);
    final isActive = state.activeSectionTab == tabId;

    return InkWell(
      onTap: () => controller.setActiveTab(tabId),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isActive ? AppColors.primary.withOpacity(0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isActive ? AppColors.primary.withOpacity(0.4) : Colors.transparent,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
            color: isActive ? AppColors.primary : c.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildAnalyzingState(BuildContext context) {
    final c = AppColors.of(context);

    return Center(
      child: Container(
        width: 480,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 42,
              height: 42,
              child: CircularProgressIndicator(strokeWidth: 3, color: AppColors.primary),
            ),
            const SizedBox(height: 16),
            const Text(
              'AI Two-Stage Movie Review Engine',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 8),
            Text(
              state.statusMessage,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: c.textSecondary),
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: state.progress > 0 ? state.progress : null,
                minHeight: 6,
                backgroundColor: c.surfaceLight,
                valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Tiến độ: ${(state.progress * 100).toStringAsFixed(0)}%',
                  style: TextStyle(fontSize: 11, color: c.textMuted),
                ),
                TextButton(
                  onPressed: controller.cancelProcess,
                  child: const Text('Hủy bỏ', style: TextStyle(fontSize: 11, color: Colors.redAccent)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final c = AppColors.of(context);

    return Center(
      child: Container(
        width: 520,
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.movie_creation_outlined, size: 36, color: AppColors.primary),
            ),
            const SizedBox(height: 16),
            const Text(
              'Studio Review Phim Tự Động (AI SOP)',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 8),
            Text(
              'Hệ thống áp dụng công nghệ Two-Stage Hierarchical tiết kiệm 90% token, tự động bóc tách dàn ý 5 hồi và sinh kịch bản chuẩn tỷ lệ vàng 4 phần:\n'
              '• The Hook (5%) — Mở bài giật gân\n'
              '• Storytelling (70%) — Mạch truyện chính\n'
              '• The Review (20%) — Đánh giá & Nhặt sạn\n'
              '• The Outro (5%) — Chấm điểm & CTA',
              textAlign: TextAlign.left,
              style: TextStyle(fontSize: 12, height: 1.5, color: c.textSecondary),
            ),
            const SizedBox(height: 20),
            const Text(
              '👈 Vui lòng chọn file phim ở thanh bên trái và bấm "🚀 PHÂN TÍCH & TẠO KỊCH BẢN"',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.primary),
            ),
          ],
        ),
      ),
    );
  }
}
