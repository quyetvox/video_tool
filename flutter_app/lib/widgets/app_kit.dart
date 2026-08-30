import 'package:flutter/material.dart';
import '../core/app_colors.dart';

// Export AppInputFields for backwards compatibility
export 'app_input_fields.dart';

/// ═══════════════════════════════════════════════════════════════════════════
/// ── 🔘 APP BUTTON SYSTEM (UNIFIED 28PX - 34PX) ─────────────────────────────
/// ═══════════════════════════════════════════════════════════════════════════

enum AppButtonVariant {
  primary,
  secondary,
  outlined,
  success,
  danger,
  ghost,
}

class AppButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final double height;
  final double? width;
  final bool isLoading;
  final double fontSize;
  final EdgeInsetsGeometry? padding;

  const AppButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.variant = AppButtonVariant.primary,
    this.height = 34,
    this.width,
    this.isLoading = false,
    this.fontSize = 11.5,
    this.padding,
  });

  const AppButton.primary({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.height = 34,
    this.width,
    this.isLoading = false,
    this.fontSize = 11.5,
    this.padding,
  }) : variant = AppButtonVariant.primary;

  const AppButton.secondary({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.height = 34,
    this.width,
    this.isLoading = false,
    this.fontSize = 11.5,
    this.padding,
  }) : variant = AppButtonVariant.secondary;

  const AppButton.outlined({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.height = 34,
    this.width,
    this.isLoading = false,
    this.fontSize = 11.5,
    this.padding,
  }) : variant = AppButtonVariant.outlined;

  const AppButton.success({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.height = 34,
    this.width,
    this.isLoading = false,
    this.fontSize = 11.5,
    this.padding,
  }) : variant = AppButtonVariant.success;

  const AppButton.danger({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.height = 34,
    this.width,
    this.isLoading = false,
    this.fontSize = 11.5,
    this.padding,
  }) : variant = AppButtonVariant.danger;

  const AppButton.ghost({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.height = 34,
    this.width,
    this.isLoading = false,
    this.fontSize = 11.5,
    this.padding,
  }) : variant = AppButtonVariant.ghost;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    Color bg;
    Color fg;
    BorderSide borderSide = BorderSide.none;

    switch (variant) {
      case AppButtonVariant.primary:
        bg = c.primary;
        fg = c.primaryText;
        break;
      case AppButtonVariant.secondary:
        bg = c.primary.withOpacity(0.15);
        fg = c.primary;
        borderSide = BorderSide(color: c.primary, width: 0.8);
        break;
      case AppButtonVariant.outlined:
        bg = c.surfaceDark;
        fg = c.textLight;
        borderSide = BorderSide(color: c.border, width: 0.8);
        break;
      case AppButtonVariant.success:
        bg = c.statusCompleted;
        fg = Colors.black;
        break;
      case AppButtonVariant.danger:
        bg = c.statusFailedBg;
        fg = c.statusFailed;
        borderSide = BorderSide(color: c.statusFailed, width: 0.8);
        break;
      case AppButtonVariant.ghost:
        bg = Colors.transparent;
        fg = c.textSecondary;
        break;
    }

    final btnStyle = ElevatedButton.styleFrom(
      backgroundColor: bg,
      foregroundColor: fg,
      disabledBackgroundColor: bg.withOpacity(0.4),
      disabledForegroundColor: fg.withOpacity(0.4),
      elevation: 0,
      padding: padding ?? const EdgeInsets.symmetric(horizontal: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: borderSide,
      ),
      minimumSize: Size(width ?? 0, height),
    );

    final labelWidget = isLoading
        ? SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 1.8,
              color: fg,
            ),
          )
        : Text(
            label,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w600,
              color: fg,
              height: 1.0,
            ),
          );

    return SizedBox(
      height: height,
      width: width,
      child: icon != null && !isLoading
          ? ElevatedButton.icon(
              style: btnStyle,
              icon: Icon(icon, size: fontSize + 2.5, color: fg),
              label: labelWidget,
              onPressed: isLoading ? null : onPressed,
            )
          : ElevatedButton(
              style: btnStyle,
              onPressed: isLoading ? null : onPressed,
              child: labelWidget,
            ),
    );
  }
}

/// ═══════════════════════════════════════════════════════════════════════════
/// ── 🔍 APP SEARCH FIELD (30PX HEIGHT, UNIFIED) ─────────────────────────────
/// ═══════════════════════════════════════════════════════════════════════════
class AppSearchField extends StatelessWidget {
  final String hint;
  final ValueChanged<String> onChanged;
  final double height;
  final double? width;
  final TextEditingController? controller;

