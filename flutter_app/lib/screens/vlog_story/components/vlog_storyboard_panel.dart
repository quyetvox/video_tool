import 'package:flutter/material.dart';
import '../../../../core/app_colors.dart';
import '../controllers/vlog_story_controller.dart';
import '../models/vlog_segment_model.dart';

class VlogStoryboardPanel extends StatefulWidget {
  final VlogStoryState state;
  final VlogStoryController controller;

  const VlogStoryboardPanel({
    super.key,
    required this.state,
    required this.controller,
  });

  @override
  State<VlogStoryboardPanel> createState() => _VlogStoryboardPanelState();
}

class _VlogStoryboardPanelState extends State<VlogStoryboardPanel> {
  final Map<int, TextEditingController> _controllers = {};

  @override
  void didUpdateWidget(covariant VlogStoryboardPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncControllers();
  }

  @override
  void initState() {
    super.initState();
    _syncControllers();
  }

  void _syncControllers() {
    final currentIds = widget.state.segments.map((s) => s.id).toSet();

    // Dọn dẹp controllers không còn tồn tại
    _controllers.removeWhere((id, ctrl) {
      if (!currentIds.contains(id)) {
        ctrl.dispose();
        return true;
      }
      return false;
    });

    // Tạo mới hoặc cập nhật controllers
    for (final seg in widget.state.segments) {
      if (!_controllers.containsKey(seg.id)) {
        _controllers[seg.id] = TextEditingController(text: seg.text);
      } else {
        // Chỉ cập nhật nếu text khác biệt hoàn toàn (được nạp từ file) và không đang focus
        if (_controllers[seg.id]!.text != seg.text && _controllers[seg.id]!.selection.isCollapsed) {
          _controllers[seg.id]!.text = seg.text;
        }
      }
    }
  }

  @override
  void dispose() {
    for (final ctrl in _controllers.values) {
      ctrl.dispose();
    }
    _controllers.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final segments = widget.state.segments;

    return Container(
      color: c.surface,
      child: Column(
        children: [
          // 1. Header Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: c.border)),
            ),
            child: Row(
              children: [
                const Icon(Icons.view_timeline_rounded, size: 18, color: AppColors.primary),
                const SizedBox(width: 8),
                Text(
                  'Bảng Storyboard (${segments.length})',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline, size: 20, color: AppColors.primary),
                  tooltip: 'Thêm phân cảnh',
                  onPressed: () => widget.controller.addSegment(),
                ),
              ],
            ),
          ),

          // 2. Danh Sách Phân Cảnh
          Expanded(
            child: segments.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.auto_stories_outlined, size: 44, color: c.textMuted.withOpacity(0.4)),
                          const SizedBox(height: 12),
                          Text(
                            'Chưa có kịch bản phân cảnh',
                            style: TextStyle(fontWeight: FontWeight.w600, color: c.textMuted, fontSize: 13),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Nhấn "Tạo Kịch Bản AI" ở cột bên trái để AI xem video và phân cảnh tự động.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: c.textMuted.withOpacity(0.8), fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: segments.length,
                    itemBuilder: (ctx, index) {
                      final seg = segments[index];
                      final ctrl = _controllers[seg.id] ?? TextEditingController(text: seg.text);
                      return _buildSegmentCard(seg, ctrl, c);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSegmentCard(VlogSegment seg, TextEditingController ctrl, dynamic c) {
    final isPlaying = widget.state.currentlyPlayingSegmentId == seg.id;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: c.surfaceLight.withOpacity(0.25),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isPlaying
              ? AppColors.primary
              : (seg.isOverBudget ? AppColors.statusFailed.withOpacity(0.5) : c.border),
          width: isPlaying ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Card
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: c.surfaceLight.withOpacity(0.4),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(9)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text('#${seg.id}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.primary)),
                ),
                const SizedBox(width: 8),
                Text(
                  seg.formatTimeRange(),
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
                ),
                const Spacer(),

                // Word count indicator
                if (seg.isMusicBreak)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.blueGrey.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text('🎵 Khoảng thở', style: TextStyle(fontSize: 10, color: Colors.blueGrey)),
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: seg.isOverBudget
                          ? AppColors.statusFailed.withOpacity(0.2)
                          : (seg.isWarningBudget ? Colors.orange.withOpacity(0.2) : Colors.green.withOpacity(0.15)),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${seg.wordCount}/${seg.maxWords} từ',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: seg.isOverBudget
                            ? AppColors.statusFailed
                            : (seg.isWarningBudget ? Colors.orange : Colors.green),
                      ),
                    ),
                  ),
                const SizedBox(width: 4),
                InkWell(
                  onTap: () => widget.controller.removeSegment(seg.id),
                  child: const Icon(Icons.close, size: 16, color: Colors.grey),
                ),
              ],
            ),
          ),

          // Visual Description
          if (seg.visualDesc.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 2),
              child: Row(
                children: [
                  const Icon(Icons.visibility_outlined, size: 13, color: Colors.grey),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      seg.visualDesc,
                      style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: c.textMuted),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),

          // Text Field Soạn Thảo (Không giật focus con trỏ)
          Padding(
            padding: const EdgeInsets.all(10),
            child: TextField(
              controller: ctrl,
              maxLines: 2,
              style: const TextStyle(fontSize: 12),
              decoration: InputDecoration(
                hintText: 'Nhập lời thoại hoặc để trống làm khoảng thở...',
                hintStyle: TextStyle(fontSize: 11, color: c.textMuted.withOpacity(0.5)),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              ),
              onChanged: (newText) {
                widget.controller.updateSegmentText(seg.id, newText);
              },
            ),
          ),

          // Footer Card: Nút Nghe Thử TTS
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  icon: Icon(
                    isPlaying ? Icons.stop_circle_rounded : Icons.volume_up_rounded,
                    size: 16,
                    color: isPlaying ? AppColors.statusFailed : AppColors.primary,
                  ),
                  label: Text(
                    isPlaying ? 'Dừng' : 'Nghe Thử TTS',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isPlaying ? AppColors.statusFailed : AppColors.primary,
                    ),
                  ),
                  onPressed: seg.text.trim().isEmpty
                      ? null
                      : () => widget.controller.previewTts(seg.id, seg.text),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
