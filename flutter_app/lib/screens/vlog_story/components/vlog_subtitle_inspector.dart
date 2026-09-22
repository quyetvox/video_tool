import 'package:flutter/material.dart';
import '../../../../core/app_colors.dart';
import '../../../../utils/time_format_utils.dart';
import '../controllers/vlog_story_controller.dart';

class VlogSubtitleInspector extends StatefulWidget {
  final VlogStoryState state;
  final VlogStoryController controller;
  final double currentTime;
  final Function(double timeSec)? onSeekToSubtitle;

  const VlogSubtitleInspector({
    super.key,
    required this.state,
    required this.controller,
    required this.currentTime,
    this.onSeekToSubtitle,
  });

  @override
  State<VlogSubtitleInspector> createState() => _VlogSubtitleInspectorState();
}

class _VlogSubtitleInspectorState extends State<VlogSubtitleInspector> {
  final Map<int, TextEditingController> _textControllers = {};

  @override
  void initState() {
    super.initState();
    _syncControllers();
  }

  @override
  void didUpdateWidget(covariant VlogSubtitleInspector oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncControllers();
  }

  void _syncControllers() {
    final currentIds = widget.state.segments.map((s) => s.id).toSet();

    // Xóa controller không còn dùng
    _textControllers.removeWhere((id, ctrl) {
      if (!currentIds.contains(id)) {
        ctrl.dispose();
        return true;
      }
      return false;
    });

    // Tạo mới hoặc cập nhật khi text thay đổi từ bên ngoài (nạp file)
    for (final seg in widget.state.segments) {
      if (!_textControllers.containsKey(seg.id)) {
        _textControllers[seg.id] = TextEditingController(text: seg.text);
      } else {
        if (_textControllers[seg.id]!.text != seg.text && _textControllers[seg.id]!.selection.isCollapsed) {
          _textControllers[seg.id]!.text = seg.text;
        }
      }
    }
  }

  @override
  void dispose() {
    for (final ctrl in _textControllers.values) {
      ctrl.dispose();
    }
    _textControllers.clear();
    super.dispose();
  }

