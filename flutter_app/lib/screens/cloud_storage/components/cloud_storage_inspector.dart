import 'package:flutter/material.dart';
import '../../../core/app_colors.dart';
import '../../../core/cloud_storage_state.dart';
import '../../../models/cloud_item.dart';
import '../../../utils/time_format_utils.dart';
import 'cloud_storage_components.dart';

/// Right Inspector detail panel for selected CloudItem.
class CloudStorageInspector extends StatelessWidget {
  final CloudItem? item;
  final CloudStorageState state;
  final VoidCallback onSyncUp;
  final VoidCallback onSyncDown;
  final VoidCallback onOffload;
  final VoidCallback onDelete;

  const CloudStorageInspector({
    super.key,
    required this.item,
    required this.state,
    required this.onSyncUp,
    required this.onSyncDown,
    required this.onOffload,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    if (item == null) {
      return const Center(
        child: Text(
          'Chọn tệp để xem chi tiết',
          style: TextStyle(color: AppColors.textMuted, fontSize: 11.5),
        ),
      );
    }

    final current = item!;

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
              current.isFolder
                  ? Icons.folder
                  : (current.isVideo ? Icons.videocam : Icons.insert_drive_file),
              size: 22,
              color: current.isFolder ? AppColors.primary : const Color(0xFF60A5FA),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: Text(
            current.name,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(height: 4),
        Center(
          child: CloudStorageStatusBadge(item: current),
        ),

        const Divider(color: AppColors.border, height: 18),

        const Text(
          'CHI TIẾT',
          style: TextStyle(
            color: AppColors.primary,
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 5),

        CloudStorageDetailRow(
          label: 'Đường dẫn GCS',
          value: current.gcsUri.isNotEmpty
              ? current.gcsUri
              : 'gs://${state.bucketName}/${state.basePrefix}/${current.path}',
          canCopy: true,
        ),
        CloudStorageDetailRow(
          label: 'Kích thước',
          value: current.isFolder
              ? '${current.itemCount} mục (${TimeFormatUtils.formatFileSize(current.sizeBytes)})'
              : current.sizeStr,
        ),
        CloudStorageDetailRow(label: 'Cập nhật lần cuối', value: current.modifiedStr),
        CloudStorageDetailRow(label: 'Lớp lưu trữ', value: current.storageClass),
        const CloudStorageDetailRow(label: 'Vị trí Bucket', value: 'asia-southeast1 (Singapore)'),

        const Divider(color: AppColors.border, height: 18),

        const Text(
          'THAO TÁC',
          style: TextStyle(
            color: AppColors.statusCompleted,
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 6),

        // Action: Copy URI
        _buildInspectorActionButton(
          icon: Icons.copy,
          label: 'Sao chép URI (gs://)',
          color: const Color(0xFF60A5FA),
          onTap: () {
            final uri = current.gcsUri.isNotEmpty
                ? current.gcsUri
                : 'gs://${state.bucketName}/${state.basePrefix}/${current.path}';
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('📋 Đã sao chép: $uri'), duration: const Duration(seconds: 1)),
            );
          },
        ),

        const SizedBox(height: 4),

        // Action: Sync-Up
        _buildInspectorActionButton(
          icon: Icons.cloud_upload,
          label: 'Tải lên Cloud (Sync-Up)',
          color: AppColors.primary,
          onTap: onSyncUp,
        ),

        const SizedBox(height: 4),

        // Action: Sync-Down
        _buildInspectorActionButton(
          icon: Icons.cloud_download,
          label: 'Đồng bộ về máy (Sync-Down)',
          color: const Color(0xFF60A5FA),
          onTap: onSyncDown,
        ),

        const SizedBox(height: 4),

        // Action: Offload
        _buildInspectorActionButton(
          icon: Icons.cleaning_services,
          label: 'Giải phóng bộ nhớ SSD',
          color: const Color(0xFFFBBF24),
          onTap: onOffload,
        ),

        const SizedBox(height: 4),

        // Action: Delete
        _buildInspectorActionButton(
          icon: Icons.delete_outline,
          label: 'Xóa vĩnh viễn trên Cloud',
          color: AppColors.statusFailed,
          onTap: onDelete,
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color.withOpacity(0.3), width: 0.8),
        ),
        child: Row(
          children: [
            Icon(icon, size: 12.5, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: TextStyle(color: color, fontSize: 10.5, fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
