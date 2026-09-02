import 'package:flutter/material.dart';
import '../core/app_colors.dart';
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
    final c = AppColors.of(context);
    final filteredLogs = widget.logs.where((log) {
      if (_levelFilter == 'all') return true;
      if (_levelFilter == 'error') return log.isError;
      if (_levelFilter == 'success') return log.isSuccess;
      if (_levelFilter == 'warning') {
        final lower = log.text.toLowerCase();
        return log.type == 'system-warning' || lower.contains('warning') || lower.contains('cảnh báo');
      }
      if (_levelFilter == 'info') {
        final lower = log.text.toLowerCase();
        final isWarning = log.type == 'system-warning' || lower.contains('warning') || lower.contains('cảnh báo');
        return !log.isError && !log.isSuccess && !isWarning;
      }
      return true;
    }).toList();

    return Container(
      color: c.surfaceDark,
      child: Column(
        children: [
          // Header Bar
          Container(
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: c.surface,
              border: Border(bottom: BorderSide(color: c.border)),
            ),
            child: Row(
              children: [
                Icon(Icons.terminal, size: 14, color: c.primary),
                const SizedBox(width: 6),
                Text(
                  'ENGINE CONSOLE',
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(width: 8),
                if (widget.isProcessRunning)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: c.statusProcessingBg,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 8,
                          height: 8,
                          child: CircularProgressIndicator(strokeWidth: 1.2, color: c.statusProcessing),
                        ),
                        const SizedBox(width: 4),
                        Text('RUNNING', style: TextStyle(color: c.statusProcessing, fontSize: 9.5, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),

                const Spacer(),

                // Level Filter
                Container(
                  height: 24,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  decoration: BoxDecoration(
                    color: c.surfaceDark,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: c.border, width: 0.8),
                  ),
                  child: DropdownButton<String>(
                    value: _levelFilter,
                    underline: const SizedBox(),
                    dropdownColor: c.surface,
                    icon: Icon(Icons.arrow_drop_down, size: 14, color: c.textSecondary),
                    style: TextStyle(color: c.textPrimary, fontSize: 10.5),
                    items: const [
                      DropdownMenuItem(value: 'all', child: Text('All Levels')),
                      DropdownMenuItem(value: 'info', child: Text('INFO only')),
                      DropdownMenuItem(value: 'success', child: Text('SUCCESS only')),
                      DropdownMenuItem(value: 'warning', child: Text('WARNING only')),
                      DropdownMenuItem(value: 'error', child: Text('ERROR only')),
                    ],
                    onChanged: (v) => setState(() => _levelFilter = v!),
                  ),
                ),

                // Stop Button (Only visible when process is active)
                if (widget.isProcessRunning) ...[
                  const SizedBox(width: 6),
                  InkWell(
                    onTap: widget.onStopProcess,
                    borderRadius: BorderRadius.circular(5),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceLight,
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(color: AppColors.statusFailed.withOpacity(0.4)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.stop_circle_outlined, size: 13, color: AppColors.statusFailed),
                          SizedBox(width: 4),
                          Text(
                            'Stop',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                              color: AppColors.statusFailed,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: 6),

                // Clear Button
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 14, color: AppColors.textSecondary),
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
                        Icon(Icons.terminal, size: 28, color: AppColors.textMuted),
                        SizedBox(height: 6),
                        Text('Chưa có logs tiến trình nào', style: TextStyle(color: AppColors.textMuted, fontSize: 10.5)),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(8),
                    itemCount: filteredLogs.length,
                    itemBuilder: (ctx, idx) {
                      final log = filteredLogs[idx];
                      final textColor = AppColors.resolveLogColor(
                        log.text,
                        type: log.type,
                        isError: log.isError,
                        isSuccess: log.isSuccess,
                      );

                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 1),
                        child: SelectableText.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: '[${log.timeStr}] ',
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 10.5,
                                  color: AppColors.logTimestamp,
                                ),
                              ),
                              TextSpan(
                                text: log.message,
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 10.5,
                                  color: textColor,
                                  height: 1.35,
                                ),
                              ),
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
