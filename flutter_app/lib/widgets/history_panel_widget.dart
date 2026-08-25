import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/studio_state_notifier.dart';

class HistoryPanelWidget extends ConsumerWidget {
  const HistoryPanelWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.watch(studioStateProvider.notifier);
    final history = notifier.history;
    final activeIndex = notifier.historyIndex;

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A),
        border: Border(bottom: BorderSide(color: Color(0xFF1E293B))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: const BoxDecoration(
              color: Color(0xFF0B1120),
              border: Border(bottom: BorderSide(color: Color(0xFF1E293B))),
            ),
            child: Row(
              children: [
                const Icon(Icons.history, size: 13, color: Color(0xFF8B5CF6)),
                const SizedBox(width: 6),
                const Text(
                  'Lịch sử thao tác',
                  style: TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Text(
                  '${history.length} bước',
                  style: const TextStyle(color: Color(0xFF64748B), fontSize: 9.5),
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
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: isActive ? const Color(0xFF8B5CF6).withOpacity(0.12) : Colors.transparent,
                      border: Border(
                        left: BorderSide(
                          color: isActive ? const Color(0xFF8B5CF6) : Colors.transparent,
                          width: 2.5,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isActive ? const Color(0xFF8B5CF6) : const Color(0xFF475569),
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
                                  color: isActive ? Colors.white : const Color(0xFF94A3B8),
                                  fontSize: 10.5,
                                  fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                              Text(
                                item.time,
                                style: const TextStyle(color: Color(0xFF475569), fontSize: 8.5),
                              ),
                            ],
                          ),
                        ),
                        if (isActive)
                          const Icon(Icons.check, size: 12, color: Color(0xFF34D399)),
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
