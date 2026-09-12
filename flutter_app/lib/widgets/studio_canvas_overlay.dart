import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/studio_state_notifier.dart';
import '../models/studio_state.dart';
import 'studio_visual_gizmo_overlay.dart';

class StudioCanvasOverlay extends ConsumerStatefulWidget {
  final double currentSeconds;
  final double aspectRatio;

  static Size lastCanvasSize = const Size(640, 360);

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
    final activeGizmoLayer = ref.watch(activeStudioGizmoLayerProvider);

    // Filter overlay clips active at current time
    final activeClips = studioState.overlayClips.where((c) {
      return widget.currentSeconds >= c.start && widget.currentSeconds <= c.end;
    }).toList();

    // Find active subtitle at current time, fallback to first sub or sample dummy when editing style
    final isEditingSub = activeGizmoLayer == StudioGizmoLayer.primarySub ||
        activeGizmoLayer == StudioGizmoLayer.secondarySub;

    final activeSub = studioState.subtitles.where((s) {
      return widget.currentSeconds >= s.start && widget.currentSeconds <= s.end;
    }).firstOrNull ??
        (_isSubSelected ? studioState.subtitles.firstOrNull : null) ??
        (isEditingSub
            ? SubtitleClip(
                id: 'sample_preview',
                start: 0.0,
                end: 9999.0,
                textOrig: 'Sample Secondary Subtitle Preview',
                textTrans: 'Phụ đề tiếng Việt mẫu trực quan',
                textSecondary: 'Sample Secondary Subtitle Preview',
              )
            : null);

