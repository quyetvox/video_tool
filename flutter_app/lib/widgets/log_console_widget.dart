import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/app_colors.dart';
import '../core/providers.dart';
import '../core/python_bridge.dart';
import '../models/job_info.dart';

class LogConsoleWidget extends ConsumerStatefulWidget {
  final String? jobId;
  final double? height;
  final bool isCollapsible;
  final VoidCallback? onClose;

  const LogConsoleWidget({
    super.key,
    this.jobId,
    this.height,
    this.isCollapsible = false,
    this.onClose,
  });

  @override
  ConsumerState<LogConsoleWidget> createState() => _LogConsoleWidgetState();
}

class _LogConsoleWidgetState extends ConsumerState<LogConsoleWidget> {
  final ScrollController _scrollController = ScrollController();
  final List<LogEntry> _logs = [];
  bool _autoScroll = true;
  String _searchFilter = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Load initial buffered logs
    final initial = PythonBridge.getBufferedLogs(widget.jobId ?? 'global');
    _logs.addAll(initial);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (!_autoScroll || !_scrollController.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Color _getLogColor(LogEntry log) {
    return AppColors.resolveLogColor(
      log.text,
      type: log.type,
      isError: log.isError,
      isSuccess: log.isSuccess,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Listen to log stream
    ref.listen<AsyncValue<LogEntry>>(
      widget.jobId != null ? jobLogsStreamProvider(widget.jobId!) : globalLogsStreamProvider,
      (previous, next) {
        next.whenData((entry) {
          setState(() {
            _logs.add(entry);
            if (_logs.length > PythonBridge.maxBufferLines) {
              _logs.removeAt(0);
            }
          });
          _scrollToBottom();
        });
      },
    );

    final filteredLogs = _searchFilter.isEmpty
        ? _logs
        : _logs.where((l) => l.text.toLowerCase().contains(_searchFilter.toLowerCase())).toList();

    final c = AppColors.of(context);

    return Container(
      height: widget.height,
      decoration: BoxDecoration(
        color: c.surfaceDark,
        border: Border(
          top: BorderSide(
            color: c.border,
            width: 1,
          ),
        ),
      ),
      child: Column(
        children: [
          // Toolbar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: c.surface,
              border: Border(bottom: BorderSide(color: c.border, width: 0.8)),
            ),
            child: Row(
              children: [
                Icon(Icons.terminal, size: 14, color: c.primary),
                const SizedBox(width: 8),
                Text(
                  widget.jobId != null ? 'Log tiến trình [${widget.jobId}]' : 'System Console Logs',
                  style: TextStyle(fontWeight: FontWeight.w500, fontSize: 11, color: c.textPrimary),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: c.surfaceDark,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: c.border, width: 0.6),
                  ),
                  child: Text(
                    '${filteredLogs.length} dòng',
                    style: TextStyle(fontSize: 10, color: c.textMuted),
                  ),
                ),
                const Spacer(),

                // Search Filter
                SizedBox(
                  width: 160,
                  height: 26,
                  child: TextField(
                    controller: _searchController,
                    onChanged: (val) => setState(() => _searchFilter = val),
                    style: TextStyle(fontSize: 11, color: c.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'Tìm kiếm log...',
                      hintStyle: TextStyle(fontSize: 11, color: c.textMuted),
                      prefixIcon: Icon(Icons.search, size: 14, color: c.textMuted),
                      contentPadding: EdgeInsets.zero,
                      filled: true,
                      fillColor: c.surfaceDark,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: BorderSide(color: c.border, width: 0.6),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: BorderSide(color: c.border, width: 0.6),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),

                // Auto Scroll Toggle
                IconButton(
                  tooltip: _autoScroll ? 'Tự cuộn: BẬT' : 'Tự cuộn: TẮT',
                  icon: Icon(
                    _autoScroll ? Icons.arrow_downward : Icons.pause,
                    size: 16,
                    color: _autoScroll ? c.primary : c.textMuted,
                  ),
                  onPressed: () {
                    setState(() => _autoScroll = !_autoScroll);
                    if (_autoScroll) _scrollToBottom();
                  },
                ),

                // Copy All
                IconButton(
                  tooltip: 'Sao chép toàn bộ log',
                  icon: Icon(Icons.copy, size: 16, color: c.textSecondary),
                  onPressed: () {
                    final allText = filteredLogs.map((l) => '[${l.time}] ${l.text}').join('\n');
                    Clipboard.setData(ClipboardData(text: allText));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Đã sao chép log vào Clipboard'), duration: Duration(seconds: 1)),
                    );
                  },
                ),

                // Clear
                IconButton(
                  tooltip: 'Xóa màn hình log',
                  icon: Icon(Icons.delete_sweep, size: 16, color: c.textSecondary),
                  onPressed: () => setState(() => _logs.clear()),
                ),

                if (widget.onClose != null)
                  IconButton(
                    tooltip: 'Đóng',
                    icon: Icon(Icons.close, size: 16, color: c.textSecondary),
                    onPressed: widget.onClose,
                  ),
              ],
            ),
          ),

          // Log Lines List
          Expanded(
            child: filteredLogs.isEmpty
                ? Center(
                    child: Text(
                      'Chưa có log đầu ra...',
                      style: TextStyle(color: c.textMuted, fontSize: 11, fontStyle: FontStyle.italic),
                    ),
                  )
                : SelectionArea(
                    child: ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      itemCount: filteredLogs.length,
                      itemBuilder: (context, index) {
                        final log = filteredLogs[index];
                        final color = _getLogColor(log);

                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 1),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '[${log.time}] ',
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 11,
                                  color: c.textMuted,
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  log.text,
                                  style: TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 11,
                                    color: color,
                                    height: 1.3,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
