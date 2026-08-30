import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/app_colors.dart';
import '../core/providers.dart';
import '../models/app_config.dart';
import '../utils/color_parser_utils.dart';

enum HandleType {
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

class InteractiveVisualFrameOverlay extends ConsumerStatefulWidget {
  final double videoAspectRatio;
  final VoidCallback? onClose;

  const InteractiveVisualFrameOverlay({
    super.key,
    this.videoAspectRatio = 9 / 16,
    this.onClose,
  });

  @override
  ConsumerState<InteractiveVisualFrameOverlay> createState() =>
      _InteractiveVisualFrameOverlayState();
}

class _InteractiveVisualFrameOverlayState
    extends ConsumerState<InteractiveVisualFrameOverlay> {
  HandleType _activeHandle = HandleType.none;
  Offset _dragStartLocal = Offset.zero;
  List<double> _dragStartRegion = [0, 0, 0, 0];
  final GlobalKey _canvasKey = GlobalKey();
  Size _currentCanvasSize = Size.zero;
  Offset _toolbarPos = const Offset(12, 12);

  FrameLayerType get _activeLayer => ref.read(activeGizmoLayerProvider);

  // ── Get region for a given layer ──
  List<double> _getLayerRegion(AppConfig config, FrameLayerType layer) {
    switch (layer) {
      case FrameLayerType.inpaint:
        return config.inpaintRegion ?? [0.75, 0.05, 0.95, 0.95];
      case FrameLayerType.primarySub:
        // Follow inpaint region if subtitleRegion is null
        return config.subtitleRegion ??
            (config.inpaintRegion != null
                ? [...config.inpaintRegion!]
                : [0.76, 0.05, 0.86, 0.95]);
      case FrameLayerType.secondarySub:
        return config.subtitleSecondaryRegion ?? [0.87, 0.05, 0.95, 0.95];
      case FrameLayerType.watermark:
        return config.watermarkRegion;
    }
  }

  void _updateLayerRegion(FrameLayerType layer, List<double> newRegion) {
    final notifier = ref.read(configProvider.notifier);
    final clamped = [
      double.parse(newRegion[0].clamp(0.0, 0.98).toStringAsFixed(2)),
      double.parse(newRegion[1].clamp(0.0, 0.98).toStringAsFixed(2)),
      double.parse(newRegion[2].clamp(newRegion[0] + 0.02, 1.0).toStringAsFixed(2)),
      double.parse(newRegion[3].clamp(newRegion[1] + 0.02, 1.0).toStringAsFixed(2)),
    ];
    switch (layer) {
      case FrameLayerType.inpaint:
        notifier.setField((c) => c.copyWith(inpaintRegion: clamped));
        break;
      case FrameLayerType.primarySub:
        notifier.setField((c) => c.copyWith(subtitleRegion: clamped));
        break;
      case FrameLayerType.secondarySub:
        notifier.setField((c) => c.copyWith(subtitleSecondaryRegion: clamped));
        break;
      case FrameLayerType.watermark:
        notifier.setField((c) => c.copyWith(watermarkRegion: clamped));
        break;
    }
  }

  // ── Convert global position to canvas-local normalized coords ──
  Offset _toLocal(Offset globalPos) {
    final box =
        _canvasKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return Offset.zero;
    return box.globalToLocal(globalPos);
  }

  Size _canvasSize() {
    if (_currentCanvasSize.width > 0 && _currentCanvasSize.height > 0) {
      return _currentCanvasSize;
    }
    final box =
        _canvasKey.currentContext?.findRenderObject() as RenderBox?;
    return box?.size ?? Size.zero;
  }

  void _handlePanStart(
      Offset globalPos, List<double> region, HandleType handle) {
    _activeHandle = handle;
    _dragStartLocal = _toLocal(globalPos);
    _dragStartRegion = List.from(region);
  }

  void _handlePanUpdate(Offset globalPos) {
    if (_activeHandle == HandleType.none) return;
    final currentLocal = _toLocal(globalPos);
    final canvas = _canvasSize();
    if (canvas.width <= 0 || canvas.height <= 0) return;

    final dxNorm = (currentLocal.dx - _dragStartLocal.dx) / canvas.width;
    final dyNorm = (currentLocal.dy - _dragStartLocal.dy) / canvas.height;

    double top = _dragStartRegion[0];
    double left = _dragStartRegion[1];
    double bottom = _dragStartRegion[2];
    double right = _dragStartRegion[3];

    switch (_activeHandle) {
      case HandleType.move:
        final h = bottom - top;
        final w = right - left;
        top = (top + dyNorm).clamp(0.0, 1.0 - h);
        bottom = top + h;
        left = (left + dxNorm).clamp(0.0, 1.0 - w);
        right = left + w;
        break;
      case HandleType.topLeft:
        top = (top + dyNorm).clamp(0.0, bottom - 0.02);
        left = (left + dxNorm).clamp(0.0, right - 0.02);
        break;
      case HandleType.top:
        top = (top + dyNorm).clamp(0.0, bottom - 0.02);
        break;
      case HandleType.topRight:
        top = (top + dyNorm).clamp(0.0, bottom - 0.02);
        right = (right + dxNorm).clamp(left + 0.02, 1.0);
        break;
      case HandleType.right:
        right = (right + dxNorm).clamp(left + 0.02, 1.0);
        break;
      case HandleType.bottomRight:
        bottom = (bottom + dyNorm).clamp(top + 0.02, 1.0);
        right = (right + dxNorm).clamp(left + 0.02, 1.0);
        break;
      case HandleType.bottom:
        bottom = (bottom + dyNorm).clamp(top + 0.02, 1.0);
        break;
      case HandleType.bottomLeft:
        bottom = (bottom + dyNorm).clamp(top + 0.02, 1.0);
        left = (left + dxNorm).clamp(0.0, right - 0.02);
        break;
      case HandleType.left:
        left = (left + dxNorm).clamp(0.0, right - 0.02);
        break;
      case HandleType.none:
        break;
    }

    _updateLayerRegion(_activeLayer, [top, left, bottom, right]);
  }

  /// Convert ASS font size (unit at native resolution) to Flutter logical pixels for preview
  double _assToPreviewFontSize(String fontSizeStr, double canvasHeight) {
    final assSize = double.tryParse(fontSizeStr);
    final nativeH = (widget.videoAspectRatio < 1.0) ? 1920.0 : 1080.0;
    if (assSize != null && assSize > 0) {
      final baseAss = (nativeH > 1080 && assSize <= 48) ? assSize * (nativeH / 1080.0) : assSize;
      return baseAss * (canvasHeight / nativeH);
    }
    // Auto: ~48px on 1920p (2.5% of height)
    return canvasHeight * 0.025;
  }

  /// Auto font size that fits snugly inside a box region
  double _autoFontSizeForBox(List<double> region, double canvasHeight, String fontSizeStr) {
    if (fontSizeStr.isNotEmpty && (double.tryParse(fontSizeStr) ?? 0) > 0) {
      return _assToPreviewFontSize(fontSizeStr, canvasHeight);
    }
    final boxHeightPx = (region[2] - region[0]) * canvasHeight;
    // Sub takes ~38% of box height as font size (comfortable fit)
    return (boxHeightPx * 0.38).clamp(8.0, 48.0);
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(configProvider);
    final activeLayer = ref.watch(activeGizmoLayerProvider);

    return LayoutBuilder(
      builder: (context, constraints) {
        final canvasSize = Size(constraints.maxWidth, constraints.maxHeight);
        _currentCanvasSize = canvasSize;

        return SizedBox(
          key: _canvasKey,
          width: constraints.maxWidth,
          height: constraints.maxHeight,
          child: Stack(
            fit: StackFit.expand,
            clipBehavior: Clip.none,
            children: [
              // ── Transparent backdrop so taps don't fall through to video player ──
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: () {},
                  child: const SizedBox.expand(),
                ),
              ),

              // 1. Inpaint box visual (Only for box_color engine)
              if (config.inpaintEngine == 'box_color' &&
                  config.inpaintShowBox &&
                  activeLayer != FrameLayerType.inpaint)
                _buildInpaintBoxLayer(config, canvasSize, dim: true),
              if (config.inpaintEngine == 'box_color' &&
                  config.inpaintShowBox &&
                  activeLayer == FrameLayerType.inpaint)
                _buildInpaintBoxLayer(config, canvasSize, dim: false),

              // 2. Primary sub preview (always show if enabled)
              if (config.showSubtitle)
                _buildPrimarySubLayer(config, canvasSize,
                    dim: activeLayer != FrameLayerType.primarySub),

              // 3. Secondary sub preview
              if (config.showSubtitle && config.subtitleSecondaryShow)
                _buildSecondarySubLayer(config, canvasSize,
                    dim: activeLayer != FrameLayerType.secondarySub),

              // 4. Watermark preview
              if (config.watermarkEnabled)
                _buildWatermarkLayer(config, canvasSize,
                    dim: activeLayer != FrameLayerType.watermark),

              // 5. Active Gizmo handles (always on top)
              _buildActiveLayerHandles(config, canvasSize),

              // ── DRAGGABLE FLOATING TOOLBAR ──
              _buildFloatingToolbar(config, canvasSize),

            ],
          ),
        );
      },
    );
  }

  String _layerLabel(FrameLayerType layer) {
    switch (layer) {
      case FrameLayerType.inpaint:
        return '🟨 Inpaint Box';
      case FrameLayerType.primarySub:
        return '🅰️ Sub Chính';
      case FrameLayerType.secondarySub:
        return '🅱️ Sub Phụ';
      case FrameLayerType.watermark:
        return '🏷️ Watermark';
    }
  }

  Color _layerColor(FrameLayerType layer) {
    switch (layer) {
      case FrameLayerType.inpaint:
        return AppColors.primary;
      case FrameLayerType.primarySub:
        return const Color(0xFF60A5FA);
      case FrameLayerType.secondarySub:
        return const Color(0xFF38BDF8);
      case FrameLayerType.watermark:
        return const Color(0xFFA855F7);
    }
  }

  // ── FLOATING DRAGGABLE TOOLBAR ──
  Widget _buildFloatingToolbar(AppConfig config, Size canvasSize) {
    final notifier = ref.read(configProvider.notifier);
    final hasUnsaved = notifier.hasUnsavedChanges;
    final activeLayer = ref.watch(activeGizmoLayerProvider);

    return Positioned(
      left: _toolbarPos.dx.clamp(4.0, (canvasSize.width - 240).clamp(4.0, double.infinity)),
      top: _toolbarPos.dy.clamp(4.0, (canvasSize.height - 42).clamp(4.0, double.infinity)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.surface.withOpacity(0.95),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: _layerColor(activeLayer).withOpacity(0.6)),
          boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 10, offset: Offset(0, 2))],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag grip handle
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
                  padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Icon(Icons.drag_indicator, size: 14, color: AppColors.textSecondary),
                ),
              ),
            ),
            const SizedBox(width: 2),

            // Layer indicator badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: _layerColor(activeLayer).withOpacity(0.2),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                    color: _layerColor(activeLayer).withOpacity(0.6), width: 0.8),
              ),
              child: Text(
                _layerLabel(activeLayer),
                style: TextStyle(
                    color: _layerColor(activeLayer),
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 5),

            // Save button
            GestureDetector(
              onTap: () async {
                await notifier.save();
                setState(() {});
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('✅ Đã lưu cấu hình!'),
                  duration: Duration(seconds: 2),
                  backgroundColor: AppColors.statusCompleted,
                ));
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: hasUnsaved
                      ? AppColors.primary.withOpacity(0.2)
                      : AppColors.statusCompletedBg,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                      color: hasUnsaved
                          ? AppColors.primary
                          : AppColors.statusCompleted,
                      width: 0.8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      hasUnsaved ? Icons.save_outlined : Icons.check_circle_outline,
                      size: 11,
                      color: hasUnsaved
                          ? AppColors.primary
                          : AppColors.statusCompleted,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      hasUnsaved ? 'Lưu' : 'Đã Lưu',
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w600,
                        color: hasUnsaved
                            ? AppColors.primary
                            : AppColors.statusCompleted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 5),

            // Close button
            GestureDetector(
              onTap: widget.onClose,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: AppColors.surfaceLight,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: AppColors.border, width: 0.6),
                ),
                child: const Icon(Icons.close, size: 11, color: AppColors.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── INPAINT BOX LAYER ──
  Widget _buildInpaintBoxLayer(AppConfig config, Size canvasSize,
      {bool dim = false}) {
    final r = _getLayerRegion(config, FrameLayerType.inpaint);
    final top = r[0] * canvasSize.height;
    final left = r[1] * canvasSize.width;
    final w = (r[3] - r[1]) * canvasSize.width;
    final h = (r[2] - r[0]) * canvasSize.height;

    final bgColor = ColorParserUtils.parse(config.boxBgColor)
        .withOpacity(dim ? 0.35 : config.boxBgOpacity);
    final borderColor = ColorParserUtils.parse(config.boxBorderColor)
        .withOpacity(dim ? 0.4 : 1.0);

    return Positioned(
      top: top,
      left: left,
      width: w,
      height: h,
      child: IgnorePointer(
        child: Container(
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius:
                BorderRadius.circular(config.boxBorderRadius.toDouble()),
            border: Border.all(
                color: borderColor,
                width: config.boxBorderWidth.toDouble()),
          ),
          // ── Sub preview inside inpaint box when subs follow inpaint ──
          child: _buildSubPreviewInsideInpaint(config, canvasSize, r, h),
        ),
      ),
    );
  }

  /// Renders sub preview inside inpaint box when sub regions are null (auto follow)
  Widget _buildSubPreviewInsideInpaint(
      AppConfig config, Size canvasSize, List<double> inpaintR, double boxH) {
    final primaryFollows =
        config.showSubtitle && config.subtitleRegion == null;
    final secondaryFollows =
        config.showSubtitle &&
            config.subtitleSecondaryShow &&
            config.subtitleSecondaryRegion == null;

    if (!primaryFollows && !secondaryFollows) return const SizedBox.shrink();

    final fontColor = ColorParserUtils.parse(config.fontColor);
    final outlineColor = ColorParserUtils.parse(config.outlineColor);
    final primaryFontSize = _autoFontSizeForBox(inpaintR, canvasSize.height, config.fontSize);
    final secondaryFontSize =
        primaryFontSize * config.subtitleSecondaryFontScale;
    final secFontColor =
        ColorParserUtils.parse(config.subtitleSecondaryFontColor);

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (primaryFollows)
          Text(
            'Mẫu Phụ Đề Chính',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily:
                  config.fontName.isNotEmpty ? config.fontName : null,
              fontSize: primaryFontSize,
              fontWeight: FontWeight.bold,
              color: fontColor,
              shadows: [
                Shadow(color: outlineColor, blurRadius: 3),
                Shadow(color: outlineColor, offset: const Offset(1, 1)),
              ],
            ),
          ),
        if (primaryFollows && secondaryFollows)
          SizedBox(height: (boxH * 0.04).clamp(2.0, 8.0)),
        if (secondaryFollows)
          Text(
            'Sample Secondary Sub',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: config.subtitleSecondaryFontName.isNotEmpty
                  ? config.subtitleSecondaryFontName
                  : (config.fontName.isNotEmpty ? config.fontName : null),
              fontSize: secondaryFontSize,
              fontWeight: FontWeight.w600,
              color: secFontColor,
              shadows: const [Shadow(color: Colors.black, blurRadius: 3)],
            ),
          ),
      ],
    );
  }

  // ── PRIMARY SUBTITLE LAYER (WYSIWYG) ──
  Widget _buildPrimarySubLayer(AppConfig config, Size canvasSize,
      {bool dim = false}) {
    final r = _getLayerRegion(config, FrameLayerType.primarySub);
    if (config.subtitleRegion == null && config.inpaintRegion == null) {
      return const SizedBox.shrink();
    }
    if (config.subtitleRegion == null) return const SizedBox.shrink();

    final top = r[0] * canvasSize.height;
    final left = r[1] * canvasSize.width;
    final w = (r[3] - r[1]) * canvasSize.width;
    final h = (r[2] - r[0]) * canvasSize.height;

    final fontColor = ColorParserUtils.parse(config.fontColor)
        .withOpacity(dim ? 0.5 : 1.0);
    final outlineColor = ColorParserUtils.parse(config.outlineColor);
    final fontSize = _assToPreviewFontSize(config.fontSize, canvasSize.height);

    return Positioned(
      top: top,
      left: left,
      width: w,
      height: h,
      child: IgnorePointer(
        child: Center(
          child: Text(
            'Mẫu Phụ Đề Chính Tiếng Việt',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily:
                  config.fontName.isNotEmpty ? config.fontName : null,
              fontSize: fontSize,
              fontWeight: FontWeight.bold,
              color: fontColor,
              shadows: [
                Shadow(color: outlineColor, blurRadius: 3),
                Shadow(color: outlineColor, offset: const Offset(1, 1)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── SECONDARY SUBTITLE LAYER (WYSIWYG) ──
  Widget _buildSecondarySubLayer(AppConfig config, Size canvasSize,
      {bool dim = false}) {
    final r = _getLayerRegion(config, FrameLayerType.secondarySub);
    if (config.subtitleSecondaryRegion == null) return const SizedBox.shrink();

    final top = r[0] * canvasSize.height;
    final left = r[1] * canvasSize.width;
    final w = (r[3] - r[1]) * canvasSize.width;
    final h = (r[2] - r[0]) * canvasSize.height;

    final primarySize = _assToPreviewFontSize(config.fontSize, canvasSize.height);
    final fontSize = primarySize * config.subtitleSecondaryFontScale;
    final fontColor =
        ColorParserUtils.parse(config.subtitleSecondaryFontColor)
            .withOpacity(dim ? 0.5 : 1.0);

    return Positioned(
      top: top,
      left: left,
      width: w,
      height: h,
      child: IgnorePointer(
        child: Center(
          child: Text(
            'Sample Secondary Bilingual Subtitle',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: config.subtitleSecondaryFontName.isNotEmpty
                  ? config.subtitleSecondaryFontName
                  : (config.fontName.isNotEmpty ? config.fontName : null),
              fontSize: fontSize,
              fontWeight: FontWeight.w600,
              color: fontColor,
              shadows: const [Shadow(color: Colors.black, blurRadius: 3)],
            ),
          ),
        ),
      ),
    );
  }

  // ── WATERMARK LAYER (WYSIWYG) ──
  Widget _buildWatermarkLayer(AppConfig config, Size canvasSize,
      {bool dim = false}) {
    final r = config.watermarkRegion;
    final top = r[0] * canvasSize.height;
    final left = r[1] * canvasSize.width;
    final w = (r[3] - r[1]) * canvasSize.width;
    final h = (r[2] - r[0]) * canvasSize.height;

    final fontColor = ColorParserUtils.parse(config.watermarkFontColor)
        .withOpacity(dim ? 0.4 : 1.0);

    return Positioned(
      top: top,
      left: left,
      width: w,
      height: h,
      child: IgnorePointer(
        child: Opacity(
          opacity: dim ? 0.5 : config.watermarkOpacity,
          child: Container(
            decoration: BoxDecoration(
              color: config.watermarkBlurBg ? Colors.black45 : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Center(
              child: config.watermarkImage.isNotEmpty &&
                      File(config.watermarkImage).existsSync()
                  ? Image.file(File(config.watermarkImage), fit: BoxFit.contain)
                  : Text(
                      config.watermarkText.isNotEmpty
                          ? config.watermarkText
                          : 'Sub-Video AI',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: config.watermarkFontName.isNotEmpty
                            ? config.watermarkFontName
                            : 'Arial',
                        fontSize: (h * 0.65).clamp(8.0, 36.0),
                        fontWeight: FontWeight.bold,
                        color: fontColor,
                        shadows: const [Shadow(color: Colors.black, blurRadius: 2)],
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  // ── GIZMO HANDLES FOR ACTIVE LAYER ──
  Widget _buildActiveLayerHandles(AppConfig config, Size canvasSize) {
    final r = _getLayerRegion(config, _activeLayer);
    final top = r[0] * canvasSize.height;
    final left = r[1] * canvasSize.width;
    final w = (r[3] - r[1]) * canvasSize.width;
    final h = (r[2] - r[0]) * canvasSize.height;
    final color = _layerColor(_activeLayer);

    return Positioned(
      top: top,
      left: left,
      width: w,
      height: h,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Move body
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: (d) =>
                  _handlePanStart(d.globalPosition, r, HandleType.move),
              onPanUpdate: (d) => _handlePanUpdate(d.globalPosition),
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: color, width: 1.5),
                  color: color.withOpacity(0.08),
                ),
              ),
            ),
          ),

          // 8 Resize handles
          _buildHandle(0, 0, HandleType.topLeft, r, color),
          _buildHandle(w / 2, 0, HandleType.top, r, color),
          _buildHandle(w, 0, HandleType.topRight, r, color),
          _buildHandle(w, h / 2, HandleType.right, r, color),
          _buildHandle(w, h, HandleType.bottomRight, r, color),
          _buildHandle(w / 2, h, HandleType.bottom, r, color),
          _buildHandle(0, h, HandleType.bottomLeft, r, color),
          _buildHandle(0, h / 2, HandleType.left, r, color),
        ],
      ),
    );
  }

  Widget _buildHandle(
      double x, double y, HandleType handle, List<double> r, Color color) {
    const visualSize = 14.0; // Visible dot size
    const hitSize = 30.0; // Tap/drag area

    // Mouse cursor based on handle type
    MouseCursor cursor;
    switch (handle) {
      case HandleType.topLeft:
      case HandleType.bottomRight:
        cursor = SystemMouseCursors.resizeUpLeftDownRight;
        break;
      case HandleType.topRight:
      case HandleType.bottomLeft:
        cursor = SystemMouseCursors.resizeUpRightDownLeft;
        break;
      case HandleType.top:
      case HandleType.bottom:
        cursor = SystemMouseCursors.resizeUpDown;
        break;
      case HandleType.left:
      case HandleType.right:
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
                  border: Border.all(color: color, width: 2),
                  boxShadow: [
                    BoxShadow(color: color.withOpacity(0.4), blurRadius: 4),
                    const BoxShadow(color: Colors.black45, blurRadius: 2),
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