    return LayoutBuilder(
      builder: (context, constraints) {
        final canvasW = constraints.maxWidth;
        final canvasH = constraints.maxHeight;
        StudioCanvasOverlay.lastCanvasSize = Size(canvasW, canvasH);

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

            // 1.5. Realtime Inpaint Box Preview
            if (studioState.inpaintConfig.enabled)
              _buildInpaintGizmo(context, studioState.inpaintConfig, canvasW, canvasH, studioNotifier),


            // 2. Realtime Subtitle Preview & Interactive Drag/Resize
            if (activeSub != null) ...[
              _buildSubtitleGizmo(context, activeSub, studioState.subStyle, canvasW, canvasH, studioNotifier),
              if (studioState.subStyle.separateSecPos &&
                  studioState.subStyle.showSubSub &&
                  activeSub.displayText.isNotEmpty)
                _buildIndependentSecSubtitleGizmo(context, activeSub, studioState.subStyle, canvasW, canvasH, studioNotifier),
            ],

            // 3. Unified WYSIWYG Gizmo Handles & Floating Toolbar
            StudioVisualGizmoOverlay(
              canvasSize: Size(canvasW, canvasH),
              studioState: studioState,
              studioNotifier: studioNotifier,
            ),
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

  Widget _buildInpaintGizmo(
    BuildContext context,
    StudioInpaintConfig inpaint,
    double canvasW,
    double canvasH,
    StudioStateNotifier studioNotifier,
  ) {
    if (!inpaint.enabled || inpaint.region.length < 4) return const SizedBox.shrink();
    final ymin = inpaint.region[0].clamp(0.0, 1.0);
    final xmin = inpaint.region[1].clamp(0.0, 1.0);
    final ymax = inpaint.region[2].clamp(ymin + 0.01, 1.0);
    final xmax = inpaint.region[3].clamp(xmin + 0.01, 1.0);

    final leftPx = xmin * canvasW;
    final topPx = ymin * canvasH;
    final widthPx = (xmax - xmin) * canvasW;
    final heightPx = (ymax - ymin) * canvasH;

    final isBoxColor = inpaint.engine == 'box_color';
    final boxColor = _parseColor(inpaint.color).withOpacity(inpaint.opacity.clamp(0.0, 1.0));
    final borderColor = isBoxColor && inpaint.borderWidth > 0
        ? _parseColor(inpaint.borderColor)
        : const Color(0xFFEF4444).withOpacity(0.85);
    final borderWidth = isBoxColor && inpaint.borderWidth > 0
        ? inpaint.borderWidth.toDouble()
        : 1.5;
    final borderRadius = isBoxColor
        ? inpaint.borderRadius.toDouble()
        : 4.0;

    return Positioned(
      left: leftPx,
      top: topPx,
      width: widthPx,
      height: heightPx,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          ref.read(activeStudioGizmoLayerProvider.notifier).state = StudioGizmoLayer.inpaint;
        },
        child: Container(
          decoration: BoxDecoration(
            color: inpaint.engine == 'ffmpeg_blur' || inpaint.mode == 'blur'
                ? Colors.black.withOpacity(0.55)
                : boxColor,
            border: Border.all(color: borderColor, width: borderWidth),
            borderRadius: BorderRadius.circular(borderRadius),
          ),
          child: Align(
            alignment: Alignment.topLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444),
                borderRadius: BorderRadius.circular(2),
              ),
              child: const Text('🧹 Inpaint Box', style: TextStyle(color: Colors.white, fontSize: 8.5, fontWeight: FontWeight.bold)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSubtitleGizmo(
    BuildContext context,
    SubtitleClip activeSub,
    SubStyle subStyle,
    double canvasW,
    double canvasH,
    StudioStateNotifier studioNotifier,
  ) {
    final double subW;
    final double leftPx;
    final double topYPx;

    if (subStyle.subtitleRegion != null) {
      final effR = subStyle.effectiveSubtitleRegion;
      topYPx = effR[0] * canvasH;
      leftPx = effR[1] * canvasW;
      subW = ((effR[3] - effR[1]) * canvasW).clamp(60.0, canvasW);
    } else {
      subW = ((subStyle.boxWidthPct / 100.0) * canvasW).clamp(60.0, canvasW);
      final centerXPx = (subStyle.posX / 100.0) * canvasW;
      topYPx = (subStyle.posY / 100.0) * canvasH;
      leftPx = (centerXPx - subW / 2).clamp(0.0, canvasW - subW);
    }

    final mainTextColor = _parseColor(subStyle.fontColor, fallback: const Color(0xFFFACC15));
    final subTextColor = _parseColor(subStyle.origColor, fallback: Colors.white);
    final boxColor = subStyle.showSubBox
        ? _parseColor(subStyle.boxBgColor).withOpacity(subStyle.boxOpacity.clamp(0.0, 1.0))
        : Colors.transparent;
    final borderDecoration = subStyle.boxBorderWidth > 0
        ? Border.all(color: _parseColor(subStyle.boxBorderColor), width: subStyle.boxBorderWidth)
        : null;
    final boxPadding = EdgeInsets.symmetric(horizontal: subStyle.boxPaddingX, vertical: subStyle.boxPaddingY);
    final boxRadius = BorderRadius.circular(subStyle.boxBorderRadius);

    final showMain = subStyle.showMainSub && activeSub.textTrans.isNotEmpty;
    final showSec = (!subStyle.separateSecPos) && subStyle.showSubSub && activeSub.textOrig.isNotEmpty;

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
              ref.read(activeStudioGizmoLayerProvider.notifier).state = StudioGizmoLayer.primarySub;
            },
            onPanUpdate: (details) {
              if (subStyle.subtitleRegion != null) {
                final dyNorm = details.delta.dy / canvasH;
                final dxNorm = details.delta.dx / canvasW;
                final r = subStyle.subtitleRegion!;
                final h = r[2] - r[0];
                final w = r[3] - r[1];
                final newTop = (r[0] + dyNorm).clamp(0.0, 1.0 - h);
                final newLeft = (r[1] + dxNorm).clamp(0.0, 1.0 - w);
                studioNotifier.updateSubtitleRegion([newTop, newLeft, newTop + h, newLeft + w]);
              } else {
                final dxPct = (details.delta.dx / canvasW) * 100.0;
                final dyPct = (details.delta.dy / canvasH) * 100.0;
                studioNotifier.updateSubStyle(
                  subStyle.copyWith(
                    posX: (subStyle.posX + dxPct).clamp(5.0, 95.0),
                    posY: (subStyle.posY + dyPct).clamp(5.0, 95.0),
                  ),
                );
              }
            },
            child: (subStyle.boxSplit && showMain && showSec)
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Box 1: Sub chính
                      Container(
                        width: subW,
                        padding: boxPadding,
                        decoration: BoxDecoration(
                          color: boxColor,
                          borderRadius: boxRadius,
                          border: borderDecoration,
                        ),
                        child: Text(
                          activeSub.textTrans,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: subStyle.fontFamily,
                            fontSize: subStyle.fontSize.toDouble(),
                            height: 1.25,
                            fontWeight: subStyle.isBold ? FontWeight.bold : FontWeight.normal,
                            fontStyle: subStyle.isItalic ? FontStyle.italic : FontStyle.normal,
                            color: mainTextColor,
                            shadows: subStyle.hasDropShadow
                                ? const [Shadow(color: Colors.black, blurRadius: 4, offset: Offset(1, 1))]
                                : null,
                          ),
                        ),
                      ),
                      SizedBox(height: subStyle.boxGap),
                      // Box 2: Sub phụ
                      Container(
                        width: subW,
                        padding: boxPadding,
                        decoration: BoxDecoration(
                          color: boxColor,
                          borderRadius: boxRadius,
                          border: borderDecoration,
                        ),
                        child: Text(
                          activeSub.textOrig,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: subStyle.fontFamily,
                            fontSize: (subStyle.fontSize - 4).clamp(10.0, 60.0).toDouble(),
                            height: 1.25,
                            fontWeight: FontWeight.w500,
                            color: subTextColor.withOpacity(0.9),
                            shadows: subStyle.hasDropShadow
                                ? const [Shadow(color: Colors.black, blurRadius: 4, offset: Offset(1, 1))]
                                : null,
                          ),
                        ),
                      ),
                    ],
                  )
                : Container(
                    padding: boxPadding,
                    decoration: BoxDecoration(
                      color: boxColor,
                      borderRadius: boxRadius,
                      border: borderDecoration,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (showMain)
                          Text(
                            activeSub.textTrans,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontFamily: subStyle.fontFamily,
                              fontSize: subStyle.fontSize.toDouble(),
                              height: 1.25,
                              fontWeight: subStyle.isBold ? FontWeight.bold : FontWeight.normal,
                              fontStyle: subStyle.isItalic ? FontStyle.italic : FontStyle.normal,
                              color: mainTextColor,
                              shadows: subStyle.hasDropShadow
                                  ? const [Shadow(color: Colors.black, blurRadius: 4, offset: Offset(1, 1))]
                                  : null,
                            ),
                          ),
                        if (showMain && showSec)
                          SizedBox(height: subStyle.boxGap),
                        if (showSec)
                          Text(
                            activeSub.textOrig,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontFamily: subStyle.fontFamily,
                              fontSize: (subStyle.fontSize - 4).clamp(10.0, 60.0).toDouble(),
                              height: 1.25,
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
        ],
      ),
    );
  }

  Widget _buildIndependentSecSubtitleGizmo(
    BuildContext context,
    SubtitleClip activeSub,
    SubStyle subStyle,
    double canvasW,
    double canvasH,
    StudioStateNotifier studioNotifier,
  ) {
    final double subW;
    final double leftPx;
    final double topYPx;

    if (subStyle.subtitleSecondaryRegion != null) {
      final effSecR = subStyle.effectiveSubtitleSecondaryRegion;
      topYPx = effSecR[0] * canvasH;
      leftPx = effSecR[1] * canvasW;
      subW = ((effSecR[3] - effSecR[1]) * canvasW).clamp(60.0, canvasW);
    } else {
      subW = ((subStyle.secBoxWidthPct / 100.0) * canvasW).clamp(60.0, canvasW);
      final centerXPx = (subStyle.secPosX / 100.0) * canvasW;
      topYPx = (subStyle.secPosY / 100.0) * canvasH;
      leftPx = (centerXPx - subW / 2).clamp(0.0, canvasW - subW);
    }

    final subTextColor = _parseColor(subStyle.origColor, fallback: Colors.white);
    final boxColor = subStyle.showSubBox
        ? _parseColor(subStyle.boxBgColor).withOpacity(subStyle.boxOpacity.clamp(0.0, 1.0))
        : Colors.transparent;
    final boxPadding = EdgeInsets.symmetric(horizontal: subStyle.boxPaddingX, vertical: subStyle.boxPaddingY);
    final boxRadius = BorderRadius.circular(subStyle.boxBorderRadius);
    final borderDecoration = subStyle.boxBorderWidth > 0
        ? Border.all(color: _parseColor(subStyle.boxBorderColor), width: subStyle.boxBorderWidth)
        : null;

    return Positioned(
      left: leftPx,
      top: topYPx,
      width: subW,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          ref.read(activeStudioGizmoLayerProvider.notifier).state = StudioGizmoLayer.secondarySub;
        },
        onPanUpdate: (details) {
          if (subStyle.subtitleSecondaryRegion != null) {
            final dyNorm = details.delta.dy / canvasH;
            final dxNorm = details.delta.dx / canvasW;
            final r = subStyle.subtitleSecondaryRegion!;
            final h = r[2] - r[0];
            final w = r[3] - r[1];
            final newTop = (r[0] + dyNorm).clamp(0.0, 1.0 - h);
            final newLeft = (r[1] + dxNorm).clamp(0.0, 1.0 - w);
            studioNotifier.updateSubtitleSecondaryRegion([newTop, newLeft, newTop + h, newLeft + w]);
          } else {
            final dxPct = (details.delta.dx / canvasW) * 100.0;
            final dyPct = (details.delta.dy / canvasH) * 100.0;
            studioNotifier.updateSubStyle(
              subStyle.copyWith(
                secPosX: (subStyle.secPosX + dxPct).clamp(5.0, 95.0),
                secPosY: (subStyle.secPosY + dyPct).clamp(5.0, 95.0),
              ),
            );
          }
        },
        child: Container(
          padding: boxPadding,
          decoration: BoxDecoration(
            color: boxColor,
            borderRadius: boxRadius,
            border: borderDecoration,
          ),
          child: Text(
            activeSub.textOrig,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: subStyle.fontFamily,
              fontSize: (subStyle.fontSize - 4).clamp(10.0, 60.0).toDouble(),
              height: 1.25,
              fontWeight: FontWeight.w500,
              color: subTextColor.withOpacity(0.9),
              shadows: subStyle.hasDropShadow
                  ? const [Shadow(color: Colors.black, blurRadius: 4, offset: Offset(1, 1))]
                  : null,
            ),
          ),
        ),
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
