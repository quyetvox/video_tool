import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../../../core/app_colors.dart';
import '../../../../widgets/app_kit.dart';
import '../../../../widgets/video_player_widget.dart';
import '../controllers/lecture_illustrator_controller.dart';
import '../models/lecture_illustrator_model.dart';

class LectureSceneStudioDialog extends StatefulWidget {
  final LectureBatch batch;
  final LectureIllustratorController controller;
  final String workspacePath;
  final LectureProjectConfig config;

  const LectureSceneStudioDialog({
    super.key,
    required this.batch,
    required this.controller,
    required this.workspacePath,
    required this.config,
  });

  static Future<void> show({
    required BuildContext context,
    required LectureBatch batch,
    required LectureIllustratorController controller,
    required String workspacePath,
    required LectureProjectConfig config,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => LectureSceneStudioDialog(
        batch: batch,
        controller: controller,
        workspacePath: workspacePath,
        config: config,
      ),
    );
  }

  @override
  State<LectureSceneStudioDialog> createState() => _LectureSceneStudioDialogState();
}

class _LectureSceneStudioDialogState extends State<LectureSceneStudioDialog> {
  final TextEditingController _feedbackController = TextEditingController();
  bool _isGenerating = false;
  int _playerRefreshKey = 0;

  @override
  void dispose() {
    _feedbackController.dispose();
    super.dispose();
  }

  String _formatSec(double s) {
    final m = (s ~/ 60).toString().padLeft(2, '0');
    final sec = (s % 60).toInt().toString().padLeft(2, '0');
    return '$m:$sec';
  }

  LectureBatch get _currentBatch {
    try {
      return widget.controller.currentState.batches.firstWhere(
        (b) => b.id == widget.batch.id,
        orElse: () => widget.batch,
      );
    } catch (_) {
      return widget.batch;
    }
  }

  String? _resolvePreviewVideo(LectureBatch b) {
    final combined = p.join(widget.workspacePath, 'scenes', '${b.id}_combined.mp4');
    if (File(combined).existsSync()) return combined;

    final videoOnly = p.join(widget.workspacePath, 'scenes', '${b.id}_video.mp4');
    if (File(videoOnly).existsSync()) return videoOnly;

    if (b.activeAsset != null && b.activeAsset!.filePath.isNotEmpty) {
      final ext = p.extension(b.activeAsset!.filePath).toLowerCase();
      if (['.mp4', '.mov', '.webm', '.mkv'].contains(ext) && File(b.activeAsset!.filePath).existsSync()) {
        return b.activeAsset!.filePath;
      }
    }

    return null;
  }

