import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../core/app_colors.dart';
import '../core/providers.dart';
import '../utils/time_format_utils.dart';
import 'interactive_visual_frame_overlay.dart';

class VideoPlayerWidget extends ConsumerStatefulWidget {
  final String videoPath;
  final bool autoPlay;
  final bool isFullscreen;
  final double volume;
  final bool isMuted;
  final VoidCallback? onToggleFullscreen;
  final Function(double currentSeconds)? onPositionChanged;
  final Function(double durationSeconds)? onDurationChanged;
  final Function(bool isPlaying)? onPlayingChanged;
  final VoidCallback? onCompleted;
  final Widget? overlayWidget;

  const VideoPlayerWidget({
    super.key,
    required this.videoPath,
    this.autoPlay = false,
    this.isFullscreen = false,
    this.volume = 100.0,
    this.isMuted = false,
    this.onToggleFullscreen,
    this.onPositionChanged,
    this.onDurationChanged,
    this.onPlayingChanged,
    this.onCompleted,
    this.overlayWidget,
  });

  @override
  ConsumerState<VideoPlayerWidget> createState() => VideoPlayerWidgetState();
}

class VideoPlayerWidgetState extends ConsumerState<VideoPlayerWidget> {
  late final Player _player;
  late final VideoController _controller;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isPlaying = false;
  double _volume = 100.0;
  double _lastNonZeroVolume = 100.0;
  double _videoAspectRatio = 9 / 16;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _controller = VideoController(_player);

    _player.stream.videoParams.listen((params) {
      if (!mounted) return;
      if (params.w != null && params.h != null && params.h! > 0) {
        setState(() {
          _videoAspectRatio = params.w! / params.h!;
        });
      }
    });

    _player.stream.position.listen((pos) {
      if (!mounted) return;
      setState(() => _position = pos);
      widget.onPositionChanged?.call(pos.inMilliseconds / 1000.0);
    });

    _player.stream.duration.listen((dur) {
      if (!mounted) return;
      setState(() => _duration = dur);
      widget.onDurationChanged?.call(dur.inMilliseconds / 1000.0);
    });

    _player.stream.playing.listen((playing) {
      if (!mounted) return;
      setState(() => _isPlaying = playing);
      widget.onPlayingChanged?.call(playing);
    });

    _player.stream.completed.listen((completed) {
      if (!mounted) return;
      if (completed) {
        widget.onCompleted?.call();
      }
    });

