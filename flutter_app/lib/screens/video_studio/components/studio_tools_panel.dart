import 'package:flutter/material.dart';
import '../../../core/app_colors.dart';
import '../../../core/studio_state_notifier.dart';
import '../../../models/studio_state.dart';
import '../../../utils/time_format_utils.dart';
import '../../../widgets/app_kit.dart';
import '../../../widgets/timecode_input_widget.dart';

/// Center Tools Panel supporting CUT, SPLIT, MERGE, and COMPOSITE modes.
class StudioToolsPanel extends StatelessWidget {
  final StudioToolMode mode;
  final StudioSnapshot state;
  final StudioStateNotifier notifier;
  final double duration;
  final double currentTime;
  final bool overwriteOriginalCut;
  final ValueChanged<bool> onOverwriteOriginalCutChanged;

  const StudioToolsPanel({
    super.key,
    required this.mode,
    required this.state,
    required this.notifier,
    required this.duration,
    required this.currentTime,
    required this.overwriteOriginalCut,
    required this.onOverwriteOriginalCutChanged,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    switch (mode) {
      case StudioToolMode.cut:
        return _buildCutPanel(context, c);
      case StudioToolMode.split:
        return _buildSplitPanel(context, c);
      case StudioToolMode.merge:
        return _buildMergePanel(context, c);
      case StudioToolMode.composite:
        return _buildCompositePanel(context, c);
    }
  }

  Widget _buildCutPanel(BuildContext context, AppColorTokens c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '✂️ Chọn đoạn rác:',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: c.statusFailed, fontSize: 10.5, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 4),
            InkWell(
              onTap: () => notifier.toggleCutBoxVisible(),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: state.showCutBox ? c.statusFailedBg : c.surfaceDark,
                  border: Border.all(color: state.showCutBox ? c.statusFailed.withOpacity(0.5) : c.border),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  children: [
                    Icon(state.showCutBox ? Icons.visibility : Icons.visibility_off, size: 10.5, color: state.showCutBox ? c.statusFailed : c.textMuted),
                    const SizedBox(width: 3),
                    Text(state.showCutBox ? 'Đang hiện' : 'Đã ẩn', style: TextStyle(color: state.showCutBox ? c.statusFailed : c.textMuted, fontSize: 9.5)),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),

        // Quick Preset Buttons
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: c.surfaceDark,
                  foregroundColor: c.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
                  minimumSize: Size.zero,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4), side: BorderSide(color: c.border, width: 0.6)),
                ),
                icon: const Icon(Icons.location_on, size: 10),
                label: const Text('10s tại Playhead', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w500)),
                onPressed: () => notifier.setCutRange(currentTime, (currentTime + 10.0).clamp(0.0, duration)),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: c.surfaceDark,
                  foregroundColor: c.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
                  minimumSize: Size.zero,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4), side: BorderSide(color: c.border, width: 0.6)),
                ),
                icon: const Icon(Icons.timer, size: 10),
                label: const Text('10s đầu', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w500)),
                onPressed: () => notifier.setCutRange(0.0, 10.0.clamp(0.0, duration)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),

        // Timecode Inputs
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Bắt đầu:', style: TextStyle(color: c.textSecondary, fontSize: 9.5)),
                  const SizedBox(height: 2),
                  TimecodeInputWidget(
                    value: state.currentJunkStart,
                    maxValue: duration,
                    onChanged: (val) => notifier.setCutRange(val, state.currentJunkEnd),
                    onSetFromPlayhead: () => notifier.setCutRange(currentTime, state.currentJunkEnd),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Kết thúc:', style: TextStyle(color: c.textSecondary, fontSize: 9.5)),
                  const SizedBox(height: 2),
                  TimecodeInputWidget(
                    value: state.currentJunkEnd,
                    maxValue: duration,
                    onChanged: (val) => notifier.setCutRange(state.currentJunkStart, val),
                    onSetFromPlayhead: () => notifier.setCutRange(state.currentJunkStart, currentTime),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),

        AppActionButton(
          icon: Icons.add,
          label: '+ Thêm đoạn rác này',
          color: c.primary,
          isFullWidth: true,
          fontSize: 10.5,
          onPressed: () => notifier.addCutSegment(state.currentJunkStart, state.currentJunkEnd),
        ),
        const SizedBox(height: 6),

        Text('Danh sách đoạn rác (${state.cutSegments.length})', style: TextStyle(color: c.textSecondary, fontSize: 10, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),

        Expanded(
          child: state.cutSegments.isEmpty
              ? Center(
                  child: Text('Chưa thêm đoạn rác nào', style: TextStyle(color: c.textMuted, fontSize: 10)),
                )
              : ListView.builder(
                  itemCount: state.cutSegments.length,
                  itemBuilder: (ctx, idx) {
                    final seg = state.cutSegments[idx];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 3),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: c.surfaceDark,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: c.border, width: 0.5),
                      ),
                      child: Row(
                        children: [
                          Text('${idx + 1}.', style: TextStyle(color: c.statusFailed, fontSize: 10, fontWeight: FontWeight.bold)),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              '${TimeFormatUtils.formatSubtitleTime(seg.start)} ➔ ${TimeFormatUtils.formatSubtitleTime(seg.end)}',
                              style: TextStyle(fontFamily: 'monospace', color: c.textPrimary, fontSize: 9.5),
                            ),
                          ),
                          AppIconButton(
                            icon: Icons.close,
                            size: 11,
                            buttonSize: 20,
                            color: c.textMuted,
                            onPressed: () => notifier.removeCutSegment(seg.id),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
        const SizedBox(height: 4),

        // Overwrite Original Checkbox
        AppCheckboxRow(
          value: overwriteOriginalCut,
          activeColor: c.statusFailed,
          label: overwriteOriginalCut ? 'Ghi đè file gốc src/' : 'Lưu vào cut/ (Giữ video gốc)',
          labelStyle: TextStyle(
            color: overwriteOriginalCut ? c.statusFailed : c.statusCompleted,
            fontSize: 9.5,
            fontWeight: FontWeight.w500,
          ),
          onChanged: (val) => onOverwriteOriginalCutChanged(val ?? false),
        ),
      ],
    );
  }

  Widget _buildSplitPanel(BuildContext context, AppColorTokens c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('🔀 Chia clip tại vị trí con trỏ Playhead:', style: TextStyle(color: c.primary, fontSize: 11.5, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: c.surfaceDark,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: c.border),
          ),
          child: Row(
            children: [
              Text('Vị trí chia: ', style: TextStyle(color: c.textSecondary, fontSize: 11)),
              Text(
                TimeFormatUtils.formatSubtitleTime(currentTime),
                style: TextStyle(fontFamily: 'monospace', color: c.textPrimary, fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),

        AppButton.primary(
          icon: Icons.splitscreen,
          label: 'Chia đôi clip tại đây (Lưu vào cut/)',
          width: double.infinity,
          height: 30,
          fontSize: 11,
          onPressed: () => notifier.addSplitAt(currentTime, duration),
        ),
        const SizedBox(height: 10),

        Text('Các phân đoạn đã chia (${state.splitSegments.length})', style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),

        Expanded(
          child: state.splitSegments.isEmpty
              ? Center(
                  child: Text('Chưa có điểm chia nào. Đặt Playhead và bấm Chia đôi clip.', style: TextStyle(color: c.textMuted, fontSize: 11)),
                )
              : ListView.builder(
                  itemCount: state.splitSegments.length,
                  itemBuilder: (ctx, idx) {
                    final seg = state.splitSegments[idx];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: c.surfaceDark,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: c.border),
                      ),
                      child: Row(
                        children: [
                          Text(seg.name, style: TextStyle(color: c.info, fontSize: 11, fontWeight: FontWeight.bold)),
                          const SizedBox(width: 8),
                          Text('${TimeFormatUtils.formatSubtitleTime(seg.start)} - ${TimeFormatUtils.formatSubtitleTime(seg.end)}', style: TextStyle(color: c.textSecondary, fontSize: 10.5)),
                          const Spacer(),
                          AppIconButton(
                            icon: Icons.close,
                            size: 12,
                            buttonSize: 20,
                            color: c.textMuted,
                            onPressed: () => notifier.removeSplitSegment(seg.id),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildMergePanel(BuildContext context, AppColorTokens c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('🥞 Danh sách video cần ghép (${state.mergePlaylist.length} file):', style: TextStyle(color: c.statusCompleted, fontSize: 12, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Text('💡 Click video ở sidebar bên trái để thêm vào danh sách ghép (Lưu vào merge/)', style: TextStyle(color: c.textMuted, fontSize: 10.5)),
        const SizedBox(height: 8),

        Expanded(
          child: state.mergePlaylist.isEmpty
              ? Center(
                  child: Text('Danh sách ghép đang trống', style: TextStyle(color: c.textMuted, fontSize: 11)),
                )
              : ReorderableListView.builder(
                  buildDefaultDragHandles: false,
                  itemCount: state.mergePlaylist.length,
                  onReorder: (oldIdx, newIdx) {
                    notifier.reorderMergeItem(oldIdx, newIdx);
                  },
                  itemBuilder: (ctx, idx) {
                    final item = state.mergePlaylist[idx];
                    return Container(
                      key: ValueKey(item.id),
                      margin: const EdgeInsets.only(bottom: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: c.surfaceDark,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: c.border),
                      ),
                      child: Row(
                        children: [
                          ReorderableDragStartListener(
                            index: idx,
                            child: Icon(Icons.drag_handle, size: 14, color: c.textMuted),
                          ),
                          const SizedBox(width: 8),
                          Text('${idx + 1}.', style: TextStyle(color: c.primary, fontSize: 11, fontWeight: FontWeight.bold)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              item.name,
                              style: TextStyle(color: c.textPrimary, fontSize: 11),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            TimeFormatUtils.formatSubtitleTime(item.duration),
                            style: TextStyle(color: c.textMuted, fontSize: 10),
                          ),
                          const SizedBox(width: 6),
                          AppIconButton(
                            icon: Icons.close,
                            size: 12,
                            buttonSize: 20,
                            color: c.textMuted,
                            onPressed: () => notifier.removeMergeItem(item.id),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildCompositePanel(BuildContext context, AppColorTokens c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('🎬 Biên Tập & Xuất Bản Đa Lớp:', style: TextStyle(color: c.primary, fontSize: 12, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Text('💡 Phối trộn Video + Lớp phủ ảnh + Nhạc nền + SFX + Subtitles thành một video hoàn chỉnh.', style: TextStyle(color: c.textSecondary, fontSize: 10.5)),
        const SizedBox(height: 10),

        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: c.surfaceDark,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: c.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('• Track Lớp Phủ: ${state.overlayTracks.length} track (${state.overlayClips.length} ảnh)', style: TextStyle(color: c.info, fontSize: 11)),
              const SizedBox(height: 4),
              Text('• Track Âm Thanh: ${state.audioTracks.length} track (${state.audioClips.length} clip)', style: TextStyle(color: c.statusCompleted, fontSize: 11)),
              const SizedBox(height: 4),
              Text('• Phụ Đề: ${state.subtitles.length} câu', style: TextStyle(color: c.primary, fontSize: 11)),
            ],
          ),
        ),
        const SizedBox(height: 10),
        const Spacer(),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: c.primary.withOpacity(0.08),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: c.primary.withOpacity(0.35)),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline, size: 14, color: c.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Bấm nút "Xuất video" ở góc phải để render bản phối đa lớp vào output/.',
                  style: TextStyle(color: c.primary, fontSize: 10),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
