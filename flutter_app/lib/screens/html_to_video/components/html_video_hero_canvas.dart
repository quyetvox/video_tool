import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../../../core/app_colors.dart';
import '../../../widgets/app_kit.dart';
import '../../../widgets/video_player_widget.dart';
import '../models/html_to_video_models.dart';

class HtmlVideoHeroCanvas extends StatelessWidget {
  final String htmlPath;
  final String outputPath;
  final String? activePreviewVideoPath;
  final bool showVideoPlayer;
  final ValueChanged<bool> onTogglePreviewMode;
  final HtmlAudioSourceMode audioSourceMode;
  final String scriptPath;
  final String audioPath;
  final String assPath;
  final String voice;
  final int width;
  final int height;
  final double fps;
  final String durationStr;
  final String numWorkers;
  final bool burnSubtitles;
  final bool isRunning;
  final bool isCompleted;
  final double progress;
  final String statusMessage;
  final GlobalKey<VideoPlayerWidgetState> playerKey;
  final VoidCallback onToggleFullscreen;
  final VoidCallback onPickHtml;
  final VoidCallback onOpenHtmlInBrowser;
  final VoidCallback onOpenOutputFile;
  final VoidCallback onOpenOutputFolder;
  final VoidCallback onStartRender;

  const HtmlVideoHeroCanvas({
    super.key,
    required this.htmlPath,
    required this.outputPath,
    required this.activePreviewVideoPath,
    required this.showVideoPlayer,
    required this.onTogglePreviewMode,
    required this.audioSourceMode,
    required this.scriptPath,
    required this.audioPath,
    required this.assPath,
    required this.voice,
    required this.width,
    required this.height,
    required this.fps,
    required this.durationStr,
    required this.numWorkers,
    required this.burnSubtitles,
    required this.isRunning,
    required this.isCompleted,
    required this.progress,
    required this.statusMessage,
    required this.playerKey,
    required this.onToggleFullscreen,
    required this.onPickHtml,
    required this.onOpenHtmlInBrowser,
    required this.onOpenOutputFile,
    required this.onOpenOutputFolder,
    required this.onStartRender,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final hasPreviewVideo = activePreviewVideoPath != null &&
        activePreviewVideoPath!.isNotEmpty &&
        File(activePreviewVideoPath!).existsSync();

    return Container(
      decoration: BoxDecoration(
        color: c.surfaceDark,
        border: Border(right: BorderSide(color: c.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── TOP CANVAS MODE SWITCHER BAR (38PX) ──
          Container(
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: c.surface,
              border: Border(bottom: BorderSide(color: c.border)),
            ),
            child: Row(
              children: [
                AppSegmentButton(
                  icon: Icons.html_rounded,
                  label: 'Cấu Hình Scene HTML',
                  isSelected: !showVideoPlayer || !hasPreviewVideo,
                  onTap: () => onTogglePreviewMode(false),
                ),
                const SizedBox(width: 6),
                AppSegmentButton(
                  icon: Icons.play_circle_outline_rounded,
                  label: hasPreviewVideo
                      ? 'Xem Video (${p.basename(activePreviewVideoPath!)})'
                      : 'Trình Phát Video MP4',
                  isSelected: showVideoPlayer && hasPreviewVideo,
                  onTap: () {
                    if (hasPreviewVideo) {
                      onTogglePreviewMode(true);
                    }
                  },
                ),
                const Spacer(),
                if (htmlPath.isNotEmpty)
                  AppButton.ghost(
                    icon: Icons.open_in_browser_rounded,
                    label: 'Xem thử HTML trên Trình duyệt',
                    onPressed: onOpenHtmlInBrowser,
                  ),
              ],
            ),
          ),

          // ── MAIN CANVAS CONTENT ──
          Expanded(
            child: (showVideoPlayer && hasPreviewVideo)
                ? VideoPlayerWidget(
                    key: ValueKey(activePreviewVideoPath),
                    videoPath: activePreviewVideoPath!,
                    onToggleFullscreen: onToggleFullscreen,
                  )
                : _buildHtmlHeroOverview(context, c, hasPreviewVideo),
          ),
        ],
      ),
    );
  }

  Widget _buildHtmlHeroOverview(
    BuildContext context,
    AppFallbackPalette c,
    bool hasPreviewVideo,
  ) {
    final hasHtml = htmlPath.trim().isNotEmpty;

    if (!hasHtml) {
      return Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 420),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: c.border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: c.primary.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.html_rounded, size: 36, color: c.primary),
              ),
              const SizedBox(height: 14),
              Text(
                'Chưa chọn tệp HTML hoạt họa',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: c.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Chọn file .html bài giảng hoặc slide hoạt họa để kết xuất sang MP4 tốc độ cao với đa luồng Scene Split & thuyết minh tự động.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11.5,
                  color: c.textSecondary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              AppButton.primary(
                icon: Icons.folder_open_rounded,
                label: 'Chọn File .HTML Nguồn',
                height: 34,
                onPressed: onPickHtml,
              ),
            ],
          ),
        ),
      );
    }

    String audioSummary;
    switch (audioSourceMode) {
      case HtmlAudioSourceMode.autoScript:
        audioSummary = scriptPath.isNotEmpty
            ? 'Tự động từ kịch bản: ${p.basename(scriptPath)} ($voice)'
            : 'Tự động từ kịch bản (Chưa chọn file .txt/.md)';
        break;
      case HtmlAudioSourceMode.manualAudio:
        audioSummary = audioPath.isNotEmpty
            ? 'Ghép Audio sẵn: ${p.basename(audioPath)}'
            : 'Ghép Audio/Sub sẵn (Chưa chọn file)';
        break;
      case HtmlAudioSourceMode.videoOnly:
        audioSummary = 'Chỉ xuất hình ảnh HTML (Không âm thanh)';
        break;
    }

    final workerText = numWorkers == '0'
        ? 'Tự động phân luồng theo Scene'
        : '$numWorkers Worker song song (-c:v copy)';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── HERO SUMMARY CARD ──
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: c.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: c.primary.withOpacity(0.14),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(Icons.movie_filter_rounded, color: c.primary, size: 22),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                p.basename(htmlPath),
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: c.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                htmlPath,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 10.5,
                                  color: c.textMuted,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ],
                          ),
                        ),
                        AppButton.outlined(
                          icon: Icons.swap_horiz_rounded,
                          label: 'Đổi File',
                          onPressed: isRunning ? null : onPickHtml,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Divider(color: c.border, height: 1),
                    const SizedBox(height: 14),
                    _buildPipelineSummaryRow(
                      c: c,
                      icon: Icons.speed_rounded,
                      title: 'Cấu hình Khung hình & Đa luồng',
                      value: '${width}x$height • ${fps.toInt()} FPS • Thời lượng ${durationStr}s • $workerText',
                    ),
                    const SizedBox(height: 10),
                    _buildPipelineSummaryRow(
                      c: c,
                      icon: Icons.record_voice_over_rounded,
                      title: 'Nguồn Thuyết minh & Âm thanh',
                      value: audioSummary,
                    ),
                    const SizedBox(height: 10),
                    _buildPipelineSummaryRow(
                      c: c,
                      icon: Icons.subtitles_outlined,
                      title: 'Phụ đề & Đầu ra MP4',
                      value:
                          '${burnSubtitles ? "Đốt cứng phụ đề vào video" : "Không đốt phụ đề"} → ${outputPath.isNotEmpty ? p.basename(outputPath) : "Chưa đặt tên"}',
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // ── PROGRESS / ACTION BANNER ──
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isRunning
                        ? c.statusProcessing.withOpacity(0.6)
                        : isCompleted
                            ? c.statusCompleted.withOpacity(0.6)
                            : c.border,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          isRunning
                              ? Icons.autorenew_rounded
                              : isCompleted
                                  ? Icons.check_circle_rounded
                                  : Icons.bolt_rounded,
                          size: 16,
                          color: isRunning
                              ? c.statusProcessing
                              : isCompleted
                                  ? c.statusCompleted
                                  : c.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            statusMessage,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: c.textPrimary,
                            ),
                          ),
                        ),
                        Text(
                          '${(progress * 100).toStringAsFixed(0)}%',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'monospace',
                            color: isCompleted ? c.statusCompleted : c.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(5),
                      child: LinearProgressIndicator(
                        value: progress.clamp(0.0, 1.0),
                        minHeight: 7,
                        backgroundColor: c.surfaceDark,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          isCompleted ? c.statusCompleted : c.primary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (hasPreviewVideo) ...[
                          AppButton.secondary(
                            icon: Icons.play_arrow_rounded,
                            label: 'Phát Video Trong App',
                            onPressed: () => onTogglePreviewMode(true),
                          ),
                          const SizedBox(width: 8),
                        ],
                        if (isCompleted && outputPath.isNotEmpty) ...[
                          AppButton.outlined(
                            icon: Icons.open_in_new_rounded,
                            label: 'Mở File MP4',
                            onPressed: onOpenOutputFile,
                          ),
                          const SizedBox(width: 8),
                          AppButton.outlined(
                            icon: Icons.folder_open_rounded,
                            label: 'Hiện Thư Mục',
                            onPressed: onOpenOutputFolder,
                          ),
                          const SizedBox(width: 8),
                        ],
                        if (!isRunning)
                          AppButton.primary(
                            icon: Icons.movie_creation_rounded,
                            label: isCompleted ? 'Kết Xuất Lại MP4' : 'Bắt Đầu Xuất Video MP4',
                            height: 32,
                            onPressed: onStartRender,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPipelineSummaryRow({
    required AppFallbackPalette c,
    required IconData icon,
    required String title,
    required String value,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 15, color: c.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 10.5,
                  color: c.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  fontSize: 11.5,
                  color: c.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

