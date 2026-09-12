import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../../../models/app_config.dart';
import '../../../../utils/color_parser_utils.dart';
import '../../../../widgets/region_picker_dialog.dart';
import '../../../../widgets/settings_section_card.dart';
import '../../../../widgets/smart_color_picker_row.dart';
import '../config_input_fields.dart';

class ConfigWatermarkSection extends StatelessWidget {
  final AppConfig cfg;
  final void Function(AppConfig Function(AppConfig)) onUpdate;
  final List<String> availableFonts;

  const ConfigWatermarkSection({
    super.key,
    required this.cfg,
    required this.onUpdate,
    required this.availableFonts,
  });

  @override
  Widget build(BuildContext context) {
    return SettingsSectionCard(
      title: '7. Watermark & Thương Hiệu (Logo Branding)',
      icon: Icons.branding_watermark_outlined,
      subtitle: 'Logo ảnh PNG hoặc văn bản đóng dấu bản quyền góc video',
      children: [
        ConfigToggle(
          label: 'Bật Watermark trên video (watermark.enabled)',
          value: cfg.watermarkEnabled,
          onChanged: (val) => onUpdate((c) => c.copyWith(watermarkEnabled: val)),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                'Vùng hiển thị: [${cfg.watermarkRegion.map((v) => '${(v * 100).toInt()}%').join(", ")}]',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
              ),
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.crop, size: 14),
              label: const Text('Chọn Vùng 9:16 (Region)'),
              onPressed: () async {
                final res = await RegionPickerDialog.show(
                  context,
                  title: 'Chọn Vùng Watermark',
                  initialRegion: cfg.watermarkRegion,
                );
                if (res != null) {
                  onUpdate((c) => c.copyWith(watermarkRegion: res));
                }
              },
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: ConfigTextField(
                label: 'Đường dẫn ảnh Logo PNG (Ưu tiên 1):',
                value: cfg.watermarkImage,
                placeholder: 'assets/.../logo.png',
                onChanged: (val) => onUpdate((c) => c.copyWith(watermarkImage: val)),
              ),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: OutlinedButton.icon(
                icon: const Icon(Icons.folder_open, size: 14),
                label: const Text('Chọn Ảnh...'),
                onPressed: () async {
                  final result = await FilePicker.platform.pickFiles(type: FileType.image);
                  if (result != null && result.files.single.path != null) {
                    onUpdate((c) => c.copyWith(watermarkImage: result.files.single.path!));
                  }
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ConfigRow2(
          w1: ConfigTextField(
            label: 'Chữ Watermark nếu không có ảnh (text):',
            value: cfg.watermarkText,
            onChanged: (val) => onUpdate((c) => c.copyWith(watermarkText: val)),
          ),
          w2: ConfigDropdown(
            label: 'Font chữ (font_name):',
            value: cfg.watermarkFontName.isNotEmpty ? cfg.watermarkFontName : 'Arial',
            options: availableFonts.isNotEmpty ? availableFonts : ['Arial'],
            onChanged: (val) {
              if (val != null) onUpdate((c) => c.copyWith(watermarkFontName: val));
            },
          ),
        ),
        const SizedBox(height: 12),
        SmartColorPickerRow(
          label: 'Màu chữ Watermark (font_color):',
          currentColor: cfg.watermarkFontColor,
          preferAssFormat: false,
          presets: const [
            ColorPreset(label: '⚪ Trắng (white)', code: 'white', previewColor: Colors.white),
            ColorPreset(label: '🟡 Vàng (yellow)', code: 'yellow', previewColor: Color(0xFFFFFF00)),
            ColorPreset(label: '🔵 Xanh Cyan (cyan)', code: 'cyan', previewColor: Color(0xFF00FFFF)),
            ColorPreset(label: '🔴 Đỏ (red)', code: 'red', previewColor: Color(0xFFFF0000)),
            ColorPreset(label: '⚫ Đen (black)', code: 'black', previewColor: Colors.black),
          ],
          onChanged: (val) => onUpdate((c) => c.copyWith(watermarkFontColor: val)),
        ),
        const SizedBox(height: 8),
        ConfigRow2(
          w1: ConfigSlider(
            label: 'Độ đậm Logo (Opacity):',
            value: cfg.watermarkOpacity,
            min: 0.1,
            max: 1.0,
            divisions: 9,
            displayValue: cfg.watermarkOpacity.toStringAsFixed(2),
            onChanged: (val) => onUpdate((c) => c.copyWith(watermarkOpacity: double.parse(val.toStringAsFixed(2)))),
          ),
          w2: ConfigToggle(
            label: 'Nền mờ kính (blur_bg)',
            value: cfg.watermarkBlurBg,
            onChanged: (val) => onUpdate((c) => c.copyWith(watermarkBlurBg: val)),
          ),
        ),
      ],
    );
  }
}
