import 'package:flutter/material.dart';
import '../core/app_colors.dart';

class TimecodeInputWidget extends StatefulWidget {
  final double value;
  final double minValue;
  final double maxValue;
  final ValueChanged<double> onChanged;
  final VoidCallback? onSetFromPlayhead;

  const TimecodeInputWidget({
    super.key,
    required this.value,
    this.minValue = 0.0,
    this.maxValue = 36000.0,
    required this.onChanged,
    this.onSetFromPlayhead,
  });

  @override
  State<TimecodeInputWidget> createState() => _TimecodeInputWidgetState();
}

class _TimecodeInputWidgetState extends State<TimecodeInputWidget> {
  late TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _formatTime(widget.value));
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(covariant TimecodeInputWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value && !_focusNode.hasFocus) {
      _controller.text = _formatTime(widget.value);
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (!_focusNode.hasFocus) {
      _commitValue();
    }
  }

  String _formatTime(double sec) {
    if (sec.isNaN || sec < 0) return '00:00:00.000';
    final hrs = (sec / 3600).floor();
    final mins = ((sec % 3600) / 60).floor();
    final secs = (sec % 60).floor();
    final ms = ((sec % 1) * 1000).round();

    final hStr = hrs.toString().padLeft(2, '0');
    final mStr = mins.toString().padLeft(2, '0');
    final sStr = secs.toString().padLeft(2, '0');
    final msStr = ms.toString().padLeft(3, '0');

    return '$hStr:$mStr:$sStr.$msStr';
  }

  double _parseTime(String str) {
    final s = str.trim();
    if (s.isEmpty) return 0.0;
    try {
      if (s.contains(':')) {
        final parts = s.split(':');
        if (parts.length == 3) {
          final h = double.tryParse(parts[0]) ?? 0;
          final m = double.tryParse(parts[1]) ?? 0;
          final sec = double.tryParse(parts[2]) ?? 0;
          return h * 3600 + m * 60 + sec;
        } else if (parts.length == 2) {
          final m = double.tryParse(parts[0]) ?? 0;
          final sec = double.tryParse(parts[1]) ?? 0;
          return m * 60 + sec;
        }
      }
      return double.tryParse(s) ?? 0.0;
    } catch (_) {
      return 0.0;
    }
  }

  void _commitValue() {
    final parsed = _parseTime(_controller.text);
    final clamped = parsed.clamp(widget.minValue, widget.maxValue);
    _controller.text = _formatTime(clamped);
    widget.onChanged(clamped);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 26,
      decoration: BoxDecoration(
        color: AppColors.surfaceDark,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: _focusNode.hasFocus ? AppColors.primary : AppColors.border,
          width: _focusNode.hasFocus ? 1.0 : 0.6,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              cursorColor: AppColors.primary,
              style: const TextStyle(
                fontFamily: 'monospace',
                color: Colors.white,
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
              ),
              decoration: const InputDecoration(
                isDense: true,
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              ),
              onSubmitted: (_) => _commitValue(),
            ),
          ),
          if (widget.onSetFromPlayhead != null)
            IconButton(
              icon: const Icon(Icons.access_time, size: 12, color: AppColors.primary),
              tooltip: 'Lấy mốc thời gian hiện tại từ Playhead',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
              onPressed: widget.onSetFromPlayhead,
            ),
        ],
      ),
    );
  }
}
