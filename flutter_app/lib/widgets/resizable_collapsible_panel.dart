import 'package:flutter/material.dart';
import '../core/app_colors.dart';

enum PanelSide { left, right, top, bottom }

/// A desktop-grade resizable and collapsible panel supporting both horizontal
/// (left/right sidebars) and vertical (top/bottom toolbars, timelines, logs).
/// Provides:
/// - Cursor `SystemMouseCursors.resizeColumn` (horizontal) or `resizeRow` (vertical) on splitter hover.
/// - Fluid drag resizing with min/max bounds.
/// - One-click collapse / expand toggle button with smooth animated transition.
/// - Double-click splitter to reset to default size.
class ResizableCollapsiblePanel extends StatefulWidget {
  final Widget child;
  final Widget panel;
  final PanelSide side;
  final double initialWidth;
  final double minWidth;
  final double maxWidth;
  final double? initialHeight;
  final double? minHeight;
  final double? maxHeight;
  final bool isCollapsible;
  final bool initiallyCollapsed;
  final String? collapseTooltip;
  final String? expandTooltip;
  final ValueChanged<double>? onWidthChanged;
  final ValueChanged<double>? onHeightChanged;
  final ValueChanged<bool>? onCollapseChanged;

  const ResizableCollapsiblePanel({
    super.key,
    required this.child,
    required this.panel,
    this.side = PanelSide.right,
    this.initialWidth = 280.0,
    this.minWidth = 180.0,
    this.maxWidth = 550.0,
    this.initialHeight,
    this.minHeight,
    this.maxHeight,
    this.isCollapsible = true,
    this.initiallyCollapsed = false,
    this.collapseTooltip,
    this.expandTooltip,
    this.onWidthChanged,
    this.onHeightChanged,
    this.onCollapseChanged,
  });

  @override
  State<ResizableCollapsiblePanel> createState() => _ResizableCollapsiblePanelState();
}

class _ResizableCollapsiblePanelState extends State<ResizableCollapsiblePanel> {
  late double _currentSize;
  late double _lastExpandedSize;
  late bool _isCollapsed;
  bool _isHoveringDivider = false;
  bool _isDragging = false;

  bool get isHorizontal => widget.side == PanelSide.left || widget.side == PanelSide.right;

  double get _effectiveInitialSize => isHorizontal
      ? widget.initialWidth
      : (widget.initialHeight ?? widget.initialWidth);

  double get _effectiveMinSize => isHorizontal
      ? widget.minWidth
      : (widget.minHeight ?? widget.minWidth);

  double get _effectiveMaxSize => isHorizontal
      ? widget.maxWidth
      : (widget.maxHeight ?? widget.maxWidth);

  @override
  void initState() {
    super.initState();
    _currentSize = _effectiveInitialSize.clamp(_effectiveMinSize, _effectiveMaxSize);
    _lastExpandedSize = _currentSize;
    _isCollapsed = widget.initiallyCollapsed;
  }

  void _toggleCollapse() {
    setState(() {
      _isCollapsed = !_isCollapsed;
      if (!_isCollapsed) {
        _currentSize = _lastExpandedSize;
      }
    });
    widget.onCollapseChanged?.call(_isCollapsed);
  }

  void _resetSize() {
    setState(() {
      _isCollapsed = false;
      _currentSize = _effectiveInitialSize.clamp(_effectiveMinSize, _effectiveMaxSize);
      _lastExpandedSize = _currentSize;
    });
    if (isHorizontal) {
      widget.onWidthChanged?.call(_currentSize);
    } else {
      widget.onHeightChanged?.call(_currentSize);
      widget.onWidthChanged?.call(_currentSize);
    }
    widget.onCollapseChanged?.call(false);
  }

