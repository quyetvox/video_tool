import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/app_colors.dart';
import '../core/providers.dart';
import '../core/python_bridge.dart';
import '../models/cloud_item.dart';
import '../widgets/gcs_config_dialog.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/resizable_collapsible_panel.dart';
import 'cloud_storage/components/cloud_storage_toolbar.dart';
import 'cloud_storage/components/cloud_storage_filter_sidebar.dart';
import 'cloud_storage/components/cloud_storage_table_view.dart';
import 'cloud_storage/components/cloud_storage_grid_view.dart';
import 'cloud_storage/components/cloud_storage_inspector.dart';

/// Orchestrator screen for Google Cloud Storage Browser.
/// Provides a dual-split resizable layout:
/// - Resizable & collapsible Left Filter Sidebar
/// - Central dynamic Table / Grid view
/// - Resizable & collapsible Right Inspector detail panel
class CloudStorageScreen extends ConsumerWidget {
  const CloudStorageScreen({super.key});

  void _openGcsConfig(BuildContext context, WidgetRef ref) async {
    final cloudState = ref.read(cloudStorageProvider);
    final config = ref.read(configProvider);
    final changed = await GcsConfigDialog.show(
      context,
      initialKeyPath: config.storageKeyFile.isNotEmpty ? config.storageKeyFile : 'resources/gcs-key.json',
      initialBucket: cloudState.bucketName,
      initialPrefix: cloudState.basePrefix,
      onSave: (key, bucket, prefix) async {
        final notifier = ref.read(configProvider.notifier);
        notifier.setField((c) => c.copyWith(
              storageKeyFile: key,
              storageBucketName: bucket,
              storageBasePrefix: prefix,
            ));
        await notifier.save();
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

    final jobId = 'syncdown_${DateTime.now().millisecondsSinceEpoch}';
    final result = await PythonBridge.runScript('storage.py', args, jobId: jobId);

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.success ? '✅ Đồng bộ thành công về local!' : '❌ Thất bại: ${result.error}'),
          backgroundColor: result.success ? const Color(0xFF10B981) : const Color(0xFFEF4444),
        ),
      );
      ref.read(cloudStorageProvider.notifier).refreshCurrent();
    }
  }

  void _confirmAndSyncUp(BuildContext context, WidgetRef ref, CloudItem item, String currentPath) async {
    final ok = await ConfirmDialog.show(
      context,
      title: 'Đẩy ${item.isFolder ? "thư mục" : "tệp"} lên Cloud?',
      message: 'Tải "${item.name}" (${item.sizeStr}) lên Google Cloud Storage?',
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

    final jobId = 'syncup_${DateTime.now().millisecondsSinceEpoch}';
    final result = await PythonBridge.runScript('storage.py', args, jobId: jobId);

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.success ? '✅ Đẩy lên Cloud thành công!' : '❌ Thất bại: ${result.error}'),
          backgroundColor: result.success ? const Color(0xFF10B981) : const Color(0xFFEF4444),
        ),
      );
      ref.read(cloudStorageProvider.notifier).refreshCurrent();
    }
  }

  void _confirmAndOffload(BuildContext context, WidgetRef ref, CloudItem item, String currentPath) async {
    final ok = await ConfirmDialog.show(
      context,
      title: 'Giải phóng SSD (Offload)?',
      message: 'Xóa tệp "${item.name}" khỏi ổ cứng Mac sau khi đã đảm bảo tệp có trên Cloud?\nThao tác này KHÔNG làm mất dữ liệu trên Cloud.',
      confirmText: 'Giải phóng SSD',
      icon: Icons.cleaning_services,
      isDestructive: true,
    );
    if (!ok) return;

    final project = currentPath.isNotEmpty ? currentPath.split('/').first : item.name;
    final files = item.isFolder ? null : [item.path.replaceFirst('$project/', '')];

    final args = ['offload', project];
    if (files != null) {
      args.add('--files');
      args.addAll(files);
    }

    final jobId = 'offload_${DateTime.now().millisecondsSinceEpoch}';
    final result = await PythonBridge.runScript('storage.py', args, jobId: jobId);

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.success ? '🧹 Đã giải phóng bộ nhớ SSD an toàn!' : '❌ Lỗi: ${result.error}'),
          backgroundColor: result.success ? const Color(0xFF10B981) : const Color(0xFFEF4444),
        ),
      );
      ref.read(cloudStorageProvider.notifier).refreshCurrent();
    }
  }

  void _confirmAndDelete(BuildContext context, WidgetRef ref, CloudItem item, String currentPath) async {
    final ok = await ConfirmDialog.show(
      context,
      title: 'Xóa VĨNH VIỄN trên Cloud?',
      message: 'CẢNH BÁO: Tệp "${item.name}" sẽ bị xóa HOÀN TOÀN khỏi Google Cloud Storage và KHÔNG THỂ khôi phục!',
      confirmText: 'Xác nhận Xóa',
      icon: Icons.delete_forever,
      isDestructive: true,
    );
    if (!ok) return;

    final activeProject = ref.read(activeProjectProvider) ?? 'default';
    final res = await PythonBridge.runCode('''
try:
    from utils.storage_manager import StorageManager
except ImportError:
    from py_engine.utils.storage_manager import StorageManager
mgr = StorageManager('$activeProject')
mgr.delete_remote('${item.path}')
print('ok')
''');

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res.exitCode == 0 ? '🗑️ Đã xóa tệp trên Cloud' : '❌ Lỗi khi xóa tệp'),
          backgroundColor: res.exitCode == 0 ? const Color(0xFF10B981) : const Color(0xFFEF4444),
        ),
      );
      ref.read(cloudStorageProvider.notifier).refreshCurrent();
    }
  }

  // ── BATCH ACTIONS ──

  void _syncDownBatch(BuildContext context, WidgetRef ref) async {
    final state = ref.read(cloudStorageProvider);
    final count = state.selectedPaths.length;
    final ok = await ConfirmDialog.show(
      context,
      title: 'Đồng bộ $count mục về máy?',
      message: 'Tải hàng loạt $count tệp/thư mục đã chọn từ Cloud về Mac?',
      confirmText: 'Tải về tất cả',
      icon: Icons.cloud_download,
    );
    if (!ok) return;

    final project = state.currentPath.isNotEmpty ? state.currentPath.split('/').first : 'default';
    final files = state.selectedPaths.map((p) => p.replaceFirst('$project/', '')).toList();

    final args = ['sync-down', project, '--files', ...files];
    final jobId = 'syncdown_batch_${DateTime.now().millisecondsSinceEpoch}';
    final result = await PythonBridge.runScript('storage.py', args, jobId: jobId);

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.success ? '✅ Đồng bộ thành công $count mục!' : '❌ Lỗi: ${result.error}'),
          backgroundColor: result.success ? const Color(0xFF10B981) : const Color(0xFFEF4444),
        ),
      );
      ref.read(cloudStorageProvider.notifier).refreshCurrent();
    }
  }

  void _syncUpBatch(BuildContext context, WidgetRef ref) async {
    final state = ref.read(cloudStorageProvider);
    final count = state.selectedPaths.length;
    final ok = await ConfirmDialog.show(
      context,
      title: 'Đẩy $count mục lên Cloud?',
      message: 'Đồng bộ tải lên hàng loạt $count tệp/thư mục đã chọn lên Google Cloud Storage?',
      confirmText: 'Đẩy lên Cloud',
      icon: Icons.cloud_upload,
    );
    if (!ok) return;

    final project = state.currentPath.isNotEmpty ? state.currentPath.split('/').first : 'default';
    final files = state.selectedPaths.map((p) => p.replaceFirst('$project/', '')).toList();

    final args = ['sync-up', project, '--files', ...files];
    final jobId = 'syncup_batch_${DateTime.now().millisecondsSinceEpoch}';
    final result = await PythonBridge.runScript('storage.py', args, jobId: jobId);

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.success ? '✅ Tải lên Cloud thành công $count mục!' : '❌ Lỗi: ${result.error}'),
          backgroundColor: result.success ? const Color(0xFF10B981) : const Color(0xFFEF4444),
        ),
      );
      ref.read(cloudStorageProvider.notifier).refreshCurrent();
    }
  }

  void _offloadBatch(BuildContext context, WidgetRef ref) async {
    final state = ref.read(cloudStorageProvider);
    final count = state.selectedPaths.length;
    final ok = await ConfirmDialog.show(
      context,
      title: 'Giải phóng SSD cho $count mục?',
      message: 'Xóa an toàn $count tệp đã chọn khỏi bộ nhớ SSD Mac (Dữ liệu trên Cloud vẫn giữ nguyên)?',
      confirmText: 'Giải phóng SSD',
      icon: Icons.cleaning_services,
      isDestructive: true,
    );
    if (!ok) return;

    final project = state.currentPath.isNotEmpty ? state.currentPath.split('/').first : 'default';
    final files = state.selectedPaths.map((p) => p.replaceFirst('$project/', '')).toList();

    final args = ['offload', project, '--files', ...files];
    final jobId = 'offload_batch_${DateTime.now().millisecondsSinceEpoch}';
    final result = await PythonBridge.runScript('storage.py', args, jobId: jobId);

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.success ? '🧹 Đã giải phóng $count mục khỏi SSD!' : '❌ Lỗi: ${result.error}'),
          backgroundColor: result.success ? const Color(0xFF10B981) : const Color(0xFFEF4444),
        ),
      );
      ref.read(cloudStorageProvider.notifier).refreshCurrent();
    }
  }

  void _deleteBatch(BuildContext context, WidgetRef ref) async {
    final state = ref.read(cloudStorageProvider);
    final count = state.selectedPaths.length;
    final ok = await ConfirmDialog.show(
      context,
      title: 'Xóa VĨNH VIỄN $count mục?',
      message: 'CẢNH BÁO: $count tệp/thư mục được chọn sẽ bị xóa HOÀN TOÀN khỏi Google Cloud Storage và KHÔNG THỂ khôi phục!',
      confirmText: 'Xóa tất cả',
      icon: Icons.delete_forever,
      isDestructive: true,
    );
    if (!ok) return;

    final activeProject = ref.read(activeProjectProvider) ?? 'default';
    for (final path in state.selectedPaths) {
      await PythonBridge.runCode('''
try:
    from utils.storage_manager import StorageManager
except ImportError:
    from py_engine.utils.storage_manager import StorageManager
mgr = StorageManager('$activeProject')
mgr.delete_remote('$path')
''');
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('🗑️ Đã xóa hoàn tất $count mục khỏi Cloud'),
          backgroundColor: const Color(0xFF10B981),
        ),
      );
      ref.read(cloudStorageProvider.notifier).refreshCurrent();
    }
  }

  void _createFolder(BuildContext context, WidgetRef ref) async {
    final cloudState = ref.read(cloudStorageProvider);
    final notifier = ref.read(cloudStorageProvider.notifier);
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: AppColors.border),
        ),
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
mgr.create_folder('${cloudState.currentPath}/$name')
print('ok')
''');
      if (res.exitCode == 0) {
        notifier.refreshCurrent();
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cloudState = ref.watch(cloudStorageProvider);
    final cloudNotifier = ref.read(cloudStorageProvider.notifier);
    final filteredItems = cloudState.filteredItems;

    int totalBytes = 0;
    for (final it in filteredItems) {
      totalBytes += it.sizeBytes;
    }
    final totalSizeStr = totalBytes > 1024 * 1024 * 1024
        ? '${(totalBytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB'
        : '${(totalBytes / (1024 * 1024)).toStringAsFixed(1)} MB';

    // ── CENTER WORKSPACE CONTENT ──
    final centerContent = Column(
      children: [
        Expanded(
          child: cloudState.isLoading
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2.5),
                      SizedBox(height: 12),
                      Text('Đang nạp dữ liệu từ Google Cloud Storage...', style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
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
                      ? CloudStorageGridView(
                          items: filteredItems,
                          state: cloudState,
                          notifier: cloudNotifier,
                        )
                      : CloudStorageTableView(
                          items: filteredItems,
                          state: cloudState,
                          notifier: cloudNotifier,
                          onSyncUp: (it) => _confirmAndSyncUp(context, ref, it, cloudState.currentPath),
                          onSyncDown: (it) => _confirmAndSyncDown(context, ref, it, cloudState.currentPath),
                          onOffload: (it) => _confirmAndOffload(context, ref, it, cloudState.currentPath),
                          onDelete: (it) => _confirmAndDelete(context, ref, it, cloudState.currentPath),
                        ),
        ),

        // Bottom Summary Bar
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
              IconButton(
                icon: const Icon(Icons.first_page, size: 14, color: AppColors.textMuted),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () {},
              ),
              IconButton(
                icon: const Icon(Icons.chevron_left, size: 14, color: AppColors.textMuted),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () {},
              ),
              const SizedBox(width: 8),
              const Text('Trang 1 / 1', style: TextStyle(color: Colors.white, fontSize: 10.5)),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.chevron_right, size: 14, color: AppColors.textMuted),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () {},
              ),
              IconButton(
                icon: const Icon(Icons.last_page, size: 14, color: AppColors.textMuted),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () {},
              ),
            ],
          ),
        ),
      ],
    );

    // Wrap Center Content with Resizable Inspector on the Right
    final centerAndRight = ResizableCollapsiblePanel(
      side: PanelSide.right,
      initialWidth: 280,
      minWidth: 220,
      maxWidth: 450,
      collapseTooltip: 'Thu gọn chi tiết tệp',
      expandTooltip: 'Mở chi tiết tệp',
      panel: Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
        ),
        child: CloudStorageInspector(
          item: cloudState.selectedItem,
          state: cloudState,
          onSyncUp: () {
            if (cloudState.selectedItem != null) {
              _confirmAndSyncUp(context, ref, cloudState.selectedItem!, cloudState.currentPath);
            }
          },
          onSyncDown: () {
            if (cloudState.selectedItem != null) {
              _confirmAndSyncDown(context, ref, cloudState.selectedItem!, cloudState.currentPath);
            }
          },
          onOffload: () {
            if (cloudState.selectedItem != null) {
              _confirmAndOffload(context, ref, cloudState.selectedItem!, cloudState.currentPath);
            }
          },
          onDelete: () {
            if (cloudState.selectedItem != null) {
              _confirmAndDelete(context, ref, cloudState.selectedItem!, cloudState.currentPath);
            }
          },
        ),
      ),
      child: centerContent,
    );

    // Wrap with Resizable Filter Sidebar on the Left
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          CloudStorageToolbar(
            state: cloudState,
            notifier: cloudNotifier,
            onOpenConfig: () => _openGcsConfig(context, ref),
            onSyncDownBatch: () => _syncDownBatch(context, ref),
            onSyncUpBatch: () => _syncUpBatch(context, ref),
            onOffloadBatch: () => _offloadBatch(context, ref),
            onDeleteBatch: () => _deleteBatch(context, ref),
          ),
          Expanded(
            child: ResizableCollapsiblePanel(
              side: PanelSide.left,
              initialWidth: 230,
              minWidth: 180,
              maxWidth: 380,
              collapseTooltip: 'Thu gọn bộ lọc',
              expandTooltip: 'Mở bộ lọc',
              panel: Container(
                decoration: const BoxDecoration(
                  color: AppColors.surface,
                ),
                child: CloudStorageFilterSidebar(
                  state: cloudState,
                  notifier: cloudNotifier,
                  onSyncUpProject: () {
                    final activeProject = ref.read(activeProjectProvider) ?? 'default';
                    _confirmAndSyncUp(
                      context,
                      ref,
                      CloudItem(id: activeProject, name: activeProject, path: activeProject, type: 'folder', isFolder: true, sizeStr: '', modifiedStr: ''),
                      '',
                    );
                  },
                  onSyncDownProject: () {
                    final activeProject = ref.read(activeProjectProvider) ?? 'default';
                    _confirmAndSyncDown(
                      context,
                      ref,
                      CloudItem(id: activeProject, name: activeProject, path: activeProject, type: 'folder', isFolder: true, sizeStr: '', modifiedStr: ''),
                      '',
                    );
                  },
                  onOffloadProject: () {
                    final activeProject = ref.read(activeProjectProvider) ?? 'default';
                    _confirmAndOffload(
                      context,
                      ref,
                      CloudItem(id: activeProject, name: activeProject, path: activeProject, type: 'folder', isFolder: true, sizeStr: '', modifiedStr: ''),
                      '',
                    );
                  },
                  onCreateFolder: () => _createFolder(context, ref),
                ),
              ),
              child: centerAndRight,
            ),
          ),
        ],
      ),
    );
  }
}