  String _formatTime(double sec) {
    return TimeFormatUtils.formatDuration(sec);
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final segments = widget.state.segments;
    final isProcessing = widget.state.isProcessing;

    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(
          right: BorderSide(color: c.border),
        ),
      ),
      child: Column(
        children: [
          // ── 1. HEADER TOOLBAR ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: c.surfaceLight.withOpacity(0.4),
              border: Border(bottom: BorderSide(color: c.border)),
            ),
            child: Row(
              children: [
                const Icon(Icons.subtitles_rounded, size: 18, color: AppColors.primary),
                const SizedBox(width: 8),
                Text(
                  'Phụ Đề & Lời Kể (${segments.length})',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(width: 8),
                if (segments.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.statusCompleted.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: AppColors.statusCompleted.withOpacity(0.3)),
                    ),
                    child: const Text(
                      'Sẵn sàng Render',
                      style: TextStyle(fontSize: 10, color: AppColors.statusCompleted, fontWeight: FontWeight.w600),
                    ),
                  ),
                const Spacer(),
                // Nút Thêm câu
                IconButton(
                  icon: const Icon(Icons.add_circle_outline, size: 18),
                  tooltip: 'Thêm phân cảnh mới',
                  color: AppColors.primary,
                  onPressed: isProcessing ? null : () => widget.controller.addSegment(),
                ),
                // Nút Lưu kịch bản
                IconButton(
                  icon: const Icon(Icons.save_outlined, size: 18),
                  tooltip: 'Lưu kịch bản vào workspace',
                  color: c.textSecondary,
                  onPressed: segments.isEmpty || isProcessing ? null : () => widget.controller.saveScriptToDisk(),
                ),
              ],
            ),
          ),

          // ── 2. TABLE HEADER ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: c.surfaceDark.withOpacity(0.3),
              border: Border(bottom: BorderSide(color: c.border)),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 32,
                  child: Text('#', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: c.textMuted)),
                ),
                SizedBox(
                  width: 140,
                  child: Text('Mốc thời gian', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: c.textMuted)),
                ),
                Expanded(
                  child: Text('Nội dung lời kể (Click để sửa)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: c.textMuted)),
                ),
                SizedBox(
                  width: 72,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Text('Thao tác', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: c.textMuted)),
                  ),
                ),
              ],
            ),
          ),

          // ── 3. TABLE BODY (LIST OF SUBTITLES) ──
          Expanded(
            child: segments.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.speaker_notes_off_outlined, size: 42, color: c.textMuted.withOpacity(0.5)),
                        const SizedBox(height: 10),
                        Text(
                          'Chưa có kịch bản lời kể cho video này',
                          style: TextStyle(fontSize: 13, color: c.textSecondary, fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Bấm "Tạo Kịch Bản AI" bên dưới để bắt đầu',
                          style: TextStyle(fontSize: 11, color: c.textMuted),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: segments.length,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemBuilder: (context, index) {
                      final seg = segments[index];
                      final isCurrentActive = widget.currentTime >= seg.start && widget.currentTime < seg.end;
                      final isPlayingTts = widget.state.currentlyPlayingSegmentId == seg.id;
                      final ctrl = _textControllers[seg.id];

                      return Container(
                        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: isCurrentActive ? AppColors.primary.withOpacity(0.08) : Colors.transparent,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: isCurrentActive ? AppColors.primary.withOpacity(0.4) : c.border.withOpacity(0.4),
                          ),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // # ID
                            SizedBox(
                              width: 24,
                              child: Text(
                                '${seg.id}',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: isCurrentActive ? AppColors.primary : c.textMuted,
                                ),
                              ),
                            ),

                            // Timestamp Badge (Clickable to Seek)
                            InkWell(
                              borderRadius: BorderRadius.circular(4),
                              onTap: () => widget.onSeekToSubtitle?.call(seg.start),
                              child: Container(
                                width: 136,
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                decoration: BoxDecoration(
                                  color: c.surfaceDark.withOpacity(0.6),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: c.border.withOpacity(0.6)),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.play_circle_outline_rounded, size: 13, color: isCurrentActive ? AppColors.primary : c.textMuted),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        '${_formatTime(seg.start)} - ${_formatTime(seg.end)}',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                          fontFamily: 'monospace',
                                          color: isCurrentActive ? AppColors.primary : c.textPrimary,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),

                            // Editable Text Field
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  TextField(
                                    controller: ctrl,
                                    maxLines: 2,
                                    minLines: 1,
                                    style: const TextStyle(fontSize: 12),
                                    decoration: InputDecoration(
                                      isDense: true,
                                      hintText: seg.isMusicBreak ? '[Khoảng lặng âm nhạc]' : 'Nhập lời kể...',
                                      hintStyle: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: c.textMuted),
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                      filled: true,
                                      fillColor: c.surfaceLight.withOpacity(0.2),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(4),
                                        borderSide: BorderSide(color: c.border.withOpacity(0.5)),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(4),
                                        borderSide: const BorderSide(color: AppColors.primary),
                                      ),
                                    ),
                                    onChanged: (newText) {
                                      widget.controller.updateSegmentText(seg.id, newText);
                                    },
                                  ),
                                  const SizedBox(height: 2),
                                  Row(
                                    children: [
                                      Text(
                                        '${seg.wordCount}/${seg.maxWords} từ (${seg.duration.toStringAsFixed(1)}s)',
                                        style: TextStyle(
                                          fontSize: 9.5,
                                          color: seg.wordCount > seg.maxWords ? AppColors.statusFailed : c.textMuted,
                                        ),
                                      ),
                                      if (seg.visualDesc.isNotEmpty) ...[
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            '🎬 ${seg.visualDesc}',
                                            style: TextStyle(fontSize: 9.5, color: c.textMuted, fontStyle: FontStyle.italic),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 6),

                            // Actions: TTS Preview + Delete
                            SizedBox(
                              width: 64,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  IconButton(
                                    icon: Icon(
                                      isPlayingTts ? Icons.graphic_eq_rounded : Icons.volume_up_rounded,
                                      size: 16,
                                      color: isPlayingTts ? AppColors.primary : c.textSecondary,
                                    ),
                                    tooltip: isPlayingTts ? 'Đang phát thử...' : 'Nghe thử câu thoại',
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                    onPressed: isProcessing ? null : () => widget.controller.previewTts(seg.id, ctrl?.text ?? seg.text),
                                  ),
                                  IconButton(
                                    icon: Icon(Icons.delete_outline_rounded, size: 16, color: c.textMuted),
                                    tooltip: 'Xóa câu này',
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                    onPressed: isProcessing ? null : () => widget.controller.removeSegment(seg.id),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),

          // ── 4. ACTION FOOTER (GENERATE & RESUME RENDER) ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: c.surface,
              border: Border(top: BorderSide(color: c.border)),
            ),
            child: Row(
              children: [
                // Secondary: Sinh kịch bản AI (Hoặc tạo lại)
                OutlinedButton.icon(
                  onPressed: isProcessing ? null : () => widget.controller.generateScript(),
                  icon: const Icon(Icons.auto_awesome_rounded, size: 16),
                  label: Text(segments.isEmpty ? 'Tạo Kịch Bản AI' : 'Tạo Lại Kịch Bản'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.primary),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                ),
                const Spacer(),

                // Primary CTA: Tiếp Tục / Resume Render Video
                FilledButton.icon(
                  onPressed: (segments.isEmpty || isProcessing)
                      ? null
                      : () => widget.controller.renderFinalVideo(),
                  icon: const Icon(Icons.movie_creation_rounded, size: 16),
                  label: const Text('Tiếp Tục Render (Resume)', style: TextStyle(fontWeight: FontWeight.bold)),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    elevation: 2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