    _player.setVolume(widget.isMuted ? 0 : widget.volume.clamp(0.0, 100.0));
    _loadVideo(widget.videoPath);
  }

  @override
  void didUpdateWidget(covariant VideoPlayerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoPath != widget.videoPath) {
      _loadVideo(widget.videoPath);
    }
    if (oldWidget.volume != widget.volume || oldWidget.isMuted != widget.isMuted) {
      _player.setVolume(widget.isMuted ? 0 : widget.volume.clamp(0.0, 100.0));
    }
  }

  void loadVideo(String path, {bool? autoPlay, double seekSeconds = 0.0}) {
    if (path.isEmpty) return;
    if (File(path).existsSync() || path.startsWith('http')) {
      _player.open(Media(path), play: autoPlay ?? widget.autoPlay).then((_) {
        if (seekSeconds > 0) {
          seekTo(seekSeconds);
        }
      });
    }
  }

  void _loadVideo(String path) => loadVideo(path);

  Future<void> seekTo(double seconds) async {
    final dur = Duration(milliseconds: (seconds * 1000).round());
    await _player.seek(dur);
  }

  Future<void> play() async => await _player.play();
  Future<void> pause() async => await _player.pause();
  Future<void> togglePlay() async => await _player.playOrPause();

  void setVolume(double vol) {
    setState(() => _volume = vol);
    _player.setVolume(vol.clamp(0.0, 100.0));
  }

  void _toggleMute() {
    if (_volume > 0) {
      _lastNonZeroVolume = _volume;
      setState(() => _volume = 0);
      _player.setVolume(0);
    } else {
      final restore = _lastNonZeroVolume > 0 ? _lastNonZeroVolume : 80.0;
      setState(() => _volume = restore);
      _player.setVolume(restore);
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final posSec = _position.inMilliseconds / 1000.0;
    final durSec = _duration.inMilliseconds / 1000.0;
    final isGizmoActive = ref.watch(isGizmoActiveProvider);

    if (widget.isFullscreen) {
      return Focus(
        autofocus: true,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.escape) {
            widget.onToggleFullscreen?.call();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Container(
          color: Colors.black,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Center(
                child: AspectRatio(
                  aspectRatio: _videoAspectRatio,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Video(
                        controller: _controller,
                        controls: NoVideoControls,
                      ),
                      if (widget.overlayWidget != null) widget.overlayWidget!,
                    ],
                  ),
                ),
              ),

              // Top Exit Fullscreen Button
              Positioned(
                top: 20,
                right: 20,
                child: IconButton(
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black54,
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.fullscreen_exit_rounded, size: 28),
                  tooltip: 'Thoát toàn màn hình (ESC)',
                  onPressed: () => widget.onToggleFullscreen?.call(),
                ),
              ),

              // Bottom Floating Control Bar
              Positioned(
                bottom: 24,
                left: 32,
                right: 32,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.surface.withOpacity(0.95),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.border, width: 1),
                    boxShadow: const [
                      BoxShadow(color: Colors.black87, blurRadius: 16),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Progress slider
                      Row(
                        children: [
                          Text(
                            TimeFormatUtils.formatDuration(posSec),
                            style: const TextStyle(
                                color: AppColors.primary,
                                fontFamily: 'monospace',
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                trackHeight: 3,
                                activeTrackColor: AppColors.primary,
                                inactiveTrackColor: AppColors.surfaceLight,
                                thumbColor: AppColors.primary,
                              ),
                              child: Slider(
                                value: posSec.clamp(0.0, durSec > 0 ? durSec : 0.0),
                                max: durSec > 0 ? durSec : 1.0,
                                onChanged: (val) {
                                  seekTo(val);
                                },
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            TimeFormatUtils.formatDuration(durSec),
                            style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontFamily: 'monospace',
                                fontSize: 11.5),
                          ),
                        ],
                      ),

                      // Controls row
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.replay_5_rounded),
                            color: Colors.white,
                            onPressed: () => seekTo((posSec - 5).clamp(0.0, durSec)),
                          ),
                          const SizedBox(width: 12),
                          GestureDetector(
                            onTap: togglePlay,
                            child: Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.primary.withOpacity(0.35),
                                    blurRadius: 8,
                                  ),
                                ],
                              ),
                              child: Icon(
                                _isPlaying
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                                color: AppColors.primaryText,
                                size: 24,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          IconButton(
                            icon: const Icon(Icons.forward_5_rounded),
                            color: Colors.white,
                            onPressed: () => seekTo((posSec + 5).clamp(0.0, durSec)),
                          ),
                          const SizedBox(width: 24),
                          IconButton(
                            icon: Icon(
                              _volume == 0
                                  ? Icons.volume_off_rounded
                                  : _volume < 50
                                      ? Icons.volume_down_rounded
                                      : Icons.volume_up_rounded,
                              color: AppColors.textSecondary,
                              size: 18,
                            ),
                            onPressed: _toggleMute,
                          ),
                          SizedBox(
                            width: 80,
                            child: SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                trackHeight: 2,
                                activeTrackColor: AppColors.primary,
                                inactiveTrackColor: AppColors.surfaceLight,
                                thumbColor: AppColors.primary,
                                thumbShape:
                                    const RoundSliderThumbShape(enabledThumbRadius: 4),
                              ),
                              child: Slider(
                                value: _volume,
                                min: 0,
                                max: 100,
                                onChanged: (val) {
                                  setState(() => _volume = val);
                                  _player.setVolume(val);
                                },
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          IconButton(
                            icon: const Icon(Icons.fullscreen_exit_rounded, color: Colors.white),
                            tooltip: 'Thoát toàn màn hình (ESC)',
                            onPressed: () => widget.onToggleFullscreen?.call(),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceDark,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      child: Column(
        children: [
          // ── VIDEO SURFACE ──
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(7)),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Center(
                    child: AspectRatio(
                      aspectRatio: _videoAspectRatio,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Video(
                            controller: _controller,
                            controls: NoVideoControls,
                          ),
                          if (widget.overlayWidget != null) widget.overlayWidget!,
                        ],
                      ),
                    ),
                  ),

                  // Interactive Visual Gizmo Overlay (Bound strictly to actual video frame)
                  if (isGizmoActive)
                    Positioned.fill(
                      child: Center(
                        child: AspectRatio(
                          aspectRatio: _videoAspectRatio,
                          child: InteractiveVisualFrameOverlay(
                            videoAspectRatio: _videoAspectRatio,
                            onClose: () =>
                                ref.read(isGizmoActiveProvider.notifier).state = false,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

          // ── MODERN CONTROL BAR ──
          Container(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
            decoration: const BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(7)),
              border: Border(top: BorderSide(color: AppColors.border, width: 1)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 1. Slim Timecode Progress Track
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceDark,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: AppColors.border, width: 0.6),
                      ),
                      child: Text(
                        TimeFormatUtils.formatDuration(posSec),
                        style: const TextStyle(
                          fontSize: 10,
                          fontFamily: 'monospace',
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 3,
                          activeTrackColor: AppColors.primary,
                          inactiveTrackColor: AppColors.surfaceLight,
                          thumbColor: AppColors.primary,
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                          overlayColor: AppColors.primary.withOpacity(0.2),
                          overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                        ),
                        child: Slider(
                          value: posSec.clamp(0.0, durSec > 0 ? durSec : 0.0),
                          max: durSec > 0 ? durSec : 1.0,
                          onChanged: (val) => seekTo(val),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceDark,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: AppColors.border, width: 0.6),
                      ),
                      child: Text(
                        TimeFormatUtils.formatDuration(durSec),
                        style: const TextStyle(
                          fontSize: 10,
                          fontFamily: 'monospace',
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 4),

                // 2. Playback Action Buttons Row
                Row(
                  children: [
                    // Rewind 5s
                    _buildRoundIconButton(
                      icon: Icons.replay_5_rounded,
                      tooltip: 'Lùi 5s',
                      size: 26,
                      iconSize: 14,
                      onPressed: () => seekTo((posSec - 5).clamp(0.0, durSec)),
                    ),
                    const SizedBox(width: 6),

                    // Primary Play/Pause Button
                    GestureDetector(
                      onTap: togglePlay,
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withOpacity(0.35),
                              blurRadius: 6,
                            ),
                          ],
                        ),
                        child: Center(
                          child: Icon(
                            _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                            color: AppColors.primaryText,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),

                    // Forward 5s
                    _buildRoundIconButton(
                      icon: Icons.forward_5_rounded,
                      tooltip: 'Tiến 5s',
                      size: 26,
                      iconSize: 14,
                      onPressed: () => seekTo((posSec + 5).clamp(0.0, durSec)),
                    ),

                    const Spacer(),

                    // 🎯 Gizmo Positioner Toggle Badge Button
                    Tooltip(
                      message: isGizmoActive
                          ? 'Đóng chế độ căn chỉnh vị trí'
                          : 'Bật căn chỉnh vị trí khung hình (Sub, Inpaint, Watermark)',
                      child: InkWell(
                        onTap: () => ref.read(isGizmoActiveProvider.notifier).state =
                            !isGizmoActive,
                        borderRadius: BorderRadius.circular(5),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding:
                              const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: isGizmoActive
                                ? AppColors.primary.withOpacity(0.18)
                                : AppColors.surfaceLight,
                            borderRadius: BorderRadius.circular(5),
                            border: Border.all(
                              color: isGizmoActive
                                  ? AppColors.primary
                                  : AppColors.border,
                              width: 0.8,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.crop_free_rounded,
                                size: 13,
                                color: isGizmoActive
                                    ? AppColors.primary
                                    : AppColors.textSecondary,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                isGizmoActive ? 'Đang Chỉnh Vị Trí' : 'Căn Chỉnh',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w500,
                                  color: isGizmoActive
                                      ? AppColors.primary
                                      : AppColors.textLight,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(width: 10),

                    // Volume Control
                    InkWell(
                      onTap: _toggleMute,
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.all(3),
                        child: Icon(
                          _volume == 0
                              ? Icons.volume_off_rounded
                              : _volume < 50
                                  ? Icons.volume_down_rounded
                                  : Icons.volume_up_rounded,
                          size: 16,
                          color: _volume == 0
                              ? AppColors.statusFailed
                              : AppColors.textSecondary,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 65,
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 2,
                          activeTrackColor: AppColors.primary,
                          inactiveTrackColor: AppColors.surfaceLight,
                          thumbColor: AppColors.primary,
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 3.5),
                          overlayShape: const RoundSliderOverlayShape(overlayRadius: 6),
                        ),
                        child: Slider(
                          value: _volume,
                          min: 0,
                          max: 100,
                          onChanged: (val) {
                            setState(() => _volume = val);
                            _player.setVolume(val);
                          },
                        ),
                      ),
                    ),

                    const SizedBox(width: 4),

                    // ⛶ Fullscreen Button
                    _buildRoundIconButton(
                      icon: Icons.fullscreen_rounded,
                      tooltip: 'Xem toàn màn hình (Fullscreen)',
                      size: 26,
                      iconSize: 16,
                      onPressed: () => widget.onToggleFullscreen?.call(),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoundIconButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
    double size = 26,
    double iconSize = 14,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(size / 2),
          child: Container(
            width: size,
            height: size,
            decoration: const BoxDecoration(
              color: AppColors.surfaceLight,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Icon(icon, size: iconSize, color: AppColors.textLight),
            ),
          ),
        ),
      ),
    );
  }
}
