import 'package:flutter/material.dart';
import '../../../core/app_colors.dart';
import '../../../models/studio_draft.dart';
import '../../../models/studio_state.dart';
import '../../../models/video_file.dart';
import '../../../widgets/app_kit.dart';

/// Top Header Toolbar for Video Studio.
/// Contains tool mode indicator, selected video badge, undo/redo, draft actions, and primary Export CTA.
class StudioHeaderToolbar extends StatelessWidget {
  final StudioToolMode toolMode;
  final VideoFile? selectedVideo;
  final bool canUndo;
  final bool canRedo;
  final VoidCallback? onUndo;
  final VoidCallback? onRedo;
  final StudioDraft? activeDraft;
  final List<StudioDraft> availableDrafts;
  final VoidCallback? onSaveDraft;
  final VoidCallback? onShowDraftsMenu;
  final VoidCallback? onClearSession;
  final bool isProcessing;
  final double exportProgress;
  final VoidCallback? onExport;

  const StudioHeaderToolbar({
    super.key,
    required this.toolMode,
    required this.selectedVideo,
    required this.canUndo,
    required this.canRedo,
    this.onUndo,
    this.onRedo,
    this.activeDraft,
    required this.availableDrafts,
    this.onSaveDraft,
    this.onShowDraftsMenu,
    this.onClearSession,
    required this.isProcessing,
    required this.exportProgress,
    this.onExport,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);

    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(bottom: BorderSide(color: c.border)),
      ),
      child: Row(
        children: [
          Icon(
            toolMode == StudioToolMode.cut
                ? Icons.content_cut
                : (toolMode == StudioToolMode.split
                    ? Icons.splitscreen
                    : (toolMode == StudioToolMode.merge ? Icons.layers : Icons.auto_awesome_mosaic)),
            size: 16,
            color: toolMode == StudioToolMode.cut ? AppColors.statusFailed : AppColors.primary,
          ),
          const SizedBox(width: 8),
          Text(
            'Biên tập & Ghép nối',
            style: TextStyle(color: c.textSecondary, fontSize: 11.5),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 6),
            child: Text('›', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
          ),
          Text(
            toolMode == StudioToolMode.cut
                ? 'Cắt bỏ rác (Cut)'
                : (toolMode == StudioToolMode.split
                    ? 'Chia clip (Split)'
                    : (toolMode == StudioToolMode.merge ? 'Ghép video (Merge)' : 'Biên tập đa lớp')),
            style: TextStyle(
              color: toolMode == StudioToolMode.cut ? AppColors.statusFailed : AppColors.primary,
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
            ),
          ),

          const SizedBox(width: 16),

          // Active Video Switcher pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.12),
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: AppColors.primary.withOpacity(0.35)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.movie_outlined, size: 12, color: AppColors.primary),
                const SizedBox(width: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 160),
                  child: Text(
                    selectedVideo?.basename ?? 'Chọn video từ sidebar',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),

          const Spacer(),

          // Undo / Redo using AppIconButton
          AppIconButton(
            icon: Icons.undo,
            color: canUndo ? c.textPrimary : c.textMuted,
            tooltip: 'Hoàn tác (Ctrl+Z)',
            onPressed: canUndo ? onUndo : null,
          ),
          const SizedBox(width: 2),
          AppIconButton(
            icon: Icons.redo,
            color: canRedo ? c.textPrimary : c.textMuted,
            tooltip: 'Làm lại (Ctrl+Shift+Z)',
            onPressed: canRedo ? onRedo : null,
          ),

          const SizedBox(width: 8),

          // 💾 Save Draft Button
          AppButton.outlined(
            icon: Icons.save_outlined,
            label: activeDraft != null ? '💾 Lưu (${activeDraft!.name})' : 'Lưu nháp',
            fontSize: 10.5,
            onPressed: onSaveDraft,
          ),
          const SizedBox(width: 6),

          // 📂 Drafts Switcher Button
          AppButton(
            variant: availableDrafts.isNotEmpty ? AppButtonVariant.secondary : AppButtonVariant.outlined,
            icon: Icons.folder_open_rounded,
            label: 'Bản nháp (${availableDrafts.length}) ▾',
            fontSize: 10.5,
            onPressed: onShowDraftsMenu,
          ),
          const SizedBox(width: 6),

          // 🗑️ Clear Session Button
          AppButton(
            variant: AppButtonVariant.outlined,
            icon: Icons.refresh_rounded,
            label: 'Làm mới',
            fontSize: 10.5,
            onPressed: onClearSession,
          ),
          const SizedBox(width: 8),

          // Master Export CTA Button
          AppButton.primary(
            icon: Icons.download,
            isLoading: isProcessing,
            label: isProcessing
                ? (toolMode == StudioToolMode.composite && exportProgress > 0
                    ? 'Đang Render... ${(exportProgress * 100).toInt()}%'
                    : 'Đang Xử Lý...')
                : (toolMode == StudioToolMode.cut
                    ? 'Cắt bỏ rác & Xuất'
                    : (toolMode == StudioToolMode.split
                        ? 'Xuất các đoạn chia'
                        : (toolMode == StudioToolMode.composite ? 'Xuất Video Đa Lớp' : 'Ghép & Xuất video'))),
            fontSize: 11.0,
            onPressed: isProcessing ? null : onExport,
          ),
        ],
      ),
    );
  }
}
