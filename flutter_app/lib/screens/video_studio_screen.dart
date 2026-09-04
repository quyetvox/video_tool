import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../core/app_colors.dart';
import '../core/providers.dart';
import '../core/studio_state_notifier.dart';
import '../models/studio_draft.dart';
import '../models/studio_state.dart';
import '../models/video_file.dart';
import '../widgets/video_player_widget.dart';
import '../widgets/multitrack_timeline_widget.dart';
import '../widgets/studio_sidebar_widget.dart';
import '../widgets/studio_canvas_overlay.dart';
import '../widgets/timecode_input_widget.dart';
import '../widgets/history_panel_widget.dart';
import '../core/audio_sync_player.dart';
import '../core/studio_draft_service.dart';
import '../core/studio_export_service.dart';
import '../widgets/studio_keyboard_handler.dart';
import '../utils/time_format_utils.dart';
import '../widgets/app_kit.dart';

class VideoStudioScreen extends ConsumerStatefulWidget {
  const VideoStudioScreen({super.key});

  @override
  ConsumerState<VideoStudioScreen> createState() => _VideoStudioScreenState();
}

class _VideoStudioScreenState extends ConsumerState<VideoStudioScreen> {
  final GlobalKey<VideoPlayerWidgetState> _videoPlayerKey = GlobalKey<VideoPlayerWidgetState>();
  final AudioSyncPlayer _audioSyncPlayer = AudioSyncPlayer();
  double _currentTime = 0.0;
  double _duration = 100.0;
  bool _isSidebarOpen = true;
  bool _isProcessing = false;
  bool _isVideoPlaying = false;
  int _activeMergeIndex = 0;
  bool _overwriteOriginalCut = false;
  double _lastAutoSeekSec = -1.0;

  // Multi-Draft state
  StudioDraft? _activeDraft;
  List<StudioDraft> _availableDrafts = [];
  String _lastLoadedVideoStem = '';

  // Active right tab: 'props' | 'sub' | 'overlay' | 'audio' | 'info'
  String _activeRightTab = 'props';

  // Export settings
  late final TextEditingController _exportFilenameController;
  String _lastAutoExportStem = '';
  StudioToolMode? _lastAutoToolMode;
  String _exportResolution = 'Giữ nguyên (1920x1080)';
  String _exportFps = '30 fps';
  String _exportRatio = '16:9 (Ngang)';
  String _exportBitrate = 'Cao (4.0M HD Sắc Nét)';

