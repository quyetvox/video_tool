import 'package:flutter/material.dart';
import '../../../../core/app_colors.dart';
import '../../../../core/studio_state_notifier.dart';
import '../../../../models/studio_state.dart';
import '../../../../utils/time_format_utils.dart';
import '../../../../widgets/app_kit.dart';
import '../../../../widgets/settings_section_card.dart';

/// Contextual Inspector Card shown at the top of the Properties Panel
/// when an AudioClip or OverlayClip is selected on the Timeline or Canvas.
class StudioClipInspectorCard extends StatelessWidget {
  final StudioSnapshot state;
  final StudioStateNotifier notifier;

  const StudioClipInspectorCard({
    super.key,
    required this.state,
    required this.notifier,
  });

  @override
  Widget build(BuildContext context) {
    final selId = state.selectedClipId;
    if (selId == null) return const SizedBox.shrink();

    // 1. Check if an AudioClip is selected
    final audioClip = state.audioClips.cast<AudioClip?>().firstWhere(
          (a) => a?.id == selId,
          orElse: () => null,
        );
    if (audioClip != null) {
      return _buildAudioClipInspector(context, audioClip);
    }

    // 2. Check if an OverlayClip is selected
    final overlayClip = state.overlayClips.cast<OverlayClip?>().firstWhere(
          (c) => c?.id == selId,
          orElse: () => null,
        );
    if (overlayClip != null) {
      return _buildOverlayClipInspector(context, overlayClip);
    }

    return const SizedBox.shrink();
  }

