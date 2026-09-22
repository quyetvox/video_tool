import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/app_colors.dart';
import '../../core/file_service.dart';
import '../../core/providers.dart';
import '../../core/library_filter_state.dart';
import '../../models/app_config.dart';
import '../../models/subtitle_segment.dart';
import '../../models/video_file.dart';
import '../../widgets/app_kit.dart';
import '../../widgets/asset_table_widget.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/process_logs_console_widget.dart';
import '../../widgets/resizable_collapsible_panel.dart';
import '../../widgets/subtitle_inspector_widget.dart';
import '../../widgets/video_gizmo_toolbar.dart';
import '../../widgets/video_player_widget.dart';
import 'components/components.dart';
import 'controllers/vlog_story_controller.dart';

class VlogStoryScreen extends ConsumerStatefulWidget {
  const VlogStoryScreen({super.key});

  @override
  ConsumerState<VlogStoryScreen> createState() => _VlogStoryScreenState();
}

class _VlogStoryScreenState extends ConsumerState<VlogStoryScreen> {
  double _currentTime = 0.0;
  bool _isPlayerFullscreen = false;
  final GlobalKey<VideoPlayerWidgetState> _playerKey = GlobalKey<VideoPlayerWidgetState>();
  List<SubtitleSegment> _subtitles = [];

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final state = ref.watch(vlogStoryProvider);
    final controller = ref.read(vlogStoryProvider.notifier);

    final activeProject = ref.watch(activeProjectProvider);
    final videosAsync = ref.watch(projectVideosProvider);
    final runningPaths = ref.watch(runningPathsProvider);
    final logBuffer = ref.watch(logBufferProvider);

    final displayFiles = ref.watch(filteredProjectVideosProvider);

    // Lắng nghe thay đổi cấu hình từ configProvider để đồng bộ xuống VlogStoryState
    ref.listen<AppConfig>(configProvider, (prev, next) {
      controller.syncFromConfig(next);
    });

    // Đồng bộ danh sách SubtitleSegment từ state.segments
    if (state.segments.isNotEmpty) {
      if (_subtitles.length != state.segments.length) {
        _subtitles = controller.toSubtitleSegments();
      }
    } else if (_subtitles.isNotEmpty) {
      _subtitles = [];
    }

    // Tìm file video đang chọn từ danh sách file dự án
    VideoFile? selectedVideo;
    if (state.videoPath.isNotEmpty) {
      try {
        selectedVideo = displayFiles.firstWhere((f) => f.fullPath == state.videoPath);
      } catch (_) {
        // Fallback: Tìm trong toàn bộ video nếu video đang chọn nằm ngoài bộ lọc hiện tại
        final allFiles = [
          ...videosAsync.value?['srcFiles'] ?? const [],
          ...videosAsync.value?['cutFiles'] ?? const [],
          ...videosAsync.value?['mergeFiles'] ?? const [],
          ...videosAsync.value?['outputFiles'] ?? const [],
        ];
        try {
          selectedVideo = allFiles.firstWhere((f) => f.fullPath == state.videoPath);
        } catch (_) {
          selectedVideo = null;
        }
      }
    }

