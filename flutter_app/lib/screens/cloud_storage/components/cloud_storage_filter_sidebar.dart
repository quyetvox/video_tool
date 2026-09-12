import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/app_colors.dart';
import '../../../core/cloud_storage_state.dart';

/// Left sidebar for Cloud Storage with bucket metadata, filter dropdowns, and quick actions.
class CloudStorageFilterSidebar extends ConsumerWidget {
  final CloudStorageState state;
  final CloudStorageNotifier notifier;
  final VoidCallback onSyncUpProject;
  final VoidCallback onSyncDownProject;
  final VoidCallback onOffloadProject;
  final VoidCallback onCreateFolder;

  const CloudStorageFilterSidebar({
    super.key,
    required this.state,
    required this.notifier,
    required this.onSyncUpProject,
    required this.onSyncDownProject,
    required this.onOffloadProject,
    required this.onCreateFolder,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: state.isConnected
                          ? AppColors.statusCompleted
                          : AppColors.statusFailed,
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
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
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
            child: const Text(
              'Đặt lại bộ lọc',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 10.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),

        const SizedBox(height: 16),

        // 3. Quick Actions Header
        const Text(
          'HÀNH ĐỘNG NHANH',
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 6),

        _buildQuickActionButton(
          icon: Icons.create_new_folder,
          label: 'Tạo folder mới',
          iconColor: AppColors.primary,
          onTap: onCreateFolder,
        ),

        _buildQuickActionButton(
          icon: Icons.cloud_upload,
          label: 'Đẩy dự án lên GCS (Sync-Up)',
          iconColor: AppColors.primary,
          onTap: onSyncUpProject,
        ),

        _buildQuickActionButton(
          icon: Icons.cloud_download,
          label: 'Kéo dự án về Local (Sync-Down)',
          iconColor: const Color(0xFF60A5FA),
          onTap: onSyncDownProject,
        ),

        _buildQuickActionButton(
          icon: Icons.cleaning_services,
          label: 'Giải phóng bộ nhớ SSD',
          iconColor: const Color(0xFFFBBF24),
          onTap: onOffloadProject,
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
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textMuted,
            fontSize: 10,
            fontWeight: FontWeight.w500,
          ),
        ),
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
                  style: const TextStyle(
                    color: AppColors.textLight,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
