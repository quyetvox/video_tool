import 'package:flutter/material.dart';
import '../core/app_colors.dart';

/// ═══════════════════════════════════════════════════════════════════════════
/// ── 🏷️ APP SECTION HEADER ──────────────────────────────────────────────────
/// ═══════════════════════════════════════════════════════════════════════════
class AppSectionHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;

  const AppSectionHeader({
    super.key,
    required this.title,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Row(
      children: [
        Container(
          width: 3,
          height: 13,
          decoration: BoxDecoration(
            color: c.primary,
            borderRadius: BorderRadius.circular(1.5),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              color: c.primary,
              fontSize: 11.5,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

/// ═══════════════════════════════════════════════════════════════════════════
/// ── 📝 APP TEXT FIELD (UNIFIED 34PX / 28PX) ────────────────────────────────
/// ═══════════════════════════════════════════════════════════════════════════
class AppTextField extends StatefulWidget {
  final String? label;
  final String? value;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final String? hint;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final bool readOnly;
  final bool enabled;
  final bool isMonospace;
  final TextInputType? keyboardType;
  final TextStyle? style;
  final TextStyle? labelStyle;
  final double height;
  final int? maxLines;
  final bool autofocus;
  final FocusNode? focusNode;

  const AppTextField({
    super.key,
    this.label,
    this.value,
    this.controller,
    this.onChanged,
    this.onSubmitted,
    this.hint,
    this.prefixIcon,
    this.suffixIcon,
    this.readOnly = false,
    this.enabled = true,
    this.isMonospace = false,
    this.keyboardType,
    this.style,
    this.labelStyle,
    this.height = 34,
    this.maxLines = 1,
    this.autofocus = false,
    this.focusNode,
  });

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  TextEditingController? _internalCtrl;
  FocusNode? _internalFocusNode;
  bool _isFocused = false;

  TextEditingController get _effectiveCtrl =>
      widget.controller ?? (_internalCtrl ??= TextEditingController(text: widget.value ?? ''));

  FocusNode get _effectiveFocusNode =>
      widget.focusNode ?? (_internalFocusNode ??= FocusNode());

  @override
  void initState() {
    super.initState();
    if (widget.controller == null && widget.value != null) {
      _internalCtrl = TextEditingController(text: widget.value);
    }
    _effectiveFocusNode.addListener(_handleFocusChange);
  }

  void _handleFocusChange() {
    if (mounted) {
      setState(() => _isFocused = _effectiveFocusNode.hasFocus);
    }
  }

  @override
  void didUpdateWidget(covariant AppTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller == null && widget.value != null && widget.value != oldWidget.value) {
      if (_effectiveCtrl.text != widget.value) {
        final oldSelection = _effectiveCtrl.selection;
        _effectiveCtrl.text = widget.value!;
        if (oldSelection.start <= widget.value!.length && oldSelection.end <= widget.value!.length) {
          _effectiveCtrl.selection = oldSelection;
        } else {
          _effectiveCtrl.selection = TextSelection.collapsed(offset: widget.value!.length);
        }
      }
    }
  }

  @override
  void dispose() {
    if (widget.focusNode == null) {
      _internalFocusNode?.removeListener(_handleFocusChange);
      _internalFocusNode?.dispose();
    }
    if (widget.controller == null) {
      _internalCtrl?.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final isSingleLine = (widget.maxLines ?? 1) == 1;

    final inputWidget = Container(
      height: isSingleLine ? widget.height : null,
      constraints: !isSingleLine ? BoxConstraints(minHeight: widget.height) : null,
      alignment: isSingleLine ? Alignment.center : Alignment.topLeft,
      decoration: BoxDecoration(
        color: widget.enabled ? c.surfaceDark : c.surfaceDark.withOpacity(0.5),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: _isFocused ? c.primary : c.border,
          width: _isFocused ? 1.0 : 0.8,
        ),
      ),
      child: TextField(
        controller: _effectiveCtrl,
        focusNode: _effectiveFocusNode,
        readOnly: widget.readOnly,
        enabled: widget.enabled,
        autofocus: widget.autofocus,
        maxLines: widget.maxLines,
        keyboardType: widget.keyboardType,
        textAlignVertical: isSingleLine ? TextAlignVertical.center : TextAlignVertical.top,
        cursorColor: c.primary,
        cursorHeight: 14,
        style: widget.style ??
            TextStyle(
              fontSize: 11.5,
              color: widget.enabled ? c.textPrimary : c.textMuted,
              fontWeight: FontWeight.w400,
              fontFamily: widget.isMonospace ? 'monospace' : null,
              height: 1.0,
            ),
        strutStyle: const StrutStyle(
          fontSize: 11.5,
          height: 1.0,
          forceStrutHeight: true,
        ),
        decoration: InputDecoration(
          isDense: true,
          filled: false,
          hintText: widget.hint,
          hintStyle: TextStyle(
            color: c.textMuted,
            fontSize: 11,
            height: 1.0,
            fontFamily: widget.isMonospace ? 'monospace' : null,
          ),
          contentPadding: EdgeInsets.symmetric(
            horizontal: 10,
            vertical: isSingleLine ? 0 : 8,
          ),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          prefixIcon: widget.prefixIcon != null
              ? Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: widget.prefixIcon,
                )
              : null,
          prefixIconConstraints: BoxConstraints(minWidth: 30, minHeight: widget.height),
          suffixIcon: widget.suffixIcon != null
              ? Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: widget.suffixIcon,
                )
              : null,
          suffixIconConstraints: BoxConstraints(minWidth: 30, minHeight: widget.height),
        ),
        onChanged: widget.onChanged,
        onSubmitted: widget.onSubmitted,
      ),
    );

    if (widget.label == null || widget.label!.isEmpty) {
      return inputWidget;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          widget.label!,
          style: widget.labelStyle ??
              TextStyle(
                fontSize: 11,
                color: c.textSecondary,
                fontWeight: FontWeight.w500,
              ),
        ),
        const SizedBox(height: 5),
        inputWidget,
      ],
    );
  }
}

/// ═══════════════════════════════════════════════════════════════════════════
/// ── 🔗 APP INPUT GROUP (SEAMLESS TEXTFIELD + ACTION BUTTON) ────────────────
/// ═══════════════════════════════════════════════════════════════════════════
class AppInputGroup extends StatelessWidget {
  final String? label;
  final Widget field;
  final Widget button;
  final double spacing;
  final TextStyle? labelStyle;

  const AppInputGroup({
    super.key,
    this.label,
    required this.field,
    required this.button,
    this.spacing = 8,
    this.labelStyle,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(child: field),
        SizedBox(width: spacing),
        button,
      ],
    );

    if (label == null || label!.isEmpty) {
      return row;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label!,
          style: labelStyle ??
              TextStyle(
                fontSize: 11,
                color: c.textSecondary,
                fontWeight: FontWeight.w500,
              ),
        ),
        const SizedBox(height: 5),
        row,
      ],
    );
  }
}

