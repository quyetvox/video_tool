import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

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
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: c.surfaceDark,
              border: Border(bottom: BorderSide(color: c.border, width: 0.8)),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  if (state.batches.isNotEmpty) ...[
                    Tooltip(
                      message: state.selectedBatchIds.length == state.batches.length
                          ? 'Bỏ chọn tất cả'
                          : 'Chọn tất cả phân cảnh',
                      child: InkWell(
                        onTap: () {
                          final isAll = state.selectedBatchIds.length == state.batches.length;
                          controller.selectAllBatches(!isAll);
                        },
                        borderRadius: BorderRadius.circular(4),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          child: Icon(
                            state.selectedBatchIds.length == state.batches.length
                                ? Icons.check_box_rounded
                                : (state.selectedBatchIds.isNotEmpty
                                    ? Icons.indeterminate_check_box_rounded
                                    : Icons.check_box_outline_blank_rounded),
                            size: 16,
                            color: state.selectedBatchIds.isNotEmpty ? c.primary : c.textMuted,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Icon(Icons.dashboard_outlined, size: 15, color: c.primary),
                  const SizedBox(width: 8),
                  Text(
                    'Kịch Bản Phân Đoạn & Prompt Pack (${state.batches.length})',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 14),
                  if (hasVideo) ...[
                    AppButton(
                      label: '+ Thêm Phân Cảnh',
                      icon: Icons.add_rounded,
                      variant: AppButtonVariant.secondary,
                      onPressed: isProcessing ? null : () => _showAddBatchDialog(context),
                    ),
                    const SizedBox(width: 8),
                  ],
                  if (hasVideo && state.batches.isNotEmpty) ...[
                    Tooltip(
                      message: 'Nhập thư mục file HTML và tự động phân bổ theo tên file',
                      child: AppButton(
                        label: 'Import Folder HTML',
                        icon: Icons.folder_open_rounded,
                        variant: AppButtonVariant.secondary,
                        onPressed: isProcessing ? null : () => _handleImportHtmlFolder(context),
                      ),
                    ),
                    const SizedBox(width: 8),
                    AppButton(
                      label: 'Copy kịch bản',
                      icon: Icons.copy_all_rounded,
                      variant: AppButtonVariant.secondary,
                      onPressed: isProcessing ? null : () => _handleCopyAllBatches(context),
                    ),
                    const SizedBox(width: 8),
                  ],
                  if (hasVideo)
                    AppButton(
                      label: isProcessing ? 'Đang chạy...' : 'Phân tích lại',
                      icon: Icons.refresh_rounded,
                      variant: AppButtonVariant.secondary,
                      onPressed: isProcessing ? null : () => showConfirmAndReanalyze(context, controller, hasExistingBatches: state.batches.isNotEmpty),
                    ),
                ],
              ),
            ),
          ),

          // ── ACTION BAR KHI CÓ BATCH ĐƯỢC CHỌN ──
          if (state.selectedBatchIds.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: c.primary.withOpacity(0.12),
                border: Border(bottom: BorderSide(color: c.primary.withOpacity(0.3), width: 1.0)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: c.primary.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'Đã chọn: ${state.selectedBatchIds.length}/${state.batches.length}',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: c.primary),
                    ),
                  ),
                  const SizedBox(width: 10),
                  AppButton.primary(
                    label: state.isBatchReauthoring
                        ? 'Đang tái tạo (${(state.batchReauthorProgress * 100).toInt()}%)...'
                        : 'Tái tạo đã chọn (${state.selectedBatchIds.length})',
                    icon: Icons.auto_awesome,
                    isLoading: state.isBatchReauthoring,
                    onPressed: (isProcessing || state.isBatchReauthoring)
                        ? null
                        : () => controller.reauthorSelectedBatches(),
                  ),
                  const SizedBox(width: 8),
                  AppButton(
                    label: 'Xóa đã chọn',
                    icon: Icons.delete_outline_rounded,
                    variant: AppButtonVariant.danger,
                    onPressed: (isProcessing || state.isBatchReauthoring)
                        ? null
                        : () => _confirmDeleteSelected(context),
                  ),
                  const Spacer(),
                  IconButton(
                    iconSize: 16,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    tooltip: 'Bỏ chọn tất cả',
                    icon: Icon(Icons.close_rounded, color: c.textMuted),
                    onPressed: () => controller.selectAllBatches(false),
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
                        index: idx + 1,
                        totalBatches: state.batches.length,
                        isSelected: state.selectedBatchId == batch.id,
                        onSelect: () => controller.selectBatch(batch.id),
                        controller: controller,
                        targetLang: state.config.targetLang,
                        isLastBatch: idx == state.batches.length - 1,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  void _handleCopyAllBatches(BuildContext context) {
    if (state.batches.isEmpty) return;
    final text = controller.generateAllBatchesInputData();
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('📋 Đã sao chép kịch bản của ${state.batches.length} phân đoạn vào Clipboard!'),
        backgroundColor: AppColors.statusCompleted,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  /// Hiển thị Confirm Dialog và thực hiện xóa toàn bộ cache rồi phân tích lại
  static Future<void> showConfirmAndReanalyze(
    BuildContext context,
    LectureIllustratorController controller, {
    required bool hasExistingBatches,
  }) async {
    if (!hasExistingBatches) {
      await controller.startAnalysis();
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) {
        final c = AppColors.of(context);
        return AlertDialog(
          backgroundColor: c.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: c.warning, size: 22),
              const SizedBox(width: 8),
              const Text(
                'Xác nhận phân tích lại',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: Text(
            'Hành động này sẽ xóa toàn bộ cache cũ (ASR, kịch bản, metadata và toàn bộ các scene đã tạo) và phân tích lại từ đầu cũng như sinh lại toàn bộ các scene mới.\n\nBạn có chắc chắn muốn tiếp tục không?',
            style: TextStyle(fontSize: 13, color: c.textSecondary, height: 1.4),
          ),
          actions: [
            AppButton(
              label: 'Hủy',
              variant: AppButtonVariant.ghost,
              onPressed: () => Navigator.of(dialogCtx).pop(false),
            ),
            AppButton(
              label: 'Xóa Cache & Phân Tích Lại',
              icon: Icons.refresh_rounded,
              variant: AppButtonVariant.primary,
              onPressed: () => Navigator.of(dialogCtx).pop(true),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      await controller.reanalyzeWithCleanCache();
    }
  }

  void _showAddBatchDialog(BuildContext context) {
    final textController = TextEditingController();
    int? selectedIndex = state.batches.length;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          backgroundColor: AppColors.of(context).surface,
          title: const Row(
            children: [
              Icon(Icons.add_circle_outline_rounded, color: AppColors.primary, size: 20),
              SizedBox(width: 8),
              Text('Thêm Phân Cảnh Bài Giảng Mới', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            ],
          ),
          content: SizedBox(
            width: 540,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Nội dung kịch bản / câu thoại mới:',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: textController,
                  maxLines: 4,
                  autofocus: true,
                  style: const TextStyle(fontSize: 12.5),
                  decoration: InputDecoration(
                    hintText: 'Nhập nội dung thoại bài giảng tại đây (hệ thống sẽ tự động gọi giọng đọc TTS và đo thời lượng chuẩn xác)...',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                    contentPadding: const EdgeInsets.all(10),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Text('Vị trí chèn:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        value: selectedIndex,
                        isDense: true,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        ),
                        items: [
                          DropdownMenuItem<int>(
                            value: state.batches.length,
                            child: const Text('Chèn vào cuối bài giảng', style: TextStyle(fontSize: 12)),
                          ),
                          for (int i = 0; i < state.batches.length; i++)
                            DropdownMenuItem<int>(
                              value: i,
                              child: Text('Chèn trước Cảnh ${i + 1} (${state.batches[i].id})', style: const TextStyle(fontSize: 12)),
                            ),
                        ],
                        onChanged: (val) => setDlgState(() => selectedIndex = val),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Hủy'),
            ),
            AppButton.primary(
              label: 'Tạo Phân Cảnh (TTS & Timeline)',
              icon: Icons.check_rounded,
              onPressed: () {
                final text = textController.text.trim();
                if (text.isEmpty) return;
                Navigator.pop(ctx);
                controller.addNewBatch(text: text, insertIndex: selectedIndex);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDeleteSelected(BuildContext context) {
    final count = state.selectedBatchIds.length;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.of(context).surface,
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppColors.statusFailed, size: 20),
            SizedBox(width: 8),
            Text('Xác Nhận Xóa Phân Cảnh', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          'Bạn có chắc chắn muốn xóa $count phân cảnh đã chọn? Toàn bộ mốc thời gian của các phân cảnh kế tiếp sẽ được tự động dồn lại liền mạch.',
          style: const TextStyle(fontSize: 12),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy'),
          ),
          AppButton(
            label: 'Xóa $count Phân Cảnh',
            icon: Icons.delete_rounded,
            variant: AppButtonVariant.danger,
            onPressed: () {
              Navigator.pop(ctx);
              controller.deleteSelectedBatches();
            },
          ),
        ],
      ),
    );
  }

  Future<String?> _resolveDownloadsDirectory() async {
    try {
      final dir = await getDownloadsDirectory();
      if (dir != null && dir.existsSync()) {
        return dir.path;
      }
    } catch (_) {}

    final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    if (home != null && home.isNotEmpty) {
      final d = Directory('$home/Downloads');
      if (d.existsSync()) {
        return d.path;
      }
    }
    return null;
  }

  Future<void> _handleImportHtmlFolder(BuildContext context) async {
    final initialDir = await _resolveDownloadsDirectory();
    final selectedDir = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Chọn thư mục chứa các file HTML phân cảnh',
      initialDirectory: initialDir,
    );

    if (selectedDir != null && context.mounted) {
      final res = await controller.importFolderHtml(folderPath: selectedDir);
      if (context.mounted) {
        final bool success = res['success'] == true;
        final int matched = res['totalMatched'] ?? 0;
        final lastErr = res['error']?.toString() ?? controller.currentState.lastError;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              success
                  ? '✨ Đã nạp thành công $matched file HTML vào các phân cảnh tương ứng!'
                  : (lastErr != null && lastErr.isNotEmpty
                      ? '❌ $lastErr'
                      : '❌ Lỗi khi nạp thư mục HTML.'),
            ),
            backgroundColor: success ? AppColors.statusCompleted : AppColors.statusFailed,
            duration: Duration(seconds: success ? 4 : 5),
          ),
        );
      }
    }
  }
}
