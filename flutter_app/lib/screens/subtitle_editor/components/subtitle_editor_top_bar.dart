import 'package:flutter/material.dart';
import '../../../models/video_file.dart';

class SubtitleEditorTopBar extends StatelessWidget {
  final VideoFile selectedVideo;
  final bool hasUnsavedChanges;
  final bool hasSegments;
  final VoidCallback onAddSegment;
  final VoidCallback onReload;
  final VoidCallback onSaveOnly;
  final VoidCallback onSaveAndResume;

  const SubtitleEditorTopBar({
    super.key,
    required this.selectedVideo,
    required this.hasUnsavedChanges,
    required this.hasSegments,
    required this.onAddSegment,
    required this.onReload,
    required this.onSaveOnly,
    required this.onSaveAndResume,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white,
        border: Border(
          bottom: BorderSide(
            color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
          ),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.edit_note, color: Colors.cyanAccent, size: 22),
          const SizedBox(width: 8),
          Text(
            'Biên tập phụ đề s08: ${selectedVideo.basename}',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(width: 12),
          if (hasUnsavedChanges)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'Chưa lưu thay đổi',
                style: TextStyle(fontSize: 11, color: Colors.orangeAccent, fontWeight: FontWeight.bold),
              ),
            ),
          const Spacer(),

          // Add Segment Button
          OutlinedButton.icon(
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Thêm câu'),
            onPressed: onAddSegment,
          ),
          const SizedBox(width: 8),

          // Reload
          IconButton(
            tooltip: 'Tải lại từ file gốc',
            icon: const Icon(Icons.refresh, size: 20),
            onPressed: onReload,
          ),
          const SizedBox(width: 8),

          // Save Only
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blueGrey.shade800,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.save_outlined, size: 16),
            label: const Text('Lưu file'),
            onPressed: hasSegments ? onSaveOnly : null,
          ),
          const SizedBox(width: 8),

          // Save & Resume Pipeline
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.cyan.shade700,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.bolt, size: 16),
            label: const Text('Lưu & Render Resume (~2s)'),
            onPressed: hasSegments ? onSaveAndResume : null,
          ),
        ],
      ),
    );
  }
}
