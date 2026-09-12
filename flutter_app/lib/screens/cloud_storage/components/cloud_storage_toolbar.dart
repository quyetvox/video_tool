import 'package:flutter/material.dart';
import '../../../core/app_colors.dart';
import '../../../core/cloud_storage_state.dart';

/// Top and sub-header toolbar for Cloud Storage.
/// Contains Breadcrumbs, Search, View switcher, and Batch action buttons.
class CloudStorageToolbar extends StatelessWidget {
  final CloudStorageState state;
  final CloudStorageNotifier notifier;
  final VoidCallback onOpenConfig;
  final VoidCallback onSyncDownBatch;
  final VoidCallback onSyncUpBatch;
  final VoidCallback onOffloadBatch;
  final VoidCallback onDeleteBatch;

  const CloudStorageToolbar({
    super.key,
    required this.state,
    required this.notifier,
    required this.onOpenConfig,
    required this.onSyncDownBatch,
    required this.onSyncUpBatch,
    required this.onOffloadBatch,
    required this.onDeleteBatch,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ── TOP HEADER BAR ──
        Container(
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: const BoxDecoration(
            color: AppColors.surface,
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            children: [
              const Icon(Icons.cloud_sync, color: AppColors.primary, size: 18),
              const SizedBox(width: 8),
              const Text(
                'Google Cloud Storage (GCS)',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.white),
              ),
              const SizedBox(width: 10),

              // Status Pill
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: state.isConnected ? AppColors.statusCompletedBg : AppColors.statusFailedBg,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  state.isConnected ? '● ĐÃ KẾT NỐI' : '● MẤT KẾT NỐI',
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.bold,
                    color: state.isConnected ? AppColors.statusCompleted : AppColors.statusFailed,
                  ),
                ),
              ),

              const Spacer(),

              // Search Box
              Container(
                width: 200,
                height: 28,
                decoration: BoxDecoration(
                  color: AppColors.surfaceDark,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: AppColors.border, width: 0.8),
                ),
                child: TextField(
                  onChanged: (val) => notifier.setSearchQuery(val),
                  style: const TextStyle(color: Colors.white, fontSize: 11),
                  decoration: const InputDecoration(
                    hintText: 'Tìm kiếm tệp...',
                    hintStyle: TextStyle(color: AppColors.textMuted, fontSize: 11),
                    prefixIcon: Icon(Icons.search, size: 13, color: AppColors.textMuted),
                    prefixIconConstraints: BoxConstraints(minWidth: 26, minHeight: 26),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 7),
                  ),
                ),
              ),

              const SizedBox(width: 8),

              // Grid / Table View Switcher
              Container(
                height: 28,
                decoration: BoxDecoration(
                  color: AppColors.surfaceDark,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: AppColors.border, width: 0.8),
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(
                        Icons.view_list,
                        size: 14,
                        color: !state.isGridView ? AppColors.primary : AppColors.textMuted,
                      ),
                      tooltip: 'Xem dạng Danh sách',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                      onPressed: () => notifier.setViewMode(false),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.grid_view,
                        size: 14,
                        color: state.isGridView ? AppColors.primary : AppColors.textMuted,
                      ),
                      tooltip: 'Xem dạng Lưới',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                      onPressed: () => notifier.setViewMode(true),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 8),

              // Config GCS Key Dialog Button
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.surfaceDark,
                  foregroundColor: AppColors.textLight,
                  side: const BorderSide(color: AppColors.border, width: 0.8),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                ),
                icon: const Icon(Icons.settings, size: 12, color: AppColors.primary),
                label: const Text('Cấu hình GCS', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w500)),
                onPressed: onOpenConfig,
              ),
            ],
          ),
        ),

        // ── BREADCRUMB BAR & BATCH ACTIONS ──
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: const BoxDecoration(
            color: AppColors.surface,
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            children: [
              if (state.currentPath.isNotEmpty) ...[
                IconButton(
                  icon: const Icon(Icons.arrow_back, size: 14, color: AppColors.primary),
                  tooltip: 'Quay lại thư mục cha',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => notifier.navigateUp(),
                ),
                const SizedBox(width: 8),
              ],

              // Breadcrumbs
              Expanded(
                child: _buildBreadcrumbs(state, notifier),
              ),

              // Batch Action Buttons
              if (state.selectedPaths.isNotEmpty) ...[
                Text(
                  'Đã chọn: ${state.selectedPaths.length}',
                  style: const TextStyle(color: AppColors.primary, fontSize: 10.5, fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 8),
                _buildBatchButton(
                  icon: Icons.cloud_download,
                  label: 'Tải về (${state.selectedPaths.length})',
                  color: const Color(0xFF60A5FA),
                  onTap: onSyncDownBatch,
                ),
                const SizedBox(width: 5),
                _buildBatchButton(
                  icon: Icons.cloud_upload,
                  label: 'Đẩy lên (${state.selectedPaths.length})',
                  color: AppColors.primary,
                  onTap: onSyncUpBatch,
                ),
                const SizedBox(width: 5),
                _buildBatchButton(
                  icon: Icons.cleaning_services,
                  label: 'Giải phóng',
                  color: const Color(0xFFFBBF24),
                  onTap: onOffloadBatch,
                ),
                const SizedBox(width: 5),
                _buildBatchButton(
                  icon: Icons.delete_outline,
                  label: 'Xóa',
                  color: AppColors.statusFailed,
                  onTap: onDeleteBatch,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

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

  Widget _buildBatchButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        height: 24,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color.withOpacity(0.35), width: 0.8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 11, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}