  @override
  void initState() {
    super.initState();
    _exportFilenameController = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final projectsDir = ref.read(projectsDirProvider);
      final activeProject = ref.read(activeProjectProvider);
      final projectDir = activeProject != null ? '$projectsDir/$activeProject' : projectsDir;
      _refreshDrafts(projectDir);
    });
  }

  @override
  void dispose() {
    _exportFilenameController.dispose();
    _audioSyncPlayer.dispose();
    super.dispose();
  }

  String _getDefaultExportFilename(StudioToolMode mode, VideoFile? video, List<MergeItem> mergePlaylist) {
    if (mode == StudioToolMode.composite) {
      return video != null ? '${video.stem}_edited.mp4' : 'studio_edited.mp4';
    } else if (mode == StudioToolMode.merge) {
      if (mergePlaylist.isNotEmpty) {
        final firstStem = p.basenameWithoutExtension(mergePlaylist.first.fullPath);
        return '${firstStem}_merged.mp4';
      }
      return 'merged_${DateTime.now().millisecondsSinceEpoch}.mp4';
    } else if (mode == StudioToolMode.cut) {
      return video != null ? '${video.stem}_cut.mp4' : 'video_cut.mp4';
    } else if (mode == StudioToolMode.split) {
      return video != null ? 'part_01_${video.stem}.mp4' : 'part_01_video.mp4';
    }
    return 'output.mp4';
  }

  Future<void> _refreshDrafts(String projectDir) async {
    if (projectDir.isEmpty) return;
    final list = await StudioDraftService.listProjectDrafts(projectDir);
    if (mounted) {
      setState(() {
        _availableDrafts = list;
        if (_activeDraft != null && !list.any((d) => d.id == _activeDraft!.id)) {
          _activeDraft = null;
        }
      });
    }
  }

  void _saveCurrentDraft(BuildContext context, String projectDir, VideoFile video, StudioSnapshot state, StudioToolMode mode) async {
    final c = AppColors.of(context);
    final nameController = TextEditingController(text: _activeDraft?.name ?? 'Bản nháp ${_availableDrafts.length + 1}');
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: c.border),
        ),
        title: Row(
          children: [
            Icon(Icons.save_as_rounded, color: c.info, size: 20),
            const SizedBox(width: 8),
            Text('Lưu bản nháp studio', style: TextStyle(color: c.textPrimary, fontSize: 13, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppTextField(
              controller: nameController,
              autofocus: true,
              label: 'Đặt tên để phân biệt phiên bản biên tập này:',
              hint: 'Ví dụ: Bản TikTok 60s, Bản Sub tiếng Anh...',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: Text('Huỷ', style: TextStyle(color: c.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: c.primary,
              foregroundColor: c.primaryText,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            ),
            onPressed: () {
              final val = nameController.text.trim();
              Navigator.pop(ctx, val.isNotEmpty ? val : 'Bản nháp ${_availableDrafts.length + 1}');
            },
            child: const Text('Lưu bản nháp', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      final draftId = _activeDraft?.name == result
          ? _activeDraft!.id
          : 'draft_${DateTime.now().millisecondsSinceEpoch}';
      final draft = StudioDraft(
        id: draftId,
        name: result,
        videoPath: video.fullPath,
        videoStem: video.stem,
        updatedAt: DateTime.now(),
        toolMode: mode,
        snapshot: state,
      );
      final ok = await StudioDraftService.saveDraft(projectDir, draft);
      if (ok) {
        if (mounted) {
          setState(() => _activeDraft = draft);
        }
        await _refreshDrafts(projectDir);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Đã lưu bản nháp "$result" thành công!'),
              backgroundColor: c.statusCompleted,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    }
  }

  void _showDraftsMenu(BuildContext context, String projectDir, VideoFile? currentVideo, StudioStateNotifier notifier) {
    final c = AppColors.of(context);
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Dialog(
          backgroundColor: c.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: c.border, width: 1.2),
          ),
          child: Container(
            width: 640,
            constraints: const BoxConstraints(maxHeight: 520),
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    Icon(Icons.folder_copy_outlined, color: c.primary, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Quản lý bản nháp dự án (${_availableDrafts.length})',
                      style: TextStyle(color: c.textPrimary, fontSize: 13.5, fontWeight: FontWeight.bold),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: Icon(Icons.close, size: 18, color: c.textSecondary),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                Divider(color: c.border, height: 20),

                // Content List
                if (_availableDrafts.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(32),
                    alignment: Alignment.center,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.inventory_2_outlined, size: 42, color: c.textMuted),
                        const SizedBox(height: 10),
                        Text('Chưa có bản nháp nào được lưu trong dự án này.', style: TextStyle(color: c.textSecondary, fontSize: 12.5)),
                        const SizedBox(height: 5),
                        Text('Bấm "Lưu nháp" ở thanh trên cùng để lưu lại cấu hình các layer hiện tại.', style: TextStyle(color: c.textMuted, fontSize: 11)),
                      ],
                    ),
                  )
                else
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: _availableDrafts.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, idx) {
                        final draft = _availableDrafts[idx];
                        final isCurrent = _activeDraft?.id == draft.id;
                        final dateStr = '${draft.updatedAt.hour.toString().padLeft(2, '0')}:${draft.updatedAt.minute.toString().padLeft(2, '0')} • ${draft.updatedAt.day}/${draft.updatedAt.month}/${draft.updatedAt.year}';
                        final videoName = draft.videoPath.isNotEmpty ? p.basename(draft.videoPath) : draft.videoStem;

                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: isCurrent ? c.surfaceLight : c.surfaceDark,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isCurrent ? c.primary : c.border,
                              width: isCurrent ? 1.5 : 1.0,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                isCurrent ? Icons.check_circle_rounded : Icons.description_outlined,
                                color: isCurrent ? c.primary : c.info,
                                size: 22,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          draft.name,
                                          style: TextStyle(
                                            color: isCurrent ? const Color(0xFFFACC15) : Colors.white,
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF334155),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            draft.toolMode.name.toUpperCase(),
                                            style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 9, fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '🎬 Video: $videoName',
                                      style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10.5),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '🕒 $dateStr  •  🖼️ ${draft.overlayCount} ảnh  •  🎵 ${draft.audioCount} nhạc/sfx  •  📝 ${draft.subtitleCount} sub',
                                      style: const TextStyle(color: Color(0xFF64748B), fontSize: 10),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: isCurrent ? const Color(0xFFFACC15) : const Color(0xFF38BDF8),
                                  foregroundColor: Colors.black,
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                ),
                                onPressed: isCurrent
                                    ? null
                                    : () async {
                                        // 1. Tự động nạp đúng video của bản nháp
                                        if (draft.videoPath.isNotEmpty && File(draft.videoPath).existsSync()) {
                                          final fileObj = File(draft.videoPath);
                                          final stat = fileObj.statSync();
                                          final bname = p.basename(draft.videoPath);
                                          VideoCategory cat = VideoCategory.src;
                                          if (draft.videoPath.contains('/cut/')) {
                                            cat = VideoCategory.cut;
                                          } else if (draft.videoPath.contains('/merge/')) {
                                            cat = VideoCategory.merge;
                                          } else if (draft.videoPath.contains('/output/')) {
                                            cat = VideoCategory.output;
                                          }

                                          final targetVideo = VideoFile(
                                            name: bname,
                                            basename: bname,
                                            relPath: draft.videoPath,
                                            fullPath: draft.videoPath,
                                            sizeBytes: stat.size,
                                            mtime: stat.modified.millisecondsSinceEpoch / 1000.0,
                                            category: cat,
                                          );
                                          ref.read(selectedVideoProvider.notifier).state = targetVideo;
                                          _videoPlayerKey.currentState?.loadVideo(targetVideo.fullPath);
                                        }

                                        // 2. Nạp snapshot layers
                                        setState(() => _activeDraft = draft);
                                        notifier.loadSnapshot(draft.snapshot, draftName: draft.name);
                                        ref.read(studioToolModeProvider.notifier).state = draft.toolMode;
                                        Navigator.pop(ctx);

                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              content: Text('Đã nạp bản nháp "${draft.name}" thành công!'),
                                              backgroundColor: const Color(0xFF10B981),
                                              duration: const Duration(seconds: 2),
                                            ),
                                          );
                                        }
                                      },
                                child: Text(
                                  isCurrent ? 'Đang mở' : 'Mở bản này',
                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                ),
                              ),
                              const SizedBox(width: 4),
                              IconButton(
                                icon: const Icon(Icons.delete_outline, size: 18, color: Color(0xFFEF4444)),
                                tooltip: 'Xoá bản nháp',
                                onPressed: () async {
                                  final ok = await StudioDraftService.deleteDraft(projectDir, draft.videoStem, draft.id);
                                  if (ok) {
                                    await _refreshDrafts(projectDir);
                                    setModalState(() {});
                                  }
                                },
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),

                const SizedBox(height: 14),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF38BDF8),
                    side: const BorderSide(color: Color(0xFF38BDF8)),
                    minimumSize: const Size.fromHeight(38),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Tạo bản nháp mới từ đầu (Trống)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  onPressed: () {
                    setState(() => _activeDraft = null);
                    notifier.resetToEmpty();
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Đã tạo bản nháp mới (Trống)!'), duration: Duration(seconds: 1)),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<double> _getMergeOffsets(List<MergeItem> playlist) {
    final offsets = <double>[];
    double acc = 0.0;
    for (final item in playlist) {
      offsets.add(acc);
      acc += (item.duration > 0 ? item.duration : 10.0);
    }
    return offsets;
  }

  double _getMergeTotalDuration(List<MergeItem> playlist) {
    if (playlist.isEmpty) return 10.0;
    return playlist.fold<double>(0.0, (acc, item) => acc + (item.duration > 0 ? item.duration : 10.0));
  }

  void _handlePositionChanged(double sec, StudioToolMode mode, StudioSnapshot state) {
    if (mode == StudioToolMode.merge && state.mergePlaylist.isNotEmpty) {
      final safeIdx = _activeMergeIndex.clamp(0, state.mergePlaylist.length - 1);
      final offsets = _getMergeOffsets(state.mergePlaylist);
      final startOffset = safeIdx < offsets.length ? offsets[safeIdx] : 0.0;
      final globalSec = startOffset + sec;
      setState(() => _currentTime = globalSec);
      return;
    }

    setState(() => _currentTime = sec);

    // Only sync multi-track audio playback when in composite mode
    if (mode == StudioToolMode.composite) {
      _audioSyncPlayer.updateClips(state.audioClips);
      _audioSyncPlayer.updateMixState(state.mixState);
      _audioSyncPlayer.syncPosition(sec, _isVideoPlaying);
    } else {
      _audioSyncPlayer.pause();
    }

    // Seamless CUT mode playback: auto-skip junk slices
    if (mode == StudioToolMode.cut && state.cutSegments.isNotEmpty) {
      for (final cut in state.cutSegments) {
        if (sec >= cut.start && sec < cut.end) {
          if ((_lastAutoSeekSec - cut.end).abs() > 0.3) {
            _lastAutoSeekSec = cut.end;
            _videoPlayerKey.currentState?.seekTo(cut.end);
          }
          return;
        }
      }
    }
  }

  void _handleVideoCompleted(StudioToolMode mode, StudioSnapshot state) {
    if (mode == StudioToolMode.merge && state.mergePlaylist.isNotEmpty) {
      if (_activeMergeIndex + 1 < state.mergePlaylist.length) {
        setState(() {
          _activeMergeIndex++;
        });
        final nextItem = state.mergePlaylist[_activeMergeIndex];
        _videoPlayerKey.currentState?.loadVideo(nextItem.fullPath, autoPlay: true);
      } else {
        // Loop back to start
        setState(() {
          _activeMergeIndex = 0;
          _currentTime = 0.0;
        });
        final firstItem = state.mergePlaylist[0];
        _videoPlayerKey.currentState?.loadVideo(firstItem.fullPath, autoPlay: false);
      }
    }
  }

  void _handleSeek(double targetSec, StudioToolMode mode, StudioSnapshot state) {
    if (mode == StudioToolMode.merge && state.mergePlaylist.isNotEmpty) {
      final offsets = _getMergeOffsets(state.mergePlaylist);
      int targetIdx = 0;
      for (int i = state.mergePlaylist.length - 1; i >= 0; i--) {
        if (targetSec >= offsets[i]) {
          targetIdx = i;
          break;
        }
      }
      final localSec = (targetSec - offsets[targetIdx]).clamp(0.0, state.mergePlaylist[targetIdx].duration);
      if (targetIdx != _activeMergeIndex) {
        setState(() {
          _activeMergeIndex = targetIdx;
          _currentTime = targetSec;
        });
        _videoPlayerKey.currentState?.loadVideo(
          state.mergePlaylist[targetIdx].fullPath,
          autoPlay: _isVideoPlaying,
          seekSeconds: localSec,
        );
      } else {
        setState(() => _currentTime = targetSec);
        _videoPlayerKey.currentState?.seekTo(localSec);
      }
      return;
    }

    setState(() => _currentTime = targetSec);
    _videoPlayerKey.currentState?.seekTo(targetSec);
    if (mode == StudioToolMode.composite) {
      _audioSyncPlayer.seek(targetSec);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedVideo = ref.watch(selectedVideoProvider);
    final toolMode = ref.watch(studioToolModeProvider);
    final studioState = ref.watch(studioStateProvider);
    final studioNotifier = ref.read(studioStateProvider.notifier);
    final projectsDir = ref.watch(projectsDirProvider);
    final activeProject = ref.watch(activeProjectProvider);
    final projectDir = activeProject != null ? '$projectsDir/$activeProject' : projectsDir;

    if (selectedVideo != null && selectedVideo.stem != _lastLoadedVideoStem) {
      _lastLoadedVideoStem = selectedVideo.stem;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _refreshDrafts(projectDir);
      });
    }

    final currentStem = selectedVideo?.stem ?? '';
    if (currentStem != _lastAutoExportStem || toolMode != _lastAutoToolMode) {
      _lastAutoExportStem = currentStem;
      _lastAutoToolMode = toolMode;
      _exportFilenameController.text = _getDefaultExportFilename(toolMode, selectedVideo, studioState.mergePlaylist);
    }

    final c = AppColors.of(context);

    return StudioKeyboardHandler(
      onTogglePlay: () => _videoPlayerKey.currentState?.togglePlay(),
      onDeleteSelected: () => studioNotifier.deleteSelectedItem(),
      child: Scaffold(
        backgroundColor: c.background,
        body: Column(
          children: [
            // ── 1. Top Bar Header ───────────────────────────────────────────
            Container(
              height: 42,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: c.surface,
                border: Border(bottom: BorderSide(color: c.border)),
              ),
              child: Row(
                children: [
                  Text('Video Studio', style: TextStyle(color: c.textPrimary, fontSize: 12, fontWeight: FontWeight.w600)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Text('›', style: TextStyle(color: c.textMuted, fontSize: 12)),
                  ),
                  Text('Biên tập & Ghép nối', style: TextStyle(color: c.textSecondary, fontSize: 11.5)),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6),
                    child: Text('›', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                  ),
                  Text(
                    toolMode == StudioToolMode.cut
                        ? 'Cắt bỏ rác (Cut)'
                        : (toolMode == StudioToolMode.split
                            ? 'Chia clip (Split)'
                            : (toolMode == StudioToolMode.merge ? 'Ghép video (Merge)' : 'Biên tập đa lớp')),
                    style: TextStyle(
                      color: toolMode == StudioToolMode.cut ? AppColors.statusFailed : AppColors.primary,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),

                  const SizedBox(width: 16),

                  // Active Video Switcher pill
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(color: AppColors.primary.withOpacity(0.35)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.movie_outlined, size: 12, color: AppColors.primary),
                        const SizedBox(width: 6),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 160),
                          child: Text(
                            selectedVideo?.basename ?? 'Chọn video từ sidebar',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const Spacer(),

                  // Undo / Redo using AppIconButton
                  AppIconButton(
                    icon: Icons.undo,
                    color: studioNotifier.canUndo ? c.textPrimary : c.textMuted,
                    tooltip: 'Hoàn tác (Ctrl+Z)',
                    onPressed: studioNotifier.canUndo ? () => studioNotifier.undo() : null,
                  ),
                  const SizedBox(width: 2),
                  AppIconButton(
                    icon: Icons.redo,
                    color: studioNotifier.canRedo ? c.textPrimary : c.textMuted,
                    tooltip: 'Làm lại (Ctrl+Shift+Z)',
                    onPressed: studioNotifier.canRedo ? () => studioNotifier.redo() : null,
                  ),

                  const SizedBox(width: 8),

                  // 💾 Save Draft Button using AppButton.outlined
                  AppButton.outlined(
                    icon: Icons.save_outlined,
                    label: _activeDraft != null ? '💾 Lưu (${_activeDraft!.name})' : 'Lưu nháp',
                    fontSize: 10.5,
                    onPressed: selectedVideo != null
                        ? () => _saveCurrentDraft(context, projectDir, selectedVideo, studioState, toolMode)
                        : null,
                  ),
                  const SizedBox(width: 6),

                  // 📂 Drafts Switcher Button using AppButton.secondary / outlined
                  AppButton(
                    variant: _availableDrafts.isNotEmpty ? AppButtonVariant.secondary : AppButtonVariant.outlined,
                    icon: Icons.folder_open_rounded,
                    label: 'Bản nháp (${_availableDrafts.length}) ▾',
                    fontSize: 10.5,
                    onPressed: projectDir.isNotEmpty
                        ? () => _showDraftsMenu(context, projectDir, selectedVideo, studioNotifier)
                        : null,
                  ),
                  const SizedBox(width: 8),

                  // Master Export CTA Button using AppButton.primary
                  AppButton.primary(
                    icon: Icons.download,
                    isLoading: _isProcessing,
                    label: _isProcessing
                        ? 'Đang Xử Lý...'
                        : (toolMode == StudioToolMode.cut
                            ? 'Cắt bỏ rác & Xuất'
                            : (toolMode == StudioToolMode.split
                                ? 'Xuất các đoạn chia'
                                : (toolMode == StudioToolMode.composite ? 'Xuất Video Đa Lớp' : 'Ghép & Xuất video'))),
                    fontSize: 11.0,
                    onPressed: _isProcessing ? null : () => _executeMasterExport(selectedVideo, toolMode, studioState),
                  ),
                ],
              ),
            ),

            // ── 2. Middle Body: Left Sidebar + Upper Canvas (Player+Tools+Right) ──
            Expanded(
              flex: 55,
              child: Row(
                children: [
                  // Left Sidebar Panel (Collapsible 320px)
                  if (_isSidebarOpen)
                    StudioSidebarWidget(
                      width: 320,
                      onCollapse: () => setState(() => _isSidebarOpen = false),
                    ),

                  // Expand Sidebar Toggle Button (if closed)
                  if (!_isSidebarOpen)
                    InkWell(
                      onTap: () => setState(() => _isSidebarOpen = true),
                      child: Container(
                        width: 20,
                        color: AppColors.surface,
                        child: const Center(
                          child: Icon(Icons.chevron_right, size: 16, color: AppColors.textSecondary),
                        ),
                      ),
                    ),

                  // Column 1: Video Player with Interactive Canvas Overlay (60%)
                  Expanded(
                    flex: 60,
                    child: Container(
                      decoration: const BoxDecoration(
                        color: AppColors.surfaceDark,
                        border: Border(
                          right: BorderSide(color: AppColors.border),
                          bottom: BorderSide(color: AppColors.border),
                        ),
                      ),
                      child: (selectedVideo != null || (toolMode == StudioToolMode.merge && studioState.mergePlaylist.isNotEmpty))
                          ? VideoPlayerWidget(
                              key: _videoPlayerKey,
                              videoPath: (toolMode == StudioToolMode.merge && studioState.mergePlaylist.isNotEmpty)
                                  ? studioState.mergePlaylist[_activeMergeIndex.clamp(0, studioState.mergePlaylist.length - 1)].fullPath
                                  : (selectedVideo?.fullPath ?? ''),
                              volume: studioState.mixState.origVolume.toDouble(),
                              isMuted: studioState.mixState.origMuted,
                              onPositionChanged: (sec) => _handlePositionChanged(sec, toolMode, studioState),
                              onDurationChanged: (dur) {
                                if (toolMode != StudioToolMode.merge) {
                                  setState(() => _duration = dur);
                                }
                              },
                              onPlayingChanged: (playing) {
                                setState(() => _isVideoPlaying = playing);
                                if (toolMode == StudioToolMode.composite) {
                                  _audioSyncPlayer.syncPosition(_currentTime, playing);
                                }
                              },
                              onCompleted: () => _handleVideoCompleted(toolMode, studioState),
                              overlayWidget: StudioCanvasOverlay(
                                currentSeconds: _currentTime,
                              ),
                            )
                          : const Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.movie_filter_outlined, size: 36, color: AppColors.textMuted),
                                  SizedBox(height: 8),
                                  Text('Chưa có video nào được chọn', style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
                                  SizedBox(height: 4),
                                  Text('Chọn một video từ sidebar bên trái để bắt đầu', style: TextStyle(color: AppColors.textMuted, fontSize: 10.5)),
                                ],
                              ),
                            ),
                    ),
                  ),

                  // Column 2: Center Tools Panel (20%)
                  Expanded(
                    flex: 20,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: c.surface,
                        border: Border(
                          right: BorderSide(color: c.border),
                          bottom: BorderSide(color: c.border),
                        ),
                      ),
                      child: _buildCenterToolsPanel(toolMode, studioState, studioNotifier),
                    ),
                  ),

                  // Column 3: Right Panel: History (top) + 5 Properties Tabs (bottom) (20%)
                  Expanded(
                    flex: 20,
                    child: Container(
                      decoration: BoxDecoration(
                        color: c.surface,
                      ),
                      child: Column(
                        children: [
                          // Upper History Panel (35% height)
                          const Expanded(
                            flex: 35,
                            child: HistoryPanelWidget(),
                          ),

                          // Lower Properties 5 Tabs (65% height)
                          Expanded(
                            flex: 65,
                            child: _buildRightPropertiesPanel(studioState, studioNotifier, selectedVideo, toolMode),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── 3. Lower Multitrack Timeline Canvas (45%) ──────────────────
            Expanded(
              flex: 45,
              child: MultitrackTimelineWidget(
                duration: (toolMode == StudioToolMode.merge && studioState.mergePlaylist.isNotEmpty)
                    ? _getMergeTotalDuration(studioState.mergePlaylist)
                    : _duration,
                currentTime: _currentTime,
                onSeek: (sec) => _handleSeek(sec, toolMode, studioState),
              ),
            ),

            // ── 4. Audio Mixer Footer Bar (Auto-hidden in MERGE mode) ───────
            if (toolMode != StudioToolMode.merge) _buildAudioMixerBar(studioState, studioNotifier),
          ],
        ),
      ),
    );
  }

  // ── Center Tools Panel: CUT | SPLIT | MERGE | COMPOSITE ───────────────────
  Widget _buildCenterToolsPanel(
    StudioToolMode mode,
    StudioSnapshot state,
    StudioStateNotifier notifier,
  ) {
    final c = AppColors.of(context);
    switch (mode) {
      case StudioToolMode.cut:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '✂️ Chọn đoạn rác:',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: c.statusFailed, fontSize: 10.5, fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(width: 4),
                InkWell(
                  onTap: () => notifier.toggleCutBoxVisible(),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: state.showCutBox ? c.statusFailedBg : c.surfaceDark,
                      border: Border.all(color: state.showCutBox ? c.statusFailed.withOpacity(0.5) : c.border),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      children: [
                        Icon(state.showCutBox ? Icons.visibility : Icons.visibility_off, size: 10.5, color: state.showCutBox ? c.statusFailed : c.textMuted),
                        const SizedBox(width: 3),
                        Text(state.showCutBox ? 'Đang hiện' : 'Đã ẩn', style: TextStyle(color: state.showCutBox ? c.statusFailed : c.textMuted, fontSize: 9.5)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),

            // Quick Preset Buttons
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: c.surfaceDark,
                      foregroundColor: c.primary,
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
                      minimumSize: Size.zero,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4), side: BorderSide(color: c.border, width: 0.6)),
                    ),
                    icon: const Icon(Icons.location_on, size: 10),
                    label: const Text('10s tại Playhead', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w500)),
                    onPressed: () => notifier.setCutRange(_currentTime, (_currentTime + 10.0).clamp(0.0, _duration)),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: c.surfaceDark,
                      foregroundColor: c.primary,
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
                      minimumSize: Size.zero,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4), side: BorderSide(color: c.border, width: 0.6)),
                    ),
                    icon: const Icon(Icons.timer, size: 10),
                    label: const Text('10s đầu', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w500)),
                    onPressed: () => notifier.setCutRange(0.0, 10.0.clamp(0.0, _duration)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),

            // Timecode Inputs
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Bắt đầu:', style: TextStyle(color: c.textSecondary, fontSize: 9.5)),
                      const SizedBox(height: 2),
                      TimecodeInputWidget(
                        value: state.currentJunkStart,
                        maxValue: _duration,
                        onChanged: (val) => notifier.setCutRange(val, state.currentJunkEnd),
                        onSetFromPlayhead: () => notifier.setCutRange(_currentTime, state.currentJunkEnd),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Kết thúc:', style: TextStyle(color: c.textSecondary, fontSize: 9.5)),
                      const SizedBox(height: 2),
                      TimecodeInputWidget(
                        value: state.currentJunkEnd,
                        maxValue: _duration,
                        onChanged: (val) => notifier.setCutRange(state.currentJunkStart, val),
                        onSetFromPlayhead: () => notifier.setCutRange(state.currentJunkStart, _currentTime),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),

            AppActionButton(
              icon: Icons.add,
              label: '+ Thêm đoạn rác này',
              color: c.primary,
              isFullWidth: true,
              fontSize: 10.5,
              onPressed: () => notifier.addCutSegment(state.currentJunkStart, state.currentJunkEnd),
            ),
            const SizedBox(height: 6),

            Text('Danh sách đoạn rác (${state.cutSegments.length})', style: TextStyle(color: c.textSecondary, fontSize: 10, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),

            Expanded(
              child: state.cutSegments.isEmpty
                  ? Center(
                      child: Text('Chưa thêm đoạn rác nào', style: TextStyle(color: c.textMuted, fontSize: 10)),
                    )
                  : ListView.builder(
                      itemCount: state.cutSegments.length,
                      itemBuilder: (ctx, idx) {
                        final seg = state.cutSegments[idx];
                        return Container(
                          margin: const EdgeInsets.only(bottom: 3),
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                          decoration: BoxDecoration(
                            color: c.surfaceDark,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: c.border, width: 0.5),
                          ),
                          child: Row(
                            children: [
                              Text('${idx + 1}.', style: TextStyle(color: c.statusFailed, fontSize: 10, fontWeight: FontWeight.bold)),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  '${TimeFormatUtils.formatSubtitleTime(seg.start)} ➔ ${TimeFormatUtils.formatSubtitleTime(seg.end)}',
                                  style: TextStyle(fontFamily: 'monospace', color: c.textPrimary, fontSize: 9.5),
                                ),
                              ),
                              AppIconButton(
                                icon: Icons.close,
                                size: 11,
                                buttonSize: 20,
                                color: c.textMuted,
                                onPressed: () => notifier.removeCutSegment(seg.id),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 4),

            // Overwrite Original Checkbox
            AppCheckboxRow(
              value: _overwriteOriginalCut,
              activeColor: c.statusFailed,
              label: _overwriteOriginalCut ? 'Ghi đè file gốc src/' : 'Lưu vào cut/ (Giữ video gốc)',
              labelStyle: TextStyle(
                color: _overwriteOriginalCut ? c.statusFailed : c.statusCompleted,
                fontSize: 9.5,
                fontWeight: FontWeight.w500,
              ),
              onChanged: (val) => setState(() => _overwriteOriginalCut = val ?? false),
            ),
          ],
        );

      case StudioToolMode.split:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('🔀 Chia clip tại vị trí con trỏ Playhead:', style: TextStyle(color: c.primary, fontSize: 11.5, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: c.surfaceDark,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: c.border),
              ),
              child: Row(
                children: [
                  Text('Vị trí chia: ', style: TextStyle(color: c.textSecondary, fontSize: 11)),
                  Text(
                    TimeFormatUtils.formatSubtitleTime(_currentTime),
                    style: TextStyle(fontFamily: 'monospace', color: c.textPrimary, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            AppButton.primary(
              icon: Icons.splitscreen,
              label: 'Chia đôi clip tại đây (Lưu vào cut/)',
              width: double.infinity,
              height: 30,
              fontSize: 11,
              onPressed: () => notifier.addSplitAt(_currentTime, _duration),
            ),
            const SizedBox(height: 10),

            Text('Các phân đoạn đã chia (${state.splitSegments.length})', style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),

            Expanded(
              child: state.splitSegments.isEmpty
                  ? Center(
                      child: Text('Chưa có điểm chia nào. Đặt Playhead và bấm Chia đôi clip.', style: TextStyle(color: c.textMuted, fontSize: 11)),
                    )
                  : ListView.builder(
                      itemCount: state.splitSegments.length,
                      itemBuilder: (ctx, idx) {
                        final seg = state.splitSegments[idx];
                        return Container(
                          margin: const EdgeInsets.only(bottom: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: c.surfaceDark,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: c.border),
                          ),
                          child: Row(
                            children: [
                              Text(seg.name, style: TextStyle(color: c.info, fontSize: 11, fontWeight: FontWeight.bold)),
                              const SizedBox(width: 8),
                              Text('${TimeFormatUtils.formatSubtitleTime(seg.start)} - ${TimeFormatUtils.formatSubtitleTime(seg.end)}', style: TextStyle(color: c.textSecondary, fontSize: 10.5)),
                              const Spacer(),
                              AppIconButton(
                                icon: Icons.close,
                                size: 12,
                                buttonSize: 20,
                                color: c.textMuted,
                                onPressed: () => notifier.removeSplitSegment(seg.id),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        );

      case StudioToolMode.merge:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('🥞 Danh sách video cần ghép (${state.mergePlaylist.length} file):', style: TextStyle(color: c.statusCompleted, fontSize: 12, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text('💡 Click video ở sidebar bên trái để thêm vào danh sách ghép (Lưu vào merge/)', style: TextStyle(color: c.textMuted, fontSize: 10.5)),
            const SizedBox(height: 8),

            Expanded(
              child: state.mergePlaylist.isEmpty
                  ? Center(
                      child: Text('Danh sách ghép đang trống', style: TextStyle(color: c.textMuted, fontSize: 11)),
                    )
                  : ReorderableListView.builder(
                      buildDefaultDragHandles: false,
                      itemCount: state.mergePlaylist.length,
                      onReorder: (oldIdx, newIdx) => notifier.reorderMergeItem(oldIdx, newIdx),
                      itemBuilder: (ctx, idx) {
                        final item = state.mergePlaylist[idx];
                        return Container(
                          key: ValueKey(item.id),
                          margin: const EdgeInsets.only(bottom: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: c.surfaceDark,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: c.border),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 20,
                                height: 20,
                                decoration: BoxDecoration(
                                  color: c.statusCompleted.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                child: Center(
                                  child: Text('${idx + 1}', style: TextStyle(color: c.statusCompleted, fontSize: 10, fontWeight: FontWeight.bold)),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  item.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: c.textPrimary, fontSize: 11),
                                ),
                              ),
                              IconButton(
                                icon: Icon(Icons.close, size: 13, color: c.textMuted),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                tooltip: 'Bỏ video',
                                onPressed: () => notifier.removeMergeItem(item.id),
                              ),
                              const SizedBox(width: 6),
                              ReorderableDragStartListener(
                                index: idx,
                                child: MouseRegion(
                                  cursor: SystemMouseCursors.grab,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                    child: Icon(Icons.drag_handle, size: 15, color: c.textSecondary),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        );

      case StudioToolMode.composite:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('🎬 Biên Tập & Xuất Bản Đa Lớp:', style: TextStyle(color: c.primary, fontSize: 12, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text('💡 Phối trộn Video + Lớp phủ ảnh + Nhạc nền + SFX + Subtitles thành một video hoàn chỉnh.', style: TextStyle(color: c.textSecondary, fontSize: 10.5)),
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
                  Text('• Track Lớp Phủ: ${state.overlayTracks.length} track (${state.overlayClips.length} ảnh)', style: TextStyle(color: c.info, fontSize: 11)),
                  const SizedBox(height: 4),
                  Text('• Track Nhạc Nền: ${state.audioClips.where((a) => a.trackId == 'music').length} clip', style: TextStyle(color: c.statusCompleted, fontSize: 11)),
                  const SizedBox(height: 4),
                  Text('• Track Hiệu Ứng: ${state.audioClips.where((a) => a.trackId == 'sfx').length} clip', style: TextStyle(color: c.info, fontSize: 11)),
                  const SizedBox(height: 4),
                  Text('• Phụ Đề: ${state.subtitles.length} câu', style: TextStyle(color: c.primary, fontSize: 11)),
                ],
              ),
            ),
            const SizedBox(height: 10),
            const Spacer(),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: c.primary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: c.primary.withOpacity(0.35)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 14, color: c.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Bấm nút "Xuất video" ở góc phải để render bản phối đa lớp vào output/.',
                      style: TextStyle(color: c.primary, fontSize: 10),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
    }
  }

  // ── Right Properties Panel: 5 Tabs ─────────────────────────────────────────
  Widget _buildRightPropertiesPanel(
    StudioSnapshot state,
    StudioStateNotifier notifier,
    VideoFile? video,
    StudioToolMode toolMode,
  ) {
    final c = AppColors.of(context);
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
      ),
      child: Column(
        children: [
          // 5 Tab Selector Header
          Container(
            height: 28,
            decoration: BoxDecoration(
              color: c.surfaceDark,
              border: Border(bottom: BorderSide(color: c.border)),
            ),
            child: Row(
              children: [
                _buildPropsTab('props', 'Thuộc tính'),
                _buildPropsTab('sub', 'Sub (Font/Size)'),
                _buildPropsTab('overlay', 'Lớp phủ'),
                _buildPropsTab('audio', 'Âm thanh'),
                _buildPropsTab('info', 'Info'),
              ],
            ),
          ),

          // Tab Content Scroll
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: ListView(
                children: [
                  if (_activeRightTab == 'props') ...[
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
                              controller: _exportFilenameController,
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
                            onPressed: () {
                              setState(() {
                                _exportFilenameController.text = _getDefaultExportFilename(toolMode, video, state.mergePlaylist);
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Audio Live Sync Card
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
                          Text('🔊 Âm Thanh Xuất (Live Sync):', style: TextStyle(color: c.primary, fontSize: 10, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 4),
                          _buildAudioSyncRow('📹 Video gốc', state.mixState.origMuted, () => notifier.toggleMuteVideo()),
                          _buildAudioSyncRow('🎵 Nhạc nền', state.mixState.musicMuted, () => notifier.toggleMuteMusic()),
                          _buildAudioSyncRow('🎤 Hiệu ứng', state.mixState.sfxMuted, () => notifier.toggleMuteSfx()),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),

                    Text('Độ phân giải:', style: TextStyle(color: c.textSecondary, fontSize: 10)),
                    DropdownButton<String>(
                      value: _exportResolution,
                      isExpanded: true,
                      dropdownColor: c.surface,
                      style: TextStyle(color: c.textPrimary, fontSize: 10.5),
                      items: ['Giữ nguyên (1920x1080)', '1080x1920 (Dọc 9:16)', '1280x720'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                      onChanged: (v) => setState(() => _exportResolution = v!),
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
                                value: _exportFps,
                                isExpanded: true,
                                dropdownColor: c.surface,
                                style: TextStyle(color: c.textPrimary, fontSize: 10.5),
                                items: ['30 fps', '60 fps', '24 fps'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                                onChanged: (v) => setState(() => _exportFps = v!),
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
                                value: _exportRatio,
                                isExpanded: true,
                                dropdownColor: c.surface,
                                style: TextStyle(color: c.textPrimary, fontSize: 10.5),
                                items: ['16:9 (Ngang)', '9:16 (Dọc TikTok)', '1:1 (Vuông)'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                                onChanged: (v) => setState(() => _exportRatio = v!),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    const Text('Chất lượng:', style: TextStyle(color: AppColors.textSecondary, fontSize: 10)),
                    DropdownButton<String>(
                      value: _exportBitrate,
                      isExpanded: true,
                      dropdownColor: AppColors.surfaceLight,
                      style: const TextStyle(color: Colors.white, fontSize: 10.5),
                      items: ['Cao (4.0M HD Sắc Nét)', 'Trung bình (2.5M)', 'Tiết kiệm (1.5M)'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                      onChanged: (v) => setState(() => _exportBitrate = v!),
                    ),
                  ],

                  if (_activeRightTab == 'sub') ...[
                    // Active Subtitle Text Editor
                    Builder(
                      builder: (context) {
                        final selectedSub = state.subtitles.where((s) => s.id == state.selectedClipId).firstOrNull ??
                            state.subtitles.where((s) => _currentTime >= s.start && _currentTime <= s.end).firstOrNull;

                        if (selectedSub != null) {
                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: c.surfaceDark,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: c.primary.withOpacity(0.4)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text('📝 Chỉnh sửa câu phụ đề:', style: TextStyle(color: c.primary, fontSize: 10.5, fontWeight: FontWeight.bold)),
                                    const Spacer(),
                                    Text(
                                      '${TimeFormatUtils.formatShortTime(selectedSub.start)} - ${TimeFormatUtils.formatShortTime(selectedSub.end)}',
                                      style: TextStyle(color: c.textSecondary, fontSize: 9.5),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text('Câu dịch (Tiếng Việt):', style: TextStyle(color: c.textSecondary, fontSize: 9.5)),
                                const SizedBox(height: 2),
                                TextFormField(
                                  initialValue: selectedSub.textTrans,
                                  key: ValueKey('trans_${selectedSub.id}'),
                                  style: TextStyle(color: c.primary, fontSize: 11),
                                  decoration: InputDecoration(
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                    filled: true,
                                    fillColor: c.surfaceLight,
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide.none),
                                  ),
                                  onChanged: (val) => notifier.updateSubtitleText(selectedSub.id, textTrans: val),
                                ),
                                const SizedBox(height: 6),
                                Text('Câu gốc:', style: TextStyle(color: c.textSecondary, fontSize: 9.5)),
                                const SizedBox(height: 2),
                                TextFormField(
                                  initialValue: selectedSub.textOrig,
                                  key: ValueKey('orig_${selectedSub.id}'),
                                  style: TextStyle(color: c.textPrimary, fontSize: 11),
                                  decoration: InputDecoration(
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                    filled: true,
                                    fillColor: c.surfaceLight,
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide.none),
                                  ),
                                  onChanged: (val) => notifier.updateSubtitleText(selectedSub.id, textOrig: val),
                                ),
                              ],
                            ),
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),

                    // Switches for Main and Sub Subtitles
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: c.surfaceDark,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: c.border),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Hiện Sub chính (Dịch):', style: TextStyle(color: c.textPrimary, fontSize: 10.5)),
                              Switch(
                                value: state.subStyle.showMainSub,
                                activeColor: c.primary,
                                onChanged: (v) => notifier.updateSubStyle(state.subStyle.copyWith(showMainSub: v)),
                              ),
                            ],
                          ),
                          Divider(height: 1, color: c.border),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Hiện Sub phụ (Gốc):', style: TextStyle(color: c.textPrimary, fontSize: 10.5)),
                              Switch(
                                value: state.subStyle.showSubSub,
                                activeColor: c.info,
                                onChanged: (v) => notifier.updateSubStyle(state.subStyle.copyWith(showSubSub: v)),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // Safe Alignment Presets
                    Text('Vị trí căn chỉnh an toàn:', style: TextStyle(color: c.textSecondary, fontSize: 10.5)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: AppSegmentButton(
                            icon: Icons.vertical_align_bottom,
                            label: 'Dưới cùng',
                            isSelected: state.subStyle.alignment == 'bottom',
                            onTap: () => notifier.alignSubtitle('bottom'),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: AppSegmentButton(
                            icon: Icons.vertical_align_center,
                            label: 'Ở giữa',
                            isSelected: state.subStyle.alignment == 'center',
                            onTap: () => notifier.alignSubtitle('center'),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: AppSegmentButton(
                            icon: Icons.vertical_align_top,
                            label: 'Trên cùng',
                            isSelected: state.subStyle.alignment == 'top',
                            onTap: () => notifier.alignSubtitle('top'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // Color palette for main sub
                    Text('Màu chữ chính:', style: TextStyle(color: c.textSecondary, fontSize: 10.5)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        '#facc15', // Gold
                        '#ffffff', // White
                        '#4ade80', // Green
                        '#38bdf8', // Cyan
                        '#f472b6', // Pink
                        '#fb923c', // Orange
                      ].map((hex) {
                        final isSel = state.subStyle.fontColor.toLowerCase() == hex.toLowerCase();
                        final col = Color(int.parse('FF${hex.replaceAll('#', '')}', radix: 16));
                        return GestureDetector(
                          onTap: () => notifier.updateSubStyle(state.subStyle.copyWith(fontColor: hex)),
                          child: Container(
                            margin: const EdgeInsets.only(right: 6),
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                              color: col,
                              shape: BoxShape.circle,
                              border: Border.all(color: isSel ? Colors.white : Colors.transparent, width: 2),
                              boxShadow: isSel ? [BoxShadow(color: col.withOpacity(0.5), blurRadius: 4)] : null,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 8),

                    Text('Phông chữ:', style: TextStyle(color: c.textSecondary, fontSize: 10.5)),
                    DropdownButton<String>(
                      value: state.subStyle.fontFamily,
                      isExpanded: true,
                      dropdownColor: c.surface,
                      style: TextStyle(color: c.primary, fontSize: 11.5, fontWeight: FontWeight.bold),
                      items: ['Be Vietnam Pro', 'Montserrat', 'Anton', 'Plus Jakarta Sans', 'Roboto', 'SF Pro Display', 'Arial'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                      onChanged: (v) => notifier.updateSubStyle(state.subStyle.copyWith(fontFamily: v)),
                    ),
                    const SizedBox(height: 8),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Cỡ chữ: ${state.subStyle.fontSize} px', style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10.5)),
                        Row(
                          children: [
                            IconButton(
                              icon: const Text('A-', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                              onPressed: () => notifier.updateSubStyle(state.subStyle.copyWith(fontSize: (state.subStyle.fontSize - 2).clamp(12, 48))),
                            ),
                            IconButton(
                              icon: const Text('A+', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                              onPressed: () => notifier.updateSubStyle(state.subStyle.copyWith(fontSize: (state.subStyle.fontSize + 2).clamp(12, 48))),
                            ),
                          ],
                        ),
                      ],
                    ),
                    Slider(
                      value: state.subStyle.fontSize.toDouble(),
                      min: 12,
                      max: 48,
                      activeColor: const Color(0xFFFACC15),
                      onChanged: (v) => notifier.updateSubStyle(state.subStyle.copyWith(fontSize: v.toInt())),
                    ),
                  ],

                  if (_activeRightTab == 'overlay') ...[
                    Builder(
                      builder: (context) {
                        final selectedOverlay = state.overlayClips.where((cl) => cl.id == state.selectedClipId).firstOrNull ??
                            state.overlayClips.where((cl) => _currentTime >= cl.start && _currentTime <= cl.end).firstOrNull;

                        if (selectedOverlay != null) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.image, size: 14, color: c.info),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      selectedOverlay.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(color: c.textPrimary, fontSize: 11, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  IconButton(
                                    icon: Icon(Icons.delete_outline, size: 14, color: c.statusFailed),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    tooltip: 'Xoá ảnh lớp phủ (Delete)',
                                    onPressed: () => notifier.removeOverlayClip(selectedOverlay.id),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),

                              // Thumbnail Preview & Time Range
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: c.surfaceDark,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: c.border),
                                ),
                                child: Row(
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(4),
                                      child: Image.file(
                                        File(selectedOverlay.imagePath),
                                        width: 36,
                                        height: 36,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => Icon(Icons.broken_image, size: 24, color: c.textMuted),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text('Thời gian xuất hiện:', style: TextStyle(color: c.textSecondary, fontSize: 9.5)),
                                          Text(
                                            '${TimeFormatUtils.formatShortTime(selectedOverlay.start)} ➔ ${TimeFormatUtils.formatShortTime(selectedOverlay.end)}',
                                            style: TextStyle(fontFamily: 'monospace', color: c.info, fontSize: 10.5, fontWeight: FontWeight.bold),
                                          ),
                                          Text(
                                            'Thời lượng: ${(selectedOverlay.end - selectedOverlay.start).toStringAsFixed(1)}s',
                                            style: TextStyle(color: c.textMuted, fontSize: 9),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 10),

                              // Position X & Y (%)
                              Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('Vị trí X: ${selectedOverlay.x.toStringAsFixed(1)}%', style: TextStyle(color: c.textSecondary, fontSize: 10)),
                                        Slider(
                                          value: selectedOverlay.x.clamp(0.0, 90.0),
                                          min: 0.0,
                                          max: 90.0,
                                          activeColor: c.info,
                                          onChanged: (v) => notifier.updateOverlayClipGeometry(selectedOverlay.id, x: v),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('Vị trí Y: ${selectedOverlay.y.toStringAsFixed(1)}%', style: TextStyle(color: c.textSecondary, fontSize: 10)),
                                        Slider(
                                          value: selectedOverlay.y.clamp(0.0, 90.0),
                                          min: 0.0,
                                          max: 90.0,
                                          activeColor: c.info,
                                          onChanged: (v) => notifier.updateOverlayClipGeometry(selectedOverlay.id, y: v),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),

                              // Size W & H (%)
                              Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('Rộng: ${selectedOverlay.width.toStringAsFixed(1)}%', style: TextStyle(color: c.textSecondary, fontSize: 10)),
                                        Slider(
                                          value: selectedOverlay.width.clamp(5.0, 80.0),
                                          min: 5.0,
                                          max: 80.0,
                                          activeColor: c.info,
                                          onChanged: (v) => notifier.updateOverlayClipGeometry(selectedOverlay.id, width: v),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('Cao: ${selectedOverlay.height.toStringAsFixed(1)}%', style: TextStyle(color: c.textSecondary, fontSize: 10)),
                                        Slider(
                                          value: selectedOverlay.height.clamp(5.0, 80.0),
                                          min: 5.0,
                                          max: 80.0,
                                          activeColor: c.info,
                                          onChanged: (v) => notifier.updateOverlayClipGeometry(selectedOverlay.id, height: v),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),

                              // Opacity (%)
                              Text('Độ trong suốt: ${(selectedOverlay.opacity * 100).toInt()}%', style: TextStyle(color: c.textSecondary, fontSize: 10)),
                              Slider(
                                value: selectedOverlay.opacity.clamp(0.1, 1.0),
                                min: 0.1,
                                max: 1.0,
                                activeColor: c.info,
                                onChanged: (v) => notifier.updateOverlayClipGeometry(selectedOverlay.id, opacity: v),
                              ),
                            ],
                          );
                        }

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Danh sách lớp phủ ảnh:', style: TextStyle(color: c.info, fontSize: 11, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 6),
                            if (state.overlayClips.isEmpty)
                              Text('Chưa có ảnh lớp phủ nào trên timeline.', style: TextStyle(color: c.textMuted, fontSize: 10.5))
                            else
                              ...state.overlayClips.map((cl) => InkWell(
                                onTap: () => notifier.selectClip(cl.id),
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: 4),
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: c.surfaceDark,
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: state.selectedClipId == cl.id ? c.info : c.border),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(Icons.image, size: 12, color: c.info),
                                      const SizedBox(width: 6),
                                      Expanded(child: Text(cl.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: c.textPrimary, fontSize: 10.5))),
                                      Text('${TimeFormatUtils.formatShortTime(cl.start)} - ${TimeFormatUtils.formatShortTime(cl.end)}', style: TextStyle(color: c.textSecondary, fontSize: 9.5)),
                                    ],
                                  ),
                                ),
                              )),
                          ],
                        );
                      },
                    ),
                  ],

                  if (_activeRightTab == 'audio') ...[
                    Builder(
                      builder: (context) {
                        final selectedAudio = state.audioClips.where((a) => a.id == state.selectedClipId).firstOrNull ??
                            state.audioClips.where((a) => _currentTime >= a.start && _currentTime <= a.end).firstOrNull;

                        if (selectedAudio != null) {
                          final isMusic = selectedAudio.trackId == 'music';
                          final trackColor = isMusic ? c.statusCompleted : c.info;

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(isMusic ? Icons.music_note : Icons.mic_none, size: 14, color: trackColor),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      selectedAudio.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(color: c.textPrimary, fontSize: 11, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  IconButton(
                                    icon: Icon(Icons.delete_outline, size: 14, color: c.statusFailed),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    tooltip: 'Xoá clip âm thanh (Delete)',
                                    onPressed: () => notifier.removeAudioClip(selectedAudio.id),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),

                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: c.surfaceDark,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: c.border),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Phân loại: ${isMusic ? "Nhạc nền (Music)" : "Hiệu ứng âm thanh (SFX)"}', style: TextStyle(color: trackColor, fontSize: 10, fontWeight: FontWeight.bold)),
                                    const SizedBox(height: 4),
                                    Text('Thời gian phát: ${TimeFormatUtils.formatShortTime(selectedAudio.start)} ➔ ${TimeFormatUtils.formatShortTime(selectedAudio.end)}', style: TextStyle(color: c.textPrimary, fontSize: 10)),
                                    Text('Thời lượng clip: ${(selectedAudio.end - selectedAudio.start).toStringAsFixed(1)}s', style: TextStyle(color: c.textSecondary, fontSize: 9.5)),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 10),

                              Text('Âm lượng clip: ${selectedAudio.volume}%', style: TextStyle(color: c.textSecondary, fontSize: 10)),
                              Slider(
                                value: selectedAudio.volume.toDouble().clamp(0.0, 200.0),
                                min: 0.0,
                                max: 200.0,
                                activeColor: trackColor,
                                onChanged: (v) => notifier.updateAudioClip(selectedAudio.copyWith(volume: v.toInt())),
                              ),
                            ],
                          );
                        }

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Danh sách clip âm thanh:', style: TextStyle(color: c.statusCompleted, fontSize: 11, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 6),
                            if (state.audioClips.isEmpty)
                              Text('Chưa có nhạc nền hay SFX nào trên timeline.', style: TextStyle(color: c.textMuted, fontSize: 10.5))
                            else
                              ...state.audioClips.map((a) {
                                final isM = a.trackId == 'music';
                                final itemColor = isM ? c.statusCompleted : c.info;
                                return InkWell(
                                  onTap: () => notifier.selectClip(a.id),
                                  child: Container(
                                    margin: const EdgeInsets.only(bottom: 4),
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: c.surfaceDark,
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: state.selectedClipId == a.id ? itemColor : c.border),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(isM ? Icons.music_note : Icons.mic_none, size: 12, color: itemColor),
                                        const SizedBox(width: 6),
                                        Expanded(child: Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: c.textPrimary, fontSize: 10.5))),
                                        Text('${a.volume}%', style: TextStyle(color: c.textSecondary, fontSize: 9.5)),
                                      ],
                                    ),
                                  ),
                                );
                              }),
                          ],
                        );
                      },
                    ),
                  ],

                  if (_activeRightTab == 'info') ...[
                    Text('📊 Thông tin chi tiết video:', style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold)),
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
                          _buildInfoRow('Tên tệp:', video?.basename ?? 'Chưa chọn'),
                          _buildInfoRow('Định dạng:', video != null ? p.extension(video.fullPath).toUpperCase() : 'N/A'),
                          _buildInfoRow('Dung lượng:', video != null ? TimeFormatUtils.formatFileSize(video.sizeBytes) : '0 MB'),
                          _buildInfoRow('Thời lượng:', TimeFormatUtils.formatSubtitleTime(_duration)),
                          _buildInfoRow('Vị trí Playhead:', TimeFormatUtils.formatSubtitleTime(_currentTime)),
                          _buildInfoRow('Độ phân giải xuất:', _exportResolution),
                          _buildInfoRow('Tỷ lệ khung hình:', _exportRatio),
                          _buildInfoRow('Tốc độ khung hình:', _exportFps),
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
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPropsTab(String tabKey, String label) {
    final c = AppColors.of(context);
    final isSelected = _activeRightTab == tabKey;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _activeRightTab = tabKey),
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: isSelected ? c.primary : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: isSelected ? c.primary : c.textSecondary,
                fontSize: 9.5,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAudioSyncRow(String label, bool isMuted, VoidCallback onToggle) {
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: c.textPrimary, fontSize: 10)),
          InkWell(
            onTap: onToggle,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isMuted ? c.statusFailedBg : c.statusCompletedBg,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                isMuted ? '🔇 Muted' : '🔊 Bật',
                style: TextStyle(
                  color: isMuted ? c.statusFailed : c.statusCompleted,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(label, style: TextStyle(color: c.textSecondary, fontSize: 10)),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(color: c.textPrimary, fontSize: 10, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  // ── Audio Mixer Bottom Bar (0-200%) ────────────────────────────────────────
  Widget _buildAudioMixerBar(StudioSnapshot state, StudioStateNotifier notifier) {
    final c = AppColors.of(context);
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.border)),
      ),
      child: Row(
        children: [
          Text('MIXER ÂM THANH:', style: TextStyle(color: c.textMuted, fontSize: 10, fontWeight: FontWeight.w600)),
          const SizedBox(width: 14),

          _buildMixerChannel(
            label: 'Video',
            vol: state.mixState.origVolume,
            isMuted: state.mixState.origMuted,
            color: AppColors.primary,
            onChanged: (v) {
              final next = state.mixState.copyWith(origVolume: v);
              notifier.updateMixState(next);
              _videoPlayerKey.currentState?.setVolume(state.mixState.origMuted ? 0 : v.toDouble());
            },
            onToggleMute: () {
              notifier.toggleMuteVideo();
              final willMute = !state.mixState.origMuted;
              _videoPlayerKey.currentState?.setVolume(willMute ? 0 : state.mixState.origVolume.toDouble());
            },
          ),
          const SizedBox(width: 14),

          _buildMixerChannel(
            label: 'Nhạc nền',
            vol: state.mixState.musicVolume,
            isMuted: state.mixState.musicMuted,
            color: AppColors.statusCompleted,
            onChanged: (v) {
              final next = state.mixState.copyWith(musicVolume: v);
              notifier.updateMixState(next);
              _audioSyncPlayer.updateMixState(next);
            },
            onToggleMute: () {
              notifier.toggleMuteMusic();
              final next = state.mixState.copyWith(musicMuted: !state.mixState.musicMuted);
              _audioSyncPlayer.updateMixState(next);
            },
          ),
          const SizedBox(width: 14),

          _buildMixerChannel(
            label: 'Hiệu ứng',
            vol: state.mixState.sfxVolume,
            isMuted: state.mixState.sfxMuted,
            color: const Color(0xFF60A5FA),
            onChanged: (v) {
              final next = state.mixState.copyWith(sfxVolume: v);
              notifier.updateMixState(next);
              _audioSyncPlayer.updateMixState(next);
            },
            onToggleMute: () {
              notifier.toggleMuteSfx();
              final next = state.mixState.copyWith(sfxMuted: !state.mixState.sfxMuted);
              _audioSyncPlayer.updateMixState(next);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMixerChannel({
    required String label,
    required int vol,
    required bool isMuted,
    required Color color,
    required ValueChanged<int> onChanged,
    required VoidCallback onToggleMute,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: onToggleMute,
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.all(3),
            child: Icon(
              isMuted ? Icons.volume_off : Icons.volume_up,
              size: 14,
              color: isMuted ? AppColors.statusFailed : color,
            ),
          ),
        ),
        const SizedBox(width: 3),
        Text(label, style: TextStyle(color: isMuted ? AppColors.statusFailed : AppColors.textLight, fontSize: 10, fontWeight: FontWeight.w500)),
        const SizedBox(width: 2),
        SizedBox(
          width: 110,
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2.5,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 8),
            ),
            child: Slider(
              value: (isMuted ? 0 : vol).toDouble(),
              min: 0,
              max: 200,
              activeColor: isMuted ? AppColors.statusFailed : color,
              inactiveColor: AppColors.surfaceLight,
              onChanged: (v) => onChanged(v.toInt()),
            ),
          ),
        ),
        SizedBox(
          width: 34,
          child: Text(
            isMuted ? 'Tắt' : '$vol%',
            style: TextStyle(color: isMuted ? AppColors.statusFailed : color, fontSize: 9.5, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  // ── Master Export Execution ────────────────────────────────────────────────
  void _executeMasterExport(VideoFile? video, StudioToolMode mode, StudioSnapshot state) async {
    final projectsDir = ref.read(projectsDirProvider);
    final activeProject = ref.read(activeProjectProvider);
    final projectDir = activeProject != null ? '$projectsDir/$activeProject' : projectsDir;

    if (mode == StudioToolMode.cut && video != null) {
      _executeCutAndExport(video, state, projectDir);
    } else if (mode == StudioToolMode.split && video != null) {
      _executeSplitAndExport(video, state, projectDir);
    } else if (mode == StudioToolMode.merge) {
      _executeMergeAndExport(state, projectDir);
    } else if (mode == StudioToolMode.composite && video != null) {
      _executeCompositeExport(video, state, projectDir);
    }
  }

  void _executeCutAndExport(VideoFile video, StudioSnapshot state, String projectDir) async {
    if (state.cutSegments.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Vui lòng thêm ít nhất 1 đoạn rác vào danh sách cắt.')));
      return;
    }
    setState(() => _isProcessing = true);
    final res = await StudioExportService.exportCutVideo(
      video: video,
      cutSegments: state.cutSegments,
      projectDir: projectDir,
      overwriteOriginal: _overwriteOriginalCut,
    );
    setState(() => _isProcessing = false);

    if (res.success) {
      ref.invalidate(projectVideosProvider);
      if (mounted) {
        _showExportSuccessDialog(
          context,
          _overwriteOriginalCut ? 'Cắt & Ghi đè file gốc hoàn tất!' : 'Cắt video thành công (Lưu vào cut/)!',
          res.outputPath ?? video.fullPath,
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi cắt video: ${res.output}')));
      }
    }
  }

  void _executeSplitAndExport(VideoFile video, StudioSnapshot state, String projectDir) async {
    if (state.splitSegments.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Vui lòng tạo ít nhất 1 điểm chia clip trước khi xuất.')));
      return;
    }
    setState(() => _isProcessing = true);
    final res = await StudioExportService.exportSplitSegments(
      video: video,
      splitSegments: state.splitSegments,
      projectDir: projectDir,
    );
    setState(() => _isProcessing = false);

    if (res.success) {
      ref.invalidate(projectVideosProvider);
      if (mounted) {
        _showExportSuccessDialog(
          context,
          'Đã chia thành ${state.splitSegments.length} clip (Lưu vào cut/)!',
          res.outputPath ?? projectDir,
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi chia video: ${res.output}')));
      }
    }
  }

  void _executeMergeAndExport(StudioSnapshot state, String projectDir) async {
    if (state.mergePlaylist.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cần ít nhất 2 video trong danh sách để ghép.')));
      return;
    }

    setState(() => _isProcessing = true);
    final customName = _exportFilenameController.text.trim();
    final res = await StudioExportService.exportMergeVideo(
      mergePlaylist: state.mergePlaylist,
      projectDir: projectDir,
      customFilename: customName.isNotEmpty ? customName : null,
    );
    setState(() => _isProcessing = false);

    if (res.success) {
      ref.invalidate(projectVideosProvider);
      if (mounted) {
        _showExportSuccessDialog(
          context,
          'Ghép & Xuất video thành công (Lưu vào merge/)!',
          res.outputPath ?? projectDir,
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi ghép video: ${res.output}')));
      }
    }
  }

  void _executeCompositeExport(VideoFile video, StudioSnapshot state, String projectDir) async {
    setState(() => _isProcessing = true);
    final customName = _exportFilenameController.text.trim();
    final res = await StudioExportService.exportCompositeVideo(
      video: video,
      state: state,
      projectDir: projectDir,
      customFilename: customName.isNotEmpty ? customName : null,
    );
    setState(() => _isProcessing = false);

    if (res.success && res.outputPath != null) {
      ref.invalidate(projectVideosProvider);
      if (mounted) {
        _showExportSuccessDialog(
          context,
          'Render bản phối đa lớp hoàn tất!',
          res.outputPath!,
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi render đa lớp: ${res.output}')));
      }
    }
  }

  void _showExportSuccessDialog(BuildContext context, String title, String targetPath) {
    final c = AppColors.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: c.border),
        ),
        title: Row(
          children: [
            Icon(Icons.check_circle_rounded, color: c.statusCompleted, size: 20),
            const SizedBox(width: 8),
            Text(title, style: TextStyle(color: c.textPrimary, fontSize: 13, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Tệp video đã được lưu và cập nhật vào thư mục dự án:', style: TextStyle(color: c.textSecondary, fontSize: 11.5)),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: c.surfaceDark,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: c.border),
              ),
              child: SelectableText(
                targetPath,
                style: TextStyle(fontFamily: 'monospace', color: c.info, fontSize: 11),
              ),
            ),
          ],
        ),
        actions: [
          if (Platform.isMacOS)
            TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: c.info),
              icon: const Icon(Icons.folder_open, size: 14),
              label: const Text('Mở thư mục chứa', style: TextStyle(fontSize: 11)),
              onPressed: () {
                final dir = File(targetPath).parent.path;
                Process.run('open', [dir]);
              },
            ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: c.primary,
              foregroundColor: c.primaryText,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            ),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Đóng', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
