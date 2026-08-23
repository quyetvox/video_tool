import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/providers.dart';
import '../core/python_bridge.dart';
import '../core/cloud_storage_state.dart';
import '../models/cloud_item.dart';
import '../widgets/gcs_config_dialog.dart';
import '../widgets/confirm_dialog.dart';
import '../utils/time_format_utils.dart';

class CloudStorageScreen extends ConsumerWidget {
  const CloudStorageScreen({super.key});

  void _openGcsConfig(BuildContext context, WidgetRef ref) async {
    final cloudState = ref.read(cloudStorageProvider);
    final config = ref.read(configProvider);
    final changed = await GcsConfigDialog.show(
      context,
      initialKeyPath: config.storageKeyFile.isNotEmpty ? config.storageKeyFile : 'assets/gcs-key.json',
      initialBucket: cloudState.bucketName,
      initialPrefix: cloudState.basePrefix,
      onSave: (key, bucket, prefix) {
        ref.read(configProvider.notifier).setField((c) => c.copyWith(
              storageKeyFile: key,
              storageBucketName: bucket,
              storageBasePrefix: prefix,
            ));
      },
    );

    if (changed == true) {
      ref.read(cloudStorageProvider.notifier).invalidateAll();
    }
  }

  // ── CONFIRM ACTIONS: SYNC-DOWN, SYNC-UP, OFFLOAD, DELETE ──

