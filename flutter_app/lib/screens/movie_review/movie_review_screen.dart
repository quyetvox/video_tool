import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/app_colors.dart';
import '../../../core/file_service.dart';
import '../../../core/library_filter_state.dart';
import '../../../core/providers.dart';
import '../../../models/app_config.dart';
import '../../../models/video_file.dart';
import '../../../widgets/app_kit.dart';
import '../../../widgets/asset_table_widget.dart';
import '../../../widgets/process_logs_console_widget.dart';
import '../../../widgets/resizable_collapsible_panel.dart';
import 'components/components.dart';
import 'controllers/movie_review_controller.dart';

/// Màn hình AI Review Phim & Tóm Tắt Điện Ảnh (2-Tier Desktop Layout)
class MovieReviewScreen extends ConsumerStatefulWidget {
  const MovieReviewScreen({super.key});

  @override
  ConsumerState<MovieReviewScreen> createState() => _MovieReviewScreenState();
}

class _MovieReviewScreenState extends ConsumerState<MovieReviewScreen> {
  final TextEditingController _renameController = TextEditingController();

  @override
  void dispose() {
    _renameController.dispose();
    super.dispose();
  }

  void _handleDeleteFile(VideoFile file) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xác nhận xóa'),
        content: Text('Bạn có chắc muốn xóa "${file.name}" khỏi dự án không?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
          AppButton.danger(
            label: 'Xóa',
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final activeProject = ref.read(activeProjectProvider);
      final success = FileService.deleteVideoFile(file.fullPath);
      if (success) {
        ref.invalidate(projectVideosProvider);
        final state = ref.read(movieReviewProvider);
        if (state.videoPath == file.fullPath) {
          ref.read(movieReviewProvider.notifier).selectVideoFromProject(
                projectName: activeProject ?? 'default',
                videoPath: '',
                videoName: '',
              );
        }
      }
    }
  }

  void _handleRenameFile(VideoFile file) async {
    _renameController.text = file.basename;
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Đổi tên video'),
        content: TextField(
          controller: _renameController,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Tên file mới',
            hintText: 'Nhập tên file (không cần đuôi .mp4)',
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

    if (newName != null && newName.isNotEmpty && mounted) {
      final activeProject = ref.read(activeProjectProvider);
      final success = FileService.renameVideoFile(file.fullPath, newName);
      if (success) {
        ref.invalidate(projectVideosProvider);
        final state = ref.read(movieReviewProvider);
        if (state.videoPath == file.fullPath) {
          ref.read(movieReviewProvider.notifier).selectVideoFromProject(
                projectName: activeProject ?? 'default',
                videoPath: file.fullPath,
                videoName: '$newName.mp4',
              );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final state = ref.watch(movieReviewProvider);
    final controller = ref.read(movieReviewProvider.notifier);
    final activeProject = ref.watch(activeProjectProvider);
    final videosAsync = ref.watch(projectVideosProvider);
    final runningPaths = ref.watch(runningPathsProvider);
    final logBuffer = ref.watch(logBufferProvider);
    final config = ref.watch(configProvider);
    final displayFiles = ref.watch(filteredProjectVideosProvider);

    // Xác định file đang được chọn trong Asset Table
    VideoFile? selectedVideo;
    if (state.videoPath != null && state.videoPath!.isNotEmpty) {
      try {
        selectedVideo = displayFiles.firstWhere((f) => f.fullPath == state.videoPath);
      } catch (_) {
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

    // Lắng nghe thay đổi của config để cập nhật API Key / Model
    ref.listen<AppConfig>(configProvider, (prev, next) {
      if (next.translatorApiKey.isNotEmpty && state.apiKey != next.translatorApiKey) {
        controller.setApiKey(next.translatorApiKey);
      }
      if (next.translatorModel.isNotEmpty && state.aiModel != next.translatorModel) {
        controller.setAiModel(next.translatorModel);
      }
    });

    // Tự động chọn video mặc định nếu chưa chọn video nào
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if ((state.videoPath == null || state.videoPath!.isEmpty) && displayFiles.isNotEmpty) {
        final first = displayFiles.first;
        controller.selectVideoFromProject(
          projectName: activeProject ?? 'default',
          videoPath: first.fullPath,
          videoName: first.name,
          apiKey: config.translatorApiKey,
          aiModel: config.translatorModel,
        );
      } else {
        if (config.translatorApiKey.isNotEmpty && state.apiKey != config.translatorApiKey) {
          controller.setApiKey(config.translatorApiKey);
        }
        if (config.translatorModel.isNotEmpty && state.aiModel != config.translatorModel) {
          controller.setAiModel(config.translatorModel);
        }
      }
    });

    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: Column(
          children: [
            MovieReviewHeaderBar(
              state: state,
              controller: controller,
            ),
            // ── BỐ CỤC 2 TẦNG CHUẨN MỰC (TOP WORKSPACE + BOTTOM ASSET PANEL) ──
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
                          apiKey: config.translatorApiKey,
                          aiModel: config.translatorModel,
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
                  collapseTooltip: 'Thu gọn bảng thuộc tính review',
                  expandTooltip: 'Mở rộng bảng thuộc tính review',
                  panel: ReviewPropertiesInspector(
                    state: state,
                    controller: controller,
                    videoFile: selectedVideo,
                    onGenerateScript: () => controller.startAnalysis(),
                    onStartRender: () => controller.startRender(),
                  ),
                  child: ResizableCollapsiblePanel(
                    side: PanelSide.right,
                    initialWidth: 420.0,
                    minWidth: 280.0,
                    maxWidth: 700.0,
                    collapseTooltip: 'Thu gọn bảng kịch bản storyboard',
                    expandTooltip: 'Mở rộng bảng kịch bản storyboard',
                    panel: ReviewInspectorCard(
                      state: state,
                      controller: controller,
                      activeProject: activeProject,
                      videoFiles: displayFiles,
                    ),
                    child: Container(
                      decoration: BoxDecoration(
                        color: c.surfaceDark,
                        border: Border(right: BorderSide(color: c.border)),
                      ),
                      child: ReviewVideoCanvasView(
                        key: const ValueKey('review_video_canvas'),
                        state: state,
                        controller: controller,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
