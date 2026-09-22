import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/app_colors.dart';
import '../../../../core/providers.dart';
import '../../../../utils/color_parser_utils.dart';
import '../../../../widgets/settings_section_card.dart';
import '../../../../widgets/smart_color_picker_row.dart';
import '../../../../widgets/layer_region_edit_row.dart';
import '../controllers/movie_review_controller.dart';
import '../models/movie_review_model.dart';

class ReviewInpaintAndLogoTab extends ConsumerWidget {
  final MovieReviewState state;
  final MovieReviewController controller;

  const ReviewInpaintAndLogoTab({
    super.key,
    required this.state,
    required this.controller,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = AppColors.of(context);
    final config = ref.watch(configProvider);
    final configNotifier = ref.read(configProvider.notifier);

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // ── 1. XÓA SUB CŨ (INPAINT ENGINE) ──
        SettingsSectionCard(
          title: '1. Xóa Sub Cũ (Inpaint Engine)',
          icon: Icons.brush_outlined,
          subtitle: 'Làm mờ hoặc che sub cứng gốc trên phim',
          children: [
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text(
                'Bật Xóa Sub Cũ / Hộp Nền (inpaint.show_box)',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              subtitle: Text(
                'Tự động áp dụng bộ lọc xóa sub khi xuất video',
                style: TextStyle(fontSize: 10.5, color: c.textMuted),
              ),
              value: state.enableInpaint,
              activeColor: AppColors.primary,
              onChanged: (val) {
                final enabled = val ?? true;
                controller.setEnableInpaint(enabled);
                configNotifier.setField((cur) => cur.copyWith(inpaintShowBox: enabled));
              },
            ),
            const SizedBox(height: 8),

            // Dropdown Inpaint Engine
            Row(
              children: [
                Text('Công cụ xóa:', style: TextStyle(fontSize: 11.5, color: c.textSecondary)),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: config.inpaintEngine,
                    isDense: true,
                    decoration: InputDecoration(
                      isDense: true,
                      filled: true,
                      fillColor: c.surfaceLight,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: c.border)),
                    ),
                    dropdownColor: c.surface,
                    items: [
                      const DropdownMenuItem(value: 'ffmpeg_blur', child: Text('ffmpeg_blur (Mờ Kính — An Toàn)', style: TextStyle(fontSize: 11, color: Colors.white))),
                      const DropdownMenuItem(value: 'box_color', child: Text('box_color (Hộp Màu Tối)', style: TextStyle(fontSize: 11, color: Colors.white))),
                      if (!Platform.isWindows)
                        const DropdownMenuItem(value: 'apple_vision_inpaint', child: Text('apple_vision_inpaint (AI Inpaint)', style: TextStyle(fontSize: 11, color: Colors.white))),
                      const DropdownMenuItem(value: 'opencv', child: Text('opencv (CV2 Inpaint)', style: TextStyle(fontSize: 11, color: Colors.white))),
                    ],
                    onChanged: (v) {
                      if (v != null) configNotifier.setField((cur) => cur.copyWith(inpaintEngine: v));
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Blur Radius (khi chọn ffmpeg_blur)
            if (config.inpaintEngine == 'ffmpeg_blur') ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Độ mờ kính (blur_radius):', style: TextStyle(fontSize: 11.5, color: c.textSecondary)),
                  Text('${config.inpaintBlurRadius} px', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: AppColors.primary)),
                ],
              ),
              Slider(
                value: config.inpaintBlurRadius.toDouble().clamp(5.0, 50.0),
                min: 5.0,
                max: 50.0,
                divisions: 9,
                activeColor: AppColors.primary,
                onChanged: (val) {
                  configNotifier.setField((cur) => cur.copyWith(inpaintBlurRadius: val.round()));
                },
              ),
            ],

            // Method (khi chọn apple_vision_inpaint hoặc opencv)
            if (config.inpaintEngine == 'apple_vision_inpaint' || config.inpaintEngine == 'opencv') ...[
              Row(
                children: [
                  Text('Thuật toán xóa:', style: TextStyle(fontSize: 11.5, color: c.textSecondary)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: config.inpaintMethod,
                      isDense: true,
                      decoration: InputDecoration(
                        isDense: true,
                        filled: true,
                        fillColor: c.surfaceLight,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: c.border)),
                      ),
                      dropdownColor: c.surface,
                      items: const [
                        DropdownMenuItem(value: 'vertical_gradient', child: Text('vertical_gradient (Khử vệt sọc)', style: TextStyle(fontSize: 11, color: Colors.white))),
                        DropdownMenuItem(value: 'navier_stokes', child: Text('navier_stokes (Dòng chảy Fluid)', style: TextStyle(fontSize: 11, color: Colors.white))),
                        DropdownMenuItem(value: 'telea', child: Text('telea (Fast Marching)', style: TextStyle(fontSize: 11, color: Colors.white))),
                      ],
                      onChanged: (v) {
                        if (v != null) configNotifier.setField((cur) => cur.copyWith(inpaintMethod: v));
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
            ],

            // Vùng Inpaint Đồng Bộ 2 Chiều
            LayerRegionEditRow(
              label: 'Vùng Xóa Sub Cũ (inpaint.region):',
              region: config.inpaintRegion ?? const [0.58, 0.08, 0.64, 0.94],
              layerType: FrameLayerType.inpaint,
              onReset: () {
                configNotifier.setField(
                  (s) => s.copyWith(inpaintRegion: const [0.58, 0.08, 0.64, 0.94]),
                );
              },
              onRegionChanged: (newRegion) {
                configNotifier.setField(
                  (s) => s.copyWith(inpaintRegion: newRegion),
                );
              },
            ),
          ],
        ),
        const SizedBox(height: 10),

        // ── 2. CẤU HÌNH HỘP NỀN BOX COLOR (Khi chọn box_color) ──
        if (config.inpaintEngine == 'box_color') ...[
          SettingsSectionCard(
            title: '2. Cấu Hình Hộp Nền Box Color',
            icon: Icons.rectangle_outlined,
            subtitle: 'Màu sắc và độ mờ hộp che sub',
            children: [
              SmartColorPickerRow(
                label: 'Màu nền hộp che (bg_color):',
                currentColor: config.boxBgColor.isNotEmpty ? config.boxBgColor : 'black',
                presets: const [
                  ColorPreset(label: '⚫ Đen (#000000)', code: '#000000', previewColor: Colors.black),
                  ColorPreset(label: '🌑 Đen Slate (#0f172a)', code: '#0f172a', previewColor: Color(0xFF0F172A)),
                  ColorPreset(label: '🔘 Xám Đậm (#1e1e1e)', code: '#1e1e1e', previewColor: Color(0xFF1E1E1E)),
                  ColorPreset(label: '⚪ Trắng (#ffffff)', code: '#ffffff', previewColor: Colors.white),
                ],
                onChanged: (val) => configNotifier.setField((c) => c.copyWith(boxBgColor: val)),
              ),
              const SizedBox(height: 10),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Độ đậm nền (bg_opacity):', style: TextStyle(fontSize: 11.5, color: c.textSecondary)),
                  Text('${(config.boxBgOpacity * 100).round()}%', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: AppColors.primary)),
                ],
              ),
              Slider(
                value: config.boxBgOpacity.clamp(0.1, 1.0),
                min: 0.1,
                max: 1.0,
                divisions: 18,
                activeColor: AppColors.primary,
                onChanged: (val) {
                  configNotifier.setField((cur) => cur.copyWith(boxBgOpacity: double.parse(val.toStringAsFixed(2))));
                },
              ),
              const SizedBox(height: 8),

              SmartColorPickerRow(
                label: 'Màu viền hộp (border_color):',
                currentColor: config.boxBorderColor.isNotEmpty ? config.boxBorderColor : '#40FFFFFF',
                presets: const [
                  ColorPreset(label: '⚪ Trắng Mờ (#40FFFFFF)', code: '#40FFFFFF', previewColor: Color(0x66FFFFFF)),
                  ColorPreset(label: '🟡 Vàng (#FACC15)', code: '#FACC15', previewColor: Color(0xFFFACC15)),
                  ColorPreset(label: '🔵 Cyan (#00FFFF)', code: '#00FFFF', previewColor: Color(0xFF00FFFF)),
                  ColorPreset(label: '🚫 Không Viền (none)', code: '#00000000', previewColor: Colors.transparent),
                ],
                onChanged: (val) => configNotifier.setField((c) => c.copyWith(boxBorderColor: val)),
              ),
              const SizedBox(height: 10),

              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Độ dày viền:', style: TextStyle(fontSize: 11, color: c.textSecondary)),
                        const SizedBox(height: 4),
                        DropdownButtonFormField<int>(
                          value: config.boxBorderWidth,
                          isDense: true,
                          decoration: InputDecoration(
                            isDense: true,
                            filled: true,
                            fillColor: c.surfaceLight,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: c.border)),
                          ),
                          dropdownColor: c.surface,
                          items: const [
                            DropdownMenuItem(value: 0, child: Text('0 px (Không viền)', style: TextStyle(fontSize: 11, color: Colors.white))),
                            DropdownMenuItem(value: 1, child: Text('1 px (Mảnh)', style: TextStyle(fontSize: 11, color: Colors.white))),
                            DropdownMenuItem(value: 2, child: Text('2 px (Vừa)', style: TextStyle(fontSize: 11, color: Colors.white))),
                            DropdownMenuItem(value: 3, child: Text('3 px (Đậm)', style: TextStyle(fontSize: 11, color: Colors.white))),
                          ],
                          onChanged: (v) {
                            if (v != null) configNotifier.setField((cur) => cur.copyWith(boxBorderWidth: v));
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Bo góc viền:', style: TextStyle(fontSize: 11, color: c.textSecondary)),
                        const SizedBox(height: 4),
                        DropdownButtonFormField<int>(
                          value: config.boxBorderRadius,
                          isDense: true,
                          decoration: InputDecoration(
                            isDense: true,
                            filled: true,
                            fillColor: c.surfaceLight,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: c.border)),
                          ),
                          dropdownColor: c.surface,
                          items: const [
                            DropdownMenuItem(value: 0, child: Text('0 px (Vuông)', style: TextStyle(fontSize: 11, color: Colors.white))),
                            DropdownMenuItem(value: 4, child: Text('4 px', style: TextStyle(fontSize: 11, color: Colors.white))),
                            DropdownMenuItem(value: 8, child: Text('8 px (Mặc định)', style: TextStyle(fontSize: 11, color: Colors.white))),
                            DropdownMenuItem(value: 12, child: Text('12 px (Tròn)', style: TextStyle(fontSize: 11, color: Colors.white))),
                          ],
                          onChanged: (v) {
                            if (v != null) configNotifier.setField((cur) => cur.copyWith(boxBorderRadius: v));
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
        ],

