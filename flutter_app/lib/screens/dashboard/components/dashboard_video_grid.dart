import 'package:flutter/material.dart';
import '../../../models/video_file.dart';
import '../../../widgets/video_card_widget.dart';

class DashboardVideoGrid extends StatelessWidget {
  final List<VideoFile> displayedFiles;
  final VideoFile? selectedVideo;
  final Set<String> runningPaths;
  final bool isGridView;
  final String activeProject;
  final String selectedCategory;
  final ValueChanged<VideoFile> onSelectFile;
  final ValueChanged<VideoFile> onTranslateVoice;
  final ValueChanged<VideoFile> onTranslateOcr;
  final ValueChanged<VideoFile> onResumeJob;
  final ValueChanged<VideoFile> onOpenSubtitleEditor;
  final ValueChanged<VideoFile> onOpenStudio;
  final ValueChanged<VideoFile> onRename;
  final ValueChanged<VideoFile> onDelete;

  const DashboardVideoGrid({
    super.key,
    required this.displayedFiles,
    required this.selectedVideo,
    required this.runningPaths,
    required this.isGridView,
    required this.activeProject,
    required this.selectedCategory,
    required this.onSelectFile,
    required this.onTranslateVoice,
    required this.onTranslateOcr,
    required this.onResumeJob,
    required this.onOpenSubtitleEditor,
    required this.onOpenStudio,
    required this.onRename,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    if (displayedFiles.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.video_library_outlined, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            Text(
              'Không có video nào trong thư mục $activeProject/$selectedCategory',
              style: const TextStyle(color: Colors.grey, fontSize: 13),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(12),
      child: isGridView
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
                  onSelect: () => onSelectFile(file),
                  onTranslateVoice: () => onTranslateVoice(file),
                  onTranslateOcr: () => onTranslateOcr(file),
                  onResumeJob: () => onResumeJob(file),
                  onOpenSubtitleEditor: () => onOpenSubtitleEditor(file),
                  onOpenStudio: () => onOpenStudio(file),
                  onRename: () => onRename(file),
                  onDelete: () => onDelete(file),
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
                    onSelect: () => onSelectFile(file),
                    onTranslateVoice: () => onTranslateVoice(file),
                    onTranslateOcr: () => onTranslateOcr(file),
                    onResumeJob: () => onResumeJob(file),
                    onOpenSubtitleEditor: () => onOpenSubtitleEditor(file),
                    onOpenStudio: () => onOpenStudio(file),
                    onRename: () => onRename(file),
                    onDelete: () => onDelete(file),
                  ),
                );
              },
            ),
    );
  }
}
