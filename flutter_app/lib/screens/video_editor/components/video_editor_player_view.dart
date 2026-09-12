import 'package:flutter/material.dart';
import '../../../core/app_colors.dart';
import '../../../models/video_file.dart';
import '../../../widgets/video_player_widget.dart';

class VideoEditorPlayerView extends StatelessWidget {
  final VideoFile? selectedVideo;
  final bool isPlayerFullscreen;
  final GlobalKey<VideoPlayerWidgetState> playerKey;
  final VoidCallback onToggleFullscreen;
  final ValueChanged<double> onPositionChanged;
  final ValueChanged<double> onDurationChanged;

  const VideoEditorPlayerView({
    super.key,
    required this.selectedVideo,
    required this.isPlayerFullscreen,
    required this.playerKey,
    required this.onToggleFullscreen,
    required this.onPositionChanged,
    required this.onDurationChanged,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);

    if (selectedVideo == null) {
      return Container(
        color: c.surfaceDark,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.video_library_outlined, size: 48, color: c.textMuted),
              const SizedBox(height: 8),
              Text('Chưa chọn video nào', style: TextStyle(color: c.textSecondary, fontSize: 13)),
            ],
          ),
        ),
      );
    }

    if (isPlayerFullscreen) {
      return Container(
        color: c.surfaceDark,
        child: Center(
          child: Text(
            'Đang phát toàn màn hình...',
            style: TextStyle(color: c.textMuted, fontSize: 12),
          ),
        ),
      );
    }

    return Container(
      color: c.surfaceDark,
      child: VideoPlayerWidget(
        key: playerKey,
        videoPath: selectedVideo!.fullPath,
        isFullscreen: false,
        onToggleFullscreen: onToggleFullscreen,
        onPositionChanged: onPositionChanged,
        onDurationChanged: onDurationChanged,
      ),
    );
  }
}
