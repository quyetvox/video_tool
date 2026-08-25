import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
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
                    color: const Color(0xFF0F172A).withOpacity(0.92),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF334155), width: 1),
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
                                color: Color(0xFF38BDF8),
                                fontFamily: 'monospace',
                                fontSize: 12),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                trackHeight: 4,
                                activeTrackColor: const Color(0xFF06B6D4),
                                inactiveTrackColor: const Color(0xFF334155),
                                thumbColor: const Color(0xFF06B6D4),
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
                                color: Color(0xFF94A3B8),
                                fontFamily: 'monospace',
                                fontSize: 12),
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
                              width: 44,
                              height: 44,
                              decoration: const BoxDecoration(
                                gradient: LinearGradient(
                                    colors: [Color(0xFF06B6D4), Color(0xFF3B82F6)]),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                _isPlaying
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                                color: Colors.white,
                                size: 26,
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
                              color: Colors.white70,
                              size: 20,
                            ),
                            onPressed: _toggleMute,
                          ),
                          SizedBox(
                            width: 80,
                            child: SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                trackHeight: 2,
                                activeTrackColor: const Color(0xFF06B6D4),
                                inactiveTrackColor: const Color(0xFF334155),
                                thumbColor: const Color(0xFF06B6D4),
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
        color: const Color(0xFF0B1120),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF1E293B), width: 1),
      ),
      child: Column(
        children: [
          // ── VIDEO SURFACE ──
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(9)),
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

          // ── MODERN CYBERPUNK CONTROL BAR ──
          Container(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
            decoration: const BoxDecoration(
              color: Color(0xFF0F172A),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(9)),
              border: Border(top: BorderSide(color: Color(0xFF1E293B), width: 1)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 1. Slim Timecode Progress Track
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0B1120),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: const Color(0xFF1E293B)),
                      ),
                      child: Text(
                        TimeFormatUtils.formatDuration(posSec),
                        style: const TextStyle(
                          fontSize: 10.5,
                          fontFamily: 'monospace',
                          color: Color(0xFF38BDF8),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 3,
                          activeTrackColor: const Color(0xFF06B6D4),
                          inactiveTrackColor: const Color(0xFF1E293B),
                          thumbColor: const Color(0xFF06B6D4),
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                          overlayColor: const Color(0xFF06B6D4).withOpacity(0.2),
                          overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                        ),
                        child: Slider(
                          value: posSec.clamp(0.0, durSec > 0 ? durSec : 0.0),
                          max: durSec > 0 ? durSec : 1.0,
                          onChanged: (val) => seekTo(val),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0B1120),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: const Color(0xFF1E293B)),
                      ),
                      child: Text(
                        TimeFormatUtils.formatDuration(durSec),
                        style: const TextStyle(
                          fontSize: 10.5,
                          fontFamily: 'monospace',
                          color: Color(0xFF94A3B8),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 6),

                // 2. Playback Action Buttons Row
                Row(
                  children: [
                    // Rewind 5s
                    _buildRoundIconButton(
                      icon: Icons.replay_5_rounded,
                      tooltip: 'Lùi 5s',
                      size: 28,
                      iconSize: 16,
                      onPressed: () => seekTo((posSec - 5).clamp(0.0, durSec)),
                    ),
                    const SizedBox(width: 8),

                    // Primary Play/Pause Button
                    GestureDetector(
                      onTap: togglePlay,
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF06B6D4), Color(0xFF2563EB)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF06B6D4).withOpacity(0.35),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                        child: Center(
                          child: Icon(
                            _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Forward 5s
                    _buildRoundIconButton(
                      icon: Icons.forward_5_rounded,
                      tooltip: 'Tiến 5s',
                      size: 28,
                      iconSize: 16,
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
                        borderRadius: BorderRadius.circular(6),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding:
                              const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                          decoration: BoxDecoration(
                            color: isGizmoActive
                                ? const Color(0xFF06B6D4).withOpacity(0.18)
                                : const Color(0xFF1E293B),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: isGizmoActive
                                  ? const Color(0xFF06B6D4)
                                  : const Color(0xFF334155),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.crop_free_rounded,
                                size: 14,
                                color: isGizmoActive
                                    ? const Color(0xFF06B6D4)
                                    : const Color(0xFF94A3B8),
                              ),
                              const SizedBox(width: 5),
                              Text(
                                isGizmoActive ? 'Đang Chỉnh Vị Trí' : 'Căn Chỉnh',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: isGizmoActive
                                      ? const Color(0xFF06B6D4)
                                      : const Color(0xFFCBD5E1),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(width: 12),

                    // Volume Control
                    InkWell(
                      onTap: _toggleMute,
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          _volume == 0
                              ? Icons.volume_off_rounded
                              : _volume < 50
                                  ? Icons.volume_down_rounded
                                  : Icons.volume_up_rounded,
                          size: 17,
                          color: _volume == 0
                              ? const Color(0xFFEF4444)
                              : const Color(0xFF94A3B8),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 70,
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 2,
                          activeTrackColor: const Color(0xFF38BDF8),
                          inactiveTrackColor: const Color(0xFF334155),
                          thumbColor: const Color(0xFF38BDF8),
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4),
                          overlayShape: const RoundSliderOverlayShape(overlayRadius: 8),
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

                    const SizedBox(width: 6),

                    // ⛶ Fullscreen Button
                    _buildRoundIconButton(
                      icon: Icons.fullscreen_rounded,
                      tooltip: 'Xem toàn màn hình (Fullscreen)',
                      size: 28,
                      iconSize: 18,
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
    double size = 28,
    double iconSize = 16,
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
              color: Color(0xFF1E293B),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Icon(icon, size: iconSize, color: const Color(0xFFCBD5E1)),
            ),
          ),
        ),
      ),
    );
  }
}