  const AppSearchField({
    super.key,
    this.hint = 'Tìm kiếm...',
    required this.onChanged,
    this.height = 30,
    this.width,
    this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return SizedBox(
      width: width,
      height: height,
      child: TextField(
        controller: controller,
        textAlignVertical: TextAlignVertical.center,
        cursorColor: c.primary,
        style: TextStyle(fontSize: 11.5, color: c.textPrimary, height: 1.0),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: c.textMuted, fontSize: 11, height: 1.0),
          prefixIcon: Icon(Icons.search, size: 14, color: c.textMuted),
          prefixIconConstraints: const BoxConstraints(minWidth: 28, minHeight: 30),
          contentPadding: EdgeInsets.zero,
          filled: true,
          fillColor: c.surfaceDark,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(color: c.border, width: 0.8),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(color: c.border, width: 0.8),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(color: c.primary, width: 1.0),
          ),
        ),
        onChanged: onChanged,
      ),
    );
  }
}

/// ═══════════════════════════════════════════════════════════════════════════
/// ── 🎚️ APP SLIDER ROW ──────────────────────────────────────────────────────
/// ═══════════════════════════════════════════════════════════════════════════
class AppSliderRow extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final String Function(double)? formatValue;

  const AppSliderRow({
    super.key,
    required this.label,
    required this.value,
    this.min = 0.0,
    this.max = 1.0,
    required this.onChanged,
    this.formatValue,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final displayVal = formatValue != null ? formatValue!(value) : value.toStringAsFixed(2);

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: c.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                displayVal,
                style: TextStyle(
                  color: c.primary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 2.5,
              activeTrackColor: c.primary,
              inactiveTrackColor: c.surfaceLight,
              thumbColor: c.primary,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4.5),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 8),
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

/// ═══════════════════════════════════════════════════════════════════════════
/// ── 🔘 APP TOGGLE ROW ──────────────────────────────────────────────────────
/// ═══════════════════════════════════════════════════════════════════════════
class AppToggleRow extends StatelessWidget {
  final String label;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const AppToggleRow({
    super.key,
    required this.label,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: c.textLight,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      color: c.textMuted,
                      fontSize: 10.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Transform.scale(
            scale: 0.75,
            child: Switch(
              value: value,
              activeColor: c.primary,
              activeTrackColor: c.primary.withOpacity(0.35),
              inactiveThumbColor: c.textMuted,
              inactiveTrackColor: c.surfaceLight,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

/// ═══════════════════════════════════════════════════════════════════════════
/// ── 🗂️ APP SECTION CARD ────────────────────────────────────────────────────
/// ═══════════════════════════════════════════════════════════════════════════
class AppSectionCard extends StatelessWidget {
  final String title;
  final IconData? icon;
  final Widget? trailing;
  final List<Widget> children;
  final EdgeInsetsGeometry padding;

  const AppSectionCard({
    super.key,
    required this.title,
    this.icon,
    this.trailing,
    required this.children,
    this.padding = const EdgeInsets.all(12),
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: c.border, width: 0.8),
      ),
      color: c.surface,
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, color: c.primary, size: 16),
                  const SizedBox(width: 8),
                ] else ...[
                  Container(
                    width: 3,
                    height: 13,
                    decoration: BoxDecoration(
                      color: c.primary,
                      borderRadius: BorderRadius.circular(1.5),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: c.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// ═══════════════════════════════════════════════════════════════════════════
/// ── 🏷️ APP STATUS BADGE ────────────────────────────────────────────────────
/// ═══════════════════════════════════════════════════════════════════════════
enum AppStatusType { running, completed, failed, pending, idle }

class AppStatusBadge extends StatelessWidget {
  final String label;
  final AppStatusType type;
  final IconData? icon;

  const AppStatusBadge({
    super.key,
    required this.label,
    this.type = AppStatusType.idle,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    Color bg;
    Color fg;

    switch (type) {
      case AppStatusType.running:
        bg = c.statusProcessingBg;
        fg = c.statusProcessing;
        break;
      case AppStatusType.completed:
        bg = c.statusCompletedBg;
        fg = c.statusCompleted;
        break;
      case AppStatusType.failed:
        bg = c.statusFailedBg;
        fg = c.statusFailed;
        break;
      case AppStatusType.pending:
        bg = c.primary.withOpacity(0.15);
        fg = c.primary;
        break;
      case AppStatusType.idle:
        bg = c.surfaceLight;
        fg = c.textMuted;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: fg.withOpacity(0.3), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: fg),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: fg,
              height: 1.0,
            ),
          ),
        ],
      ),
    );
  }
}
