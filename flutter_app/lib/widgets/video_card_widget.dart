import 'package:flutter/material.dart';
import '../models/video_file.dart';
import '../utils/time_format_utils.dart';
import 'video_thumbnail_widget.dart';

class VideoCardWidget extends StatelessWidget {
  final VideoFile video;
  final bool isSelected;
  final bool isRunning;
  final VoidCallback onSelect;
  final VoidCallback? onTranslateVoice;
  final VoidCallback? onTranslateOcr;
  final VoidCallback? onResumeJob;
  final VoidCallback? onOpenSubtitleEditor;
  final VoidCallback? onOpenStudio;
  final VoidCallback? onRename;
  final VoidCallback? onDelete;

  const VideoCardWidget({
    super.key,
    required this.video,
    required this.isSelected,
    this.isRunning = false,
    required this.onSelect,
    this.onTranslateVoice,
    this.onTranslateOcr,
    this.onResumeJob,
    this.onOpenSubtitleEditor,
    this.onOpenStudio,
    this.onRename,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Color badgeColor;
    String badgeText;
    switch (video.category) {
      case VideoCategory.src:
        badgeColor = Colors.blue;
        badgeText = 'GỐC (SRC)';
        break;
      case VideoCategory.cut:
        badgeColor = Colors.orange;
        badgeText = 'ĐÃ CẮT (CUT)';
        break;
      case VideoCategory.merge:
        badgeColor = Colors.purple;
        badgeText = 'ĐÃ GHÉP';
        break;
      case VideoCategory.output:
        badgeColor = Colors.green;
        badgeText = 'XUẤT (OUTPUT)';
        break;
      case VideoCategory.workspace:
        badgeColor = Colors.grey;
        badgeText = 'WORKSPACE';
        break;
      case VideoCategory.cloudOnly:
        badgeColor = Colors.indigo;
        badgeText = 'CLOUD ONLY';
        break;
    }

    return Card(
      elevation: isSelected ? 4 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: isSelected
              ? Colors.cyanAccent
              : isRunning
                  ? Colors.blueAccent
                  : isDark
                      ? const Color(0xFF334155)
                      : const Color(0xFFE2E8F0),
          width: isSelected || isRunning ? 2 : 1,
        ),
      ),
      color: isSelected
          ? (isDark ? const Color(0xFF1E293B) : const Color(0xFFE0F2FE))
          : (isDark ? const Color(0xFF0F172A) : Colors.white),
      child: InkWell(
        onTap: onSelect,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header: Badge + Category + Running Spinner / Action Menu
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: badgeColor.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: badgeColor.withOpacity(0.4)),
                    ),
                    child: Text(
                      badgeText,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: badgeColor,
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (isRunning) ...[
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 6),
                    const Text('Đang chạy...', style: TextStyle(fontSize: 10, color: Colors.blueAccent)),
                  ] else ...[
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert, size: 18),
                      padding: EdgeInsets.zero,
                      onSelected: (val) {
                        switch (val) {
                          case 'voice':
                            onTranslateVoice?.call();
                            break;
                          case 'ocr':
                            onTranslateOcr?.call();
                            break;
                          case 'resume':
                            onResumeJob?.call();
                            break;
                          case 'sub':
                            onOpenSubtitleEditor?.call();
                            break;
                          case 'studio':
                            onOpenStudio?.call();
                            break;
                          case 'rename':
                            onRename?.call();
                            break;
                          case 'delete':
                            onDelete?.call();
                            break;
                        }
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'voice',
                          child: Row(
                            children: [
                              Icon(Icons.mic, size: 16, color: Colors.cyanAccent),
                              SizedBox(width: 8),
                              Text('Dịch Voice (Whisper + Demucs + TTS)'),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'ocr',
                          child: Row(
                            children: [
                              Icon(Icons.subtitles, size: 16, color: Colors.orangeAccent),
                              SizedBox(width: 8),
                              Text('Dịch Sub Hardsub (OCR Only ~0s)'),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'resume',
                          child: Row(
                            children: [
                              Icon(Icons.replay, size: 16, color: Colors.greenAccent),
                              SizedBox(width: 8),
                              Text('Resume Pipeline'),
                            ],
                          ),
                        ),
                        const PopupMenuDivider(),
                        const PopupMenuItem(
                          value: 'sub',
                          child: Row(
                            children: [
                              Icon(Icons.edit_note, size: 16),
                              SizedBox(width: 8),
                              Text('Chỉnh sửa phụ đề s08'),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'studio',
                          child: Row(
                            children: [
                              Icon(Icons.content_cut, size: 16),
                              SizedBox(width: 8),
                              Text('Mở Video Studio / Cắt video'),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'rename',
                          child: Row(
                            children: [
                              Icon(Icons.drive_file_rename_outline, size: 16),
                              SizedBox(width: 8),
                              Text('Đổi tên file'),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(Icons.delete, size: 16, color: Colors.redAccent),
                              SizedBox(width: 8),
                              Text('Xóa file', style: TextStyle(color: Colors.redAccent)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),

              // Thumbnail Image + Video Name
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  VideoThumbnailWidget(
                    videoPath: video.fullPath,
                    width: 58,
                    height: 58,
                    showDuration: true,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          video.basename,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: isSelected ? Colors.cyanAccent : null,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Text(
                              TimeFormatUtils.formatFileSize(video.sizeBytes),
                              style: const TextStyle(fontSize: 11, color: Colors.grey),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Quick Action Buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                        visualDensity: VisualDensity.compact,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      ),
                      icon: const Icon(Icons.mic, size: 14, color: Colors.cyanAccent),
                      label: const Text('Voice', style: TextStyle(fontSize: 11)),
                      onPressed: onTranslateVoice,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                        visualDensity: VisualDensity.compact,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      ),
                      icon: const Icon(Icons.subtitles, size: 14, color: Colors.orangeAccent),
                      label: const Text('OCR Only', style: TextStyle(fontSize: 11)),
                      onPressed: onTranslateOcr,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