/// ═══════════════════════════════════════════════════════════════════════════
/// ── 🔑 APP PASSWORD / API KEY FIELD (PERFECT VERTICAL ALIGNMENT) ────────────
/// ═══════════════════════════════════════════════════════════════════════════
class AppPasswordField extends StatefulWidget {
  final String? label;
  final String value;
  final ValueChanged<String> onChanged;
  final String? hint;
  final TextStyle? labelStyle;
  final double height;

  const AppPasswordField({
    super.key,
    this.label,
    required this.value,
    required this.onChanged,
    this.hint = 'Nhập API key...',
    this.labelStyle,
    this.height = 34,
  });

  @override
  State<AppPasswordField> createState() => _AppPasswordFieldState();
}

class _AppPasswordFieldState extends State<AppPasswordField> {
  late TextEditingController _ctrl;
  final FocusNode _focusNode = FocusNode();
  bool _isFocused = false;
  bool _obscured = true;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.value);
    _focusNode.addListener(() {
      if (mounted) setState(() => _isFocused = _focusNode.hasFocus);
    });
  }

  @override
  void didUpdateWidget(covariant AppPasswordField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value && _ctrl.text != widget.value) {
      final oldSelection = _ctrl.selection;
      _ctrl.text = widget.value;
      if (oldSelection.start <= widget.value.length && oldSelection.end <= widget.value.length) {
        _ctrl.selection = oldSelection;
      } else {
        _ctrl.selection = TextSelection.collapsed(offset: widget.value.length);
      }
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final inputWidget = Container(
      height: widget.height,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c.surfaceDark,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: _isFocused ? c.primary : c.border,
          width: _isFocused ? 1.0 : 0.8,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: TextField(
              controller: _ctrl,
              focusNode: _focusNode,
              obscureText: _obscured,
              textAlignVertical: TextAlignVertical.center,
              cursorColor: c.primary,
              cursorHeight: 14,
              style: TextStyle(
                fontSize: 11.5,
                color: c.textPrimary,
                fontWeight: FontWeight.w400,
                letterSpacing: _obscured ? 2.0 : 0.0,
                height: 1.0,
              ),
              strutStyle: const StrutStyle(
                fontSize: 11.5,
                height: 1.0,
                forceStrutHeight: true,
              ),
              decoration: InputDecoration(
                isDense: true,
                filled: false,
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                hintText: widget.hint,
                hintStyle: TextStyle(
                  color: c.textMuted,
                  fontSize: 11,
                  letterSpacing: 0.0,
                  height: 1.0,
                ),
              ),
              onChanged: widget.onChanged,
            ),
          ),
          SizedBox(
            width: 30,
            height: widget.height,
            child: IconButton(
              padding: EdgeInsets.zero,
              splashRadius: 14,
              icon: Icon(
                _obscured ? Icons.visibility : Icons.visibility_off,
                size: 15,
                color: c.textSecondary,
              ),
              tooltip: _obscured ? 'Hiện API Key' : 'Ẩn API Key',
              onPressed: () => setState(() => _obscured = !_obscured),
            ),
          ),
        ],
      ),
    );

    if (widget.label == null || widget.label!.isEmpty) {
      return inputWidget;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          widget.label!,
          style: widget.labelStyle ??
              TextStyle(
                fontSize: 11,
                color: c.textSecondary,
                fontWeight: FontWeight.w500,
              ),
        ),
        const SizedBox(height: 5),
        inputWidget,
      ],
    );
  }
}

