import 'dart:io';
import 'package:flutter/material.dart';
import '../../../../models/app_config.dart';
import '../../../../widgets/settings_section_card.dart';
import '../config_input_fields.dart';

class ConfigHardwareSection extends StatelessWidget {
  final AppConfig cfg;
  final void Function(AppConfig Function(AppConfig)) onUpdate;

  const ConfigHardwareSection({
    super.key,
    required this.cfg,
    required this.onUpdate,
  });

  @override
  Widget build(BuildContext context) {
    return SettingsSectionCard(
      title: '8. Đa Luồng & Tài Nguyên Thiết Bị (Hardware & Concurrency)',
      icon: Icons.memory,
      subtitle: 'Phân bổ số luồng CPU/GPU cho từng bước trong quy trình',
      children: [
        ConfigRow2(
          w1: ConfigDropdown(
            label: 'Số luồng xử lý chung (num_workers):',
            value: cfg.numWorkers,
            options: const ['auto', '1', '2', '3', '4', '8'],
            onChanged: (val) {
              if (val != null) onUpdate((c) => c.copyWith(numWorkers: val));
            },
          ),
          w2: ConfigDropdown(
            label: 'Số luồng sinh TTS (tts.num_workers):',
            value: cfg.ttsNumWorkers,
            options: const ['auto', '1', '2', '4', '8', '16'],
            onChanged: (val) {
              if (val != null) onUpdate((c) => c.copyWith(ttsNumWorkers: val));
            },
          ),
        ),
        const SizedBox(height: 12),
        ConfigRow2(
          w1: ConfigDropdown(
            label: 'Engine nhận diện giọng nói (asr.engine):',
            value: cfg.asrEngine,
            options: [
              if (!Platform.isWindows) 'whisper_mlx',
              'whisper',
              'faster_whisper'
            ],
            onChanged: (val) {
              if (val != null) onUpdate((c) => c.copyWith(asrEngine: val));
            },
          ),
          w2: ConfigDropdown(
            label: 'Kích thước Model Whisper (asr.model):',
            value: cfg.asrModel,
            options: const [
              'large-v3-turbo',
              'large-v3',
              'medium',
              'small',
              'base',
              'tiny'
            ],
            onChanged: (val) {
              if (val != null) onUpdate((c) => c.copyWith(asrModel: val));
            },
          ),
        ),
        const SizedBox(height: 12),
        ConfigRow2(
          w1: ConfigDropdown(
            label: 'Engine nhận dạng chữ OCR (ocr.engine):',
            value: cfg.ocrEngine,
            options: [
              if (!Platform.isWindows) 'apple_vision',
              'rapidocr',
              'tesseract'
            ],
            onChanged: (val) {
              if (val != null) onUpdate((c) => c.copyWith(ocrEngine: val));
            },
          ),
          w2: ConfigDropdown(
            label: 'Số luồng OCR song song (ocr.num_workers):',
            value: cfg.ocrNumWorkers,
            options: const ['auto', '1', '2', '4', '8'],
            onChanged: (val) {
              if (val != null) onUpdate((c) => c.copyWith(ocrNumWorkers: val));
            },
          ),
        ),
        const SizedBox(height: 12),
        ConfigRow2(
          w1: ConfigSlider(
            label: 'Quét vị trí sub từ giây (detect_start_sec):',
            value: cfg.detectStartSec,
            min: 0.0,
            max: 30.0,
            divisions: 30,
            displayValue: '${cfg.detectStartSec.toStringAsFixed(1)}s',
            onChanged: (val) => onUpdate((c) => c.copyWith(detectStartSec: double.parse(val.toStringAsFixed(1)))),
          ),
          w2: ConfigSlider(
            label: 'Thời gian quét mẫu (detect_duration_sec):',
            value: cfg.detectDurationSec,
            min: 5.0,
            max: 60.0,
            divisions: 11,
            displayValue: '${cfg.detectDurationSec.toStringAsFixed(1)}s',
            onChanged: (val) => onUpdate((c) => c.copyWith(detectDurationSec: double.parse(val.toStringAsFixed(1)))),
          ),
        ),
      ],
    );
  }
}
