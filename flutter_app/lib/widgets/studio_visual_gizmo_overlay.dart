import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/providers.dart';
import '../core/studio_state_notifier.dart';
import '../models/studio_state.dart';

enum _StudioHandleType {
  none,
  move,
  topLeft,
  top,
  topRight,
  right,
  bottomRight,
  bottom,
  bottomLeft,
  left,
}

/// Interactive WYSIWYG Gizmo Overlay for Studio Canvas.
/// Provides 8-handle direct resizing, moving, and draggable floating toolbar
/// for Inpaint Box, Primary Subtitle, Secondary Subtitle, and Watermark Logo.
class StudioVisualGizmoOverlay extends ConsumerStatefulWidget {
  final Size canvasSize;
  final StudioSnapshot studioState;
  final StudioStateNotifier studioNotifier;

  const StudioVisualGizmoOverlay({
    super.key,
    required this.canvasSize,
    required this.studioState,
    required this.studioNotifier,
  });

  @override
  ConsumerState<StudioVisualGizmoOverlay> createState() =>
      _StudioVisualGizmoOverlayState();
}

class _StudioVisualGizmoOverlayState
    extends ConsumerState<StudioVisualGizmoOverlay> {
  _StudioHandleType _activeHandle = _StudioHandleType.none;
  Offset _dragStartLocal = Offset.zero;
  List<double> _dragStartRegion = [0, 0, 0, 0];
  final GlobalKey _canvasKey = GlobalKey();

  Color _layerColor(StudioGizmoLayer layer) {
    switch (layer) {
      case StudioGizmoLayer.inpaint:
        return const Color(0xFFEF4444); // Red
      case StudioGizmoLayer.primarySub:
        return const Color(0xFFFACC15); // Amber / Yellow
      case StudioGizmoLayer.secondarySub:
        return const Color(0xFF38BDF8); // Cyan / Sky
      case StudioGizmoLayer.watermark:
        return const Color(0xFF22C55E); // Green
      case StudioGizmoLayer.none:
        return Colors.white;
    }
  }

  List<double> _getLayerRegion(StudioGizmoLayer layer) {
    switch (layer) {
      case StudioGizmoLayer.inpaint:
        final r = widget.studioState.inpaintConfig.region;
        return r.length == 4 ? r : [0.72, 0.05, 0.88, 0.95];
      case StudioGizmoLayer.primarySub:
        return widget.studioState.subStyle.effectiveSubtitleRegion;
      case StudioGizmoLayer.secondarySub:
        return widget.studioState.subStyle.effectiveSubtitleSecondaryRegion;
      case StudioGizmoLayer.watermark:
        final r = widget.studioState.inpaintConfig.watermarkRegion;
        return r.length == 4 ? r : [0.02, 0.85, 0.05, 0.95];
      case StudioGizmoLayer.none:
        return [0, 0, 0, 0];
    }
  }

  void _updateLayerRegion(StudioGizmoLayer layer, List<double> newRegion) {
    switch (layer) {
      case StudioGizmoLayer.inpaint:
        widget.studioNotifier.updateInpaintRegion(newRegion);
        break;
      case StudioGizmoLayer.primarySub:
        widget.studioNotifier.updateSubtitleRegion(newRegion);
        break;
      case StudioGizmoLayer.secondarySub:
        widget.studioNotifier.updateSubtitleSecondaryRegion(newRegion);
        break;
      case StudioGizmoLayer.watermark:
        widget.studioNotifier.updateWatermarkRegion(newRegion);
        break;
      case StudioGizmoLayer.none:
        break;
    }
  }

  Offset _toLocal(Offset globalPos) {
    final box = _canvasKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return Offset.zero;
    return box.globalToLocal(globalPos);
  }

  void _handlePanStart(
      Offset globalPos, List<double> region, _StudioHandleType handle) {
    _activeHandle = handle;
    _dragStartLocal = _toLocal(globalPos);
    _dragStartRegion = List.from(region);
  }

  void _handlePanUpdate(Offset globalPos) {
    if (_activeHandle == _StudioHandleType.none) return;
    final currentLocal = _toLocal(globalPos);
    final canvas = widget.canvasSize;
    if (canvas.width <= 0 || canvas.height <= 0) return;

    final dxNorm = (currentLocal.dx - _dragStartLocal.dx) / canvas.width;
    final dyNorm = (currentLocal.dy - _dragStartLocal.dy) / canvas.height;

    double top = _dragStartRegion[0];
    double left = _dragStartRegion[1];
    double bottom = _dragStartRegion[2];
    double right = _dragStartRegion[3];

    switch (_activeHandle) {
      case _StudioHandleType.move:
        final h = bottom - top;
        final w = right - left;
        top = (top + dyNorm).clamp(0.0, 1.0 - h);
        bottom = top + h;
        left = (left + dxNorm).clamp(0.0, 1.0 - w);
        right = left + w;
        break;
      case _StudioHandleType.topLeft:
        top = (top + dyNorm).clamp(0.0, bottom - 0.02);
        left = (left + dxNorm).clamp(0.0, right - 0.02);
        break;
      case _StudioHandleType.top:
        top = (top + dyNorm).clamp(0.0, bottom - 0.02);
        break;
      case _StudioHandleType.topRight:
        top = (top + dyNorm).clamp(0.0, bottom - 0.02);
        right = (right + dxNorm).clamp(left + 0.02, 1.0);
        break;
      case _StudioHandleType.right:
        right = (right + dxNorm).clamp(left + 0.02, 1.0);
        break;
      case _StudioHandleType.bottomRight:
        bottom = (bottom + dyNorm).clamp(top + 0.02, 1.0);
        right = (right + dxNorm).clamp(left + 0.02, 1.0);
        break;
      case _StudioHandleType.bottom:
        bottom = (bottom + dyNorm).clamp(top + 0.02, 1.0);
        break;
      case _StudioHandleType.bottomLeft:
        bottom = (bottom + dyNorm).clamp(top + 0.02, 1.0);
        left = (left + dxNorm).clamp(0.0, right - 0.02);
        break;
      case _StudioHandleType.left:
        left = (left + dxNorm).clamp(0.0, right - 0.02);
        break;
      case _StudioHandleType.none:
        break;
    }

    final activeLayer = ref.read(activeStudioGizmoLayerProvider);
    final clamped = [
      double.parse(top.clamp(0.0, 0.98).toStringAsFixed(3)),
      double.parse(left.clamp(0.0, 0.98).toStringAsFixed(3)),
      double.parse(bottom.clamp(top + 0.015, 1.0).toStringAsFixed(3)),
      double.parse(right.clamp(left + 0.015, 1.0).toStringAsFixed(3)),
    ];
    _updateLayerRegion(activeLayer, clamped);
  }

  @override
  Widget build(BuildContext context) {
    final isGizmoActive = ref.watch(isGizmoActiveProvider);
    final activeLayer = ref.watch(activeStudioGizmoLayerProvider);
    if (!isGizmoActive || activeLayer == StudioGizmoLayer.none) {
      return const SizedBox.shrink();
    }

    final canvasSize = widget.canvasSize;
    if (canvasSize.width <= 0 || canvasSize.height <= 0) {
      return const SizedBox.shrink();
    }

    final region = _getLayerRegion(activeLayer);
    final topPx = region[0] * canvasSize.height;
    final leftPx = region[1] * canvasSize.width;
    final widthPx = ((region[3] - region[1]) * canvasSize.width).clamp(24.0, canvasSize.width);
    final heightPx = ((region[2] - region[0]) * canvasSize.height).clamp(16.0, canvasSize.height);
    final color = _layerColor(activeLayer);

    return SizedBox(
      key: _canvasKey,
      width: canvasSize.width,
      height: canvasSize.height,
      child: Stack(
        fit: StackFit.expand,
        clipBehavior: Clip.none,
        children: [
          // ── Active Gizmo Box with 8 Handles ──
          Positioned(
            top: topPx,
            left: leftPx,
            width: widthPx,
            height: heightPx,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // Move Body Hit Target
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanStart: (d) => _handlePanStart(d.globalPosition, region, _StudioHandleType.move),
                    onPanUpdate: (d) => _handlePanUpdate(d.globalPosition),
                    onPanEnd: (_) => _activeHandle = _StudioHandleType.none,
                    onPanCancel: () => _activeHandle = _StudioHandleType.none,
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: color, width: 2.0),
                        color: color.withOpacity(0.08),
                      ),
                      child: Align(
                        alignment: Alignment.topLeft,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: const BorderRadius.only(bottomRight: Radius.circular(4)),
                          ),
                          child: Text(
                            activeLayer == StudioGizmoLayer.inpaint
                                ? '🧹 Inpaint'
                                : activeLayer == StudioGizmoLayer.primarySub
                                    ? '🅰️ Sub Chính'
                                    : activeLayer == StudioGizmoLayer.secondarySub
                                        ? '🅱️ Sub Phụ'
                                        : '🏷️ Logo',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                // 8 Direct Resizing Handles
                _buildGizmoHandle(-7, -7, _StudioHandleType.topLeft, region, color),
                _buildGizmoHandle(widthPx / 2 - 7, -7, _StudioHandleType.top, region, color),
                _buildGizmoHandle(widthPx - 7, -7, _StudioHandleType.topRight, region, color),
                _buildGizmoHandle(widthPx - 7, heightPx / 2 - 7, _StudioHandleType.right, region, color),
                _buildGizmoHandle(widthPx - 7, heightPx - 7, _StudioHandleType.bottomRight, region, color),
                _buildGizmoHandle(widthPx / 2 - 7, heightPx - 7, _StudioHandleType.bottom, region, color),
                _buildGizmoHandle(-7, heightPx - 7, _StudioHandleType.bottomLeft, region, color),
                _buildGizmoHandle(-7, heightPx / 2 - 7, _StudioHandleType.left, region, color),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGizmoHandle(
    double x,
    double y,
    _StudioHandleType handle,
    List<double> r,
    Color color,
  ) {
    const visualSize = 13.0;
    const hitSize = 28.0;

    MouseCursor cursor;
    switch (handle) {
      case _StudioHandleType.topLeft:
      case _StudioHandleType.bottomRight:
        cursor = SystemMouseCursors.resizeUpLeftDownRight;
        break;
      case _StudioHandleType.topRight:
      case _StudioHandleType.bottomLeft:
        cursor = SystemMouseCursors.resizeUpRightDownLeft;
        break;
      case _StudioHandleType.top:
      case _StudioHandleType.bottom:
        cursor = SystemMouseCursors.resizeUpDown;
        break;
      case _StudioHandleType.left:
      case _StudioHandleType.right:
        cursor = SystemMouseCursors.resizeLeftRight;
        break;
      default:
        cursor = SystemMouseCursors.grab;
    }

    return Positioned(
      left: x - hitSize / 2,
      top: y - hitSize / 2,
      child: MouseRegion(
        cursor: cursor,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (d) => _handlePanStart(d.globalPosition, r, handle),
          onPanUpdate: (d) => _handlePanUpdate(d.globalPosition),
          onPanEnd: (_) => _activeHandle = _StudioHandleType.none,
          onPanCancel: () => _activeHandle = _StudioHandleType.none,
          child: SizedBox(
            width: hitSize,
            height: hitSize,
            child: Center(
              child: Container(
                width: visualSize,
                height: visualSize,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: color, width: 2.2),
                  boxShadow: [
                    BoxShadow(color: color.withOpacity(0.5), blurRadius: 4),
                    const BoxShadow(color: Colors.black54, blurRadius: 2),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
