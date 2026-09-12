import 'package:flutter/material.dart';
import '../../../models/subtitle_segment.dart';
import '../../../utils/time_format_utils.dart';
import '../../../widgets/speaker_badge.dart';

class SubtitleSegmentCard extends StatelessWidget {
  final int index;
  final SubtitleSegment seg;
  final bool isSelected;
  final VoidCallback onSeek;
  final VoidCallback onToggleSpeaker;
  final VoidCallback onAdjustStartMinus;
  final VoidCallback onAdjustEndPlus;
  final VoidCallback onInsertBelow;
  final VoidCallback onDelete;
  final ValueChanged<String> onTextChanged;

  const SubtitleSegmentCard({
    super.key,
    required this.index,
    required this.seg,
    required this.isSelected,
    required this.onSeek,
    required this.onToggleSpeaker,
    required this.onAdjustStartMinus,
    required this.onAdjustEndPlus,
    required this.onInsertBelow,
    required this.onDelete,
    required this.onTextChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: isSelected ? 3 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: isSelected ? Colors.cyanAccent : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
          width: isSelected ? 1.5 : 1,
        ),
      ),
      color: isDark ? const Color(0xFF1E293B) : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Row 1: Index + Timecode Range + Seek Button + Add/Delete Buttons
            Row(
              children: [
                // Index Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.cyanAccent.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '#${seg.id}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.cyanAccent),
                  ),
                ),
                const SizedBox(width: 8),

                // Timecode Seek Button
                InkWell(
                  onTap: onSeek,
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.cyanAccent.withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.play_circle_fill, size: 14, color: Colors.cyanAccent),
                        const SizedBox(width: 6),
                        Text(
                          '${TimeFormatUtils.formatSubtitleTime(seg.start)} ➔ ${TimeFormatUtils.formatSubtitleTime(seg.end)}',
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 11, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '(${(seg.end - seg.start).toStringAsFixed(1)}s)',
                          style: const TextStyle(fontSize: 10, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ),

                // Speaker / Gender Badge
                SpeakerBadgeWidget(
                  speaker: seg.speaker,
                  gender: seg.gender,
                  onTap: onToggleSpeaker,
                  tooltip: 'Click để đổi người nói (Nam ↔ Nữ)',
                  margin: const EdgeInsets.only(left: 6),
                ),

                const Spacer(),

                // Time adjust buttons (-0.1s, +0.1s)
                IconButton(
                  tooltip: 'Lùi Start 0.1s',
                  icon: const Icon(Icons.remove, size: 14),
                  onPressed: onAdjustStartMinus,
                ),
                IconButton(
                  tooltip: 'Tăng End 0.1s',
                  icon: const Icon(Icons.add, size: 14),
                  onPressed: onAdjustEndPlus,
                ),

                // Insert below
                IconButton(
                  tooltip: 'Chèn câu phía dưới',
                  icon: const Icon(Icons.playlist_add, size: 16),
                  onPressed: onInsertBelow,
                ),

                // Delete
                IconButton(
                  tooltip: 'Xóa câu này',
                  icon: const Icon(Icons.delete_outline, size: 16, color: Colors.redAccent),
                  onPressed: onDelete,
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Original Text (if exists)
            if (seg.text.isNotEmpty) ...[
              Text(
                'Gốc: ${seg.text}',
                style: const TextStyle(fontSize: 11, color: Colors.grey, fontStyle: FontStyle.italic),
              ),
              const SizedBox(height: 4),
            ],

            // Translated Text Field (Vietnamese)
            _SubtitleEditorTextInput(
              key: ValueKey('seg_${seg.id}_$index'),
              initialText: seg.displayText,
              isDark: isDark,
              onChanged: onTextChanged,
            ),
          ],
        ),
      ),
    );
  }
}

class _SubtitleEditorTextInput extends StatefulWidget {
  final String initialText;
  final bool isDark;
  final ValueChanged<String> onChanged;

  const _SubtitleEditorTextInput({
    super.key,
    required this.initialText,
    required this.isDark,
    required this.onChanged,
  });

  @override
  State<_SubtitleEditorTextInput> createState() => _SubtitleEditorTextInputState();
}

class _SubtitleEditorTextInputState extends State<_SubtitleEditorTextInput> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
  }

  @override
  void didUpdateWidget(covariant _SubtitleEditorTextInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialText != widget.initialText && _controller.text != widget.initialText) {
      final oldSel = _controller.selection;
      _controller.text = widget.initialText;
      if (oldSel.start <= widget.initialText.length && oldSel.end <= widget.initialText.length) {
        _controller.selection = oldSel;
      } else {
        _controller.selection = TextSelection.collapsed(offset: widget.initialText.length);
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      onChanged: widget.onChanged,
      maxLines: null,
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
      decoration: InputDecoration(
        hintText: 'Nhập nội dung phụ đề tiếng Việt...',
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        filled: true,
        fillColor: widget.isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(
            color: widget.isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
          ),
        ),
      ),
    );
  }
}
