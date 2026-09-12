import 'dart:io';
import 'package:flutter/material.dart';
import '../../../../models/app_config.dart';
import '../../../../utils/color_parser_utils.dart';
import '../../../../widgets/region_picker_dialog.dart';
import '../../../../widgets/settings_section_card.dart';
import '../../../../widgets/smart_color_picker_row.dart';
import '../config_input_fields.dart';

class ConfigInpaintSection extends StatelessWidget {
  final AppConfig cfg;
  final void Function(AppConfig Function(AppConfig)) onUpdate;

  const ConfigInpaintSection({
    super.key,
    required this.cfg,
    required this.onUpdate,
  });

  @override
  Widget build(BuildContext context) {
    return SettingsSectionCard(
      title: '3. Xóa Sub Cũ & Hộp Nền Che (Inpaint & SubBox)',
      icon: Icons.brush_outlined,
      subtitle: 'Xóa sub cứng bằng blur hoặc hộp nền tùy biến',
      children: [
        ConfigToggle(
          label: 'Bật Xóa Sub Cũ / Hộp Nền (show_box)',
          value: cfg.inpaintShowBox,
          onChanged: (val) => onUpdate((c) => c.copyWith(inpaintShowBox: val)),
        ),
        const SizedBox(height: 10),
        ConfigRow2(
          w1: ConfigDropdown(
            label: 'Công cụ xóa sub (engine):',
            value: cfg.inpaintEngine,
            options: [
              'box_color',
              'ffmpeg_blur',
              if (!Platform.isWindows) 'apple_vision_inpaint',
              'opencv'
            ],
            onChanged: (val) {
              if (val != null) onUpdate((c) => c.copyWith(inpaintEngine: val));
            },
          ),
          w2: ConfigDropdown(
            label: 'Thuật toán xóa (method):',
            value: cfg.inpaintMethod,
            options: const ['vertical_gradient', 'navier_stokes', 'telea'],
            onChanged: (val) {
              if (val != null) onUpdate((c) => c.copyWith(inpaintMethod: val));
            },
          ),
        ),
        const SizedBox(height: 12),
        SmartColorPickerRow(
          label: 'Màu nền hộp che (bg_color):',
          currentColor: cfg.boxBgColor,
          presets: const [
            ColorPreset(label: '⚫ Đen (black)', code: 'black', previewColor: Colors.black),
            ColorPreset(label: '🌑 Đen Slate (#0f172a)', code: '#0f172a', previewColor: Color(0xFF0F172A)),
            ColorPreset(label: '⚪ Trắng (white)', code: 'white', previewColor: Colors.white),
          ],
          onChanged: (val) => onUpdate((c) => c.copyWith(boxBgColor: val)),
        ),
        const SizedBox(height: 12),
        ConfigRow2(
          w1: ConfigSlider(
            label: 'Độ mờ nền hộp che (bg_opacity):',
            value: cfg.boxBgOpacity,
            min: 0.0,
            max: 1.0,
            divisions: 20,
            displayValue: cfg.boxBgOpacity.toStringAsFixed(2),
            onChanged: (val) => onUpdate((c) => c.copyWith(boxBgOpacity: double.parse(val.toStringAsFixed(2)))),
          ),
          w2: ConfigSlider(
            label: 'Bán kính mờ (blur_radius):',
            value: cfg.inpaintBlurRadius.toDouble(),
            min: 0.0,
            max: 60.0,
            divisions: 12,
            displayValue: '${cfg.inpaintBlurRadius} px',
            onChanged: (val) => onUpdate((c) => c.copyWith(inpaintBlurRadius: val.round())),
          ),
        ),
        const SizedBox(height: 12),
        ConfigRow2(
          w1: ConfigSlider(
            label: 'Bo góc hộp che (border_radius):',
            value: cfg.boxBorderRadius.toDouble(),
            min: 0.0,
            max: 30.0,
            divisions: 15,
            displayValue: '${cfg.boxBorderRadius} px',
            onChanged: (val) => onUpdate((c) => c.copyWith(boxBorderRadius: val.round())),
          ),
          w2: ConfigSlider(
            label: 'Độ đệm dọc (padding_y):',
            value: cfg.inpaintPaddingY,
            min: 0.0,
            max: 30.0,
            divisions: 15,
            displayValue: '${cfg.inpaintPaddingY.toStringAsFixed(1)} px',
            onChanged: (val) => onUpdate((c) => c.copyWith(inpaintPaddingY: double.parse(val.toStringAsFixed(1)))),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text(
                'Vùng Inpaint: ${cfg.inpaintRegion != null ? "[${cfg.inpaintRegion!.map((v) => '${(v * 100).toInt()}%').join(', ')}]" : "Tự động phát hiện (Auto Detect)"}',
                style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500),
              ),
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.crop, size: 14),
              label: const Text('Chọn Vùng Inpaint (9:16)'),
              onPressed: () async {
                final res = await RegionPickerDialog.show(
                  context,
                  title: 'Chọn Vùng Inpaint Xóa Sub',
                  initialRegion: cfg.inpaintRegion,
                );
                if (res != null) {
                  onUpdate((c) => c.copyWith(inpaintRegion: res));
                }
              },
            ),
          ],
        ),
      ],
    );
  }
}
