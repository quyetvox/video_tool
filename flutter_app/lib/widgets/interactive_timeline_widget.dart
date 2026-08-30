import 'package:flutter/material.dart';
import '../core/app_colors.dart';
import '../utils/time_format_utils.dart';

class InteractiveTimelineWidget extends StatefulWidget {
  final double duration;
  final double currentTime;
  final double startTime;
  final double endTime;
  final Function(double start, double end) onRangeChange;
  final Function(double timeSec) onSeek;
  final VoidCallback onCutTrim;
  final bool isAccurateCut;
  final Function(bool accurate) onToggleAccurateCut;
  final bool isProcessing;

  const InteractiveTimelineWidget({
    super.key,
    required this.duration,
    required this.currentTime,
    required this.startTime,
    required this.endTime,
    required this.onRangeChange,
    required this.onSeek,
    required this.onCutTrim,
    required this.isAccurateCut,
    required this.onToggleAccurateCut,
    this.isProcessing = false,
  });

  @override
  State<InteractiveTimelineWidget> createState() => _InteractiveTimelineWidgetState();
}

class _InteractiveTimelineWidgetState extends State<InteractiveTimelineWidget> {
  double _zoomLevel = 1.0;
  String? _draggingHandle; // 'start' | 'end' | 'playhead'
  late TextEditingController _startCtrl;
  late TextEditingController _endCtrl;

  @override
  void initState() {
    super.initState();
    _startCtrl = TextEditingController(text: TimeFormatUtils.formatSubtitleTime(widget.startTime));
    _endCtrl = TextEditingController(text: TimeFormatUtils.formatSubtitleTime(widget.endTime));
  }

