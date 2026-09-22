import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/app_colors.dart';
import '../../../../core/providers.dart';
import '../../../../widgets/settings_section_card.dart';
import '../controllers/movie_review_controller.dart';
import '../models/movie_review_model.dart';

class ReviewVoiceAudioTab extends ConsumerWidget {
  final MovieReviewState state;
  final MovieReviewController controller;

  const ReviewVoiceAudioTab({
    super.key,
    required this.state,
    required this.controller,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = AppColors.of(context);
    final config = ref.watch(configProvider);
    final configNotifier = ref.read(configProvider.notifier);
    final budget = WordBudget.calculate(state.targetDurationSec, state.ttsSpeed);

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // ── 1. GIỌNG ĐỌC AI LỒNG TIẾNG ──
        SettingsSectionCard(
          title: '1. Giọng Đọc Lồng Tiếng AI',
          icon: Icons.record_voice_over_outlined,
          children: [
            DropdownButtonFormField<String>(
              value: state.ttsVoice,
              isExpanded: true,
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: c.surfaceLight,
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: c.border)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: c.border)),
              ),
              dropdownColor: c.surface,
              items: const [
                DropdownMenuItem(
                  value: 'hoai_my',
                  child: Text('🌸 Hoài My (Nữ miền Nam — Truyền cảm, hấp dẫn)', style: TextStyle(fontSize: 11.5, color: Colors.white)),
                ),
                DropdownMenuItem(
                  value: 'nam_minh',
                  child: Text('🎙️ Nam Minh (Nam miền Bắc — Trầm ấm, hào hùng)', style: TextStyle(fontSize: 11.5, color: Colors.white)),
                ),
                DropdownMenuItem(
                  value: 'ban_mai',
                  child: Text('🌸 Ban Mai (Nữ miền Bắc — Rõ ràng, dứt khoát)', style: TextStyle(fontSize: 11.5, color: Colors.white)),
                ),
              ],
              onChanged: (v) {
                if (v != null) controller.setTtsVoice(v);
              },
            ),
            const SizedBox(height: 10),

