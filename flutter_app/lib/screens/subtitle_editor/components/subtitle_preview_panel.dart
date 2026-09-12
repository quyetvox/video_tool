import 'package:flutter/material.dart';
import '../../../models/video_file.dart';
import '../../../widgets/video_player_widget.dart';

class SubtitlePreviewPanel extends StatelessWidget {
  final VideoFile selectedVideo;
  final GlobalKey<VideoPlayerWidgetState> playerKey;

  const SubtitlePreviewPanel({
    super.key,
    required this.selectedVideo,
    required this.playerKey,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(16),
      color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.ondemand_video, size: 18, color: Colors.cyanAccent),
              SizedBox(width: 8),
              Text('Xem trước Video', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: VideoPlayerWidget(
              key: playerKey,
              videoPath: selectedVideo.fullPath,
              autoPlay: false,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
              ),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline, size: 16, color: Colors.cyanAccent),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Mẹo: Bấm vào mốc thời gian của từng câu bên trái để tự động nhảy (Seek) video tới đúng đoạn đó.',
                    style: TextStyle(fontSize: 11, color: Colors.grey, height: 1.3),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
