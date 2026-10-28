import 'package:flutter/material.dart';
import '../../../../core/app_colors.dart';
import '../../../../models/app_config.dart';
import '../../../../widgets/settings_section_card.dart';
import '../config_input_fields.dart';

class ConfigAppDeviceSection extends StatefulWidget {
  final AppConfig cfg;
  final void Function(AppConfig Function(AppConfig)) onUpdate;

  const ConfigAppDeviceSection({
    super.key,
    required this.cfg,
    required this.onUpdate,
  });

  @override
  State<ConfigAppDeviceSection> createState() => _ConfigAppDeviceSectionState();
}

class _ConfigAppDeviceSectionState extends State<ConfigAppDeviceSection> {
  bool _isCustomSecondaryLang = false;

  static const _targetLangLabels = {
    'vi': '🇻🇳 Tiếng Việt (vi)',
    'en': '🇺🇸 Tiếng Anh (en)',
    'zh': '🇨🇳 Tiếng Trung (zh)',
    'ja': '🇯🇵 Tiếng Nhật (ja)',
    'ko': '🇰🇷 Tiếng Hàn (ko)',
    'fr': '🇫🇷 Tiếng Pháp (fr)',
    'es': '🇪🇸 Tiếng Tây Ban Nha (es)',
  };

  static const _standardSecondaryLangs = [
    '',
    'vi',
    'en',
    'zh',
    'ja',
    'ko',
    'fr',
    'es',
  ];

  static const _secondaryLangLabels = {
    '': 'Tắt (Chỉ làm đơn ngữ)',
    'vi': '🇻🇳 Tiếng Việt (vi)',
    'en': '🇺🇸 Tiếng Anh (en)',
    'zh': '🇨🇳 Tiếng Trung (zh)',
    'ja': '🇯🇵 Tiếng Nhật (ja)',
    'ko': '🇰🇷 Tiếng Hàn (ko)',
    'fr': '🇫🇷 Tiếng Pháp (fr)',
    'es': '🇪🇸 Tiếng Tây Ban Nha (es)',
    'custom': '✏️ Nhập mã ngôn ngữ khác...',
  };

  @override
  void initState() {
    super.initState();
    final current = widget.cfg.secondaryLang.trim();
    if (current.isNotEmpty && !_standardSecondaryLangs.contains(current)) {
      _isCustomSecondaryLang = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final cfg = widget.cfg;
    final onUpdate = widget.onUpdate;

    final currentSec = cfg.secondaryLang.trim();
    final hasCustom = currentSec.isNotEmpty && !_standardSecondaryLangs.contains(currentSec);
    final secondaryOptions = [
      ..._standardSecondaryLangs,
      if (hasCustom) currentSec,
      'custom',
    ];
    final secondaryLabels = {
      ..._secondaryLangLabels,
      if (hasCustom) currentSec: 'Tùy chỉnh: $currentSec',
    };

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
            label: 'Ngôn ngữ dịch chính (target_lang):',
            value: cfg.targetLang,
            options: const ['vi', 'en', 'zh', 'ja', 'ko', 'fr', 'es'],
            labels: _targetLangLabels,
            onChanged: (val) {
              if (val != null) {
                onUpdate((c) {
                  if (val.toLowerCase() == 'en' && c.targetLang.toLowerCase() != 'en') {
                    final newVoice = c.ttsVoice.startsWith('vi-') || c.ttsVoice.startsWith('vi_')
                        ? 'en-US-JennyNeural'
                        : c.ttsVoice;
                    final newMale = c.ttsVoiceMale.startsWith('vi-') || c.ttsVoiceMale.startsWith('vi_')
                        ? 'en-US-GuyNeural'
                        : c.ttsVoiceMale;
                    final newFemale = c.ttsVoiceFemale.startsWith('vi-') || c.ttsVoiceFemale.startsWith('vi_')
                        ? 'en-US-JennyNeural'
                        : c.ttsVoiceFemale;
                    return c.copyWith(
                      targetLang: val,
                      ttsVoice: newVoice,
                      ttsVoiceMale: newMale,
                      ttsVoiceFemale: newFemale,
                    );
                  } else if (val.toLowerCase() == 'vi' && c.targetLang.toLowerCase() != 'vi') {
                    final newVoice = c.ttsVoice.startsWith('en-')
                        ? 'vi-VN-HoaiMyNeural'
                        : c.ttsVoice;
                    final newMale = c.ttsVoiceMale.startsWith('en-')
                        ? 'vi-VN-NamMinhNeural'
                        : c.ttsVoiceMale;
                    final newFemale = c.ttsVoiceFemale.startsWith('en-')
                        ? 'vi-VN-HoaiMyNeural'
                        : c.ttsVoiceFemale;
                    return c.copyWith(
                      targetLang: val,
                      ttsVoice: newVoice,
                      ttsVoiceMale: newMale,
                      ttsVoiceFemale: newFemale,
                    );
                  }
                  return c.copyWith(targetLang: val);
                });
              }
            },
          ),
        ),
        const SizedBox(height: 12),
        ConfigRow2(
          w1: _isCustomSecondaryLang
              ? ConfigTextField(
                  label: 'Ngôn ngữ phụ tùy chỉnh (ISO):',
                  value: cfg.secondaryLang,
                  placeholder: 'de, ru, th... để trống nếu chỉ đơn ngữ',
                  onChanged: (val) => onUpdate((c) => c.copyWith(secondaryLang: val.trim())),
                  suffixIcon: Tooltip(
                    message: 'Quay lại danh sách chọn nhanh (vi, en, zh...)',
                    child: IconButton(
                      icon: const Icon(Icons.list_rounded, size: 18),
                      onPressed: () {
                        setState(() {
                          _isCustomSecondaryLang = false;
                          if (!_standardSecondaryLangs.contains(cfg.secondaryLang)) {
                            onUpdate((c) => c.copyWith(secondaryLang: ''));
                          }
                        });
                      },
                    ),
                  ),
                )
              : ConfigDropdown(
                  label: 'Ngôn ngữ phụ song ngữ (secondary_lang):',
                  value: cfg.secondaryLang,
                  options: secondaryOptions,
                  labels: secondaryLabels,
                  onChanged: (val) {
                    if (val == 'custom') {
                      setState(() => _isCustomSecondaryLang = true);
                    } else if (val != null) {
                      onUpdate((c) => c.copyWith(secondaryLang: val));
                    }
                  },
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
