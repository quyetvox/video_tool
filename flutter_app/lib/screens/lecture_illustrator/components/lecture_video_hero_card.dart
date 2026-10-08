import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../../core/app_colors.dart';
import '../../../../widgets/video_gizmo_toolbar.dart';
import '../../../../widgets/video_player_widget.dart';
import '../controllers/lecture_illustrator_controller.dart';
import '../models/lecture_illustrator_model.dart';

class LectureVideoHeroCard extends ConsumerWidget {
  final LectureIllustratorState state;
  final LectureIllustratorController controller;
  final GlobalKey<VideoPlayerWidgetState>? playerKey;
  final Function(double currentSeconds)? onPositionChanged;

  const LectureVideoHeroCard({
    super.key,
    required this.state,
    required this.controller,
    this.playerKey,
    this.onPositionChanged,
  });

  String _formatDuration(double seconds) {
    final mins = (seconds ~/ 60).toString().padLeft(2, '0');
    final secs = (seconds % 60).toStringAsFixed(1).padLeft(4, '0');
    return '$mins:$secs';
  }

  Widget _buildTextViewer(BuildContext context, String filePath) {
    String content = '';
    try {
      content = File(filePath).readAsStringSync();
    } catch (_) {
      content = 'Không thể đọc nội dung tệp văn bản.';
    }

    final lines = content.split('\n');
    final wordCount = content.trim().isEmpty ? 0 : RegExp(r'\S+').allMatches(content).length;

    return Container(
      color: AppColors.surfaceDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.surfaceLight.withOpacity(0.5),
              border: const Border(bottom: BorderSide(color: AppColors.border, width: 0.5)),
            ),
            child: Row(
              children: [
                const Icon(Icons.description_outlined, size: 14, color: AppColors.primary),
                const SizedBox(width: 6),
                Text(
                  'Xem trước kịch bản (${lines.length} dòng • $wordCount từ)',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: SelectableText(
                content,
                style: const TextStyle(
                  fontSize: 12.5,
                  height: 1.6,
                  color: AppColors.textPrimary,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = AppColors.of(context);
    final renderedVideo = controller.outputVideoPath;
    final hasRendered = renderedVideo != null && File(renderedVideo).existsSync();

    final hasFile = state.videoPath != null &&
        state.videoPath!.isNotEmpty &&
        File(state.videoPath!).existsSync();

    final ext = (state.videoPath != null) ? p.extension(state.videoPath!).toLowerCase() : '';
    final isText = {'.txt', '.md', '.markdown'}.contains(ext);
    final isAudio = {'.wav', '.mp3', '.m4a', '.aac', '.flac'}.contains(ext);

    IconData headerIcon = Icons.video_library_outlined;
    Color headerIconColor = AppColors.primary;
    if (hasRendered) {
      headerIcon = Icons.check_circle_outline;
      headerIconColor = AppColors.statusCompleted;
    } else if (isText) {
      headerIcon = Icons.description_outlined;
      headerIconColor = AppColors.primary;
    } else if (isAudio) {
      headerIcon = Icons.audiotrack_outlined;
      headerIconColor = Colors.orangeAccent;
    }

    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Info Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: c.surfaceLight.withOpacity(0.4),
              border: Border(bottom: BorderSide(color: c.border)),
            ),
            child: Row(
              children: [
                Icon(headerIcon, size: 16, color: headerIconColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    hasRendered
                        ? '${p.basename(renderedVideo)} (Đã xuất bản)'
                        : ((state.videoName != null && state.videoName!.isNotEmpty)
                            ? state.videoName!
                            : 'Xem trước bài giảng'),
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                      color: hasRendered ? AppColors.statusCompleted : c.textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (state.videoDuration > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: c.surface,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: c.border),
                    ),
                    child: Text(
                      _formatDuration(state.videoDuration),
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: c.textSecondary),
                    ),
                  ),
              ],
            ),
          ),

          // 2. Video / Text / Audio View Area
          Expanded(
            child: Container(
              color: Colors.black,
              child: hasRendered
                  ? VideoPlayerWidget(
                      key: playerKey,
                      videoPath: renderedVideo,
                      onPositionChanged: onPositionChanged,
                    )
                  : hasFile
                      ? (isText
                          ? _buildTextViewer(context, state.videoPath!)
                          : VideoPlayerWidget(
                              key: playerKey,
                              videoPath: state.videoPath!,
                              onPositionChanged: onPositionChanged,
                            ))
                      : Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.dashboard_customize_outlined, size: 48, color: c.textMuted),
                              const SizedBox(height: 10),
                              Text(
                                'Chưa chọn tài sản bài giảng',
                                style: TextStyle(color: c.textSecondary, fontSize: 13, fontWeight: FontWeight.w500),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Hỗ trợ Video (.mp4), Âm thanh (.mp3, .wav) hoặc Văn bản (.md, .txt)',
                                style: TextStyle(color: c.textMuted, fontSize: 11),
                              ),
                            ],
                          ),
                        ),
            ),
          ),

          // 3. Gizmo Toolbar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: c.surfaceDark,
              border: Border(top: BorderSide(color: c.border)),
            ),
            child: Row(
              children: [
                const Expanded(child: VideoGizmoToolbar()),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: c.surfaceLight,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: c.border.withOpacity(0.5)),
                  ),
                  child: Text(
                    'Preset: ${state.config.visualLayoutPreset.toUpperCase()}',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: c.primary),
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
