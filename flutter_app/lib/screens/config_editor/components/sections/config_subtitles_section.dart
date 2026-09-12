import 'package:flutter/material.dart';
import '../../../../models/app_config.dart';
import '../../../../utils/color_parser_utils.dart';
import '../../../../widgets/settings_section_card.dart';
import '../../../../widgets/smart_color_picker_row.dart';
import '../config_input_fields.dart';

class ConfigSubtitlesSection extends StatelessWidget {
  final AppConfig cfg;
  final void Function(AppConfig Function(AppConfig)) onUpdate;
  final List<String> availableFonts;

  const ConfigSubtitlesSection({
    super.key,
    required this.cfg,
    required this.onUpdate,
    required this.availableFonts,
  });

  @override
  Widget build(BuildContext context) {
    return SettingsSectionCard(
      title: '4. Phụ Đề & Kiểu Chữ (Subtitles & Fonts)',
      icon: Icons.subtitles,
      subtitle: 'Font chữ, kích thước, màu sắc và cấu hình song ngữ',
      children: [
        ConfigToggle(
          label: 'Hiển thị phụ đề trên video (show_subtitle)',
          value: cfg.showSubtitle,
          onChanged: (val) => onUpdate((c) => c.copyWith(showSubtitle: val)),
        ),
        const SizedBox(height: 10),
        ConfigRow2(
          w1: ConfigDropdown(
            label: 'Font chữ phụ đề chính (font_name):',
            value: cfg.fontName.isNotEmpty ? cfg.fontName : 'Arial',
            options: availableFonts.isNotEmpty ? availableFonts : ['Arial'],
            onChanged: (val) {
              if (val != null) onUpdate((c) => c.copyWith(fontName: val));
            },
          ),
          w2: ConfigTextField(
            label: 'Cỡ chữ (font_size, để trống để tự động):',
            value: cfg.fontSize,
            placeholder: 'Auto (ví dụ: 36, 42...)',
            onChanged: (val) => onUpdate((c) => c.copyWith(fontSize: val)),
          ),
        ),
        const SizedBox(height: 12),
        SmartColorPickerRow(
          label: 'Màu chữ chính (font_color):',
          currentColor: cfg.fontColor,
          presets: const [
            ColorPreset(label: '⚪ Trắng (white)', code: 'white', previewColor: Colors.white),
            ColorPreset(label: '🟡 Vàng (yellow)', code: 'yellow', previewColor: Color(0xFFFFFF00)),
            ColorPreset(label: '🔵 Xanh Cyan (cyan)', code: 'cyan', previewColor: Color(0xFF00FFFF)),
            ColorPreset(label: '🔴 Đỏ (red)', code: 'red', previewColor: Color(0xFFFF0000)),
          ],
          onChanged: (val) => onUpdate((c) => c.copyWith(fontColor: val)),
        ),
        const SizedBox(height: 8),
        SmartColorPickerRow(
          label: 'Màu viền chữ (outline_color):',
          currentColor: cfg.outlineColor,
          presets: const [
            ColorPreset(label: '⚫ Đen (black)', code: 'black', previewColor: Colors.black),
            ColorPreset(label: '⚪ Trắng (white)', code: 'white', previewColor: Colors.white),
            ColorPreset(label: '🔴 Đỏ Đậm (#991b1b)', code: '#991b1b', previewColor: Color(0xFF991B1B)),
          ],
          onChanged: (val) => onUpdate((c) => c.copyWith(outlineColor: val)),
        ),
        const SizedBox(height: 12),
        ConfigRow2(
          w1: ConfigSlider(
            label: 'Tốc độ đọc ký tự (char_rate):',
            value: cfg.charRate,
            min: 10.0,
            max: 35.0,
            divisions: 25,
            displayValue: '${cfg.charRate.toStringAsFixed(1)} ký tự/s',
            onChanged: (val) => onUpdate((c) => c.copyWith(charRate: double.parse(val.toStringAsFixed(1)))),
          ),
          w2: ConfigSlider(
            label: 'Lề an toàn (safety_margin):',
            value: cfg.safetyMargin,
            min: 0.05,
            max: 0.5,
            divisions: 9,
            displayValue: '${cfg.safetyMargin.toStringAsFixed(2)}s',
            onChanged: (val) => onUpdate((c) => c.copyWith(safetyMargin: double.parse(val.toStringAsFixed(2)))),
          ),
        ),
        const SizedBox(height: 12),
        ConfigRow2(
          w1: ConfigToggle(
            label: 'Lấp khoảng trống phụ đề (fill_gap)',
            value: cfg.fillGap,
            onChanged: (val) => onUpdate((c) => c.copyWith(fillGap: val)),
          ),
          w2: ConfigSlider(
            label: 'Khoảng trống tối đa nối (max_gap_fill):',
            value: cfg.maxGapFill,
            min: 0.1,
            max: 1.0,
            divisions: 9,
            displayValue: '${cfg.maxGapFill.toStringAsFixed(2)}s',
            onChanged: (val) => onUpdate((c) => c.copyWith(maxGapFill: double.parse(val.toStringAsFixed(2)))),
          ),
        ),
        const SizedBox(height: 12),
        ConfigRow2(
          w1: ConfigSlider(
            label: 'Lead In hộp nền (box_lead_in):',
            value: cfg.boxLeadIn,
            min: 0.0,
            max: 0.5,
            divisions: 10,
            displayValue: '${cfg.boxLeadIn.toStringAsFixed(2)}s',
            onChanged: (val) => onUpdate((c) => c.copyWith(boxLeadIn: double.parse(val.toStringAsFixed(2)))),
          ),
          w2: ConfigSlider(
            label: 'Lead Out hộp nền (box_lead_out):',
            value: cfg.boxLeadOut,
            min: 0.0,
            max: 0.5,
            divisions: 10,
            displayValue: '${cfg.boxLeadOut.toStringAsFixed(2)}s',
            onChanged: (val) => onUpdate((c) => c.copyWith(boxLeadOut: double.parse(val.toStringAsFixed(2)))),
          ),
        ),
        const SizedBox(height: 12),
        Divider(color: Theme.of(context).dividerColor, height: 16),
        ConfigToggle(
          label: 'Bật phụ đề song ngữ dòng 2 (subtitle_secondary.show)',
          value: cfg.subtitleSecondaryShow,
          onChanged: (val) => onUpdate((c) => c.copyWith(subtitleSecondaryShow: val)),
        ),
        if (cfg.subtitleSecondaryShow) ...[
          const SizedBox(height: 10),
          ConfigRow2(
            w1: ConfigDropdown(
              label: 'Thứ tự dòng sub (subtitle_order):',
              value: cfg.subtitleOrder,
              options: const ['primary_top', 'secondary_top'],
              onChanged: (val) {
                if (val != null) onUpdate((c) => c.copyWith(subtitleOrder: val));
              },
            ),
            w2: ConfigToggle(
              label: 'Tách biệt 2 hộp nền độc lập (box_split)',
              value: cfg.boxSplit,
              onChanged: (val) => onUpdate((c) => c.copyWith(boxSplit: val)),
            ),
          ),
          const SizedBox(height: 10),
          ConfigSlider(
            label: 'Khoảng cách giữa 2 hộp phụ đề (box_gap):',
            value: cfg.boxGap.toDouble(),
            min: 0.0,
            max: 40.0,
            divisions: 20,
            displayValue: '${cfg.boxGap} px',
            onChanged: (val) => onUpdate((c) => c.copyWith(boxGap: val.round())),
          ),
        ],
      ],
    );
  }
}
