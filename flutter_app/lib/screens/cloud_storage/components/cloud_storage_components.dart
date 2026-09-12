import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/app_colors.dart';
import '../../../models/cloud_item.dart';

/// Status badge for cloud items (Synced, Local Only, Modified, Cloud Only).
class CloudStorageStatusBadge extends StatelessWidget {
  final CloudItem item;
  final bool mini;

  const CloudStorageStatusBadge({
    super.key,
    required this.item,
    this.mini = false,
  });

  @override
  Widget build(BuildContext context) {
    if (mini) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
        decoration: BoxDecoration(
          color: item.isSynced
              ? AppColors.statusCompletedBg
              : (item.isLocalOnly
                  ? AppColors.primary.withOpacity(0.2)
                  : const Color(0xFF38BDF8).withOpacity(0.2)),
          borderRadius: BorderRadius.circular(2),
        ),
        child: Text(
          item.isSynced ? 'SYNC' : (item.isLocalOnly ? 'LOCAL' : 'CLOUD'),
          style: TextStyle(
            fontSize: 7.5,
            fontWeight: FontWeight.bold,
            color: item.isSynced
                ? AppColors.statusCompleted
                : (item.isLocalOnly
                    ? AppColors.primary
                    : const Color(0xFF38BDF8)),
          ),
        ),
      );
    }

    if (item.isSynced) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
        decoration: BoxDecoration(
          color: AppColors.statusCompletedBg,
          borderRadius: BorderRadius.circular(3),
        ),
        child: const Text(
          '🔄 Đã Đồng Bộ',
          style: TextStyle(
            color: AppColors.statusCompleted,
            fontSize: 9,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    } else if (item.isLocalOnly) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
        decoration: BoxDecoration(
          color: AppColors.primary.withOpacity(0.15),
          borderRadius: BorderRadius.circular(3),
        ),
        child: const Text(
          '💻 Chỉ Local',
          style: TextStyle(
            color: AppColors.primary,
            fontSize: 9,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    } else if (item.isModified) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
        decoration: BoxDecoration(
          color: const Color(0xFFF97316).withOpacity(0.15),
          borderRadius: BorderRadius.circular(3),
        ),
        child: const Text(
          '⚠️ Khác Biệt',
          style: TextStyle(
            color: Color(0xFFF97316),
            fontSize: 9,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    } else {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
        decoration: BoxDecoration(
          color: const Color(0xFF38BDF8).withOpacity(0.15),
          borderRadius: BorderRadius.circular(3),
        ),
        child: const Text(
          '☁️ Chỉ Cloud',
          style: TextStyle(
            color: Color(0xFF38BDF8),
            fontSize: 9,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }
  }
}

/// Key-Value row with optional copy button for Cloud Storage Inspector.
class CloudStorageDetailRow extends StatelessWidget {
  final String label;
  final String value;
  final bool canCopy;

  const CloudStorageDetailRow({
    super.key,
    required this.label,
    required this.value,
    this.canCopy = false,
  });

  @override
  Widget build(BuildContext context) {
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
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (canCopy)
                IconButton(
                  icon: const Icon(Icons.copy, size: 11, color: AppColors.primary),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: value));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('📋 Đã sao chép: $value'),
                        duration: const Duration(seconds: 1),
                      ),
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