  void _confirmAndSyncDown(BuildContext context, WidgetRef ref, CloudItem item, String currentPath) async {
    final ok = await ConfirmDialog.show(
      context,
      title: 'Đồng bộ ${item.isFolder ? "thư mục" : "tệp"} về Local?',
      message: 'Tải "${item.name}" (${item.sizeStr}) từ Google Cloud Storage về máy Mac?',
      confirmText: 'Đồng bộ về máy',
      icon: Icons.cloud_download,
    );
    if (!ok) return;

    final project = currentPath.isNotEmpty ? currentPath.split('/').first : item.name;
    final files = item.isFolder ? null : [item.path.replaceFirst('$project/', '')];

    final args = ['sync-down', project];
    if (files != null) {
      args.add('--files');
      args.addAll(files);
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('⬇️ Đang kéo ${item.name} từ Cloud về máy...'), duration: const Duration(seconds: 2)),
      );
    }

    final res = await PythonBridge.runScript('storage.py', args, jobId: 'sync_down_${item.name}');
    if (res.success) {
      ref.invalidate(projectVideosProvider);
      ref.read(cloudStorageProvider.notifier).invalidatePath(currentPath);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('✅ Đã đồng bộ ${item.name} về máy Mac thành công!'), backgroundColor: const Color(0xFF10B981)),
        );
      }
    }
  }

  void _confirmAndSyncUp(BuildContext context, WidgetRef ref, CloudItem item, String currentPath) async {
    final ok = await ConfirmDialog.show(
      context,
      title: 'Đẩy ${item.isFolder ? "thư mục" : "tệp"} lên Cloud?',
      message: 'Tải "${item.name}" (${item.sizeStr}) từ Local máy Mac lên Google Cloud Storage?',
      confirmText: 'Tải lên Cloud',
      icon: Icons.cloud_upload,
    );
    if (!ok) return;

    final project = currentPath.isNotEmpty ? currentPath.split('/').first : item.name;
    final files = item.isFolder ? null : [item.path.replaceFirst('$project/', '')];

    final args = ['sync-up', project];
    if (files != null) {
      args.add('--files');
      args.addAll(files);
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('☁️ Đang tải ${item.name} lên Google Cloud...'), duration: const Duration(seconds: 2)),
      );
    }

    final res = await PythonBridge.runScript('storage.py', args, jobId: 'sync_up_${item.name}');
    if (res.success) {
      ref.read(cloudStorageProvider.notifier).invalidatePath(currentPath);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('✅ Đã tải ${item.name} lên Google Cloud thành công!'), backgroundColor: const Color(0xFF10B981)),
        );
      }
    }
  }

  void _confirmAndOffload(BuildContext context, WidgetRef ref, CloudItem item, String currentPath) async {
    final ok = await ConfirmDialog.show(
      context,
      title: 'Giải phóng dung lượng SSD?',
      message: 'Xóa bản sao local của "${item.name}" (${item.sizeStr}) trên SSD máy Mac?\n\nBản sao trên Google Cloud Storage vẫn được bảo toàn 100%.',
      confirmText: 'Giải phóng SSD',
      icon: Icons.cleaning_services,
    );
    if (!ok) return;

    final project = currentPath.isNotEmpty ? currentPath.split('/').first : item.name;
    final files = item.isFolder ? null : [item.path.replaceFirst('$project/', '')];

    final args = ['offload', project];
    if (files != null) {
      args.add('--files');
      args.addAll(files);
    }

    final res = await PythonBridge.runScript('storage.py', args, jobId: 'offload_${item.name}');
    if (res.success) {
      ref.invalidate(projectVideosProvider);
      ref.read(cloudStorageProvider.notifier).invalidatePath(currentPath);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('🧹 Đã giải phóng SSD cho ${item.name} an toàn!'), backgroundColor: const Color(0xFF10B981)),
        );
      }
    }
  }

  void _confirmAndDelete(BuildContext context, WidgetRef ref, CloudItem item, String currentPath) async {
    final ok = await ConfirmDialog.show(
      context,
      title: 'Xóa vĩnh viễn trên Cloud?',
      message: 'Bạn có chắc chắn muốn xóa vĩnh viễn "${item.name}" khỏi Google Cloud Storage?\n\n⚠️ Thao tác này không thể hoàn tác!',
      confirmText: 'Xóa Vĩnh Viễn',
      isDestructive: true,
    );
    if (!ok) return;

    final project = currentPath.isNotEmpty ? currentPath.split('/').first : item.name;
    final files = item.isFolder ? null : [item.path.replaceFirst('$project/', '')];
    if (files == null) return;

    final args = ['delete-cloud', project, '--files', ...files];
    final res = await PythonBridge.runScript('storage.py', args, jobId: 'del_cloud_${item.name}');
    if (res.success) {
      ref.read(cloudStorageProvider.notifier).invalidatePath(currentPath);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('🗑️ Đã xóa ${item.name} khỏi Google Cloud Storage!'), backgroundColor: const Color(0xFF10B981)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cloudState = ref.watch(cloudStorageProvider);
    final cloudNotifier = ref.read(cloudStorageProvider.notifier);

    final filteredItems = cloudState.filteredItems;

    // Compute total size of filtered items
    int totalSizeBytes = 0;
    for (final it in filteredItems) {
      totalSizeBytes += it.sizeBytes;
    }
    final totalSizeStr = TimeFormatUtils.formatFileSize(totalSizeBytes);

    return Scaffold(
      backgroundColor: const Color(0xFF0B1120),
      body: Column(
        children: [
          // ── 1. TOP HEADER BAR ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: const BoxDecoration(
              color: Color(0xFF0F172A),
              border: Border(bottom: BorderSide(color: Color(0xFF1E293B))),
            ),
            child: Row(
              children: [
                const Icon(Icons.cloud_done, color: Color(0xFF06B6D4), size: 18),
                const SizedBox(width: 8),
                const Text(
                  'Google Cloud Storage (GCS)',
                  style: TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 8),

                // Connection Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                  decoration: BoxDecoration(
                    color: cloudState.isConnected ? const Color(0xFF10B981).withOpacity(0.15) : const Color(0xFFEF4444).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: cloudState.isConnected ? const Color(0xFF10B981).withOpacity(0.3) : const Color(0xFFEF4444).withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: cloudState.isConnected ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        cloudState.isConnected ? 'Đã kết nối (gs://${cloudState.bucketName})' : 'Chưa Kết Nối (Cần gcs-key.json)',
                        style: TextStyle(
                          color: cloudState.isConnected ? const Color(0xFF34D399) : const Color(0xFFFCA5A5),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),

                const Spacer(),

                // Top Actions: Sync-Up, Sync-Down
                InkWell(
                  onTap: () {
                    final activeProject = ref.read(activeProjectProvider) ?? 'default';
                    _confirmAndSyncUp(context, ref, CloudItem(id: activeProject, name: activeProject, path: activeProject, type: 'folder', isFolder: true, sizeStr: '', modifiedStr: ''), '');
                  },
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    height: 28,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6366F1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.cloud_upload, size: 13, color: Colors.white),
                        SizedBox(width: 6),
                        Text('Tải lên (Sync-Up)', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Colors.white)),
                      ],
                    ),
                  ),
                ),

                const SizedBox(width: 8),

                InkWell(
                  onTap: () {
                    final activeProject = ref.read(activeProjectProvider) ?? 'default';
                    _confirmAndSyncDown(context, ref, CloudItem(id: activeProject, name: activeProject, path: activeProject, type: 'folder', isFolder: true, sizeStr: '', modifiedStr: ''), '');
                  },
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    height: 28,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFF334155), width: 1.0),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.cloud_download, size: 13, color: Colors.white),
                        SizedBox(width: 6),
                        Text('Đồng bộ về local', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Colors.white)),
                      ],
                    ),
                  ),
                ),

                const SizedBox(width: 12),

                // Settings Button (GCS Key & Bucket Configuration)
                IconButton(
                  icon: const Icon(Icons.settings, size: 16, color: Color(0xFF94A3B8)),
                  tooltip: 'Cấu hình Service Account Key GCS',
                  onPressed: () => _openGcsConfig(context, ref),
                ),

                // Refresh Button
                IconButton(
                  icon: cloudState.isLoading
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF06B6D4)))
                      : const Icon(Icons.refresh, size: 16, color: Color(0xFF94A3B8)),
                  tooltip: 'Làm mới danh mục Cloud',
                  onPressed: cloudState.isLoading ? null : () => cloudNotifier.refreshCurrent(),
                ),
              ],
            ),
          ),

          // ── 2. MAIN 3-COLUMN LAYOUT ──
          Expanded(
            child: Row(
              children: [
                // ── LEFT FILTER & SHORTCUT COLUMN (230px) ──
                Container(
                  width: 230,
                  decoration: const BoxDecoration(
                    color: Color(0xFF0B1120),
                    border: Border(right: BorderSide(color: Color(0xFF1E293B))),
                  ),
                  child: _buildFilterSidebar(context, ref, cloudState, cloudNotifier),
                ),

                // ── CENTER BROWSER TABLE (Expanded) ──
                Expanded(
                  child: Column(
                    children: [
                      // Breadcrumb Bar & Search
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                        decoration: const BoxDecoration(
                          color: Color(0xFF0F172A),
                          border: Border(bottom: BorderSide(color: Color(0xFF1E293B))),
                        ),
                        child: Row(
                          children: [
                            if (cloudState.currentPath.isNotEmpty) ...[
                              IconButton(
                                icon: const Icon(Icons.arrow_back, size: 15, color: Color(0xFF06B6D4)),
                                tooltip: 'Quay lại thư mục cha',
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                onPressed: () => cloudNotifier.navigateUp(),
                              ),
                              const SizedBox(width: 10),
                            ],

                            // Breadcrumb Path
                            Expanded(
                              child: _buildBreadcrumbs(cloudState, cloudNotifier),
                            ),

                            // Copy GCS URI Button
                            IconButton(
                              icon: const Icon(Icons.copy, size: 13, color: Color(0xFF64748B)),
                              tooltip: 'Sao chép đường dẫn GCS',
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: () {
                                final uri = 'gs://${cloudState.bucketName}/${cloudState.basePrefix}/${cloudState.currentPath}'.replaceAll(RegExp(r'/+$'), '');
                                Clipboard.setData(ClipboardData(text: uri));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('📋 Đã sao chép: $uri'), duration: const Duration(seconds: 1)),
                                );
                              },
                            ),

                            const SizedBox(width: 12),

                            // Search Input
                            SizedBox(
                              width: 180,
                              height: 28,
                              child: TextField(
                                style: const TextStyle(fontSize: 11.5, color: Colors.white),
                                decoration: InputDecoration(
                                  hintText: 'Tìm trong thư mục...',
                                  hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 11),
                                  prefixIcon: const Icon(Icons.search, size: 13, color: Color(0xFF64748B)),
                                  contentPadding: EdgeInsets.zero,
                                  filled: true,
                                  fillColor: const Color(0xFF1E293B),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none),
                                ),
                                onChanged: (val) => cloudNotifier.setSearchQuery(val),
                              ),
                            ),

                            const SizedBox(width: 8),

                            // Table / Grid Toggle
                            IconButton(
                              icon: Icon(cloudState.isGridView ? Icons.view_list : Icons.grid_view, size: 15, color: const Color(0xFF94A3B8)),
                              tooltip: cloudState.isGridView ? 'Dạng bảng' : 'Dạng lưới',
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: () => cloudNotifier.toggleViewMode(),
                            ),
                          ],
                        ),
                      ),

                      // Table View or Grid View
                      Expanded(
                        child: cloudState.isLoading
                            ? const Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF06B6D4)),
                                    SizedBox(height: 10),
                                    Text('Đang duyệt tệp Google Cloud Storage...', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
                                  ],
                                ),
                              )
                            : filteredItems.isEmpty
                                ? Center(
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        const Icon(Icons.cloud_off, size: 40, color: Color(0xFF334155)),
                                        const SizedBox(height: 8),
                                        Text(
                                          cloudState.isConnected ? 'Thư mục này trống trên Cloud' : 'Chưa kết nối được Google Cloud Storage',
                                          style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12.5),
                                        ),
                                        const SizedBox(height: 8),
                                        if (!cloudState.isConnected)
                                          ElevatedButton.icon(
                                            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2563EB)),
                                            icon: const Icon(Icons.settings, size: 14),
                                            label: const Text('Cấu Hình gcs-key.json Ngay', style: TextStyle(fontSize: 11)),
                                            onPressed: () => _openGcsConfig(context, ref),
                                          ),
                                      ],
                                    ),
                                  )
                                : cloudState.isGridView
                                    ? _buildGridView(context, ref, filteredItems, cloudState, cloudNotifier)
                                    : _buildTableView(context, ref, filteredItems, cloudState, cloudNotifier),
                      ),

                      // Bottom Pagination Bar
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: const BoxDecoration(
                          color: Color(0xFF0F172A),
                          border: Border(top: BorderSide(color: Color(0xFF1E293B))),
                        ),
                        child: Row(
                          children: [
                            Text(
                              'Hiển thị 1 - ${filteredItems.length} trong ${filteredItems.length} mục ($totalSizeStr)',
                              style: const TextStyle(color: Color(0xFF64748B), fontSize: 11),
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1E293B),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text('20 / trang', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
                            ),
                            const SizedBox(width: 8),
                            const Icon(Icons.chevron_left, size: 16, color: Color(0xFF64748B)),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF2563EB),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text('1', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                            ),
                            const Icon(Icons.chevron_right, size: 16, color: Color(0xFF64748B)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // ── RIGHT INSPECTOR DETAIL PANEL (280px) ──
                Container(
                  width: 280,
                  decoration: const BoxDecoration(
                    color: Color(0xFF0F172A),
                    border: Border(left: BorderSide(color: Color(0xFF1E293B))),
                  ),
                  child: _buildInspectorPanel(context, ref, cloudState),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── LEFT FILTER SIDEBAR ──
  Widget _buildFilterSidebar(BuildContext context, WidgetRef ref, CloudStorageState state, CloudStorageNotifier notifier) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // 1. Storage Bucket Card
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF1E293B)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.storage, size: 14, color: Color(0xFF06B6D4)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      state.bucketName,
                      style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: state.isConnected ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Thư mục gốc: ${state.basePrefix}',
                style: const TextStyle(color: Color(0xFF64748B), fontSize: 10),
              ),
              const SizedBox(height: 2),
              const Text(
                'Vị trí: asia-southeast1',
                style: TextStyle(color: Color(0xFF64748B), fontSize: 10),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // 2. Filters Section Header
        const Text(
          'BỘ LỌC',
          style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5),
        ),
        const SizedBox(height: 10),

        // Filter: Loại tệp
        _buildFilterDropdown(
          label: 'Loại tệp',
          value: state.filterType,
          items: const [
            DropdownMenuItem(value: 'all', child: Text('Tất cả')),
            DropdownMenuItem(value: 'video', child: Text('Video (.mp4, .mkv)')),
            DropdownMenuItem(value: 'audio', child: Text('Audio (.wav, .mp3)')),
            DropdownMenuItem(value: 'subtitle', child: Text('Phụ đề (.srt, .ass)')),
            DropdownMenuItem(value: 'document', child: Text('Tài liệu / JSON')),
            DropdownMenuItem(value: 'folder', child: Text('Thư mục (Folder)')),
          ],
          onChanged: (v) => notifier.setFilterType(v ?? 'all'),
        ),

        const SizedBox(height: 8),

        // Filter: Trạng thái
        _buildFilterDropdown(
          label: 'Trạng thái',
          value: state.filterStatus,
          items: const [
            DropdownMenuItem(value: 'all', child: Text('Tất cả trạng thái')),
            DropdownMenuItem(value: 'synced', child: Text('🔄 Đã đồng bộ')),
            DropdownMenuItem(value: 'cloud_only', child: Text('☁️ Chỉ trên Cloud')),
            DropdownMenuItem(value: 'local_only', child: Text('💻 Chỉ trên Local')),
            DropdownMenuItem(value: 'modified', child: Text('⚠️ Đã chỉnh sửa')),
          ],
          onChanged: (v) => notifier.setFilterStatus(v ?? 'all'),
        ),

        const SizedBox(height: 8),

        // Filter: Kích thước
        _buildFilterDropdown(
          label: 'Kích thước',
          value: state.filterSize,
          items: const [
            DropdownMenuItem(value: 'all', child: Text('Tất cả kích thước')),
            DropdownMenuItem(value: '<10mb', child: Text('< 10 MB')),
            DropdownMenuItem(value: '10mb-100mb', child: Text('10 MB - 100 MB')),
            DropdownMenuItem(value: '100mb-1gb', child: Text('100 MB - 1 GB')),
            DropdownMenuItem(value: '>1gb', child: Text('> 1 GB')),
          ],
          onChanged: (v) => notifier.setFilterSize(v ?? 'all'),
        ),

        const SizedBox(height: 8),

        // Filter: Ngày tải lên
        _buildFilterDropdown(
          label: 'Ngày tải lên',
          value: state.filterDate,
          items: const [
            DropdownMenuItem(value: 'all', child: Text('Tất cả thời gian')),
            DropdownMenuItem(value: 'today', child: Text('Hôm nay')),
            DropdownMenuItem(value: '7days', child: Text('7 ngày qua')),
            DropdownMenuItem(value: '30days', child: Text('30 ngày qua')),
          ],
          onChanged: (v) => notifier.setFilterDate(v ?? 'all'),
        ),

        const SizedBox(height: 10),

        // Reset Filter Button
        InkWell(
          onTap: () => notifier.resetFilters(),
          borderRadius: BorderRadius.circular(6),
          child: Container(
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFF334155), width: 1.0),
            ),
            child: const Text('Đặt lại bộ lọc', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11.5, fontWeight: FontWeight.w600)),
          ),
        ),

        const SizedBox(height: 20),

        // 3. Quick Actions Header
        const Text(
          'HÀNH ĐỘNG NHANH',
          style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5),
        ),
        const SizedBox(height: 8),

        _buildQuickActionButton(
          icon: Icons.create_new_folder,
          label: 'Tạo folder mới',
          iconColor: const Color(0xFF38BDF8),
          onTap: () async {
            // Prompt dialog for new folder name
            final ctrl = TextEditingController();
            final name = await showDialog<String>(
              context: context,
              builder: (ctx) => AlertDialog(
                backgroundColor: const Color(0xFF0F172A),
                title: const Text('Tạo thư mục mới trên Cloud', style: TextStyle(color: Colors.white, fontSize: 14)),
                content: TextField(
                  controller: ctrl,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                  decoration: const InputDecoration(hintText: 'Tên thư mục...', hintStyle: TextStyle(color: Color(0xFF64748B))),
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
                  ElevatedButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Tạo')),
                ],
              ),
            );
            if (name != null && name.isNotEmpty) {
              final activeProject = ref.read(activeProjectProvider) ?? 'default';
              final res = await PythonBridge.runCode('''
from lib.utils.storage_manager import StorageManager
mgr = StorageManager('$activeProject')
mgr.create_folder('${state.currentPath}/$name')
print('ok')
''');
              if (res.exitCode == 0) {
                notifier.refreshCurrent();
              }
            }
          },
        ),

        _buildQuickActionButton(
          icon: Icons.cloud_upload,
          label: 'Đẩy dự án lên GCS (Sync-Up)',
          iconColor: const Color(0xFFC084FC),
          onTap: () {
            final activeProject = ref.read(activeProjectProvider) ?? 'default';
            _confirmAndSyncUp(context, ref, CloudItem(id: activeProject, name: activeProject, path: activeProject, type: 'folder', isFolder: true, sizeStr: '', modifiedStr: ''), '');
          },
        ),

        _buildQuickActionButton(
          icon: Icons.cloud_download,
          label: 'Kéo dự án về Local (Sync-Down)',
          iconColor: const Color(0xFF38BDF8),
          onTap: () {
            final activeProject = ref.read(activeProjectProvider) ?? 'default';
            _confirmAndSyncDown(context, ref, CloudItem(id: activeProject, name: activeProject, path: activeProject, type: 'folder', isFolder: true, sizeStr: '', modifiedStr: ''), '');
          },
        ),

        _buildQuickActionButton(
          icon: Icons.cleaning_services,
          label: 'Giải phóng bộ nhớ SSD',
          iconColor: const Color(0xFFF59E0B),
          onTap: () {
            final activeProject = ref.read(activeProjectProvider) ?? 'default';
            _confirmAndOffload(context, ref, CloudItem(id: activeProject, name: activeProject, path: activeProject, type: 'folder', isFolder: true, sizeStr: '', modifiedStr: ''), '');
          },
        ),

        _buildQuickActionButton(
          icon: Icons.refresh,
          label: 'Làm mới danh mục',
          iconColor: const Color(0xFF34D399),
          onTap: () => notifier.refreshCurrent(),
        ),
      ],
    );
  }

  Widget _buildFilterDropdown({
    required String label,
    required String value,
    required List<DropdownMenuItem<String>> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Color(0xFF64748B), fontSize: 10.5, fontWeight: FontWeight.w500)),
        const SizedBox(height: 3),
        Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: const Color(0xFF1E293B)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              dropdownColor: const Color(0xFF0F172A),
              style: const TextStyle(color: Colors.white, fontSize: 11),
              icon: const Icon(Icons.arrow_drop_down, size: 16, color: Color(0xFF64748B)),
              items: items,
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildQuickActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color iconColor = const Color(0xFF06B6D4),
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: const Color(0xFF1E293B), width: 1.0),
          ),
          child: Row(
            children: [
              Icon(icon, size: 13.5, color: iconColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 11, fontWeight: FontWeight.w500),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── BREADCRUMBS WIDGET ──
  Widget _buildBreadcrumbs(CloudStorageState state, CloudStorageNotifier notifier) {
    final List<Widget> crumbs = [];

    // Root crumb
    crumbs.add(
      InkWell(
        onTap: () => notifier.loadBrowse(''),
        child: Row(
          children: [
            const Icon(Icons.home, size: 13, color: Color(0xFF06B6D4)),
            const SizedBox(width: 4),
            Text(
              state.bucketName,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: state.currentPath.isEmpty ? FontWeight.bold : FontWeight.normal,
                color: state.currentPath.isEmpty ? Colors.white : const Color(0xFF06B6D4),
              ),
            ),
          ],
        ),
      ),
    );

    crumbs.add(const Padding(
      padding: EdgeInsets.symmetric(horizontal: 4),
      child: Text('/', style: TextStyle(color: Color(0xFF64748B), fontSize: 11)),
    ));

    crumbs.add(
      InkWell(
        onTap: () => notifier.loadBrowse(''),
        child: Text(
          state.basePrefix,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: state.currentPath.isEmpty ? FontWeight.bold : FontWeight.normal,
            color: state.currentPath.isEmpty ? Colors.white : const Color(0xFF06B6D4),
          ),
        ),
      ),
    );

    if (state.currentPath.isNotEmpty) {
      final parts = state.currentPath.split('/');
      String accumulated = '';
      for (int i = 0; i < parts.length; i++) {
        accumulated = accumulated.isEmpty ? parts[i] : '$accumulated/${parts[i]}';
        final isLast = i == parts.length - 1;
        final targetPath = accumulated;

        crumbs.add(const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4),
          child: Text('/', style: TextStyle(color: Color(0xFF64748B), fontSize: 11)),
        ));

        crumbs.add(
          InkWell(
            onTap: isLast ? null : () => notifier.loadBrowse(targetPath),
            child: Text(
              parts[i],
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: isLast ? FontWeight.bold : FontWeight.normal,
                color: isLast ? Colors.white : const Color(0xFF06B6D4),
              ),
            ),
          ),
        );
      }
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: crumbs),
    );
  }

  // ── TABLE VIEW ──
  Widget _buildTableView(BuildContext context, WidgetRef ref, List<CloudItem> items, CloudStorageState state, CloudStorageNotifier notifier) {
    final isAllSelected = items.isNotEmpty && items.every((e) => state.selectedPaths.contains(e.path));

    return ListView.builder(
      itemCount: items.length + 1,
      itemBuilder: (ctx, idx) {
        if (idx == 0) {
          // Table Header
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: const BoxDecoration(
              color: Color(0xFF0B1120),
              border: Border(bottom: BorderSide(color: Color(0xFF1E293B))),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 24,
                  child: Checkbox(
                    value: isAllSelected,
                    onChanged: (val) => notifier.selectAllPaths(val ?? false),
                    activeColor: const Color(0xFF2563EB),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
                const SizedBox(width: 8),
                const Expanded(flex: 4, child: Text('TÊN', style: TextStyle(color: Color(0xFF64748B), fontSize: 10.5, fontWeight: FontWeight.bold))),
                const Expanded(flex: 2, child: Text('LOẠI', style: TextStyle(color: Color(0xFF64748B), fontSize: 10.5, fontWeight: FontWeight.bold))),
                const Expanded(flex: 2, child: Text('KÍCH THƯỚC', style: TextStyle(color: Color(0xFF64748B), fontSize: 10.5, fontWeight: FontWeight.bold))),
                const Expanded(flex: 2, child: Text('TRẠNG THÁI', style: TextStyle(color: Color(0xFF64748B), fontSize: 10.5, fontWeight: FontWeight.bold))),
                const Expanded(flex: 2, child: Text('NGÀY SỬA ĐỔI', style: TextStyle(color: Color(0xFF64748B), fontSize: 10.5, fontWeight: FontWeight.bold))),
                const SizedBox(width: 110, child: Text('THAO TÁC', style: TextStyle(color: Color(0xFF64748B), fontSize: 10.5, fontWeight: FontWeight.bold))),
              ],
            ),
          );
        }

        final item = items[idx - 1];
        final isSelected = state.selectedItem?.path == item.path;
        final isChecked = state.selectedPaths.contains(item.path);

        return InkWell(
          onTap: () => notifier.selectItem(item),
          onDoubleTap: () => notifier.navigateInto(item),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: isSelected ? const Color(0xFF1E293B) : Colors.transparent,
              border: const Border(bottom: BorderSide(color: Color(0xFF1E293B), width: 0.5)),
            ),
            child: Row(
              children: [
                // Checkbox
                SizedBox(
                  width: 24,
                  child: Checkbox(
                    value: isChecked,
                    onChanged: (val) => notifier.toggleSelectPath(item.path),
                    activeColor: const Color(0xFF2563EB),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
                const SizedBox(width: 8),

                // Name & Icon
                Expanded(
                  flex: 4,
                  child: Row(
                    children: [
                      Icon(
                        item.isFolder
                            ? Icons.folder
                            : (item.isVideo ? Icons.videocam : (item.ext == 'json' ? Icons.code : Icons.insert_drive_file)),
                        size: 15,
                        color: item.isFolder
                            ? const Color(0xFFF59E0B)
                            : (item.isVideo ? const Color(0xFF06B6D4) : const Color(0xFF94A3B8)),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          item.name,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: isSelected || item.isFolder ? FontWeight.bold : FontWeight.normal,
                            color: isSelected ? Colors.white : const Color(0xFFCBD5E1),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),

                // Type
                Expanded(
                  flex: 2,
                  child: Text(
                    item.isFolder ? 'Folder' : item.ext.toUpperCase(),
                    style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                  ),
                ),

                // Size
                Expanded(
                  flex: 2,
                  child: Text(
                    item.sizeStr,
                    style: const TextStyle(fontSize: 11, color: Color(0xFF38BDF8), fontWeight: FontWeight.w600),
                  ),
                ),

                // Sync Status Badge
                Expanded(
                  flex: 2,
                  child: _buildStatusBadge(item),
                ),

                // Modified Date
                Expanded(
                  flex: 2,
                  child: Text(
                    item.modifiedStr,
                    style: const TextStyle(fontSize: 10.5, color: Color(0xFF64748B)),
                  ),
                ),

                // Per-Row 4 Action Icons (Sync-Up, Sync-Down, Offload, Delete)
                SizedBox(
                  width: 110,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // ☁️ Sync-Up
                      IconButton(
                        icon: const Icon(Icons.cloud_upload, size: 14, color: Color(0xFFC084FC)),
                        tooltip: 'Tải lên Cloud (Sync-Up)',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                        onPressed: () => _confirmAndSyncUp(context, ref, item, state.currentPath),
                      ),

                      // ⬇️ Sync-Down
                      IconButton(
                        icon: const Icon(Icons.cloud_download, size: 14, color: Color(0xFF38BDF8)),
                        tooltip: 'Tải về máy (Sync-Down)',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                        onPressed: () => _confirmAndSyncDown(context, ref, item, state.currentPath),
                      ),

                      // 🗄️ Offload SSD
                      IconButton(
                        icon: const Icon(Icons.cleaning_services, size: 14, color: Color(0xFFF59E0B)),
                        tooltip: 'Giải phóng SSD (Offload)',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                        onPressed: () => _confirmAndOffload(context, ref, item, state.currentPath),
                      ),

                      // 🗑️ Delete
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 14, color: Color(0xFFEF4444)),
                        tooltip: 'Xóa trên Cloud',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                        onPressed: () => _confirmAndDelete(context, ref, item, state.currentPath),
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

  // ── GRID VIEW ──
  Widget _buildGridView(BuildContext context, WidgetRef ref, List<CloudItem> items, CloudStorageState state, CloudStorageNotifier notifier) {
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        childAspectRatio: 1.4,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: items.length,
      itemBuilder: (ctx, idx) {
        final item = items[idx];
        final isSelected = state.selectedItem?.path == item.path;

        return InkWell(
          onTap: () => notifier.selectItem(item),
          onDoubleTap: () => notifier.navigateInto(item),
          borderRadius: BorderRadius.circular(6),
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isSelected ? const Color(0xFF1E293B) : const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: isSelected ? const Color(0xFF06B6D4) : const Color(0xFF1E293B)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      item.isFolder
                          ? Icons.folder
                          : (item.isVideo ? Icons.videocam : Icons.insert_drive_file),
                      size: 16,
                      color: item.isFolder
                          ? const Color(0xFFF59E0B)
                          : (item.isVideo ? const Color(0xFF06B6D4) : const Color(0xFF94A3B8)),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        item.name,
                        style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(item.sizeStr, style: const TextStyle(fontSize: 10, color: Color(0xFF38BDF8))),
                    _buildMiniStatusBadge(item),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── RIGHT INSPECTOR DETAIL PANEL ──
  Widget _buildInspectorPanel(BuildContext context, WidgetRef ref, CloudStorageState state) {
    if (state.selectedItem == null) {
      return const Center(
        child: Text('Chọn tệp để xem chi tiết', style: TextStyle(color: Color(0xFF64748B), fontSize: 12)),
      );
    }

    final item = state.selectedItem!;

    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        // Big Icon Preview
        Center(
          child: Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: const Color(0xFF0B1120),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF1E293B)),
            ),
            child: Icon(
              item.isFolder ? Icons.folder : (item.isVideo ? Icons.videocam : Icons.insert_drive_file),
              size: 26,
              color: item.isFolder ? const Color(0xFFF59E0B) : const Color(0xFF06B6D4),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: Text(
            item.name,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(height: 4),
        Center(
          child: _buildStatusBadge(item),
        ),

        const Divider(color: Color(0xFF1E293B), height: 20),

        const Text('CHI TIẾT', style: TextStyle(color: Color(0xFF06B6D4), fontSize: 10.5, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
        const SizedBox(height: 6),

        _buildDetailRow('Đường dẫn GCS', item.gcsUri.isNotEmpty ? item.gcsUri : 'gs://${state.bucketName}/${state.basePrefix}/${item.path}', canCopy: true, context: context),
        _buildDetailRow('Kích thước', item.isFolder ? '${item.itemCount} mục (${TimeFormatUtils.formatFileSize(item.sizeBytes)})' : item.sizeStr),
        _buildDetailRow('Cập nhật lần cuối', item.modifiedStr),
        _buildDetailRow('Lớp lưu trữ', item.storageClass),
        _buildDetailRow('Vị trí Bucket', 'asia-southeast1 (Singapore)'),

        const Divider(color: Color(0xFF1E293B), height: 20),

        const Text('THAO TÁC', style: TextStyle(color: Color(0xFF10B981), fontSize: 10.5, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
        const SizedBox(height: 8),

        // Action: Copy URI
        _buildInspectorActionButton(
          icon: Icons.copy,
          label: 'Sao chép URI (gs://)',
          color: const Color(0xFF38BDF8),
          onTap: () {
            final uri = item.gcsUri.isNotEmpty ? item.gcsUri : 'gs://${state.bucketName}/${state.basePrefix}/${item.path}';
            Clipboard.setData(ClipboardData(text: uri));
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('📋 Đã sao chép: $uri'), duration: const Duration(seconds: 1)),
            );
          },
        ),

        // Action: Sync-Down
        _buildInspectorActionButton(
          icon: Icons.cloud_download,
          label: 'Đồng bộ về local (Sync-Down)',
          color: const Color(0xFF2563EB),
          onTap: () => _confirmAndSyncDown(context, ref, item, state.currentPath),
        ),

        // Action: Sync-Up
        _buildInspectorActionButton(
          icon: Icons.cloud_upload,
          label: 'Đẩy lên Cloud (Sync-Up)',
          color: const Color(0xFFC084FC),
          onTap: () => _confirmAndSyncUp(context, ref, item, state.currentPath),
        ),

        // Action: Offload
        _buildInspectorActionButton(
          icon: Icons.cleaning_services,
          label: 'Giải phóng SSD (Offload)',
          color: const Color(0xFFF59E0B),
          onTap: () => _confirmAndOffload(context, ref, item, state.currentPath),
        ),

        // Action: Delete
        _buildInspectorActionButton(
          icon: Icons.delete_outline,
          label: 'Xóa tệp',
          color: const Color(0xFFEF4444),
          onTap: () => _confirmAndDelete(context, ref, item, state.currentPath),
        ),

        const Divider(color: Color(0xFF1E293B), height: 20),

        // Bucket Capacity
        Text(
          'DUNG LƯỢNG BUCKET (${state.bucketName.toUpperCase()})',
          style: const TextStyle(color: Color(0xFF64748B), fontSize: 9.5, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        const Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('1.2 GB / 500 GB', style: TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.bold)),
            Text('[25.7%]', style: TextStyle(color: Color(0xFF06B6D4), fontSize: 10.5)),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: const LinearProgressIndicator(
            value: 0.257,
            backgroundColor: Color(0xFF1E293B),
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF06B6D4)),
            minHeight: 4,
          ),
        ),
      ],
    );
  }

  Widget _buildInspectorActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: color.withOpacity(0.4), width: 1.0),
          ),
          child: Row(
            children: [
              Icon(icon, size: 13.5, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: color),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBadge(CloudItem item) {
    if (item.isSynced) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
        decoration: BoxDecoration(color: const Color(0xFF10B981).withOpacity(0.15), borderRadius: BorderRadius.circular(3)),
        child: const Text('🔄 Đã Đồng Bộ', style: TextStyle(color: Color(0xFF10B981), fontSize: 9.5, fontWeight: FontWeight.bold)),
      );
    } else if (item.isLocalOnly) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
        decoration: BoxDecoration(color: const Color(0xFFF59E0B).withOpacity(0.15), borderRadius: BorderRadius.circular(3)),
        child: const Text('💻 Chỉ Local', style: TextStyle(color: Color(0xFFF59E0B), fontSize: 9.5, fontWeight: FontWeight.bold)),
      );
    } else if (item.isModified) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
        decoration: BoxDecoration(color: const Color(0xFFF97316).withOpacity(0.15), borderRadius: BorderRadius.circular(3)),
        child: const Text('⚠️ Khác Biệt', style: TextStyle(color: Color(0xFFF97316), fontSize: 9.5, fontWeight: FontWeight.bold)),
      );
    } else {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
        decoration: BoxDecoration(color: const Color(0xFF38BDF8).withOpacity(0.15), borderRadius: BorderRadius.circular(3)),
        child: const Text('☁️ Chỉ Cloud', style: TextStyle(color: Color(0xFF38BDF8), fontSize: 9.5, fontWeight: FontWeight.bold)),
      );
    }
  }

  Widget _buildMiniStatusBadge(CloudItem item) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
      decoration: BoxDecoration(
        color: item.isSynced
            ? const Color(0xFF10B981).withOpacity(0.2)
            : (item.isLocalOnly ? const Color(0xFFF59E0B).withOpacity(0.2) : const Color(0xFF38BDF8).withOpacity(0.2)),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Text(
        item.isSynced ? 'SYNC' : (item.isLocalOnly ? 'LOCAL' : 'CLOUD'),
        style: TextStyle(
          fontSize: 8,
          fontWeight: FontWeight.bold,
          color: item.isSynced ? const Color(0xFF10B981) : (item.isLocalOnly ? const Color(0xFFF59E0B) : const Color(0xFF38BDF8)),
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, {bool canCopy = false, BuildContext? context}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Color(0xFF64748B), fontSize: 10)),
          const SizedBox(height: 1),
          Row(
            children: [
              Expanded(
                child: SelectableText(
                  value,
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w500),
                ),
              ),
              if (canCopy && context != null)
                IconButton(
                  icon: const Icon(Icons.copy, size: 12, color: Color(0xFF06B6D4)),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: value));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('📋 Đã sao chép: $value'), duration: const Duration(seconds: 1)),
                    );
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }
}
