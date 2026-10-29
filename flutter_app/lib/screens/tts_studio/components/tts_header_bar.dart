import 'package:flutter/material.dart';
import '../../../core/app_colors.dart';
import '../../../widgets/app_kit.dart';
import '../../../widgets/tool_header_toolbar.dart';
import '../controllers/tts_studio_controller.dart';
import '../models/tts_models.dart';

class TtsHeaderBar extends StatelessWidget {
  final TtsStudioState state;
  final TtsStudioController controller;
  final VoidCallback onSplitScript;
  final VoidCallback onRenderFull;
  final VoidCallback onSendToHtmlToMp4;
  final VoidCallback onSendToVideoStudio;

  const TtsHeaderBar({
    super.key,
    required this.state,
    required this.controller,
    required this.onSplitScript,
    required this.onRenderFull,
    required this.onSendToHtmlToMp4,
    required this.onSendToVideoStudio,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final isBusy = state.isSplitting || state.isRenderingFull;
    final total = state.segments.length;
    final doneCount = state.segments.where((s) => s.audioPath != null).length;
    final estDur = state.totalDuration > 0
        ? state.totalDuration
        : state.segments.fold<double>(0.0, (sum, s) => sum + s.duration);
    final activeVoice = state.availableVoices.firstWhere(
      (v) => v.id == state.defaultVoice,
      orElse: () => TtsVoice.defaultVoices.first,
    );

    return ToolHeaderToolbar(
      icon: Icon(
        Icons.record_voice_over_rounded,
        size: 16,
        color: c.primary,
      ),
      title: 'Tạo Giọng Đọc AI (TTS Studio)',
      breadcrumb: total > 0
          ? '$total câu thoại • Đã nghe/tạo: $doneCount/$total • Tổng: ~${estDur.toStringAsFixed(1)}s'
          : 'Chưa phân tách câu thoại',
      badge: isBusy
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: c.statusProcessingBg,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: c.statusProcessing.withOpacity(0.5), width: 0.8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 9,
                    height: 9,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      valueColor: AlwaysStoppedAnimation<Color>(c.statusProcessing),
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    state.statusMessage,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: c.statusProcessing,
                    ),
                  ),
                ],
              ),
            )
          : Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: c.surfaceLight.withOpacity(0.5),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: c.border.withOpacity(0.5), width: 0.8),
              ),
              child: Text(
                '${activeVoice.flagEmoji} ${activeVoice.name} • ${state.defaultSpeed.toStringAsFixed(2)}x',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w500,
                  color: c.textSecondary,
                ),
              ),
            ),
      actions: [
        AppButton.outlined(
          icon: Icons.bolt_rounded,
          label: 'Phân Tách Câu',
          isLoading: state.isSplitting,
          onPressed: isBusy ? null : onSplitScript,
        ),
        const SizedBox(width: 6),
        AppButton.primary(
          icon: Icons.auto_awesome_rounded,
          label: state.isRenderingFull ? 'Đang tạo Audio...' : 'Tạo & Ghép Master Audio',
          isLoading: state.isRenderingFull,
          onPressed: (total == 0 || isBusy) ? null : onRenderFull,
        ),
        const SizedBox(width: 6),
        AppButton.accent(
          icon: Icons.html_rounded,
          label: 'Gửi sang HTML to MP4',
          onPressed: isBusy ? null : onSendToHtmlToMp4,
        ),
      ],
    );
  }
}

