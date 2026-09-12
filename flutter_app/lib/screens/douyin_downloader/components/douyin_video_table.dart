import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/app_colors.dart';
import '../../../models/douyin_video_item.dart';
import '../../../widgets/app_kit.dart';

/// Table / List view of extracted Douyin videos with selection, search, and download actions.
class DouyinVideoTable extends StatelessWidget {
  final List<DouyinVideoItem> displayItems;
  final DouyinVideoItem? selectedItem;
  final Set<int> selectedIndexes;
  final String searchQuery;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onToggleSelectAll;
  final ValueChanged<int> onToggleSelect;
  final ValueChanged<DouyinVideoItem> onItemSelected;
  final ValueChanged<DouyinVideoItem> onDownloadSingle;
  final int downloadingIndex;
  final bool isDownloadingAll;
  final VoidCallback? onDownloadAll;
  final bool isDownloadingSequential;
  final int sequentialCurrent;
  final int sequentialTotal;
  final String sequentialStatus;
  final VoidCallback onDownloadSequential;
  final VoidCallback onCancelSequential;

  const DouyinVideoTable({
    super.key,
    required this.displayItems,
    required this.selectedItem,
    required this.selectedIndexes,
    required this.searchQuery,
    required this.onSearchChanged,
    required this.onToggleSelectAll,
    required this.onToggleSelect,
    required this.onItemSelected,
    required this.onDownloadSingle,
    required this.downloadingIndex,
    required this.isDownloadingAll,
    required this.onDownloadAll,
    required this.isDownloadingSequential,
    required this.sequentialCurrent,
    required this.sequentialTotal,
    required this.sequentialStatus,
    required this.onDownloadSequential,
    required this.onCancelSequential,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);

    return Column(
      children: [
        // Search & Batch Download Bar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              InkWell(
                onTap: onToggleSelectAll,
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AppCheckbox(
                        value: displayItems.isNotEmpty && displayItems.every((e) => selectedIndexes.contains(e.index)),
                        onChanged: (_) => onToggleSelectAll(),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Tất cả (${displayItems.length})',
                        style: TextStyle(color: c.textPrimary, fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
              if (selectedIndexes.isNotEmpty) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: c.primary.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: c.primary.withOpacity(0.4), width: 0.8),
                  ),
                  child: Text(
                    'Đã chọn: ${selectedIndexes.length}',
                    style: TextStyle(color: c.primary, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
              const Spacer(),
              if (isDownloadingSequential) ...[
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFEF4444),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    minimumSize: const Size(0, 28),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
                  ),
                  icon: const Icon(Icons.stop_circle_outlined, size: 14),
                  label: const Text('Dừng Tải', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  onPressed: onCancelSequential,
                ),
              ] else ...[
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: selectedIndexes.isNotEmpty ? const Color(0xFF10B981) : c.surfaceLight,
                    foregroundColor: selectedIndexes.isNotEmpty ? Colors.white : c.textMuted,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    minimumSize: const Size(0, 28),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
                  ),
                  icon: const Icon(Icons.playlist_play, size: 15),
                  label: Text(
                    selectedIndexes.isEmpty
                        ? 'Tải Đã Chọn'
                        : 'Tải Tuần Tự (${selectedIndexes.length})',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                  onPressed: selectedIndexes.isEmpty || isDownloadingAll ? null : onDownloadSequential,
                ),
                const SizedBox(width: 6),
                AppButton.primary(
                  label: 'Tải Hết (${displayItems.length})',
                  icon: Icons.download,
                  height: 28,
                  fontSize: 11,
                  isLoading: isDownloadingAll,
                  onPressed: isDownloadingAll || isDownloadingSequential ? null : onDownloadAll,
                ),
              ],
            ],
          ),
        ),

        // Sequential Download Progress Banner
        if (isDownloadingSequential)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withOpacity(0.12),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFF10B981).withOpacity(0.35)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const SizedBox(
                      width: 11,
                      height: 11,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF10B981)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        sequentialStatus,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Color(0xFF34D399), fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                    ),
                    Text(
                      '$sequentialCurrent/$sequentialTotal',
                      style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: sequentialTotal > 0 ? (sequentialCurrent / sequentialTotal) : 0,
                    minHeight: 3,
                    backgroundColor: Colors.black26,
                    valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF10B981)),
                  ),
                ),
              ],
            ),
          ),

        // Search Input
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: AppSearchField(
            hint: 'Lọc link theo ID, bitrate hoặc URL...',
            onChanged: onSearchChanged,
          ),
        ),

        const SizedBox(height: 8),

        // Items List
        Expanded(
          child: displayItems.isEmpty
              ? Center(
                  child: Text('Không có video nào khớp với bộ lọc', style: TextStyle(color: c.textMuted, fontSize: 11)),
                )
              : ListView.builder(
                  itemCount: displayItems.length,
                  itemBuilder: (ctx, idx) {
                    final it = displayItems[idx];
                    final isSelected = selectedItem?.index == it.index;
                    final isChecked = selectedIndexes.contains(it.index);

                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(
                        color: isSelected ? c.surfaceLight : c.surfaceDark,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: isSelected
                              ? c.primary
                              : (isChecked ? c.primary.withOpacity(0.5) : c.border),
                          width: 0.8,
                        ),
                      ),
                      child: ListTile(
                        dense: true,
                        leading: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AppCheckbox(
                              value: isChecked,
                              onChanged: (_) => onToggleSelect(it.index),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '#${it.index.toString().padLeft(2, '0')}',
                              style: TextStyle(color: c.textMuted, fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        title: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: c.primary.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: Text(it.resolution, style: TextStyle(color: c.primary, fontSize: 9.5, fontWeight: FontWeight.bold)),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                it.filename,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: c.textPrimary, fontSize: 11.5, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                        subtitle: Row(
                          children: [
                            if (it.isDownloaded)
                              Container(
                                margin: const EdgeInsets.only(top: 4, right: 6),
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: AppColors.statusCompleted.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                child: const Text('✓ Đã có trong src/', style: TextStyle(color: AppColors.statusCompleted, fontSize: 9)),
                              ),
                            Expanded(
                              child: Text(
                                it.directUrl,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: c.textMuted, fontSize: 10),
                              ),
                            ),
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: Icon(Icons.copy, size: 14, color: c.textSecondary),
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: it.directUrl));
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã copy link!')));
                              },
                            ),
                            IconButton(
                              icon: downloadingIndex == it.index
                                  ? SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: c.primary))
                                  : const Icon(Icons.download, size: 16, color: AppColors.statusCompleted),
                              onPressed: () => onDownloadSingle(it),
                            ),
                          ],
                        ),
                        onTap: () => onItemSelected(it),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
