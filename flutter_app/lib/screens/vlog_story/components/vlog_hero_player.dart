import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/app_colors.dart';
import '../../../../widgets/video_gizmo_toolbar.dart';
import '../../../../widgets/video_player_widget.dart';
import '../controllers/vlog_story_controller.dart';

class VlogHeroPlayer extends ConsumerStatefulWidget {
  final VlogStoryState state;
  final VlogStoryController controller;

  const VlogHeroPlayer({
    super.key,
    required this.state,
    required this.controller,
  });

  @override
  ConsumerState<VlogHeroPlayer> createState() => _VlogHeroPlayerState();
}

class _VlogHeroPlayerState extends ConsumerState<VlogHeroPlayer> {
  bool _showOutputVideo = false;

  String _formatDuration(double seconds) {
    final mins = (seconds ~/ 60).toString().padLeft(2, '0');
    final secs = (seconds % 60).toStringAsFixed(1).padLeft(4, '0');
    return '$mins:$secs';
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final state = widget.state;
    final hasVideo = state.videoPath.isNotEmpty && File(state.videoPath).existsSync();
    final hasOutput = state.outputVideoPath != null && File(state.outputVideoPath!).existsSync();

    final activePath = (_showOutputVideo && hasOutput) ? state.outputVideoPath! : state.videoPath;

    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Header Bar: Video Info & Switcher
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: c.surfaceLight.withOpacity(0.4),
              border: Border(bottom: BorderSide(color: c.border)),
            ),
            child: Row(
              children: [
                Icon(
                  _showOutputVideo ? Icons.auto_awesome_rounded : Icons.videocam_rounded,
                  size: 18,
                  color: _showOutputVideo ? AppColors.primaryHover : AppColors.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    state.videoName.isNotEmpty ? state.videoName : 'Chưa chọn video',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (state.duration > 0) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: c.surface,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: c.border),
                    ),
                    child: Text(
                      '⏱️ ${_formatDuration(state.duration)}',
                      style: TextStyle(fontSize: 11, color: c.textMuted),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                if (hasOutput) ...[
                  ChoiceChip(
                    label: const Text('Gốc', style: TextStyle(fontSize: 11)),
                    selected: !_showOutputVideo,
                    onSelected: (val) => setState(() => _showOutputVideo = !val),
                  ),
                  const SizedBox(width: 4),
                  ChoiceChip(
                    label: const Text('Thành Phẩm ✨', style: TextStyle(fontSize: 11)),
                    selected: _showOutputVideo,
                    selectedColor: AppColors.primaryHover.withOpacity(0.3),
                    onSelected: (val) => setState(() => _showOutputVideo = val),
                  ),
                ],
              ],
            ),
          ),

          // 1.5. Gizmo Layer Toolbar
          VideoGizmoToolbar(
            enabled: hasVideo,
          ),

          // 2. Video Player Body
          Expanded(
            child: hasVideo
                ? VideoPlayerWidget(
                    videoPath: activePath,
                    key: ValueKey(activePath),
                  )
                : Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.video_collection_outlined, size: 48, color: c.textMuted.withOpacity(0.5)),
                        const SizedBox(height: 12),
                        Text(
                          'Chọn một video vlog từ Sidebar để bắt đầu kể chuyện',
                          style: TextStyle(color: c.textMuted, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