  void _handleDrag(DragUpdateDetails details) {
    if (_isCollapsed) {
      setState(() {
        _isCollapsed = false;
      });
      widget.onCollapseChanged?.call(false);
    }

    final double delta;
    if (widget.side == PanelSide.left) {
      delta = details.delta.dx;
    } else if (widget.side == PanelSide.right) {
      delta = -details.delta.dx;
    } else if (widget.side == PanelSide.top) {
      delta = details.delta.dy;
    } else {
      // PanelSide.bottom
      delta = -details.delta.dy;
    }

    final newSize = _currentSize + delta;
    final minSize = _effectiveMinSize;
    final maxSize = _effectiveMaxSize;

    // If dragged below half minSize, snap to collapse
    if (widget.isCollapsible && newSize < minSize * 0.55) {
      setState(() {
        _isCollapsed = true;
      });
      widget.onCollapseChanged?.call(true);
      return;
    }

    final clamped = newSize.clamp(minSize, maxSize);
    if (clamped != _currentSize) {
      setState(() {
        _currentSize = clamped;
        _lastExpandedSize = clamped;
      });
      if (isHorizontal) {
        widget.onWidthChanged?.call(_currentSize);
      } else {
        widget.onHeightChanged?.call(_currentSize);
        widget.onWidthChanged?.call(_currentSize);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);

    if (isHorizontal) {
      return _buildHorizontalLayout(c);
    } else {
      return _buildVerticalLayout(c);
    }
  }

  Widget _buildHorizontalLayout(AppColorTokens c) {
    final isLeft = widget.side == PanelSide.left;

    final panelWidget = AnimatedContainer(
      duration: _isDragging ? Duration.zero : const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      width: _isCollapsed ? 0 : _currentSize,
      child: ClipRect(
        child: OverflowBox(
          alignment: isLeft ? Alignment.centerRight : Alignment.centerLeft,
          minWidth: _effectiveMinSize,
          maxWidth: _effectiveMaxSize,
          child: SizedBox(
            width: _currentSize,
            child: widget.panel,
          ),
        ),
      ),
    );

    final dividerWidget = MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      onEnter: (_) => setState(() => _isHoveringDivider = true),
      onExit: (_) => setState(() => _isHoveringDivider = false),
      child: SizedBox(
        width: 8,
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            // Divider Line with hover glow & drag gesture
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onDoubleTap: _resetSize,
                onHorizontalDragStart: (_) => setState(() => _isDragging = true),
                onHorizontalDragUpdate: _handleDrag,
                onHorizontalDragEnd: (_) => setState(() => _isDragging = false),
                child: Container(
                  color: _isHoveringDivider || _isDragging
                      ? c.primary.withOpacity(0.15)
                      : Colors.transparent,
                  child: Center(
                    child: Container(
                      width: _isHoveringDivider || _isDragging ? 2.5 : 1.0,
                      color: _isHoveringDivider || _isDragging
                          ? c.primary
                          : c.border,
                    ),
                  ),
                ),
              ),
            ),

            // Collapsible Toggle Micro-Button
            if (widget.isCollapsible)
              Positioned(
                top: 18,
                child: Tooltip(
                  message: _isCollapsed
                      ? (widget.expandTooltip ?? (isLeft ? 'Mở thanh bên trái' : 'Mở thanh bên phải'))
                      : (widget.collapseTooltip ?? (isLeft ? 'Thu gọn thanh bên trái' : 'Thu gọn thanh bên phải')),
                  waitDuration: const Duration(milliseconds: 400),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: _toggleCollapse,
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        width: 14,
                        height: 26,
                        decoration: BoxDecoration(
                          color: _isHoveringDivider || _isDragging ? c.surfaceLight : c.surface,
                          borderRadius: BorderRadius.circular(3),
                          border: Border.all(
                            color: _isHoveringDivider || _isDragging ? c.primary : c.border,
                            width: 0.8,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.25),
                              blurRadius: 3,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                        child: Center(
                          child: Icon(
                            isLeft
                                ? (_isCollapsed ? Icons.chevron_right : Icons.chevron_left)
                                : (_isCollapsed ? Icons.chevron_left : Icons.chevron_right),
                            size: 11,
                            color: _isHoveringDivider || _isDragging ? c.primary : c.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (isLeft) ...[
          panelWidget,
          dividerWidget,
          Expanded(child: widget.child),
        ] else ...[
          Expanded(child: widget.child),
          dividerWidget,
          panelWidget,
        ],
      ],
    );
  }

  Widget _buildVerticalLayout(AppColorTokens c) {
    final isTop = widget.side == PanelSide.top;

    final panelWidget = AnimatedContainer(
      duration: _isDragging ? Duration.zero : const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      height: _isCollapsed ? 0 : _currentSize,
      child: ClipRect(
        child: OverflowBox(
          alignment: isTop ? Alignment.bottomCenter : Alignment.topCenter,
          minHeight: _effectiveMinSize,
          maxHeight: _effectiveMaxSize,
          child: SizedBox(
            height: _currentSize,
            child: widget.panel,
          ),
        ),
      ),
    );

    final dividerWidget = MouseRegion(
      cursor: SystemMouseCursors.resizeRow,
      onEnter: (_) => setState(() => _isHoveringDivider = true),
      onExit: (_) => setState(() => _isHoveringDivider = false),
      child: Container(
        height: _isCollapsed ? 24 : 8,
        decoration: BoxDecoration(
          color: _isCollapsed ? c.surfaceDark : Colors.transparent,
          border: _isCollapsed
              ? Border(
                  top: BorderSide(color: c.border, width: 0.8),
                  bottom: BorderSide(color: c.border, width: 0.8),
                )
              : null,
        ),
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            // Divider Line with hover glow & drag gesture
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onDoubleTap: _resetSize,
                onVerticalDragStart: (_) => setState(() => _isDragging = true),
                onVerticalDragUpdate: _handleDrag,
                onVerticalDragEnd: (_) => setState(() => _isDragging = false),
                child: Container(
                  color: _isHoveringDivider || _isDragging
                      ? c.primary.withOpacity(0.15)
                      : Colors.transparent,
                  child: Center(
                    child: Container(
                      height: _isHoveringDivider || _isDragging ? 2.5 : 1.0,
                      color: _isHoveringDivider || _isDragging
                          ? c.primary
                          : c.border,
                    ),
                  ),
                ),
              ),
            ),

            // Collapsible Toggle Micro-Button
            if (widget.isCollapsible)
              Positioned(
                right: 24,
                child: Tooltip(
                  message: _isCollapsed
                      ? (widget.expandTooltip ?? (isTop ? 'Mở thanh phía trên' : 'Mở thanh phía dưới'))
                      : (widget.collapseTooltip ?? (isTop ? 'Thu gọn thanh phía trên' : 'Thu gọn thanh phía dưới')),
                  waitDuration: const Duration(milliseconds: 400),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: _toggleCollapse,
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        width: 28,
                        height: 14,
                        decoration: BoxDecoration(
                          color: _isHoveringDivider || _isDragging ? c.surfaceLight : c.surface,
                          borderRadius: BorderRadius.circular(3),
                          border: Border.all(
                            color: _isHoveringDivider || _isDragging ? c.primary : c.border,
                            width: 0.8,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.25),
                              blurRadius: 3,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                        child: Center(
                          child: Icon(
                            isTop
                                ? (_isCollapsed ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up)
                                : (_isCollapsed ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down),
                            size: 11,
                            color: _isHoveringDivider || _isDragging ? c.primary : c.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (isTop) ...[
          panelWidget,
          dividerWidget,
          Expanded(child: widget.child),
        ] else ...[
          Expanded(child: widget.child),
          dividerWidget,
          panelWidget,
        ],
      ],
    );
  }
}
