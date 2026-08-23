import 'package:flutter/material.dart';
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
  });

  @override
  State<AssetTableWidget> createState() => _AssetTableWidgetState();
}

class _AssetTableWidgetState extends State<AssetTableWidget> {
  bool _isGridView = false;
  String _searchQuery = '';
  final Set<String> _selectedPaths = {};

  @override
  Widget build(BuildContext context) {
    final filtered = widget.files.where((f) {
      if (_searchQuery.trim().isEmpty) return true;
      return f.basename.toLowerCase().contains(_searchQuery.toLowerCase().trim());
    }).toList();

    final allSelected = filtered.isNotEmpty && _selectedPaths.length == filtered.length;
    final selectedVideoFiles = widget.files.where((f) => _selectedPaths.contains(f.fullPath)).toList();

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A),
      ),
      child: Column(
        children: [
          // ── HEADER TOOLBAR ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Text(
                  'All Videos (${widget.files.length})',
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 6),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 15, color: Color(0xFF94A3B8)),
                  tooltip: 'Làm mới danh sách',
                  onPressed: widget.onRefresh,
                ),
                const Spacer(),

                // Search Box
                SizedBox(
                  width: 180,
                  height: 30,
                  child: TextField(
                    style: const TextStyle(fontSize: 11.5, color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Tìm kiếm video...',
                      hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 11),
                      prefixIcon: const Icon(Icons.search, size: 13, color: Color(0xFF64748B)),
                      contentPadding: EdgeInsets.zero,
                      filled: true,
                      fillColor: const Color(0xFF1E293B),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none),
                    ),
                    onChanged: (val) => setState(() => _searchQuery = val),
                  ),
                ),

                const SizedBox(width: 8),

                // View Toggle (Table / Grid)
                IconButton(
                  icon: Icon(_isGridView ? Icons.view_list : Icons.grid_view, size: 16, color: const Color(0xFF94A3B8)),
                  tooltip: _isGridView ? 'Chuyển sang dạng Bảng' : 'Chuyển sang dạng Lưới',
                  onPressed: () => setState(() => _isGridView = !_isGridView),
                ),
              ],
            ),
          ),

          // ── MAIN TABLE / GRID ──
          Expanded(
            child: filtered.isEmpty
                ? const Center(
                    child: Text('Không tìm thấy video nào trong thư mục này', style: TextStyle(color: Color(0xFF64748B), fontSize: 12)),
                  )
                : _isGridView
                    ? _buildGridView(filtered)
                    : _buildTableView(filtered, allSelected),
          ),

          // ── FLOATING BATCH ACTIONS BAR ──
          if (_selectedPaths.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: const BoxDecoration(
                color: Color(0xFF0B1120),
                border: Border(top: BorderSide(color: Color(0xFF1E293B))),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2563EB).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${_selectedPaths.length} video đã chọn',
                      style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 6),
                  TextButton.icon(
                    style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), minimumSize: Size.zero),
                    icon: const Icon(Icons.close, size: 12, color: Color(0xFF94A3B8)),
                    label: const Text('Bỏ chọn', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
                    onPressed: () => setState(() => _selectedPaths.clear()),
                  ),

                  const Spacer(),

                  // 1. Dịch Voice (N)
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2563EB),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      minimumSize: const Size(0, 28),
                    ),
                    icon: const Icon(Icons.mic, size: 13),
                    label: Text('Dịch Voice (${_selectedPaths.length})', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                    onPressed: () => widget.onBatchTranslateVoice?.call(selectedVideoFiles),
                  ),
                  const SizedBox(width: 6),

                  // 2. Dịch Sub (N)
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF059669),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      minimumSize: const Size(0, 28),
                    ),
                    icon: const Icon(Icons.subtitles, size: 13),
                    label: Text('Dịch Sub (${_selectedPaths.length})', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                    onPressed: () => widget.onBatchTranslateSub?.call(selectedVideoFiles),
                  ),
                  const SizedBox(width: 6),

                  // 3. Upload Cloud
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFC084FC),
                      side: const BorderSide(color: Color(0xFFC084FC)),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      minimumSize: const Size(0, 28),
                    ),
                    icon: const Icon(Icons.cloud_upload, size: 13),
                    label: Text('Upload Cloud (${_selectedPaths.length})', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
                    onPressed: () => widget.onBatchUploadCloud?.call(selectedVideoFiles),
                  ),
                  const SizedBox(width: 6),

                  // 4. Download Cloud
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF38BDF8),
                      side: const BorderSide(color: Color(0xFF38BDF8)),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      minimumSize: const Size(0, 28),
                    ),
                    icon: const Icon(Icons.cloud_download, size: 13),
                    label: Text('Download (${_selectedPaths.length})', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
                    onPressed: () => widget.onBatchSyncDown?.call(selectedVideoFiles),
                  ),
                  const SizedBox(width: 6),

                  // 5. Offload SSD
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFF59E0B),
                      side: const BorderSide(color: Color(0xFFF59E0B)),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      minimumSize: const Size(0, 28),
                    ),
                    icon: const Icon(Icons.cleaning_services, size: 13),
                    label: Text('Offload SSD (${_selectedPaths.length})', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
                    onPressed: () => widget.onBatchOffload?.call(selectedVideoFiles),
                  ),
                  const SizedBox(width: 6),

                  // 6. Delete All
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFEF4444),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      minimumSize: const Size(0, 28),
                    ),
                    icon: const Icon(Icons.delete_forever, size: 13),
                    label: Text('Xóa Tất Cả (${_selectedPaths.length})', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                    onPressed: () => widget.onBatchDelete?.call(selectedVideoFiles),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTableView(List<VideoFile> filtered, bool allSelected) {
    return ListView.builder(
      itemCount: filtered.length + 1,
      itemBuilder: (ctx, idx) {
        if (idx == 0) {
          // Table Header
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: const BoxDecoration(
              color: Color(0xFF0B1120),
              border: Border(bottom: BorderSide(color: Color(0xFF1E293B))),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 28,
                  child: Checkbox(
                    value: allSelected,
                    onChanged: (val) {
                      setState(() {
                        if (val == true) {
                          _selectedPaths.addAll(filtered.map((f) => f.fullPath));
                        } else {
                          _selectedPaths.clear();
                        }
                      });
                    },
                  ),
                ),
                const SizedBox(width: 8),
                const SizedBox(width: 44, child: Text('Preview', style: TextStyle(color: Color(0xFF64748B), fontSize: 11, fontWeight: FontWeight.bold))),
                const SizedBox(width: 12),
                const Expanded(flex: 4, child: Text('Name', style: TextStyle(color: Color(0xFF64748B), fontSize: 11, fontWeight: FontWeight.bold))),
                const Expanded(flex: 2, child: Text('Category', style: TextStyle(color: Color(0xFF64748B), fontSize: 11, fontWeight: FontWeight.bold))),
                const Expanded(flex: 2, child: Text('Duration', style: TextStyle(color: Color(0xFF64748B), fontSize: 11, fontWeight: FontWeight.bold))),
                const Expanded(flex: 2, child: Text('Size', style: TextStyle(color: Color(0xFF64748B), fontSize: 11, fontWeight: FontWeight.bold))),
                const Expanded(flex: 2, child: Text('Status', style: TextStyle(color: Color(0xFF64748B), fontSize: 11, fontWeight: FontWeight.bold))),
                const SizedBox(width: 70, child: Center(child: Text('Actions', style: TextStyle(color: Color(0xFF64748B), fontSize: 11, fontWeight: FontWeight.bold)))),
              ],
            ),
          );
        }

        final file = filtered[idx - 1];
        final isSelected = widget.selectedFile?.fullPath == file.fullPath;
        final isChecked = _selectedPaths.contains(file.fullPath);
        final isRunning = widget.runningRelPaths.any((p) => p.contains(file.stem) || file.fullPath.contains(p));

        return InkWell(
          onTap: () => widget.onSelectFile(file),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: isSelected ? const Color(0xFF1E293B) : Colors.transparent,
              border: const Border(bottom: BorderSide(color: Color(0xFF1E293B), width: 0.5)),
            ),
            child: Row(
              children: [
                // Checkbox
                SizedBox(
                  width: 28,
                  child: Checkbox(
                    value: isChecked,
                    onChanged: (val) {
                      setState(() {
                        if (val == true) {
                          _selectedPaths.add(file.fullPath);
                        } else {
                          _selectedPaths.remove(file.fullPath);
                        }
                      });
                    },
                  ),
                ),
                const SizedBox(width: 8),

                // Mini Thumbnail
                SizedBox(
                  width: 44,
                  height: 28,
                  child: VideoThumbnailWidget(
                    videoPath: file.fullPath,
                    width: 44,
                    height: 28,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(width: 12),

                // Name & Tags
                Expanded(
                  flex: 4,
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          file.basename,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            color: isSelected ? Colors.white : const Color(0xFFCBD5E1),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (file.category == VideoCategory.output) ...[
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(color: const Color(0xFF10B981).withOpacity(0.2), borderRadius: BorderRadius.circular(3)),
                          child: const Text('VI', style: TextStyle(color: Color(0xFF10B981), fontSize: 8.5, fontWeight: FontWeight.bold)),
                        ),
                      ],
                      if (file.category == VideoCategory.cut) ...[
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(color: const Color(0xFF06B6D4).withOpacity(0.2), borderRadius: BorderRadius.circular(3)),
                          child: const Text('CUT', style: TextStyle(color: Color(0xFF06B6D4), fontSize: 8.5, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ],
                  ),
                ),

                // Category
                Expanded(
                  flex: 2,
                  child: Text(
                    file.category.name.toUpperCase(),
                    style: const TextStyle(fontSize: 10.5, color: Color(0xFF64748B)),
                  ),
                ),

                // Duration Column
                Expanded(
                  flex: 2,
                  child: ValueListenableBuilder<double?>(
                    valueListenable: ThumbnailService.instance.getDurationNotifier(file.fullPath),
                    builder: (context, durSec, _) {
                      final durFormatted = ThumbnailService.formatDuration(durSec);
                      return Row(
                        children: [
                          const Icon(Icons.schedule, size: 12, color: Color(0xFF94A3B8)),
                          const SizedBox(width: 4),
                          Text(
                            durFormatted,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11,
                              color: Color(0xFFE2E8F0),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),

                // Size
                Expanded(
                  flex: 2,
                  child: Text(
                    TimeFormatUtils.formatFileSize(file.sizeBytes),
                    style: const TextStyle(fontSize: 11, color: Color(0xFF38BDF8), fontWeight: FontWeight.w600),
                  ),
                ),

                // Status Badge
                Expanded(
                  flex: 2,
                  child: isRunning
                      ? const Row(
                          children: [
                            SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 1.5, color: Color(0xFF06B6D4))),
                            SizedBox(width: 4),
                            Text('Running', style: TextStyle(color: Color(0xFF06B6D4), fontSize: 10, fontWeight: FontWeight.bold)),
                          ],
                        )
                      : Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981).withOpacity(0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text('Ready', style: TextStyle(color: Color(0xFF10B981), fontSize: 9.5, fontWeight: FontWeight.bold)),
                        ),
                ),

                // Actions
                SizedBox(
                  width: 70,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.drive_file_rename_outline, size: 14, color: Color(0xFF94A3B8)),
                        tooltip: 'Đổi tên',
                        onPressed: () => widget.onRenameFile(file),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 14, color: Color(0xFFEF4444)),
                        tooltip: 'Xóa video',
                        onPressed: () => widget.onDeleteFile(file),
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

  Widget _buildGridView(List<VideoFile> filtered) {
    return GridView.builder(
      padding: const EdgeInsets.all(10),
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
              color: isSelected ? const Color(0xFF1E293B) : const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isSelected ? const Color(0xFF06B6D4) : const Color(0xFF1E293B),
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
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        file.basename,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: isSelected ? const Color(0xFF38BDF8) : Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: const Color(0xFF334155),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(
                              file.category.name.toUpperCase(),
                              style: const TextStyle(fontSize: 8.5, color: Color(0xFF94A3B8), fontWeight: FontWeight.bold),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            TimeFormatUtils.formatFileSize(file.sizeBytes),
                            style: const TextStyle(fontSize: 10, color: Color(0xFF64748B)),
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
                                  fontSize: 10,
                                  color: Color(0xFF38BDF8),
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
}