/// ═══════════════════════════════════════════════════════════════════════════
/// ── 🔽 APP DROPDOWN (UNIFIED 34PX / 28PX) ──────────────────────────────────
/// ═══════════════════════════════════════════════════════════════════════════
class AppDropdown<T> extends StatelessWidget {
  final String? label;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  final TextStyle? labelStyle;
  final double height;

  const AppDropdown({
    super.key,
    this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.labelStyle,
    this.height = 34,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final dropdownWidget = Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c.surfaceDark,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: c.border, width: 0.8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          dropdownColor: c.surface,
          style: TextStyle(fontSize: 11.5, color: c.textPrimary),
          icon: Icon(Icons.arrow_drop_down, size: 16, color: c.textSecondary),
          items: items,
          onChanged: onChanged,
        ),
      ),
    );

    if (label == null || label!.isEmpty) {
      return dropdownWidget;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label!,
          style: labelStyle ??
              TextStyle(
                fontSize: 11,
                color: c.textSecondary,
                fontWeight: FontWeight.w500,
              ),
        ),
        const SizedBox(height: 5),
        dropdownWidget,
      ],
    );
  }
}

/// ═══════════════════════════════════════════════════════════════════════════
/// ── ☑️ APP CHECKBOX & CHECKBOX ROW (DESKTOP OPTIMIZED) ─────────────────────
/// ═══════════════════════════════════════════════════════════════════════════
class AppCheckbox extends StatelessWidget {
  final bool value;
  final ValueChanged<bool?>? onChanged;
  final Color? activeColor;
  final Color? checkColor;
  final double size;

  const AppCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
    this.activeColor,
    this.checkColor,
    this.size = 18,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final effectiveActiveColor = activeColor ?? c.primary;
    final effectiveCheckColor = checkColor ?? c.primaryText;