        // ── 3. WATERMARK & THƯƠNG HIỆU (LOGO BRANDING) ──
        SettingsSectionCard(
          title: '3. Watermark & Logo Bản Quyền',
          icon: Icons.branding_watermark_outlined,
          subtitle: 'Đóng dấu logo PNG hoặc chữ bản quyền',
          children: [
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text(
                'Bật Watermark trên video',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              subtitle: Text(
                'Hiển thị logo hoặc chữ thương hiệu ở góc video',
                style: TextStyle(fontSize: 10.5, color: c.textMuted),
              ),
              value: config.watermarkEnabled,
              activeColor: AppColors.primary,
              onChanged: (val) {
                configNotifier.setField((cur) => cur.copyWith(watermarkEnabled: val ?? false));
              },
            ),

            if (config.watermarkEnabled) ...[
              const SizedBox(height: 8),

              // File ảnh Logo PNG
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Đường dẫn ảnh Logo PNG:', style: TextStyle(fontSize: 11, color: c.textSecondary)),
                        const SizedBox(height: 4),
                        TextFormField(
                          initialValue: config.watermarkImage,
                          style: const TextStyle(fontSize: 11, color: Colors.white),
                          decoration: InputDecoration(
                            isDense: true,
                            hintText: 'assets/.../logo.png',
                            hintStyle: TextStyle(fontSize: 11, color: c.textMuted),
                            filled: true,
                            fillColor: c.surfaceLight,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: c.border)),
                          ),
                          onChanged: (val) => configNotifier.setField((cur) => cur.copyWith(watermarkImage: val)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.folder_open, size: 14),
                    label: const Text('Chọn Ảnh...', style: TextStyle(fontSize: 11)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    ),
                    onPressed: () async {
                      final result = await FilePicker.platform.pickFiles(type: FileType.image);
                      if (result != null && result.files.single.path != null) {
                        configNotifier.setField((cur) => cur.copyWith(watermarkImage: result.files.single.path!));
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Chữ Watermark fallback
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Hoặc chữ Watermark nếu không có ảnh:', style: TextStyle(fontSize: 11, color: c.textSecondary)),
                  const SizedBox(height: 4),
                  TextFormField(
                    initialValue: config.watermarkText,
                    style: const TextStyle(fontSize: 11, color: Colors.white),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'Ví dụ: @SubVideoAI',
                      hintStyle: TextStyle(fontSize: 11, color: c.textMuted),
                      filled: true,
                      fillColor: c.surfaceLight,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: c.border)),
                    ),
                    onChanged: (val) => configNotifier.setField((cur) => cur.copyWith(watermarkText: val)),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Độ mờ Watermark Opacity
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Độ mờ logo (opacity):', style: TextStyle(fontSize: 11.5, color: c.textSecondary)),
                  Text('${(config.watermarkOpacity * 100).round()}%', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: AppColors.primary)),
                ],
              ),
              Slider(
                value: config.watermarkOpacity.clamp(0.1, 1.0),
                min: 0.1,
                max: 1.0,
                divisions: 18,
                activeColor: AppColors.primary,
                onChanged: (val) {
                  configNotifier.setField((cur) => cur.copyWith(watermarkOpacity: double.parse(val.toStringAsFixed(2))));
                },
              ),
              const SizedBox(height: 8),

              // Vùng Watermark Đồng Bộ 2 Chiều
              LayerRegionEditRow(
                label: 'Vùng Đặt Watermark (watermark.region):',
                region: config.watermarkRegion,
                layerType: FrameLayerType.watermark,
                onReset: () {
                  configNotifier.setField(
                    (s) => s.copyWith(watermarkRegion: const [0.02, 0.85, 0.05, 0.95]),
                  );
                },
                onRegionChanged: (newRegion) {
                  configNotifier.setField(
                    (s) => s.copyWith(watermarkRegion: newRegion),
                  );
                },
              ),
            ],
          ],
        ),
      ],
    );
  }
}
