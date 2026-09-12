import 'package:flutter/material.dart';
import '../../../core/file_service.dart';
import '../../../models/video_file.dart';
import '../../../utils/time_format_utils.dart';
import '../../../widgets/confirm_dialog.dart';
import '../../../widgets/step_progress_indicator.dart';
import '../../../widgets/video_player_widget.dart';

class DashboardVideoDetailPanel extends StatelessWidget {
  final VideoFile? selectedVideo;
  final String projectsDir;
  final String activeProject;
  final VoidCallback onRefresh;

  const DashboardVideoDetailPanel({
    super.key,
    required this.selectedVideo,
    required this.projectsDir,
    required this.activeProject,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (selectedVideo == null) {
      return const Center(
        child: Text('Chọn một video để xem thông tin chi tiết', style: TextStyle(color: Colors.grey)),
      );
    }

    final video = selectedVideo!;
    final jobId = 'job_${video.stem}';
    final wsJobFiles = FileService.listWorkspaceJobFiles(projectsDir, activeProject, jobId);

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
            project: activeProject,
            jobId: jobId,
            projectsDir: projectsDir,
            onDeleteStepCache: (stepId) async {
              await FileService.deleteStepCache(projectsDir, activeProject, jobId, stepId);
              onRefresh();
            },
            onClearAllSteps: () async {
              await FileService.deleteAllStepCaches(projectsDir, activeProject, jobId);
              onRefresh();
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
                    if (ok == true) {
                      FileService.deleteWorkspaceJob(projectsDir, activeProject, jobId);
                      onRefresh();
                    }
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }
}