  void _handleCopyPrompt() {
    final prompt = widget.controller.generatePromptForBatch(_currentBatch);
    Clipboard.setData(ClipboardData(text: prompt));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('📋 Đã sao chép Master Prompt của Scene ${_currentBatch.id}! Bạn có thể dán vào ChatGPT / Gemini.'),
        backgroundColor: AppColors.statusCompleted,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _handlePickHtml() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['html', 'htm'],
    );
    if (res != null && res.files.single.path != null && mounted) {
      final pickedPath = res.files.single.path!;
      setState(() => _isGenerating = true);
      final success = await widget.controller.importBatchHtml(
        batchId: widget.batch.id,
        htmlFilePath: pickedPath,
      );
      if (mounted) {
        setState(() {
          _isGenerating = false;
          _playerRefreshKey++;
        });
        final err = widget.controller.currentState.lastError;
        final failMsg = err != null && err.isNotEmpty
            ? '❌ Import HTML thất bại: $err'
            : '❌ Import HTML thất bại, vui lòng kiểm tra console.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              success
                  ? '🌐 Đã import & căn chỉnh tốc độ Scene ${widget.batch.id} thành công!'
                  : failMsg,
            ),
            backgroundColor: success ? AppColors.statusCompleted : AppColors.statusFailed,
            duration: Duration(seconds: success ? 3 : 5),
          ),
        );
      }
    }
  }

  Future<void> _handlePasteHtmlCode() async {
    final codeController = TextEditingController();
    final htmlCode = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.code_rounded, color: AppColors.primary, size: 20),
            const SizedBox(width: 8),
            Text('Dán Mã HTML cho Scene ${widget.batch.id}',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          ],
        ),
        content: SizedBox(
          width: 650,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Dán mã HTML (<!DOCTYPE html>... hoặc SVG):',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                  TextButton.icon(
                    icon: const Icon(Icons.content_paste_rounded, size: 14),
                    label: const Text('Dán từ Clipboard', style: TextStyle(fontSize: 11)),
                    onPressed: () async {
                      final data = await Clipboard.getData(Clipboard.kTextPlain);
                      if (data?.text != null && data!.text!.isNotEmpty) {
                        codeController.text = data.text!;
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.of(context).surfaceDark,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppColors.of(context).border),
                ),
                child: TextField(
                  controller: codeController,
                  maxLines: 14,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 11.5),
                  decoration: const InputDecoration(
                    hintText:
                        '<!DOCTYPE html>\n<html>\n<head>...\n<body>\n  <svg id="svg" viewBox="0 0 1920 1080">...\n  <script>\n    window.__renderAt = function(t, stepStarts) { ... }\n  </script>\n</body>\n</html>',
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.all(10),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('Hủy'),
          ),
          AppButton.primary(
            label: 'Xác Nhận Import Code',
            icon: Icons.check_circle_outline_rounded,
            onPressed: () {
              final text = codeController.text.trim();
              if (text.isNotEmpty) {
                Navigator.pop(ctx, text);
              }
            },
          ),
        ],
      ),
    );

    if (htmlCode != null && htmlCode.isNotEmpty && mounted) {
      setState(() => _isGenerating = true);
      final success = await widget.controller.importBatchHtmlCode(
        batchId: widget.batch.id,
        htmlContent: htmlCode,
      );

      if (mounted) {
        setState(() {
          _isGenerating = false;
          _playerRefreshKey++;
        });
        final err = widget.controller.currentState.lastError;
        final failMsg = err != null && err.isNotEmpty
            ? '❌ Import mã HTML thất bại: $err'
            : '❌ Import mã HTML thất bại, vui lòng kiểm tra console.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              success
                  ? '✨ Đã import mã HTML và cân chỉnh Scene ${widget.batch.id} thành công!'
                  : failMsg,
            ),
            backgroundColor: success ? AppColors.statusCompleted : AppColors.statusFailed,
            duration: Duration(seconds: success ? 3 : 5),
          ),
        );
      }
    }
  }

  Future<void> _handleReauthor() async {
    final feedback = _feedbackController.text.trim();
    setState(() => _isGenerating = true);

    final success = await widget.controller.reauthorBatchWithAi(
      batchId: widget.batch.id,
      feedback: feedback,
    );

    if (mounted) {
      setState(() {
        _isGenerating = false;
        _playerRefreshKey++;
      });
      final err = widget.controller.currentState.lastError;
      final failMsg = err != null && err.isNotEmpty ? '❌ Tái tạo Scene thất bại: $err' : '❌ Tái tạo Scene thất bại, vui lòng kiểm tra console.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success ? '✨ Đã tái tạo Scene ${widget.batch.id} thành công!' : failMsg,
          ),
          backgroundColor: success ? AppColors.statusCompleted : AppColors.statusFailed,
          duration: Duration(seconds: success ? 3 : 5),
        ),
      );
    }
  }

  Future<void> _handleRefineHtml() async {
    final feedback = _feedbackController.text.trim();
    if (feedback.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vui lòng nhập yêu cầu tinh chỉnh (feedback) để AI chỉnh sửa mã HTML hiện tại.'),
          backgroundColor: AppColors.statusFailed,
        ),
      );
      return;
    }
    setState(() => _isGenerating = true);

    final success = await widget.controller.refineBatchHtmlWithAi(
      batchId: widget.batch.id,
      feedback: feedback,
    );

    if (mounted) {
      setState(() {
        _isGenerating = false;
        _playerRefreshKey++;
      });
      final err = widget.controller.currentState.lastError;
      final failMsg = err != null && err.isNotEmpty
          ? '❌ Tinh chỉnh HTML thất bại: $err'
          : '❌ Tinh chỉnh HTML thất bại, vui lòng kiểm tra console.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success ? '✨ Đã tinh chỉnh HTML Scene ${widget.batch.id} thành công!' : failMsg,
          ),
          backgroundColor: success ? AppColors.statusCompleted : AppColors.statusFailed,
          duration: Duration(seconds: success ? 3 : 5),
        ),
      );
    }
  }

  Future<void> _handleRestoreBackup() async {
    final bakPath = p.join(widget.workspacePath, 'scenes', '${widget.batch.id}.html.bak');
    final bakFile = File(bakPath);
    if (!bakFile.existsSync()) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.of(context).surface,
        title: const Row(
          children: [
            Icon(Icons.history_rounded, color: AppColors.primary, size: 20),
            SizedBox(width: 8),
            Text('Khôi phục bản sao lưu (.bak)?', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          'Hệ thống sẽ nạp lại mã HTML từ bản sao lưu trước lần tinh chỉnh gần nhất và render lại video.',
          style: TextStyle(fontSize: 12.5, color: AppColors.of(context).textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy'),
          ),
          AppButton.primary(
            label: 'Khôi phục ngay',
            icon: Icons.check_circle_outline_rounded,
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isGenerating = true);
    final success = await widget.controller.importBatchHtml(
      batchId: widget.batch.id,
      htmlFilePath: bakPath,
    );
    if (mounted) {
      setState(() {
        _isGenerating = false;
        _playerRefreshKey++;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success
                ? '↺ Đã khôi phục mã HTML từ bản sao lưu (.bak) thành công!'
                : '❌ Khôi phục bản sao thất bại.',
          ),
          backgroundColor: success ? AppColors.statusCompleted : AppColors.statusFailed,
        ),
      );
    }
  }

  Future<void> _handlePickAsset() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['png', 'jpg', 'jpeg', 'webp', 'mp4', 'mov', 'svg'],
    );
    if (res != null && res.files.single.path != null && mounted) {
      final pickedPath = res.files.single.path!;
      final isVideo = ['.mp4', '.mov', '.webm'].contains(p.extension(pickedPath).toLowerCase());
      widget.controller.assignAssetToBatch(
        widget.batch.id,
        filePath: pickedPath,
        type: isVideo ? 'video' : 'image',
      );
      setState(() => _playerRefreshKey++);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('📁 Đã gán tài sản ngoài: ${p.basename(pickedPath)}'),
          backgroundColor: AppColors.statusCompleted,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _handleClearAsset() {
    widget.controller.clearBatchAsset(widget.batch.id);
    setState(() => _playerRefreshKey++);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('↺ Đã khôi phục về Scene tự động.'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final b = _currentBatch;
    final previewVideo = _resolvePreviewVideo(b);
    final hasAsset = b.activeAsset != null && b.activeAsset!.filePath.isNotEmpty;
    final isCustomImage = hasAsset &&
        ['.png', '.jpg', '.jpeg', '.webp'].contains(p.extension(b.activeAsset!.filePath).toLowerCase()) &&
        File(b.activeAsset!.filePath).existsSync();
    final htmlPath = p.join(widget.workspacePath, 'scenes', '${b.id}.html');
    final bakPath = p.join(widget.workspacePath, 'scenes', '${b.id}.html.bak');
    final hasHtml = File(htmlPath).existsSync();
    final hasBak = File(bakPath).existsSync();

    return Dialog(
      backgroundColor: c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: c.border, width: 1),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 30),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960, maxHeight: 660),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── 1. HEADER DIALOG ──
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: c.surfaceDark,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                border: Border(bottom: BorderSide(color: c.border, width: 0.8)),
              ),
              child: Row(
                children: [
                  Icon(Icons.movie_creation_outlined, size: 18, color: c.primary),
                  const SizedBox(width: 8),
                  Text(
                    'Scene Studio — ${b.id}',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: c.surfaceLight,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: c.border.withOpacity(0.5)),
                    ),
                    child: Text(
                      '${_formatSec(b.startSec)} → ${_formatSec(b.endSec)} (${(b.endSec - b.startSec).toStringAsFixed(1)}s)',
                      style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: c.textSecondary),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 18),
                    tooltip: 'Đóng',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // ── 2. BODY 2 CỘT: PREVIEW TRÁI & CONTROLS PHẢI ──
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── CỘT TRÁI: PREVIEW KHUNG HÌNH (58%) ──
                  Expanded(
                    flex: 58,
                    child: Container(
                      color: Colors.black,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: isCustomImage
                                ? Center(
                                    child: Image.file(
                                      File(b.activeAsset!.filePath),
                                      fit: BoxFit.contain,
                                    ),
                                  )
                                : (previewVideo != null
                                    ? VideoPlayerWidget(
                                        key: ValueKey('$previewVideo-$_playerRefreshKey'),
                                        videoPath: previewVideo,
                                        autoPlay: true,
                                      )
                                    : Center(
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(Icons.video_library_outlined, size: 44, color: c.textMuted),
                                            const SizedBox(height: 10),
                                            Text(
                                              'Chưa có video clip xem trước',
                                              style: TextStyle(color: c.textSecondary, fontSize: 12),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              'Bấm nút "Gửi AI Thiết Kế Lại" bên phải để tạo clip độc lập',
                                              style: TextStyle(color: c.textMuted, fontSize: 10.5),
                                            ),
                                          ],
                                        ),
                                      )),
                          ),
                          // Dải thông tin kịch bản dưới chân video
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: c.surfaceDark,
                              border: Border(top: BorderSide(color: c.border, width: 0.8)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  b.transcriptOriginal,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 10.5, color: c.textMuted),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  b.transcriptTranslated.isNotEmpty ? b.transcriptTranslated : '--',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Colors.white),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // ── CỘT PHẢI: BẢNG TINH CHỈNH AI & NGUỒN TƯ LIỆU (42%) ──
                  Expanded(
                    flex: 42,
                    child: Container(
                      decoration: BoxDecoration(
                        color: c.surface,
                        border: Border(left: BorderSide(color: c.border, width: 0.8)),
                      ),
                      padding: const EdgeInsets.all(16),
                      child: ListView(
                        children: [
                          // ── THÔNG TIN CHẾ ĐỘ HIỆN TẠI ──
                          Row(
                            children: [
                              Icon(Icons.tune_rounded, size: 14, color: c.primary),
                              const SizedBox(width: 6),
                              Text('THIẾT LẬP CẢNH MINH HỌA', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: c.textSecondary)),
                              const Spacer(),
                              if (hasAsset)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(color: Colors.orange.withOpacity(0.15), borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.orange.withOpacity(0.5))),
                                  child: const Text('Asset Thủ Công', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Colors.orange)),
                                )
                              else if (b.scene['mode'] == 'authored')
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(color: const Color(0xFF10B981).withOpacity(0.15), borderRadius: BorderRadius.circular(4), border: Border.all(color: const Color(0xFF10B981).withOpacity(0.5))),
                                  child: const Text('AI-Authored', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Color(0xFF10B981))),
                                )
                              else
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(color: c.surfaceLight, borderRadius: BorderRadius.circular(4), border: Border.all(color: c.border)),
                                  child: Text('AI Native SVG (${b.scene['template'] ?? 'authored'})', style: TextStyle(fontSize: 9.5, color: c.textSecondary)),
                                ),
                            ],
                          ),
                          const SizedBox(height: 14),

                          // ── CÔNG CỤ NHANH: SAO CHÉP MASTER PROMPT BATCH ──
                          Row(
                            children: [
                              Expanded(
                                child: AppButton(
                                  label: 'Sao Chép Master Prompt (${b.id})',
                                  icon: Icons.content_copy_rounded,
                                  variant: AppButtonVariant.secondary,
                                  onPressed: _handleCopyPrompt,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Sao chép prompt đầy đủ kèm danh sách câu thoại và mốc thời gian để dán vào ChatGPT / Gemini.',
                            style: TextStyle(fontSize: 10, color: c.textMuted, height: 1.2),
                          ),
                          const SizedBox(height: 16),

                          // ── KHỐI 1: YÊU CẦU AI VẼ LẠI HTML ──
                          Text(
                            'Yêu cầu AI Tinh chỉnh / Sinh lại HTML:',
                            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: c.textPrimary),
                          ),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _feedbackController,
                            maxLines: 4,
                            style: const TextStyle(fontSize: 12),
                            decoration: InputDecoration(
                              hintText: 'Ví dụ: Thiết kế dạng sơ đồ luồng 3 nhánh, tinh giản chữ ngắn gọn 2-3 từ, dùng màu nhấn đỏ gạch...',
                              hintStyle: TextStyle(fontSize: 11, color: c.textMuted),
                              filled: true,
                              fillColor: c.surfaceDark,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: c.border)),
                              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: c.border.withOpacity(0.6))),
                              contentPadding: const EdgeInsets.all(10),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: AppButton.primary(
                                  label: _isGenerating ? 'AI đang thiết kế...' : 'Sinh Lại Mới (HTML)',
                                  icon: Icons.auto_awesome,
                                  onPressed: _isGenerating ? null : _handleReauthor,
                                ),
                              ),
                              if (hasHtml) ...[
                                const SizedBox(width: 8),
                                Expanded(
                                  child: AppButton(
                                    label: _isGenerating ? 'AI đang tinh chỉnh...' : 'AI Tinh Chỉnh HTML',
                                    icon: Icons.edit_note_rounded,
                                    variant: AppButtonVariant.secondary,
                                    onPressed: _isGenerating ? null : _handleRefineHtml,
                                  ),
                                ),
                              ],
                            ],
                          ),
                          if (hasBak) ...[
                            const SizedBox(height: 8),
                            AppButton(
                              label: 'Khôi phục bản sao trước tinh chỉnh (.bak)',
                              icon: Icons.history_rounded,
                              variant: AppButtonVariant.ghost,
                              onPressed: _isGenerating ? null : _handleRestoreBackup,
                            ),
                          ],
                          const SizedBox(height: 16),
                          Text(
                            'Mã HTML sinh ra tự chứa 100% thuần native SVG vẽ tay, khớp khung thời gian và bảo vệ vùng phụ đề đáy.',
                            style: TextStyle(fontSize: 10, color: c.textMuted, height: 1.3),
                          ),

                          const Divider(height: 32, color: AppColors.border),

                          // ── KHỐI 2: IMPORT HTML HOẶC TƯ LIỆU NGOÀI (THỦ CÔNG) ──
                          Text(
                            'Import Tài Sản Ngoài (HTML / Media):',
                            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: c.textPrimary),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Dán code HTML hoặc import file sinh từ ChatGPT/Claude/Gemini, hoặc gán ảnh/video minh họa có sẵn.',
                            style: TextStyle(fontSize: 10.5, color: c.textMuted),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              AppButton(
                                label: _isGenerating ? 'Đang xử lý...' : 'Dán Code HTML',
                                icon: Icons.integration_instructions_outlined,
                                variant: AppButtonVariant.primary,
                                onPressed: _isGenerating ? null : _handlePasteHtmlCode,
                              ),
                              AppButton(
                                label: 'Chọn File HTML (.html)',
                                icon: Icons.file_open_outlined,
                                variant: AppButtonVariant.secondary,
                                onPressed: _isGenerating ? null : _handlePickHtml,
                              ),
                              AppButton(
                                label: 'Import Media',
                                icon: Icons.file_upload_outlined,
                                variant: AppButtonVariant.secondary,
                                onPressed: _isGenerating ? null : _handlePickAsset,
                              ),
                              if (hasAsset || b.scene['mode'] == 'authored')
                                AppButton(
                                  label: 'Khôi Phục Mặc Định',
                                  icon: Icons.undo_rounded,
                                  variant: AppButtonVariant.ghost,
                                  onPressed: _isGenerating ? null : _handleClearAsset,
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
