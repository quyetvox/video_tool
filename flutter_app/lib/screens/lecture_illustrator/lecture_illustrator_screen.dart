import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/app_colors.dart';
import '../../../core/providers.dart';
import '../../../core/file_service.dart';
import '../../../core/python_bridge.dart';
import '../../../core/library_filter_state.dart';
import '../../../models/app_config.dart';
import '../../../models/video_file.dart';
import '../../../widgets/app_kit.dart';
import '../../../widgets/asset_table_widget.dart';
import '../../../widgets/process_logs_console_widget.dart';
import '../../../widgets/resizable_collapsible_panel.dart';
import '../../../widgets/subtitle_inspector_widget.dart';
import '../../../widgets/video_player_widget.dart';
import 'components/lecture_header_bar.dart';
import 'components/lecture_properties_inspector.dart';
import 'components/lecture_storyboard_tab_card.dart';
import 'components/lecture_video_hero_card.dart';
import 'controllers/lecture_illustrator_controller.dart';

class LectureIllustratorScreen extends ConsumerStatefulWidget {
  const LectureIllustratorScreen({super.key});

  @override
  ConsumerState<LectureIllustratorScreen> createState() =>
      _LectureIllustratorScreenState();
}

class _LectureIllustratorScreenState
    extends ConsumerState<LectureIllustratorScreen> {
  final TextEditingController _renameController = TextEditingController();
  final GlobalKey<VideoPlayerWidgetState> _playerKey =
      GlobalKey<VideoPlayerWidgetState>();
  double _currentTime = 0.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(lectureIllustratorProvider.notifier).syncFromConfig(ref.read(configProvider));
    });
  }

  @override
  void dispose() {
    _renameController.dispose();
    super.dispose();
  }

  void _handleDeleteFile(VideoFile file) {
    final success = FileService.deleteVideoFile(file.fullPath);
    if (success && mounted) {
      ref.invalidate(projectVideosProvider);
    }
  }

  Future<void> _handleRenameFile(VideoFile file) async {
    final ext = p.extension(file.name);
    _renameController.text = p.withoutExtension(file.name);
    final newBaseName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Đổi tên tệp tài sản bài giảng'),
        content: TextField(
          controller: _renameController,
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'Tên file mới',
            hintText: 'Nhập tên file (giữ đuôi $ext)',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
          AppButton.primary(
            label: 'Lưu',
            onPressed: () => Navigator.pop(ctx, _renameController.text.trim()),
          ),
        ],
      ),
    );

    if (newBaseName != null && newBaseName.isNotEmpty && mounted) {
      final finalName = ext.isNotEmpty ? '$newBaseName$ext' : newBaseName;
      final activeProject = ref.read(activeProjectProvider);
      final success = FileService.renameVideoFile(file.fullPath, finalName);
      if (success) {
        ref.invalidate(projectVideosProvider);
        final state = ref.read(lectureIllustratorProvider);
        if (state.videoPath == file.fullPath) {
          final newFullPath = p.join(p.dirname(file.fullPath), finalName);
          ref.read(lectureIllustratorProvider.notifier).selectVideoFromProject(
                projectName: activeProject ?? 'default',
                videoPath: newFullPath,
                videoName: finalName,
              );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final state = ref.watch(lectureIllustratorProvider);
    final controller = ref.read(lectureIllustratorProvider.notifier);
    final activeProject = ref.watch(activeProjectProvider);
    final displayFiles = ref.watch(filteredProjectVideosProvider);
    final runningPaths = ref.watch(runningPathsProvider);
    final logBuffer = ref.watch(logBufferProvider);

    // Lắng nghe thay đổi cấu hình từ configProvider để đồng bộ xuống state
    ref.listen<AppConfig>(configProvider, (prev, next) {
      controller.syncFromConfig(next);
    });

    // Xác định file đang được chọn trong Asset Table
    VideoFile? selectedVideo;
    if (state.videoPath != null && state.videoPath!.isNotEmpty) {
      try {
        selectedVideo = displayFiles.firstWhere((f) => f.fullPath == state.videoPath);
      } catch (_) {
        selectedVideo = null;
      }
    }

    // Tự động chọn video đầu tiên nếu chưa chọn
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if ((state.videoPath == null || state.videoPath!.isEmpty) && displayFiles.isNotEmpty) {
        final first = displayFiles.first;
        controller.selectVideoFromProject(
          projectName: activeProject ?? 'default',
          videoPath: first.fullPath,
          videoName: first.name,
        );
      }
    });

    return Scaffold(
      backgroundColor: c.background,
      body: Column(
        children: [
          // ── 1. SUB-HEADER TOOLBAR (44px) ──
          LectureHeaderBar(state: state, controller: controller),

          // ── 2. BỐ CỤC 2 TẦNG CHUẨN MỰC (TOP WORKSPACE + BOTTOM ASSET PANEL) ──
          Expanded(
            child: ResizableCollapsiblePanel(
              side: PanelSide.bottom,
              initialHeight: 220.0,
              minHeight: 130.0,
              maxHeight: 500.0,
              collapseTooltip: 'Thu gọn danh sách video & console',
              expandTooltip: 'Mở rộng danh sách video & console',
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
                    isProcessRunning: state.isAnalyzing || state.isRendering,
                    onClearLogs: () => ref.read(logBufferProvider.notifier).clear(),
                    onStopProcess: () => controller.cancelProcess(),
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
                      controller.selectVideoFromProject(
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
                    onImportFile: () async {
                      final result = await FilePicker.platform.pickFiles(
                        dialogTitle: 'Chọn tệp bài giảng (Video, Audio, Văn bản)',
                        type: FileType.custom,
                        allowedExtensions: ['mp4', 'mov', 'mkv', 'webm', 'wav', 'mp3', 'm4a', 'aac', 'flac', 'txt', 'md'],
                      );
                      if (result != null && result.files.single.path != null) {
                        final pickedPath = result.files.single.path!;
                        final root = PythonBridge.resolveRootDir();
                        final pName = ref.read(activeProjectProvider) ?? 'default';
                        final copied = FileService.importFileToProject(p.join(root, 'resources'), pName, pickedPath);
                        if (copied != null && context.mounted) {
                          ref.invalidate(projectVideosProvider);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('📥 Đã nhập tệp: ${p.basename(copied.path)} vào dự án!'),
                              backgroundColor: AppColors.statusCompleted,
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        }
                      }
                    },
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
                panel: LecturePropertiesInspector(
                  state: state,
                  controller: controller,
                  videoFile: selectedVideo,
                ),
                child: ResizableCollapsiblePanel(
                  side: PanelSide.right,
                  initialWidth: 420.0,
                  minWidth: 280.0,
                  maxWidth: 700.0,
                  collapseTooltip: 'Thu gọn bảng phụ đề & kịch bản',
                  expandTooltip: 'Mở rộng bảng phụ đề & kịch bản',
                  panel: SubtitleInspectorWidget(
                    subtitles: controller.toSubtitleSegments(),
                    currentTime: _currentTime,
                    onSubtitleChange: (subs) {
                      controller.syncSegmentsFromSubtitles(subs);
                    },
                    onSeekToSubtitle: (timeSec) =>
                        _playerKey.currentState?.seekTo(timeSec),
                    onTranslateAll: () => controller.startAnalysis(),
                    onAutoSync: () => controller.startAnalysis(),
                    onSaveSubtitles: () => controller.startAnalysis(),
                    isProcessing: state.isAnalyzing || state.isRendering,
                    showLongVideoTab: false,
                    customScriptTabTitle: '🎓 Kịch Bản & Storyboard',
                    customScriptTab: LectureStoryboardTabCard(
                      state: state,
                      controller: controller,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: LectureVideoHeroCard(
                      state: state,
                      controller: controller,
                      playerKey: _playerKey,
                      onPositionChanged: (pos) {
                        if ((pos - _currentTime).abs() >= 0.5) {
                          setState(() => _currentTime = pos);
                        }
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