  @override
  void didUpdateWidget(covariant InteractiveTimelineWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.startTime != widget.startTime && !_startCtrl.text.startsWith(TimeFormatUtils.formatSubtitleTime(widget.startTime))) {
      _startCtrl.text = TimeFormatUtils.formatSubtitleTime(widget.startTime);
    }
    if (oldWidget.endTime != widget.endTime && !_endCtrl.text.startsWith(TimeFormatUtils.formatSubtitleTime(widget.endTime))) {
      _endCtrl.text = TimeFormatUtils.formatSubtitleTime(widget.endTime);
    }
  }

  @override
  void dispose() {
    _startCtrl.dispose();
    _endCtrl.dispose();
    super.dispose();
  }

  void _handleStartSubmit(String val) {
    final sec = TimeFormatUtils.parseTimecodeToSeconds(val);
    if (sec < widget.endTime) {
      widget.onRangeChange(sec, widget.endTime);
    }
  }

  void _handleEndSubmit(String val) {
    final sec = TimeFormatUtils.parseTimecodeToSeconds(val);
    if (sec > widget.startTime) {
      widget.onRangeChange(widget.startTime, sec);
    }
  }

  void _select10sAtPlayhead() {
    final start = widget.currentTime;
    final end = (widget.currentTime + 10.0).clamp(0.0, widget.duration > 0 ? widget.duration : 100.0);
    widget.onRangeChange(start, end);
  }

  void _selectFirst10s() {
    final end = 10.0.clamp(0.0, widget.duration > 0 ? widget.duration : 100.0);
    widget.onRangeChange(0.0, end);
  }

  @override
  Widget build(BuildContext context) {
    final effectiveDuration = widget.duration > 0 ? widget.duration : 100.0;
    final startRatio = (widget.startTime / effectiveDuration).clamp(0.0, 1.0);
    final endRatio = (widget.endTime / effectiveDuration).clamp(0.0, 1.0);
    final playheadRatio = (widget.currentTime / effectiveDuration).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(
          top: BorderSide(color: AppColors.border),
          bottom: BorderSide(color: AppColors.border),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── TOOLBAR: Trimmer Tag, Speed switch, Millisecond inputs, Shortcuts, Action button ──
          Row(
            children: [
              // 1. Trimmer Tag Label
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primaryMuted,
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(color: AppColors.primary.withOpacity(0.4)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.content_cut, size: 12, color: AppColors.primary),
                    SizedBox(width: 4),
                    Text(
                      'Trimmer',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 8),

              // 2. Speed Toggle: Siêu Tốc vs Chuẩn Frame
              Container(
                decoration: BoxDecoration(
                  color: AppColors.surfaceDark,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    InkWell(
                      onTap: () => widget.onToggleAccurateCut(false),
                      borderRadius: BorderRadius.circular(5),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: !widget.isAccurateCut ? AppColors.statusCompletedBg : Colors.transparent,
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          '⚡ Siêu Tốc (~0.3s)',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                            color: !widget.isAccurateCut ? AppColors.statusCompleted : AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                    InkWell(
                      onTap: () => widget.onToggleAccurateCut(true),
                      borderRadius: BorderRadius.circular(5),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: widget.isAccurateCut ? AppColors.primaryMuted : Colors.transparent,
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          '🎯 Chuẩn Frame (~1s)',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                            color: widget.isAccurateCut ? AppColors.primary : AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 8),

              // 3. Millisecond Precision Inputs
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.surfaceDark,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Từ: ', style: TextStyle(color: AppColors.textMuted, fontSize: 10.5)),
                    SizedBox(
                      width: 80,
                      height: 22,
                      child: TextField(
                        controller: _startCtrl,
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Colors.white),
                        decoration: const InputDecoration(
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                          border: InputBorder.none,
                        ),
                        onSubmitted: _handleStartSubmit,
                      ),
                    ),
                    const Text('— ', style: TextStyle(color: AppColors.textMuted, fontSize: 10.5)),
                    const Text('Đến: ', style: TextStyle(color: AppColors.textMuted, fontSize: 10.5)),
                    SizedBox(
                      width: 80,
                      height: 22,
                      child: TextField(
                        controller: _endCtrl,
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Colors.white),
                        decoration: const InputDecoration(
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                          border: InputBorder.none,
                        ),
                        onSubmitted: _handleEndSubmit,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 8),

              // 4. Quick 10s Shortcuts
              InkWell(
                onTap: _select10sAtPlayhead,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceLight,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: const Text('⏱️ 10s tại Playhead', style: TextStyle(fontSize: 10, color: AppColors.textSecondary)),
                ),
              ),
              const SizedBox(width: 4),
              InkWell(
                onTap: _selectFirst10s,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceLight,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: const Text('⚡ 10s Đầu', style: TextStyle(fontSize: 10, color: AppColors.primary)),
                ),
              ),

              const Spacer(),

              // 5. Direct Action Cut Button (Màu vàng chủ đạo)
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.primaryText,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                ),
                icon: widget.isProcessing
                    ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primaryText))
                    : const Icon(Icons.content_cut, size: 13, color: AppColors.primaryText),
                label: const Text(
                  '✂️ Cắt Video',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.primaryText),
                ),
                onPressed: widget.isProcessing ? null : widget.onCutTrim,
              ),

              const SizedBox(width: 8),

              // 6. Zoom Slider
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.zoom_out, size: 13, color: AppColors.textMuted),
                  SizedBox(
                    width: 70,
                    child: SliderTheme(
                      data: const SliderThemeData(
                        trackHeight: 2,
                        thumbShape: RoundSliderThumbShape(enabledThumbRadius: 4),
                        overlayShape: RoundSliderOverlayShape(overlayRadius: 8),
                        activeTrackColor: AppColors.primary,
                        inactiveTrackColor: AppColors.border,
                        thumbColor: AppColors.primary,
                      ),
                      child: Slider(
                        value: _zoomLevel,
                        min: 1.0,
                        max: 3.0,
                        onChanged: (v) => setState(() => _zoomLevel = v),
                      ),
                    ),
                  ),
                  const Icon(Icons.zoom_in, size: 13, color: AppColors.textMuted),
                ],
              ),
            ],
          ),

          const SizedBox(height: 6),

          // ── VISUAL FILMSTRIP TIMELINE CANVAS ──
          LayoutBuilder(
            builder: (context, constraints) {
              final totalWidth = constraints.maxWidth;

              void seekToX(double localX) {
                final ratio = (localX / totalWidth).clamp(0.0, 1.0);
                final timeSec = ratio * effectiveDuration;
                widget.onSeek(timeSec);
              }

              void updateRangeFromX(double localX) {
                final ratio = (localX / totalWidth).clamp(0.0, 1.0);
                final targetSec = ratio * effectiveDuration;

                if (_draggingHandle == 'start') {
                  final newStart = targetSec.clamp(0.0, widget.endTime - 0.05);
                  widget.onRangeChange(newStart, widget.endTime);
                } else if (_draggingHandle == 'end') {
                  final newEnd = targetSec.clamp(widget.startTime + 0.05, effectiveDuration);
                  widget.onRangeChange(widget.startTime, newEnd);
                } else if (_draggingHandle == 'playhead') {
                  widget.onSeek(targetSec);
                }
              }

              final boxLeft = startRatio * totalWidth;
              final boxWidth = ((endRatio - startRatio) * totalWidth).clamp(10.0, totalWidth);
              final playheadX = playheadRatio * totalWidth;

              return GestureDetector(
                onTapDown: (details) => seekToX(details.localPosition.dx),
                onPanStart: (details) {
                  final x = details.localPosition.dx;
                  if ((x - boxLeft).abs() < 12) {
                    _draggingHandle = 'start';
                  } else if ((x - (boxLeft + boxWidth)).abs() < 12) {
                    _draggingHandle = 'end';
                  } else if ((x - playheadX).abs() < 10) {
                    _draggingHandle = 'playhead';
                  } else {
                    _draggingHandle = 'playhead';
                    seekToX(x);
                  }
                },
                onPanUpdate: (details) => updateRangeFromX(details.localPosition.dx),
                onPanEnd: (_) => _draggingHandle = null,
                child: Container(
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceDark,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Stack(
                    children: [
                      // Filmstrip background pattern
                      Positioned.fill(
                        child: CustomPaint(
                          painter: _TimelineRulerPainter(
                            duration: effectiveDuration,
                            stepSec: effectiveDuration > 300 ? 60 : (effectiveDuration > 60 ? 15 : 5),
                          ),
                        ),
                      ),

                      // Selection Range Box (Vàng Hổ Phách sang trọng)
                      Positioned(
                        left: boxLeft,
                        width: boxWidth,
                        top: 2,
                        bottom: 2,
                        child: Container(
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: AppColors.primary,
                              width: 1.5,
                            ),
                          ),
                          child: const Center(
                            child: Text(
                              '✂️ ĐOẠN ĐƯỢC CHỌN',
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.bold,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                        ),
                      ),

                      // Left Handle
                      Positioned(
                        left: boxLeft - 4,
                        top: 0,
                        bottom: 0,
                        width: 8,
                        child: Container(
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(2),
                          ),
                          child: const Center(
                            child: Icon(Icons.drag_handle, size: 8, color: AppColors.primaryText),
                          ),
                        ),
                      ),

                      // Right Handle
                      Positioned(
                        left: boxLeft + boxWidth - 4,
                        top: 0,
                        bottom: 0,
                        width: 8,
                        child: Container(
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(2),
                          ),
                          child: const Center(
                            child: Icon(Icons.drag_handle, size: 8, color: AppColors.primaryText),
                          ),
                        ),
                      ),

                      // Playhead Line
                      Positioned(
                        left: playheadX - 1,
                        top: 0,
                        bottom: 0,
                        child: Container(
                          width: 2,
                          color: Colors.white,
                          child: Align(
                            alignment: Alignment.topCenter,
                            child: Container(
                              width: 8,
                              height: 6,
                              decoration: const BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.vertical(bottom: Radius.circular(3)),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _TimelineRulerPainter extends CustomPainter {
  final double duration;
  final double stepSec;

  _TimelineRulerPainter({required this.duration, required this.stepSec});

  @override
  void paint(Canvas canvas, Size size) {
    final tickPaint = Paint()
      ..color = AppColors.border
      ..strokeWidth = 1;

    const textStyle = TextStyle(
      color: AppColors.textMuted,
      fontSize: 8.5,
      fontFamily: 'monospace',
    );

    final totalTicks = (duration / stepSec).ceil();
    for (int i = 0; i <= totalTicks; i++) {
      final s = i * stepSec;
      if (s > duration) break;
      final x = (s / duration) * size.width;

      // Draw tick line
      canvas.drawLine(Offset(x, 0), Offset(x, 8), tickPaint);

      // Draw label
      final textSpan = TextSpan(text: TimeFormatUtils.formatDuration(s), style: textStyle);
      final tp = TextPainter(text: textSpan, textDirection: TextDirection.ltr);
      tp.layout();
      tp.paint(canvas, Offset(x + 2, 2));
    }
  }

  @override
  bool shouldRepaint(covariant _TimelineRulerPainter oldDelegate) {
    return oldDelegate.duration != duration || oldDelegate.stepSec != stepSec;
  }
}