  Widget _buildAudioClipInspector(BuildContext context, AudioClip clip) {
    final c = AppColors.of(context);
    final track = state.audioTracks.cast<StudioAudioTrack?>().firstWhere(
          (t) => t?.id == clip.trackId,
          orElse: () => null,
        );
    final trackName = track?.name ?? 'Âm thanh';
    final dur = (clip.end - clip.start).clamp(0.0, 9999.0);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: SettingsSectionCard(
        title: 'THUỘC TÍNH CLIP ÂM THANH',
        icon: Icons.music_note,
        subtitle: clip.name,
        trailing: AppIconButton(
          icon: Icons.close,
          size: 14,
          color: c.textMuted,
          tooltip: 'Bỏ chọn clip',
          onPressed: () => notifier.selectClip(null),
        ),
        children: [
          // 1. Track Badge & Time Range
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF065F46),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: const Color(0xFF34D399).withOpacity(0.5)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.music_note_outlined, size: 11, color: Color(0xFF34D399)),
                    const SizedBox(width: 4),
                    Text(
                      trackName,
                      style: const TextStyle(color: Color(0xFF34D399), fontSize: 10.5, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '⏱️ ${TimeFormatUtils.formatDuration(clip.start)} – ${TimeFormatUtils.formatDuration(clip.end)} (${dur.toStringAsFixed(1)}s)',
                  style: TextStyle(color: c.textSecondary, fontSize: 10.5, fontFamily: 'monospace'),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 2. Volume Slider & Mute Toggle
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: c.surfaceDark,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: c.border, width: 0.6),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        AppIconButton(
                          icon: clip.muted ? Icons.volume_off : Icons.volume_up,
                          size: 16,
                          color: clip.muted ? c.statusFailed : const Color(0xFF34D399),
                          tooltip: clip.muted ? 'Bật âm thanh clip' : 'Tắt tiếng clip',
                          onPressed: () => notifier.toggleAudioClipMute(clip.id),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          clip.muted ? 'ĐÃ TẮT TIẾNG' : 'Âm lượng clip: ${clip.volume}%',
                          style: TextStyle(
                            color: clip.muted ? c.statusFailed : c.textPrimary,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    if (clip.volume != 100)
                      AppButton(
                        label: '100%',
                        height: 24,
                        fontSize: 10,
                        variant: AppButtonVariant.secondary,
                        onPressed: () => notifier.setAudioClipVolume(clip.id, 100),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: const Color(0xFF34D399),
                    inactiveTrackColor: c.surfaceLight,
                    thumbColor: const Color(0xFF34D399),
                    overlayColor: const Color(0xFF34D399).withOpacity(0.16),
                    trackHeight: 3.5,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                  ),
                  child: Slider(
                    value: clip.volume.toDouble().clamp(0.0, 200.0),
                    min: 0.0,
                    max: 200.0,
                    divisions: 200,
                    onChanged: (val) => notifier.setAudioClipVolume(clip.id, val.round()),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('0%', style: TextStyle(color: c.textMuted, fontSize: 9.5)),
                    Text('100% (Gốc)', style: TextStyle(color: c.textMuted, fontSize: 9.5)),
                    Text('200% (Gấp đôi)', style: TextStyle(color: c.textMuted, fontSize: 9.5)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // 3. Delete Clip Button
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              AppButton(
                icon: Icons.delete_outline,
                label: 'Xoá clip này',
                height: 26,
                fontSize: 11,
                variant: AppButtonVariant.danger,
                onPressed: () => notifier.removeAudioClip(clip.id),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOverlayClipInspector(BuildContext context, OverlayClip clip) {
    final c = AppColors.of(context);
    final track = state.overlayTracks.cast<OverlayTrack?>().firstWhere(
          (t) => t?.id == clip.trackId,
          orElse: () => null,
        );
    final trackName = track?.name ?? 'Lớp phủ';
    final dur = (clip.end - clip.start).clamp(0.0, 9999.0);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: SettingsSectionCard(
        title: 'THUỘC TÍNH LỚP PHỦ',
        icon: Icons.image_outlined,
        subtitle: clip.name,
        trailing: AppIconButton(
          icon: Icons.close,
          size: 14,
          color: c.textMuted,
          tooltip: 'Bỏ chọn lớp phủ',
          onPressed: () => notifier.selectClip(null),
        ),
        children: [
          // 1. Track Badge & Time Range
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF0369A1),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: const Color(0xFF38BDF8).withOpacity(0.5)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.image_outlined, size: 11, color: Color(0xFF38BDF8)),
                    const SizedBox(width: 4),
                    Text(
                      trackName,
                      style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 10.5, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '⏱️ ${TimeFormatUtils.formatDuration(clip.start)} – ${TimeFormatUtils.formatDuration(clip.end)} (${dur.toStringAsFixed(1)}s)',
                  style: TextStyle(color: c.textSecondary, fontSize: 10.5, fontFamily: 'monospace'),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // 2. Opacity Slider
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: c.surfaceDark,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: c.border, width: 0.6),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Độ mờ (Opacity): ${(clip.opacity * 100).round()}%',
                      style: TextStyle(color: c.textPrimary, fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                    if (clip.opacity != 1.0)
                      AppButton(
                        label: '100%',
                        height: 24,
                        fontSize: 10,
                        variant: AppButtonVariant.secondary,
                        onPressed: () => notifier.updateOverlayClipGeometry(clip.id, opacity: 1.0),
                      ),
                  ],
                ),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: const Color(0xFF38BDF8),
                    inactiveTrackColor: c.surfaceLight,
                    thumbColor: const Color(0xFF38BDF8),
                    trackHeight: 3.5,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                  ),
                  child: Slider(
                    value: clip.opacity.clamp(0.0, 1.0),
                    min: 0.0,
                    max: 1.0,
                    onChanged: (v) => notifier.updateOverlayClipGeometry(clip.id, opacity: v),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // 3. Geometry (X, Y, W, H) - Realtime synchronized with Canvas
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: c.surfaceDark,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: c.border, width: 0.6),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Vị trí & Kích thước (Đồng bộ Canvas):',
                  style: TextStyle(color: c.textSecondary, fontSize: 10.5, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: _buildMiniParamSlider(
                        context: context,
                        label: 'X (${clip.x.toStringAsFixed(1)}%)',
                        value: clip.x.clamp(0.0, 95.0),
                        min: 0.0,
                        max: 95.0,
                        color: const Color(0xFF38BDF8),
                        onChanged: (v) => notifier.updateOverlayClipGeometry(clip.id, x: v),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildMiniParamSlider(
                        context: context,
                        label: 'Y (${clip.y.toStringAsFixed(1)}%)',
                        value: clip.y.clamp(0.0, 95.0),
                        min: 0.0,
                        max: 95.0,
                        color: const Color(0xFF38BDF8),
                        onChanged: (v) => notifier.updateOverlayClipGeometry(clip.id, y: v),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: _buildMiniParamSlider(
                        context: context,
                        label: 'Rộng (${clip.width.toStringAsFixed(1)}%)',
                        value: clip.width.clamp(5.0, 100.0),
                        min: 5.0,
                        max: 100.0,
                        color: const Color(0xFFFACC15),
                        onChanged: (v) => notifier.updateOverlayClipGeometry(clip.id, width: v),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildMiniParamSlider(
                        context: context,
                        label: 'Cao (${clip.height.toStringAsFixed(1)}%)',
                        value: clip.height.clamp(5.0, 100.0),
                        min: 5.0,
                        max: 100.0,
                        color: const Color(0xFFFACC15),
                        onChanged: (v) => notifier.updateOverlayClipGeometry(clip.id, height: v),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                _buildMiniParamSlider(
                  context: context,
                  label: 'Bo góc (${clip.borderRadius.toStringAsFixed(0)}px)',
                  value: clip.borderRadius.clamp(0.0, 32.0),
                  min: 0.0,
                  max: 32.0,
                  color: c.textMuted,
                  onChanged: (v) => notifier.updateOverlayClipGeometry(clip.id, borderRadius: v),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // 4. Delete Overlay Button
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              AppButton(
                icon: Icons.delete_outline,
                label: 'Xoá lớp phủ này',
                height: 26,
                fontSize: 11,
                variant: AppButtonVariant.danger,
                onPressed: () => notifier.removeOverlayClip(clip.id),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMiniParamSlider({
    required BuildContext context,
    required String label,
    required double value,
    required double min,
    required double max,
    required Color color,
    required ValueChanged<double> onChanged,
  }) {
    final c = AppColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: c.textMuted, fontSize: 9.5)),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: color,
            inactiveTrackColor: c.surfaceLight,
            thumbColor: color,
            trackHeight: 2.5,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4),
          ),
          child: Slider(
            value: value,
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}
