import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/app_colors.dart';
import '../../../../core/providers.dart';
import '../../../../core/studio_state_notifier.dart';
import '../../../../models/studio_state.dart';
import '../../../../utils/color_parser_utils.dart';
import '../../../../widgets/smart_color_picker_row.dart';
import 'studio_property_rows.dart';
import 'studio_region_edit_row.dart';

/// 'style' Tab: Complete Subtitle Styling for Primary Subtitle, Secondary Subtitle,
/// Bilingual Layout, and SubBox container styling (synchronized with Video Editor).
class StudioSubtitleStyleTab extends ConsumerWidget {
  final StudioSnapshot state;
  final StudioStateNotifier notifier;

  const StudioSubtitleStyleTab({
    super.key,
    required this.state,
    required this.notifier,
  });

  Widget _buildAlignBtn(BuildContext context, String alignKey, String label, bool isSelected, VoidCallback onTap) {
    final c = AppColors.of(context);
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
            color: isSelected ? c.primary.withOpacity(0.2) : c.surfaceDark,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isSelected ? c.primary : c.border,
              width: isSelected ? 1.0 : 0.6,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? c.primary : c.textSecondary,
              fontSize: 10,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = AppColors.of(context);
    final s = state.subStyle;
    final availableFonts = ref.watch(availableFontsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── 🅰️ PHỤ ĐỀ CHÍNH ──
        const StudioSectionHeader('🅰️ PHỤ ĐỀ CHÍNH (PRIMARY SUBTITLE)'),
        const SizedBox(height: 4),

        StudioToggleRow(
          label: 'Bật Hiển Thị Sub Chính',
          value: s.showMainSub,
          onChanged: (val) => notifier.updateSubStyle(s.copyWith(showMainSub: val)),
        ),

        if (s.showMainSub) ...[
          const SizedBox(height: 4),

          StudioToggleRow(
            label: 'Vị Trí Thủ Công (Manual Region)',
            subtitle: 'Tắt = Tự động bám Inpaint Box',
            value: s.subtitleRegion != null,
            onChanged: (val) {
              if (val) {
                notifier.updateSubtitleRegion(state.inpaintConfig.enabled
                    ? [...state.inpaintConfig.region]
                    : [0.76, 0.05, 0.86, 0.95]);
              } else {
                notifier.updateSubtitleRegion(null);
              }
            },
          ),

          if (s.subtitleRegion != null) ...[
            StudioRegionEditRow(
              label: 'Tọa Độ Sub Chính (subtitle.region):',
              region: s.subtitleRegion!,
              layerType: StudioGizmoLayer.primarySub,
              onReset: () => notifier.updateSubtitleRegion([0.76, 0.05, 0.86, 0.95]),
            ),
          ] else ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 6, top: 2),
              child: Text(
                '↳ Tự động căn giữa theo Hộp Inpaint (Auto Focus)',
                style: TextStyle(
                  color: c.textMuted,
                  fontSize: 10.5,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ],

          // Dropdown Font Chữ Sub Chính
          StudioDropdownRow<String>(
            label: 'Font Chữ Sub Chính:',
            value: s.fontFamily.isNotEmpty ? s.fontFamily : 'Arial',
            items: availableFonts.map((f) {
              return DropdownMenuItem(
                value: f.name,
                child: Row(
                  children: [
                    if (f.isCustom) ...[
                      Icon(Icons.folder, size: 12, color: c.primary),
                      const SizedBox(width: 4),
                    ],
                    Text(f.name, overflow: TextOverflow.ellipsis),
                  ],
                ),
              );
            }).toList(),
            onChanged: (v) {
              if (v != null) notifier.updateSubStyle(s.copyWith(fontFamily: v));
            },
          ),

          StudioSliderRow(
            label: 'Cỡ Chữ Sub Chính (px):',
            value: s.fontSize.toDouble(),
            min: 12.0,
            max: 48.0,
            onChanged: (v) => notifier.updateSubStyle(s.copyWith(fontSize: v.toInt())),
            format: (v) => '${v.toInt()} px',
          ),

          SmartColorPickerRow(
            label: 'Màu Chữ Sub Chính:',
            currentColor: s.fontColor,
            presets: const [
              ColorPreset(label: '⚪ Trắng (#FFFFFF)', code: '#FFFFFF', previewColor: Colors.white),
              ColorPreset(label: '🟡 Vàng (#FACC15)', code: '#FACC15', previewColor: Color(0xFFFACC15)),
              ColorPreset(label: '🔵 Cyan (#00FFFF)', code: '#00FFFF', previewColor: Color(0xFF00FFFF)),
              ColorPreset(label: '🔴 Đỏ (#EF4444)', code: '#EF4444', previewColor: Color(0xFFEF4444)),
              ColorPreset(label: '⚫ Đen (#000000)', code: '#000000', previewColor: Colors.black),
            ],
            onChanged: (v) => notifier.updateSubStyle(s.copyWith(fontColor: v)),
          ),

          Row(
            children: [
              Expanded(
                child: StudioToggleRow(
                  label: 'In Đậm (Bold)',
                  value: s.isBold,
                  onChanged: (v) => notifier.updateSubStyle(s.copyWith(isBold: v)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: StudioToggleRow(
                  label: 'In Nghiêng (Italic)',
                  value: s.isItalic,
                  onChanged: (v) => notifier.updateSubStyle(s.copyWith(isItalic: v)),
                ),
              ),
            ],
          ),

          StudioToggleRow(
            label: 'Đổ Bóng Chữ (Drop Shadow)',
            value: s.hasDropShadow,
            onChanged: (v) => notifier.updateSubStyle(s.copyWith(hasDropShadow: v)),
          ),

          StudioSliderRow(
            label: 'Vị Trí Dọc Trục Y (% Chiều Cao):',
            value: s.posY,
            min: 5.0,
            max: 95.0,
            onChanged: (v) => notifier.updateSubStyle(s.copyWith(posY: v)),
            format: (v) => '${v.toStringAsFixed(1)}%',
          ),

          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Căn Lề Vị Trí:', style: TextStyle(color: c.textSecondary, fontSize: 10)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    _buildAlignBtn(context, 'left', 'Căn Trái', s.alignment == 'left', () => notifier.alignSubtitle('left')),
                    const SizedBox(width: 4),
                    _buildAlignBtn(context, 'center', 'Căn Giữa', s.alignment == 'center', () => notifier.alignSubtitle('center')),
                    const SizedBox(width: 4),
                    _buildAlignBtn(context, 'right', 'Căn Phải', s.alignment == 'right', () => notifier.alignSubtitle('right')),
                  ],
                ),
              ],
            ),
          ),
        ],

        const Divider(color: AppColors.border, height: 20),

        // ── 🅱️ PHỤ ĐỀ PHỤ SONG NGỮ ──
        const StudioSectionHeader('🅱️ PHỤ ĐỀ PHỤ SONG NGỮ (SECONDARY SUBTITLE)'),
        const SizedBox(height: 4),

        StudioToggleRow(
          label: 'Bật Hiển Thị Sub Phụ (Song Ngữ)',
          value: s.showSubSub,
          onChanged: (val) => notifier.updateSubStyle(s.copyWith(showSubSub: val)),
        ),

        if (s.showSubSub) ...[
          const SizedBox(height: 4),

          StudioToggleRow(
            label: 'Vị Trí Thủ Công Sub Phụ (Manual Region)',
            subtitle: 'Tắt = Tự động bám theo Sub Chính',
            value: s.subtitleSecondaryRegion != null,
            onChanged: (val) {
              if (val) {
                notifier.updateSubtitleSecondaryRegion([0.87, 0.05, 0.95, 0.95]);
              } else {
                notifier.updateSubtitleSecondaryRegion(null);
              }
            },
          ),

          if (s.subtitleSecondaryRegion != null) ...[
            StudioRegionEditRow(
              label: 'Tọa Độ Sub Phụ (subtitle.secondary.region):',
              region: s.subtitleSecondaryRegion!,
              layerType: StudioGizmoLayer.secondarySub,
              onReset: () => notifier.updateSubtitleSecondaryRegion([0.87, 0.05, 0.95, 0.95]),
            ),
          ] else ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 6, top: 2),
              child: Text(
                '↳ Tự động bám theo Sub Chính (cách box_gap px)',
                style: TextStyle(
                  color: c.textMuted,
                  fontSize: 10.5,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ],

          // Dropdown Font Chữ Sub Phụ
          StudioDropdownRow<String>(
            label: 'Font Chữ Sub Phụ:',
            value: s.secondaryFontFamily.isNotEmpty ? s.secondaryFontFamily : (s.fontFamily.isNotEmpty ? s.fontFamily : 'Arial'),
            items: availableFonts.map((f) {
              return DropdownMenuItem(
                value: f.name,
                child: Row(
                  children: [
                    if (f.isCustom) ...[
                      Icon(Icons.folder, size: 12, color: c.primary),
                      const SizedBox(width: 4),
                    ],
                    Text(f.name, overflow: TextOverflow.ellipsis),
                  ],
                ),
              );
            }).toList(),
            onChanged: (v) {
              if (v != null) notifier.updateSubStyle(s.copyWith(secondaryFontFamily: v));
            },
          ),

          StudioSliderRow(
            label: 'Cỡ Chữ Sub Phụ (px):',
            value: s.secondaryFontSize.toDouble(),
            min: 10.0,
            max: 40.0,
            onChanged: (v) => notifier.updateSubStyle(s.copyWith(secondaryFontSize: v.toInt())),
            format: (v) => '${v.toInt()} px',
          ),

          SmartColorPickerRow(
            label: 'Màu Chữ Phụ:',
            currentColor: s.origColor,
            presets: const [
              ColorPreset(label: '⚪ Trắng Xám (#D0D0D0)', code: '#D0D0D0', previewColor: Color(0xFFD0D0D0)),
              ColorPreset(label: '⚪ Trắng (#FFFFFF)', code: '#FFFFFF', previewColor: Colors.white),
              ColorPreset(label: '🟡 Vàng (#FACC15)', code: '#FACC15', previewColor: Color(0xFFFACC15)),
              ColorPreset(label: '🔵 Cyan (#00FFFF)', code: '#00FFFF', previewColor: Color(0xFF00FFFF)),
            ],
            onChanged: (v) => notifier.updateSubStyle(s.copyWith(origColor: v)),
          ),

          StudioToggleRow(
            label: 'Tách Vị Trí Sub Phụ Độc Lập',
            value: s.separateSecPos,
            onChanged: (val) => notifier.updateSubStyle(s.copyWith(separateSecPos: val)),
          ),

          if (s.separateSecPos) ...[
            StudioSliderRow(
              label: 'Vị Trí Dọc Trục Y Sub Phụ (% Chiều Cao):',
              value: s.secPosY,
              min: 5.0,
              max: 95.0,
              onChanged: (v) => notifier.updateSubStyle(s.copyWith(secPosY: v)),
              format: (v) => '${v.toStringAsFixed(1)}%',
            ),
          ],
        ],

        const Divider(color: AppColors.border, height: 20),

        // ── 🔀 BỐ CỤC SONG NGỮ & KÍCH THƯỚC ──
        const StudioSectionHeader('🔀 BỐ CỤC SONG NGỮ & KÍCH THƯỚC'),
        const SizedBox(height: 4),

        StudioSliderRow(
          label: 'Khoảng Cách 2 Hộp (box_gap):',
          value: s.boxGap,
          min: 0.0,
          max: 30.0,
          onChanged: (v) => notifier.updateSubStyle(s.copyWith(boxGap: v)),
          format: (v) => '${v.toInt()} px',
        ),

        StudioToggleRow(
          label: 'Tách 2 Hộp Nền Riêng Biệt (box_split)',
          value: s.boxSplit,
          onChanged: (val) => notifier.updateSubStyle(s.copyWith(boxSplit: val)),
        ),

        StudioSliderRow(
          label: 'Chiều Rộng Khung Sub (% Canvas):',
          value: s.boxWidthPct,
          min: 40.0,
          max: 100.0,
          onChanged: (v) => notifier.updateSubStyle(s.copyWith(boxWidthPct: v)),
          format: (v) => '${v.toInt()}%',
        ),

        const Divider(color: AppColors.border, height: 20),

        // ── 📦 HỘP NỀN SUBTITLE (SUBBOX) ──
        const StudioSectionHeader('📦 HỘP NỀN SUBTITLE (SUBBOX)'),
        const SizedBox(height: 4),

        StudioToggleRow(
          label: 'Bật Hộp Nền Subtitle (show_sub_box)',
          value: s.showSubBox,
          onChanged: (val) => notifier.updateSubStyle(s.copyWith(showSubBox: val)),
        ),

        if (s.showSubBox) ...[
          const SizedBox(height: 4),

          SmartColorPickerRow(
            label: 'Màu Nền Box (bg_color):',
            currentColor: s.boxBgColor,
            presets: const [
              ColorPreset(label: '⚫ Đen (#000000)', code: '#000000', previewColor: Colors.black),
              ColorPreset(label: '🌑 Đen Slate (#0F172A)', code: '#0F172A', previewColor: Color(0xFF0F172A)),
              ColorPreset(label: '🔘 Xám Đậm (#1E1E1E)', code: '#1E1E1E', previewColor: Color(0xFF1E1E1E)),
              ColorPreset(label: '⚪ Trắng (#FFFFFF)', code: '#FFFFFF', previewColor: Colors.white),
            ],
            onChanged: (v) => notifier.updateSubStyle(s.copyWith(boxBgColor: v)),
          ),

          StudioSliderRow(
            label: 'Độ Đậm Mờ Nền Box:',
            value: s.boxOpacity,
            min: 0.1,
            max: 1.0,
            onChanged: (v) => notifier.updateSubStyle(s.copyWith(boxOpacity: double.parse(v.toStringAsFixed(2)))),
            format: (v) => '${(v * 100).toInt()}%',
          ),

          SmartColorPickerRow(
            label: 'Màu Viền Hộp (border_color):',
            currentColor: s.boxBorderColor,
            presets: const [
              ColorPreset(label: '⚪ Trắng Mờ (#40FFFFFF)', code: '#40FFFFFF', previewColor: Color(0x66FFFFFF)),
              ColorPreset(label: '🟡 Vàng (#FACC15)', code: '#FACC15', previewColor: Color(0xFFFACC15)),
              ColorPreset(label: '🔵 Cyan (#00FFFF)', code: '#00FFFF', previewColor: Color(0xFF00FFFF)),
              ColorPreset(label: '🚫 Không Viền (transparent)', code: '#00000000', previewColor: Colors.transparent),
            ],
            onChanged: (v) => notifier.updateSubStyle(s.copyWith(boxBorderColor: v)),
          ),

          Row(
            children: [
              Expanded(
                child: StudioDropdownRow<String>(
                  label: 'Độ Dày Viền:',
                  value: s.boxBorderWidth.toInt().toString(),
                  items: const [
                    DropdownMenuItem(value: '0', child: Text('0 px (Không)')),
                    DropdownMenuItem(value: '1', child: Text('1 px (Mảnh)')),
                    DropdownMenuItem(value: '2', child: Text('2 px (Vừa)')),
                    DropdownMenuItem(value: '3', child: Text('3 px (Đậm)')),
                  ],
                  onChanged: (v) {
                    if (v != null) notifier.updateSubStyle(s.copyWith(boxBorderWidth: double.tryParse(v) ?? 0.0));
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: StudioDropdownRow<String>(
                  label: 'Bo Góc Viền:',
                  value: s.boxBorderRadius.toInt().toString(),
                  items: const [
                    DropdownMenuItem(value: '0', child: Text('0 px (Vuông)')),
                    DropdownMenuItem(value: '4', child: Text('4 px')),
                    DropdownMenuItem(value: '6', child: Text('6 px (Chuẩn)')),
                    DropdownMenuItem(value: '10', child: Text('10 px (Tròn)')),
                    DropdownMenuItem(value: '16', child: Text('16 px (Viên thuốc)')),
                  ],
                  onChanged: (v) {
                    if (v != null) notifier.updateSubStyle(s.copyWith(boxBorderRadius: double.tryParse(v) ?? 6.0));
                  },
                ),
              ),
            ],
          ),

          Row(
            children: [
              Expanded(
                child: StudioSliderRow(
                  label: 'Lề Ngang Box (px):',
                  value: s.boxPaddingX,
                  min: 0.0,
                  max: 30.0,
                  onChanged: (v) => notifier.updateSubStyle(s.copyWith(boxPaddingX: v)),
                  format: (v) => '${v.toInt()} px',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: StudioSliderRow(
                  label: 'Lề Dọc Box (px):',
                  value: s.boxPaddingY,
                  min: 0.0,
                  max: 20.0,
                  onChanged: (v) => notifier.updateSubStyle(s.copyWith(boxPaddingY: v)),
                  format: (v) => '${v.toInt()} px',
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
