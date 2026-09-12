import 'package:flutter/material.dart';
import '../../../../models/app_config.dart';
import '../../../../widgets/settings_section_card.dart';
import '../config_input_fields.dart';

class ConfigAudioVolumesSection extends StatelessWidget {
  final AppConfig cfg;
  final void Function(AppConfig Function(AppConfig)) onUpdate;

  const ConfigAudioVolumesSection({
    super.key,
    required this.cfg,
    required this.onUpdate,
  });

  @override
  Widget build(BuildContext context) {
    return SettingsSectionCard(
      title: '6. Âm Lượng & Bộ Lọc Âm Thanh (Audio Volumes)',
      icon: Icons.volume_up,
      subtitle: 'Tỷ lệ hòa âm giữa giọng đọc, giọng gốc, nhạc nền và âm thanh môi trường',
      children: [
        ConfigRow2(
          w1: ConfigSlider(
            label: 'Giọng đọc TTS (tts_voice):',
            value: cfg.ttsVol,
            min: 0.0,
            max: 2.0,
            divisions: 20,
            displayValue: '${(cfg.ttsVol * 100).toInt()}%',
            onChanged: (val) => onUpdate((c) => c.copyWith(ttsVol: double.parse(val.toStringAsFixed(2)))),
          ),
          w2: ConfigSlider(
            label: 'Giọng gốc (original_voice):',
            value: cfg.origVoiceVol,
            min: 0.0,
            max: 1.0,
            divisions: 10,
            displayValue: '${(cfg.origVoiceVol * 100).toInt()}%',
            onChanged: (val) => onUpdate((c) => c.copyWith(origVoiceVol: double.parse(val.toStringAsFixed(2)))),
          ),
        ),
        const SizedBox(height: 12),
        ConfigRow2(
          w1: ConfigSlider(
            label: 'Nhạc nền (music):',
            value: cfg.musicVol,
            min: 0.0,
            max: 1.0,
            divisions: 10,
            displayValue: '${(cfg.musicVol * 100).toInt()}%',
            onChanged: (val) => onUpdate((c) => c.copyWith(musicVol: double.parse(val.toStringAsFixed(2)))),
          ),
          w2: ConfigSlider(
            label: 'Âm thanh môi trường (ambient):',
            value: cfg.ambientVol,
            min: 0.0,
            max: 1.0,
            divisions: 10,
            displayValue: '${(cfg.ambientVol * 100).toInt()}%',
            onChanged: (val) => onUpdate((c) => c.copyWith(ambientVol: double.parse(val.toStringAsFixed(2)))),
          ),
        ),
      ],
    );
  }
}