    return MouseRegion(
      cursor: onChanged != null ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: onChanged != null ? () => onChanged!(!value) : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: value ? effectiveActiveColor : c.surfaceDark,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: value ? effectiveActiveColor : c.border,
              width: 1.0,
            ),
          ),
          alignment: Alignment.center,
          child: value
              ? Icon(
                  Icons.check,
                  size: size - 4,
                  color: effectiveCheckColor,
                )
              : null,
        ),
      ),
    );
  }
}

class AppCheckboxRow extends StatelessWidget {
  final String label;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool?>? onChanged;
  final Color? activeColor;
  final TextStyle? labelStyle;

  const AppCheckboxRow({
    super.key,
    required this.label,
    this.subtitle,
    required this.value,
    required this.onChanged,
    this.activeColor,
    this.labelStyle,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: MouseRegion(
        cursor: onChanged != null ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: GestureDetector(
          onTap: onChanged != null ? () => onChanged!(!value) : null,
          behavior: HitTestBehavior.opaque,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              AppCheckbox(
                value: value,
                onChanged: onChanged,
                activeColor: activeColor,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: labelStyle ??
                          TextStyle(
                            color: value ? c.textPrimary : c.textSecondary,
                            fontSize: 11.5,
                            fontWeight: value ? FontWeight.w600 : FontWeight.w400,
                          ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 1),
                      Text(
                        subtitle!,
                        style: TextStyle(color: c.textMuted, fontSize: 10),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// ═══════════════════════════════════════════════════════════════════════════
/// ── 🔍 APP SEARCH FIELD (28PX TOOLBAR) ─────────────────────────────────────
/// ═══════════════════════════════════════════════════════════════════════════
class AppSearchField extends StatefulWidget {
  final String? hint;
  final String? initialValue;
  final ValueChanged<String> onChanged;
  final VoidCallback? onClear;
  final double height;
  final double? width;

  const AppSearchField({
    super.key,
    this.hint = 'Tìm kiếm...',
    this.initialValue,
    required this.onChanged,
    this.onClear,
    this.height = 28,
    this.width,
  });

  @override
  State<AppSearchField> createState() => _AppSearchFieldState();
}

class _AppSearchFieldState extends State<AppSearchField> {
  late TextEditingController _ctrl;
  final FocusNode _focusNode = FocusNode();
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialValue ?? '');
    _focusNode.addListener(() {
      if (mounted) setState(() => _isFocused = _focusNode.hasFocus);
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final hasText = _ctrl.text.isNotEmpty;

    return Container(
      width: widget.width,
      height: widget.height,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c.surfaceDark,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: _isFocused ? c.primary : c.border,
          width: _isFocused ? 1.0 : 0.8,
        ),
      ),
      child: TextField(
        controller: _ctrl,
        focusNode: _focusNode,
        textAlignVertical: TextAlignVertical.center,
        cursorColor: c.primary,
        cursorHeight: 13,
        style: TextStyle(fontSize: 11, color: c.textPrimary, height: 1.0),
        strutStyle: const StrutStyle(fontSize: 11, height: 1.0, forceStrutHeight: true),
        decoration: InputDecoration(
          isDense: true,
          filled: false,
          hintText: widget.hint,
          hintStyle: TextStyle(color: c.textMuted, fontSize: 10.5, height: 1.0),
          prefixIcon: Icon(Icons.search, size: 13, color: _isFocused ? c.primary : c.textMuted),
          prefixIconConstraints: BoxConstraints(minWidth: 26, minHeight: widget.height),
          suffixIcon: hasText
              ? SizedBox(
                  width: 24,
                  height: widget.height,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    icon: Icon(Icons.close, size: 12, color: c.textMuted),
                    onPressed: () {
                      _ctrl.clear();
                      widget.onChanged('');
                      widget.onClear?.call();
                      setState(() {});
                    },
                  ),
                )
              : null,
          suffixIconConstraints: BoxConstraints(minWidth: 24, minHeight: widget.height),
          contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
        ),
        onChanged: (val) {
          widget.onChanged(val);
          setState(() {});
        },
      ),
    );
  }
}
