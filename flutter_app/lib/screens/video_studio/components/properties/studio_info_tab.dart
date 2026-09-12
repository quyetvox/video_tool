import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../../../../core/app_colors.dart';
import '../../../../models/studio_state.dart';
import '../../../../models/video_file.dart';
import '../../../../utils/time_format_utils.dart';

/// 'info' Tab: Detailed video technical metadata and layer counts.
class StudioInfoTab extends StatelessWidget {
  final StudioSnapshot state;
  final VideoFile? video;
  final double duration;
  final double currentTime;
  final String exportResolution;
  final String exportRatio;
  final String exportFps;

  const StudioInfoTab({
    super.key,
    required this.state,
    required this.video,
    required this.duration,
    required this.currentTime,
    required this.exportResolution,
    required this.exportRatio,
    required this.exportFps,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '📊 Thông tin chi tiết video:',
          style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),

        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: c.surfaceDark,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: c.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildInfoRow(c, 'Tên tệp:', video?.basename ?? 'Chưa chọn'),
              _buildInfoRow(c, 'Định dạng:', video != null ? p.extension(video!.fullPath).toUpperCase() : 'N/A'),
              _buildInfoRow(c, 'Dung lượng:', video != null ? TimeFormatUtils.formatFileSize(video!.sizeBytes) : '0 MB'),
              _buildInfoRow(c, 'Thời lượng:', TimeFormatUtils.formatSubtitleTime(duration)),
              _buildInfoRow(c, 'Vị trí Playhead:', TimeFormatUtils.formatSubtitleTime(currentTime)),
              _buildInfoRow(c, 'Độ phân giải xuất:', exportResolution),
              _buildInfoRow(c, 'Tỷ lệ khung hình:', exportRatio),
              _buildInfoRow(c, 'Tốc độ khung hình:', exportFps),
            ],
          ),
        ),
        const SizedBox(height: 10),

        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: c.surfaceDark,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: c.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Đa lớp (Layers count):', style: TextStyle(color: c.primary, fontSize: 10.5, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text('• Lớp phủ hình ảnh: ${state.overlayClips.length} ảnh', style: TextStyle(color: c.textSecondary, fontSize: 10)),
              Text('• Nhạc nền / SFX: ${state.audioClips.length} clip', style: TextStyle(color: c.textSecondary, fontSize: 10)),
              Text('• Câu phụ đề: ${state.subtitles.length} câu', style: TextStyle(color: c.textSecondary, fontSize: 10)),
              Text('• Vùng cắt rác: ${state.cutSegments.length} đoạn', style: TextStyle(color: c.textSecondary, fontSize: 10)),
              Text('• Phân đoạn chia: ${state.splitSegments.length} đoạn', style: TextStyle(color: c.textSecondary, fontSize: 10)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(AppColorTokens c, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: c.textSecondary, fontSize: 10)),
          Text(
            value,
            style: TextStyle(
              color: c.textPrimary,
              fontSize: 10,
              fontFamily: 'monospace',
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
