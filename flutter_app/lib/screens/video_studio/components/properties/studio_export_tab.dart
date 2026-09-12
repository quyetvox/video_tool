import 'package:flutter/material.dart';
import '../../../../core/app_colors.dart';
import '../../../../core/studio_state_notifier.dart';
import '../../../../models/studio_state.dart';
import '../../../../models/video_file.dart';
import 'studio_clip_inspector_card.dart';

/// 'props' Tab: Export settings including filename, speed scaling, resolution, FPS, ratio, and bitrate.
class StudioExportTab extends StatelessWidget {
  final StudioSnapshot state;
  final StudioStateNotifier notifier;
  final VideoFile? video;
  final StudioToolMode toolMode;
  final TextEditingController exportFilenameController;
  final String exportResolution;
  final String exportFps;
  final String exportRatio;
  final String exportBitrate;
  final ValueChanged<String> onResolutionChanged;
  final ValueChanged<String> onFpsChanged;
  final ValueChanged<String> onRatioChanged;
  final ValueChanged<String> onBitrateChanged;
  final VoidCallback onResetDefaultFilename;
  final void Function(double speed) onSpeedChanged;

  const StudioExportTab({
    super.key,
    required this.state,
    required this.notifier,
    required this.video,
    required this.toolMode,
    required this.exportFilenameController,
    required this.exportResolution,
    required this.exportFps,
    required this.exportRatio,
    required this.exportBitrate,
    required this.onResolutionChanged,
    required this.onFpsChanged,
    required this.onRatioChanged,
    required this.onBitrateChanged,
    required this.onResetDefaultFilename,
    required this.onSpeedChanged,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StudioClipInspectorCard(state: state, notifier: notifier),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Tên file xuất:', style: TextStyle(color: c.textSecondary, fontSize: 10)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
              decoration: BoxDecoration(
                color: c.surfaceDark,
                borderRadius: BorderRadius.circular(3),
                border: Border.all(color: c.border, width: 0.5),
              ),
              child: Text(
                toolMode == StudioToolMode.merge
                    ? '📁 merge/'
                    : (toolMode == StudioToolMode.cut || toolMode == StudioToolMode.split ? '📁 cut/' : '📁 output/'),
                style: TextStyle(color: c.primary, fontSize: 9.5, fontFamily: 'monospace', fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Container(
          height: 32,
          decoration: BoxDecoration(
            color: c.surfaceDark,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: c.border, width: 0.6),
          ),
          child: Row(
            children: [
              const Padding(
                padding: EdgeInsets.only(left: 7, right: 4),
                child: Icon(Icons.movie_creation_outlined, size: 13, color: AppColors.textMuted),
              ),
              Expanded(
                child: TextField(
                  controller: exportFilenameController,
                  style: TextStyle(fontFamily: 'monospace', color: c.textPrimary, fontSize: 10.5),
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 7),
                    border: InputBorder.none,
                    hintText: 'Nhập tên file xuất...',
                    hintStyle: TextStyle(color: AppColors.textMuted, fontSize: 10.5),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.restore_rounded, size: 13, color: AppColors.textMuted),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                tooltip: 'Khôi phục tên mặc định',
                onPressed: onResetDefaultFilename,
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // ⚡ Bộ điều chỉnh Tốc độ Video Gốc (Speed Scaling)
        Text('Tốc độ video gốc:', style: TextStyle(color: c.textSecondary, fontSize: 10)),
        const SizedBox(height: 4),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0].map((speed) {
            final isSelected = (state.videoSpeed - speed).abs() < 0.01;
            return InkWell(
              onTap: () => onSpeedChanged(speed),
              borderRadius: BorderRadius.circular(4),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3.5),
                decoration: BoxDecoration(
                  color: isSelected ? c.primary.withOpacity(0.2) : c.surfaceDark,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: isSelected ? c.primary : c.border,
                    width: isSelected ? 1.0 : 0.6,
                  ),
                ),
                child: Text(
                  '${speed}x',
                  style: TextStyle(
                    color: isSelected ? c.primary : c.textSecondary,
                    fontSize: 10,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 8),

        Text('Độ phân giải:', style: TextStyle(color: c.textSecondary, fontSize: 10)),
        DropdownButton<String>(
          value: exportResolution,
          isExpanded: true,
          dropdownColor: c.surface,
          style: TextStyle(color: c.textPrimary, fontSize: 10.5),
          items: ['Giữ nguyên (1920x1080)', '1080x1920 (Dọc 9:16)', '1280x720']
              .map((e) => DropdownMenuItem(value: e, child: Text(e)))
              .toList(),
          onChanged: (v) {
            if (v != null) onResolutionChanged(v);
          },
        ),
        const SizedBox(height: 8),

        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('FPS:', style: TextStyle(color: c.textSecondary, fontSize: 10)),
                  DropdownButton<String>(
                    value: exportFps,
                    isExpanded: true,
                    dropdownColor: c.surface,
                    style: TextStyle(color: c.textPrimary, fontSize: 10.5),
                    items: ['30 fps', '60 fps', '24 fps']
                        .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) onFpsChanged(v);
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Tỷ lệ:', style: TextStyle(color: c.textSecondary, fontSize: 10)),
                  DropdownButton<String>(
                    value: exportRatio,
                    isExpanded: true,
                    dropdownColor: c.surface,
                    style: TextStyle(color: c.textPrimary, fontSize: 10.5),
                    items: ['16:9 (Ngang)', '9:16 (Dọc TikTok)', '1:1 (Vuông)']
                        .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) onRatioChanged(v);
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        Text('Chất lượng bitrate khi xuất:', style: TextStyle(color: c.textSecondary, fontSize: 10)),
        const SizedBox(height: 2),
        DropdownButton<String>(
          value: exportBitrate,
          isExpanded: true,
          dropdownColor: c.surface,
          style: TextStyle(color: c.textPrimary, fontSize: 10.5),
          items: const [
            DropdownMenuItem(value: '6M', child: Text('6.0M (Siêu nét - 2K/4K)')),
            DropdownMenuItem(value: '4M', child: Text('4.0M (Chuẩn nét - Mặc định)')),
            DropdownMenuItem(value: '2.5M', child: Text('2.5M (Trung bình - Cân bằng)')),
            DropdownMenuItem(value: '1.5M', child: Text('1.5M (Tiết kiệm dung lượng)')),
            DropdownMenuItem(value: '0.5M', child: Text('0.5M (Siêu nhẹ - Chia sẻ nhanh)')),
          ],
          onChanged: (v) {
            if (v != null) onBitrateChanged(v);
          },
        ),
      ],
    );
  }
}
