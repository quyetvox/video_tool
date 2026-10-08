import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../../core/app_colors.dart';
import '../../../../core/python_bridge.dart';
import '../../../../models/video_file.dart';
import '../../../../utils/time_format_utils.dart';
import '../../../../widgets/app_kit.dart';
import '../controllers/lecture_illustrator_controller.dart';
import '../models/lecture_illustrator_model.dart';
import 'lecture_step_progress_widget.dart';

class LecturePropertiesInspector extends ConsumerStatefulWidget {
  final LectureIllustratorState state;
  final LectureIllustratorController controller;
  final VideoFile? videoFile;

  const LecturePropertiesInspector({
    super.key,
    required this.state,
    required this.controller,
    this.videoFile,
  });

  @override
  ConsumerState<LecturePropertiesInspector> createState() =>
      _LecturePropertiesInspectorState();
}

class _LecturePropertiesInspectorState
    extends ConsumerState<LecturePropertiesInspector> {
  int _activeTopTab = 0; // 0: Properties, 1: Steps, 2: AI Metadata

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final hasVideo = widget.state.videoPath != null &&
        widget.state.videoPath!.isNotEmpty &&
        (widget.videoFile != null || File(widget.state.videoPath!).existsSync());

    return Container(
      color: c.surface,
      child: Column(
        children: [
          // ── HEADER 3 TOP TABS ĐỒNG BỘ 1:1 SUB-VIDEO ──
          Container(
            height: 38,
            decoration: BoxDecoration(
              color: c.surfaceDark,
              border: Border(bottom: BorderSide(color: c.border, width: 0.8)),
            ),
            child: Row(
              children: [
                _buildTopTabBtn(title: 'Properties', index: 0, c: c),
                _buildTopTabBtn(title: 'Tiến Trình (Steps)', index: 1, c: c),
                _buildTopTabBtn(title: 'AI Metadata', index: 2, c: c),
              ],
            ),
          ),

          // ── NỘI DUNG THEO TAB CHÍNH ──
          Expanded(
            child: !hasVideo
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.video_collection_outlined, size: 36, color: c.textMuted),
                        const SizedBox(height: 8),
                        Text(
                          'Chưa chọn video nào',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: c.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  )
                : (_activeTopTab == 0
                    ? _buildPropertiesMainTab(c)
                    : _activeTopTab == 1
                        ? _buildStepsTab(c)
                        : _buildMetadataTab(c)),
          ),
        ],
      ),
    );
  }

  Widget _buildTopTabBtn({
    required String title,
    required int index,
    required AppFallbackPalette c,
  }) {
    final isActive = _activeTopTab == index;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _activeTopTab = index),
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: isActive ? c.primary : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Center(
            child: Text(
              title,
              style: TextStyle(
                color: isActive ? c.primary : c.textSecondary,
                fontSize: 11,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ── TAB 0: PROPERTIES (BASIC INFO + TÓM TẮT BÀI GIẢNG + ACTIONS) ───────────
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildPropertiesMainTab(AppFallbackPalette c) {
    final state = widget.state;
    final file = widget.videoFile;
    final isProcessing = state.isAnalyzing || state.isRendering;

    final fileName = state.videoName ?? (file != null ? file.name : '--');
    final durationStr = state.videoDuration > 0
        ? TimeFormatUtils.formatDuration(state.videoDuration)
        : '--:--';
    final sizeStr = file != null
        ? TimeFormatUtils.formatFileSize(file.sizeBytes)
        : (state.videoPath != null && File(state.videoPath!).existsSync()
            ? TimeFormatUtils.formatFileSize(File(state.videoPath!).lengthSync())
            : '--');
    final resStr = '${state.videoWidth} x ${state.videoHeight}';
    const fpsStr = '30 fps';

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // ── 1. THÔNG TIN VIDEO GỐC ──
        const AppSectionHeader(title: 'THÔNG TIN VIDEO (BASIC INFO)'),
        const SizedBox(height: 8),

        _buildPropertyItem('Tên File', fileName, c, copyable: true),
        const SizedBox(height: 6),
        _buildPropertyItem('Thời Lượng', durationStr, c),
        const SizedBox(height: 6),
        _buildPropertyItem('Độ Phân Giải', resStr, c),
        const SizedBox(height: 6),
        _buildPropertyItem('Tốc Độ', fpsStr, c),
        const SizedBox(height: 6),
        _buildPropertyItem('Dung Lượng', sizeStr, c),
        if (state.videoPath != null && state.videoPath!.isNotEmpty) ...[
          const SizedBox(height: 6),
          _buildPropertyItem('Đường Dẫn', state.videoPath!, c, copyable: true, maxLines: 2),
        ],

        const Divider(height: 24, color: AppColors.border),

        // ── 2. TÓM TẮT BÀI GIẢNG & BỐ CỤC ──
        const AppSectionHeader(title: 'TÓM TẮT BÀI GIẢNG & BỐ CỤC'),
        const SizedBox(height: 8),

        _buildPropertyItem(
          'Số Phân Cảnh (Batches)',
          '${state.batches.length} phân đoạn kiến thức',
          c,
        ),
        const SizedBox(height: 6),
        _buildPropertyItem(
          'Bố Cục Minh Họa',
          _getLayoutName(state.config.visualLayoutPreset),
          c,
        ),
        const SizedBox(height: 6),
        _buildPropertyItem(
          'Ngôn Ngữ',
          '${state.config.sourceLang.toUpperCase()} ➔ ${state.config.targetLang.toUpperCase()} (${state.config.secondaryLang.toUpperCase()})',
          c,
        ),
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 100,
              child: Text(
                'Chế Độ Giọng Đọc',
                style: TextStyle(fontSize: 11, color: c.textMuted),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: PopupMenuButton<String>(
                enabled: !isProcessing,
                tooltip: 'Chọn chế độ giọng đọc',
                onSelected: (val) {
                  if (val == 'original') {
                    widget.controller.setVoiceMode('original');
                  } else {
                    widget.controller.setVoiceMode('tts_dub');
                    widget.controller.setTtsVoice(val);
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'ban_mai',
                    child: Text('🎙️ Dịch TTS: Ban Mai (Nữ Bắc)', style: TextStyle(fontSize: 12)),
                  ),
                  const PopupMenuItem(
                    value: 'hoai_my',
                    child: Text('🎙️ Dịch TTS: Hoài My (Nữ Nam)', style: TextStyle(fontSize: 12)),
                  ),
                  const PopupMenuItem(
                    value: 'nam_minh',
                    child: Text('🎙️ Dịch TTS: Nam Minh (Nam)', style: TextStyle(fontSize: 12)),
                  ),
                  const PopupMenuDivider(),
                  const PopupMenuItem(
                    value: 'original',
                    child: Text('🎵 Giữ giọng gốc (Không dịch TTS)', style: TextStyle(fontSize: 12)),
                  ),
                ],
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: c.surfaceLight.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: c.border.withOpacity(0.5), width: 0.8),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          state.config.voiceMode == 'tts_dub'
                              ? '🎙️ Dịch TTS (${state.config.ttsVoice})'
                              : '🎵 Giọng Gốc',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: c.primary),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Icon(Icons.arrow_drop_down, size: 14, color: c.textMuted),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),

        const Divider(height: 24, color: AppColors.border),

        // ── 3. THAO TÁC HÀNH ĐỘNG CHÍNH ──
        const AppSectionHeader(title: 'THAO TÁC XỬ LÝ (ACTIONS)'),
        const SizedBox(height: 10),

        // Nút 1: Phân Tích Bài Giảng AI
        SizedBox(
          height: 36,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.auto_awesome_rounded, size: 15),
            label: Text(
              state.isAnalyzing
                  ? 'Đang Phân Tích (${(state.progress * 100).toInt()}%)...'
                  : (state.batches.isEmpty ? 'Phân Tích Bài Giảng AI' : 'Phân Tích Lại'),
              style: const TextStyle(fontSize: 12),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: c.primary,
              side: BorderSide(color: c.primary),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            ),
            onPressed: isProcessing ? null : () => widget.controller.startAnalysis(),
          ),
        ),

        const SizedBox(height: 10),

        // Nút 2: Xuất Video Hoàn Chỉnh
        SizedBox(
          height: 38,
          child: FilledButton.icon(
            icon: const Icon(Icons.movie_creation_rounded, size: 16),
            label: Text(
              state.isRendering
                  ? 'Đang Xuất Video (${(state.progress * 100).toInt()}%)...'
                  : 'Xuất Video Hoàn Chỉnh',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: c.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            ),
            onPressed: (isProcessing || state.batches.isEmpty)
                ? null
                : () => widget.controller.startRender(),
          ),
        ),

        if (isProcessing) ...[
          const SizedBox(height: 10),
          SizedBox(
            height: 32,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.cancel_outlined, size: 14, color: AppColors.statusFailed),
              label: const Text('Hủy Tác Vụ', style: TextStyle(fontSize: 11, color: AppColors.statusFailed)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.statusFailed),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
              ),
              onPressed: () => widget.controller.cancelActiveTask(),
            ),
          ),
        ],

        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: c.surfaceLight.withOpacity(0.15),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.tips_and_updates_outlined, size: 14, color: c.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Cấu hình Subtitle Style, Inpaint, Voice và Engine đã được chuyển sang bảng bên cạnh để đồng bộ hoàn toàn với Video Editor.',
                  style: TextStyle(fontSize: 10, color: c.textMuted, height: 1.3),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _getLayoutName(String preset) {
    switch (preset) {
      case 'pip':
        return '🖼️ Picture-in-Picture (38%)';
      case 'full':
        return '📺 Toàn Màn Hình';
      case 'split':
        return '⚖️ Chia Đôi 50/50';
      default:
        return preset.toUpperCase();
    }
  }

  Widget _buildPropertyItem(
    String label,
    String value,
    AppFallbackPalette c, {
    bool copyable = false,
    int maxLines = 1,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 100,
          child: Text(
            label,
            style: TextStyle(fontSize: 11, color: c.textMuted),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: c.textPrimary,
            ),
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (copyable && value != '--') ...[
          const SizedBox(width: 4),
          InkWell(
            onTap: () {
              Clipboard.setData(ClipboardData(text: value));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Đã sao chép: $value'), duration: const Duration(seconds: 1)),
              );
            },
            child: Icon(Icons.copy_rounded, size: 12, color: c.textMuted),
          ),
        ],
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ── TAB 1: 📊 TIẾN TRÌNH & RUN WORKFLOW (STEPS TAB) ───────────────────────
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildStepsTab(AppFallbackPalette c) {
    final state = widget.state;
    final isProcessing = state.isAnalyzing || state.isRendering;

    final root = PythonBridge.resolveRootDir();
    final pName = state.projectName?.isNotEmpty == true ? state.projectName! : 'default';
    final vName = state.videoName?.isNotEmpty == true
        ? state.videoName!
        : (state.videoPath != null ? p.basename(state.videoPath!) : 'default_video');
    final safeName = p.withoutExtension(vName).replaceAll(RegExp(r'[^\w\-]+'), '_');
    final wsPath = p.join(root, 'resources', pName, 'workspace', 'lecture_illustrator', safeName);
    final outVideoPath = p.join(root, 'resources', pName, 'output', '${safeName}_illustrated.mp4');

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // ── 1. Visual 6-Step Progress Indicator ──
        LectureStepProgressWidget(
          state: state,
          workspacePath: wsPath,
          outputVideoPath: outVideoPath,
          controller: widget.controller,
        ),
        const SizedBox(height: 12),

        Text(
          'TRẠNG THÁI TIẾN TRÌNH HIỆN TẠI',
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: c.textMuted, letterSpacing: 0.5),
        ),
        const SizedBox(height: 8),

        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: c.surfaceLight.withOpacity(0.3),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: c.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    isProcessing
                        ? Icons.sync_rounded
                        : (state.batches.isNotEmpty ? Icons.check_circle_outline_rounded : Icons.info_outline_rounded),
                    size: 16,
                    color: isProcessing
                        ? c.primary
                        : (state.batches.isNotEmpty ? AppColors.statusCompleted : c.textMuted),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      state.statusMessage?.isNotEmpty == true
                          ? state.statusMessage!
                          : 'Sẵn sàng xử lý bài giảng',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: c.textPrimary),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              if (isProcessing) ...[
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: state.progress > 0 ? state.progress : null,
                    minHeight: 4,
                    backgroundColor: c.border,
                    valueColor: AlwaysStoppedAnimation<Color>(c.primary),
                  ),
                ),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    '${(state.progress * 100).toInt()}%',
                    style: TextStyle(fontSize: 10, color: c.primary, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ── TAB 2: 🏷️ AI METADATA (TIÊU ĐỀ, MÔ TẢ & HASHTAGS) ─────────────────────
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildMetadataTab(AppFallbackPalette c) {
    final state = widget.state;

    final hookTitle = state.metaTitle.isNotEmpty
        ? state.metaTitle
        : (state.videoName?.isNotEmpty == true
            ? 'Bài Giảng: ${p.withoutExtension(state.videoName!).replaceAll('_', ' ').title()}'
            : 'Video Bài Giảng Giáo Dục');

    final metaDesc = state.metaDesc.isNotEmpty
        ? state.metaDesc
        : (state.batches.isNotEmpty
            ? state.batches.map((b) => b.transcriptTranslated).take(3).join(' ')
            : 'Video bài giảng trực quan minh họa sơ đồ, khái niệm và hoạt cảnh dễ hiểu.');

    final hashtags = state.metaHashtags.isNotEmpty
        ? state.metaHashtags.join(' ')
        : '#baigiang #kienthuc #hoctap #congnghe #giaoduc #subvideo';

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _buildMetadataSection(
          title: '📌 Tiêu Đề Bài Giảng (Title / Hook)',
          content: hookTitle,
          tooltip: 'Sao chép tiêu đề',
          c: c,
        ),
        const SizedBox(height: 12),
        _buildMetadataSection(
          title: '📝 Mô Tả Bài Giảng (Description)',
          content: metaDesc,
          tooltip: 'Sao chép mô tả',
          c: c,
        ),
        const SizedBox(height: 12),
        _buildMetadataSection(
          title: '🏷️ Hashtags Xu Hướng (AI Generated)',
          content: hashtags,
          tooltip: 'Sao chép hashtags',
          c: c,
        ),
      ],
    );
  }

  Widget _buildMetadataSection({
    required String title,
    required String content,
    required String tooltip,
    required AppFallbackPalette c,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: c.surfaceDark.withOpacity(0.6),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: c.border, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.bold,
                  color: c.primary,
                ),
              ),
              IconButton(
                icon: Icon(Icons.copy_rounded, size: 14, color: c.primary),
                tooltip: tooltip,
                constraints: const BoxConstraints(),
                padding: EdgeInsets.zero,
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: content));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Đã sao chép: $title'), duration: const Duration(seconds: 1)),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 6),
          SelectableText(
            content,
            style: TextStyle(fontSize: 11, color: c.textPrimary, height: 1.3),
          ),
        ],
      ),
    );
  }
}

extension StringTitleCase on String {
  String title() {
    return split(' ')
        .map((str) => str.isNotEmpty
            ? '${str[0].toUpperCase()}${str.substring(1).toLowerCase()}'
            : '')
        .join(' ');
  }
}
