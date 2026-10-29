import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../../../core/app_colors.dart';
import '../../../utils/time_format_utils.dart';
import '../../../widgets/app_kit.dart';
import '../models/html_to_video_models.dart';

class HtmlPropertiesInspector extends StatelessWidget {
  final String htmlPath;
  final String outputPath;
  final int width;
  final int height;
  final double fps;
  final String durationStr;
  final String numWorkers;
  final String codec;
  final HtmlAudioSourceMode audioSourceMode;
  final String scriptPath;
  final String audioPath;
  final bool burnSubtitles;
  final bool isRunning;
  final bool isCompleted;
  final VoidCallback onStartRender;
  final VoidCallback onOpenOutputFile;
  final VoidCallback onOpenOutputFolder;

  const HtmlPropertiesInspector({
    super.key,
    required this.htmlPath,
    required this.outputPath,
    required this.width,
    required this.height,
    required this.fps,
    required this.durationStr,
    required this.numWorkers,
    required this.codec,
    required this.audioSourceMode,
    required this.scriptPath,
    required this.audioPath,
    required this.burnSubtitles,
    required this.isRunning,
    required this.isCompleted,
    required this.onStartRender,
    required this.onOpenOutputFile,
    required this.onOpenOutputFolder,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final outFile = outputPath.isNotEmpty ? File(outputPath) : null;
    final outExists = outFile != null && outFile.existsSync();
    final outSizeStr = outExists ? TimeFormatUtils.formatFileSize(outFile.lengthSync()) : '--';

    String modeLabel;
    switch (audioSourceMode) {
      case HtmlAudioSourceMode.autoScript:
        modeLabel = 'Tự động từ Kịch bản';
        break;
      case HtmlAudioSourceMode.manualAudio:
        modeLabel = 'Ghép Audio/Sub sẵn';
        break;
      case HtmlAudioSourceMode.videoOnly:
        modeLabel = 'Chỉ Hình ảnh HTML';
        break;
    }

    return Container(
      color: c.surface,
      child: Column(
        children: [
          // ── HEADER 38PX ──
          Container(
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: c.surfaceDark,
              border: Border(bottom: BorderSide(color: c.border)),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded, size: 14, color: c.primary),
                const SizedBox(width: 6),
                Text(
                  'THUỘC TÍNH & ĐẦU RA',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: c.textPrimary,
                    letterSpacing: 0.4,
                  ),
                ),
              ],
            ),
          ),

          // ── BODY ──
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                Text(
                  'THÔNG SỐ KẾT XUẤT (RENDER SPEC)',
                  style: TextStyle(
                    color: c.primary,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                _buildInfoRow(c, 'File HTML', htmlPath.isNotEmpty ? p.basename(htmlPath) : 'Chưa chọn'),
                _buildInfoRow(c, 'File Đích', outputPath.isNotEmpty ? p.basename(outputPath) : 'Chưa đặt'),
                _buildInfoRow(c, 'Độ Phân Giải', '${width}x$height px'),
                _buildInfoRow(c, 'Khung Hình', '${fps.toInt()} FPS'),
                _buildInfoRow(c, 'Thời Lượng', '${durationStr}s'),
                _buildInfoRow(
                  c,
                  'Đa Luồng',
                  numWorkers == '0' ? 'Auto Scene Workers' : '$numWorkers Workers',
                ),
                _buildInfoRow(c, 'Video Codec', codec == 'libx264' ? 'H.264 (MP4)' : 'H.265 (HEVC)'),
                Divider(color: c.border, height: 20),
                Text(
                  'ÂM THANH & PHỤ ĐỀ',
                  style: TextStyle(
                    color: c.primary,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                _buildInfoRow(c, 'Chế Độ Audio', modeLabel),
                if (audioSourceMode == HtmlAudioSourceMode.autoScript)
                  _buildInfoRow(
                    c,
                    'File Kịch Bản',
                    scriptPath.isNotEmpty ? p.basename(scriptPath) : 'Chưa chọn',
                  ),
                if (audioSourceMode == HtmlAudioSourceMode.manualAudio)
                  _buildInfoRow(
                    c,
                    'File Audio',
                    audioPath.isNotEmpty ? p.basename(audioPath) : 'Chưa chọn',
                  ),
                _buildInfoRow(c, 'Đốt Phụ Đề', burnSubtitles ? 'Bật (Hardsub)' : 'Tắt'),
                Divider(color: c.border, height: 20),
                Text(
                  'KẾT QUẢ FILE MP4',
                  style: TextStyle(
                    color: c.primary,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                _buildInfoRow(c, 'Trạng Thái', outExists ? 'Đã có file MP4' : 'Chưa xuất'),
                _buildInfoRow(c, 'Dung Lượng', outSizeStr),
                const SizedBox(height: 14),
                AppButton.primary(
                  icon: Icons.movie_creation_rounded,
                  label: isRunning ? 'Đang Kết Xuất...' : 'Xuất Video MP4',
                  isLoading: isRunning,
                  height: 32,
                  onPressed: (htmlPath.isNotEmpty && !isRunning) ? onStartRender : null,
                ),
                if (outExists) ...[
                  const SizedBox(height: 8),
                  AppButton.outlined(
                    icon: Icons.play_circle_outline_rounded,
                    label: 'Mở Bằng Trình Phát Hệ Thống',
                    height: 30,
                    onPressed: onOpenOutputFile,
                  ),
                  const SizedBox(height: 6),
                  AppButton.ghost(
                    icon: Icons.folder_open_rounded,
                    label: 'Hiển Thị Trong Thư Mục',
                    height: 28,
                    onPressed: onOpenOutputFolder,
                  ),
                ],
              ],
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: TextStyle(color: c.textSecondary, fontSize: 11),
            ),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: c.textPrimary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

