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

class ReviewSubtitleStyleTab extends ConsumerWidget {
  final MovieReviewState state;
  final MovieReviewController controller;

  const ReviewSubtitleStyleTab({
    super.key,
    required this.state,
    required this.controller,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = AppColors.of(context);
    final config = ref.watch(configProvider);
    final configNotifier = ref.read(configProvider.notifier);
    final availableFonts = ref.watch(availableFontsProvider);

    final currentFontSize = double.tryParse(config.fontSize) ?? 34.0;

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // ── 🅰️ PHỤ ĐỀ CHÍNH (PRIMARY SUBTITLE) ──
        SettingsSectionCard(
          title: '🅰️ Phụ Đề Chính (Primary Subtitle)',
          icon: Icons.subtitles_outlined,
          subtitle: 'Kiểu dáng, cỡ chữ và màu sắc phụ đề dòng 1',
          children: [
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text(
                'Bật Hiển Thị Sub Chính (show_subtitle)',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              subtitle: Text(
                'Tự động ghép phụ đề ASS theo nhịp đọc TTS',
                style: TextStyle(fontSize: 10.5, color: c.textMuted),
              ),
              value: state.burnSubtitles,
              activeColor: AppColors.primary,
              onChanged: (val) {
                final enabled = val ?? true;
                controller.setBurnSubtitles(enabled);
                configNotifier.setField((cur) => cur.copyWith(showSubtitle: enabled, subtitleShowPrimary: enabled));
              },
            ),

            if (state.burnSubtitles) ...[
              const SizedBox(height: 8),

              // Dropdown Font Chữ
              Row(
                children: [
                  Text('Phông chữ:', style: TextStyle(fontSize: 11.5, color: c.textSecondary)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: config.fontName.isNotEmpty ? config.fontName : 'Arial',
                      isDense: true,
                      decoration: InputDecoration(
                        isDense: true,
                        filled: true,
                        fillColor: c.surfaceLight,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: c.border)),
                      ),
                      dropdownColor: c.surface,
                      items: availableFonts.isNotEmpty
                          ? availableFonts.map((f) {
                              return DropdownMenuItem(
                                value: f.name,
                                child: Text(f.name, style: const TextStyle(fontSize: 11, color: Colors.white), overflow: TextOverflow.ellipsis),
                              );
                            }).toList()
                          : const [
                              DropdownMenuItem(value: 'Arial', child: Text('Arial (Mặc định)', style: TextStyle(fontSize: 11, color: Colors.white))),
                              DropdownMenuItem(value: 'Be Vietnam Pro', child: Text('Be Vietnam Pro', style: TextStyle(fontSize: 11, color: Colors.white))),
                              DropdownMenuItem(value: 'Montserrat', child: Text('Montserrat', style: TextStyle(fontSize: 11, color: Colors.white))),
                              DropdownMenuItem(value: 'Roboto', child: Text('Roboto', style: TextStyle(fontSize: 11, color: Colors.white))),
                              DropdownMenuItem(value: 'Times New Roman', child: Text('Times New Roman', style: TextStyle(fontSize: 11, color: Colors.white))),
                            ],
                      onChanged: (f) {
                        if (f != null) configNotifier.setField((cur) => cur.copyWith(fontName: f));
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Cỡ chữ Sub Chính Slider
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Cỡ chữ Sub Chính (px):', style: TextStyle(fontSize: 11.5, color: c.textSecondary)),
                  Text(
                    '${currentFontSize.round()} px',
                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: AppColors.primary),
                  ),
                ],
              ),
              Slider(
                value: currentFontSize.clamp(12.0, 56.0),
                min: 12.0,
                max: 56.0,
                divisions: 22,
                activeColor: AppColors.primary,
                onChanged: (val) {
                  configNotifier.setField((cur) => cur.copyWith(fontSize: val.round().toString()));
                },
              ),
              const SizedBox(height: 6),

              // Màu chữ chính
              SmartColorPickerRow(
                label: 'Màu chữ chính (font_color):',
                currentColor: config.fontColor.isNotEmpty ? config.fontColor : 'white',
                presets: const [
                  ColorPreset(label: '⚪ Trắng (#FFFFFF)', code: '#FFFFFF', previewColor: Colors.white),
                  ColorPreset(label: '🟡 Vàng (#FACC15)', code: '#FACC15', previewColor: Color(0xFFFACC15)),
                  ColorPreset(label: '🔵 Cyan (#00FFFF)', code: '#00FFFF', previewColor: Color(0xFF00FFFF)),
                  ColorPreset(label: '🔴 Đỏ (#EF4444)', code: '#EF4444', previewColor: Color(0xFFEF4444)),
                  ColorPreset(label: '⚫ Đen (#000000)', code: '#000000', previewColor: Colors.black),
                ],
                onChanged: (val) => configNotifier.setField((c) => c.copyWith(fontColor: val)),
              ),
              const SizedBox(height: 8),

              // Màu viền chữ
              SmartColorPickerRow(
                label: 'Màu viền chữ (outline_color):',
                currentColor: config.outlineColor.isNotEmpty ? config.outlineColor : 'black',
                presets: const [
                  ColorPreset(label: '⚫ Đen (black)', code: 'black', previewColor: Colors.black),
                  ColorPreset(label: '⚪ Trắng (white)', code: 'white', previewColor: Colors.white),
                  ColorPreset(label: '🔴 Đỏ Đậm (#991b1b)', code: '#991b1b', previewColor: Color(0xFF991B1B)),
                ],
                onChanged: (val) => configNotifier.setField((c) => c.copyWith(outlineColor: val)),
              ),
              const SizedBox(height: 8),

              // Vị Trí Sub Chính Đồng Bộ 2 Chiều
              LayerRegionEditRow(
                label: 'Vị Trí Sub Chính (subtitle.region):',
                region: config.subtitleRegion ?? const [0.76, 0.05, 0.86, 0.95],
                layerType: FrameLayerType.primarySub,
                onReset: () {
                  configNotifier.setField((s) => s.copyWith(setSubtitleRegionNull: true));
                },
                onRegionChanged: (newRegion) {
                  configNotifier.setField((s) => s.copyWith(subtitleRegion: newRegion));
                },
                nullLabel: 'Tự động (Auto)',
              ),
            ],
          ],
        ),
        const SizedBox(height: 10),

        // ── 🅱️ PHỤ ĐỀ PHỤ SONG NGỮ (SECONDARY SUBTITLE) ──
        SettingsSectionCard(
          title: '🅱️ Phụ Đề Phụ Song Ngữ (Secondary Subtitle)',
          icon: Icons.translate_outlined,
          subtitle: 'Dòng phụ đề thứ 2 cho video song ngữ',
          children: [
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text(
                'Bật Hiển Thị Sub Phụ (subtitle_secondary.show)',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              subtitle: Text(
                'Hiển thị dòng phụ đề dịch / song ngữ thứ hai',
                style: TextStyle(fontSize: 10.5, color: c.textMuted),
              ),
              value: config.subtitleSecondaryShow,
              activeColor: AppColors.primary,
              onChanged: (val) {
                configNotifier.setField((cur) => cur.copyWith(subtitleSecondaryShow: val ?? false));
              },
            ),

            if (config.subtitleSecondaryShow) ...[
              const SizedBox(height: 8),

              // Thứ tự hiển thị Sub
              Row(
                children: [
                  Text('Thứ tự dòng sub:', style: TextStyle(fontSize: 11.5, color: c.textSecondary)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: config.subtitleOrder,
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
                        DropdownMenuItem(value: 'primary_top', child: Text('Sub Chính ở Trên (Primary Top)', style: TextStyle(fontSize: 11, color: Colors.white))),
                        DropdownMenuItem(value: 'secondary_top', child: Text('Sub Phụ ở Trên (Secondary Top)', style: TextStyle(fontSize: 11, color: Colors.white))),
                      ],
                      onChanged: (v) {
                        if (v != null) configNotifier.setField((cur) => cur.copyWith(subtitleOrder: v));
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Font Chữ Sub Phụ
              Row(
                children: [
                  Text('Phông chữ phụ:', style: TextStyle(fontSize: 11.5, color: c.textSecondary)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: config.subtitleSecondaryFontName.isNotEmpty ? config.subtitleSecondaryFontName : 'Arial',
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
                        DropdownMenuItem(value: 'Arial', child: Text('Arial', style: TextStyle(fontSize: 11, color: Colors.white))),
                        DropdownMenuItem(value: 'Be Vietnam Pro', child: Text('Be Vietnam Pro', style: TextStyle(fontSize: 11, color: Colors.white))),
                        DropdownMenuItem(value: 'Montserrat', child: Text('Montserrat', style: TextStyle(fontSize: 11, color: Colors.white))),
                        DropdownMenuItem(value: 'Roboto', child: Text('Roboto', style: TextStyle(fontSize: 11, color: Colors.white))),
                        DropdownMenuItem(value: 'Times New Roman', child: Text('Times New Roman', style: TextStyle(fontSize: 11, color: Colors.white))),
                      ],
                      onChanged: (f) {
                        if (f != null) configNotifier.setField((cur) => cur.copyWith(subtitleSecondaryFontName: f));
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Tỷ lệ cỡ chữ Sub Phụ
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Tỷ lệ cỡ chữ phụ (% so với chính):', style: TextStyle(fontSize: 11.5, color: c.textSecondary)),
                  Text('${(config.subtitleSecondaryFontScale * 100).round()}%', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: AppColors.primary)),
                ],
              ),
              Slider(
                value: config.subtitleSecondaryFontScale.clamp(0.5, 1.2),
                min: 0.5,
                max: 1.2,
                divisions: 14,
                activeColor: AppColors.primary,
                onChanged: (val) {
                  configNotifier.setField((cur) => cur.copyWith(subtitleSecondaryFontScale: double.parse(val.toStringAsFixed(2))));
                },
              ),
              const SizedBox(height: 6),

              // Màu chữ phụ
              SmartColorPickerRow(
                label: 'Màu chữ phụ (secondary.color):',
                currentColor: config.subtitleSecondaryFontColor.isNotEmpty ? config.subtitleSecondaryFontColor : '#D0D0D0',
                presets: const [
                  ColorPreset(label: '⚪ Trắng Xám (#D0D0D0)', code: '#D0D0D0', previewColor: Color(0xFFD0D0D0)),
                  ColorPreset(label: '⚪ Trắng (#FFFFFF)', code: '#FFFFFF', previewColor: Colors.white),
                  ColorPreset(label: '🟡 Vàng (#FACC15)', code: '#FACC15', previewColor: Color(0xFFFACC15)),
                  ColorPreset(label: '🔵 Cyan (#00FFFF)', code: '#00FFFF', previewColor: Color(0xFF00FFFF)),
                ],
                onChanged: (val) => configNotifier.setField((c) => c.copyWith(subtitleSecondaryFontColor: val)),
              ),
              const SizedBox(height: 8),

              // Vị Trí Sub Phụ Đồng Bộ 2 Chiều
              LayerRegionEditRow(
                label: 'Vị Trí Sub Phụ (subtitle_secondary.region):',
                region: config.subtitleSecondaryRegion ?? const [0.87, 0.05, 0.95, 0.95],
                layerType: FrameLayerType.secondarySub,
                onReset: () {
                  configNotifier.setField((s) => s.copyWith(setSubtitleSecondaryRegionNull: true));
                },
                onRegionChanged: (newRegion) {
                  configNotifier.setField((s) => s.copyWith(subtitleSecondaryRegion: newRegion));
                },
                nullLabel: 'Tự động (Auto)',
              ),
            ],
          ],
        ),
        const SizedBox(height: 10),

        // ── 🔀 BỐ CỤC SONG NGỮ & KÍCH THƯỚC (SUBBOX) ──
        SettingsSectionCard(
          title: '🔀 Bố Cục Song Ngữ & SubBox',
          icon: Icons.view_agenda_outlined,
          subtitle: 'Khoảng cách và cơ chế tách hộp nền 2 dòng sub',
          children: [
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text(
                'Tách 2 hộp nền riêng biệt (box_split)',
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              subtitle: Text(
                'Mỗi dòng sub nằm trong một hộp riêng thay vì gộp chung',
                style: TextStyle(fontSize: 10, color: c.textMuted),
              ),
              value: config.boxSplit,
              activeColor: AppColors.primary,
              onChanged: (val) => configNotifier.setField((c) => c.copyWith(boxSplit: val ?? false)),
            ),
            const SizedBox(height: 8),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Khoảng cách 2 hộp (box_gap):', style: TextStyle(fontSize: 11.5, color: c.textSecondary)),
                Text('${config.boxGap} px', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: AppColors.primary)),
              ],
            ),
            Slider(
              value: config.boxGap.toDouble().clamp(0.0, 40.0),
              min: 0.0,
              max: 40.0,
              divisions: 20,
              activeColor: AppColors.primary,
              onChanged: (val) {
                configNotifier.setField((cur) => cur.copyWith(boxGap: val.round()));
              },
            ),
          ],
        ),
      ],
    );
  }
}
