import 'package:flutter/material.dart';
import '../../../../core/app_colors.dart';
import '../../../../widgets/settings_section_card.dart';
import '../controllers/movie_review_controller.dart';
import '../models/movie_review_model.dart';

class ReviewActsStructureTab extends StatelessWidget {
  final MovieReviewState state;
  final MovieReviewController controller;

  const ReviewActsStructureTab({
    super.key,
    required this.state,
    required this.controller,
  });

  static const Color hookColor = Color(0xFFF59E0B);
  static const Color storyColor = Color(0xFF10B981);
  static const Color reviewColor = Color(0xFF8B5CF6);
  static const Color outroColor = Color(0xFFF97316);

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final actConfig = state.actConfig;
    final budget = state.wordBudget;

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // ── 1. THANH TỶ LỆ TỔNG QUAN ──
        SettingsSectionCard(
          title: '1. Phân Bổ Tỷ Lệ Thời Lượng (Tổng 100%)',
          icon: Icons.pie_chart_outline,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Bố cục: ${state.reviewStyle.label}',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: c.textSecondary),
                ),
                TextButton.icon(
                  onPressed: () => controller.resetActRatios(),
                  icon: const Icon(Icons.refresh, size: 13, color: AppColors.primary),
                  label: const Text(
                    'Khôi phục chuẩn',
                    style: TextStyle(fontSize: 11, color: AppColors.primary),
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Visual Segmented Bar
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                height: 18,
                child: Row(
                  children: [
                    if (actConfig.enableHook && actConfig.hookPct > 0)
                      Expanded(
                        flex: (actConfig.hookPct * 100).round(),
                        child: Container(
                          color: hookColor,
                          alignment: Alignment.center,
                          child: Text(
                            '${(actConfig.hookPct * 100).round()}%',
                            style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.black),
                          ),
                        ),
                      ),
                    if (actConfig.enableStory && actConfig.storyPct > 0)
                      Expanded(
                        flex: (actConfig.storyPct * 100).round(),
                        child: Container(
                          color: storyColor,
                          alignment: Alignment.center,
                          child: Text(
                            '${(actConfig.storyPct * 100).round()}%',
                            style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                        ),
                      ),
                    if (actConfig.enableReview && actConfig.reviewPct > 0)
                      Expanded(
                        flex: (actConfig.reviewPct * 100).round(),
                        child: Container(
                          color: reviewColor,
                          alignment: Alignment.center,
                          child: Text(
                            '${(actConfig.reviewPct * 100).round()}%',
                            style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                        ),
                      ),
                    if (actConfig.enableOutro && actConfig.outroPct > 0)
                      Expanded(
                        flex: (actConfig.outroPct * 100).round(),
                        child: Container(
                          color: outroColor,
                          alignment: Alignment.center,
                          child: Text(
                            '${(actConfig.outroPct * 100).round()}%',
                            style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),

            // Legend indicators
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                _buildLegendItem('Hook', hookColor, actConfig.enableHook, actConfig.hookPct, budget.hookWords),
                _buildLegendItem('Cốt truyện', storyColor, actConfig.enableStory, actConfig.storyPct, budget.storyWords),
                _buildLegendItem('Bình luận', reviewColor, actConfig.enableReview, actConfig.reviewPct, budget.reviewWords),
                _buildLegendItem('Outro', outroColor, actConfig.enableOutro, actConfig.outroPct, budget.outroWords),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '💡 Cơ chế Story-Anchor: Kéo tỷ lệ Hook, Review, Outro sẽ tự động bù trừ vào Cốt truyện để luôn đạt tròn 100%.',
              style: TextStyle(fontSize: 10, color: c.textMuted, height: 1.3),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // ── 2. CẤU HÌNH TỪNG HỒI ──
        SettingsSectionCard(
          title: '2. Tùy Chỉnh Hồi Kịch Bản',
          icon: Icons.tune_outlined,
          children: [
            // 2.1 Hook
            _buildActCard(
              context: context,
              title: 'Mở đầu kịch tính (Hook)',
              subtitle: 'Gợi mở nút thắt éo le hoặc cao trào ấn tượng để giữ chân người xem trong 5-15s đầu.',
              color: hookColor,
              enabled: actConfig.enableHook,
              pct: actConfig.hookPct,
              wordCount: budget.hookWords,
              onToggle: (val) => controller.toggleAct('hook', val),
              onPctChanged: (val) => controller.updateActPct('hook', val),
              minPct: 0.05,
              maxPct: 0.40,
            ),
            const SizedBox(height: 8),

            // 2.2 Story
            _buildActCard(
              context: context,
              title: 'Cốt truyện chính (Storyline)',
              subtitle: 'Kể lại các diễn biến kịch bản theo chuỗi các hồi và cảnh quay tiêu biểu của phim.',
              color: storyColor,
              enabled: actConfig.enableStory,
              pct: actConfig.storyPct,
              wordCount: budget.storyWords,
              onToggle: (val) => controller.toggleAct('story', val),
              onPctChanged: (val) => controller.updateActPct('story', val),
              minPct: 0.20,
              maxPct: 0.90,
              isStoryAnchor: true,
            ),
            const SizedBox(height: 8),

            // 2.3 Review
            _buildActCard(
              context: context,
              title: 'Bình luận & Phê bình (Review)',
              subtitle: 'Mổ xẻ ý nghĩa biểu tượng, diễn xuất, kỹ xảo, triết lý hoặc các cú twist bất ngờ.',
              color: reviewColor,
              enabled: actConfig.enableReview,
              pct: actConfig.reviewPct,
              wordCount: budget.reviewWords,
              onToggle: (val) => controller.toggleAct('review', val),
              onPctChanged: (val) => controller.updateActPct('review', val),
              minPct: 0.05,
              maxPct: 0.50,
            ),
            const SizedBox(height: 8),

            // 2.4 Outro
            _buildActCard(
              context: context,
              title: 'Kết bài & Kêu gọi (Outro)',
              subtitle: 'Tổng kết thông điệp cốt lõi, chấm điểm và kêu gọi người xem like / subscribe.',
              color: outroColor,
              enabled: actConfig.enableOutro,
              pct: actConfig.outroPct,
              wordCount: budget.outroWords,
              onToggle: (val) => controller.toggleAct('outro', val),
              onPctChanged: (val) => controller.updateActPct('outro', val),
              minPct: 0.02,
              maxPct: 0.25,
            ),
          ],
        ),
        const SizedBox(height: 10),

        // ── 3. CHỌN CHƯƠNG TỪ BLUEPRINT ──
        SettingsSectionCard(
          title: '3. Danh Sách Chương Cốt Truyện',
          icon: Icons.list_alt_outlined,
          children: [
            if (actConfig.availableChapters.isEmpty) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: c.surfaceLight,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: c.border),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, size: 16, color: AppColors.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Chưa có danh sách chương. Sau khi chạy Phân tích Phim (Bước 1), AI sẽ tự động lập dàn ý các chương cốt truyện tại đây.',
                        style: TextStyle(fontSize: 10.5, color: c.textSecondary, height: 1.3),
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Đã phát hiện ${actConfig.availableChapters.length} chương từ Blueprint:',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: c.textPrimary),
                  ),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () => controller.selectAllChapters(true),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text('Chọn hết', style: TextStyle(fontSize: 10.5, color: AppColors.primary)),
                      ),
                      const SizedBox(width: 4),
                      TextButton(
                        onPressed: () => controller.selectAllChapters(false),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text('Bỏ chọn', style: TextStyle(fontSize: 10.5, color: c.textMuted)),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ...actConfig.availableChapters.map((ch) {
                final chId = ch['chapter_id'] as int? ?? 0;
                final chTitle = ch['title'] as String? ?? 'Chương $chId';
                final timeRange = ch['time_range'] as String? ?? '';
                final isSelected = actConfig.selectedChapterIds.isEmpty || actConfig.selectedChapterIds.contains(chId);

                return CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(
                    chTitle,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                      color: isSelected ? Colors.white : c.textMuted,
                    ),
                  ),
                  subtitle: timeRange.isNotEmpty
                      ? Text(timeRange, style: TextStyle(fontSize: 9.5, color: c.textMuted))
                      : null,
                  value: isSelected,
                  activeColor: storyColor,
                  onChanged: (val) => controller.toggleChapter(chId),
                );
              }),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildLegendItem(String name, Color color, bool enabled, double pct, int words) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: enabled ? color : Colors.grey,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          '$name: ${enabled ? "${(pct * 100).round()}% (~$words từ)" : "Tắt"}',
          style: TextStyle(
            fontSize: 10,
            color: enabled ? Colors.white : Colors.grey,
            fontWeight: enabled ? FontWeight.w500 : FontWeight.normal,
          ),
        ),
      ],
    );
  }

  Widget _buildActCard({
    required BuildContext context,
    required String title,
    required String subtitle,
    required Color color,
    required bool enabled,
    required double pct,
    required int wordCount,
    required ValueChanged<bool> onToggle,
    required ValueChanged<double> onPctChanged,
    required double minPct,
    required double maxPct,
    bool isStoryAnchor = false,
  }) {
    final c = AppColors.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: c.surfaceLight,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: enabled ? color.withAlpha(80) : c.border,
          width: enabled ? 1.2 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Checkbox(
                value: enabled,
                activeColor: color,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onChanged: (v) => onToggle(v ?? false),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                        color: enabled ? Colors.white : c.textMuted,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(fontSize: 9.5, color: c.textMuted, height: 1.2),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: enabled ? color.withAlpha(40) : Colors.transparent,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: enabled ? color : c.border),
                ),
                child: Text(
                  enabled ? '${(pct * 100).round()}% (~$wordCount từ)' : 'Đã tắt (0%)',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: enabled ? color : c.textMuted,
                  ),
                ),
              ),
            ],
          ),
          if (enabled) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Text(
                  '${(minPct * 100).round()}%',
                  style: TextStyle(fontSize: 9, color: c.textMuted),
                ),
                Expanded(
                  child: Slider(
                    value: pct.clamp(minPct, maxPct),
                    min: minPct,
                    max: maxPct,
                    divisions: ((maxPct - minPct) * 100).round(),
                    activeColor: color,
                    inactiveColor: c.border,
                    onChanged: onPctChanged,
                  ),
                ),
                Text(
                  '${(maxPct * 100).round()}%',
                  style: TextStyle(fontSize: 9, color: c.textMuted),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
