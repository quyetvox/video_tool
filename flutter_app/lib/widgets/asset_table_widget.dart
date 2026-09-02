import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import '../core/app_colors.dart';
import '../core/thumbnail_service.dart';
import '../models/video_file.dart';
import '../utils/time_format_utils.dart';
import 'video_thumbnail_widget.dart';

class AssetTableWidget extends StatefulWidget {
  final List<VideoFile> files;
  final VideoFile? selectedFile;
  final Function(VideoFile file) onSelectFile;
  final Set<String> runningRelPaths;
  final VoidCallback onRefresh;
  final Function(VideoFile file) onOpenTrimmer;
  final Function(VideoFile file) onDeleteFile;
  final Function(VideoFile file) onRenameFile;
  final Function(List<VideoFile> selectedFiles)? onBatchTranslateVoice;
  final Function(List<VideoFile> selectedFiles)? onBatchTranslateSub;
  final Function(List<VideoFile> selectedFiles)? onBatchUploadCloud;
  final Function(List<VideoFile> selectedFiles)? onBatchSyncDown;
  final Function(List<VideoFile> selectedFiles)? onBatchOffload;
  final Function(List<VideoFile> selectedFiles)? onBatchDelete;

  const AssetTableWidget({
    super.key,
    required this.files,
    required this.selectedFile,
    required this.onSelectFile,
    required this.runningRelPaths,
    required this.onRefresh,
    required this.onOpenTrimmer,
    required this.onDeleteFile,
    required this.onRenameFile,
    this.onBatchTranslateVoice,
    this.onBatchTranslateSub,
    this.onBatchUploadCloud,
    this.onBatchSyncDown,
    this.onBatchOffload,
    this.onBatchDelete,
    this.externalSelectedPaths,
    this.onSelectionChanged,
  });

  final Set<String>? externalSelectedPaths;
  final ValueChanged<Set<String>>? onSelectionChanged;

  @override
  State<AssetTableWidget> createState() => _AssetTableWidgetState();
}

class _AssetTableWidgetState extends State<AssetTableWidget> {
  bool _isGridView = false;
  String _searchQuery = '';
  final Set<String> _selectedPaths = {};

  @override
  void initState() {
    super.initState();
    if (widget.externalSelectedPaths != null) {
      _selectedPaths.addAll(widget.externalSelectedPaths!);
    }
  }

