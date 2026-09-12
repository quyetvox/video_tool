import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/app_colors.dart';
import '../../../../core/providers.dart';
import '../../../../core/studio_state_notifier.dart';
import '../../../../models/studio_state.dart';
import '../../../../models/video_file.dart';
import '../../../../utils/time_format_utils.dart';
import '../../../../widgets/app_kit.dart';
import '../../../../widgets/speaker_badge.dart';
import 'studio_subtitle_inline_editor.dart';

/// 'sub' Tab: Dedicated Subtitle clips list editor with inline 3-tier editing,
/// quick In/Out timecode grabbing, speaker assignment, and pipeline step 8c import.
class StudioSubtitleTab extends ConsumerStatefulWidget {
  final StudioSnapshot state;
  final StudioStateNotifier notifier;
  final VideoFile? video;
  final double currentTime;
  final void Function(double sec) onSeek;
  final VoidCallback? onReloadPipeline;

  const StudioSubtitleTab({
    super.key,
    required this.state,
    required this.notifier,
    required this.video,
    required this.currentTime,
    required this.onSeek,
    this.onReloadPipeline,
  });

  @override
  ConsumerState<StudioSubtitleTab> createState() => _StudioSubtitleTabState();
}

class _StudioSubtitleTabState extends ConsumerState<StudioSubtitleTab> {
  String _subSourceLang = 'auto';
  String _subTargetLang = 'vi';

  void _toggleSpeaker(int idx) {
    final list = [...widget.state.subtitles];
    if (idx >= 0 && idx < list.length) {
      final current = list[idx];
      final raw = current.speaker.toLowerCase();
      final String nextSpeaker;
      final String nextGender;
      if (raw == 'nam' || raw == 'male' || current.gender == 'male') {
        nextSpeaker = 'Nữ';
        nextGender = 'female';
      } else if (raw == 'nữ' || raw == 'nu' || raw == 'female' || current.gender == 'female') {
        nextSpeaker = 'Nam';
        nextGender = 'male';
      } else {
        nextSpeaker = 'Nam';
        nextGender = 'male';
      }
      list[idx] = current.copyWith(speaker: nextSpeaker, gender: nextGender);
      widget.notifier.setSubtitles(list);
    }
  }

  void _handleAddSegment() {
    final startSec = widget.currentTime > 0
        ? widget.currentTime
        : (widget.state.subtitles.isNotEmpty ? widget.state.subtitles.last.end : 0.0);
    final endSec = startSec + 2.5;
    final newClip = SubtitleClip(
      id: 'sub_${DateTime.now().millisecondsSinceEpoch}',
      start: startSec,
      end: endSec,
      text: '',
      textVi: '',
      textSecondary: '',
      speaker: 'Nam',
      gender: 'male',
    );
    final list = [...widget.state.subtitles, newClip]..sort((a, b) => a.start.compareTo(b.start));
    widget.notifier.setSubtitles(list);
  }

  void _grabInTime(int idx) {
    final list = [...widget.state.subtitles];
    if (idx >= 0 && idx < list.length) {
      final cur = list[idx];
      final newStart = double.parse(widget.currentTime.toStringAsFixed(3));
      final newEnd = newStart >= cur.end ? newStart + 1.0 : cur.end;
      list[idx] = cur.copyWith(start: newStart, end: newEnd);
      widget.notifier.setSubtitles(list);
    }
  }