    // Tự động nạp video đầu tiên nếu chưa chọn
    if (selectedVideo == null && displayFiles.isNotEmpty && state.videoPath.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final first = displayFiles.first;
        controller.selectVideo(
          projectName: activeProject ?? 'default',
          videoPath: first.fullPath,
          videoName: first.name,
        );
      });
    }

    return Scaffold(
      backgroundColor: c.background,
      body: Stack(
        children: [
          Column(
            children: [
              VlogStoryHeaderBar(
                state: state,
                controller: controller,
              ),
              // ══════════════════════════════════════════════════════════════════════
              // ── TOÀN BỘ KHÔNG GIAN: TẦNG TRÊN & TẦNG DƯỚI (VERTICAL RESIZABLE) ──
              // ══════════════════════════════════════════════════════════════════════
              Expanded(
                child: ResizableCollapsiblePanel(
                  side: PanelSide.bottom,
                  initialHeight: 280.0,
                  minHeight: 130.0,
                  maxHeight: 600.0,
                  collapseTooltip: 'Thu gọn danh sách video & nhật ký',
                  expandTooltip: 'Mở rộng danh sách video & nhật ký',
                  panel: ResizableCollapsiblePanel(
                    side: PanelSide.right,
                    initialWidth: 420.0,
                    minWidth: 260.0,
                    maxWidth: 750.0,
                    collapseTooltip: 'Thu gọn nhật ký',
                    expandTooltip: 'Mở rộng nhật ký',
                    panel: Container(
                      decoration: BoxDecoration(
                        color: c.surfaceDark,
                        border: Border(
                          top: BorderSide(color: c.border),
                          left: BorderSide(color: c.border),
                        ),
                      ),
                      child: ProcessLogsConsoleWidget(
                        logs: logBuffer,
                        isProcessRunning: state.isProcessing,
                        onClearLogs: () => ref.read(logBufferProvider.notifier).clear(),
                        onStopProcess: () => controller.cancelActiveTask(),
                      ),
                    ),
                    child: Container(
                      decoration: BoxDecoration(
                        color: c.surface,
                        border: Border(top: BorderSide(color: c.border)),
                      ),
                      child: AssetTableWidget(
                        files: displayFiles,
                        selectedFile: selectedVideo,
                        onSelectFile: (file) {
                          controller.selectVideo(
                            projectName: activeProject ?? 'default',
                            videoPath: file.fullPath,
                            videoName: file.name,
                          );
                        },
                        runningRelPaths: runningPaths,
                        onRefresh: () => ref.invalidate(projectVideosProvider),
                        onOpenTrimmer: (_) {},
                        onDeleteFile: _handleDeleteFile,
                        onRenameFile: _handleRenameFile,
                      ),
                    ),
                  ),
                  child: ResizableCollapsiblePanel(
                    side: PanelSide.right,
                    initialWidth: 280.0,
                    minWidth: 220.0,
                    maxWidth: 450.0,
                    collapseTooltip: 'Thu gọn bảng thuộc tính',
                    expandTooltip: 'Mở rộng bảng thuộc tính',
                    panel: VlogPropertiesInspector(
                      state: state,
                      controller: controller,
                      videoFile: selectedVideo,
                      onGenerateScript: () => controller.generateScript(),
                      onResumeRender: () => controller.renderFinalVideo(),
                    ),
                    child: ResizableCollapsiblePanel(
                      side: PanelSide.right,
                      initialWidth: 420.0,
                      minWidth: 280.0,
                      maxWidth: 700.0,
                      collapseTooltip: 'Thu gọn bảng kịch bản AI',
                      expandTooltip: 'Mở rộng bảng kịch bản AI',
                      panel: SubtitleInspectorWidget(
                        subtitles: _subtitles,
                        currentTime: _currentTime,
                        onSubtitleChange: (subs) {
                          setState(() => _subtitles = subs);
                          controller.syncSegmentsFromSubtitles(subs);
                        },
                        onSeekToSubtitle: (timeSec) => _playerKey.currentState?.seekTo(timeSec),
                        onTranslateAll: () => controller.generateScript(),
                        onAutoSync: () => controller.saveScriptToDisk(),
                        onSaveSubtitles: () => controller.saveScriptToDisk(),
                        isProcessing: state.isProcessing,
                        showLongVideoTab: false,
                        customScriptTabTitle: '📖 Kịch bản AI',
                        customScriptTab: VlogPromptConfigCard(
                          state: state,
                          controller: controller,
                        ),
                      ),
                      child: Container(
                        decoration: BoxDecoration(
                          color: c.surfaceDark,
                          border: Border(
                            right: BorderSide(color: c.border),
                          ),
                        ),
                        child: Column(
                          children: [
                            // ── 1. THANH CÔNG CỤ GIZMO 4 LỚP CĂN CHỈNH ──
                            VideoGizmoToolbar(
                              enabled: selectedVideo != null,
                            ),

                            // ── 2. KHUNG PHÁT VIDEO PLAYER ──
                            Expanded(
                              child: selectedVideo != null
                                  ? (!_isPlayerFullscreen
                                      ? VideoPlayerWidget(
                                          key: ValueKey(selectedVideo.fullPath),
                                          videoPath: selectedVideo.fullPath,
                                          isFullscreen: false,
                                          onToggleFullscreen: () => setState(() => _isPlayerFullscreen = true),
                                          onPositionChanged: (sec) => setState(() => _currentTime = sec),
                                          onDurationChanged: (dur) => controller.setDuration(dur),
                                        )
                                      : Center(
                                          child: Text(
                                            'Đang phát toàn màn hình...',
                                            style: TextStyle(color: c.textMuted, fontSize: 12),
                                          ),
                                        ))
                                  : Center(
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.movie_filter_outlined, size: 48, color: c.textMuted),
                                          const SizedBox(height: 12),
                                          Text('Chọn video từ danh sách bên trái để bắt đầu', style: TextStyle(color: c.textSecondary, fontSize: 13)),
                                        ],
                                      ),
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),

          // ── FULLSCREEN CINEMATIC PLAYER OVERLAY ──
          if (_isPlayerFullscreen && selectedVideo != null)
            Positioned.fill(
              child: Material(
                color: Colors.black,
                child: VideoPlayerWidget(
                  videoPath: selectedVideo.fullPath,
                  isFullscreen: true,
                  onToggleFullscreen: () => setState(() => _isPlayerFullscreen = false),
                  onPositionChanged: (sec) => setState(() => _currentTime = sec),
                  onDurationChanged: (dur) => controller.setDuration(dur),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _handleRenameFile(VideoFile file) {
    final textCtrl = TextEditingController(text: file.basename);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: const BorderSide(color: AppColors.border)),
        title: const Text('Đổi Tên Video', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
        content: AppTextField(
          controller: textCtrl,
          autofocus: true,
          height: 34,
          hint: 'Nhập tên video mới...',
        ),
        actions: [
          AppButton.ghost(
            label: 'Hủy',
            onPressed: () => Navigator.pop(ctx),
          ),
          const SizedBox(width: 6),
          AppButton.primary(
            label: 'Đổi Tên',
            onPressed: () {
              final newName = textCtrl.text.trim();
              if (newName.isNotEmpty && newName != file.basename) {
                FileService.renameVideoFile(file.fullPath, newName);
                ref.invalidate(projectVideosProvider);
              }
              Navigator.pop(ctx);
            },
          ),
        ],
      ),
    );
  }

  void _handleDeleteFile(VideoFile file) async {
    final ok = await ConfirmDialog.show(
      context,
      title: 'Xóa video?',
      message: 'Bạn có chắc chắn muốn xóa vĩnh viễn "${file.basename}" khỏi đĩa cứng?',
      isDestructive: true,
    );
    if (ok) {
      FileService.deleteVideoFile(file.fullPath);
      ref.invalidate(projectVideosProvider);
    }
  }
}
