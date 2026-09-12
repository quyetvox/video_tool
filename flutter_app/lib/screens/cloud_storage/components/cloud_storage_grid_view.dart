import 'package:flutter/material.dart';
import '../../../core/app_colors.dart';
import '../../../core/cloud_storage_state.dart';
import '../../../models/cloud_item.dart';
import 'cloud_storage_components.dart';

/// Grid View for Cloud Storage files and folders.
class CloudStorageGridView extends StatelessWidget {
  final List<CloudItem> items;
  final CloudStorageState state;
  final CloudStorageNotifier notifier;

  const CloudStorageGridView({
    super.key,
    required this.items,
    required this.state,
    required this.notifier,
  });

  @override
  Widget build(BuildContext context) {
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
              border: Border.all(
                color: isSelected ? AppColors.primary : AppColors.border,
                width: 0.8,
              ),
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
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      item.sizeStr,
                      style: const TextStyle(fontSize: 9.5, color: AppColors.primary),
                    ),
                    CloudStorageStatusBadge(item: item, mini: true),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
