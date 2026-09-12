import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
  Offset _toolbarPos = const Offset(12, 12);
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
    final activeLayer = ref.watch(activeStudioGizmoLayerProvider);
    if (activeLayer == StudioGizmoLayer.none) {
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
                        border: Border.all(color: color, width: 1.8),
                        color: color.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ),

                // 8 Handles
                _buildGizmoHandle(0, 0, _StudioHandleType.topLeft, region, color),
                _buildGizmoHandle(widthPx / 2, 0, _StudioHandleType.top, region, color),
                _buildGizmoHandle(widthPx, 0, _StudioHandleType.topRight, region, color),
                _buildGizmoHandle(widthPx, heightPx / 2, _StudioHandleType.right, region, color),
                _buildGizmoHandle(widthPx, heightPx, _StudioHandleType.bottomRight, region, color),
                _buildGizmoHandle(widthPx / 2, heightPx, _StudioHandleType.bottom, region, color),
                _buildGizmoHandle(0, heightPx, _StudioHandleType.bottomLeft, region, color),
                _buildGizmoHandle(0, heightPx / 2, _StudioHandleType.left, region, color),
              ],
            ),
          ),

          // ── Draggable Floating Toolbar ──
          _buildFloatingToolbar(activeLayer, canvasSize),
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

  Widget _buildFloatingToolbar(StudioGizmoLayer activeLayer, Size canvasSize) {
    return Positioned(
      left: _toolbarPos.dx.clamp(6.0, (canvasSize.width - 340).clamp(6.0, double.infinity)),
      top: _toolbarPos.dy.clamp(6.0, (canvasSize.height - 44).clamp(6.0, double.infinity)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A).withOpacity(0.92),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _layerColor(activeLayer).withOpacity(0.7), width: 1.0),
          boxShadow: const [
            BoxShadow(color: Colors.black87, blurRadius: 10, offset: Offset(0, 3)),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag grip
            MouseRegion(
              cursor: SystemMouseCursors.move,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanUpdate: (d) {
                  setState(() {
                    _toolbarPos += d.delta;
                  });
                },
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(Icons.drag_indicator, size: 16, color: Colors.white54),
                ),
              ),
            ),
            const SizedBox(width: 4),

            // Button Inpaint
            _buildToolbarTabBtn(
              label: '🧹 Xóa Sub',
              layer: StudioGizmoLayer.inpaint,
              activeLayer: activeLayer,
              onTap: () {
                ref.read(activeStudioGizmoLayerProvider.notifier).state = StudioGizmoLayer.inpaint;
                if (!widget.studioState.inpaintConfig.enabled) {
                  widget.studioNotifier.updateInpaintConfig(enabled: true);
                }
              },
            ),
            const SizedBox(width: 3),

            // Button Primary Sub
            _buildToolbarTabBtn(
              label: '🅰️ Sub Chính',
              layer: StudioGizmoLayer.primarySub,
              activeLayer: activeLayer,
              onTap: () {
                ref.read(activeStudioGizmoLayerProvider.notifier).state = StudioGizmoLayer.primarySub;
                if (!widget.studioState.subStyle.showMainSub) {
                  widget.studioNotifier.updateSubStyle(widget.studioState.subStyle.copyWith(showMainSub: true));
                }
              },
            ),
            const SizedBox(width: 3),

            // Button Secondary Sub
            _buildToolbarTabBtn(
              label: '🅱️ Sub Phụ',
              layer: StudioGizmoLayer.secondarySub,
              activeLayer: activeLayer,
              onTap: () {
                ref.read(activeStudioGizmoLayerProvider.notifier).state = StudioGizmoLayer.secondarySub;
                if (!widget.studioState.subStyle.showSubSub) {
                  widget.studioNotifier.updateSubStyle(widget.studioState.subStyle.copyWith(showSubSub: true));
                }
              },
            ),
            const SizedBox(width: 6),

            // Close button
            InkWell(
              borderRadius: BorderRadius.circular(4),
              onTap: () {
                ref.read(activeStudioGizmoLayerProvider.notifier).state = StudioGizmoLayer.none;
              },
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Icon(Icons.close, size: 14, color: Colors.white70),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolbarTabBtn({
    required String label,
    required StudioGizmoLayer layer,
    required StudioGizmoLayer activeLayer,
    required VoidCallback onTap,
  }) {
    final isSel = layer == activeLayer;
    final c = _layerColor(layer);

    return InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        decoration: BoxDecoration(
          color: isSel ? c.withOpacity(0.25) : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isSel ? c : Colors.white12,
            width: isSel ? 1.0 : 0.6,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSel ? c : Colors.white70,
            fontSize: 10.5,
            fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
