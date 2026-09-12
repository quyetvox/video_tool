import 'package:flutter/material.dart';
import '../../../../core/app_colors.dart';
import '../../../../models/app_config.dart';
import '../../../../widgets/settings_section_card.dart';
import '../config_input_fields.dart';

class ConfigAppDeviceSection extends StatelessWidget {
  final AppConfig cfg;
  final void Function(AppConfig Function(AppConfig)) onUpdate;

  const ConfigAppDeviceSection({
    super.key,
    required this.cfg,
    required this.onUpdate,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);

    return SettingsSectionCard(
      title: '1. Ứng Dụng & Thiết Bị (App & Device)',
      icon: Icons.computer,
      subtitle: 'Thiết bị tăng tốc phần cứng, ngôn ngữ dịch và làm mát CPU',
      children: [
        ConfigRow2(
          w1: ConfigDropdown(
            label: 'Thiết bị xử lý (device):',
            value: cfg.device,
            options: const ['auto', 'mps', 'cpu', 'cuda'],
            onChanged: (val) {
              if (val != null) onUpdate((c) => c.copyWith(device: val));
            },
          ),
          w2: ConfigDropdown(
            label: 'Ngôn ngữ dịch chính:',
            value: cfg.targetLang,
            options: const ['vi', 'en', 'zh', 'ja', 'ko', 'fr', 'es'],
            onChanged: (val) {
              if (val != null) onUpdate((c) => c.copyWith(targetLang: val));
            },
          ),
        ),
        const SizedBox(height: 12),
        ConfigRow2(
          w1: ConfigTextField(
            label: 'Ngôn ngữ phụ song ngữ (secondary_lang):',
            value: cfg.secondaryLang,
            placeholder: 'en, zh, ja... để trống nếu chỉ đơn ngữ',
            onChanged: (val) => onUpdate((c) => c.copyWith(secondaryLang: val)),
          ),
          w2: ConfigDropdown(
            label: 'Chất lượng Bitrate Video:',
            value: cfg.videoBitrate,
            options: const ['4.0M', '2.5M', '1.5M', '6.0M'],
            onChanged: (val) {
              if (val != null) onUpdate((c) => c.copyWith(videoBitrate: val));
            },
          ),
        ),
        const SizedBox(height: 12),
        ConfigToggle(
          label: 'Chế độ Dịch Sub Cứng Hình Ảnh (ocr_only)',
          subtitle: 'Bỏ qua Whisper & Demucs (~0s audio), giữ 100% âm thanh gốc, chỉ dịch chữ phụ đề',
          value: cfg.ocrOnly,
          onChanged: (val) => onUpdate((c) => c.copyWith(ocrOnly: val)),
        ),
        const SizedBox(height: 12),
        ConfigDropdown(
          label: 'Làm mát CPU khi dịch hàng loạt (batch_cooldown_sec):',
          value: const ['auto', '0', '2', '5', '8', '10', '15', '30'].contains(cfg.batchCooldownSec)
              ? cfg.batchCooldownSec
              : 'auto',
          options: const ['auto', '0', '2', '5', '8', '10', '15', '30'],
          onChanged: (val) {
            if (val != null) onUpdate((c) => c.copyWith(batchCooldownSec: val));
          },
        ),
        const SizedBox(height: 4),
        Text(
          '• auto: Tự động thông minh theo tải (Sub: 2s, Voice: 5s, Video dài: 8s) • 0: Không chờ • 5s-15s: Làm mát máy',
          style: TextStyle(fontSize: 11, color: c.textMuted),
        ),
      ],
    );
  }
}
