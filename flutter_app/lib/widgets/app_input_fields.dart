import 'package:flutter/material.dart';
import '../core/app_colors.dart';

/// ── 🏷️ APP SECTION HEADER ──────────────────────────────────────────────────
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

/// ── 📝 APP TEXT FIELD (CONTROLLED 34PX) ─────────────────────────────────────
class AppTextField extends StatefulWidget {
  final String? label;
  final String value;
  final ValueChanged<String> onChanged;
  final String? hint;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final bool readOnly;
  final TextInputType? keyboardType;
  final TextStyle? style;
  final TextStyle? labelStyle;

  const AppTextField({
    super.key,
    this.label,
    required this.value,
    required this.onChanged,
    this.hint,
    this.prefixIcon,
    this.suffixIcon,
    this.readOnly = false,
    this.keyboardType,
    this.style,
    this.labelStyle,
  });

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  late TextEditingController _ctrl;
  final FocusNode _focusNode = FocusNode();
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.value);
    _focusNode.addListener(() {
      setState(() => _isFocused = _focusNode.hasFocus);
    });
  }

  @override
  void didUpdateWidget(covariant AppTextField oldWidget) {
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
      height: 34,
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
        readOnly: widget.readOnly,
        keyboardType: widget.keyboardType,
        textAlignVertical: TextAlignVertical.center,
        cursorColor: c.primary,
        style: widget.style ??
            TextStyle(
              fontSize: 11.5,
              color: c.textPrimary,
              fontWeight: FontWeight.w400,
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
          hintStyle: TextStyle(color: c.textMuted, fontSize: 11, height: 1.0),
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          prefixIcon: widget.prefixIcon != null
              ? Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: widget.prefixIcon,
                )
              : null,
          prefixIconConstraints: const BoxConstraints(minWidth: 32, minHeight: 34),
          suffixIcon: widget.suffixIcon != null
              ? Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: widget.suffixIcon,
                )
              : null,
          suffixIconConstraints: const BoxConstraints(minWidth: 32, minHeight: 34),
        ),
        onChanged: widget.onChanged,
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

/// ── 🔑 APP PASSWORD / API KEY FIELD (PERFECT VERTICAL ALIGNMENT) ────────────
class AppPasswordField extends StatefulWidget {
  final String? label;
  final String value;
  final ValueChanged<String> onChanged;
  final String? hint;
  final TextStyle? labelStyle;

  const AppPasswordField({
    super.key,
    this.label,
    required this.value,
    required this.onChanged,
    this.hint = 'Nhập API key...',
    this.labelStyle,
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
      setState(() => _isFocused = _focusNode.hasFocus);
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
      height: 34,
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
            height: 30,
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

/// ── 🔽 APP DROPDOWN (34PX) ─────────────────────────────────────────────────
class AppDropdown<T> extends StatelessWidget {
  final String? label;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  final TextStyle? labelStyle;

  const AppDropdown({
    super.key,
    this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.labelStyle,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final dropdownWidget = Container(
      height: 34,
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
