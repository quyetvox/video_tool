import 'package:flutter/material.dart';
import '../../../../core/app_colors.dart';
import '../models/movie_review_model.dart';

class ReviewStatsBar extends StatelessWidget {
  final MovieReviewState state;

  const ReviewStatsBar({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final budget = state.wordBudget;
    final currentWords = state.currentWordCount;
    final targetWords = budget.totalWords;

    final estSec = state.estimatedDurationSec;
    final targetSec = state.targetDurationSec.toDouble();

    final isWordCountGood = (currentWords - targetWords).abs() <= (targetWords * 0.15);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(bottom: BorderSide(color: c.border)),
      ),
      child: Row(
        children: [
          // Thể loại Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.15),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppColors.primary.withOpacity(0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.movie_filter_outlined, size: 13, color: AppColors.primary),
                const SizedBox(width: 5),
                Text(
                  state.genre.label,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.primary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),

          // Định dạng Tỷ lệ Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: c.surfaceLight,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: c.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  state.aspectRatio == '9:16' ? Icons.stay_current_portrait : Icons.tv,
                  size: 13,
                  color: c.textSecondary,
                ),
                const SizedBox(width: 5),
                Text(
                  state.aspectRatio == '9:16' ? '9:16 Dọc (TikTok/Shorts)' : '16:9 Ngang (YouTube)',
                  style: TextStyle(fontSize: 11, color: c.textSecondary),
                ),
              ],
            ),
          ),

          const Spacer(),

          // Thống kê Số chữ
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.text_snippet_outlined,
                size: 14,
                color: isWordCountGood ? AppColors.statusCompleted : AppColors.statusProcessing,
              ),
              const SizedBox(width: 5),
              Text(
                'Số chữ: ',
                style: TextStyle(fontSize: 11, color: c.textSecondary),
              ),
              Text(
                '$currentWords',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isWordCountGood ? AppColors.statusCompleted : AppColors.statusProcessing,
                ),
              ),
              Text(
                ' / $targetWords chữ',
                style: TextStyle(fontSize: 11, color: c.textMuted),
              ),
            ],
          ),
          const SizedBox(width: 16),

          // Thống kê Thời lượng ước tính
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.timer_outlined, size: 14, color: AppColors.primary),
              const SizedBox(width: 5),
              Text(
                'Thời lượng: ',
                style: TextStyle(fontSize: 11, color: c.textSecondary),
              ),
              Text(
                _formatDuration(estSec),
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              Text(
                ' / ${_formatDuration(targetSec)}',
                style: TextStyle(fontSize: 11, color: c.textMuted),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDuration(double sec) {
    final m = (sec / 60).floor();
    final s = (sec % 60).floor();
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}
