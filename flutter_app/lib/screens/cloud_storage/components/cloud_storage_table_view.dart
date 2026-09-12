import 'package:flutter/material.dart';
import '../../../core/app_colors.dart';
import '../../../core/cloud_storage_state.dart';
import '../../../models/cloud_item.dart';
import 'cloud_storage_components.dart';

/// Table View for Cloud Storage files and folders.
class CloudStorageTableView extends StatelessWidget {
  final List<CloudItem> items;
  final CloudStorageState state;
  final CloudStorageNotifier notifier;
  final void Function(CloudItem item) onSyncUp;
  final void Function(CloudItem item) onSyncDown;
  final void Function(CloudItem item) onOffload;
  final void Function(CloudItem item) onDelete;

  const CloudStorageTableView({
    super.key,
    required this.items,
    required this.state,
    required this.notifier,
    required this.onSyncUp,
    required this.onSyncDown,
    required this.onOffload,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
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
                const Expanded(
                  flex: 4,
                  child: Text('TÊN', style: TextStyle(color: AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.w600)),
                ),
                const Expanded(
                  flex: 2,
                  child: Text('LOẠI', style: TextStyle(color: AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.w600)),
                ),
                const Expanded(
                  flex: 2,
                  child: Text('KÍCH THƯỚC', style: TextStyle(color: AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.w600)),
                ),
                const Expanded(
                  flex: 2,
                  child: Text('TRẠNG THÁI', style: TextStyle(color: AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.w600)),
                ),
                const Expanded(
                  flex: 2,
                  child: Text('NGÀY SỬA ĐỔI', style: TextStyle(color: AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.w600)),
                ),
                const SizedBox(
                  width: 110,
                  child: Text('THAO TÁC', style: TextStyle(color: AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.w600)),
                ),
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
                  child: CloudStorageStatusBadge(item: item),
                ),

                // Modified Date
                Expanded(
                  flex: 2,
                  child: Text(
                    item.modifiedStr,
                    style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
                  ),
                ),

                // Per-Row 4 Action Icons
                SizedBox(
                  width: 110,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.cloud_upload, size: 13, color: AppColors.primary),
                        tooltip: 'Tải lên Cloud (Sync-Up)',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                        onPressed: () => onSyncUp(item),
                      ),
                      IconButton(
                        icon: const Icon(Icons.cloud_download, size: 13, color: Color(0xFF60A5FA)),
                        tooltip: 'Tải về máy (Sync-Down)',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                        onPressed: () => onSyncDown(item),
                      ),
                      IconButton(
                        icon: const Icon(Icons.cleaning_services, size: 13, color: Color(0xFFFBBF24)),
                        tooltip: 'Giải phóng SSD (Offload)',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                        onPressed: () => onOffload(item),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 13, color: AppColors.statusFailed),
                        tooltip: 'Xóa trên Cloud',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                        onPressed: () => onDelete(item),
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
