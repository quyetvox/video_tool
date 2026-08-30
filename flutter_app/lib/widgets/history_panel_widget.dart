import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/app_colors.dart';
import '../core/studio_state_notifier.dart';

class HistoryPanelWidget extends ConsumerWidget {
  const HistoryPanelWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.watch(studioStateProvider.notifier);
    final history = notifier.history;
    final activeIndex = notifier.historyIndex;
    final c = AppColors.of(context);

    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(bottom: BorderSide(color: c.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: c.surfaceDark,
              border: Border(bottom: BorderSide(color: c.border)),
            ),
            child: Row(
              children: [
                Icon(Icons.history, size: 12, color: c.primary),
                const SizedBox(width: 5),
                Text(
                  'Lịch sử thao tác',
                  style: TextStyle(color: c.textPrimary, fontSize: 10.5, fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                Text(
                  '${history.length} bước',
                  style: TextStyle(color: c.textMuted, fontSize: 9),
                ),
              ],
            ),
          ),

          // Scrollable History List
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 2),
              itemCount: history.length,
              itemBuilder: (ctx, idx) {
                final item = history[idx];
                final isActive = idx == activeIndex;

                return InkWell(
                  onTap: () => notifier.restoreAt(idx),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: isActive ? c.primary.withOpacity(0.12) : Colors.transparent,
                      border: Border(
                        left: BorderSide(
                          color: isActive ? c.primary : Colors.transparent,
                          width: 2,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 5,
                          height: 5,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isActive ? c.primary : c.textMuted,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: isActive ? c.textPrimary : c.textSecondary,
                                  fontSize: 10,
                                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                                ),
                              ),
                              Text(
                                item.time,
                                style: TextStyle(color: c.textMuted, fontSize: 8.5),
                              ),
                            ],
                          ),
                        ),
                        if (isActive)
                          Icon(Icons.check, size: 12, color: c.statusCompleted),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
