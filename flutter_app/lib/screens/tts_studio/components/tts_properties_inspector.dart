import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../../../core/app_colors.dart';
import '../../../widgets/app_kit.dart';
import '../controllers/tts_studio_controller.dart';
import '../models/tts_models.dart';

class TtsPropertiesInspector extends StatelessWidget {
  final TtsStudioState state;
  final TtsStudioController controller;
  final VoidCallback onRenderFull;
  final VoidCallback onSendToHtmlToMp4;
  final VoidCallback onSendToVideoStudio;
  final VoidCallback onSaveAudioFile;

  const TtsPropertiesInspector({
    super.key,
    required this.state,
    required this.controller,
    required this.onRenderFull,
    required this.onSendToHtmlToMp4,
    required this.onSendToVideoStudio,
    required this.onSaveAudioFile,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final total = state.segments.length;
    final doneCount = state.segments.where((s) => s.audioPath != null).length;
    final totalWords = state.segments.fold<int>(0, (sum, s) => sum + s.wordCount);
    final hasMaster = state.fullAudioPath != null &&
        state.fullAudioPath!.isNotEmpty &&
        File(state.fullAudioPath!).existsSync();
    final activeVoice = state.availableVoices.firstWhere(
      (v) => v.id == state.defaultVoice,
      orElse: () => TtsVoice.defaultVoices.first,
    );

    return Container(
      color: c.surface,
      child: Column(
        children: [
          // ── HEADER 38PX ──
          Container(
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: c.surfaceDark,
              border: Border(bottom: BorderSide(color: c.border)),
            ),
            child: Row(
              children: [
                Icon(Icons.analytics_outlined, size: 14, color: c.primary),
                const SizedBox(width: 6),
                Text(
                  'THUỘC TÍNH & XUẤT BẢN',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: c.textPrimary,
                    letterSpacing: 0.4,
                  ),
                ),
              ],
            ),
          ),

          // ── BODY ──
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                Text(
                  'THỐNG KÊ KỊCH BẢN (SCRIPT STATS)',
                  style: TextStyle(
                    color: c.primary,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                _buildInfoRow(c, 'Tổng Số Câu', '$total câu'),
                _buildInfoRow(c, 'Tổng Số Từ', '$totalWords từ'),
                _buildInfoRow(c, 'Đã Nghe Thử', '$doneCount / $total câu'),
                _buildInfoRow(
                  c,
                  'Tổng Thời Lượng',
                  state.totalDuration > 0
                      ? '${state.totalDuration.toStringAsFixed(1)}s'
                      : '~${state.segments.fold<double>(0.0, (s, i) => s + i.duration).toStringAsFixed(1)}s',
                ),
                Divider(color: c.border, height: 20),
                Text(
                  'CẤU HÌNH GIỌNG ĐỌC',
                  style: TextStyle(
                    color: c.primary,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                _buildInfoRow(c, 'Giọng Mặc Định', '${activeVoice.flagEmoji} ${activeVoice.name}'),
                _buildInfoRow(c, 'Tốc Độ Đọc', '${state.defaultSpeed.toStringAsFixed(2)}x'),
                _buildInfoRow(c, 'Cao Độ (Pitch)', '${state.defaultPitch >= 0 ? "+" : ""}${state.defaultPitch} Hz'),
                _buildInfoRow(c, 'Khoảng Nghỉ', '${state.pauseSec.toStringAsFixed(2)}s'),
                _buildInfoRow(
                  c,
                  'Khóa Timeline',
                  state.isTimelineLocked ? 'Đang bật (Auto-Speed)' : 'Tự do',
                ),
                Divider(color: c.border, height: 20),
                Text(
                  'XUẤT BẢN & CHUYỂN TIẾP',
                  style: TextStyle(
                    color: c.primary,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                _buildInfoRow(
                  c,
                  'Master Audio',
                  hasMaster ? p.basename(state.fullAudioPath!) : 'Chưa ghép',
                ),
                const SizedBox(height: 12),
                AppButton.primary(
                  icon: Icons.auto_awesome_rounded,
                  label: state.isRenderingFull ? 'Đang Xuất Audio...' : 'Tạo & Ghép Master Audio',
                  isLoading: state.isRenderingFull,
                  height: 32,
                  onPressed: (total > 0 && !state.isRenderingFull) ? onRenderFull : null,
                ),
                const SizedBox(height: 8),
                AppButton.accent(
                  icon: Icons.html_rounded,
                  label: '🎬 Gửi sang HTML to MP4',
                  height: 30,
                  onPressed: onSendToHtmlToMp4,
                ),
                const SizedBox(height: 8),
                AppButton.secondary(
                  icon: Icons.video_library_outlined,
                  label: '🎞️ Đưa vào Video Studio',
                  height: 30,
                  onPressed: total > 0 ? onSendToVideoStudio : null,
                ),
                if (hasMaster) ...[
                  const SizedBox(height: 6),
                  AppButton.outlined(
                    icon: Icons.download_rounded,
                    label: 'Lưu File MP3 & SRT Ra Máy',
                    height: 28,
                    onPressed: onSaveAudioFile,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(AppFallbackPalette c, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: TextStyle(color: c.textSecondary, fontSize: 11),
            ),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: c.textPrimary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

