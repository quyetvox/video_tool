import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../../../core/app_colors.dart';
import '../controllers/vlog_story_controller.dart';

class VlogVoiceAndBgmCard extends StatelessWidget {
  final VlogStoryState state;
  final VlogStoryController controller;

  const VlogVoiceAndBgmCard({
    super.key,
    required this.state,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Tiêu Đề Mục
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.statusCompleted.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.record_voice_over_rounded, size: 18, color: AppColors.statusCompleted),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  '2. Âm Thanh, Nhạc Nền & Xuất Bản',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 2. Chọn Giọng Đọc & Tốc Độ
          Row(
            children: [
              Expanded(
                flex: 3,
                child: DropdownButtonFormField<String>(
                  value: state.voice,
                  decoration: InputDecoration(
                    labelText: 'Giọng Đọc TTS',
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'hoai_my', child: Text('🌸 Hoài My (Nữ Microsoft)', style: TextStyle(fontSize: 12))),
                    DropdownMenuItem(value: 'ban_mai', child: Text('🎙️ Ban Mai (Nữ Google)', style: TextStyle(fontSize: 12))),
                    DropdownMenuItem(value: 'nam_minh', child: Text('👔 Nam Minh (Nam Microsoft)', style: TextStyle(fontSize: 12))),
                  ],
                  onChanged: (val) {
                    if (val != null) controller.setVoice(val);
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Tốc độ: ${state.ttsSpeed.toStringAsFixed(2)}x', style: const TextStyle(fontSize: 11)),
                    Slider(
                      value: state.ttsSpeed,
                      min: 0.9,
                      max: 1.5,
                      divisions: 6,
                      activeColor: AppColors.primary,
                      onChanged: (val) => controller.setTtsSpeed(val),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // 3. Nhạc Nền (BGM) & Smart Ducking
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    side: BorderSide(color: state.bgmPath != null ? AppColors.info : c.border),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: Icon(
                    state.bgmPath != null ? Icons.music_note : Icons.music_off_outlined,
                    size: 16,
                    color: state.bgmPath != null ? AppColors.info : c.textMuted,
                  ),
                  label: Text(
                    state.bgmPath != null ? 'BGM: ${_getFileName(state.bgmPath!)}' : 'Dùng âm thanh gốc',
                    style: TextStyle(
                      fontSize: 12,
                      color: state.bgmPath != null ? AppColors.info : c.textMuted,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  onPressed: () async {
                    if (state.bgmPath != null) {
                      // Hủy BGM ngoài -> chuyển về âm thanh gốc
                      controller.setBgmPath(null);
                    } else {
                      final res = await FilePicker.platform.pickFiles(
                        type: FileType.custom,
                        allowedExtensions: ['mp3', 'wav', 'm4a', 'aac'],
                      );
                      if (res != null && res.files.single.path != null) {
                        controller.setBgmPath(res.files.single.path);
                      }
                    }
                  },
                ),
              ),
              const SizedBox(width: 10),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Xóa Sub Cũ', style: TextStyle(fontSize: 11, color: c.textMuted)),
                  Checkbox(
                    value: state.enableInpaint,
                    activeColor: AppColors.primary,
                    onChanged: (val) => controller.setEnableInpaint(val ?? false),
                  ),
                  const SizedBox(width: 4),
                  Text('In Sub', style: TextStyle(fontSize: 11, color: c.textMuted)),
                  Checkbox(
                    value: state.burnSubtitles,
                    activeColor: AppColors.primary,
                    onChanged: (val) => controller.setBurnSubtitles(val ?? true),
                  ),
                ],
              ),
            ],
          ),

          if (state.isProcessing && state.progress > 0 && state.progress < 1.0) ...[
            const SizedBox(height: 10),
            LinearProgressIndicator(
              value: state.progress,
              backgroundColor: c.border,
              color: AppColors.primary,
            ),
            const SizedBox(height: 4),
            Text(
              state.statusMessage,
              style: TextStyle(fontSize: 11, color: c.textMuted),
              textAlign: TextAlign.center,
            ),
          ],

          const SizedBox(height: 12),

          // 4. Nút Render Xuất Video
          SizedBox(
            height: 44,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.statusCompleted,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              icon: state.isRenderingVideo
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.movie_creation_outlined, size: 18),
              label: Text(
                state.isRenderingVideo ? 'Đang Xuất Bản...' : 'Xuất Video Hoàn Chỉnh (1:1)',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              onPressed: (state.isProcessing || state.segments.isEmpty)
                  ? null
                  : () => controller.renderFinalVideo(),
            ),
          ),
        ],
      ),
    );
  }

  String _getFileName(String path) {
    return path.split('/').last.split('\\').last;
  }
}
