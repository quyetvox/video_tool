import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/app_colors.dart';
import '../controllers/lecture_illustrator_controller.dart';
import '../models/lecture_illustrator_model.dart';
import 'lecture_scene_studio_dialog.dart';

class LectureBatchStoryboardCard extends StatefulWidget {
  final LectureBatch batch;
  final bool isSelected;
  final VoidCallback onSelect;
  final LectureIllustratorController controller;
  final String targetLang;
  final bool isLastBatch;
  final int? index;
  final int? totalBatches;

  const LectureBatchStoryboardCard({
    super.key,
    required this.batch,
    required this.isSelected,
    required this.onSelect,
    required this.controller,
    this.targetLang = 'vi',
    this.isLastBatch = false,
    this.index,
    this.totalBatches,
  });

  @override
  State<LectureBatchStoryboardCard> createState() => _LectureBatchStoryboardCardState();
}

class _LectureBatchStoryboardCardState extends State<LectureBatchStoryboardCard> {
  late TextEditingController _textController;
  bool _isSyncingAudio = false;

  LectureBatch get batch => widget.batch;
  LectureIllustratorController get controller => widget.controller;
  bool get isSelected => widget.isSelected;
  bool get isLastBatch => widget.isLastBatch;
  String get targetLang => widget.targetLang;
  VoidCallback get onSelect => widget.onSelect;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.batch.transcriptTranslated);
  }

  Future<void> _handleSyncAudio() async {
    final text = _textController.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vui lòng không để trống kịch bản phân cảnh.'),
          backgroundColor: AppColors.statusFailed,
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    setState(() => _isSyncingAudio = true);

    final success = await controller.syncBatchAudioAndText(batch.id, text);

    if (mounted) {
      setState(() => _isSyncingAudio = false);
      final lastErr = controller.currentState.lastError;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success
                ? '✨ Đã đồng bộ thoại, tạo giọng đọc & cập nhật timeline cho ${batch.id}!'
                : (lastErr != null && lastErr.isNotEmpty
                    ? '❌ Thất bại: $lastErr'
                    : '❌ Lỗi đồng bộ giọng đọc cho ${batch.id}. Vui lòng thử lại.'),
          ),
          backgroundColor: success ? AppColors.statusCompleted : AppColors.statusFailed,
          duration: Duration(seconds: success ? 3 : 5),
        ),
      );
    }
  }

  @override
  void didUpdateWidget(covariant LectureBatchStoryboardCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.batch.id != widget.batch.id) {
      _textController.text = widget.batch.transcriptTranslated;
    } else if (oldWidget.batch.transcriptTranslated != widget.batch.transcriptTranslated &&
        _textController.text != widget.batch.transcriptTranslated) {
      final prevSelection = _textController.selection;
      _textController.text = widget.batch.transcriptTranslated;
      if (prevSelection.isValid && prevSelection.end <= widget.batch.transcriptTranslated.length) {
        _textController.selection = prevSelection;
      }
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  String _formatSec(double s) {
    final m = (s ~/ 60).toString().padLeft(2, '0');
    final sec = (s % 60).toInt().toString().padLeft(2, '0');
    return '$m:$sec';
  }

  Color _getIntentColor(String intent) {
    switch (intent.toUpperCase()) {
      case 'PROCESS':
        return const Color(0xFF38BDF8); // Sky blue
      case 'DEFINITION':
        return const Color(0xFF34D399); // Emerald
      case 'COMPARISON':
        return const Color(0xFFFBBF24); // Amber
      case 'STRUCTURE':
        return const Color(0xFFA78BFA); // Purple
      case 'MECHANISM':
        return const Color(0xFFF43F5E); // Rose
      case 'FORMULA':
        return const Color(0xFFFB923C); // Orange
      default:
        return const Color(0xFF94A3B8); // Slate
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final hasAsset = batch.activeAsset != null && batch.activeAsset!.filePath.isNotEmpty;
    final intentColor = _getIntentColor(batch.educationalIntent);
    final langUpper = targetLang.toUpperCase();
    final String displayIndex;
    if (widget.index != null) {
      displayIndex = '#${widget.index.toString().padLeft(2, '0')}';
    } else if (batch.id.startsWith('batch_')) {
      displayIndex = '#${batch.id.replaceFirst('batch_', '')}';
    } else {
      displayIndex = '#${batch.id}';
    }

    return InkWell(
      onTap: onSelect,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: isSelected ? c.surfaceLight : c.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? c.primary : c.border.withOpacity(0.6),
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── HEADER THẺ: Checkbox, Intent Tag, Template Tag, Mốc thời gian, Action Buttons ──
            Row(
              children: [
                InkWell(
                  onTap: () => controller.toggleSelectBatch(batch.id),
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Icon(
                      controller.currentState.selectedBatchIds.contains(batch.id)
                          ? Icons.check_box_rounded
                          : Icons.check_box_outline_blank_rounded,
                      size: 16,
                      color: controller.currentState.selectedBatchIds.contains(batch.id)
                          ? c.primary
                          : c.textMuted,
                    ),
                  ),
                ),
                // ── CHỈ THỊ INDEX CỦA BATCH (#01, #02...) ──
                Tooltip(
                  message: 'Phân cảnh $displayIndex${widget.totalBatches != null ? ' / ${widget.totalBatches}' : ''} (${batch.id})',
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
                    margin: const EdgeInsets.only(right: 6),
                    decoration: BoxDecoration(
                      color: c.surfaceLight,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: c.border.withOpacity(0.9), width: 0.8),
                    ),
                    child: Text(
                      displayIndex,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                        color: c.textPrimary,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: intentColor.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: intentColor.withOpacity(0.5), width: 0.8),
                          ),
                          child: Text(
                            batch.educationalIntent.toUpperCase(),
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: intentColor,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        // ── AI Native SVG Badge ──
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981).withOpacity(0.15),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: const Color(0xFF10B981).withOpacity(0.6), width: 0.8),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.auto_awesome, size: 11, color: Color(0xFF10B981)),
                              SizedBox(width: 3),
                              Text(
                                'AI Native SVG',
                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF10B981)),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        // ── Quality Badge Widget (Green >=90, Amber 75-89, Red <75) ──
                        Builder(
                          builder: (bCtx) {
                            final int score = (batch.scene['quality_score'] is num)
                                ? (batch.scene['quality_score'] as num).toInt()
                                : 100;
                            final Color qColor = score >= 90
                                ? const Color(0xFF10B981)
                                : (score >= 75 ? const Color(0xFFF59E0B) : const Color(0xFFEF4444));
                            return Tooltip(
                              message: 'Chất lượng Playwright: $score/100. Bấm để xem chi tiết kiểm định & Auto-Calibration.',
                              child: InkWell(
                                onTap: () => _showQualityDetailsDialog(context, batch.scene),
                                borderRadius: BorderRadius.circular(4),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: qColor.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: qColor.withOpacity(0.7), width: 0.8),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.verified_rounded, size: 11, color: qColor),
                                      const SizedBox(width: 3),
                                      Text(
                                        '$score điểm',
                                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: qColor),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${_formatSec(batch.startSec)} → ${_formatSec(batch.endSec)} (${(batch.endSec - batch.startSec).toStringAsFixed(1)}s)',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: c.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (!isLastBatch) ...[
                  Tooltip(
                    message: 'Gộp phân cảnh này với phân cảnh tiếp theo (tự động vá câu, tính lại thời lượng & tạo lại HTML)',
                    child: InkWell(
                      onTap: () => _confirmAndMergeWithNext(context),
                      borderRadius: BorderRadius.circular(4),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: c.surfaceLight,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: c.border.withOpacity(0.8)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.merge_type_rounded, size: 12, color: c.textSecondary),
                            const SizedBox(width: 4),
                            Text(
                              'Gộp cảnh sau',
                              style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: c.textSecondary),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                Tooltip(
                  message: 'Mở Scene Studio: Xem trước, AI biên tập lại hoặc thay đổi minh họa',
                  child: InkWell(
                    onTap: () {
                      LectureSceneStudioDialog.show(
                        context: context,
                        batch: batch,
                        controller: controller,
                        workspacePath: controller.workspacePath,
                        config: controller.currentConfig,
                      );
                    },
                    borderRadius: BorderRadius.circular(4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: c.surfaceLight,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: c.primary.withOpacity(0.5)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.palette_outlined, size: 12, color: c.primary),
                          const SizedBox(width: 4),
                          Text(
                            'Scene Studio',
                            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: c.primary),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                if (hasAsset) ...[
                  IconButton(
                    iconSize: 16,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    tooltip: batch.activeAsset!.locked ? 'Đã khóa minh họa' : 'Chưa khóa',
                    icon: Icon(
                      batch.activeAsset!.locked ? Icons.lock_rounded : Icons.lock_open_rounded,
                      color: batch.activeAsset!.locked ? c.primary : c.textMuted,
                    ),
                    onPressed: () => controller.toggleBatchLock(batch.id),
                  ),
                  const SizedBox(width: 6),
                ],
                Tooltip(
                  message: 'Xóa phân cảnh này',
                  child: IconButton(
                    iconSize: 15,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: Icon(Icons.delete_outline_rounded, color: c.textMuted),
                    onPressed: () => _confirmDeleteThisBatch(context),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // ── NỘI DUNG THOẠI GỐC & BẢN DỊCH ──
            Text(
              batch.transcriptOriginal,
              style: TextStyle(fontSize: 11.5, color: c.textMuted),
            ),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _textController,
                    minLines: 2,
                    maxLines: 6,
                    keyboardType: TextInputType.multiline,
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: Colors.white, height: 1.35),
                    decoration: InputDecoration(
                      isDense: true,
                      filled: true,
                      fillColor: c.surfaceDark,
                      hintText: 'Bản dịch kịch bản ($langUpper)...',
                      hintStyle: TextStyle(fontSize: 11, color: c.textMuted),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: c.border)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: c.border.withOpacity(0.5))),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: c.primary, width: 1.2)),
                    ),
                    onChanged: (text) => controller.updateBatchText(batch.id, translated: text),
                  ),
                ),
                const SizedBox(width: 8),
                Tooltip(
                  message: _isSyncingAudio
                      ? 'Đang tổng hợp giọng đọc và cập nhật timeline...'
                      : 'Lưu & gọi TTS tạo lại giọng đọc cho phân cảnh này',
                  child: InkWell(
                    onTap: _isSyncingAudio ? null : _handleSyncAudio,
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      height: 54,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: _isSyncingAudio ? c.surfaceDark.withOpacity(0.5) : c.surfaceDark,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: _isSyncingAudio ? c.primary.withOpacity(0.3) : c.primary.withOpacity(0.6),
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (_isSyncingAudio)
                            SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(c.primary),
                              ),
                            )
                          else
                            Icon(Icons.record_voice_over_rounded, size: 15, color: c.primary),
                          const SizedBox(height: 3),
                          Text(
                            _isSyncingAudio ? 'Đang tạo...' : 'Đồng bộ TTS',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                              color: _isSyncingAudio ? c.primary.withOpacity(0.7) : c.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // ── GÓI PROMPT PACK 3-TRONG-1 (1-CLICK COPY) ──
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: c.surfaceDark.withOpacity(0.6),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: c.border.withOpacity(0.4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.auto_awesome, size: 12, color: c.primary),
                      const SizedBox(width: 4),
                      Text('Gói Prompt Tạo Minh Họa:', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: c.textSecondary)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      // Nút 1: Copy Prompt Ảnh (English)
                      if (batch.prompts.imagePrompt.isNotEmpty)
                        _buildCopyPromptButton(
                          context,
                          c,
                          icon: Icons.image_outlined,
                          label: 'Copy Prompt Ảnh (AI)',
                          textToCopy: batch.prompts.imagePrompt,
                          toastMsg: 'Đã sao chép Prompt Tạo Ảnh (Midjourney/Flux/SD)!',
                          tooltip: 'Prompt Tiếng Anh chuyên sâu (Midjourney/Flux, không dính chữ gốc)',
                        ),

                      // Nút 2: Copy Code Sơ Đồ Mermaid (Ngôn ngữ đích)
                      if (batch.prompts.diagramMermaid.isNotEmpty)
                        _buildCopyPromptButton(
                          context,
                          c,
                          icon: Icons.schema_outlined,
                          label: 'Copy Code Sơ Đồ (Mermaid)',
                          textToCopy: batch.prompts.diagramMermaid,
                          toastMsg: 'Đã sao chép mã sơ đồ Mermaid.js!',
                          tooltip: 'Mã sơ đồ Mermaid ($langUpper)',
                        ),

                      // Nút 3: Copy Animation Concept (Ngôn ngữ đích)
                      if (batch.prompts.animationConcept.isNotEmpty)
                        _buildCopyPromptButton(
                          context,
                          c,
                          icon: Icons.animation_outlined,
                          label: 'Copy Ý Tưởng Chuyển Động',
                          textToCopy: batch.prompts.animationConcept,
                          toastMsg: 'Đã sao chép ý tưởng chuyển động!',
                          tooltip: 'Kịch bản chuyển động ($langUpper)',
                        ),

                      // Nút 4: Copy Animation Code (Dành riêng cho bài giảng lập trình)
                      if (batch.prompts.codeAnimation.isNotEmpty)
                        _buildCopyPromptButton(
                          context,
                          c,
                          icon: Icons.terminal_rounded,
                          label: 'Copy Animation Code',
                          textToCopy: batch.prompts.codeAnimation,
                          toastMsg: 'Đã sao chép Kịch bản Animation Code Minh Họa!',
                          tooltip: 'Kịch bản gõ code minh họa ($langUpper)',
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // ── DROPZONE / GÁN ASSET HÌNH ẢNH ──
            _buildAssetZone(context, c, hasAsset),
          ],
        ),
      ),
    );
  }

  Widget _buildCopyPromptButton(
    BuildContext context,
    AppFallbackPalette c, {
    required IconData icon,
    required String label,
    required String textToCopy,
    required String toastMsg,
    String? tooltip,
  }) {
    final btn = InkWell(
      onTap: () {
        Clipboard.setData(ClipboardData(text: textToCopy));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(toastMsg, style: const TextStyle(fontSize: 11)),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      },
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        decoration: BoxDecoration(
          color: c.surfaceLight,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: c.border.withOpacity(0.6)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: c.primary),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w500, color: c.textPrimary)),
          ],
        ),
      ),
    );
    if (tooltip != null && tooltip.isNotEmpty) {
      return Tooltip(message: tooltip, child: btn);
    }
    return btn;
  }

  Widget _buildAssetZone(BuildContext context, AppFallbackPalette c, bool hasAsset) {
    if (hasAsset) {
      final file = File(batch.activeAsset!.filePath);
      final isImage = ['png', 'jpg', 'jpeg', 'webp'].contains(file.path.split('.').last.toLowerCase());

      return Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: c.surfaceDark,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: c.primary.withOpacity(0.5)),
        ),
        child: Row(
          children: [
            if (isImage && file.existsSync())
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Image.file(
                  file,
                  width: 48,
                  height: 36,
                  fit: BoxFit.cover,
                ),
              )
            else
              Container(
                width: 48,
                height: 36,
                decoration: BoxDecoration(color: c.surfaceLight, borderRadius: BorderRadius.circular(4)),
                child: Icon(Icons.movie_outlined, size: 20, color: c.primary),
              ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    file.uri.pathSegments.last,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white),
                  ),
                  Text(
                    'Bố cục: ${batch.activeAsset!.layout.toUpperCase()}',
                    style: TextStyle(fontSize: 10, color: c.textMuted),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close_rounded, size: 15, color: Colors.redAccent),
              onPressed: () => controller.clearBatchAsset(batch.id),
              tooltip: 'Gỡ asset khỏi phân đoạn này',
            ),
          ],
        ),
      );
    }

    return InkWell(
      onTap: () async {
        final res = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['png', 'jpg', 'jpeg', 'webp', 'mp4', 'mov', 'svg'],
        );
        if (res != null && res.files.single.path != null) {
          controller.assignAssetToBatch(
            batch.id,
            filePath: res.files.single.path!,
            type: res.files.single.path!.endsWith('.mp4') ? 'video' : 'image',
          );
        }
      },
      borderRadius: BorderRadius.circular(6),
      child: Container(
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: c.surfaceDark.withOpacity(0.4),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: c.border.withOpacity(0.5), style: BorderStyle.solid),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_photo_alternate_outlined, size: 15, color: c.textMuted),
            const SizedBox(width: 6),
            Text(
              'Bấm chọn hoặc kéo thả ảnh/sơ đồ minh họa vào đây',
              style: TextStyle(fontSize: 10.5, color: c.textMuted),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmAndMergeWithNext(BuildContext context) {
    final c = AppColors.of(context);
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: c.surface,
        title: Row(
          children: [
            Icon(Icons.merge_type_rounded, color: c.primary, size: 20),
            const SizedBox(width: 8),
            const Text('Gộp với phân cảnh sau?', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          'Phân cảnh ${batch.id} sẽ được gộp liền mạch với phân cảnh tiếp theo thành một cụm tri thức duy nhất.\n\n'
          '• Tự động vá các câu kết thúc dở dang (dấu phẩy, liên từ).\n'
          '• Tính toán lại mốc thời gian (timeline).\n'
          '• Yêu cầu AI tái tạo mã HTML động và render lại clip xem trước.',
          style: TextStyle(fontSize: 13, color: c.textSecondary, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: Text('Hủy', style: TextStyle(color: c.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: c.primary,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.of(dialogCtx).pop();
              controller.mergeBatchWithNext(batchId: batch.id);
            },
            child: const Text('Đồng ý gộp', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteThisBatch(BuildContext context) {
    final c = AppColors.of(context);
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: c.surface,
        title: const Row(
          children: [
            Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
            SizedBox(width: 8),
            Text('Xóa phân cảnh này?', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          'Bạn có chắc chắn muốn xóa phân cảnh ${batch.id}?\n\n'
          'Hệ thống sẽ xóa phân cảnh, thu dọn các tệp liên quan và tự động dồn lại mốc thời gian (timeline).',
          style: TextStyle(fontSize: 13, color: c.textSecondary, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: Text('Hủy', style: TextStyle(color: c.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.of(dialogCtx).pop();
              controller.deleteBatch(batch.id);
            },
            child: const Text('Xóa ngay', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showQualityDetailsDialog(BuildContext context, Map<String, dynamic> scene) {
    final c = AppColors.of(context);
    final int score = (scene['quality_score'] is num) ? (scene['quality_score'] as num).toInt() : 100;
    final List<dynamic> calibrations = (scene['calibrations'] is List) ? (scene['calibrations'] as List) : [];
    final Map<String, dynamic> evalDetails = (scene['eval_details'] is Map) ? (scene['eval_details'] as Map<String, dynamic>) : {};

    final Color scoreColor = score >= 90
        ? const Color(0xFF10B981)
        : (score >= 75 ? const Color(0xFFF59E0B) : const Color(0xFFEF4444));

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: c.border)),
        title: Row(
          children: [
            Icon(Icons.verified_rounded, color: scoreColor, size: 22),
            const SizedBox(width: 8),
            Text('Kiểm Định Chất Lượng HTML/SVG', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: c.textPrimary)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: scoreColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: scoreColor.withOpacity(0.6)),
              ),
              child: Text(
                '$score / 100đ',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: scoreColor),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Playwright Headless Quality Gate tự động kiểm chứng 4 tiêu chuẩn sư phạm:',
                style: TextStyle(fontSize: 12, color: c.textSecondary),
              ),
              const SizedBox(height: 12),
              _buildQualityCriteriaRow('Đồng bộ nhịp điệu (Timing)', evalDetails['timing_passed'] != false, 'Các mốc thời gian tăng dần và khớp với thoại', c),
              const SizedBox(height: 8),
              _buildQualityCriteriaRow('Vùng an toàn phụ đề (Exclusion Zone)', evalDetails['subtitle_safe'] != false, 'Không có phần tử đồ họa/chữ lấn vào vùng phụ đề', c),
              const SizedBox(height: 8),
              _buildQualityCriteriaRow('Kích thước chữ (Min-Font Gate)', evalDetails['font_passed'] != false, 'Đảm bảo cỡ chữ font Patrick Hand đạt chuẩn đọc rõ (≥ 22px)', c),
              const SizedBox(height: 8),
              _buildQualityCriteriaRow('Chống chồng chéo (AABB Collision)', evalDetails['collision_passed'] != false, 'Các khối đối tượng cách nhau tối thiểu, không đè lên nhau', c),
              const SizedBox(height: 14),
              const Divider(height: 1),
              const SizedBox(height: 12),
              Text(
                'Tự Động Nắn Chỉnh (Auto-Calibration):',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: c.textPrimary),
              ),
              const SizedBox(height: 6),
              if (calibrations.isNotEmpty) ...[
                ...calibrations.map((calib) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.check_circle_outline_rounded, size: 14, color: Color(0xFF10B981)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          calib.toString(),
                          style: TextStyle(fontSize: 11.5, color: c.textSecondary),
                        ),
                      ),
                    ],
                  ),
                )),
              ] else ...[
                Text(
                  'Mã SVG đạt chuẩn trực tiếp từ AI, không cần can thiệp nắn chỉnh.',
                  style: TextStyle(fontSize: 11.5, fontStyle: FontStyle.italic, color: c.textSecondary),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Đóng'),
          ),
        ],
      ),
    );
  }

  Widget _buildQualityCriteriaRow(String title, bool passed, String desc, dynamic c) {
    final color = passed ? const Color(0xFF10B981) : const Color(0xFFEF4444);
    final icon = passed ? Icons.check_circle_rounded : Icons.cancel_rounded;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c.textPrimary)),
              Text(desc, style: TextStyle(fontSize: 11, color: c.textSecondary)),
            ],
          ),
        ),
      ],
    );
  }
}
