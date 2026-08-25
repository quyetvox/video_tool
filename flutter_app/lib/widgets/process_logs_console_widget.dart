import 'package:flutter/material.dart';
import '../models/job_info.dart';

class ProcessLogsConsoleWidget extends StatefulWidget {
  final List<LogEntry> logs;
  final bool isProcessRunning;
  final VoidCallback onClearLogs;
  final VoidCallback onStopProcess;

  const ProcessLogsConsoleWidget({
    super.key,
    required this.logs,
    required this.isProcessRunning,
    required this.onClearLogs,
    required this.onStopProcess,
  });

  @override
  State<ProcessLogsConsoleWidget> createState() => _ProcessLogsConsoleWidgetState();
}

class _ProcessLogsConsoleWidgetState extends State<ProcessLogsConsoleWidget> {
  String _levelFilter = 'all'; // 'all' | 'info' | 'success' | 'error'
  final ScrollController _scrollController = ScrollController();
  final bool _autoScroll = true;

  @override
  void didUpdateWidget(covariant ProcessLogsConsoleWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_autoScroll && widget.logs.length != oldWidget.logs.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filteredLogs = widget.logs.where((log) {
      if (_levelFilter == 'all') return true;
      if (_levelFilter == 'error') return log.isError;
      if (_levelFilter == 'success') return log.isSuccess;
      if (_levelFilter == 'info') return !log.isError && !log.isSuccess;
      return true;
    }).toList();

    return Container(
      color: const Color(0xFF0B1120),
      child: Column(
        children: [
          // Header Bar
          Container(
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: const BoxDecoration(
              color: Color(0xFF0F172A),
              border: Border(bottom: BorderSide(color: Color(0xFF1E293B))),
            ),
            child: Row(
              children: [
                const Icon(Icons.terminal, size: 14, color: Color(0xFF06B6D4)),
                const SizedBox(width: 6),
                const Text('Process Logs', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                if (widget.isProcessRunning) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF06B6D4).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: const Color(0xFF06B6D4).withOpacity(0.3)),
                    ),
                    child: const Row(
                      children: [
                        SizedBox(width: 8, height: 8, child: CircularProgressIndicator(strokeWidth: 1.5, color: Color(0xFF06B6D4))),
                        SizedBox(width: 4),
                        Text('Running', style: TextStyle(color: Color(0xFF06B6D4), fontSize: 9.5, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ],

                const Spacer(),

                // Level Filter
                Container(
                  height: 24,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: DropdownButton<String>(
                    value: _levelFilter,
                    underline: const SizedBox(),
                    dropdownColor: const Color(0xFF1E293B),
                    style: const TextStyle(color: Colors.white, fontSize: 10.5),
                    items: const [
                      DropdownMenuItem(value: 'all', child: Text('All Levels')),
                      DropdownMenuItem(value: 'info', child: Text('INFO only')),
                      DropdownMenuItem(value: 'success', child: Text('SUCCESS only')),
                      DropdownMenuItem(value: 'error', child: Text('ERROR only')),
                    ],
                    onChanged: (v) => setState(() => _levelFilter = v!),
                  ),
                ),

                const SizedBox(width: 6),

                // Stop Button (Always accessible to cancel any background/sidecar process)
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFDC2626),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    minimumSize: Size.zero,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    elevation: 0,
                  ),
                  icon: const Icon(Icons.stop_circle_outlined, size: 13),
                  label: const Text('Stop', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  onPressed: widget.onStopProcess,
                ),
                const SizedBox(width: 6),

                // Clear Button
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 14, color: Color(0xFF94A3B8)),
                  tooltip: 'Xóa log',
                  onPressed: widget.onClearLogs,
                ),
              ],
            ),
          ),

          // Monospace Logs Output
          Expanded(
            child: filteredLogs.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.terminal, size: 32, color: Color(0xFF334155)),
                        SizedBox(height: 6),
                        Text('Chưa có logs tiến trình nào', style: TextStyle(color: Color(0xFF64748B), fontSize: 11)),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(8),
                    itemCount: filteredLogs.length,
                    itemBuilder: (ctx, idx) {
                      final log = filteredLogs[idx];
                      Color textColor = const Color(0xFFCBD5E1);
                      if (log.isError) textColor = const Color(0xFFEF4444);
                      if (log.isSuccess) textColor = const Color(0xFF10B981);
                      if (log.isInfo) textColor = const Color(0xFF06B6D4);

                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 1),
                        child: SelectableText(
                          '[${log.timeStr}] ${log.message}',
                          style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: textColor),
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
