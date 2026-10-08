import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/app_colors.dart';
import '../controllers/lecture_illustrator_controller.dart';
import '../models/lecture_illustrator_model.dart';
import 'lecture_template_picker_dialog.dart';

class LectureBatchStoryboardCard extends StatelessWidget {
  final LectureBatch batch;
  final bool isSelected;
  final VoidCallback onSelect;
  final LectureIllustratorController controller;
  final String targetLang;

  const LectureBatchStoryboardCard({
    super.key,
    required this.batch,
    required this.isSelected,
    required this.onSelect,
    required this.controller,
    this.targetLang = 'vi',
  });

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
            // ── HEADER THẺ: Intent Tag, Template Tag, Mốc thời gian & Nút Lock ──
            Row(
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
                // Template Selector Chip với Blueprint Picker
                Tooltip(
                  message: 'Bấm để mở Bộ chọn Template trực quan (14 mẫu)',
                  child: InkWell(
                    onTap: () {
                      LectureTemplatePickerDialog.show(
                        context: context,
                        currentTemplate: batch.scene['template']?.toString() ?? 'bullet_list',
                        batch: batch,
                        onSelected: (tmpl) => controller.updateBatchTemplate(batch.id, tmpl),
                      );
                    },
                    borderRadius: BorderRadius.circular(4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: c.surfaceLight,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: c.border.withOpacity(0.8), width: 0.8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.palette_outlined, size: 11, color: c.primary),
                          const SizedBox(width: 4),
                          Text(
                            batch.scene['template']?.toString() ?? 'bullet_list',
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: c.textPrimary),
                          ),
                          const SizedBox(width: 3),
                          Icon(Icons.tune_rounded, size: 11, color: c.primary),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${_formatSec(batch.startSec)} → ${_formatSec(batch.endSec)} (${(batch.endSec - batch.startSec).toStringAsFixed(1)}s)',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: c.textSecondary),
                ),
                const Spacer(),
                if (hasAsset)
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
              ],
            ),
            const SizedBox(height: 8),

            // ── NỘI DUNG THOẠI GỐC & BẢN DỊCH ──
            Text(
              batch.transcriptOriginal,
              style: TextStyle(fontSize: 11.5, color: c.textMuted),
            ),
            const SizedBox(height: 6),
            TextFormField(
              initialValue: batch.transcriptTranslated,
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: Colors.white),
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: c.surfaceDark,
                hintText: 'Bản dịch kịch bản ($langUpper)...',
                hintStyle: TextStyle(fontSize: 11, color: c.textMuted),
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide(color: c.border)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide(color: c.border.withOpacity(0.5))),
              ),
              onChanged: (text) => controller.updateBatchText(batch.id, translated: text),
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
}
