import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/app_colors.dart';
import '../core/file_service.dart';
import '../core/providers.dart';
import '../core/engine_bridge.dart';
import '../models/video_file.dart';
import '../widgets/app_kit.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/license_dialog.dart';
import '../widgets/paywall_dialog.dart';
import '../core/license_service.dart';
import '../widgets/resizable_collapsible_panel.dart';
import 'dashboard/components/dashboard_components.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  String _selectedCategory = 'all'; // all | src | cut | merge | output
  String _searchQuery = '';
  bool _isGridView = true;

  @override
  Widget build(BuildContext context) {
    final activeProject = ref.watch(activeProjectProvider);
    final projectsDir = ref.watch(projectsDirProvider);
    final selectedVideo = ref.watch(selectedVideoProvider);
    final runningPaths = ref.watch(runningPathsProvider);

    if (activeProject == null || activeProject.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.folder_open, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('Vui lòng chọn hoặc tạo một dự án ở thanh tiêu đề phía trên.', style: TextStyle(fontSize: 14)),
          ],
        ),
      );
    }

    final videosAsync = ref.watch(projectVideosProvider);

    return videosAsync.when(
      data: (videoData) {
        final srcFiles = videoData['srcFiles'] ?? <VideoFile>[];
        final cutFiles = videoData['cutFiles'] ?? <VideoFile>[];
        final mergeFiles = videoData['mergeFiles'] ?? <VideoFile>[];
        final outputFiles = videoData['outputFiles'] ?? <VideoFile>[];
        final allMedia = <VideoFile>[...srcFiles, ...cutFiles, ...mergeFiles, ...outputFiles];

        List<VideoFile> displayedFiles = [];
        switch (_selectedCategory) {
          case 'src':
            displayedFiles = srcFiles;
            break;
          case 'cut':
            displayedFiles = cutFiles;
            break;
          case 'merge':
            displayedFiles = mergeFiles;
            break;
          case 'output':
            displayedFiles = outputFiles;
            break;
          case 'all':
          default:
            displayedFiles = allMedia;
            break;
        }

        if (_searchQuery.trim().isNotEmpty) {
          displayedFiles = displayedFiles
              .where((f) => f.basename.toLowerCase().contains(_searchQuery.toLowerCase().trim()))
              .toList();
        }

        // Auto select first video if none selected
        if (selectedVideo == null && displayedFiles.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            ref.read(selectedVideoProvider.notifier).state = displayedFiles.first;
          });
        }

        return ResizableCollapsiblePanel(
          initialWidth: 420,
          minWidth: 280,
          maxWidth: 650,
          side: PanelSide.right,
          collapseTooltip: 'Thu gọn chi tiết video',
          panel: DashboardVideoDetailPanel(
            selectedVideo: selectedVideo,
            projectsDir: projectsDir,
            activeProject: activeProject,
            onRefresh: () {
              if (mounted) setState(() {});
              ref.invalidate(projectVideosProvider);
            },
          ),
          child: Column(
            children: [
              DashboardFilterBar(
                selectedCategory: _selectedCategory,
                allCount: allMedia.length,
                srcCount: srcFiles.length,
                cutCount: cutFiles.length,
                mergeCount: mergeFiles.length,
                outputCount: outputFiles.length,
                searchQuery: _searchQuery,
                isGridView: _isGridView,
                onCategoryChanged: (cat) => setState(() => _selectedCategory = cat),
                onSearchChanged: (val) => setState(() => _searchQuery = val),
                onToggleGridView: () => setState(() => _isGridView = !_isGridView),
              ),
              Expanded(
                child: DashboardVideoGrid(
                  displayedFiles: displayedFiles,
                  selectedVideo: selectedVideo,
                  runningPaths: runningPaths,
                  isGridView: _isGridView,
                  activeProject: activeProject,
                  selectedCategory: _selectedCategory,
                  onSelectFile: (file) {
                    ref.read(selectedVideoProvider.notifier).state = file;
                  },
                  onTranslateVoice: (file) => _runTranslate(context, file, isVoice: true),
                  onTranslateOcr: (file) => _runTranslate(context, file, isVoice: false),
                  onResumeJob: (file) => _runResume(context, file),
                  onOpenSubtitleEditor: (file) {
                    ref.read(selectedVideoProvider.notifier).state = file;
                    ref.read(activeNavTabProvider.notifier).state = 1; // Subtitle Editor
                  },
                  onOpenStudio: (file) {
                    ref.read(selectedVideoProvider.notifier).state = file;
                    ref.read(activeNavTabProvider.notifier).state = 2; // Studio
                  },
                  onRename: (file) => _showRenameDialog(context, file),
                  onDelete: (file) => _showDeleteConfirm(context, file),
                ),
              ),
            ],
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, st) => Center(child: Text('Lỗi: $e', style: const TextStyle(color: Colors.redAccent))),
    );
  }

  Future<void> _runTranslate(BuildContext context, VideoFile video, {required bool isVoice}) async {
    final license = ref.read(licenseInfoProvider);
    if (!license.isValid) {
      LicenseDialog.show(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Vui lòng kích hoạt bản quyền hoặc đăng ký nhận 7 ngày dùng thử miễn phí để tiếp tục!'),
          backgroundColor: Color(0xFFD97706),
        ),
      );
      return;
    }

    final activeProj = ref.read(activeProjectProvider);
    if (activeProj == null) return;
    final jobId = 'job_${video.stem}';

    ref.read(runningPathsProvider.notifier).update((set) => {...set, video.relPath, video.stem, jobId});

    EngineBridge.translateVideo(
      video.fullPath,
      ocrOnly: !isVoice,
      voice: isVoice,
      jobId: jobId,
    ).then((res) {
      ref.read(runningPathsProvider.notifier).update((set) => set.where((p) => !p.contains(video.stem)).toSet());
      ref.invalidate(projectVideosProvider);
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('🚀 Đã bắt đầu tiến trình dịch [${isVoice ? "Voice" : "OCR Only"}]: ${video.basename}'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _runResume(BuildContext context, VideoFile video) async {
    final license = ref.read(licenseInfoProvider);
    if (!license.isValid) {
      LicenseDialog.show(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Vui lòng kích hoạt bản quyền hoặc đăng ký nhận 7 ngày dùng thử miễn phí để tiếp tục!'),
          backgroundColor: Color(0xFFD97706),
        ),
      );
      return;
    }

    if (!license.canUseResume) {
      PaywallDialog.show(
        context,
        featureName: 'Cơ Chế Resume Thông Minh',
        featureDescription: 'Tự động phát hiện và tiếp tục quy trình tại bước gián đoạn gần nhất',
      );
      return;
    }

    final activeProj = ref.read(activeProjectProvider);
    if (activeProj == null) return;
    final jobId = 'job_${video.stem}';

    ref.read(runningPathsProvider.notifier).update((set) => {...set, video.relPath, video.stem, jobId});

    EngineBridge.resumeJob(
      video.fullPath,
      projectId: activeProj,
    ).then((res) {
      ref.read(runningPathsProvider.notifier).update((set) => set.where((p) => !p.contains(video.stem)).toSet());
      ref.invalidate(projectVideosProvider);
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('🔄 Đang tiếp tục xử lý (Resume): $activeProj:$jobId'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showRenameDialog(BuildContext context, VideoFile video) {
    final controller = TextEditingController(text: video.basename);
    final activeProj = ref.read(activeProjectProvider);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: const BorderSide(color: AppColors.border)),
        content: AppTextField(
          controller: controller,
          autofocus: true,
          height: 34,
          hint: 'Nhập tên file mới...',
        ),
        actions: [
          AppButton.ghost(
            label: 'Hủy',
            onPressed: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 6),
          AppButton.primary(
            label: 'Lưu',
            onPressed: () {
              final newName = controller.text.trim();
              if (newName.isNotEmpty && newName != video.basename) {
                final ok = FileService.renameFile(video.fullPath, newName);
                if (ok && activeProj != null) {
                  ref.invalidate(projectVideosProvider);
                  ref.read(selectedVideoProvider.notifier).state = null;
                }
              }
              Navigator.of(context).pop();
            },
          ),
        ],
      ),
    );
  }

  Future<void> _showDeleteConfirm(BuildContext context, VideoFile video) async {
    final activeProj = ref.read(activeProjectProvider);
    final ok = await ConfirmDialog.show(
      context,
      title: 'Xóa video?',
      message: 'Bạn có chắc chắn muốn xóa "${video.basename}" khỏi đĩa cứng?',
      isDestructive: true,
    );
    if (ok && activeProj != null) {
      FileService.deleteFile(video.fullPath);
      ref.invalidate(projectVideosProvider);
      ref.read(selectedVideoProvider.notifier).state = null;
    }
  }
}
