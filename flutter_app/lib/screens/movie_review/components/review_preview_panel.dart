import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import '../../../../core/app_colors.dart';
import '../../../../widgets/app_kit.dart';
import '../../../../widgets/video_player_widget.dart';
import '../controllers/movie_review_controller.dart';
import '../models/movie_review_model.dart';
import 'review_step_progress_widget.dart';

class ReviewPreviewPanel extends StatefulWidget {
  final MovieReviewState state;
  final MovieReviewController controller;

  const ReviewPreviewPanel({
    super.key,
    required this.state,
    required this.controller,
  });

  @override
  State<ReviewPreviewPanel> createState() => _ReviewPreviewPanelState();
}

class _ReviewPreviewPanelState extends State<ReviewPreviewPanel> {
  int _activeTab = 0; // 0: Xuất Bản & Logs, 1: Tiến Trình 7 Bước

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final state = widget.state;
    final controller = widget.controller;
    final hasOutput = state.outputVideoPath != null && File(state.outputVideoPath!).existsSync();

    return Container(
      color: c.surface,
      child: Column(
        children: [
          // ── HEADER WITH 2-TAB SWITCHER ──
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: c.border)),
            ),
            child: Row(
              children: [
                _buildHeaderTab(
                  index: 0,
                  label: '🎬 Xuất Bản & Logs',
                  isActive: _activeTab == 0,
                  c: c,
                ),
                const SizedBox(width: 8),
                _buildHeaderTab(
                  index: 1,
                  label: '📋 Tiến Trình 7 Bước',
                  isActive: _activeTab == 1,
                  c: c,
                ),
              ],
            ),
          ),

          // ── BODY CONTENT ──
          Expanded(
            child: _activeTab == 1
                ? ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      ReviewStepProgressWidget(
                        state: state,
                        workspacePath: controller.workspacePath,
                        outputVideoPath: state.outputVideoPath,
                        onRerunStep: (stepId) => controller.rerunFromStep(stepId),
                        onDeleteStepCache: (stepId) => controller.deleteStepCache(stepId),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: c.surfaceLight,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: c.border),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.folder_outlined, size: 14, color: c.textMuted),
                                const SizedBox(width: 6),
                                Text(
                                  'Thư mục lưu trữ workspace:',
                                  style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: c.textSecondary),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            SelectableText(
                              controller.workspacePath,
                              style: TextStyle(fontSize: 9.5, color: c.textMuted, fontFamily: 'monospace'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  )
                : ListView(
                    padding: const EdgeInsets.all(14),
                    children: [
                      // 1. KẾT QUẢ VIDEO HOẶC PREVIEW CARD
                      if (hasOutput)
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: c.surfaceLight,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppColors.statusCompleted.withOpacity(0.5)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.check_circle, color: AppColors.statusCompleted, size: 18),
                                  const SizedBox(width: 8),
                                  const Expanded(
                                    child: Text(
                                      'Video Review Hoàn Tất!',
                                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.statusCompleted),
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.folder_open, size: 16, color: AppColors.primary),
                                    tooltip: 'Mở thư mục chứa video',
                                    onPressed: () {
                                      final dir = File(state.outputVideoPath!).parent.path;
                                      if (Platform.isMacOS) {
                                        Process.run('open', [dir]);
                                      } else if (Platform.isWindows) {
                                        Process.run('explorer.exe', [dir]);
                                      }
                                    },
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: AspectRatio(
                                  aspectRatio: state.aspectRatio == '9:16' ? 9 / 16 : 16 / 9,
                                  child: VideoPlayerWidget(
                                    key: ValueKey(state.outputVideoPath!),
                                    videoPath: state.outputVideoPath!,
                                    autoPlay: false,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                p.basename(state.outputVideoPath!),
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                state.outputVideoPath!,
                                style: TextStyle(fontSize: 10, color: c.textMuted),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        )
                      else
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: c.surfaceLight,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: c.border),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(
                                children: [
                                  Icon(Icons.movie_filter_outlined, size: 18, color: AppColors.primary),
                                  SizedBox(width: 8),
                                  Text(
                                    'Thông Số Video Review Dự Kiến',
                                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              _buildInfoRow(c, 'Tổng câu thoại:', '${state.segments.length} phân đoạn'),
                              _buildInfoRow(c, 'Kho cảnh minh họa:', '${state.availableScenes.length} scenes'),
                              _buildInfoRow(c, 'Thời lượng ước tính:', '~${(state.estimatedDurationSec / 60).toStringAsFixed(1)} phút'),
                              _buildInfoRow(c, 'Tỷ lệ khung hình:', state.aspectRatio == '9:16' ? '9:16 Dọc (TikTok)' : '16:9 Ngang (YouTube)'),
                              _buildInfoRow(c, 'Ngôn ngữ review:', state.targetLang.toUpperCase()),
                              _buildInfoRow(c, 'Giọng đọc:', state.ttsVoice == 'hoai_my' ? 'Hoài My (Nữ)' : 'Nam Minh (Nam)'),
                              _buildInfoRow(c, 'Phụ đề ASS:', state.burnSubtitles ? 'Ghép nổi (Đồng bộ TTS)' : 'Tắt'),
                              _buildInfoRow(c, 'Inpaint xóa sub:', state.enableInpaint ? 'Bật làm mờ' : 'Tắt'),
                            ],
                          ),
                        ),

                      const SizedBox(height: 16),

                      // 2. NÚT DỰNG & XUẤT VIDEO HOẶC THẺ TIẾN ĐỘ ĐANG XỬ LÝ
                      if (state.isRendering)
                        _buildRenderingProgressCard(c, state, controller)
                      else
                        SizedBox(
                          width: double.infinity,
                          height: 42,
                          child: AppButton.success(
                            icon: Icons.movie_creation,
                            label: '🎬 DỰNG & XUẤT VIDEO REVIEW',
                            isLoading: false,
                            onPressed: state.segments.isEmpty
                                ? null
                                : () => controller.startRender(),
                          ),
                        ),

                      const SizedBox(height: 16),

                      // 3. CONSOLE LOGS TRỰC TIẾP
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Text('Console Logs', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: c.textSecondary)),
                              const SizedBox(width: 8),
                              Text('(${state.consoleLogs.length} dòng)', style: TextStyle(fontSize: 10, color: c.textMuted)),
                            ],
                          ),
                          IconButton(
                            icon: const Icon(Icons.copy_rounded, size: 15, color: AppColors.primary),
                            tooltip: 'Sao chép toàn bộ logs',
                            visualDensity: VisualDensity.compact,
                            splashRadius: 16,
                            onPressed: state.consoleLogs.isEmpty
                                ? null
                                : () {
                                    Clipboard.setData(ClipboardData(text: state.consoleLogs.join('\n')));
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Đã sao chép toàn bộ console logs vào Clipboard!'),
                                        duration: Duration(seconds: 2),
                                      ),
                                    );
                                  },
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Container(
                        height: 180,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.black45,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: c.border),
                        ),
                        child: state.consoleLogs.isEmpty
                            ? Center(child: Text('Chưa có log tiến trình.', style: TextStyle(fontSize: 10, color: c.textMuted)))
                            : ListView.builder(
                                reverse: true,
                                itemCount: state.consoleLogs.length,
                                itemBuilder: (ctx, idx) {
                                  final log = state.consoleLogs[state.consoleLogs.length - 1 - idx];
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 1.5),
                                    child: SelectableText(
                                      log,
                                      style: const TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 9.5,
                                        color: Colors.white70,
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderTab({
    required int index,
    required String label,
    required bool isActive,
    required AppFallbackPalette c,
  }) {
    return InkWell(
      onTap: () => setState(() => _activeTab = index),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? AppColors.primary.withOpacity(0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isActive ? AppColors.primary : Colors.transparent,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
            color: isActive ? AppColors.primary : c.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildRenderingProgressCard(
    AppFallbackPalette c,
    MovieReviewState state,
    MovieReviewController controller,
  ) {
    final pctInt = (state.progress * 100).clamp(0, 100).toInt();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.surfaceLight,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.primary.withOpacity(0.35)),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                    ),
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Đang Dựng Video Review...',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              Text(
                '$pctInt%',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: state.progress.clamp(0.0, 1.0),
              minHeight: 7,
              backgroundColor: c.border,
              valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            state.statusMessage.isEmpty ? 'Đang xử lý...' : state.statusMessage,
            style: TextStyle(
              fontSize: 11,
              color: c.textSecondary,
              fontStyle: FontStyle.italic,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 32,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.stop_circle_outlined, size: 14, color: AppColors.statusFailed),
              label: const Text(
                'Hủy Bỏ Tiến Trình',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.statusFailed),
              ),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: AppColors.statusFailed.withOpacity(0.4)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                padding: EdgeInsets.zero,
              ),
              onPressed: controller.cancelProcess,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(AppFallbackPalette c, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: c.textSecondary)),
          Text(value, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white)),
        ],
      ),
    );
  }
}
