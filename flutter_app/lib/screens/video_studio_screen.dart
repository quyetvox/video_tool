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
import '../core/audio_sync_player.dart';
import '../core/studio_draft_service.dart';
import '../core/studio_export_service.dart';
import '../widgets/studio_keyboard_handler.dart';
import '../widgets/app_kit.dart';
import '../widgets/license_dialog.dart';
import '../core/license_service.dart';
import '../widgets/resizable_collapsible_panel.dart';
import 'video_studio/components/studio_header_toolbar.dart';
import 'video_studio/components/studio_tools_panel.dart';
import 'video_studio/components/studio_audio_mixer.dart';
import 'video_studio/components/properties/studio_properties_panel.dart';

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
  bool _isProcessing = false;
  double _exportProgress = 0.0;
  bool _isVideoPlaying = false;
  int _activeMergeIndex = 0;
  bool _overwriteOriginalCut = false;
  double _lastAutoSeekSec = -1.0;

  // Multi-Draft state
  StudioDraft? _activeDraft;
  List<StudioDraft> _availableDrafts = [];
  String _lastLoadedVideoStem = '';

  // Export settings
  late final TextEditingController _exportFilenameController;
  String _lastAutoExportStem = '';
  StudioToolMode? _lastAutoToolMode;
  String _exportResolution = 'Giữ nguyên (1920x1080)';
  String _exportFps = '30 fps';
  String _exportRatio = '16:9 (Ngang)';
  String _exportBitrate = '4M';

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

  Future<void> _refreshDrafts(String projectDir, {VideoFile? videoToLoad, StudioStateNotifier? notifier}) async {
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

    if (videoToLoad != null && notifier != null) {
      final videoDrafts = list.where((d) => d.videoStem == videoToLoad.stem || d.videoPath.contains(videoToLoad.stem)).toList();
      if (videoDrafts.isNotEmpty) {
        final draft = videoDrafts.first;
        if (mounted) setState(() => _activeDraft = draft);
        notifier.loadSnapshot(draft.snapshot, draftName: draft.name);
      } else {
        if (mounted) setState(() => _activeDraft = null);
        notifier.loadSubtitlesFromPipeline(projectDir, videoToLoad.stem);
      }
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

    final speed = (state.videoSpeed > 0) ? state.videoSpeed : 1.0;
    final timelineSec = sec / speed;
    setState(() => _currentTime = timelineSec);

    if (mode == StudioToolMode.composite) {
      _audioSyncPlayer.updateTracks(state.audioTracks);
      _audioSyncPlayer.updateClips(state.audioClips);
      _audioSyncPlayer.updateMixState(state.mixState);
      _audioSyncPlayer.syncPosition(timelineSec, _isVideoPlaying);
    } else {
      _audioSyncPlayer.pause();
    }

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

    final speed = (state.videoSpeed > 0) ? state.videoSpeed : 1.0;
    setState(() => _currentTime = targetSec);
    _videoPlayerKey.currentState?.seekTo(targetSec * speed);
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
        _refreshDrafts(projectDir, videoToLoad: selectedVideo, notifier: studioNotifier);
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
            // ── 1. Top Bar Header Toolbar ───────────────────────────────────────────
            StudioHeaderToolbar(
              toolMode: toolMode,
              selectedVideo: selectedVideo,
              canUndo: studioNotifier.canUndo,
              canRedo: studioNotifier.canRedo,
              onUndo: () => studioNotifier.undo(),
              onRedo: () => studioNotifier.redo(),
              activeDraft: _activeDraft,
              availableDrafts: _availableDrafts,
              onSaveDraft: selectedVideo != null
                  ? () => _saveCurrentDraft(context, projectDir, selectedVideo, studioState, toolMode)
                  : null,
              onShowDraftsMenu: projectDir.isNotEmpty
                  ? () => _showDraftsMenu(context, projectDir, selectedVideo, studioNotifier)
                  : null,
              onClearSession: () => _showClearSessionDialog(context, toolMode, studioState),
              isProcessing: _isProcessing,
              exportProgress: _exportProgress,
              onExport: () => _executeMasterExport(selectedVideo, toolMode, studioState),
            ),

            // ── 2. Middle Body: Workspace & Lower Multitrack Timeline Canvas (Vertical Resizable) ──
            Expanded(
              child: ResizableCollapsiblePanel(
                side: PanelSide.bottom,
                initialHeight: 280.0,
                minHeight: 120.0,
                maxHeight: 560.0,
                collapseTooltip: 'Thu gọn Timeline',
                expandTooltip: 'Mở rộng Timeline',
                panel: MultitrackTimelineWidget(
                  duration: (toolMode == StudioToolMode.merge && studioState.mergePlaylist.isNotEmpty)
                      ? _getMergeTotalDuration(studioState.mergePlaylist)
                      : (_duration / (studioState.videoSpeed > 0 ? studioState.videoSpeed : 1.0)),
                  currentTime: _currentTime,
                  onSeek: (sec) => _handleSeek(sec, toolMode, studioState),
                ),
                child: ResizableCollapsiblePanel(
                  side: PanelSide.left,
                  initialWidth: 320,
                  minWidth: 240,
                  maxWidth: 480,
                  collapseTooltip: 'Thu gọn danh sách video',
                  expandTooltip: 'Mở danh sách video',
                  panel: StudioSidebarWidget(
                    width: double.infinity,
                    onCollapse: () {},
                    currentTime: _currentTime,
                    duration: (toolMode == StudioToolMode.merge && studioState.mergePlaylist.isNotEmpty)
                        ? _getMergeTotalDuration(studioState.mergePlaylist)
                        : (_duration / (studioState.videoSpeed > 0 ? studioState.videoSpeed : 1.0)),
                  ),
                  child: ResizableCollapsiblePanel(
                    side: PanelSide.right,
                    initialWidth: 400,
                    minWidth: 280,
                    maxWidth: 650,
                    collapseTooltip: 'Thu gọn thuộc tính studio',
                    expandTooltip: 'Mở thuộc tính studio',
                    panel: StudioPropertiesPanel(
                      state: studioState,
                      notifier: studioNotifier,
                      video: selectedVideo,
                      toolMode: toolMode,
                      duration: _duration,
                      currentTime: _currentTime,
                      onReloadPipeline: selectedVideo != null
                          ? () {
                              final ok = studioNotifier.loadSubtitlesFromPipeline(projectDir, selectedVideo.stem);
                              final count = ref.read(studioStateProvider).subtitles.length;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(ok
                                      ? 'Đã nạp $count phụ đề từ Bước 8c Pipeline!'
                                      : 'Không tìm thấy file phụ đề bước 8c cho video này.'),
                                  duration: const Duration(seconds: 2),
                                ),
                              );
                            }
                          : null,
                      exportFilenameController: _exportFilenameController,
                      exportResolution: _exportResolution,
                      exportFps: _exportFps,
                      exportRatio: _exportRatio,
                      exportBitrate: _exportBitrate,
                      onResolutionChanged: (val) => setState(() => _exportResolution = val),
                      onFpsChanged: (val) => setState(() => _exportFps = val),
                      onRatioChanged: (val) => setState(() => _exportRatio = val),
                      onBitrateChanged: (val) => setState(() => _exportBitrate = val),
                      onResetDefaultFilename: () {
                        _exportFilenameController.text = _getDefaultExportFilename(toolMode, selectedVideo, studioState.mergePlaylist);
                      },
                      onSpeedChanged: (speed) {
                        studioNotifier.setVideoSpeed(speed);
                        _videoPlayerKey.currentState?.setPlaybackRate(speed);
                      },
                      onSeek: (sec) => _handleSeek(sec, toolMode, studioState),
                    ),
                    child: Container(
                      decoration: BoxDecoration(color: c.surfaceDark),
                      child: Row(
                        children: [
                          // Center Column 1: Video Player & Canvas
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                color: c.surfaceDark,
                                border: Border(
                                  right: BorderSide(color: c.border),
                                  bottom: BorderSide(color: c.border),
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
                                      playbackRate: studioState.videoSpeed,
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
                                  : Center(
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.movie_filter_outlined, size: 36, color: c.textMuted),
                                          const SizedBox(height: 8),
                                          Text('Chưa có video nào được chọn', style: TextStyle(color: c.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
                                          const SizedBox(height: 4),
                                          Text('Chọn một video từ sidebar bên trái để bắt đầu', style: TextStyle(color: c.textMuted, fontSize: 10.5)),
                                        ],
                                      ),
                                    ),
                            ),
                          ),

                          // Center Column 2: Center Tools Panel
                          Container(
                            width: 230,
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: c.surface,
                              border: Border(
                                right: BorderSide(color: c.border),
                                bottom: BorderSide(color: c.border),
                              ),
                            ),
                            child: StudioToolsPanel(
                              mode: toolMode,
                              state: studioState,
                              notifier: studioNotifier,
                              duration: _duration,
                              currentTime: _currentTime,
                              overwriteOriginalCut: _overwriteOriginalCut,
                              onOverwriteOriginalCutChanged: (v) => setState(() => _overwriteOriginalCut = v),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // ── 4. Audio Mixer Footer Bar (Auto-hidden in MERGE mode) ───────
            if (toolMode != StudioToolMode.merge)
              StudioAudioMixerBar(
                state: studioState,
                notifier: studioNotifier,
                onVideoVolumeChanged: (vol, isMuted) {
                  _videoPlayerKey.currentState?.setVolume(isMuted ? 0.0 : vol.toDouble());
                },
                onMusicVolumeChanged: (vol, isMuted) {
                  _audioSyncPlayer.updateMixState(studioState.mixState);
                },
                onSfxVolumeChanged: (vol, isMuted) {
                  _audioSyncPlayer.updateMixState(studioState.mixState);
                },
              ),
          ],
        ),
      ),
    );
  }

  void _executeMasterExport(VideoFile? video, StudioToolMode mode, StudioSnapshot state) async {
    final license = ref.read(licenseInfoProvider);
    if (!license.isValid) {
      LicenseDialog.show(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Vui lòng kích hoạt bản quyền hoặc đăng ký nhận 7 ngày dùng thử miễn phí để xuất video!'),
          backgroundColor: Color(0xFFD97706),
        ),
      );
      return;
    }

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
    setState(() {
      _isProcessing = true;
      _exportProgress = 0.0;
    });
    final customName = _exportFilenameController.text.trim();
    final canvasSize = StudioCanvasOverlay.lastCanvasSize;
    final res = await StudioExportService.exportCompositeVideo(
      video: video,
      state: state,
      projectDir: projectDir,
      customFilename: customName.isNotEmpty ? customName : null,
      videoSpeed: state.videoSpeed,
      videoBitrate: _exportBitrate,
      canvasWidth: canvasSize.width,
      canvasHeight: canvasSize.height,
      onProgress: (pct) {
        if (mounted) setState(() => _exportProgress = pct / 100.0);
      },
    );
    setState(() {
      _isProcessing = false;
      _exportProgress = 0.0;
    });

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

  void _showClearSessionDialog(BuildContext context, StudioToolMode toolMode, StudioSnapshot state) {
    final c = AppColors.of(context);
    String label;
    int count;
    if (toolMode == StudioToolMode.cut) {
      label = 'Cắt bỏ rác';
      count = state.cutSegments.length;
    } else if (toolMode == StudioToolMode.split) {
      label = 'Chia clip';
      count = state.splitSegments.length;
    } else if (toolMode == StudioToolMode.merge) {
      label = 'Ghép video';
      count = state.mergePlaylist.length;
    } else {
      label = 'Biên tập đa lớp';
      count = state.overlayClips.length + state.audioClips.length + state.subtitles.length;
    }
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
            const Icon(Icons.warning_amber_rounded, color: AppColors.statusFailed, size: 20),
            const SizedBox(width: 8),
            Text('Làm mới session $label?',
                style: TextStyle(color: c.textPrimary, fontSize: 13, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          'Xác nhận xóa toàn bộ $count mục trong tab "$label"?\n(Có thể hoàn tác bằng Undo trên timeline)',
          style: TextStyle(color: c.textSecondary, fontSize: 11.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Hủy', style: TextStyle(color: c.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              final notifier = ref.read(studioStateProvider.notifier);
              if (toolMode == StudioToolMode.cut) {
                notifier.clearCutSession();
              } else if (toolMode == StudioToolMode.split) {
                notifier.clearSplitSession();
              } else if (toolMode == StudioToolMode.merge) {
                notifier.clearMergeSession();
              } else {
                notifier.clearCompositeSession();
              }
            },
            child: const Text('Xóa', style: TextStyle(color: AppColors.statusFailed, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
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
          TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: c.info),
            icon: const Icon(Icons.folder_open, size: 14),
            label: const Text('Mở thư mục chứa', style: TextStyle(fontSize: 11)),
            onPressed: () {
              final dir = File(targetPath).parent.path;
              if (Platform.isMacOS) {
                Process.run('open', [dir]);
              } else if (Platform.isWindows) {
                Process.run('explorer.exe', [dir]);
              } else {
                Process.run('xdg-open', [dir]);
              }
            },
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            ),
            icon: const Icon(Icons.play_circle_fill_rounded, size: 15),
            label: const Text('Xem video ngay', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
            onPressed: () {
              if (Platform.isMacOS) {
                Process.run('open', [targetPath]);
              } else if (Platform.isWindows) {
                Process.run('cmd', ['/c', 'start', '', targetPath]);
              } else {
                Process.run('xdg-open', [targetPath]);
              }
            },
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: c.surfaceDark,
              foregroundColor: c.textPrimary,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
                side: BorderSide(color: c.border),
              ),
            ),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Đóng', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
