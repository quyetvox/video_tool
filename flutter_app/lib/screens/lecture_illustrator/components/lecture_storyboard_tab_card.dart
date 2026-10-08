import 'package:flutter/material.dart';

import '../../../../core/app_colors.dart';
import '../../../../widgets/app_kit.dart';
import '../controllers/lecture_illustrator_controller.dart';
import '../models/lecture_illustrator_model.dart';
import 'lecture_batch_storyboard_card.dart';

class LectureStoryboardTabCard extends StatelessWidget {
  final LectureIllustratorState state;
  final LectureIllustratorController controller;

  const LectureStoryboardTabCard({
    super.key,
    required this.state,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final hasVideo = state.videoPath != null && state.videoPath!.isNotEmpty;
    final isProcessing = state.isAnalyzing || state.isRendering;

    return Container(
      color: c.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── HEADER THANH CÔNG CỤ STORYBOARD ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: c.surfaceDark,
              border: Border(bottom: BorderSide(color: c.border, width: 0.8)),
            ),
            child: Row(
              children: [
                Icon(Icons.dashboard_outlined, size: 15, color: c.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Kịch Bản Phân Đoạn & Prompt Pack (${state.batches.length})',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (hasVideo)
                  AppButton(
                    label: isProcessing ? 'Đang chạy...' : 'Phân tích lại',
                    icon: Icons.refresh_rounded,
                    variant: AppButtonVariant.secondary,
                    onPressed: isProcessing ? null : () => controller.startAnalysis(),
                  ),
              ],
            ),
          ),

          // ── DANH SÁCH CÁC THẺ PHÂN ĐOÀN HOẶC TRẠNG THÁI RỖNG ──
          Expanded(
            child: state.batches.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.psychology_alt_outlined, size: 48, color: c.textMuted),
                          const SizedBox(height: 12),
                          Text(
                            'Chưa có dữ liệu phân đoạn bài giảng',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: c.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Bấm nút bên dưới để AI tự động trích xuất ý đồ sư phạm, dựng storyboard và tạo prompt animation.',
                            style: TextStyle(fontSize: 11, color: c.textMuted, height: 1.4),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          AppButton.primary(
                            label: isProcessing ? 'Đang phân tích...' : 'Phân Tích Bài Giảng (AI)',
                            icon: Icons.auto_awesome,
                            onPressed: (hasVideo && !isProcessing)
                                ? () => controller.startAnalysis()
                                : null,
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: state.batches.length,
                    itemBuilder: (context, idx) {
                      final batch = state.batches[idx];
                      return LectureBatchStoryboardCard(
                        batch: batch,
                        isSelected: state.selectedBatchId == batch.id,
                        onSelect: () => controller.selectBatch(batch.id),
                        controller: controller,
                        targetLang: state.config.targetLang,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
