import 'package:flutter/material.dart';
import '../../../core/app_colors.dart';
import '../../../core/studio_state_notifier.dart';
import '../../../models/studio_state.dart';

/// Audio Mixer Bottom Bar for Video Studio (Video, Music, SFX channels).
class StudioAudioMixerBar extends StatelessWidget {
  final StudioSnapshot state;
  final StudioStateNotifier notifier;
  final void Function(int vol, bool isMuted) onVideoVolumeChanged;
  final void Function(int vol, bool isMuted) onMusicVolumeChanged;
  final void Function(int vol, bool isMuted) onSfxVolumeChanged;

  const StudioAudioMixerBar({
    super.key,
    required this.state,
    required this.notifier,
    required this.onVideoVolumeChanged,
    required this.onMusicVolumeChanged,
    required this.onSfxVolumeChanged,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.border)),
      ),
      child: Row(
        children: [
          Text(
            'MIXER ÂM THANH:',
            style: TextStyle(color: c.textMuted, fontSize: 10, fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 14),

          _buildMixerChannel(
            context: context,
            label: 'Video',
            vol: state.mixState.origVolume,
            isMuted: state.mixState.origMuted,
            color: AppColors.primary,
            onChanged: (v) {
              final next = state.mixState.copyWith(origVolume: v);
              notifier.updateMixState(next);
              onVideoVolumeChanged(v, state.mixState.origMuted);
            },
            onToggleMute: () {
              notifier.toggleMuteVideo();
              final willMute = !state.mixState.origMuted;
              onVideoVolumeChanged(state.mixState.origVolume, willMute);
            },
          ),
          const SizedBox(width: 14),

          _buildMixerChannel(
            context: context,
            label: 'Nhạc nền',
            vol: state.mixState.musicVolume,
            isMuted: state.mixState.musicMuted,
            color: AppColors.statusCompleted,
            onChanged: (v) {
              final next = state.mixState.copyWith(musicVolume: v);
              notifier.updateMixState(next);
              onMusicVolumeChanged(v, state.mixState.musicMuted);
            },
            onToggleMute: () {
              notifier.toggleMuteMusic();
              final willMute = !state.mixState.musicMuted;
              onMusicVolumeChanged(state.mixState.musicVolume, willMute);
            },
          ),
          const SizedBox(width: 14),

          _buildMixerChannel(
            context: context,
            label: 'Hiệu ứng',
            vol: state.mixState.sfxVolume,
            isMuted: state.mixState.sfxMuted,
            color: const Color(0xFF60A5FA),
            onChanged: (v) {
              final next = state.mixState.copyWith(sfxVolume: v);
              notifier.updateMixState(next);
              onSfxVolumeChanged(v, state.mixState.sfxMuted);
            },
            onToggleMute: () {
              notifier.toggleMuteSfx();
              final willMute = !state.mixState.sfxMuted;
              onSfxVolumeChanged(state.mixState.sfxVolume, willMute);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMixerChannel({
    required BuildContext context,
    required String label,
    required int vol,
    required bool isMuted,
    required Color color,
    required ValueChanged<int> onChanged,
    required VoidCallback onToggleMute,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: onToggleMute,
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.all(3),
            child: Icon(
              isMuted ? Icons.volume_off : Icons.volume_up,
              size: 14,
              color: isMuted ? AppColors.statusFailed : color,
            ),
          ),
        ),
        const SizedBox(width: 3),
        Text(
          label,
          style: TextStyle(
            color: isMuted ? AppColors.statusFailed : AppColors.textLight,
            fontSize: 10,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(width: 2),
        SizedBox(
          width: 110,
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2.5,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 8),
            ),
            child: Slider(
              value: (isMuted ? 0 : vol).toDouble(),
              min: 0,
              max: 200,
              activeColor: isMuted ? AppColors.statusFailed : color,
              inactiveColor: AppColors.surfaceLight,
              onChanged: (v) => onChanged(v.toInt()),
            ),
          ),
        ),
        SizedBox(
          width: 34,
          child: Text(
            isMuted ? 'Tắt' : '$vol%',
            style: TextStyle(
              color: isMuted ? AppColors.statusFailed : color,
              fontSize: 9.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
