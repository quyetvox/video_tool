import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/file_service.dart';
import '../core/providers.dart';
import '../core/engine_bridge.dart';
import '../models/video_file.dart';
import '../utils/time_format_utils.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/step_progress_indicator.dart';
import '../widgets/video_card_widget.dart';
import '../widgets/video_player_widget.dart';

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
    final isDark = Theme.of(context).brightness == Brightness.dark;
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

        return Row(
          children: [
            // ── LEFT: Video List / Grid ──────────────────────────────
            Expanded(
              flex: 6,
              child: Column(
                children: [
                  // Filter bar & View toggles
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF0F172A) : Colors.white,
                      border: Border(
                        bottom: BorderSide(
                          color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        // Category Filter Chips
                        _buildFilterChip('Tất cả (${allMedia.length})', 'all'),
                        const SizedBox(width: 6),
                        _buildFilterChip('Gốc src (${srcFiles.length})', 'src'),
                        const SizedBox(width: 6),
                        _buildFilterChip('Cắt cut (${cutFiles.length})', 'cut'),
                        const SizedBox(width: 6),
                        _buildFilterChip('Ghép merge (${mergeFiles.length})', 'merge'),
                        const SizedBox(width: 6),
                        _buildFilterChip('Xuất out (${outputFiles.length})', 'output'),

                        const Spacer(),

                        // Search box
                        SizedBox(
                          width: 180,
                          height: 32,
                          child: TextField(
                            onChanged: (val) => setState(() => _searchQuery = val),
                            style: const TextStyle(fontSize: 12),
                            decoration: InputDecoration(
                              hintText: 'Tìm video...',
                              prefixIcon: const Icon(Icons.search, size: 16),
                              contentPadding: EdgeInsets.zero,
                              filled: true,
                              fillColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(6),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),

                        // View mode toggle
                        IconButton(
                          tooltip: _isGridView ? 'Chuyển sang dạng Danh sách' : 'Chuyển sang dạng Lưới',
                          icon: Icon(_isGridView ? Icons.view_list : Icons.grid_view, size: 20),
                          onPressed: () => setState(() => _isGridView = !_isGridView),
                        ),
                      ],
                    ),
                  ),

                  // Videos Grid / List
                  Expanded(
                    child: displayedFiles.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.video_library_outlined, size: 48, color: Colors.grey),
                                const SizedBox(height: 12),
                                Text(
                                  'Không có video nào trong thư mục $activeProject/$_selectedCategory',
                                  style: const TextStyle(color: Colors.grey, fontSize: 13),
                                ),
                              ],
                            ),
                          )
                        : Padding(
                            padding: const EdgeInsets.all(12),
                            child: _isGridView
                                ? GridView.builder(
                                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                                      maxCrossAxisExtent: 320,
                                      mainAxisExtent: 170,
                                      crossAxisSpacing: 12,
                                      mainAxisSpacing: 12,
                                    ),
                                    itemCount: displayedFiles.length,
                                    itemBuilder: (context, index) {
                                      final file = displayedFiles[index];
                                      final isSelected = selectedVideo?.relPath == file.relPath;
                                      final isRunning = runningPaths.contains(file.relPath) ||
                                          runningPaths.contains(file.stem) ||
                                          runningPaths.contains('job_${file.stem}');

                                      return VideoCardWidget(
                                        video: file,
                                        isSelected: isSelected,
                                        isRunning: isRunning,
                                        onSelect: () {
                                          ref.read(selectedVideoProvider.notifier).state = file;
                                        },
                                        onTranslateVoice: () => _runTranslate(context, file, isVoice: true),
                                        onTranslateOcr: () => _runTranslate(context, file, isVoice: false),
                                        onResumeJob: () => _runResume(context, file),
                                        onOpenSubtitleEditor: () {
                                          ref.read(selectedVideoProvider.notifier).state = file;
                                          ref.read(activeNavTabProvider.notifier).state = 1; // Subtitle Editor
                                        },
                                        onOpenStudio: () {
                                          ref.read(selectedVideoProvider.notifier).state = file;
                                          ref.read(activeNavTabProvider.notifier).state = 2; // Studio
                                        },
                                        onRename: () => _showRenameDialog(context, file),
                                        onDelete: () => _showDeleteConfirm(context, file),
                                      );
                                    },
                                  )
                                : ListView.builder(
                                    itemCount: displayedFiles.length,
                                    itemBuilder: (context, index) {
                                      final file = displayedFiles[index];
                                      final isSelected = selectedVideo?.relPath == file.relPath;
                                      final isRunning = runningPaths.contains(file.relPath) ||
                                          runningPaths.contains(file.stem) ||
                                          runningPaths.contains('job_${file.stem}');

                                      return Padding(
                                        padding: const EdgeInsets.only(bottom: 8),
                                        child: VideoCardWidget(
                                          video: file,
                                          isSelected: isSelected,
                                          isRunning: isRunning,
                                          onSelect: () {
                                            ref.read(selectedVideoProvider.notifier).state = file;
                                          },
                                          onTranslateVoice: () => _runTranslate(context, file, isVoice: true),
                                          onTranslateOcr: () => _runTranslate(context, file, isVoice: false),
                                          onResumeJob: () => _runResume(context, file),
                                          onOpenSubtitleEditor: () {
                                            ref.read(selectedVideoProvider.notifier).state = file;
                                            ref.read(activeNavTabProvider.notifier).state = 1;
                                          },
                                          onOpenStudio: () {
                                            ref.read(selectedVideoProvider.notifier).state = file;
                                            ref.read(activeNavTabProvider.notifier).state = 2;
                                          },
                                          onRename: () => _showRenameDialog(context, file),
                                          onDelete: () => _showDeleteConfirm(context, file),
                                        ),
                                      );
                                    },
                                  ),
                          ),
                  ),
                ],
              ),
            ),

            const VerticalDivider(width: 1, thickness: 1),

            // ── RIGHT: Video Detail & Workspace Step Progress ────────
            Expanded(
              flex: 4,
              child: selectedVideo == null
                  ? const Center(
                      child: Text('Chọn một video để xem thông tin chi tiết', style: TextStyle(color: Colors.grey)),
                    )
                  : _buildVideoDetailsPanel(context, selectedVideo, projectsDir, activeProject),
            ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, st) => Center(child: Text('Lỗi: $e', style: const TextStyle(color: Colors.redAccent))),
    );
  }

  Widget _buildFilterChip(String label, String category) {
    final isSelected = _selectedCategory == category;
    return ChoiceChip(
      label: Text(label, style: TextStyle(fontSize: 11, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
      selected: isSelected,
      onSelected: (val) {
        if (val) setState(() => _selectedCategory = category);
      },
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _buildVideoDetailsPanel(
    BuildContext context,
    VideoFile video,
    String projectsDir,
    String activeProject,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final jobId = 'job_${video.stem}';
    final wsJobFiles = FileService.listWorkspaceJobFiles(projectsDir, activeProject, jobId);

    // Compute completed steps based on workspace file existence
    final completedSteps = <String>{};
    for (final f in wsJobFiles) {
      final base = f.basename;
      if (base.startsWith('s01_probe')) completedSteps.add('s01_probe');
      if (base.startsWith('video_stream') || base.startsWith('audio_stream')) completedSteps.add('s02_demux');
      if (base.startsWith('s03_subtitle')) completedSteps.add('s03_subtitle_detect');
      if (base == 'voice.wav' || base.contains('voice')) completedSteps.add('s04_audio_separate');
      if (base.startsWith('s05_asr')) completedSteps.add('s05_asr');
      if (base.startsWith('s05b_gender')) completedSteps.add('s05b_gender_detect');
      if (base.startsWith('s06_ocr')) completedSteps.add('s06_ocr');
      if (base.startsWith('s07_transcript')) completedSteps.add('s07_transcript_merge');
      if (base.startsWith('s08_translation')) completedSteps.add('s08_translation');
      if (base.startsWith('s08b_metadata')) completedSteps.add('s08b_metadata_gen');
      if (base.startsWith('s08c_timing')) completedSteps.add('s08c_timing');
      if (base.endsWith('.ass') || base.endsWith('.srt')) completedSteps.add('s09_subtitle_gen');
      if (base.startsWith('clean_video')) completedSteps.add('s10_inpaint');
      if (base.startsWith('rendered_video')) completedSteps.add('s11_subtitle_render');
      if (base.startsWith('tts_audio')) completedSteps.add('s12_tts');
      if (base.startsWith('mixed_audio')) completedSteps.add('s13_audio_mix');
    }

    return Container(
      padding: const EdgeInsets.all(16),
      color: isDark ? const Color(0xFF0F172A) : const Color(0xFFFAFAFA),
      child: ListView(
        children: [
          // Video Player Preview
          SizedBox(
            height: 220,
            child: VideoPlayerWidget(
              videoPath: video.fullPath,
              autoPlay: false,
            ),
          ),
          const SizedBox(height: 16),

          // File Info Card
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  video.basename,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text('Dung lượng: ', style: TextStyle(color: Colors.grey, fontSize: 12)),
                    Text(
                      TimeFormatUtils.formatFileSize(video.sizeBytes),
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                    ),
                    const Spacer(),
                    const Text('Job ID: ', style: TextStyle(color: Colors.grey, fontSize: 12)),
                    Text(
                      jobId,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12, fontFamily: 'monospace'),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Đường dẫn: ${video.relPath}',
                  style: const TextStyle(color: Colors.grey, fontSize: 11, fontFamily: 'monospace'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Step Progress Indicator
          StepProgressIndicator(
            completedSteps: completedSteps,
            onDeleteStepCache: (stepId) async {
              final ok = await ConfirmDialog.show(
                context,
                title: 'Xóa Cache Bước $stepId?',
                message: 'Bạn có chắc chắn muốn xóa cache của bước $stepId không? Hệ thống sẽ tự động chạy lại từ bước này trong lần resume tiếp theo.',
                isDestructive: true,
              );
              if (ok) {
                await FileService.deleteStepCache(projectsDir, activeProject, jobId, stepId);
                ref.invalidate(projectVideosProvider);
              }
            },
          ),
          const SizedBox(height: 16),

          // Workspace Files Summary & Delete Job Button
          Row(
            children: [
              Text(
                'Workspace Files (${wsJobFiles.length} tệp cache)',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const Spacer(),
              if (wsJobFiles.isNotEmpty)
                TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: const Text('Xóa toàn bộ Job', style: TextStyle(fontSize: 12)),
                  onPressed: () async {
                    final ok = await ConfirmDialog.show(
                      context,
                      title: 'Xóa toàn bộ Workspace Job?',
                      message: 'Xóa tất cả file cache trung gian của $jobId? Thao tác này không thể hoàn tác.',
                      isDestructive: true,
                    );
                    if (ok) {
                      FileService.deleteWorkspaceJob(projectsDir, activeProject, jobId);
                      ref.invalidate(projectVideosProvider);
                    }
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _runTranslate(BuildContext context, VideoFile video, {required bool isVoice}) async {
    final activeProj = ref.read(activeProjectProvider);
    if (activeProj == null) return;
    final jobId = 'job_${video.stem}';

    // Register running state
    ref.read(runningPathsProvider.notifier).update((set) => {...set, video.relPath, video.stem, jobId});

    EngineBridge.translateVideo(
      video.fullPath,
      ocrOnly: !isVoice,
      voice: isVoice,
      jobId: jobId,
    ).then((res) {
      // Unregister running state
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Đổi tên file'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Hủy')),
          ElevatedButton(
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
            child: const Text('Lưu'),
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
