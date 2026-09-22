import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/app_colors.dart';
import '../../../../core/providers.dart';
import '../../../../widgets/region_picker_dialog.dart';
import '../../../../widgets/settings_section_card.dart';
import '../controllers/movie_review_controller.dart';
import '../models/movie_review_model.dart';

class ReviewVoiceAndSubTab extends ConsumerWidget {
  final MovieReviewState state;
  final MovieReviewController controller;

  const ReviewVoiceAndSubTab({
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
        // 1. GIỌNG ĐỌC & HÒA ÂM DUCKING
        SettingsSectionCard(
          title: 'Giọng Đọc & Hòa Âm Nền',
          icon: Icons.record_voice_over_outlined,
          children: [
            DropdownButtonFormField<String>(
              value: state.ttsVoice,
              isExpanded: true,
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: c.surfaceLight,
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: c.border)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: c.border)),
              ),
              dropdownColor: c.surface,
              items: const [
                DropdownMenuItem(value: 'hoai_my', child: Text('Hoài My (Nữ miền Nam - Truyền cảm)', style: TextStyle(fontSize: 12, color: Colors.white))),
                DropdownMenuItem(value: 'nam_minh', child: Text('Nam Minh (Nam miền Bắc - Trầm ấm)', style: TextStyle(fontSize: 12, color: Colors.white))),
                DropdownMenuItem(value: 'ban_mai', child: Text('Ban Mai (Nữ miền Bắc - Rõ ràng)', style: TextStyle(fontSize: 12, color: Colors.white))),
              ],
              onChanged: (v) {
                if (v != null) controller.setTtsVoice(v);
              },
            ),
            const SizedBox(height: 8),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Tốc độ đọc:', style: TextStyle(fontSize: 11.5, color: c.textSecondary)),
                Text('${state.ttsSpeed.toStringAsFixed(2)}x', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: AppColors.primary)),
              ],
            ),
            Slider(
              value: state.ttsSpeed,
              min: 1.0,
              max: 1.5,
              divisions: 10,
              activeColor: AppColors.primary,
              onChanged: (val) => controller.setTtsSpeed(val),
            ),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Âm lượng nền (Ducking):', style: TextStyle(fontSize: 11.5, color: c.textSecondary)),
                Text(
                  state.bgmVolume == 0.0
                      ? 'Tắt tiếng phim (0%)'
                      : '${(state.bgmVolume * 100).round()}% (Hạ âm khi đọc)',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.bold,
                    color: state.bgmVolume == 0.0 ? AppColors.statusProcessing : AppColors.statusCompleted,
                  ),
                ),
              ],
            ),
            Slider(
              value: state.bgmVolume,
              min: 0.0,
              max: 0.50,
              divisions: 10,
              activeColor: AppColors.primary,
              onChanged: (val) => controller.setBgmVolume(val),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // 2. KIỂU DÁNG PHỤ ĐỀ ASS (SUBTITLE STYLE)
        SettingsSectionCard(
          title: 'Kiểu Dáng Phụ Đề ASS',
          icon: Icons.subtitles_outlined,
          children: [
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('Ghép phụ đề ASS theo giọng đọc', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
              subtitle: Text('Đồng bộ từng câu voiceover theo timing TTS', style: TextStyle(fontSize: 10, color: c.textMuted)),
              value: state.burnSubtitles,
              activeColor: AppColors.primary,
              onChanged: (val) => controller.setBurnSubtitles(val ?? true),
            ),
            if (state.burnSubtitles) ...[
              const SizedBox(height: 6),
              // Font Name
              Row(
                children: [
                  Text('Phông chữ:', style: TextStyle(fontSize: 11, color: c.textSecondary)),
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
                      items: const [
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
              const SizedBox(height: 8),

              // Font Size Slider
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Cỡ chữ:', style: TextStyle(fontSize: 11, color: c.textSecondary)),
                  Text(
                    config.fontSize.isNotEmpty ? '${config.fontSize} pt' : 'Tự động (Auto)',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.primary),
                  ),
                ],
              ),
              Slider(
                value: (double.tryParse(config.fontSize) ?? 24.0).clamp(14.0, 48.0),
                min: 14.0,
                max: 48.0,
                divisions: 17,
                activeColor: AppColors.primary,
                onChanged: (val) {
                  configNotifier.setField((cur) => cur.copyWith(fontSize: val.round().toString()));
                },
              ),

              // Colors (Chữ chính & Viền)
              Row(
                children: [
                  Expanded(
                    child: _buildColorPresetTile(
                      c,
                      label: 'Màu chữ',
                      currentColor: config.fontColor,
                      options: [
                        {'label': 'Trắng', 'val': '&H00FFFFFF', 'color': Colors.white},
                        {'label': 'Vàng', 'val': '&H0000FFFF', 'color': const Color(0xFFFBBF24)},
                        {'label': 'Xanh', 'val': '&H00FFFF00', 'color': const Color(0xFF38BDF8)},
                      ],
                      onSelect: (val) => configNotifier.setField((cur) => cur.copyWith(fontColor: val)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildColorPresetTile(
                      c,
                      label: 'Màu viền',
                      currentColor: config.outlineColor,
                      options: [
                        {'label': 'Đen', 'val': '&H00000000', 'color': Colors.black},
                        {'label': 'Đỏ', 'val': '&H000000FF', 'color': const Color(0xFFEF4444)},
                        {'label': 'Tối', 'val': '&H00202020', 'color': const Color(0xFF1E293B)},
                      ],
                      onSelect: (val) => configNotifier.setField((cur) => cur.copyWith(outlineColor: val)),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
        const SizedBox(height: 10),

        // 3. LÀM MỜ / XÓA SUB CŨ (INPAINT)
        SettingsSectionCard(
          title: 'Làm Mờ / Xóa Sub Cũ (Inpaint)',
          icon: Icons.blur_on_outlined,
          children: [
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('Làm mờ phụ đề cũ trên phim', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
              subtitle: Text('Áp dụng filter BoxBlur làm mờ vùng sub cũ', style: TextStyle(fontSize: 10, color: c.textMuted)),
              value: state.enableInpaint,
              activeColor: AppColors.primary,
              onChanged: (val) => controller.setEnableInpaint(val ?? true),
            ),
            if (state.enableInpaint) ...[
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Vùng sub mờ [Top, Left, Bottom, Right]:', style: TextStyle(fontSize: 10.5, color: c.textSecondary)),
                  InkWell(
                    onTap: () {
                      configNotifier.setField((cur) => cur.copyWith(inpaintRegion: [0.58, 0.08, 0.64, 0.94]));
                    },
                    child: const Text('Gán mẫu [0.58, 0.08, 0.64, 0.94]', style: TextStyle(fontSize: 10, color: AppColors.primary, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  _buildRegionField(c, 'Top', config.inpaintRegion != null && config.inpaintRegion!.isNotEmpty ? config.inpaintRegion![0] : 0.58, (v) {
                    final cur = List<double>.from(config.inpaintRegion ?? [0.58, 0.08, 0.64, 0.94]);
                    cur[0] = v;
                    configNotifier.setField((s) => s.copyWith(inpaintRegion: cur));
                  }),
                  const SizedBox(width: 6),
                  _buildRegionField(c, 'Left', config.inpaintRegion != null && config.inpaintRegion!.length > 1 ? config.inpaintRegion![1] : 0.08, (v) {
                    final cur = List<double>.from(config.inpaintRegion ?? [0.58, 0.08, 0.64, 0.94]);
                    cur[1] = v;
                    configNotifier.setField((s) => s.copyWith(inpaintRegion: cur));
                  }),
                  const SizedBox(width: 6),
                  _buildRegionField(c, 'Bottom', config.inpaintRegion != null && config.inpaintRegion!.length > 2 ? config.inpaintRegion![2] : 0.64, (v) {
                    final cur = List<double>.from(config.inpaintRegion ?? [0.58, 0.08, 0.64, 0.94]);
                    cur[2] = v;
                    configNotifier.setField((s) => s.copyWith(inpaintRegion: cur));
                  }),
                  const SizedBox(width: 6),
                  _buildRegionField(c, 'Right', config.inpaintRegion != null && config.inpaintRegion!.length > 3 ? config.inpaintRegion![3] : 0.94, (v) {
                    final cur = List<double>.from(config.inpaintRegion ?? [0.58, 0.08, 0.64, 0.94]);
                    cur[3] = v;
                    configNotifier.setField((s) => s.copyWith(inpaintRegion: cur));
                  }),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.crop, size: 14),
                  label: const Text('📐 Căn Chỉnh Vùng Trên Video (Interactive)', style: TextStyle(fontSize: 11)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.primary, width: 0.9),
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                  onPressed: () async {
                    final res = await RegionPickerDialog.show(
                      context,
                      title: 'Căn Chỉnh Vùng Inpaint Xóa Sub',
                      initialRegion: config.inpaintRegion,
                    );
                    if (res != null) {
                      configNotifier.setField((s) => s.copyWith(inpaintRegion: res));
                    }
                  },
                ),
              ),
              const SizedBox(height: 10),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Độ mờ (Blur Radius):', style: TextStyle(fontSize: 11, color: c.textSecondary)),
                  Text('${config.inpaintBlurRadius} px', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.primary)),
                ],
              ),
              Slider(
                value: config.inpaintBlurRadius.toDouble().clamp(5.0, 30.0),
                min: 5.0,
                max: 30.0,
                divisions: 25,
                activeColor: AppColors.primary,
                onChanged: (val) {
                  configNotifier.setField((cur) => cur.copyWith(inpaintBlurRadius: val.round()));
                },
              ),
            ],
          ],
        ),
        const SizedBox(height: 10),

        // 4. BẢO VỆ BẢN QUYỀN (COPYRIGHT SHIELD)
        SettingsSectionCard(
          title: 'Bảo Vệ Bản Quyền (Copyright Shield)',
          icon: Icons.shield_outlined,
          children: [
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('Lật gương khung hình (Horizontal Flip)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
              subtitle: Text('Đảo ngược trục ngang để tránh bot quét khuôn hình bản quyền', style: TextStyle(fontSize: 10, color: c.textMuted)),
              value: state.flipHorizontal,
              activeColor: AppColors.primary,
              onChanged: (_) => controller.toggleFlipHorizontal(),
            ),
            const Divider(height: 8, color: Colors.white12),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('Thu phóng vi mô 3% (Crop Zoom)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
              subtitle: Text('Phóng to nhẹ và cắt viền để thay đổi thông số pixel gốc', style: TextStyle(fontSize: 10, color: c.textMuted)),
              value: state.cropZoom,
              activeColor: AppColors.primary,
              onChanged: (_) => controller.toggleCropZoom(),
            ),
            const Divider(height: 8, color: Colors.white12),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('Tắt hoàn toàn âm thanh gốc của phim', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
              subtitle: Text('Chỉ phát giọng đọc lồng tiếng (TTS), triệt tiêu hoàn toàn bản quyền âm thanh', style: TextStyle(fontSize: 10, color: c.textMuted)),
              value: state.muteMovieAudio,
              activeColor: AppColors.primary,
              onChanged: (_) => controller.toggleMuteMovieAudio(),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildRegionField(AppFallbackPalette c, String label, double val, ValueChanged<double> onChanged) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 9.5, color: c.textMuted)),
          const SizedBox(height: 2),
          Container(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              color: c.surfaceLight,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: c.border),
            ),
            child: TextFormField(
              initialValue: val.toStringAsFixed(2),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(fontSize: 11, color: Colors.white),
              decoration: const InputDecoration(
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 6),
              ),
              onFieldSubmitted: (text) {
                final d = double.tryParse(text);
                if (d != null) onChanged(d);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildColorPresetTile(
    AppFallbackPalette c, {
    required String label,
    required String currentColor,
    required List<Map<String, dynamic>> options,
    required ValueChanged<String> onSelect,
  }) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: c.surfaceLight,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 10, color: c.textSecondary)),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: options.map((opt) {
              final val = opt['val'] as String;
              final color = opt['color'] as Color;
              final isSelected = currentColor.toLowerCase() == val.toLowerCase();
              return InkWell(
                onTap: () => onSelect(val),
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected ? AppColors.primary : Colors.white24,
                      width: isSelected ? 2 : 1,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
