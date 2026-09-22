import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import '../../../../core/app_colors.dart';
import '../../../../models/video_file.dart';
import '../../../../utils/time_format_utils.dart';
import '../../../../widgets/app_kit.dart';
import '../controllers/movie_review_controller.dart';
import '../models/movie_review_model.dart';
import 'review_step_progress_widget.dart';

/// Bảng Inspector 2 Tab Hiện Đại Dành Cho Movie Review (Tương tự Vlog Story)
class ReviewPropertiesInspector extends StatefulWidget {
  final MovieReviewState state;
  final MovieReviewController controller;
  final VideoFile? videoFile;
  final VoidCallback? onGenerateScript;
  final VoidCallback? onStartRender;

  const ReviewPropertiesInspector({
    super.key,
    required this.state,
    required this.controller,
    this.videoFile,
    this.onGenerateScript,
    this.onStartRender,
  });

  @override
  State<ReviewPropertiesInspector> createState() => _ReviewPropertiesInspectorState();
}

class _ReviewPropertiesInspectorState extends State<ReviewPropertiesInspector> {
  int _activeTab = 1; // Mặc định mở tab Tiến Trình & Run để người dùng dễ thao tác workflow

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
                _buildTabBtn(title: 'Tiến Trình & Run', index: 1, c: c),
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
                fontSize: 10.5,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ── SUBTAB 0: PROPERTIES TAB ───────────────────────────────────────────────
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildPropertiesTab(AppFallbackPalette c) {
    final file = widget.videoFile;
    final state = widget.state;

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _buildInfoGroup(c, 'Thông Tin Phim', [
          _buildInfoRow(c, 'Tên file', state.videoName ?? (file != null ? file.name : 'Chưa nạp')),
          _buildInfoRow(c, 'Dung lượng', file != null ? '${(file.sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB' : '--'),
          _buildInfoRow(c, 'Thời lượng gốc', TimeFormatUtils.formatDuration(state.videoDuration)),
          _buildInfoRow(c, 'Thể loại phim', state.genre.label),
          _buildInfoRow(c, 'Phong cách', state.reviewStyle.label.split(' / ').first),
          _buildInfoRow(c, 'Thời lượng review', '~${(state.targetDurationSec / 60).toStringAsFixed(1)} phút'),
        ]),
        const SizedBox(height: 12),
        _buildInfoGroup(c, 'Thống Kê Kịch Bản', [
          _buildInfoRow(c, 'Số câu thoại', '${state.segments.length} phân đoạn'),
          _buildInfoRow(c, 'Kho cảnh phim', '${state.availableScenes.length} scenes'),
          _buildInfoRow(c, 'Tổng số từ', '${state.segments.fold<int>(0, (sum, s) => sum + s.voiceoverText.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length)} từ'),
          _buildInfoRow(c, 'Tỷ lệ khung hình', state.aspectRatio == '9:16' ? '9:16 Dọc' : '16:9 Ngang'),
          _buildInfoRow(c, 'Giọng đọc', state.ttsVoice == 'hoai_my' ? 'Hoài My' : (state.ttsVoice == 'ban_mai' ? 'Ban Mai' : 'Nam Minh')),
        ]),
        const SizedBox(height: 12),
        if (state.videoPath != null)
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: c.surfaceLight.withOpacity(0.3),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: c.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Đường dẫn file gốc:', style: TextStyle(fontSize: 10, color: c.textMuted)),
                const SizedBox(height: 3),
                SelectableText(
                  state.videoPath!,
                  style: TextStyle(fontSize: 9.5, color: c.textSecondary, fontFamily: 'monospace'),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ── SUBTAB 1: TIẾN TRÌNH & RUN WORKFLOW ────────────────────────────────────
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildRunTab(AppFallbackPalette c) {
    final state = widget.state;
    final controller = widget.controller;
    final hasOutput = state.outputVideoPath != null && File(state.outputVideoPath!).existsSync();

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // 1. KẾT QUẢ VIDEO NẾU ĐÃ CÓ OUTPUT
        if (hasOutput) ...[
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.statusCompleted.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.statusCompleted.withOpacity(0.4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.check_circle_rounded, color: AppColors.statusCompleted, size: 16),
                    const SizedBox(width: 6),
                    const Expanded(
                      child: Text(
                        'Video Review Đã Hoàn Tất!',
                        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: AppColors.statusCompleted),
                      ),
                    ),
                    InkWell(
                      onTap: () {
                        final dir = File(state.outputVideoPath!).parent.path;
                        if (Platform.isMacOS) {
                          Process.run('open', [dir]);
                        } else if (Platform.isWindows) {
                          Process.run('explorer.exe', [dir]);
                        }
                      },
                      child: Tooltip(
                        message: 'Mở thư mục chứa video',
                        child: Icon(Icons.folder_open_rounded, size: 16, color: c.primary),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                SelectableText(
                  p.basename(state.outputVideoPath!),
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.white),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        // 2. WIDGET TIẾN TRÌNH 6-7 BƯỚC VỚI SELECTIVE RERUN
        ReviewStepProgressWidget(
          state: state,
          workspacePath: controller.workspacePath,
          outputVideoPath: state.outputVideoPath,
          onRerunStep: (stepId) => controller.rerunFromStep(stepId),
          onDeleteStepCache: (stepId) => controller.deleteStepCache(stepId),
        ),
        const SizedBox(height: 12),

        // 3. THẺ TRẠNG THÁI RENDERING NẾU ĐANG CHẠY
        if (state.isRendering || state.isAnalyzing) ...[
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: c.surfaceLight.withOpacity(0.4),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.primary.withOpacity(0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        state.isAnalyzing ? 'Đang phân tích phim & tạo kịch bản...' : 'Đang dựng video review...',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.primary),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                LinearProgressIndicator(
                  value: state.progress > 0 ? state.progress : null,
                  backgroundColor: c.border,
                  valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
                  minHeight: 4,
                ),
                const SizedBox(height: 6),
                Text(
                  state.statusMessage,
                  style: TextStyle(fontSize: 10, color: c.textMuted),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        // 4. CÁC NÚT THỰC THI CHỦ LỰC
        // Nút Chặng 1: Phân tích & Tạo kịch bản
        SizedBox(
          height: 38,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: c.surfaceLight,
              foregroundColor: c.textPrimary,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
                side: BorderSide(color: c.border),
              ),
            ),
            icon: state.isAnalyzing
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 1.8, color: AppColors.primary))
                : const Icon(Icons.auto_awesome_rounded, size: 16, color: AppColors.primary),
            label: Text(
              state.isAnalyzing
                  ? 'Đang phân tích (${(state.progress * 100).toInt()}%)...'
                  : '✨ Tạo Kịch Bản Review',
              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
            ),
            onPressed: (state.isAnalyzing || state.isRendering || state.videoPath == null)
                ? null
                : () => widget.onGenerateScript?.call(),
          ),
        ),
        const SizedBox(height: 8),

        // Nút Chặng 2: Dựng & Xuất Video Review
        SizedBox(
          height: 42,
          child: AppButton.success(
            icon: Icons.movie_creation_outlined,
            label: state.isRendering
                ? '🎬 ĐANG XUẤT (${(state.progress * 100).toInt()}%)'
                : '🎬 DỰNG & XUẤT VIDEO',
            isLoading: state.isRendering,
            progress: state.isRendering ? state.progress : null,
            onPressed: (state.isAnalyzing || state.isRendering || state.segments.isEmpty)
                ? null
                : () => widget.onStartRender?.call(),
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ── SUBTAB 2: AI METADATA TAB ──────────────────────────────────────────────
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildMetadataTab(AppFallbackPalette c) {
    final state = widget.state;
    final hookTitle = state.metaTitle.isNotEmpty
        ? state.metaTitle
        : (state.videoName != null
            ? 'Tóm Tắt Phim: ${p.withoutExtension(state.videoName!)} | Cú Twist Nghẹt Thở'
            : 'Tóm Tắt Phim Điện Ảnh');

    final metaDesc = state.metaDesc.isNotEmpty
        ? state.metaDesc
        : (state.segments.isNotEmpty
            ? state.segments.map((s) => s.voiceoverText).take(3).join(' ')
            : 'Video review tóm tắt nội dung tác phẩm điện ảnh kịch tính và hấp dẫn. Đăng ký kênh để đón xem nhiều siêu phẩm hơn!');

    final hashtags = state.metaHashtags.isNotEmpty
        ? state.metaHashtags.join(' ')
        : '#reviewphim #tomtatphim #phimhay #${state.genre.id} #cinema';

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _buildMetaCard(
          c,
          title: 'Tiêu Đề Hook Video (YouTube / TikTok)',
          content: hookTitle,
          tooltip: 'Sao chép tiêu đề',
        ),
        const SizedBox(height: 12),
        _buildMetaCard(
          c,
          title: 'Mô Tả Video Tóm Tắt',
          content: metaDesc,
          tooltip: 'Sao chép mô tả',
        ),
        const SizedBox(height: 12),
        _buildMetaCard(
          c,
          title: 'Hashtags Thịnh Hành',
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
                visualDensity: VisualDensity.compact,
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: content));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Đã sao chép: $title'), duration: const Duration(seconds: 1)),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 4),
          SelectableText(
            content,
            style: TextStyle(fontSize: 11, color: c.textPrimary, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoGroup(AppFallbackPalette c, String title, List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: c.surfaceLight.withOpacity(0.25),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: c.primary),
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }

  Widget _buildInfoRow(AppFallbackPalette c, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 10.5, color: c.textMuted)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w500, color: c.textPrimary),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
