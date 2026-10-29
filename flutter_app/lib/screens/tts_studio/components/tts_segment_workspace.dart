import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../../../core/app_colors.dart';
import '../../../widgets/app_kit.dart';
import '../controllers/tts_studio_controller.dart';
import '../models/tts_models.dart';

class TtsSegmentWorkspace extends StatelessWidget {
  final TtsStudioState state;
  final TtsStudioController controller;
  final VoidCallback onRenderFull;
  final VoidCallback onSaveAudioFile;
  final VoidCallback onSendToHtmlToMp4;
  final VoidCallback onSendToVideoStudio;

  const TtsSegmentWorkspace({
    super.key,
    required this.state,
    required this.controller,
    required this.onRenderFull,
    required this.onSaveAudioFile,
    required this.onSendToHtmlToMp4,
    required this.onSendToVideoStudio,
  });

  String _formatSec(double sec) {
    final m = (sec ~/ 60).toString().padLeft(2, '0');
    final s = (sec % 60).toStringAsFixed(1).padLeft(4, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final hasMaster = state.fullAudioPath != null &&
        state.fullAudioPath!.isNotEmpty &&
        File(state.fullAudioPath!).existsSync();
    final totalWords = state.segments.fold<int>(0, (sum, item) => sum + item.wordCount);

    return Container(
      decoration: BoxDecoration(
        color: c.surfaceDark,
        border: Border(right: BorderSide(color: c.border)),
      ),
      child: Column(
        children: [
          // ── 1. HEADER TOOLBAR (38PX) ──
          Container(
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: c.surface,
              border: Border(bottom: BorderSide(color: c.border)),
            ),
            child: Row(
              children: [
                Icon(Icons.format_list_numbered_rounded, size: 15, color: c.primary),
                const SizedBox(width: 6),
                Text(
                  'DANH SÁCH CÂU THOẠI (${state.segments.length} câu • $totalWords từ)',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: c.textPrimary,
                    letterSpacing: 0.4,
                  ),
                ),
                const Spacer(),
                AppButton.ghost(
                  icon: state.isTimelineLocked ? Icons.lock_rounded : Icons.lock_open_rounded,
                  label: state.isTimelineLocked ? 'Khóa Timeline (Bật)' : 'Khóa Timeline (Tắt)',
                  height: 26,
                  onPressed: () => controller.toggleLockTimeline(),
                ),
                const SizedBox(width: 6),
                AppButton.ghost(
                  icon: Icons.add_rounded,
                  label: 'Thêm câu',
                  height: 26,
                  onPressed: () {
                    if (state.segments.isNotEmpty) {
                      controller.addSegmentBelow(state.segments.last.id);
                    }
                  },
                ),
                const SizedBox(width: 4),
                AppButton.ghost(
                  icon: Icons.delete_sweep_outlined,
                  label: 'Làm mới',
                  height: 26,
                  onPressed: state.segments.isNotEmpty ? controller.clearAll : null,
                ),
              ],
            ),
          ),

          // ── 2. MASTER AUDIO PREVIEW BANNER (NẾU ĐÃ GHÉP XONG) ──
          if (hasMaster)
            Container(
              margin: const EdgeInsets.fromLTRB(12, 10, 12, 2),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: c.statusCompleted.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: c.statusCompleted.withOpacity(0.45)),
              ),
              child: Row(
                children: [
                  Icon(Icons.spatial_audio_off_rounded, size: 16, color: c.statusCompleted),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Master Audio: ${p.basename(state.fullAudioPath!)}',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                            color: c.textPrimary,
                          ),
                        ),
                        Text(
                          'Tổng thời lượng: ${state.totalDuration.toStringAsFixed(1)}s • Đã tạo kèm phụ đề .SRT/.VTT',
                          style: TextStyle(fontSize: 10, color: c.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  AppButton.outlined(
                    icon: state.isPlayingFull ? Icons.stop_rounded : Icons.play_arrow_rounded,
                    label: state.isPlayingFull ? 'Dừng' : 'Nghe Toàn Bài',
                    height: 26,
                    onPressed: controller.togglePlayFullAudio,
                  ),
                  const SizedBox(width: 6),
                  AppButton.outlined(
                    icon: Icons.download_rounded,
                    label: 'Lưu File',
                    height: 26,
                    onPressed: onSaveAudioFile,
                  ),
                  const SizedBox(width: 6),
                  AppButton.accent(
                    icon: Icons.html_rounded,
                    label: 'Gửi sang HTML to MP4',
                    height: 26,
                    onPressed: onSendToHtmlToMp4,
                  ),
                ],
              ),
            ),

          // ── 3. SEGMENT CARDS LIST ──
          Expanded(
            child: state.segments.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.record_voice_over_outlined,
                          size: 42,
                          color: c.textMuted.withOpacity(0.4),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Chưa có phân đoạn câu thoại nào',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: c.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Nhập văn bản ở tab "📖 Kịch Bản Nguồn" bên phải rồi bấm "⚡ Phân Tách Kịch Bản Thành Câu".',
                          style: TextStyle(fontSize: 11, color: c.textMuted),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: state.segments.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, idx) {
                      final seg = state.segments[idx];
                      return _buildSegmentCard(context, c, seg, idx);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSegmentCard(
    BuildContext context,
    AppFallbackPalette c,
    TtsSegmentItem seg,
    int index,
  ) {
    final isPlaying = state.currentlyPlayingSegmentId == seg.id;
    final hasAudio = seg.audioPath != null && File(seg.audioPath!).existsSync();
    final hasTiming = seg.startSec > 0 || seg.endSec > 0;
    final effectiveVoiceId = seg.voice ?? state.defaultVoice;
    final effectiveSpd = seg.effectiveSpeed ?? seg.speed ?? state.defaultSpeed;

    return Container(
      key: ValueKey('tts_card_${seg.id}'),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isPlaying
              ? c.primary
              : hasAudio
                  ? c.statusCompleted.withOpacity(0.45)
                  : c.border,
          width: isPlaying ? 1.2 : 0.8,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: c.primary.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '#${(index + 1).toString().padLeft(2, '0')}',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                    color: c.primary,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              if (hasTiming) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: c.surfaceDark,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: c.border),
                  ),
                  child: Text(
                    '${_formatSec(seg.startSec)} → ${_formatSec(seg.endSec)}',
                    style: TextStyle(
                      fontSize: 10,
                      color: c.textSecondary,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 8),
              // Voice selector per segment
              _buildInlineVoiceDropdown(c, seg, effectiveVoiceId),
              const SizedBox(width: 8),
              Text(
                seg.duration > 0
                    ? '⏱ ${seg.duration.toStringAsFixed(1)}s • ${effectiveSpd.toStringAsFixed(2)}x'
                    : '${seg.wordCount} từ • ${effectiveSpd.toStringAsFixed(2)}x',
                style: TextStyle(
                  fontSize: 10.5,
                  color: hasAudio ? c.statusCompleted : c.textMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              AppButton.outlined(
                icon: isPlaying ? Icons.stop_rounded : Icons.play_arrow_rounded,
                label: isPlaying ? 'Dừng' : (hasAudio ? 'Nghe lại' : 'Nghe thử'),
                isLoading: seg.isSynthesizing,
                height: 24,
                fontSize: 10,
                onPressed: () => controller.previewSegment(seg.id),
              ),
              const SizedBox(width: 4),
              AppIconButton(
                icon: Icons.add_rounded,
                size: 13,
                buttonSize: 22,
                tooltip: 'Chèn thêm câu bên dưới',
                onPressed: () => controller.addSegmentBelow(seg.id),
              ),
              if (state.segments.length > 1)
                AppIconButton(
                  icon: Icons.close_rounded,
                  size: 13,
                  buttonSize: 22,
                  tooltip: 'Xóa câu này',
                  onPressed: () => controller.deleteSegment(seg.id),
                ),
            ],
          ),
          const SizedBox(height: 8),
          AppTextField(
            key: ValueKey('tts_seg_${seg.id}'),
            value: seg.text,
            maxLines: 2,
            height: 44,
            hint: 'Nhập nội dung câu thoại...',
            onChanged: (val) => controller.updateSegmentText(seg.id, val),
          ),
        ],
      ),
    );
  }

  Widget _buildInlineVoiceDropdown(
    AppFallbackPalette c,
    TtsSegmentItem seg,
    String effectiveVoiceId,
  ) {
    return Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: c.surfaceDark,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: seg.voice != null ? c.primary.withOpacity(0.6) : c.border,
          width: 0.8,
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          value: seg.voice,
          isDense: true,
          dropdownColor: c.surface,
          icon: Icon(Icons.arrow_drop_down, size: 13, color: c.textSecondary),
          style: TextStyle(fontSize: 10, color: c.textPrimary),
          hint: Text(
            'Giọng mặc định',
            style: TextStyle(fontSize: 10, color: c.textSecondary),
          ),
          items: [
            DropdownMenuItem<String?>(
              value: null,
              child: Text(
                'Mặc định (${state.defaultVoice.split("-").last.replaceAll("Neural", "")})',
                style: TextStyle(fontSize: 10, color: c.textSecondary),
              ),
            ),
            ...state.availableVoices.map(
              (v) => DropdownMenuItem<String?>(
                value: v.id,
                child: Text(
                  '${v.flagEmoji} ${v.name} (${v.genderLabel})',
                  style: const TextStyle(fontSize: 10),
                ),
              ),
            ),
          ],
          onChanged: (v) => controller.updateSegmentVoice(seg.id, v),
        ),
      ),
    );
  }
}

