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

  static const _englishVoices = [
    'en-US-JennyNeural',
    'en-US-GuyNeural',
    'en-US-AriaNeural',
    'en-US-ChristopherNeural',
    'en-GB-SoniaNeural',
    'en-GB-RyanNeural',
    'en-AU-NatashaNeural',
    'en-AU-WilliamNeural',
  ];

  static const _englishMaleVoices = [
    'en-US-GuyNeural',
    'en-US-ChristopherNeural',
    'en-GB-RyanNeural',
    'en-AU-WilliamNeural',
  ];

  static const _englishFemaleVoices = [
    'en-US-JennyNeural',
    'en-US-AriaNeural',
    'en-GB-SoniaNeural',
    'en-AU-NatashaNeural',
  ];

  static const _englishVoiceLabels = {
    'en-US-JennyNeural': '🇺🇸 Jenny (Nữ Mỹ tự nhiên)',
    'en-US-GuyNeural': '🇺🇸 Guy (Nam Mỹ truyền cảm)',
    'en-US-AriaNeural': '🇺🇸 Aria (Nữ Mỹ sôi nổi)',
    'en-US-ChristopherNeural': '🇺🇸 Christopher (Nam Mỹ trầm ấm)',
    'en-GB-SoniaNeural': '🇬🇧 Sonia (Nữ Anh chuẩn)',
    'en-GB-RyanNeural': '🇬🇧 Ryan (Nam Anh lịch lãm)',
    'en-AU-NatashaNeural': '🇦🇺 Natasha (Nữ Úc trong trẻo)',
    'en-AU-WilliamNeural': '🇦🇺 William (Nam Úc thân thiện)',
  };

  static const _vietnameseVoices = [
    'vi-VN-HoaiMyNeural',
    'vi-VN-NamMinhNeural',
    'vi_banmai_fast',
    'vi_banmai_standard',
    'vi_namminh_fast',
  ];

  static const _vietnameseMaleVoices = [
    'vi-VN-NamMinhNeural',
    'vi-VN-BanMai',
    'vi-VN-HoaiMyNeural',
    'vi_namminh_fast',
  ];

  static const _vietnameseFemaleVoices = [
    'vi-VN-HoaiMyNeural',
    'vi-VN-BanMai',
    'vi-VN-NamMinhNeural',
    'vi_banmai_fast',
  ];

  static const _vietnameseVoiceLabels = {
    'vi-VN-HoaiMyNeural': '🇻🇳 Hoài My (Nữ truyền cảm - EdgeTTS)',
    'vi-VN-NamMinhNeural': '🇻🇳 Nam Minh (Nam thời sự - EdgeTTS)',
    'vi_banmai_fast': '🇻🇳 Ban Mai Nhanh (FPT/Edge)',
    'vi_banmai_standard': '🇻🇳 Ban Mai Chuẩn (FPT/Edge)',
    'vi_namminh_fast': '🇻🇳 Nam Minh Nhanh (FPT/Edge)',
    'vi-VN-BanMai': '🇻🇳 Ban Mai (Nữ nhẹ nhàng)',
  };

  @override
  Widget build(BuildContext context) {
    final isEnglish = cfg.targetLang.toLowerCase() == 'en';
    final voiceOptions = isEnglish ? _englishVoices : _vietnameseVoices;
    final voiceMaleOptions = isEnglish ? _englishMaleVoices : _vietnameseMaleVoices;
    final voiceFemaleOptions = isEnglish ? _englishFemaleVoices : _vietnameseFemaleVoices;
    final voiceLabels = isEnglish ? _englishVoiceLabels : _vietnameseVoiceLabels;

    return SettingsSectionCard(
      title: '5. Giọng Đọc Lồng Tiếng AI (TTS & Voice)',
      icon: Icons.record_voice_over,
      subtitle: isEnglish
          ? 'Đang kích hoạt gói giọng đọc Tiếng Anh (EdgeTTS US/UK/AU) cho mục tiêu dịch "en"'
          : 'Engine sinh giọng đọc EdgeTTS / gTTS và phân biệt giới tính Nam/Nữ',
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
            label: isEnglish ? 'Giọng đọc Tiếng Anh mặc định:' : 'Giọng đọc mặc định (voice):',
            value: cfg.ttsVoice,
            options: voiceOptions,
            labels: voiceLabels,
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
              label: isEnglish ? 'Giọng Nam Tiếng Anh (voice_male):' : 'Giọng Nam (voice_male):',
              value: cfg.ttsVoiceMale,
              options: voiceMaleOptions,
              labels: voiceLabels,
              onChanged: (val) {
                if (val != null) onUpdate((c) => c.copyWith(ttsVoiceMale: val));
              },
            ),
            w2: ConfigDropdown(
              label: isEnglish ? 'Giọng Nữ Tiếng Anh (voice_female):' : 'Giọng Nữ (voice_female):',
              value: cfg.ttsVoiceFemale,
              options: voiceFemaleOptions,
              labels: voiceLabels,
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