            // Nút nghe thử giọng mẫu
            OutlinedButton.icon(
              icon: const Icon(Icons.volume_up_outlined, size: 14, color: AppColors.primary),
              label: const Text('Nghe thử giọng đọc mẫu (1-2s)', style: TextStyle(fontSize: 11, color: AppColors.primary)),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: AppColors.primary.withOpacity(0.6)),
                padding: const EdgeInsets.symmetric(vertical: 8),
              ),
              onPressed: () {
                controller.previewTts(0, 'Xin chào các bạn, đây là phần review tóm tắt phim hấp dẫn trên Sub-Video.');
              },
            ),
            const SizedBox(height: 10),

            // Phân biệt giọng Nam/Nữ theo giới tính
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text(
                'Phân biệt giọng đọc theo giới tính (enable_gender_tts)',
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              subtitle: Text(
                'Tự động đổi giọng Nam hoặc Nữ dựa trên nhân vật thoại',
                style: TextStyle(fontSize: 10, color: c.textMuted),
              ),
              value: config.enableGenderTts,
              activeColor: AppColors.primary,
              onChanged: (val) {
                configNotifier.setField((cur) => cur.copyWith(enableGenderTts: val ?? false));
              },
            ),

            if (config.enableGenderTts) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Giọng Nam:', style: TextStyle(fontSize: 10.5, color: c.textSecondary)),
                        const SizedBox(height: 4),
                        DropdownButtonFormField<String>(
                          value: config.ttsVoiceMale,
                          isDense: true,
                          decoration: InputDecoration(
                            isDense: true,
                            filled: true,
                            fillColor: c.surfaceLight,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: c.border)),
                          ),
                          dropdownColor: c.surface,
                          items: const [
                            DropdownMenuItem(value: 'vi-VN-NamMinhNeural', child: Text('Nam Minh', style: TextStyle(fontSize: 11, color: Colors.white))),
                            DropdownMenuItem(value: 'vi-VN-BanMai', child: Text('Ban Mai', style: TextStyle(fontSize: 11, color: Colors.white))),
                            DropdownMenuItem(value: 'vi-VN-HoaiMyNeural', child: Text('Hoài My', style: TextStyle(fontSize: 11, color: Colors.white))),
                          ],
                          onChanged: (v) {
                            if (v != null) configNotifier.setField((cur) => cur.copyWith(ttsVoiceMale: v));
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Giọng Nữ:', style: TextStyle(fontSize: 10.5, color: c.textSecondary)),
                        const SizedBox(height: 4),
                        DropdownButtonFormField<String>(
                          value: config.ttsVoiceFemale,
                          isDense: true,
                          decoration: InputDecoration(
                            isDense: true,
                            filled: true,
                            fillColor: c.surfaceLight,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: c.border)),
                          ),
                          dropdownColor: c.surface,
                          items: const [
                            DropdownMenuItem(value: 'vi-VN-HoaiMyNeural', child: Text('Hoài My', style: TextStyle(fontSize: 11, color: Colors.white))),
                            DropdownMenuItem(value: 'vi-VN-BanMai', child: Text('Ban Mai', style: TextStyle(fontSize: 11, color: Colors.white))),
                            DropdownMenuItem(value: 'vi-VN-NamMinhNeural', child: Text('Nam Minh', style: TextStyle(fontSize: 11, color: Colors.white))),
                          ],
                          onChanged: (v) {
                            if (v != null) configNotifier.setField((cur) => cur.copyWith(ttsVoiceFemale: v));
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
        const SizedBox(height: 10),

        // ── 2. TỐC ĐỘ ĐỌC & ĐỘ TRỄ ──
        SettingsSectionCard(
          title: '2. Tốc Độ Đọc & Khớp Thoại',
          icon: Icons.speed_outlined,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Tốc độ đọc (TTS Speed):', style: TextStyle(fontSize: 11.5, color: c.textSecondary)),
                Text(
                  '${state.ttsSpeed.toStringAsFixed(2)}x (~${(140 * state.ttsSpeed).round()} từ/phút)',
                  style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: AppColors.primary),
                ),
              ],
            ),
            Slider(
              value: state.ttsSpeed,
              min: 1.0,
              max: 1.5,
              divisions: 10,
              activeColor: AppColors.primary,
              onChanged: (val) => controller.setTtsSpeed(val),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: c.surfaceLight,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: c.border),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, size: 13, color: AppColors.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Thời lượng ~${(state.targetDurationSec / 60).toStringAsFixed(1)} phút tương ứng ngân sách: ${budget.totalWords} từ.',
                      style: TextStyle(fontSize: 10.5, color: c.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Độ trễ phát âm (delay):', style: TextStyle(fontSize: 11.5, color: c.textSecondary)),
                Text('${config.ttsDelay.toStringAsFixed(2)}s', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: AppColors.primary)),
              ],
            ),
            Slider(
              value: config.ttsDelay.clamp(0.0, 1.0),
              min: 0.0,
              max: 1.0,
              divisions: 20,
              activeColor: AppColors.primary,
              onChanged: (val) {
                configNotifier.setField((cur) => cur.copyWith(ttsDelay: double.parse(val.toStringAsFixed(2))));
              },
            ),
          ],
        ),
        const SizedBox(height: 10),

        // ── 3. HÒA ÂM 3 LUỒNG ĐỘC LẬP & COPYRIGHT SHIELD ──
        SettingsSectionCard(
          title: '3. Hòa Âm 3 Luồng & Chống Bản Quyền',
          icon: Icons.graphic_eq_outlined,
          children: [
            // 3.1 TTS Volume
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    IconButton(
                      icon: Icon(
                        state.ttsVolume == 0.0 ? Icons.volume_off : Icons.record_voice_over,
                        size: 16,
                        color: state.ttsVolume == 0.0 ? AppColors.statusProcessing : AppColors.primary,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      tooltip: state.ttsVolume == 0.0 ? 'Bật giọng đọc' : 'Tắt tiếng giọng đọc',
                      onPressed: () => controller.setTtsVolume(state.ttsVolume == 0.0 ? 1.0 : 0.0),
                    ),
                    const SizedBox(width: 6),
                    Text('Giọng đọc (TTS Voice):', style: TextStyle(fontSize: 11.5, color: c.textSecondary)),
                  ],
                ),
                Text(
                  state.ttsVolume == 0.0 ? 'Tắt tiếng (0%)' : '${(state.ttsVolume * 100).round()}%',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.bold,
                    color: state.ttsVolume == 0.0 ? AppColors.statusProcessing : AppColors.primary,
                  ),
                ),
              ],
            ),
            Slider(
              value: state.ttsVolume,
              min: 0.0,
              max: 1.0,
              divisions: 20,
              activeColor: AppColors.primary,
              onChanged: (val) => controller.setTtsVolume(val),
            ),
            const SizedBox(height: 6),

            // 3.2 Movie Audio Volume
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    IconButton(
                      icon: Icon(
                        state.originalAudioVolume == 0.0 ? Icons.volume_off : Icons.movie_outlined,
                        size: 16,
                        color: state.originalAudioVolume == 0.0 ? AppColors.statusProcessing : const Color(0xFF10B981),
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      tooltip: state.originalAudioVolume == 0.0 ? 'Bật tiếng phim' : 'Tắt tiếng phim (Shield)',
                      onPressed: () => controller.setOriginalAudioVolume(state.originalAudioVolume == 0.0 ? 0.15 : 0.0),
                    ),
                    const SizedBox(width: 6),
                    Text('Tiếng phim gốc (Movie Audio):', style: TextStyle(fontSize: 11.5, color: c.textSecondary)),
                  ],
                ),
                Text(
                  state.originalAudioVolume == 0.0
                      ? 'Tắt tiếng phim (0%) 🛡️'
                      : '${(state.originalAudioVolume * 100).round()}% (Hạ âm khi đọc)',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.bold,
                    color: state.originalAudioVolume == 0.0 ? AppColors.statusProcessing : const Color(0xFF10B981),
                  ),
                ),
              ],
            ),
            Slider(
              value: state.originalAudioVolume,
              min: 0.0,
              max: 1.0,
              divisions: 20,
              activeColor: const Color(0xFF10B981),
              onChanged: (val) => controller.setOriginalAudioVolume(val),
            ),
            if (state.originalAudioVolume == 0.0)
              const Padding(
                padding: EdgeInsets.only(bottom: 6),
                child: Text(
                  '🛡️ Đã tắt âm thanh phim: Triệt tiêu hoàn toàn bản quyền âm nhạc & thoại từ video gốc.',
                  style: TextStyle(fontSize: 10, color: AppColors.statusProcessing, height: 1.2),
                ),
              ),
            const SizedBox(height: 6),

            // 3.3 BGM Volume
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    IconButton(
                      icon: Icon(
                        state.bgmVolume == 0.0 ? Icons.volume_off : Icons.music_note_outlined,
                        size: 16,
                        color: state.bgmVolume == 0.0 ? AppColors.statusProcessing : const Color(0xFF8B5CF6),
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      tooltip: state.bgmVolume == 0.0 ? 'Bật nhạc nền' : 'Tắt nhạc nền',
                      onPressed: () => controller.setBgmVolume(state.bgmVolume == 0.0 ? 0.20 : 0.0),
                    ),
                    const SizedBox(width: 6),
                    Text('Nhạc nền (BGM Music):', style: TextStyle(fontSize: 11.5, color: c.textSecondary)),
                  ],
                ),
                Text(
                  state.bgmVolume == 0.0 ? 'Tắt nhạc nền (0%)' : '${(state.bgmVolume * 100).round()}%',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.bold,
                    color: state.bgmVolume == 0.0 ? AppColors.statusProcessing : const Color(0xFF8B5CF6),
                  ),
                ),
              ],
            ),
            Slider(
              value: state.bgmVolume,
              min: 0.0,
              max: 1.0,
              divisions: 20,
              activeColor: const Color(0xFF8B5CF6),
              onChanged: (val) => controller.setBgmVolume(val),
            ),
            Text(
              '💡 3 luồng âm lượng được hòa âm tự động: Giọng đọc nổi bật ở trung tâm, âm thanh phim gốc làm nền sống động và nhạc nền tạo nhịp điệu cảm xúc.',
              style: TextStyle(fontSize: 10, color: c.textMuted, height: 1.3),
            ),
          ],
        ),
      ],
    );
  }
}
