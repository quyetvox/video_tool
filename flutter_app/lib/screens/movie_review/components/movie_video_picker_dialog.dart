import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../../../../core/app_colors.dart';
import '../../../../core/python_bridge.dart';
import '../../../../models/video_file.dart';
import '../../../../widgets/video_thumbnail_widget.dart';

class MovieVideoPickerDialog extends StatefulWidget {
  final List<VideoFile> videoFiles;
  final String? currentSelectedPath;
  final String projectName;
  final ValueChanged<VideoFile> onVideoSelected;

  const MovieVideoPickerDialog({
    super.key,
    required this.videoFiles,
    this.currentSelectedPath,
    required this.projectName,
    required this.onVideoSelected,
  });

  @override
  State<MovieVideoPickerDialog> createState() => _MovieVideoPickerDialogState();
}

class _MovieVideoPickerDialogState extends State<MovieVideoPickerDialog> {
  String _searchQuery = '';

  bool _hasCachedScript(VideoFile file) {
    final root = PythonBridge.resolveRootDir();
    final safeName = p.withoutExtension(file.name).replaceAll(RegExp(r'[^\w\-]+'), '_');
    final scriptPath = p.join(root, 'resources', widget.projectName, 'workspace', 'movie_review', safeName, 'review_script.json');
    return File(scriptPath).existsSync();
  }

  String _formatFileSize(int bytes) {
    if (bytes <= 0) return '0 B';
    final mb = bytes / (1024 * 1024);
    if (mb >= 1024) {
      return '${(mb / 1024).toStringAsFixed(2)} GB';
    }
    return '${mb.toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final filtered = widget.videoFiles.where((f) {
      if (_searchQuery.isEmpty) return true;
      return f.name.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();

    return Dialog(
      backgroundColor: c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: c.border),
      ),
      child: Container(
        width: 740,
        height: 540,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                const Icon(Icons.movie_filter_outlined, size: 22, color: AppColors.primary),
                const SizedBox(width: 10),
                const Text(
                  'Chọn Video Phim Nguồn (src/)',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppColors.primary.withOpacity(0.35)),
                  ),
                  child: Text(
                    widget.projectName,
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.primaryHover),
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, size: 20, color: Colors.white70),
                  tooltip: 'Đóng',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Search Bar
            TextField(
              style: const TextStyle(fontSize: 12, color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Tìm kiếm tên phim theo từ khóa...',
                hintStyle: TextStyle(fontSize: 12, color: c.textMuted),
                prefixIcon: const Icon(Icons.search, size: 18, color: AppColors.primary),
                isDense: true,
                filled: true,
                fillColor: c.surfaceLight,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c.border)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c.border)),
              ),
              onChanged: (val) => setState(() => _searchQuery = val.trim()),
            ),
            const SizedBox(height: 14),

            // Video Grid List
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.video_library_outlined, size: 40, color: c.textMuted),
                          const SizedBox(height: 10),
                          Text(
                            'Không tìm thấy video nào trong thư mục src/ của project.',
                            style: TextStyle(fontSize: 12, color: c.textMuted),
                          ),
                        ],
                      ),
                    )
                  : GridView.builder(
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: 1.15,
                      ),
                      itemCount: filtered.length,
                      itemBuilder: (ctx, idx) {
                        final file = filtered[idx];
                        final isSelected = file.fullPath == widget.currentSelectedPath;
                        final hasCache = _hasCachedScript(file);

                        return InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () {
                            widget.onVideoSelected(file);
                            Navigator.of(context).pop();
                          },
                          child: Container(
                            decoration: BoxDecoration(
                              color: isSelected ? AppColors.primary.withOpacity(0.08) : c.surfaceLight,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isSelected ? AppColors.primary : c.border,
                                width: isSelected ? 2 : 1,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Thumbnail with Duration Badge
                                Expanded(
                                  child: Stack(
                                    children: [
                                      Positioned.fill(
                                        child: ClipRRect(
                                          borderRadius: const BorderRadius.vertical(top: Radius.circular(7)),
                                          child: VideoThumbnailWidget(
                                            videoPath: file.fullPath,
                                            showDuration: true,
                                          ),
                                        ),
                                      ),
                                      if (hasCache)
                                        Positioned(
                                          top: 6,
                                          left: 6,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Colors.black87,
                                              borderRadius: BorderRadius.circular(4),
                                              border: Border.all(color: AppColors.statusCompleted, width: 0.8),
                                            ),
                                            child: const Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(Icons.cached, size: 10, color: AppColors.statusCompleted),
                                                SizedBox(width: 3),
                                                Text(
                                                  'Có kịch bản',
                                                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: AppColors.statusCompleted),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      if (isSelected)
                                        Positioned(
                                          top: 6,
                                          right: 6,
                                          child: Container(
                                            padding: const EdgeInsets.all(3),
                                            decoration: const BoxDecoration(
                                              color: AppColors.primary,
                                              shape: BoxShape.circle,
                                            ),
                                            child: const Icon(Icons.check, size: 12, color: Colors.black),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),

                                // Meta Info
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        file.name,
                                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 2),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            _formatFileSize(file.sizeBytes),
                                            style: TextStyle(fontSize: 10, color: c.textMuted),
                                          ),
                                          Text(
                                            'Click để chọn',
                                            style: TextStyle(fontSize: 9.5, color: isSelected ? AppColors.primaryHover : c.textMuted),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
