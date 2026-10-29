import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../../../core/app_colors.dart';
import '../../../widgets/app_kit.dart';
import '../../../widgets/tool_header_toolbar.dart';

class HtmlHeaderBar extends StatelessWidget {
  final String htmlPath;
  final String outputPath;
  final int width;
  final int height;
  final double fps;
  final String numWorkers;
  final bool isRunning;
  final bool isCompleted;
  final double progress;
  final String statusMessage;
  final VoidCallback onPickHtml;
  final VoidCallback onStartRender;
  final VoidCallback onStopRender;
  final VoidCallback onOpenOutputFolder;
  final VoidCallback? onSwitchToTtsStudio;

  const HtmlHeaderBar({
    super.key,
    required this.htmlPath,
    required this.outputPath,
    required this.width,
    required this.height,
    required this.fps,
    required this.numWorkers,
    required this.isRunning,
    required this.isCompleted,
    required this.progress,
    required this.statusMessage,
    required this.onPickHtml,
    required this.onStartRender,
    required this.onStopRender,
    required this.onOpenOutputFolder,
    this.onSwitchToTtsStudio,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final hasHtml = htmlPath.trim().isNotEmpty;
    final workerLabel = numWorkers == '0' ? 'Auto luồng' : '$numWorkers luồng';

    return ToolHeaderToolbar(
      icon: Icon(
        Icons.html_rounded,
        size: 16,
        color: c.primary,
      ),
      title: 'HTML to MP4 Studio',
      breadcrumb: hasHtml ? p.basename(htmlPath) : 'Chưa chọn tệp HTML nguồn',
      badge: isRunning
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: c.statusProcessingBg,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: c.statusProcessing.withOpacity(0.5), width: 0.8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 9,
                    height: 9,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      valueColor: AlwaysStoppedAnimation<Color>(c.statusProcessing),
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    '${(progress * 100).toStringAsFixed(0)}% • $statusMessage',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: c.statusProcessing,
                    ),
                  ),
                ],
              ),
            )
          : Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: c.surfaceLight.withOpacity(0.5),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: c.border.withOpacity(0.5), width: 0.8),
              ),
              child: Text(
                '${width}x$height • ${fps.toInt()} FPS • $workerLabel',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w500,
                  color: c.textSecondary,
                ),
              ),
            ),
      actions: [
        if (onSwitchToTtsStudio != null) ...[
          AppButton.ghost(
            icon: Icons.record_voice_over_outlined,
            label: 'Soạn Giọng Đọc TTS',
            onPressed: isRunning ? null : onSwitchToTtsStudio,
          ),
          const SizedBox(width: 6),
        ],
        AppButton.outlined(
          icon: Icons.folder_open_rounded,
          label: 'Chọn HTML',
          onPressed: isRunning ? null : onPickHtml,
        ),
        if (isCompleted && outputPath.isNotEmpty) ...[
          const SizedBox(width: 6),
          AppButton.secondary(
            icon: Icons.folder_special_outlined,
            label: 'Mở Thư Mục',
            onPressed: onOpenOutputFolder,
          ),
        ],
        const SizedBox(width: 8),
        if (isRunning)
          AppButton.danger(
            icon: Icons.stop_rounded,
            label: 'Dừng Render',
            onPressed: onStopRender,
          )
        else
          AppButton.primary(
            icon: Icons.movie_creation_rounded,
            label: 'Xuất Video MP4',
            onPressed: hasHtml ? onStartRender : null,
          ),
      ],
    );
  }
}

