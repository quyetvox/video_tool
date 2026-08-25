import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/studio_state_notifier.dart';
import '../models/studio_state.dart';

class StudioCanvasOverlay extends ConsumerStatefulWidget {
  final double currentSeconds;
  final double aspectRatio;

  const StudioCanvasOverlay({
    super.key,
    required this.currentSeconds,
    this.aspectRatio = 16 / 9,
  });

  @override
  ConsumerState<StudioCanvasOverlay> createState() => _StudioCanvasOverlayState();
}

class _StudioCanvasOverlayState extends ConsumerState<StudioCanvasOverlay> {
  bool _isSubSelected = false;

  @override
  Widget build(BuildContext context) {
    final toolMode = ref.watch(studioToolModeProvider);
    // Only render multi-track overlay graphics and subtitles in composite mode
    if (toolMode != StudioToolMode.composite) {
      return const SizedBox.shrink();
    }

    final studioState = ref.watch(studioStateProvider);
    final studioNotifier = ref.read(studioStateProvider.notifier);

    // Filter overlay clips active at current time
    final activeClips = studioState.overlayClips.where((c) {
      return widget.currentSeconds >= c.start && widget.currentSeconds <= c.end;
    }).toList();

    // Find active subtitle at current time, fallback to first sub if user selected/wants to edit
    final activeSub = studioState.subtitles.where((s) {
      return widget.currentSeconds >= s.start && widget.currentSeconds <= s.end;
    }).firstOrNull ?? (_isSubSelected ? studioState.subtitles.firstOrNull : null);

    return LayoutBuilder(
      builder: (context, constraints) {
        final canvasW = constraints.maxWidth;
        final canvasH = constraints.maxHeight;

        return Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.none,
          children: [
            // 1. Render Overlay Clips
            ...activeClips.map((clip) {
              final isSelected = studioState.selectedClipId == clip.id;
              final leftPx = (clip.x / 100.0) * canvasW;
              final topPx = (clip.y / 100.0) * canvasH;
              final widthPx = ((clip.width / 100.0) * canvasW).clamp(24.0, canvasW);
              final heightPx = ((clip.height / 100.0) * canvasH).clamp(24.0, canvasH);

              return Positioned(
                left: leftPx,
                top: topPx,
                width: widthPx,
                height: heightPx,
                child: Stack(
                  clipBehavior: Clip.none,
                  fit: StackFit.expand,
                  children: [
                    // Body - Move Drag
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        setState(() => _isSubSelected = false);
                        studioNotifier.selectClip(clip.id);
                      },
                      onPanUpdate: (details) {
                        final dxPct = (details.delta.dx / canvasW) * 100.0;
                        final dyPct = (details.delta.dy / canvasH) * 100.0;
                        studioNotifier.updateOverlayClipGeometry(
                          clip.id,
                          x: (clip.x + dxPct).clamp(0.0, 95.0),
                          y: (clip.y + dyPct).clamp(0.0, 95.0),
                        );
                      },
                      child: Opacity(
                        opacity: clip.opacity,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(clip.borderRadius),
                          child: File(clip.imagePath).existsSync()
                              ? Image.file(
                                  File(clip.imagePath),
                                  fit: BoxFit.fill,
                                  errorBuilder: (ctx, err, stack) => _buildPlaceholder(),
                                )
                              : _buildPlaceholder(),
                        ),
                      ),
                    ),

                    // Selection Border
                    if (isSelected)
                      IgnorePointer(
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: const Color(0xFF38BDF8), width: 1.8),
                            borderRadius: BorderRadius.circular(clip.borderRadius),
                          ),
                        ),
                      ),

                    // 4 Corner Resize Handles (Independent Hit Targets)
                    if (isSelected) ...[
                      // Top-Left Handle
                      _buildHandle(
                        left: -6,
                        top: -6,
                        cursor: SystemMouseCursors.resizeUpLeft,
                        onDrag: (delta) {
                          final dxPct = (delta.dx / canvasW) * 100.0;
                          final dyPct = (delta.dy / canvasH) * 100.0;
                          final newX = (clip.x + dxPct).clamp(0.0, clip.x + clip.width - 5.0);
                          final newY = (clip.y + dyPct).clamp(0.0, clip.y + clip.height - 5.0);
                          final newW = (clip.width - (newX - clip.x)).clamp(5.0, 100.0);
                          final newH = (clip.height - (newY - clip.y)).clamp(5.0, 100.0);
                          studioNotifier.updateOverlayClipGeometry(clip.id, x: newX, y: newY, width: newW, height: newH);
                        },
                      ),

                      // Top-Right Handle
                      _buildHandle(
                        right: -6,
                        top: -6,
                        cursor: SystemMouseCursors.resizeUpRight,
                        onDrag: (delta) {
                          final dxPct = (delta.dx / canvasW) * 100.0;
                          final dyPct = (delta.dy / canvasH) * 100.0;
                          final newY = (clip.y + dyPct).clamp(0.0, clip.y + clip.height - 5.0);
                          final newW = (clip.width + dxPct).clamp(5.0, 100.0);
                          final newH = (clip.height - (newY - clip.y)).clamp(5.0, 100.0);
                          studioNotifier.updateOverlayClipGeometry(clip.id, y: newY, width: newW, height: newH);
                        },
                      ),

                      // Bottom-Left Handle
                      _buildHandle(
                        left: -6,
                        bottom: -6,
                        cursor: SystemMouseCursors.resizeDownLeft,
                        onDrag: (delta) {
                          final dxPct = (delta.dx / canvasW) * 100.0;
                          final dyPct = (delta.dy / canvasH) * 100.0;
                          final newX = (clip.x + dxPct).clamp(0.0, clip.x + clip.width - 5.0);
                          final newW = (clip.width - (newX - clip.x)).clamp(5.0, 100.0);
                          final newH = (clip.height + dyPct).clamp(5.0, 100.0);
                          studioNotifier.updateOverlayClipGeometry(clip.id, x: newX, width: newW, height: newH);
                        },
                      ),

                      // Bottom-Right Handle
                      _buildHandle(
                        right: -6,
                        bottom: -6,
                        cursor: SystemMouseCursors.resizeDownRight,
                        onDrag: (delta) {
                          final dxPct = (delta.dx / canvasW) * 100.0;
                          final dyPct = (delta.dy / canvasH) * 100.0;
                          final newW = (clip.width + dxPct).clamp(5.0, 100.0);
                          final newH = (clip.height + dyPct).clamp(5.0, 100.0);
                          studioNotifier.updateOverlayClipGeometry(clip.id, width: newW, height: newH);
                        },
                      ),
                    ],
                  ],
                ),
              );
            }),

            // 2. Realtime Subtitle Preview & Interactive Drag/Resize
            if (activeSub != null) _buildSubtitleGizmo(context, activeSub, studioState.subStyle, canvasW, canvasH, studioNotifier),
          ],
        );
      },
    );
  }

  Color _parseColor(String hex, {Color fallback = Colors.white}) {
    try {
      var str = hex.replaceAll('#', '').replaceAll('rgba(', '').replaceAll(')', '').trim();
      if (str.startsWith('0x')) str = str.substring(2);
      if (str.length == 6) {
        return Color(int.parse('FF$str', radix: 16));
      } else if (str.length == 8) {
        return Color(int.parse(str, radix: 16));
      }
    } catch (_) {}
    return fallback;
  }

  Widget _buildSubtitleGizmo(
    BuildContext context,
    SubtitleClip activeSub,
    SubStyle subStyle,
    double canvasW,
    double canvasH,
    StudioStateNotifier studioNotifier,
  ) {
    final subW = ((subStyle.boxWidthPct / 100.0) * canvasW).clamp(60.0, canvasW);
    final centerXPx = (subStyle.posX / 100.0) * canvasW;
    final topYPx = (subStyle.posY / 100.0) * canvasH;
    final leftPx = (centerXPx - subW / 2).clamp(0.0, canvasW - subW);

    final mainTextColor = _parseColor(subStyle.fontColor, fallback: const Color(0xFFFACC15));
    final subTextColor = _parseColor(subStyle.origColor, fallback: Colors.white);

    return Positioned(
      left: leftPx,
      top: topYPx,
      width: subW,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Subtitle Body - Drag to Move
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              setState(() => _isSubSelected = true);
              studioNotifier.selectClip(activeSub.id);
            },
            onPanUpdate: (details) {
              final dxPct = (details.delta.dx / canvasW) * 100.0;
              final dyPct = (details.delta.dy / canvasH) * 100.0;
              studioNotifier.updateSubStyle(
                subStyle.copyWith(
                  posX: (subStyle.posX + dxPct).clamp(5.0, 95.0),
                  posY: (subStyle.posY + dyPct).clamp(5.0, 95.0),
                ),
              );
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: subStyle.showSubBox ? Colors.black.withOpacity(0.75) : Colors.transparent,
                borderRadius: BorderRadius.circular(4),
                border: _isSubSelected
                    ? Border.all(color: const Color(0xFFFACC15), width: 1.5)
                    : (subStyle.showSubBox ? null : Border.all(color: Colors.transparent)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (subStyle.showMainSub && activeSub.textTrans.isNotEmpty)
                    Text(
                      activeSub.textTrans,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: subStyle.fontFamily,
                        fontSize: subStyle.fontSize.toDouble(),
                        fontWeight: subStyle.isBold ? FontWeight.bold : FontWeight.normal,
                        fontStyle: subStyle.isItalic ? FontStyle.italic : FontStyle.normal,
                        color: mainTextColor,
                        shadows: subStyle.hasDropShadow
                            ? const [Shadow(color: Colors.black, blurRadius: 4, offset: Offset(1, 1))]
                            : null,
                      ),
                    ),
                  if (subStyle.showMainSub && subStyle.showSubSub && activeSub.textOrig.isNotEmpty && activeSub.textTrans.isNotEmpty)
                    const SizedBox(height: 2),
                  if (subStyle.showSubSub && activeSub.textOrig.isNotEmpty)
                    Text(
                      activeSub.textOrig,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: subStyle.fontFamily,
                        fontSize: (subStyle.fontSize - 4).clamp(10.0, 60.0).toDouble(),
                        fontWeight: FontWeight.w500,
                        color: subTextColor.withOpacity(0.9),
                        shadows: subStyle.hasDropShadow
                            ? const [Shadow(color: Colors.black, blurRadius: 4, offset: Offset(1, 1))]
                            : null,
                      ),
                    ),
                ],
              ),
            ),
          ),

          // Subtitle Left & Right Resize Width Handles
          if (_isSubSelected) ...[
            // Left Handle
            _buildHandle(
              left: -5,
              top: 10,
              cursor: SystemMouseCursors.resizeLeftRight,
              color: const Color(0xFFFACC15),
              onDrag: (delta) {
                final dWidthPct = (-delta.dx * 2 / canvasW) * 100.0;
                studioNotifier.updateSubStyle(
                  subStyle.copyWith(
                    boxWidthPct: (subStyle.boxWidthPct + dWidthPct).clamp(20.0, 100.0),
                  ),
                );
              },
            ),

            // Right Handle
            _buildHandle(
              right: -5,
              top: 10,
              cursor: SystemMouseCursors.resizeLeftRight,
              color: const Color(0xFFFACC15),
              onDrag: (delta) {
                final dWidthPct = (delta.dx * 2 / canvasW) * 100.0;
                studioNotifier.updateSubStyle(
                  subStyle.copyWith(
                    boxWidthPct: (subStyle.boxWidthPct + dWidthPct).clamp(20.0, 100.0),
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHandle({
    double? left,
    double? top,
    double? right,
    double? bottom,
    required MouseCursor cursor,
    required ValueChanged<Offset> onDrag,
    Color color = const Color(0xFF38BDF8),
  }) {
    return Positioned(
      left: left,
      top: top,
      right: right,
      bottom: bottom,
      child: MouseRegion(
        cursor: cursor,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanUpdate: (details) => onDrag(details.delta),
          child: Container(
            width: 13,
            height: 13,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 1.5),
              boxShadow: const [
                BoxShadow(color: Colors.black45, blurRadius: 4),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      color: const Color(0xFF0284C7).withOpacity(0.5),
      child: const Center(child: Icon(Icons.image, color: Colors.white, size: 18)),
    );
  }
}
