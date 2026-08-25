import 'dart:io';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import '../core/providers.dart';
import '../core/studio_state_notifier.dart';
import '../core/thumbnail_service.dart';
import '../models/studio_state.dart';
import '../utils/time_format_utils.dart';

class MultitrackTimelineWidget extends ConsumerStatefulWidget {
  final double duration;
  final double currentTime;
  final Function(double) onSeek;

  const MultitrackTimelineWidget({
    super.key,
    required this.duration,
    required this.currentTime,
    required this.onSeek,
  });

  @override
  ConsumerState<MultitrackTimelineWidget> createState() => _MultitrackTimelineWidgetState();
}

class _MultitrackTimelineWidgetState extends ConsumerState<MultitrackTimelineWidget> {
  double _zoomLevel = 1.0;
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _handleZoomChange(double newZoom) {
    setState(() {
      _zoomLevel = newZoom.clamp(0.2, 10.0);
    });
  }

  @override
  Widget build(BuildContext context) {
    final selectedVideo = ref.watch(selectedVideoProvider);
    final toolMode = ref.watch(studioToolModeProvider);
    final studioState = ref.watch(studioStateProvider);
    final studioNotifier = ref.read(studioStateProvider.notifier);

    final effectiveDuration = widget.duration > 0 ? widget.duration : 100.0;
    final isMergeMode = toolMode == StudioToolMode.merge;
    final isCompositeMode = toolMode == StudioToolMode.composite;

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
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: const BoxDecoration(
              color: Color(0xFF0B1120),
              border: Border(bottom: BorderSide(color: Color(0xFF1E293B))),
            ),
            child: Row(
              children: [
                // 3 Mode Switchers
                _buildToolBtn(
                  icon: Icons.content_cut,
                  label: 'Cắt bỏ rác',
                  isSelected: toolMode == StudioToolMode.cut,
                  activeColor: const Color(0xFFEF4444),
                  onTap: () => ref.read(studioToolModeProvider.notifier).state = StudioToolMode.cut,
                ),
                const SizedBox(width: 4),
                _buildToolBtn(
                  icon: Icons.splitscreen,
                  label: 'Chia clip (S)',
                  isSelected: toolMode == StudioToolMode.split,
                  activeColor: const Color(0xFF38BDF8),
                  onTap: () => ref.read(studioToolModeProvider.notifier).state = StudioToolMode.split,
                ),
                const SizedBox(width: 4),
                _buildToolBtn(
                  icon: Icons.layers,
                  label: 'Ghép video (M)',
                  isSelected: toolMode == StudioToolMode.merge,
                  activeColor: const Color(0xFF34D399),
                  onTap: () => ref.read(studioToolModeProvider.notifier).state = StudioToolMode.merge,
                ),
                const SizedBox(width: 4),
                _buildToolBtn(
                  icon: Icons.movie_edit,
                  label: 'Biên tập đa lớp',
                  isSelected: toolMode == StudioToolMode.composite,
                  activeColor: const Color(0xFFA855F7),
                  onTap: () => ref.read(studioToolModeProvider.notifier).state = StudioToolMode.composite,
                ),
                const SizedBox(width: 8),

                if (isCompositeMode) ...[
                  const VerticalDivider(width: 1, indent: 8, endIndent: 8, color: Color(0xFF334155)),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF38BDF8),
                      side: const BorderSide(color: Color(0xFF0284C7), width: 0.8),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      minimumSize: Size.zero,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                    ),
                    icon: const Icon(Icons.add_photo_alternate_outlined, size: 12),
                    label: const Text('+ Track Lớp Phủ', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold)),
                    onPressed: () => studioNotifier.addOverlayTrack(),
                  ),
                ],

                const Spacer(),

                // Undo / Redo
                IconButton(
                  icon: const Icon(Icons.undo, size: 14),
                  color: studioNotifier.canUndo ? Colors.white : const Color(0xFF475569),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                  tooltip: 'Hoàn tác (Ctrl+Z)',
                  onPressed: studioNotifier.canUndo ? () => studioNotifier.undo() : null,
                ),
                IconButton(
                  icon: const Icon(Icons.redo, size: 14),
                  color: studioNotifier.canRedo ? Colors.white : const Color(0xFF475569),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                  tooltip: 'Làm lại (Ctrl+Shift+Z)',
                  onPressed: studioNotifier.canRedo ? () => studioNotifier.redo() : null,
                ),

                const SizedBox(width: 8),
                const VerticalDivider(width: 1, indent: 8, endIndent: 8, color: Color(0xFF334155)),
                const SizedBox(width: 8),

                // Zoom controls
                IconButton(
                  icon: const Icon(Icons.remove, size: 13, color: Color(0xFF94A3B8)),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                  tooltip: 'Thu nhỏ timeline (-)',
                  onPressed: () => _handleZoomChange(_zoomLevel - 0.5),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${(_zoomLevel * 100).toInt()}%',
                    style: const TextStyle(color: Color(0xFF2DD4BF), fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add, size: 13, color: Color(0xFF94A3B8)),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                  tooltip: 'Phóng to timeline (+)',
                  onPressed: () => _handleZoomChange(_zoomLevel + 0.5),
                ),
                const SizedBox(width: 4),
                TextButton(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    minimumSize: Size.zero,
                    backgroundColor: _zoomLevel == 1.0 ? const Color(0xFF2DD4BF).withOpacity(0.15) : const Color(0xFF1E293B),
                    foregroundColor: _zoomLevel == 1.0 ? const Color(0xFF2DD4BF) : const Color(0xFF94A3B8),
                  ),
                  onPressed: () => _handleZoomChange(1.0),
                  child: const Text('Fit', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),

          // 2. Multitrack Canvas Area
          Expanded(
            child: Row(
              children: [
                // Track Headers Column (Left 140px)
                Container(
                  width: 140,
                  decoration: const BoxDecoration(
                    color: Color(0xFF0B1120),
                    border: Border(right: BorderSide(color: Color(0xFF1E293B))),
                  ),
                  child: ListView(
                    children: [
                      // Ruler placeholder header
                      Container(
                        height: 22,
                        decoration: const BoxDecoration(
                          color: Color(0xFF070D18),
                          border: Border(bottom: BorderSide(color: Color(0xFF1E293B))),
                        ),
                        alignment: Alignment.centerLeft,
                        padding: const EdgeInsets.only(left: 8),
                        child: const Text('Tracks', style: TextStyle(color: Color(0xFF64748B), fontSize: 9.5, fontWeight: FontWeight.bold)),
                      ),

                      // Track 1: Video gốc
                      _buildTrackHeader(
                        height: 48,
                        title: isMergeMode ? 'Chuỗi video' : 'Video gốc',
                        icon: Icons.movie_outlined,
                        color: const Color(0xFF8B5CF6),
                        hasMute: true,
                        isMuted: studioState.mixState.origMuted,
                        onToggleMute: () => studioNotifier.toggleMuteVideo(),
                      ),

                      if (isCompositeMode) ...[
                        // Dynamic Overlay Tracks
                        ...studioState.overlayTracks.map((track) {
                          final isTrackSelected = studioState.selectedTrackId == track.id;
                          return _buildTrackHeader(
                            height: 36,
                            title: track.name,
                            icon: Icons.image_outlined,
                            color: const Color(0xFF38BDF8),
                            tag: '+ Ảnh',
                            isSelected: isTrackSelected,
                            onHeaderTap: () => studioNotifier.selectTrack(track.id),
                            onTagTap: () => _pickAndAddOverlayImage(context, track.id, effectiveDuration),
                            isVisible: track.visible,
                            isLocked: track.locked,
                            onToggleVisible: () => studioNotifier.toggleTrackVisible(track.id),
                            onToggleLock: () => studioNotifier.toggleTrackLocked(track.id),
                            onDelete: studioState.overlayTracks.length > 1
                                ? () => studioNotifier.removeOverlayTrack(track.id)
                                : null,
                          );
                        }),

                        // Audio Track 1: Nhạc nền
                        _buildTrackHeader(
                          height: 34,
                          title: 'Nhạc nền',
                          icon: Icons.music_note_outlined,
                          color: const Color(0xFF34D399),
                          tag: '+ Nhạc',
                          hasMute: true,
                          isMuted: studioState.mixState.musicMuted,
                          onToggleMute: () => studioNotifier.toggleMuteMusic(),
                          onTagTap: () => _pickAndAddAudio(context, 'music', effectiveDuration),
                        ),

                        // Audio Track 2: Hiệu ứng SFX
                        _buildTrackHeader(
                          height: 34,
                          title: 'Hiệu ứng',
                          icon: Icons.mic_none_outlined,
                          color: const Color(0xFF60A5FA),
                          tag: '+ FX',
                          hasMute: true,
                          isMuted: studioState.mixState.sfxMuted,
                          onToggleMute: () => studioNotifier.toggleMuteSfx(),
                          onTagTap: () => _pickAndAddAudio(context, 'sfx', effectiveDuration),
                        ),

                        // Subtitle Track
                        _buildTrackHeader(
                          height: 34,
                          title: 'Subtitle',
                          icon: Icons.subtitles_outlined,
                          color: const Color(0xFFFACC15),
                          tag: '+ Sub',
                          onTagTap: () => _addQuickSubtitle(effectiveDuration),
                        ),
                      ],
                    ],
                  ),
                ),

                // Track Timelines Canvas (Right)
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final baseWidth = constraints.maxWidth;
                      final canvasWidth = baseWidth * _zoomLevel;

                      final progress = (widget.currentTime / effectiveDuration).clamp(0.0, 1.0);
                      final playheadX = progress * canvasWidth;

                      final junkStartX = (studioState.currentJunkStart / effectiveDuration).clamp(0.0, 1.0) * canvasWidth;
                      final junkEndX = (studioState.currentJunkEnd / effectiveDuration).clamp(0.0, 1.0) * canvasWidth;
                      final junkWidth = (junkEndX - junkStartX).clamp(0.0, canvasWidth);

                      return Listener(
                        onPointerSignal: (pointerSignal) {
                          if (pointerSignal is PointerScrollEvent) {
                            final isCmdOrCtrl = HardwareKeyboard.instance.isMetaPressed || HardwareKeyboard.instance.isControlPressed;
                            if (isCmdOrCtrl) {
                              final delta = pointerSignal.scrollDelta.dy;
                              _handleZoomChange(_zoomLevel - delta * 0.003);
                            } else {
                              final delta = pointerSignal.scrollDelta.dx != 0 ? pointerSignal.scrollDelta.dx : pointerSignal.scrollDelta.dy;
                              if (_scrollController.hasClients) {
                                final newOffset = (_scrollController.offset + delta).clamp(0.0, _scrollController.position.maxScrollExtent);
                                _scrollController.jumpTo(newOffset);
                              }
                            }
                          }
                        },
                        child: Scrollbar(
                          controller: _scrollController,
                          thumbVisibility: true,
                          trackVisibility: true,
                          child: SingleChildScrollView(
                            controller: _scrollController,
                            scrollDirection: Axis.horizontal,
                            child: SizedBox(
                              width: canvasWidth,
                              child: Stack(
                                children: [
                                  Column(
                                    children: [
                                      // 1. Time Ruler (Only Time Ruler accepts direct seek clicks & drags)
                                      GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onTapDown: (details) {
                                          final localX = details.localPosition.dx.clamp(0.0, canvasWidth);
                                          final sec = (localX / canvasWidth) * effectiveDuration;
                                          widget.onSeek(sec);
                                        },
                                        onHorizontalDragStart: (details) {
                                          final localX = details.localPosition.dx.clamp(0.0, canvasWidth);
                                          final sec = (localX / canvasWidth) * effectiveDuration;
                                          widget.onSeek(sec);
                                        },
                                        onHorizontalDragUpdate: (details) {
                                          final localX = details.localPosition.dx.clamp(0.0, canvasWidth);
                                          final sec = (localX / canvasWidth) * effectiveDuration;
                                          widget.onSeek(sec);
                                        },
                                        child: Container(
                                          height: 22,
                                          decoration: const BoxDecoration(
                                            color: Color(0xFF070D18),
                                            border: Border(bottom: BorderSide(color: Color(0xFF1E293B))),
                                          ),
                                          child: CustomPaint(
                                            size: Size(canvasWidth, 22),
                                            painter: _TimelineRulerPainter(
                                              duration: effectiveDuration,
                                              canvasWidth: canvasWidth,
                                            ),
                                          ),
                                        ),
                                      ),

                                        // Track 1: Video Track with Thumbnail Strip & Split/Merge Blocks
                                        Container(
                                          height: 48,
                                          decoration: const BoxDecoration(
                                            border: Border(bottom: BorderSide(color: Color(0xFF1E293B))),
                                          ),
                                          child: Stack(
                                            children: [
                                              // Case 1: Split segments render
                                              if (toolMode == StudioToolMode.split && studioState.splitSegments.isNotEmpty)
                                                ...studioState.splitSegments.map((seg) {
                                                  final startX = (seg.start / effectiveDuration).clamp(0.0, 1.0) * canvasWidth;
                                                  final endX = (seg.end / effectiveDuration).clamp(0.0, 1.0) * canvasWidth;
                                                  final segW = (endX - startX).clamp(10.0, canvasWidth);
                                                  return Positioned(
                                                    left: startX,
                                                    width: segW,
                                                    top: 2,
                                                    bottom: 2,
                                                    child: Container(
                                                      margin: const EdgeInsets.symmetric(horizontal: 1),
                                                      decoration: BoxDecoration(
                                                        color: const Color(0xFF8B5CF6).withOpacity(0.2),
                                                        borderRadius: BorderRadius.circular(4),
                                                        border: Border.all(color: const Color(0xFF8B5CF6).withOpacity(0.8), width: 1.2),
                                                      ),
                                                      clipBehavior: Clip.antiAlias,
                                                      child: Stack(
                                                        fit: StackFit.expand,
                                                        children: [
                                                          if (selectedVideo != null)
                                                            _buildThumbnailStrip(selectedVideo.fullPath, seg.end - seg.start, segW),
                                                          Container(
                                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                            alignment: Alignment.topLeft,
                                                            color: Colors.black38,
                                                            child: Text(
                                                              '🎬 ${seg.name}',
                                                              style: const TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.bold),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  );
                                                })
                                              // Case 2: Merge Playlist video blocks
                                              else if (toolMode == StudioToolMode.merge && studioState.mergePlaylist.isNotEmpty)
                                                ..._buildMergeTimelineBlocks(studioState, studioNotifier, effectiveDuration, canvasWidth)
                                              // Case 3: Single full video
                                              else
                                                Positioned.fill(
                                                  child: Container(
                                                    margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 1),
                                                    decoration: BoxDecoration(
                                                      color: const Color(0xFF8B5CF6).withOpacity(0.2),
                                                      borderRadius: BorderRadius.circular(4),
                                                      border: Border.all(color: const Color(0xFF8B5CF6).withOpacity(0.6)),
                                                    ),
                                                    clipBehavior: Clip.antiAlias,
                                                    child: Stack(
                                                      fit: StackFit.expand,
                                                      children: [
                                                        if (selectedVideo != null && !isMergeMode)
                                                          _buildThumbnailStrip(selectedVideo.fullPath, effectiveDuration, canvasWidth),
                                                        Container(
                                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                          alignment: Alignment.topLeft,
                                                          color: Colors.black26,
                                                          child: Text(
                                                            isMergeMode
                                                                ? '🥞 Danh sách ghép (${studioState.mergePlaylist.length} video)'
                                                                : '🎬 Video gốc (${TimeFormatUtils.formatShortTime(effectiveDuration)})',
                                                            style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.bold),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),

                                            // Red Junk Slice with drag move and left/right resize handles
                                            if (toolMode == StudioToolMode.cut && studioState.showCutBox && junkWidth > 0)
                                              Positioned(
                                                left: junkStartX,
                                                width: junkWidth,
                                                top: 2,
                                                bottom: 2,
                                                child: Stack(
                                                  clipBehavior: Clip.none,
                                                  children: [
                                                    // Main Body - Drag to Move
                                                    GestureDetector(
                                                      onHorizontalDragUpdate: (details) {
                                                        final dtSec = (details.delta.dx / canvasWidth) * effectiveDuration;
                                                        final curLen = studioState.currentJunkEnd - studioState.currentJunkStart;
                                                        final newStart = (studioState.currentJunkStart + dtSec).clamp(0.0, effectiveDuration - curLen);
                                                        final newEnd = newStart + curLen;
                                                        studioNotifier.setCutRange(newStart, newEnd);
                                                      },
                                                      child: Container(
                                                        decoration: BoxDecoration(
                                                          color: const Color(0xFFEF4444).withOpacity(0.35),
                                                          borderRadius: BorderRadius.circular(4),
                                                          border: Border.all(color: const Color(0xFFEF4444), width: 1.5),
                                                          boxShadow: [
                                                            BoxShadow(
                                                              color: const Color(0xFFEF4444).withOpacity(0.3),
                                                              blurRadius: 6,
                                                            ),
                                                          ],
                                                        ),
                                                        child: const Center(
                                                          child: Row(
                                                            mainAxisSize: MainAxisSize.min,
                                                            children: [
                                                              Icon(Icons.content_cut, size: 12, color: Colors.white),
                                                              SizedBox(width: 4),
                                                              Text(
                                                                'Đoạn rác',
                                                                style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                      ),
                                                    ),

                                                    // Left Handle - Resize Start
                                                    Positioned(
                                                      left: 0,
                                                      top: 0,
                                                      bottom: 0,
                                                      width: 8,
                                                      child: MouseRegion(
                                                        cursor: SystemMouseCursors.resizeLeftRight,
                                                        child: GestureDetector(
                                                          behavior: HitTestBehavior.opaque,
                                                          onHorizontalDragUpdate: (details) {
                                                            final dtSec = (details.delta.dx / canvasWidth) * effectiveDuration;
                                                            final newStart = (studioState.currentJunkStart + dtSec).clamp(0.0, studioState.currentJunkEnd - 0.2);
                                                            studioNotifier.setCutRange(newStart, studioState.currentJunkEnd);
                                                          },
                                                          child: Container(
                                                            decoration: const BoxDecoration(
                                                              color: Color(0xFFEF4444),
                                                              borderRadius: BorderRadius.horizontal(left: Radius.circular(3)),
                                                            ),
                                                            child: const Center(
                                                              child: Icon(Icons.drag_indicator, size: 8, color: Colors.white),
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                    ),

                                                    // Right Handle - Resize End
                                                    Positioned(
                                                      right: 0,
                                                      top: 0,
                                                      bottom: 0,
                                                      width: 8,
                                                      child: MouseRegion(
                                                        cursor: SystemMouseCursors.resizeLeftRight,
                                                        child: GestureDetector(
                                                          behavior: HitTestBehavior.opaque,
                                                          onHorizontalDragUpdate: (details) {
                                                            final dtSec = (details.delta.dx / canvasWidth) * effectiveDuration;
                                                            final newEnd = (studioState.currentJunkEnd + dtSec).clamp(studioState.currentJunkStart + 0.2, effectiveDuration);
                                                            studioNotifier.setCutRange(studioState.currentJunkStart, newEnd);
                                                          },
                                                          child: Container(
                                                            decoration: const BoxDecoration(
                                                              color: Color(0xFFEF4444),
                                                              borderRadius: BorderRadius.horizontal(right: Radius.circular(3)),
                                                            ),
                                                            child: const Center(
                                                              child: Icon(Icons.drag_indicator, size: 8, color: Colors.white),
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),

                                            // Split markers
                                            if (toolMode == StudioToolMode.split)
                                              ...studioState.splitSegments.map((seg) {
                                                final segX = (seg.start / effectiveDuration).clamp(0.0, 1.0) * canvasWidth;
                                                return Positioned(
                                                  left: segX,
                                                  top: 0,
                                                  bottom: 0,
                                                  child: Container(
                                                    width: 2,
                                                    color: const Color(0xFF38BDF8),
                                                  ),
                                                );
                                              }),
                                          ],
                                        ),
                                      ),

                                      if (isCompositeMode) ...[
                                        // Dynamic Overlay Tracks
                                        ...studioState.overlayTracks.map((track) {
                                          final clips = studioState.overlayClips.where((c) => c.trackId == track.id).toList();
                                          return Container(
                                            height: 36,
                                            decoration: const BoxDecoration(
                                              border: Border(bottom: BorderSide(color: Color(0xFF1E293B))),
                                            ),
                                            child: Stack(
                                              clipBehavior: Clip.none,
                                              children: clips.map((c) {
                                                final startX = (c.start / effectiveDuration).clamp(0.0, 1.0) * canvasWidth;
                                                final endX = (c.end / effectiveDuration).clamp(0.0, 1.0) * canvasWidth;
                                                final clipW = (endX - startX).clamp(12.0, canvasWidth - startX);
                                                final isSelected = studioState.selectedClipId == c.id;

                                                return _InteractiveTimelineClip(
                                                  key: ValueKey(c.id),
                                                  clipId: c.id,
                                                  startX: startX,
                                                  width: clipW,
                                                  trackHeight: 32,
                                                  color: const Color(0xFF0284C7),
                                                  accentColor: const Color(0xFF38BDF8),
                                                  title: '🖼️ ${c.name}',
                                                  isSelected: isSelected,
                                                  canvasWidth: canvasWidth,
                                                  effectiveDuration: effectiveDuration,
                                                  currentStart: c.start,
                                                  currentEnd: c.end,
                                                  onSelect: () => studioNotifier.selectClip(c.id),
                                                  onStartChanged: (newStart) => studioNotifier.moveOverlayClip(c.id, newStart, effectiveDuration),
                                                  onEndChanged: (newEnd) => studioNotifier.resizeOverlayClip(c.id, newEnd, effectiveDuration),
                                                  onDelete: () => studioNotifier.removeOverlayClip(c.id),
                                                );
                                              }).toList(),
                                            ),
                                          );
                                        }),

                                        // Music Track
                                        _buildAudioTrackContainer(
                                          clips: studioState.audioClips.where((a) => a.trackId == 'music').toList(),
                                          canvasWidth: canvasWidth,
                                          effectiveDuration: effectiveDuration,
                                          selectedClipId: studioState.selectedClipId,
                                          color: const Color(0xFF10B981),
                                          accentColor: const Color(0xFF34D399),
                                          icon: '🎵',
                                          onSelect: (id) => studioNotifier.selectClip(id),
                                          onMove: (id, start) => studioNotifier.moveAudioClip(id, start, effectiveDuration),
                                          onResize: (id, end) => studioNotifier.resizeAudioClip(id, end, effectiveDuration),
                                          onDelete: (id) => studioNotifier.removeAudioClip(id),
                                        ),

                                        // SFX Track
                                        _buildAudioTrackContainer(
                                          clips: studioState.audioClips.where((a) => a.trackId == 'sfx').toList(),
                                          canvasWidth: canvasWidth,
                                          effectiveDuration: effectiveDuration,
                                          selectedClipId: studioState.selectedClipId,
                                          color: const Color(0xFF2563EB),
                                          accentColor: const Color(0xFF60A5FA),
                                          icon: '🎤',
                                          onSelect: (id) => studioNotifier.selectClip(id),
                                          onMove: (id, start) => studioNotifier.moveAudioClip(id, start, effectiveDuration),
                                          onResize: (id, end) => studioNotifier.resizeAudioClip(id, end, effectiveDuration),
                                          onDelete: (id) => studioNotifier.removeAudioClip(id),
                                        ),

                                        // Subtitle Track
                                        Container(
                                          height: 34,
                                          decoration: const BoxDecoration(
                                            border: Border(bottom: BorderSide(color: Color(0xFF1E293B))),
                                          ),
                                          child: Stack(
                                            clipBehavior: Clip.none,
                                            children: studioState.subtitles.map((sub) {
                                              final startX = (sub.start / effectiveDuration).clamp(0.0, 1.0) * canvasWidth;
                                              final endX = (sub.end / effectiveDuration).clamp(0.0, 1.0) * canvasWidth;
                                              final subW = (endX - startX).clamp(12.0, canvasWidth - startX);
                                              final isSelected = studioState.selectedClipId == sub.id;

                                              return _InteractiveTimelineClip(
                                                key: ValueKey(sub.id),
                                                clipId: sub.id,
                                                startX: startX,
                                                width: subW,
                                                trackHeight: 30,
                                                color: const Color(0xFFCA8A04),
                                                accentColor: const Color(0xFFFACC15),
                                                title: sub.textTrans.isNotEmpty ? sub.textTrans : (sub.textOrig.isNotEmpty ? sub.textOrig : 'Phụ đề'),
                                                isSelected: isSelected,
                                                canvasWidth: canvasWidth,
                                                effectiveDuration: effectiveDuration,
                                                currentStart: sub.start,
                                                currentEnd: sub.end,
                                                onSelect: () => studioNotifier.selectClip(sub.id),
                                                onStartChanged: (newStart) => studioNotifier.moveSubtitleClip(sub.id, newStart, effectiveDuration),
                                                onEndChanged: (newEnd) => studioNotifier.resizeSubtitleClip(sub.id, newEnd, effectiveDuration),
                                                onDelete: () => studioNotifier.removeSubtitleClip(sub.id),
                                              );
                                            }).toList(),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),

                                  // Draggable Playhead Scrubber Handle & Vertical Line
                                  Positioned(
                                    left: (playheadX - 10).clamp(0.0, canvasWidth - 20),
                                    top: 0,
                                    bottom: 0,
                                    width: 20,
                                    child: MouseRegion(
                                      cursor: SystemMouseCursors.grab,
                                      child: GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onHorizontalDragUpdate: (details) {
                                          final newPlayheadX = (playheadX + details.delta.dx).clamp(0.0, canvasWidth);
                                          final sec = (newPlayheadX / canvasWidth) * effectiveDuration;
                                          widget.onSeek(sec);
                                        },
                                        child: Stack(
                                          alignment: Alignment.topCenter,
                                          children: [
                                            Container(
                                              width: 2,
                                              color: const Color(0xFFEF4444),
                                            ),
                                            Container(
                                              width: 12,
                                              height: 12,
                                              decoration: const BoxDecoration(
                                                color: Color(0xFFEF4444),
                                                shape: BoxShape.circle,
                                                boxShadow: [
                                                  BoxShadow(color: Colors.black45, blurRadius: 4),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
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

  Widget _buildThumbnailStrip(String videoPath, double durationSec, double clipWidthPx) {
    final notifier = ThumbnailService.instance.getStripNotifier(videoPath, durationSec, clipWidthPx);
    return ValueListenableBuilder<List<String?>>(
      valueListenable: notifier,
      builder: (context, thumbs, child) {
        if (thumbs.isEmpty) {
          return Container(color: Colors.black26);
        }
        return Row(
          children: thumbs.map((path) {
            return Expanded(
              child: (path != null && File(path).existsSync())
                  ? Image.file(
                      File(path),
                      fit: BoxFit.cover,
                      height: double.infinity,
                      errorBuilder: (ctx, err, stack) => const SizedBox.shrink(),
                    )
                  : Container(color: const Color(0xFF1E293B).withOpacity(0.5)),
            );
          }).toList(),
        );
      },
    );
  }

  List<Widget> _buildMergeTimelineBlocks(
    StudioSnapshot studioState,
    StudioStateNotifier studioNotifier,
    double effectiveDuration,
    double canvasWidth,
  ) {
    final playlist = studioState.mergePlaylist;
    final widgets = <Widget>[];
    double accumulatedSec = 0.0;
    final totalPlaylistDur = playlist.fold(0.0, (acc, item) => acc + (item.duration > 0 ? item.duration : 10.0));
    final calcTotalDur = totalPlaylistDur > 0 ? totalPlaylistDur : effectiveDuration;

    for (int i = 0; i < playlist.length; i++) {
      final item = playlist[i];
      final itemDur = item.duration > 0 ? item.duration : (calcTotalDur / playlist.length);
      final clipStartSec = accumulatedSec;
      final startX = (accumulatedSec / calcTotalDur).clamp(0.0, 1.0) * canvasWidth;
      final segW = ((itemDur / calcTotalDur).clamp(0.0, 1.0) * canvasWidth).clamp(28.0, canvasWidth);
      accumulatedSec += itemDur;

      final isSelected = studioState.selectedClipId == item.id;

      widgets.add(
        Positioned(
          left: startX,
          width: segW,
          top: 2,
          bottom: 2,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              studioNotifier.selectClip(item.id);
              widget.onSeek(clipStartSec);
            },
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 1.5),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFF10B981).withOpacity(0.35) : const Color(0xFF10B981).withOpacity(0.2),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: isSelected ? const Color(0xFFFACC15) : const Color(0xFF10B981).withOpacity(0.8),
                  width: isSelected ? 2.0 : 1.2,
                ),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: const Color(0xFFFACC15).withOpacity(0.4),
                          blurRadius: 6,
                          spreadRadius: 1,
                        )
                      ]
                    : null,
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _buildThumbnailStrip(item.fullPath, itemDur, segW),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    alignment: Alignment.topLeft,
                    color: Colors.black54,
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${i + 1}. ${item.name} (${TimeFormatUtils.formatShortTime(itemDur)})',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: isSelected ? const Color(0xFFFACC15) : Colors.white,
                              fontSize: 9.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        if (isSelected) ...[
                          if (i > 0)
                            InkWell(
                              onTap: () => studioNotifier.reorderMergeItem(i, i - 1),
                              child: Container(
                                padding: const EdgeInsets.all(2),
                                margin: const EdgeInsets.symmetric(horizontal: 1),
                                decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(2)),
                                child: const Icon(Icons.arrow_back, size: 10, color: Color(0xFF38BDF8)),
                              ),
                            ),
                          if (i < playlist.length - 1)
                            InkWell(
                              onTap: () => studioNotifier.reorderMergeItem(i, i + 1),
                              child: Container(
                                padding: const EdgeInsets.all(2),
                                margin: const EdgeInsets.symmetric(horizontal: 1),
                                decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(2)),
                                child: const Icon(Icons.arrow_forward, size: 10, color: Color(0xFF38BDF8)),
                              ),
                            ),
                          InkWell(
                            onTap: () => studioNotifier.removeMergeItem(item.id),
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              margin: const EdgeInsets.only(left: 2),
                              decoration: BoxDecoration(color: Colors.red.withOpacity(0.8), borderRadius: BorderRadius.circular(2)),
                              child: const Icon(Icons.close, size: 10, color: Colors.white),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return widgets;
  }

  Widget _buildAudioTrackContainer({
    required List<AudioClip> clips,
    required double canvasWidth,
    required double effectiveDuration,
    required String? selectedClipId,
    required Color color,
    required Color accentColor,
    required String icon,
    required ValueChanged<String> onSelect,
    required Function(String id, double newStart) onMove,
    required Function(String id, double newEnd) onResize,
    required ValueChanged<String> onDelete,
  }) {
    return Container(
      height: 34,
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF1E293B))),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: clips.map((a) {
          final startX = (a.start / effectiveDuration).clamp(0.0, 1.0) * canvasWidth;
          final endX = (a.end / effectiveDuration).clamp(0.0, 1.0) * canvasWidth;
          final clipW = (endX - startX).clamp(12.0, canvasWidth - startX);
          final isSelected = selectedClipId == a.id;

          return _InteractiveTimelineClip(
            key: ValueKey(a.id),
            clipId: a.id,
            startX: startX,
            width: clipW,
            trackHeight: 30,
            color: color,
            accentColor: accentColor,
            title: '$icon ${a.name}',
            isSelected: isSelected,
            canvasWidth: canvasWidth,
            effectiveDuration: effectiveDuration,
            currentStart: a.start,
            currentEnd: a.end,
            onSelect: () => onSelect(a.id),
            onStartChanged: (newStart) => onMove(a.id, newStart),
            onEndChanged: (newEnd) => onResize(a.id, newEnd),
            onDelete: () => onDelete(a.id),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildToolBtn({
    required IconData icon,
    required String label,
    required bool isSelected,
    required Color activeColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? activeColor.withOpacity(0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: isSelected ? Border.all(color: activeColor, width: 0.8) : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: isSelected ? activeColor : const Color(0xFF94A3B8)),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : const Color(0xFF94A3B8),
                fontSize: 10.5,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrackHeader({
    required double height,
    required String title,
    required IconData icon,
    required Color color,
    String? tag,
    bool isSelected = false,
    bool isVisible = true,
    bool isLocked = false,
    bool hasMute = false,
    bool isMuted = false,
    VoidCallback? onHeaderTap,
    VoidCallback? onTagTap,
    VoidCallback? onToggleVisible,
    VoidCallback? onToggleLock,
    VoidCallback? onToggleMute,
    VoidCallback? onDelete,
  }) {
    return InkWell(
      onTap: onHeaderTap,
      child: Container(
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.12) : Colors.transparent,
          border: Border(
            bottom: const BorderSide(color: Color(0xFF1E293B)),
            left: isSelected ? BorderSide(color: color, width: 3) : BorderSide.none,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
              ),
            ),
            if (tag != null) ...[
              InkWell(
                onTap: onTagTap,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(color: color.withOpacity(0.6), width: 0.8),
                  ),
                  child: Text(
                    tag,
                    style: TextStyle(color: color, fontSize: 8.5, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(width: 4),
            ],
            if (hasMute)
              InkWell(
                onTap: onToggleMute,
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Icon(
                    isMuted ? Icons.volume_off : Icons.volume_up,
                    size: 11,
                    color: isMuted ? const Color(0xFFEF4444) : const Color(0xFF94A3B8),
                  ),
                ),
              ),
            if (onToggleVisible != null)
              InkWell(
                onTap: onToggleVisible,
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Icon(
                    isVisible ? Icons.visibility : Icons.visibility_off,
                    size: 11,
                    color: isVisible ? const Color(0xFF94A3B8) : const Color(0xFFEF4444),
                  ),
                ),
              ),
            if (onToggleLock != null)
              InkWell(
                onTap: onToggleLock,
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Icon(
                    isLocked ? Icons.lock : Icons.lock_open,
                    size: 11,
                    color: isLocked ? const Color(0xFFF59E0B) : const Color(0xFF475569),
                  ),
                ),
              ),
            if (onDelete != null)
              InkWell(
                onTap: onDelete,
                child: const Padding(
                  padding: EdgeInsets.all(2),
                  child: Icon(Icons.delete_outline, size: 11, color: Color(0xFFEF4444)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _pickAndAddOverlayImage(BuildContext context, String trackId, double maxDuration) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['png', 'jpg', 'jpeg', 'webp'],
    );
    if (result != null && result.files.single.path != null) {
      final path = result.files.single.path!;
      final name = result.files.single.name;
      final start = widget.currentTime.clamp(0.0, maxDuration - 2.0);
      final end = (start + 5.0).clamp(start + 0.5, maxDuration);

      ref.read(studioStateProvider.notifier).addOverlayClip(
            OverlayClip(
              id: 'clip_ov_${DateTime.now().millisecondsSinceEpoch}',
              trackId: trackId,
              name: name,
              imagePath: path,
              start: start,
              end: end,
            ),
          );
    }
  }

  void _pickAndAddAudio(BuildContext context, String trackId, double maxDuration) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mp3', 'wav', 'aac', 'm4a', 'flac'],
    );
    if (result != null && result.files.single.path != null) {
      final path = result.files.single.path!;
      final name = result.files.single.name;
      final start = widget.currentTime.clamp(0.0, maxDuration - 2.0);
      final end = (start + 10.0).clamp(start + 0.5, maxDuration);

      ref.read(studioStateProvider.notifier).addAudioClip(
            AudioClip(
              id: 'clip_audio_${DateTime.now().millisecondsSinceEpoch}',
              trackId: trackId,
              name: name,
              fullPath: path,
              start: start,
              end: end,
            ),
          );
    }
  }

  void _addQuickSubtitle(double maxDuration) {
    final start = widget.currentTime.clamp(0.0, maxDuration - 2.0);
    final end = (start + 3.0).clamp(start + 0.5, maxDuration);

    ref.read(studioStateProvider.notifier).addSubtitleClip(
          SubtitleClip(
            id: 'sub_${DateTime.now().millisecondsSinceEpoch}',
            start: start,
            end: end,
            textOrig: 'Đoạn phụ đề mới',
            textTrans: 'Đoạn phụ đề dịch',
          ),
        );
  }
}

class _InteractiveTimelineClip extends StatefulWidget {
  final String clipId;
  final double startX;
  final double width;
  final double trackHeight;
  final Color color;
  final Color accentColor;
  final String title;
  final bool isSelected;
  final double canvasWidth;
  final double effectiveDuration;
  final double currentStart;
  final double currentEnd;
  final VoidCallback onSelect;
  final ValueChanged<double> onStartChanged;
  final ValueChanged<double> onEndChanged;
  final VoidCallback onDelete;

  const _InteractiveTimelineClip({
    super.key,
    required this.clipId,
    required this.startX,
    required this.width,
    required this.trackHeight,
    required this.color,
    required this.accentColor,
    required this.title,
    required this.isSelected,
    required this.canvasWidth,
    required this.effectiveDuration,
    required this.currentStart,
    required this.currentEnd,
    required this.onSelect,
    required this.onStartChanged,
    required this.onEndChanged,
    required this.onDelete,
  });

  @override
  State<_InteractiveTimelineClip> createState() => _InteractiveTimelineClipState();
}

class _InteractiveTimelineClipState extends State<_InteractiveTimelineClip> {
  double _dragAccumulator = 0;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: widget.startX,
      width: widget.width,
      top: 2,
      height: widget.trackHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Main Body with Drag to Move
          GestureDetector(
            onTap: widget.onSelect,
            onHorizontalDragStart: (_) {
              widget.onSelect();
              _dragAccumulator = 0;
            },
            onHorizontalDragUpdate: (details) {
              _dragAccumulator += details.delta.dx;
              final dtSec = (_dragAccumulator / widget.canvasWidth) * widget.effectiveDuration;
              if (dtSec.abs() >= 0.05) {
                widget.onStartChanged(widget.currentStart + dtSec);
                _dragAccumulator = 0;
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              decoration: BoxDecoration(
                color: widget.color.withOpacity(widget.isSelected ? 0.65 : 0.4),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: widget.isSelected ? Colors.white : widget.accentColor,
                  width: widget.isSelected ? 2.0 : 1.0,
                ),
                boxShadow: widget.isSelected
                    ? [
                        BoxShadow(
                          color: widget.accentColor.withOpacity(0.6),
                          blurRadius: 8,
                          spreadRadius: 1,
                        )
                      ]
                    : null,
              ),
              alignment: Alignment.centerLeft,
              child: Text(
                widget.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.w600),
              ),
            ),
          ),

          // Right Handle for Resizing
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            width: 10,
            child: MouseRegion(
              cursor: SystemMouseCursors.resizeLeftRight,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragStart: (_) {
                  widget.onSelect();
                  _dragAccumulator = 0;
                },
                onHorizontalDragUpdate: (details) {
                  _dragAccumulator += details.delta.dx;
                  final dtSec = (_dragAccumulator / widget.canvasWidth) * widget.effectiveDuration;
                  if (dtSec.abs() >= 0.05) {
                    widget.onEndChanged(widget.currentEnd + dtSec);
                    _dragAccumulator = 0;
                  }
                },
                child: Container(
                  decoration: BoxDecoration(
                    color: widget.isSelected ? Colors.white : widget.accentColor.withOpacity(0.8),
                    borderRadius: const BorderRadius.horizontal(right: Radius.circular(3)),
                  ),
                  child: const Center(
                    child: Icon(Icons.drag_indicator, size: 8, color: Colors.black87),
                  ),
                ),
              ),
            ),
          ),

          // Delete Button when selected
          if (widget.isSelected)
            Positioned(
              top: -8,
              right: -6,
              child: GestureDetector(
                onTap: widget.onDelete,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: const BoxDecoration(
                    color: Color(0xFFEF4444),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close, size: 10, color: Colors.white),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TimelineRulerPainter extends CustomPainter {
  final double duration;
  final double canvasWidth;

  _TimelineRulerPainter({required this.duration, required this.canvasWidth});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF334155)
      ..strokeWidth = 1;

    const textStyle = TextStyle(
      color: Color(0xFF64748B),
      fontSize: 8.5,
      fontFamily: 'monospace',
    );

    const stepSec = 10; // 10s tick interval
    final totalTicks = (duration / stepSec).ceil();

    for (int i = 0; i <= totalTicks; i++) {
      final sec = i * stepSec;
      if (sec > duration) break;
      final x = (sec / duration) * canvasWidth;

      canvas.drawLine(Offset(x, size.height - 8), Offset(x, size.height), paint);

      final textSpan = TextSpan(text: TimeFormatUtils.formatShortTime(sec.toDouble()), style: textStyle);
      final textPainter = TextPainter(text: textSpan, textDirection: TextDirection.ltr);
      textPainter.layout();
      textPainter.paint(canvas, Offset(x + 2, 2));
    }
  }

  @override
  bool shouldRepaint(covariant _TimelineRulerPainter oldDelegate) {
    return oldDelegate.duration != duration || oldDelegate.canvasWidth != canvasWidth;
  }
}