  @override
  void didUpdateWidget(covariant AssetTableWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.externalSelectedPaths != null && !setEquals(widget.externalSelectedPaths, oldWidget.externalSelectedPaths)) {
      setState(() {
        _selectedPaths.clear();
        _selectedPaths.addAll(widget.externalSelectedPaths!);
      });
    }
  }

  void _setSelection(VoidCallback fn) {
    setState(fn);
    widget.onSelectionChanged?.call(_selectedPaths);
  }

  String _formatTimeAgo(DateTime dateTime) {
    final diff = DateTime.now().difference(dateTime);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    if (diff.inDays < 30) return '${(diff.inDays / 7).floor()}w ago';
    return '${(diff.inDays / 30).floor()}mo ago';
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final filtered = widget.files.where((f) {
      if (_searchQuery.trim().isEmpty) return true;
      return f.basename.toLowerCase().contains(_searchQuery.toLowerCase().trim());
    }).toList();

    final allSelected = filtered.isNotEmpty && _selectedPaths.length == filtered.length;
    final selectedVideoFiles = widget.files.where((f) => _selectedPaths.contains(f.fullPath)).toList();

    return Container(
      decoration: BoxDecoration(
        color: c.surface,
      ),
      child: Column(
        children: [
          // ── HEADER TOOLBAR ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Text(
                  'All Videos (${widget.files.length})',
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 13.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: Icon(Icons.refresh, size: 16, color: c.textSecondary),
                  tooltip: 'Làm mới danh sách',
                  onPressed: widget.onRefresh,
                ),
                const Spacer(),

                // Search Box
                SizedBox(
                  width: 200,
                  height: 32,
                  child: TextField(
                    style: TextStyle(fontSize: 12, color: c.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'Tìm kiếm video...',
                      hintStyle: TextStyle(color: c.textMuted, fontSize: 11.5),
                      prefixIcon: Icon(Icons.search, size: 14, color: c.textMuted),
                      contentPadding: EdgeInsets.zero,
                      filled: true,
                      fillColor: c.surfaceDark,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: BorderSide(color: c.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: BorderSide(color: c.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: BorderSide(color: c.primary),
                      ),
                    ),
                    onChanged: (val) => setState(() => _searchQuery = val),
                  ),
                ),

                const SizedBox(width: 8),

                // View Toggle (Table / Grid)
                IconButton(
                  icon: Icon(_isGridView ? Icons.view_list : Icons.grid_view, size: 17, color: c.textSecondary),
                  tooltip: _isGridView ? 'Chuyển sang dạng Bảng' : 'Chuyển sang dạng Lưới',
                  onPressed: () => setState(() => _isGridView = !_isGridView),
                ),
              ],
            ),
          ),

          // ── MAIN TABLE / GALLERY ──
          Expanded(
            child: filtered.isEmpty
                ? const Center(
                    child: Text(
                      'Không tìm thấy video nào trong thư mục này',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 12.5),
                    ),
                  )
                : _isGridView
                    ? _buildGridView(filtered)
                    : _buildGalleryListView(filtered, allSelected),
          ),

          // ── FLOATING BATCH ACTIONS BAR ──
          if (_selectedPaths.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: const BoxDecoration(
                color: AppColors.surfaceDark,
                border: Border(top: BorderSide(color: AppColors.border)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primaryMuted,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: AppColors.primary.withOpacity(0.4)),
                    ),
                    child: Text(
                      '${_selectedPaths.length} video đã chọn',
                      style: const TextStyle(color: AppColors.primary, fontSize: 11.5, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), minimumSize: Size.zero),
                    icon: const Icon(Icons.close, size: 12, color: AppColors.textSecondary),
                    label: const Text('Bỏ chọn', style: TextStyle(color: AppColors.textSecondary, fontSize: 11.5)),
                    onPressed: () => _setSelection(() => _selectedPaths.clear()),
                  ),

                  const Spacer(),

                  // 1. Dịch Voice (N)
                  _buildBatchActionButton(
                    icon: Icons.mic,
                    label: 'Dịch Voice (${_selectedPaths.length})',
                    color: AppColors.statusCompleted,
                    onTap: () {
                      final selected = List<VideoFile>.from(selectedVideoFiles);
                      _setSelection(() => _selectedPaths.clear());
                      widget.onBatchTranslateVoice?.call(selected);
                    },
                  ),
                  const SizedBox(width: 6),

                  // 2. Dịch Sub (N)
                  _buildBatchActionButton(
                    icon: Icons.subtitles,
                    label: 'Dịch Sub (${_selectedPaths.length})',
                    color: AppColors.primary,
                    onTap: () {
                      final selected = List<VideoFile>.from(selectedVideoFiles);
                      _setSelection(() => _selectedPaths.clear());
                      widget.onBatchTranslateSub?.call(selected);
                    },
                  ),
                  const SizedBox(width: 6),

                  // 3. Upload Cloud
                  _buildBatchActionButton(
                    icon: Icons.cloud_upload,
                    label: 'Upload Cloud (${_selectedPaths.length})',
                    color: AppColors.info,
                    onTap: () {
                      final selected = List<VideoFile>.from(selectedVideoFiles);
                      _setSelection(() => _selectedPaths.clear());
                      widget.onBatchUploadCloud?.call(selected);
                    },
                  ),
                  const SizedBox(width: 6),

                  // 4. Download Cloud
                  _buildBatchActionButton(
                    icon: Icons.cloud_download,
                    label: 'Download (${_selectedPaths.length})',
                    color: const Color(0xFF22D3EE),
                    onTap: () {
                      final selected = List<VideoFile>.from(selectedVideoFiles);
                      _setSelection(() => _selectedPaths.clear());
                      widget.onBatchSyncDown?.call(selected);
                    },
                  ),
                  const SizedBox(width: 6),

                  // 5. Offload SSD
                  _buildBatchActionButton(
                    icon: Icons.cleaning_services,
                    label: 'Offload SSD (${_selectedPaths.length})',
                    color: const Color(0xFFF97316),
                    onTap: () {
                      final selected = List<VideoFile>.from(selectedVideoFiles);
                      _setSelection(() => _selectedPaths.clear());
                      widget.onBatchOffload?.call(selected);
                    },
                  ),
                  const SizedBox(width: 6),

                  // 6. Delete All
                  _buildBatchActionButton(
                    icon: Icons.delete_forever,
                    label: 'Xóa (${_selectedPaths.length})',
                    color: AppColors.statusFailed,
                    onTap: () {
                      final selected = List<VideoFile>.from(selectedVideoFiles);
                      setState(() => _selectedPaths.clear());
                      widget.onBatchDelete?.call(selected);
                    },
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// Modern List Gallery View strictly matching Image 2
  Widget _buildGalleryListView(List<VideoFile> filtered, bool allSelected) {
    final c = AppColors.of(context);
    return ListView.builder(
      itemCount: filtered.length + 1,
      itemBuilder: (ctx, idx) {
        if (idx == 0) {
          // Table Header
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: c.surface,
              border: Border(bottom: BorderSide(color: c.border)),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 22,
                  child: Checkbox(
                    value: allSelected,
                    activeColor: c.primary,
                    checkColor: c.primaryText,
                    side: BorderSide(color: c.textMuted, width: 1),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
                    onChanged: (val) {
                      _setSelection(() {
                        if (val == true) {
                          _selectedPaths.addAll(filtered.map((f) => f.fullPath));
                        } else {
                          _selectedPaths.clear();
                        }
                      });
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 7,
                  child: Text('Name', style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.w500)),
                ),
                Expanded(
                  flex: 3,
                  child: Text('Status', style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.w500)),
                ),
                SizedBox(
                  width: 65,
                  child: Text('Duration', style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.w500)),
                ),
                SizedBox(
                  width: 75,
                  child: Text('Updated', style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.w500)),
                ),
                const SizedBox(width: 36),
              ],
            ),
          );
        }

        final file = filtered[idx - 1];
        final isSelected = widget.selectedFile?.fullPath == file.fullPath;
        final isChecked = _selectedPaths.contains(file.fullPath);
        final isRunning = widget.runningRelPaths.any((p) => p.contains(file.stem) || file.fullPath.contains(p));

        // Format updated relative time
        DateTime lastMod = DateTime.now();
        try {
          lastMod = File(file.fullPath).lastModifiedSync();
        } catch (_) {}
        final updatedAgo = _formatTimeAgo(lastMod);

        return InkWell(
          onTap: () => widget.onSelectFile(file),
          hoverColor: c.surfaceLight.withOpacity(0.5),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: isSelected ? c.surfaceLight : Colors.transparent,
              border: Border(bottom: BorderSide(color: c.border, width: 0.5)),
            ),
            child: Row(
              children: [
                // 1. Checkbox
                SizedBox(
                  width: 22,
                  child: Checkbox(
                    value: isChecked,
                    activeColor: c.primary,
                    checkColor: c.primaryText,
                    side: BorderSide(color: c.textMuted, width: 1),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
                    onChanged: (val) {
                      _setSelection(() {
                        if (val == true) {
                          _selectedPaths.add(file.fullPath);
                        } else {
                          _selectedPaths.remove(file.fullPath);
                        }
                      });
                    },
                  ),
                ),
                const SizedBox(width: 10),

                // 2. Name Column (flex: 7) - Thumbnail + Title + Subtitle Specs
                Expanded(
                  flex: 7,
                  child: Row(
                    children: [
                      // 16:9 Curved Thumbnail
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: SizedBox(
                          width: 88,
                          height: 50,
                          child: VideoThumbnailWidget(
                            videoPath: file.fullPath,
                            width: 88,
                            height: 50,
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),

                      // Text Block
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              file.basename,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: isSelected ? c.primary : c.textPrimary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '${file.category.name.toUpperCase()} • ${TimeFormatUtils.formatFileSize(file.sizeBytes)}',
                              style: TextStyle(
                                fontSize: 10,
                                color: c.textMuted,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // 3. Status Pill Badge Column (flex: 3)
                Expanded(
                  flex: 3,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: _buildStatusPill(file, isRunning),
                  ),
                ),

                // 4. Duration Column (65px)
                SizedBox(
                  width: 65,
                  child: ValueListenableBuilder<double?>(
                    valueListenable: ThumbnailService.instance.getDurationNotifier(file.fullPath),
                    builder: (context, durSec, _) {
                      final durFormatted = ThumbnailService.formatDuration(durSec);
                      return Text(
                        durFormatted,
                        style: TextStyle(
                          fontSize: 11,
                          color: c.textSecondary,
                          fontWeight: FontWeight.w400,
                        ),
                      );
                    },
                  ),
                ),

                // 5. Updated Column (75px)
                SizedBox(
                  width: 75,
                  child: Text(
                    updatedAgo,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textMuted,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),

                // 6. Action 3-dots Menu (36px)
                SizedBox(
                  width: 36,
                  child: PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, size: 16, color: AppColors.textSecondary),
                    offset: const Offset(0, 32),
                    color: AppColors.surfaceLight,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                      side: const BorderSide(color: AppColors.border),
                    ),
                    onSelected: (action) {
                      if (action == 'rename') {
                        widget.onRenameFile(file);
                      } else if (action == 'trim') {
                        widget.onOpenTrimmer(file);
                      } else if (action == 'delete') {
                        widget.onDeleteFile(file);
                      } else if (action == 'copy_path') {
                        Clipboard.setData(ClipboardData(text: file.fullPath));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('📋 Đã sao chép đường dẫn file!'),
                            backgroundColor: AppColors.statusCompleted,
                            duration: Duration(seconds: 1),
                          ),
                        );
                      }
                    },
                    itemBuilder: (ctx) => [
                      const PopupMenuItem(
                        value: 'rename',
                        child: Row(
                          children: [
                            Icon(Icons.drive_file_rename_outline, size: 14, color: AppColors.textSecondary),
                            SizedBox(width: 8),
                            Text('Đổi Tên Video', style: TextStyle(color: Colors.white, fontSize: 11.5)),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'trim',
                        child: Row(
                          children: [
                            Icon(Icons.content_cut, size: 14, color: AppColors.primary),
                            SizedBox(width: 8),
                            Text('Cắt Video (Trimmer)', style: TextStyle(color: Colors.white, fontSize: 11.5)),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'copy_path',
                        child: Row(
                          children: [
                            Icon(Icons.copy, size: 14, color: AppColors.info),
                            SizedBox(width: 8),
                            Text('Sao Chép Đường Dẫn', style: TextStyle(color: Colors.white, fontSize: 11.5)),
                          ],
                        ),
                      ),
                      const PopupMenuDivider(height: 1),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete_outline, size: 14, color: AppColors.statusFailed),
                            SizedBox(width: 8),
                            Text('Xóa Vĩnh Viễn', style: TextStyle(color: AppColors.statusFailed, fontSize: 11.5)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Status Pill Widget according to Image 2 design
  Widget _buildStatusPill(VideoFile file, bool isRunning) {
    if (isRunning) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.statusProcessingBg,
          borderRadius: BorderRadius.circular(5),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 8,
              height: 8,
              child: CircularProgressIndicator(strokeWidth: 1.2, color: AppColors.statusProcessing),
            ),
            SizedBox(width: 5),
            Text(
              'Processing',
              style: TextStyle(
                color: AppColors.statusProcessing,
                fontSize: 10.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    if (file.category == VideoCategory.output) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.statusCompletedBg,
          borderRadius: BorderRadius.circular(5),
        ),
        child: const Text(
          'Completed',
          style: TextStyle(
            color: AppColors.statusCompleted,
            fontSize: 10.5,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
    }

    // Default Ready status
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(5),
      ),
      child: const Text(
        'Ready',
        style: TextStyle(
          color: AppColors.statusCompleted,
          fontSize: 10.5,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildGridView(List<VideoFile> filtered) {
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 1.35,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: filtered.length,
      itemBuilder: (ctx, idx) {
        final file = filtered[idx];
        final isSelected = widget.selectedFile?.fullPath == file.fullPath;

        return InkWell(
          onTap: () => widget.onSelectFile(file),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            decoration: BoxDecoration(
              color: isSelected ? AppColors.surfaceLight : AppColors.surfaceDark,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isSelected ? AppColors.primary : AppColors.border,
                width: isSelected ? 1.5 : 1,
              ),
              boxShadow: const [
                BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2)),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Visual Thumbnail with Duration Overlay
                Expanded(
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(7)),
                    child: VideoThumbnailWidget(
                      videoPath: file.fullPath,
                      showDuration: true,
                      borderRadius: BorderRadius.zero,
                    ),
                  ),
                ),

                // Video Info
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        file.basename,
                        style: TextStyle(
                          fontSize: 12,
                          color: isSelected ? AppColors.primary : Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceLight,
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(
                              file.category.name.toUpperCase(),
                              style: const TextStyle(fontSize: 9, color: AppColors.textSecondary, fontWeight: FontWeight.bold),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            TimeFormatUtils.formatFileSize(file.sizeBytes),
                            style: const TextStyle(fontSize: 10.5, color: AppColors.textMuted),
                          ),
                          const Spacer(),
                          ValueListenableBuilder<double?>(
                            valueListenable: ThumbnailService.instance.getDurationNotifier(file.fullPath),
                            builder: (context, durSec, _) {
                              final durStr = ThumbnailService.formatDuration(durSec);
                              return Text(
                                durStr,
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 10.5,
                                  color: AppColors.textLight,
                                  fontWeight: FontWeight.w500,
                                ),
                              );
                            },
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
    );
  }

  Widget _buildBatchActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withOpacity(0.4), width: 1.0),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
