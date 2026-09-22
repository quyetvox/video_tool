import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import '../../../../core/app_colors.dart';
import '../../../../core/python_bridge.dart';
import '../../../../models/video_file.dart';
import '../../../../utils/time_format_utils.dart';
import '../controllers/vlog_story_controller.dart';
import '../models/vlog_segment_model.dart';
import 'vlog_step_progress_widget.dart';

class VlogPropertiesInspector extends StatefulWidget {
  final VlogStoryState state;
  final VlogStoryController controller;
  final VideoFile? videoFile;
  final VoidCallback? onGenerateScript;
  final VoidCallback? onResumeRender;

  const VlogPropertiesInspector({
    super.key,
    required this.state,
    required this.controller,
    this.videoFile,
    this.onGenerateScript,
    this.onResumeRender,
  });

  @override
  State<VlogPropertiesInspector> createState() => _VlogPropertiesInspectorState();
}

class _VlogPropertiesInspectorState extends State<VlogPropertiesInspector> {
  int _activeTab = 0; // 0: Properties, 1: Tiến Trình & Resume, 2: AI Metadata

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);

    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(left: BorderSide(color: c.border)),
      ),
      child: Column(
        children: [
          // Header Subtabs
          Container(
            height: 38,
            decoration: BoxDecoration(
              color: c.surfaceDark,
              border: Border(bottom: BorderSide(color: c.border)),
            ),
            child: Row(
              children: [
                _buildTabBtn(title: 'Properties', index: 0, c: c),
                _buildTabBtn(title: 'Resume & Run', index: 1, c: c),
                _buildTabBtn(title: 'Metadata', index: 2, c: c),
              ],
            ),
          ),

          // Content
          Expanded(
            child: _activeTab == 0
                ? _buildPropertiesTab(c)
                : _activeTab == 1
                    ? _buildRunTab(c)
                    : _buildMetadataTab(c),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBtn({required String title, required int index, required AppFallbackPalette c}) {
    final isActive = _activeTab == index;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _activeTab = index),
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

  // ── SUBTAB 0: PROPERTIES ──
  Widget _buildPropertiesTab(AppFallbackPalette c) {
    final state = widget.state;
    final file = widget.videoFile;

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Text(
          'THÔNG TIN VIDEO GỐC',
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: c.textMuted, letterSpacing: 0.5),
        ),
        const SizedBox(height: 8),

        _buildPropertyItem('Tên File', state.videoName.isNotEmpty ? state.videoName : '--', c, copyable: true),
        const SizedBox(height: 8),
        _buildPropertyItem(
          'Thời Lượng',
          state.duration > 0 ? TimeFormatUtils.formatDuration(state.duration) : '--:--',
          c,
        ),
        const SizedBox(height: 8),
        _buildPropertyItem(
          'Kích Thước',
          file != null ? TimeFormatUtils.formatFileSize(file.sizeBytes) : '--',
          c,
        ),
        const SizedBox(height: 8),
        _buildPropertyItem(
          'Đường Dẫn',
          state.videoPath.isNotEmpty ? state.videoPath : '--',
          c,
          copyable: true,
          maxLines: 2,
        ),

        const Divider(height: 24),

        Text(
          'TRẠNG THÁI KỊCH BẢN VLOG',
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: c.textMuted, letterSpacing: 0.5),
        ),
        const SizedBox(height: 8),
        _buildPropertyItem(
          'Số Phân Cảnh',
          '${state.segments.length} câu thoại',
          c,
          highlight: state.segments.isNotEmpty,
        ),
        const SizedBox(height: 8),
        _buildPropertyItem(
          'Phong Cách',
          state.style.label.split(' / ').first,
          c,
        ),
        const SizedBox(height: 8),
        _buildPropertyItem(
          'Giọng Đọc TTS',
          state.voice.toUpperCase(),
          c,
        ),

        if (state.outputVideoPath != null) ...[
          const Divider(height: 24),
          const Text(
            'VIDEO THÀNH PHẨM',
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.statusCompleted, letterSpacing: 0.5),
          ),
          const SizedBox(height: 6),
          _buildPropertyItem('File Output', p.basename(state.outputVideoPath!), c, highlight: true, copyable: true),
        ],
      ],
    );
  }

  // ── SUBTAB 1: TIẾN TRÌNH & RESUME ──
  Widget _buildRunTab(AppFallbackPalette c) {
    final state = widget.state;
    final isProcessing = state.isProcessing;

    final root = PythonBridge.resolveRootDir();
    final pName = state.projectName.isNotEmpty ? state.projectName : 'default';
    final vName = state.videoName.isNotEmpty ? state.videoName : p.basename(state.videoPath);
    final safeName = p.withoutExtension(vName).replaceAll(RegExp(r'[^\w\-]+'), '_');
    final wsPath = p.join(root, 'resources', pName, 'workspace', 'vlog_story', safeName);

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // ── 1. Visual 6-Step Progress Indicator ──
        VlogStepProgressWidget(
          state: state,
          workspacePath: wsPath,
          outputVideoPath: state.outputVideoPath,
        ),
        const SizedBox(height: 12),

        Text(
          'TRẠNG THÁI TIẾN TRÌNH',
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
                        : (state.segments.isNotEmpty ? Icons.check_circle_outline_rounded : Icons.info_outline_rounded),
                    size: 16,
                    color: isProcessing ? c.primary : (state.segments.isNotEmpty ? AppColors.statusCompleted : c.textMuted),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      state.statusMessage.isNotEmpty ? state.statusMessage : 'Sẵn sàng xử lý',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: c.textPrimary),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              if (isProcessing) ...[
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: state.progress > 0 ? state.progress : null,
                  backgroundColor: c.border,
                  color: c.primary,
                  minHeight: 4,
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

        const SizedBox(height: 16),

        // Nút hành động 1: Tạo Kịch Bản AI
        SizedBox(
          height: 36,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.auto_awesome_rounded, size: 15),
            label: Text(
              state.isGeneratingScript
                  ? 'Đang Phân Tích (${(state.progress * 100).toInt()}%)...'
                  : (state.segments.isEmpty ? 'Tạo Kịch Bản AI' : 'Tạo Lại Kịch Bản AI'),
              style: const TextStyle(fontSize: 12),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: c.primary,
              side: BorderSide(color: c.primary),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            ),
            onPressed: isProcessing
                ? null
                : (widget.onGenerateScript ?? () => widget.controller.generateScript()),
          ),
        ),

        const SizedBox(height: 10),

        // Nút hành động 2: Tiếp Tục Render / Resume
        SizedBox(
          height: 40,
          child: FilledButton.icon(
            icon: const Icon(Icons.movie_creation_rounded, size: 16),
            label: Text(
              state.isRenderingVideo
                  ? 'Đang Render (${(state.progress * 100).toInt()}%)...'
                  : 'Tiếp Tục Render (Resume)',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: c.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
              elevation: 2,
            ),
            onPressed: (isProcessing || state.segments.isEmpty)
                ? null
                : (widget.onResumeRender ?? () => widget.controller.renderFinalVideo()),
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

        const SizedBox(height: 16),
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
                  'Cơ chế Resume: Bạn có thể sửa câu từ ở tab "Subtitles", sau đó bấm Resume để render mà không tốn thêm token AI.',
                  style: TextStyle(fontSize: 10, color: c.textMuted, height: 1.3),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── SUBTAB 2: AI METADATA ──
  Widget _buildMetadataTab(AppFallbackPalette c) {
    final state = widget.state;

    final hookTitle = state.metaTitle.isNotEmpty
        ? state.metaTitle
        : (state.videoName.isNotEmpty
            ? 'Vlog: ${p.withoutExtension(state.videoName)} | Câu Chuyện Thường Nhật'
            : 'Vlog Kể Chuyện Thường Nhật');

    final metaDesc = state.metaDesc.isNotEmpty
        ? state.metaDesc
        : (state.segments.isNotEmpty
            ? state.segments.map((s) => s.text).take(3).join(' ')
            : 'Video Vlog kể chuyện cảm xúc, ghi lại những khoảnh khắc đời thường ý nghĩa.');

    final hashtags = state.metaHashtags.isNotEmpty
        ? state.metaHashtags.join(' ')
        : '#vlog #storytelling #${state.style.id} #dailyvlog #subvideo';

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _buildMetaCard(
          c,
          title: 'Tiêu Đề Vlog (Title)',
          content: hookTitle,
          tooltip: 'Sao chép tiêu đề',
        ),
        const SizedBox(height: 12),
        _buildMetaCard(
          c,
          title: 'Mô Tả Video Kể Chuyện',
          content: metaDesc,
          tooltip: 'Sao chép mô tả',
        ),
        const SizedBox(height: 12),
        _buildMetaCard(
          c,
          title: 'Hashtags Xu Hướng',
          content: hashtags,
          tooltip: 'Sao chép hashtags',
        ),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: c.primary,
            foregroundColor: c.primaryText,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          ),
          icon: const Icon(Icons.copy_rounded, size: 14),
          label: const Text('📋 Sao Chép Toàn Bộ Metadata', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
          onPressed: () {
            final all = '$hookTitle\n\n$metaDesc\n\n$hashtags';
            Clipboard.setData(ClipboardData(text: all));
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã sao chép toàn bộ metadata vào clipboard!')));
          },
        ),
      ],
    );
  }

  Widget _buildMetaCard(AppFallbackPalette c, {required String title, required String content, required String tooltip}) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: c.surfaceLight.withOpacity(0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: c.textSecondary)),
              IconButton(
                icon: Icon(Icons.copy_rounded, size: 14, color: c.primary),
                tooltip: tooltip,
                constraints: const BoxConstraints(),
                padding: EdgeInsets.zero,
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: content));
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Đã sao chép: $title')));
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

  Widget _buildPropertyItem(String label, String value, AppFallbackPalette c, {bool highlight = false, bool copyable = false, int maxLines = 1}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: c.textMuted, fontSize: 10)),
        const SizedBox(height: 2),
        Row(
          children: [
            Expanded(
              child: Text(
                value,
                maxLines: maxLines,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: highlight ? c.primary : c.textPrimary,
                  fontSize: 11.5,
                  fontWeight: highlight ? FontWeight.w600 : FontWeight.normal,
                ),
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
                child: Icon(Icons.copy, size: 12, color: c.textMuted),
              ),
            ],
          ],
        ),
      ],
    );
  }
}
