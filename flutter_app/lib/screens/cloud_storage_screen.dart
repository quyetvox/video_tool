import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/app_colors.dart';
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
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          // ── 1. TOP HEADER BAR ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: const BoxDecoration(
              color: AppColors.surface,
              border: Border(bottom: BorderSide(color: AppColors.border)),
            ),
            child: Row(
              children: [
                const Icon(Icons.cloud_done, color: AppColors.primary, size: 17),
                const SizedBox(width: 8),
                const Text(
                  'Google Cloud Storage (GCS)',
                  style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 8),

                // Connection Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: cloudState.isConnected ? AppColors.statusCompletedBg : AppColors.statusFailedBg,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: cloudState.isConnected ? AppColors.statusCompleted.withOpacity(0.3) : AppColors.statusFailed.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: cloudState.isConnected ? AppColors.statusCompleted : AppColors.statusFailed,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        cloudState.isConnected ? 'Đã kết nối (gs://${cloudState.bucketName})' : 'Chưa Kết Nối (Cần gcs-key.json)',
                        style: TextStyle(
                          color: cloudState.isConnected ? AppColors.statusCompleted : AppColors.statusFailed,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w500,
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
                  borderRadius: BorderRadius.circular(5),
                  child: Container(
                    height: 26,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.cloud_upload, size: 12, color: AppColors.primaryText),
                        SizedBox(width: 5),
                        Text('Tải lên (Sync-Up)', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: AppColors.primaryText)),
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
                  borderRadius: BorderRadius.circular(5),
                  child: Container(
                    height: 26,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceLight,
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(color: AppColors.border, width: 1.0),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.cloud_download, size: 12, color: Colors.white),
                        SizedBox(width: 5),
                        Text('Đồng bộ về local', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w500, color: Colors.white)),
                      ],
                    ),
                  ),
                ),

                const SizedBox(width: 10),

                // Settings Button (GCS Key & Bucket Configuration)
                IconButton(
                  icon: const Icon(Icons.settings, size: 15, color: AppColors.textSecondary),
                  tooltip: 'Cấu hình Service Account Key GCS',
                  onPressed: () => _openGcsConfig(context, ref),
                ),

                // Refresh Button
                IconButton(
                  icon: cloudState.isLoading
                      ? const SizedBox(width: 13, height: 13, child: CircularProgressIndicator(strokeWidth: 1.5, color: AppColors.primary))
                      : const Icon(Icons.refresh, size: 15, color: AppColors.textSecondary),
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
                    color: AppColors.surface,
                    border: Border(right: BorderSide(color: AppColors.border)),
                  ),
                  child: _buildFilterSidebar(context, ref, cloudState, cloudNotifier),
                ),

                // ── CENTER BROWSER TABLE (Expanded) ──
                Expanded(
                  child: Column(
                    children: [
                      // Breadcrumb Bar & Search
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        decoration: const BoxDecoration(
                          color: AppColors.surface,
                          border: Border(bottom: BorderSide(color: AppColors.border)),
                        ),
                        child: Row(
                          children: [
                            if (cloudState.currentPath.isNotEmpty) ...[
                              IconButton(
                                icon: const Icon(Icons.arrow_back, size: 14, color: AppColors.primary),
                                tooltip: 'Quay lại thư mục cha',
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                onPressed: () => cloudNotifier.navigateUp(),
                              ),
                              const SizedBox(width: 8),
                            ],

                            // Breadcrumb Path
                            Expanded(
                              child: _buildBreadcrumbs(cloudState, cloudNotifier),
                            ),

                            // Copy GCS URI Button
                            IconButton(
                              icon: const Icon(Icons.copy, size: 12, color: AppColors.textMuted),
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

                            const SizedBox(width: 10),

                            // Search Input
                            SizedBox(
                              width: 180,
                              height: 30,
                              child: TextField(
                                textAlignVertical: TextAlignVertical.center,
                                style: const TextStyle(fontSize: 11.5, color: Colors.white, height: 1.0),
                                decoration: InputDecoration(
                                  hintText: 'Tìm trong thư mục...',
                                  hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 11, height: 1.0),
                                  prefixIcon: const Icon(Icons.search, size: 14, color: AppColors.textMuted),
                                  contentPadding: EdgeInsets.zero,
                                  filled: true,
                                  fillColor: AppColors.surfaceDark,
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: AppColors.border, width: 0.8)),
                                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: AppColors.border, width: 0.8)),
                                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: AppColors.primary, width: 1.0)),
                                ),
                                onChanged: (val) => cloudNotifier.setSearchQuery(val),
                              ),
                            ),

                            const SizedBox(width: 8),

                            // Table / Grid Toggle
                            IconButton(
                              icon: Icon(cloudState.isGridView ? Icons.view_list : Icons.grid_view, size: 14, color: AppColors.textSecondary),
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
                                    CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                                    SizedBox(height: 10),
                                    Text('Đang duyệt tệp Google Cloud Storage...', style: TextStyle(color: AppColors.textSecondary, fontSize: 11.5)),
                                  ],
                                ),
                              )
                            : filteredItems.isEmpty
                                ? Center(
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        const Icon(Icons.cloud_off, size: 36, color: AppColors.border),
                                        const SizedBox(height: 8),
                                        Text(
                                          cloudState.isConnected ? 'Thư mục này trống trên Cloud' : 'Chưa kết nối được Google Cloud Storage',
                                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5),
                                        ),
                                        const SizedBox(height: 8),
                                        if (!cloudState.isConnected)
                                          ElevatedButton.icon(
                                            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: AppColors.primaryText),
                                            icon: const Icon(Icons.settings, size: 13),
                                            label: const Text('Cấu Hình gcs-key.json Ngay', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
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
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        decoration: const BoxDecoration(
                          color: AppColors.surface,
                          border: Border(top: BorderSide(color: AppColors.border)),
                        ),
                        child: Row(
                          children: [
                            Text(
                              'Hiển thị 1 - ${filteredItems.length} trong ${filteredItems.length} mục ($totalSizeStr)',
                              style: const TextStyle(color: AppColors.textMuted, fontSize: 10.5),
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: AppColors.surfaceLight,
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: const Text('20 / trang', style: TextStyle(color: AppColors.textSecondary, fontSize: 10)),
                            ),
                            const SizedBox(width: 8),
                            const Icon(Icons.chevron_left, size: 14, color: AppColors.textMuted),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: const Text('1', style: TextStyle(color: AppColors.primaryText, fontSize: 10, fontWeight: FontWeight.bold)),
                            ),
                            const Icon(Icons.chevron_right, size: 14, color: AppColors.textMuted),
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
                    color: AppColors.surface,
                    border: Border(left: BorderSide(color: AppColors.border)),
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
      padding: const EdgeInsets.all(10),
      children: [
        // 1. Storage Bucket Card
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.surfaceDark,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AppColors.border, width: 0.8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.storage, size: 13.5, color: AppColors.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      state.bucketName,
                      style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: state.isConnected ? AppColors.statusCompleted : AppColors.statusFailed,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                'Thư mục gốc: ${state.basePrefix}',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 9.5),
              ),
              const SizedBox(height: 2),
              const Text(
                'Vị trí: asia-southeast1',
                style: TextStyle(color: AppColors.textMuted, fontSize: 9.5),
              ),
            ],
          ),
        ),

        const SizedBox(height: 14),

        // 2. Filters Section Header
        const Text(
          'BỘ LỌC',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 0.5),
        ),
        const SizedBox(height: 8),

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

        const SizedBox(height: 6),

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

        const SizedBox(height: 6),

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

        const SizedBox(height: 6),

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

        const SizedBox(height: 8),

        // Reset Filter Button
        InkWell(
          onTap: () => notifier.resetFilters(),
          borderRadius: BorderRadius.circular(5),
          child: Container(
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.surfaceDark,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: AppColors.border, width: 0.8),
            ),
            child: const Text('Đặt lại bộ lọc', style: TextStyle(color: AppColors.textSecondary, fontSize: 10.5, fontWeight: FontWeight.w500)),
          ),
        ),

        const SizedBox(height: 16),

        // 3. Quick Actions Header
        const Text(
          'HÀNH ĐỘNG NHANH',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 0.5),
        ),
        const SizedBox(height: 6),

        _buildQuickActionButton(
          icon: Icons.create_new_folder,
          label: 'Tạo folder mới',
          iconColor: AppColors.primary,
          onTap: () async {
            final ctrl = TextEditingController();
            final name = await showDialog<String>(
              context: context,
              builder: (ctx) => AlertDialog(
                backgroundColor: AppColors.surface,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: const BorderSide(color: AppColors.border)),
                title: const Text('Tạo thư mục mới trên Cloud', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                content: TextField(
                  controller: ctrl,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                  decoration: const InputDecoration(hintText: 'Tên thư mục...', hintStyle: TextStyle(color: AppColors.textMuted)),
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy', style: TextStyle(color: AppColors.textSecondary))),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: AppColors.primaryText),
                    onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
                    child: const Text('Tạo', style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            );
            if (name != null && name.isNotEmpty) {
              final activeProject = ref.read(activeProjectProvider) ?? 'default';
              final res = await PythonBridge.runCode('''
try:
    from utils.storage_manager import StorageManager
except ImportError:
    from py_engine.utils.storage_manager import StorageManager
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
          iconColor: AppColors.primary,
          onTap: () {
            final activeProject = ref.read(activeProjectProvider) ?? 'default';
            _confirmAndSyncUp(context, ref, CloudItem(id: activeProject, name: activeProject, path: activeProject, type: 'folder', isFolder: true, sizeStr: '', modifiedStr: ''), '');
          },
        ),

        _buildQuickActionButton(
          icon: Icons.cloud_download,
          label: 'Kéo dự án về Local (Sync-Down)',
          iconColor: const Color(0xFF60A5FA),
          onTap: () {
            final activeProject = ref.read(activeProjectProvider) ?? 'default';
            _confirmAndSyncDown(context, ref, CloudItem(id: activeProject, name: activeProject, path: activeProject, type: 'folder', isFolder: true, sizeStr: '', modifiedStr: ''), '');
          },
        ),

        _buildQuickActionButton(
          icon: Icons.cleaning_services,
          label: 'Giải phóng bộ nhớ SSD',
          iconColor: const Color(0xFFFBBF24),
          onTap: () {
            final activeProject = ref.read(activeProjectProvider) ?? 'default';
            _confirmAndOffload(context, ref, CloudItem(id: activeProject, name: activeProject, path: activeProject, type: 'folder', isFolder: true, sizeStr: '', modifiedStr: ''), '');
          },
        ),

        _buildQuickActionButton(
          icon: Icons.refresh,
          label: 'Làm mới danh mục',
          iconColor: AppColors.statusCompleted,
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
        Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.w500)),
        const SizedBox(height: 2),
        Container(
          height: 26,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: AppColors.surfaceDark,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: AppColors.border, width: 0.8),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              dropdownColor: AppColors.surfaceLight,
              style: const TextStyle(color: Colors.white, fontSize: 10.5),
              icon: const Icon(Icons.arrow_drop_down, size: 14, color: AppColors.textSecondary),
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
    Color iconColor = AppColors.primary,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(5),
        child: Container(
          height: 26,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: AppColors.surfaceDark,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: AppColors.border, width: 0.8),
          ),
          child: Row(
            children: [
              Icon(icon, size: 12.5, color: iconColor),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(color: AppColors.textLight, fontSize: 10.5, fontWeight: FontWeight.w500),
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
            const Icon(Icons.home, size: 12, color: AppColors.primary),
            const SizedBox(width: 4),
            Text(
              state.bucketName,
              style: TextStyle(
                fontSize: 11,
                fontWeight: state.currentPath.isEmpty ? FontWeight.w600 : FontWeight.normal,
                color: state.currentPath.isEmpty ? Colors.white : AppColors.primary,
              ),
            ),
          ],
        ),
      ),
    );

    crumbs.add(const Padding(
      padding: EdgeInsets.symmetric(horizontal: 4),
      child: Text('/', style: TextStyle(color: AppColors.textMuted, fontSize: 10.5)),
    ));

    crumbs.add(
      InkWell(
        onTap: () => notifier.loadBrowse(''),
        child: Text(
          state.basePrefix,
          style: TextStyle(
            fontSize: 11,
            fontWeight: state.currentPath.isEmpty ? FontWeight.w600 : FontWeight.normal,
            color: state.currentPath.isEmpty ? Colors.white : AppColors.primary,
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
          child: Text('/', style: TextStyle(color: AppColors.textMuted, fontSize: 10.5)),
        ));

        crumbs.add(
          InkWell(
            onTap: isLast ? null : () => notifier.loadBrowse(targetPath),
            child: Text(
              parts[i],
              style: TextStyle(
                fontSize: 11,
                fontWeight: isLast ? FontWeight.w600 : FontWeight.normal,
                color: isLast ? Colors.white : AppColors.primary,
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
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: const BoxDecoration(
              color: AppColors.surfaceDark,
              border: Border(bottom: BorderSide(color: AppColors.border)),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 24,
                  child: Checkbox(
                    value: isAllSelected,
                    onChanged: (val) => notifier.selectAllPaths(val ?? false),
                    activeColor: AppColors.primary,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
                const SizedBox(width: 8),
                const Expanded(flex: 4, child: Text('TÊN', style: TextStyle(color: AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.w600))),
                const Expanded(flex: 2, child: Text('LOẠI', style: TextStyle(color: AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.w600))),
                const Expanded(flex: 2, child: Text('KÍCH THƯỚC', style: TextStyle(color: AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.w600))),
                const Expanded(flex: 2, child: Text('TRẠNG THÁI', style: TextStyle(color: AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.w600))),
                const Expanded(flex: 2, child: Text('NGÀY SỬA ĐỔI', style: TextStyle(color: AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.w600))),
                const SizedBox(width: 110, child: Text('THAO TÁC', style: TextStyle(color: AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.w600))),
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
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
            decoration: BoxDecoration(
              color: isSelected ? AppColors.surfaceLight : Colors.transparent,
              border: const Border(bottom: BorderSide(color: AppColors.border, width: 0.5)),
            ),
            child: Row(
              children: [
                // Checkbox
                SizedBox(
                  width: 24,
                  child: Checkbox(
                    value: isChecked,
                    onChanged: (val) => notifier.toggleSelectPath(item.path),
                    activeColor: AppColors.primary,
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
                        size: 14,
                        color: item.isFolder
                            ? AppColors.primary
                            : (item.isVideo ? const Color(0xFF60A5FA) : AppColors.textSecondary),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          item.name,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: isSelected || item.isFolder ? FontWeight.w600 : FontWeight.normal,
                            color: isSelected ? Colors.white : AppColors.textLight,
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
                    style: const TextStyle(fontSize: 10.5, color: AppColors.textMuted),
                  ),
                ),

                // Size
                Expanded(
                  flex: 2,
                  child: Text(
                    item.sizeStr,
                    style: const TextStyle(fontSize: 10.5, color: AppColors.primary, fontWeight: FontWeight.w600),
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
                    style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
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
                        icon: const Icon(Icons.cloud_upload, size: 13, color: AppColors.primary),
                        tooltip: 'Tải lên Cloud (Sync-Up)',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                        onPressed: () => _confirmAndSyncUp(context, ref, item, state.currentPath),
                      ),

                      // ⬇️ Sync-Down
                      IconButton(
                        icon: const Icon(Icons.cloud_download, size: 13, color: Color(0xFF60A5FA)),
                        tooltip: 'Tải về máy (Sync-Down)',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                        onPressed: () => _confirmAndSyncDown(context, ref, item, state.currentPath),
                      ),

                      // 🗄️ Offload SSD
                      IconButton(
                        icon: const Icon(Icons.cleaning_services, size: 13, color: Color(0xFFFBBF24)),
                        tooltip: 'Giải phóng SSD (Offload)',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                        onPressed: () => _confirmAndOffload(context, ref, item, state.currentPath),
                      ),

                      // 🗑️ Delete
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 13, color: AppColors.statusFailed),
                        tooltip: 'Xóa trên Cloud',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
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
      padding: const EdgeInsets.all(10),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        childAspectRatio: 1.4,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
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
              color: isSelected ? AppColors.surfaceLight : AppColors.surfaceDark,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: isSelected ? AppColors.primary : AppColors.border, width: 0.8),
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
                      size: 15,
                      color: item.isFolder
                          ? AppColors.primary
                          : (item.isVideo ? const Color(0xFF60A5FA) : AppColors.textSecondary),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        item.name,
                        style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(item.sizeStr, style: const TextStyle(fontSize: 9.5, color: AppColors.primary)),
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
        child: Text('Chọn tệp để xem chi tiết', style: TextStyle(color: AppColors.textMuted, fontSize: 11.5)),
      );
    }

    final item = state.selectedItem!;

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // Big Icon Preview
        Center(
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.surfaceDark,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppColors.border, width: 0.8),
            ),
            child: Icon(
              item.isFolder ? Icons.folder : (item.isVideo ? Icons.videocam : Icons.insert_drive_file),
              size: 22,
              color: item.isFolder ? AppColors.primary : const Color(0xFF60A5FA),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: Text(
            item.name,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(height: 4),
        Center(
          child: _buildStatusBadge(item),
        ),

        const Divider(color: AppColors.border, height: 18),

        const Text('CHI TIẾT', style: TextStyle(color: AppColors.primary, fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
        const SizedBox(height: 5),

        _buildDetailRow('Đường dẫn GCS', item.gcsUri.isNotEmpty ? item.gcsUri : 'gs://${state.bucketName}/${state.basePrefix}/${item.path}', canCopy: true, context: context),
        _buildDetailRow('Kích thước', item.isFolder ? '${item.itemCount} mục (${TimeFormatUtils.formatFileSize(item.sizeBytes)})' : item.sizeStr),
        _buildDetailRow('Cập nhật lần cuối', item.modifiedStr),
        _buildDetailRow('Lớp lưu trữ', item.storageClass),
        _buildDetailRow('Vị trí Bucket', 'asia-southeast1 (Singapore)'),

        const Divider(color: AppColors.border, height: 18),

        const Text('THAO TÁC', style: TextStyle(color: AppColors.statusCompleted, fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
        const SizedBox(height: 6),

        // Action: Copy URI
        _buildInspectorActionButton(
          icon: Icons.copy,
          label: 'Sao chép URI (gs://)',
          color: const Color(0xFF60A5FA),
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
          color: AppColors.primary,
          onTap: () => _confirmAndSyncDown(context, ref, item, state.currentPath),
        ),

        // Action: Sync-Up
        _buildInspectorActionButton(
          icon: Icons.cloud_upload,
          label: 'Đẩy lên Cloud (Sync-Up)',
          color: const Color(0xFFA855F7),
          onTap: () => _confirmAndSyncUp(context, ref, item, state.currentPath),
        ),

        // Action: Offload
        _buildInspectorActionButton(
          icon: Icons.cleaning_services,
          label: 'Giải phóng SSD (Offload)',
          color: const Color(0xFFFBBF24),
          onTap: () => _confirmAndOffload(context, ref, item, state.currentPath),
        ),

        // Action: Delete
        _buildInspectorActionButton(
          icon: Icons.delete_outline,
          label: 'Xóa tệp',
          color: AppColors.statusFailed,
          onTap: () => _confirmAndDelete(context, ref, item, state.currentPath),
        ),

        const Divider(color: AppColors.border, height: 18),

        // Bucket Capacity
        Text(
          'DUNG LƯỢNG BUCKET (${state.bucketName.toUpperCase()})',
          style: const TextStyle(color: AppColors.textMuted, fontSize: 9.5, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 5),
        const Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('1.2 GB / 500 GB', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600)),
            Text('[25.7%]', style: TextStyle(color: AppColors.primary, fontSize: 10)),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: const LinearProgressIndicator(
            value: 0.257,
            backgroundColor: AppColors.surfaceLight,
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
            minHeight: 3.5,
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
      padding: const EdgeInsets.only(bottom: 5),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(5),
        child: Container(
          height: 26,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.surfaceDark,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: color.withOpacity(0.4), width: 0.8),
          ),
          child: Row(
            children: [
              Icon(icon, size: 12.5, color: color),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: color),
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
        decoration: BoxDecoration(color: AppColors.statusCompletedBg, borderRadius: BorderRadius.circular(3)),
        child: const Text('🔄 Đã Đồng Bộ', style: TextStyle(color: AppColors.statusCompleted, fontSize: 9, fontWeight: FontWeight.w600)),
      );
    } else if (item.isLocalOnly) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
        decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.15), borderRadius: BorderRadius.circular(3)),
        child: const Text('💻 Chỉ Local', style: TextStyle(color: AppColors.primary, fontSize: 9, fontWeight: FontWeight.w600)),
      );
    } else if (item.isModified) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
        decoration: BoxDecoration(color: const Color(0xFFF97316).withOpacity(0.15), borderRadius: BorderRadius.circular(3)),
        child: const Text('⚠️ Khác Biệt', style: TextStyle(color: Color(0xFFF97316), fontSize: 9, fontWeight: FontWeight.w600)),
      );
    } else {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
        decoration: BoxDecoration(color: const Color(0xFF38BDF8).withOpacity(0.15), borderRadius: BorderRadius.circular(3)),
        child: const Text('☁️ Chỉ Cloud', style: TextStyle(color: Color(0xFF38BDF8), fontSize: 9, fontWeight: FontWeight.w600)),
      );
    }
  }

  Widget _buildMiniStatusBadge(CloudItem item) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
      decoration: BoxDecoration(
        color: item.isSynced
            ? AppColors.statusCompletedBg
            : (item.isLocalOnly ? AppColors.primary.withOpacity(0.2) : const Color(0xFF38BDF8).withOpacity(0.2)),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Text(
        item.isSynced ? 'SYNC' : (item.isLocalOnly ? 'LOCAL' : 'CLOUD'),
        style: TextStyle(
          fontSize: 7.5,
          fontWeight: FontWeight.bold,
          color: item.isSynced ? AppColors.statusCompleted : (item.isLocalOnly ? AppColors.primary : const Color(0xFF38BDF8)),
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, {bool canCopy = false, BuildContext? context}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 9.5)),
          const SizedBox(height: 1),
          Row(
            children: [
              Expanded(
                child: SelectableText(
                  value,
                  style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w500),
                ),
              ),
              if (canCopy && context != null)
                IconButton(
                  icon: const Icon(Icons.copy, size: 11, color: AppColors.primary),
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
