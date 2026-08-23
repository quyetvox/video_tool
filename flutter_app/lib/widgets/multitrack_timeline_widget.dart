import 'package:flutter/material.dart';

class MultitrackTimelineWidget extends StatefulWidget {
  final double duration;
  final double currentTime;
  final double junkStart;
  final double junkEnd;
  final bool hasJunkSelected;
  final Function(double) onSeek;
  final Function(double start, double end)? onRangeChanged;

  const MultitrackTimelineWidget({
    super.key,
    required this.duration,
    required this.currentTime,
    this.junkStart = 5.0,
    this.junkEnd = 15.0,
    this.hasJunkSelected = true,
    required this.onSeek,
    this.onRangeChanged,
  });

  @override
  State<MultitrackTimelineWidget> createState() => _MultitrackTimelineWidgetState();
}

class _MultitrackTimelineWidgetState extends State<MultitrackTimelineWidget> {
  double _zoomLevel = 1.0;
  String _activeTool = 'cut'; // 'cut' | 'split' | 'merge'

  @override
  Widget build(BuildContext context) {
    final effectiveDuration = widget.duration > 0 ? widget.duration : 100.0;

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A),
        border: Border(
          top: BorderSide(color: Color(0xFF1E293B), width: 1),
        ),
      ),
      child: Column(
        children: [
          // 1. Timeline Toolbar
          Container(
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: const BoxDecoration(
              color: Color(0xFF0B1120),
              border: Border(
                bottom: BorderSide(color: Color(0xFF1E293B), width: 1),
              ),
            ),
            child: Row(
              children: [
                _buildToolBtn(icon: Icons.folder_outlined, label: 'Thư viện video', isSelected: false, onTap: () {}),
                const SizedBox(width: 6),
                _buildToolBtn(icon: Icons.content_cut, label: 'Cắt bỏ rác', isSelected: _activeTool == 'cut', onTap: () => setState(() => _activeTool = 'cut')),
                const SizedBox(width: 6),
                _buildToolBtn(icon: Icons.splitscreen_outlined, label: 'Chia clip (S)', isSelected: _activeTool == 'split', onTap: () => setState(() => _activeTool = 'split')),
                const SizedBox(width: 6),
                _buildToolBtn(icon: Icons.merge_type, label: 'Ghép video', isSelected: _activeTool == 'merge', onTap: () => setState(() => _activeTool = 'merge')),
                const SizedBox(width: 6),
                _buildToolBtn(icon: Icons.add_to_photos_outlined, label: '+ Track Lớp Phủ', isSelected: false, onTap: () {}),

                const Spacer(),

                IconButton(
                  icon: const Icon(Icons.undo, size: 16, color: Color(0xFF94A3B8)),
                  tooltip: 'Hoàn tác (Ctrl+Z)',
                  onPressed: () {},
                ),
                IconButton(
                  icon: const Icon(Icons.redo, size: 16, color: Color(0xFF94A3B8)),
                  tooltip: 'Làm lại (Ctrl+Y)',
                  onPressed: () {},
                ),

                const SizedBox(width: 8),

                // Zoom controls
                IconButton(
                  icon: const Icon(Icons.remove, size: 14, color: Color(0xFF94A3B8)),
                  onPressed: () => setState(() => _zoomLevel = (_zoomLevel - 0.2).clamp(0.5, 3.0)),
                ),
                Text(
                  '${(_zoomLevel * 100).toInt()}% Fit',
                  style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                ),
                IconButton(
                  icon: const Icon(Icons.add, size: 14, color: Color(0xFF94A3B8)),
                  onPressed: () => setState(() => _zoomLevel = (_zoomLevel + 0.2).clamp(0.5, 3.0)),
                ),
              ],
            ),
          ),

          // 2. Multitrack Tracks with Playhead
          Expanded(
            child: Row(
              children: [
                // Track Headers (Left sidebar)
                Container(
                  width: 140,
                  decoration: const BoxDecoration(
                    color: Color(0xFF0B1120),
                    border: Border(right: BorderSide(color: Color(0xFF1E293B))),
                  ),
                  child: Column(
                    children: [
                      _buildTrackHeader(title: '🎬 Video gốc', icon: Icons.videocam, hasControls: true),
                      _buildTrackHeader(title: '🖼️ Lớp phủ 1', icon: Icons.image, tag: '+ Ảnh'),
                      _buildTrackHeader(title: '🎵 Nhạc nền', icon: Icons.music_note, tag: '+ Nhạc'),
                      _buildTrackHeader(title: '🔊 Hiệu ứng', icon: Icons.volume_up, tag: '+ FX'),
                      _buildTrackHeader(title: '💬 Subtitle', icon: Icons.subtitles, tag: '+ Sub'),
                    ],
                  ),
                ),

                // Track Timelines (Right Canvas)
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final trackWidth = constraints.maxWidth;
                      final progress = (widget.currentTime / effectiveDuration).clamp(0.0, 1.0);
                      final playheadX = progress * trackWidth;

                      final junkStartX = (widget.junkStart / effectiveDuration).clamp(0.0, 1.0) * trackWidth;
                      final junkEndX = (widget.junkEnd / effectiveDuration).clamp(0.0, 1.0) * trackWidth;
                      final junkWidth = (junkEndX - junkStartX).clamp(0.0, trackWidth);

                      return GestureDetector(
                        onHorizontalDragUpdate: (details) {
                          final localX = details.localPosition.dx.clamp(0.0, trackWidth);
                          final sec = (localX / trackWidth) * effectiveDuration;
                          widget.onSeek(sec);
                        },
                        onTapDown: (details) {
                          final localX = details.localPosition.dx.clamp(0.0, trackWidth);
                          final sec = (localX / trackWidth) * effectiveDuration;
                          widget.onSeek(sec);
                        },
                        child: Stack(
                          children: [
                            Column(
                              children: [
                                // Track 1: Video gốc
                                Container(
                                  height: 36,
                                  decoration: const BoxDecoration(
                                    border: Border(bottom: BorderSide(color: Color(0xFF1E293B))),
                                  ),
                                  child: Stack(
                                    children: [
                                      // Main video strip
                                      Positioned.fill(
                                        child: Container(
                                                                               decoration: BoxDecoration(
                                            color: const Color(0xFF065F46).withOpacity(0.8),
                                            borderRadius: BorderRadius.circular(4),
                                            border: Border.all(color: const Color(0xFF10B981)),
                                          ),
                                          child: const Align(
                                            alignment: Alignment.centerLeft,
                                            child: Padding(
                                              padding: EdgeInsets.symmetric(horizontal: 8),
                                              child: Text(
                                                '#1 Video gốc',
                                                style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),

                                      // Red Junk Slice
                                      if (widget.hasJunkSelected && junkWidth > 0)
                                        Positioned(
                                          left: junkStartX,
                                          width: junkWidth,
                                          top: 2,
                                          bottom: 2,
                                          child: Container(
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFEF4444).withOpacity(0.85),
                                              borderRadius: BorderRadius.circular(4),
                                              border: Border.all(color: Colors.white, width: 1.5),
                                            ),
                                            child: const Center(
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(Icons.content_cut, size: 12, color: Colors.white),
                                                  SizedBox(width: 4),
                                                  Text(
                                                    'Cắt bỏ',
                                                    style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),

                                // Track 2: Overlay
                                _buildEmptyTrack(),
                                // Track 3: BGM
                                _buildEmptyTrack(),
                                // Track 4: FX
                                _buildEmptyTrack(),
                                // Track 5: Subtitle
                                _buildEmptyTrack(),
                              ],
                            ),

                            // Playhead Needle
                            Positioned(
                              left: playheadX - 1,
                              top: 0,
                              bottom: 0,
                              child: Container(
                                width: 2,
                                color: const Color(0xFF06B6D4),
                              ),
                            ),
                            Positioned(
                              left: playheadX - 5,
                              top: 0,
                              child: Container(
                                width: 10,
                                height: 10,
                                decoration: const BoxDecoration(
                                  color: Color(0xFF06B6D4),
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolBtn({
    required IconData icon,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF1E293B) : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: isSelected ? Border.all(color: const Color(0xFFEF4444)) : null,
        ),
        child: Row(
          children: [
            Icon(icon, size: 13, color: isSelected ? const Color(0xFFEF4444) : const Color(0xFF94A3B8)),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: isSelected ? Colors.white : const Color(0xFF94A3B8),
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrackHeader({required String title, required IconData icon, String? tag, bool hasControls = false}) {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF1E293B))),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 11, fontWeight: FontWeight.w500),
            ),
          ),
          if (tag != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(tag, style: const TextStyle(color: Color(0xFF06B6D4), fontSize: 9)),
            ),
          if (hasControls)
            const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.volume_up, size: 12, color: Color(0xFF94A3B8)),
                SizedBox(width: 4),
                Icon(Icons.visibility, size: 12, color: Color(0xFF94A3B8)),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyTrack() {
    return Container(
      height: 36,
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF1E293B))),
      ),
      child: Center(
        child: Container(
          height: 1,
          color: const Color(0xFF1E293B),
        ),
      ),
    );
  }
}
