import 'dart:io';
import 'package:flutter/material.dart';
import '../../../core/app_colors.dart';
import '../../../models/douyin_video_item.dart';
import '../../../widgets/video_player_widget.dart';

/// Right Preview Panel for Douyin Downloader screen.
class DouyinPreviewPanel extends StatelessWidget {
  final DouyinVideoItem? selectedItem;
  final String activeProject;
  final ValueChanged<DouyinVideoItem> onDownloadSingle;

  const DouyinPreviewPanel({
    super.key,
    required this.selectedItem,
    required this.activeProject,
    required this.onDownloadSingle,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);

    if (selectedItem == null) {
      return Container(
        padding: const EdgeInsets.all(16),
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.ondemand_video_outlined, size: 40, color: c.textMuted),
            const SizedBox(height: 10),
            Text('Chọn video để xem trước', style: TextStyle(color: c.textMuted, fontSize: 12)),
          ],
        ),
      );
    }

    final isLocal = selectedItem!.isDownloaded &&
        selectedItem!.localFilePath != null &&
        File(selectedItem!.localFilePath!).existsSync();
    final targetPlayPath = isLocal ? selectedItem!.localFilePath! : selectedItem!.directUrl;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.surface,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.ondemand_video, size: 16, color: c.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Xem Trước Video — #${selectedItem!.index}',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: c.textPrimary, fontSize: 13, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isLocal
                      ? const Color(0xFF059669).withOpacity(0.2)
                      : const Color(0xFFD97706).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: isLocal ? const Color(0xFF059669) : const Color(0xFFD97706),
                    width: 0.8,
                  ),
                ),
                child: Text(
                  isLocal ? '✓ File Local (src/)' : '⚡ Live Stream CDN',
                  style: TextStyle(
                    color: isLocal ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Preview Player (Local File OR Live CDN Stream)
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: c.border),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: VideoPlayerWidget(
                  key: ValueKey(targetPlayPath),
                  videoPath: targetPlayPath,
                  autoPlay: false,
                ),
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Specs Table
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: c.surfaceDark, borderRadius: BorderRadius.circular(6)),
            child: Column(
              children: [
                _buildSpecRow('Tên file tải về:', selectedItem!.filename, c),
                _buildSpecRow('Ngày đăng (Timestamp):', selectedItem!.timestampStr ?? 'N/A', c),
                _buildSpecRow('Video ID / Hash:', selectedItem!.shortHash, c),
                _buildSpecRow('Chất lượng / Bitrate:', selectedItem!.bitrateStr, c),
                _buildSpecRow('Lưu về thư mục:', 'resources/$activeProject/src/', c),
              ],
            ),
          ),

          const SizedBox(height: 12),

          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: isLocal ? const Color(0xFF059669) : const Color(0xFF2563EB),
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 38),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            ),
            icon: Icon(isLocal ? Icons.check_circle : Icons.download, size: 16),
            label: Text(
              isLocal
                  ? '✓ Đã Có Trong src/ (Tải Lại Đè Video #${selectedItem!.index})'
                  : '📥 Tải Ngay Video #${selectedItem!.index} Về src/',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
            onPressed: () => onDownloadSingle(selectedItem!),
          ),
        ],
      ),
    );
  }

  Widget _buildSpecRow(String label, String val, AppFallbackPalette c) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: c.textSecondary, fontSize: 11)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              val,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontFamily: 'monospace', color: c.textPrimary, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}
