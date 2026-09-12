import 'package:flutter/material.dart';
import '../../../../models/app_config.dart';
import '../../../../widgets/settings_section_card.dart';
import '../config_input_fields.dart';

class ConfigVoiceTtsSection extends StatelessWidget {
  final AppConfig cfg;
  final void Function(AppConfig Function(AppConfig)) onUpdate;

  const ConfigVoiceTtsSection({
    super.key,
    required this.cfg,
    required this.onUpdate,
  });

  @override
  Widget build(BuildContext context) {
    return SettingsSectionCard(
      title: '5. Giọng Đọc Lồng Tiếng AI (TTS & Voice)',
      icon: Icons.record_voice_over,
      subtitle: 'Engine sinh giọng đọc EdgeTTS / gTTS và phân biệt giới tính Nam/Nữ',
      children: [
        ConfigRow2(
          w1: ConfigDropdown(
            label: 'Công cụ TTS (engine):',
            value: cfg.ttsEngine,
            options: const ['edge_tts', 'gtts', 'coqui', 'fpt'],
            onChanged: (val) {
              if (val != null) onUpdate((c) => c.copyWith(ttsEngine: val));
            },
          ),
          w2: ConfigDropdown(
            label: 'Giọng đọc mặc định (voice):',
            value: cfg.ttsVoice,
            options: const [
              'vi-VN-HoaiMyNeural',
              'vi-VN-NamMinhNeural',
              'vi_banmai_fast',
              'vi_banmai_standard',
              'vi_namminh_fast',
            ],
            onChanged: (val) {
              if (val != null) onUpdate((c) => c.copyWith(ttsVoice: val));
            },
          ),
        ),
        const SizedBox(height: 12),
        ConfigRow2(
          w1: ConfigSlider(
            label: 'Tốc độ đọc (speed):',
            value: cfg.ttsSpeed,
            min: 0.5,
            max: 2.0,
            divisions: 15,
            displayValue: '${cfg.ttsSpeed.toStringAsFixed(2)}x',
            onChanged: (val) => onUpdate((c) => c.copyWith(ttsSpeed: double.parse(val.toStringAsFixed(2)))),
          ),
          w2: ConfigSlider(
            label: 'Độ trễ phát âm (delay):',
            value: cfg.ttsDelay,
            min: 0.0,
            max: 1.0,
            divisions: 20,
            displayValue: '${cfg.ttsDelay.toStringAsFixed(2)}s',
            onChanged: (val) => onUpdate((c) => c.copyWith(ttsDelay: double.parse(val.toStringAsFixed(2)))),
          ),
        ),
        const SizedBox(height: 12),
        ConfigToggle(
          label: 'Phân biệt giọng đọc theo giới tính (enable_gender_tts)',
          subtitle: 'Tự động chọn giọng Nam hoặc Nữ dựa trên phân tích âm thanh gốc',
          value: cfg.enableGenderTts,
          onChanged: (val) => onUpdate((c) => c.copyWith(enableGenderTts: val)),
        ),
        if (cfg.enableGenderTts) ...[
          const SizedBox(height: 12),
          ConfigRow2(
            w1: ConfigDropdown(
              label: 'Giọng Nam (voice_male):',
              value: cfg.ttsVoiceMale,
              options: const [
                'vi-VN-NamMinhNeural',
                'vi-VN-BanMai',
                'vi-VN-HoaiMyNeural',
                'vi_namminh_fast',
              ],
              onChanged: (val) {
                if (val != null) onUpdate((c) => c.copyWith(ttsVoiceMale: val));
              },
            ),
            w2: ConfigDropdown(
              label: 'Giọng Nữ (voice_female):',
              value: cfg.ttsVoiceFemale,
              options: const [
                'vi-VN-HoaiMyNeural',
                'vi-VN-BanMai',
                'vi-VN-NamMinhNeural',
                'vi_banmai_fast',
              ],
              onChanged: (val) {
                if (val != null) onUpdate((c) => c.copyWith(ttsVoiceFemale: val));
              },
            ),
          ),
        ],
      ],
    );
  }
}
