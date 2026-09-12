import 'dart:io';
import 'package:flutter/material.dart';
import '../../../../core/app_colors.dart';
import '../../../../core/studio_state_notifier.dart';
import '../../../../models/studio_state.dart';
import '../../../../utils/color_parser_utils.dart';
import '../../../../widgets/smart_color_picker_row.dart';
import 'studio_property_rows.dart';
import 'studio_region_edit_row.dart';

/// 'inpaint' Tab: Inpaint engine, region gizmo trigger, and background box options.
class StudioInpaintTab extends StatelessWidget {
  final StudioSnapshot state;
  final StudioStateNotifier notifier;

  const StudioInpaintTab({
    super.key,
    required this.state,
    required this.notifier,
  });

  @override
  Widget build(BuildContext context) {
    final conf = state.inpaintConfig;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── 1. INPAINT ENGINE & MASTER TOGGLE ──
        const StudioSectionHeader('🖼️ XÓA SUB CŨ (INPAINT ENGINE)'),
        const SizedBox(height: 6),

        StudioToggleRow(
          label: 'Bật Xóa Sub Cũ / Hộp Nền (show_box)',
          value: conf.enabled,
          onChanged: (val) => notifier.updateInpaintConfig(enabled: val),
        ),
        const SizedBox(height: 6),

        StudioDropdownRow<String>(
          label: 'Inpaint Engine:',
          value: conf.engine,
          items: [
            const DropdownMenuItem(value: 'box_color', child: Text('box_color (Hộp Màu Tối)')),
            const DropdownMenuItem(value: 'ffmpeg_blur', child: Text('ffmpeg_blur (Mờ Kính)')),
            if (!Platform.isWindows)
              const DropdownMenuItem(value: 'apple_vision_inpaint', child: Text('apple_vision_inpaint (AI Inpaint)')),
            const DropdownMenuItem(value: 'opencv', child: Text('opencv (CV2 Inpaint)')),
          ],
          onChanged: (v) {
            if (v != null) notifier.updateInpaintConfig(engine: v, mode: v == 'ffmpeg_blur' ? 'blur' : 'box_color');
          },
        ),

        if (conf.engine == 'ffmpeg_blur') ...[
          const SizedBox(height: 4),
          StudioSliderRow(
            label: 'Độ Mờ Kính (blur_radius):',
            value: conf.blurRadius.toDouble(),
            min: 5.0,
            max: 40.0,
            onChanged: (v) => notifier.updateInpaintConfig(blurRadius: v.toInt()),
            format: (v) => '${v.toInt()} px',
          ),
        ],

        if (conf.engine == 'apple_vision_inpaint' || conf.engine == 'opencv') ...[
          const SizedBox(height: 4),
          StudioDropdownRow<String>(
            label: 'Thuật Toán Inpaint (Method):',
            value: conf.method,
            items: const [
              DropdownMenuItem(value: 'vertical_gradient', child: Text('vertical_gradient (Khử Vệt Sọc - Tự Nhiên)')),
              DropdownMenuItem(value: 'navier_stokes', child: Text('navier_stokes (Dòng Chảy Fluid)')),
              DropdownMenuItem(value: 'telea', child: Text('telea (Fast Marching)')),
            ],
            onChanged: (v) {
              if (v != null) notifier.updateInpaintConfig(method: v);
            },
          ),
        ],

        // Vùng che sub cũ (Inpaint Region)
        const SizedBox(height: 6),
        StudioRegionEditRow(
          label: 'Tọa Độ Vùng Che (inpaint.region):',
          region: conf.region,
          layerType: StudioGizmoLayer.inpaint,
          onReset: () => notifier.updateInpaintRegion([0.72, 0.05, 0.88, 0.95]),
        ),

        // ── 2. CẤU HÌNH HỘP NỀN BOX COLOR ──
        if (conf.engine == 'box_color') ...[
          const Divider(color: AppColors.border, height: 20),
          const StudioSectionHeader('🎨 CẤU HÌNH HỘP NỀN BOX COLOR'),
          const SizedBox(height: 6),

          SmartColorPickerRow(
            label: 'Màu Nền Box (bg_color):',
            currentColor: conf.color,
            presets: const [
              ColorPreset(label: '⚫ Đen (black)', code: '#000000', previewColor: Colors.black),
              ColorPreset(label: '🌑 Đen Slate (#0f172a)', code: '#0f172a', previewColor: Color(0xFF0F172A)),
              ColorPreset(label: '🔘 Xám Đậm (#1e1e1e)', code: '#1e1e1e', previewColor: Color(0xFF1E1E1E)),
              ColorPreset(label: '⚪ Trắng (white)', code: '#ffffff', previewColor: Colors.white),
            ],
            onChanged: (v) => notifier.updateInpaintConfig(color: v),
          ),

          StudioSliderRow(
            label: 'Độ Đậm Nền (bg_opacity):',
            value: conf.opacity,
            min: 0.1,
            max: 1.0,
            onChanged: (v) => notifier.updateInpaintConfig(opacity: double.parse(v.toStringAsFixed(2))),
            format: (v) => '${(v * 100).toInt()}%',
          ),

          SmartColorPickerRow(
            label: 'Màu Viền Hộp (border_color):',
            currentColor: conf.borderColor,
            presets: const [
              ColorPreset(label: '⚪ Trắng Mờ (#40FFFFFF)', code: '#40FFFFFF', previewColor: Color(0x66FFFFFF)),
              ColorPreset(label: '🟡 Vàng (#FACC15)', code: '#FACC15', previewColor: Color(0xFFFACC15)),
              ColorPreset(label: '🔵 Cyan (#00FFFF)', code: '#00FFFF', previewColor: Color(0xFF00FFFF)),
              ColorPreset(label: '🚫 Không Viền (none)', code: '#00000000', previewColor: Colors.transparent),
            ],
            onChanged: (v) => notifier.updateInpaintConfig(borderColor: v),
          ),

          Row(
            children: [
              Expanded(
                child: StudioDropdownRow<String>(
                  label: 'Độ Dày Viền:',
                  value: conf.borderWidth.toString(),
                  items: const [
                    DropdownMenuItem(value: '0', child: Text('0 px (Không)')),
                    DropdownMenuItem(value: '1', child: Text('1 px (Mảnh)')),
                    DropdownMenuItem(value: '2', child: Text('2 px (Vừa)')),
                    DropdownMenuItem(value: '3', child: Text('3 px (Đậm)')),
                  ],
                  onChanged: (v) {
                    if (v != null) notifier.updateInpaintConfig(borderWidth: int.tryParse(v) ?? 1);
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: StudioDropdownRow<String>(
                  label: 'Bo Góc Viền:',
                  value: conf.borderRadius.toString(),
                  items: const [
                    DropdownMenuItem(value: '0', child: Text('0 px (Vuông)')),
                    DropdownMenuItem(value: '4', child: Text('4 px')),
                    DropdownMenuItem(value: '8', child: Text('8 px (Mặc định)')),
                    DropdownMenuItem(value: '12', child: Text('12 px (Tròn)')),
                  ],
                  onChanged: (v) {
                    if (v != null) notifier.updateInpaintConfig(borderRadius: int.tryParse(v) ?? 8);
                  },
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