  void _grabOutTime(int idx) {
    final list = [...widget.state.subtitles];
    if (idx >= 0 && idx < list.length) {
      final cur = list[idx];
      final newEnd = double.parse(widget.currentTime.toStringAsFixed(3));
      final newStart = newEnd <= cur.start ? (newEnd - 1.0).clamp(0.0, newEnd) : cur.start;
      list[idx] = cur.copyWith(start: newStart, end: newEnd);
      widget.notifier.setSubtitles(list);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final config = ref.watch(configProvider);
    final configNotifier = ref.read(configProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── 1. Toolbar: Ngôn ngữ, Xưng hô, Nạp từ 8c, Thêm câu ──
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: c.surfaceDark,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: c.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    Text('From:', style: TextStyle(color: c.textSecondary, fontSize: 10)),
                    const SizedBox(width: 4),
                    Container(
                      height: 22,
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(4)),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _subSourceLang,
                          dropdownColor: c.surface,
                          style: TextStyle(color: c.textPrimary, fontSize: 10),
                          items: const [
                            DropdownMenuItem(value: 'auto', child: Text('🌐 Auto')),
                            DropdownMenuItem(value: 'zh', child: Text('🇨🇳 Trung')),
                            DropdownMenuItem(value: 'en', child: Text('🇬🇧 Anh')),
                            DropdownMenuItem(value: 'ja', child: Text('🇯🇵 Nhật')),
                            DropdownMenuItem(value: 'ko', child: Text('🇰🇷 Hàn')),
                          ],
                          onChanged: (v) => setState(() => _subSourceLang = v ?? 'auto'),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.arrow_forward, size: 9, color: AppColors.textMuted),
                    const SizedBox(width: 4),
                    Text('To:', style: TextStyle(color: c.textSecondary, fontSize: 10)),
                    const SizedBox(width: 4),
                    Container(
                      height: 22,
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(4)),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _subTargetLang,
                          dropdownColor: c.surface,
                          style: TextStyle(color: c.textPrimary, fontSize: 10),
                          items: const [
                            DropdownMenuItem(value: 'vi', child: Text('🇻🇳 Việt')),
                            DropdownMenuItem(value: 'en', child: Text('🇬🇧 Anh')),
                          ],
                          onChanged: (v) => setState(() => _subTargetLang = v ?? 'vi'),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      height: 22,
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(4)),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: ['dynamic', 'couple', 'family_parent_child', 'friends', 'formal', 'custom'].contains(config.pronounMode)
                              ? config.pronounMode
                              : 'dynamic',
                          dropdownColor: c.surface,
                          style: TextStyle(color: c.primary, fontSize: 10, fontWeight: FontWeight.w500),
                          items: const [
                            DropdownMenuItem(value: 'dynamic', child: Text('🎭 Linh hoạt')),
                            DropdownMenuItem(value: 'couple', child: Text('👩‍❤️‍👨 Cặp đôi')),
                            DropdownMenuItem(value: 'family_parent_child', child: Text('👨‍👩‍👧 Gia đình')),
                            DropdownMenuItem(value: 'friends', child: Text('🤝 Bạn bè')),
                            DropdownMenuItem(value: 'formal', child: Text('💼 Trang trọng')),
                            DropdownMenuItem(value: 'custom', child: Text('⚙️ Tùy chỉnh')),
                          ],
                          onChanged: (v) {
                            if (v != null) {
                              configNotifier.setField((cfg) => cfg.copyWith(pronounMode: v));
                            }
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: c.primary,
                        side: BorderSide(color: c.primary.withOpacity(0.5)),
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                      ),
                      icon: const Icon(Icons.download_rounded, size: 13),
                      label: const Text('Nạp từ Bước 8c', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                      onPressed: widget.onReloadPipeline,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: c.primary,
                        foregroundColor: c.primaryText,
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                      ),
                      icon: const Icon(Icons.add_rounded, size: 13),
                      label: const Text('Thêm câu', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                      onPressed: _handleAddSegment,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // ── 2. Header Đếm Số Lượng Câu ──
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            children: [
              Text(
                'Danh Sách Phụ Đề (${widget.state.subtitles.length} câu):',
                style: TextStyle(color: c.textSecondary, fontSize: 10.5, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              Text(
                'Click timecode để nhảy • ⏱️ In/Out bắt giờ',
                style: TextStyle(color: c.textMuted, fontSize: 9.5),
              ),
            ],
          ),
        ),

        // ── 3. Danh Sách Phụ Đề Clips ──
        if (widget.state.subtitles.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.subtitles_off_outlined, size: 36, color: c.textMuted),
                  const SizedBox(height: 8),
                  Text('Chưa có câu phụ đề nào', style: TextStyle(color: c.textSecondary, fontSize: 11.5, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text('Bạn có thể nạp từ bước 8c hoặc bấm "Thêm câu" để soạn thảo.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: c.textMuted, fontSize: 10)),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (widget.onReloadPipeline != null)
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: c.surfaceLight,
                            foregroundColor: c.textPrimary,
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          ),
                          icon: const Icon(Icons.download_rounded, size: 12),
                          label: const Text('Nạp từ Bước 8c', style: TextStyle(fontSize: 10.5)),
                          onPressed: widget.onReloadPipeline,
                        ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: c.primary,
                          foregroundColor: c.primaryText,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        ),
                        icon: const Icon(Icons.add_rounded, size: 12),
                        label: const Text('Thêm câu đầu tiên', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold)),
                        onPressed: _handleAddSegment,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: widget.state.subtitles.length,
            itemBuilder: (ctx, idx) {
              final sub = widget.state.subtitles[idx];
              final isCurrent = widget.currentTime >= sub.start && widget.currentTime <= sub.end;

              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: isCurrent ? c.primary.withOpacity(0.08) : c.surfaceDark,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isCurrent ? c.primary : c.border,
                    width: isCurrent ? 1.2 : 0.6,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Dòng 1: Index, ⏱️ In, Timecode Seek, ⏱️ Out, Speaker Badge, Delete
                    Row(
                      children: [
                        Text('#${idx + 1}', style: TextStyle(color: c.primary, fontSize: 10, fontWeight: FontWeight.bold)),
                        const SizedBox(width: 4),

                        // Nút bắt nhanh In
                        InkWell(
                          onTap: () => _grabInTime(idx),
                          borderRadius: BorderRadius.circular(3),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: c.surface,
                              borderRadius: BorderRadius.circular(3),
                              border: Border.all(color: c.primary.withOpacity(0.5)),
                            ),
                            child: Text('⏱️ In', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: c.primary)),
                          ),
                        ),
                        const SizedBox(width: 4),

                        // Timecode clickable
                        InkWell(
                          onTap: () => widget.onSeek(sub.start),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                            child: Text(
                              '${TimeFormatUtils.formatSubtitleTime(sub.start)} ➔ ${TimeFormatUtils.formatSubtitleTime(sub.end)}',
                              style: TextStyle(
                                fontFamily: 'monospace',
                                color: isCurrent ? c.primary : c.textSecondary,
                                fontSize: 9.5,
                                fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),

                        // Nút bắt nhanh Out
                        InkWell(
                          onTap: () => _grabOutTime(idx),
                          borderRadius: BorderRadius.circular(3),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: c.surface,
                              borderRadius: BorderRadius.circular(3),
                              border: Border.all(color: c.primaryDark.withOpacity(0.5)),
                            ),
                            child: Text('⏱️ Out', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: c.primaryDark)),
                          ),
                        ),

                        const SizedBox(width: 4),
                        // Huy hiệu Người nói
                        SpeakerBadgeWidget(
                          speaker: sub.speaker,
                          gender: sub.gender,
                          onTap: () => _toggleSpeaker(idx),
                        ),

                        const Spacer(),
                        AppIconButton(
                          icon: Icons.delete_outline_rounded,
                          size: 13,
                          buttonSize: 22,
                          color: c.statusFailed,
                          tooltip: 'Xóa câu này',
                          onPressed: () {
                            final list = [...widget.state.subtitles]..removeAt(idx);
                            widget.notifier.setSubtitles(list);
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),

                    // Dòng 2: Trình soạn thảo văn bản 3 tầng
                    // 1. Phụ đề Chính (Tiếng Việt)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFACC15).withOpacity(0.2),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: const Text('Chính', style: TextStyle(color: Color(0xFFFACC15), fontSize: 9, fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: StudioSubtitleInlineEditor(
                            text: sub.textVi,
                            style: TextStyle(color: c.textPrimary, fontSize: 11, fontWeight: FontWeight.w500),
                            decoration: const InputDecoration(
                              hintText: 'Nhập phụ đề tiếng Việt...',
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(vertical: 2),
                              border: InputBorder.none,
                            ),
                            onChanged: (newText) {
                              final list = [...widget.state.subtitles];
                              list[idx] = sub.copyWith(textVi: newText);
                              widget.notifier.setSubtitles(list);
                            },
                          ),
                        ),
                      ],
                    ),

                    // 2. Phụ đề Phụ (Song ngữ)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: const Color(0xFF38BDF8).withOpacity(0.2),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: const Text('Phụ', style: TextStyle(color: Color(0xFF38BDF8), fontSize: 9, fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: StudioSubtitleInlineEditor(
                            text: sub.textSecondary,
                            style: TextStyle(color: c.textSecondary, fontSize: 10.5),
                            decoration: const InputDecoration(
                              hintText: 'Nhập phụ đề song ngữ...',
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(vertical: 2),
                              border: InputBorder.none,
                            ),
                            onChanged: (newText) {
                              final list = [...widget.state.subtitles];
                              list[idx] = sub.copyWith(textSecondary: newText);
                              widget.notifier.setSubtitles(list);
                            },
                          ),
                        ),
                      ],
                    ),

                    // 3. Transcript Gốc
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: const Color(0xFF94A3B8).withOpacity(0.2),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: const Text('Gốc', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 9, fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: StudioSubtitleInlineEditor(
                            text: sub.text,
                            style: TextStyle(color: c.textMuted, fontSize: 10),
                            decoration: const InputDecoration(
                              hintText: 'Nhập transcript gốc OCR/ASR...',
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(vertical: 2),
                              border: InputBorder.none,
                            ),
                            onChanged: (newText) {
                              final list = [...widget.state.subtitles];
                              list[idx] = sub.copyWith(text: newText);
                              widget.notifier.setSubtitles(list);
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }
}
