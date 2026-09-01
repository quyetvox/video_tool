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
  accent,
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
  final BorderRadius? borderRadius;

  const AppButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.variant = AppButtonVariant.primary,
    this.height = 28,
    this.width,
    this.isLoading = false,
    this.fontSize = 11.0,
    this.padding,
    this.borderRadius,
  });

  const AppButton.primary({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.height = 28,
    this.width,
    this.isLoading = false,
    this.fontSize = 11.0,
    this.padding,
    this.borderRadius,
  }) : variant = AppButtonVariant.primary;

  const AppButton.secondary({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.height = 28,
    this.width,
    this.isLoading = false,
    this.fontSize = 11.0,
    this.padding,
    this.borderRadius,
  }) : variant = AppButtonVariant.secondary;

  const AppButton.outlined({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.height = 28,
    this.width,
    this.isLoading = false,
    this.fontSize = 11.0,
    this.padding,
    this.borderRadius,
  }) : variant = AppButtonVariant.outlined;

  const AppButton.success({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.height = 28,
    this.width,
    this.isLoading = false,
    this.fontSize = 11.0,
    this.padding,
    this.borderRadius,
  }) : variant = AppButtonVariant.success;

  const AppButton.danger({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.height = 28,
    this.width,
    this.isLoading = false,
    this.fontSize = 11.0,
    this.padding,
    this.borderRadius,
  }) : variant = AppButtonVariant.danger;

  const AppButton.ghost({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.height = 28,
    this.width,
    this.isLoading = false,
    this.fontSize = 11.0,
    this.padding,
    this.borderRadius,
  }) : variant = AppButtonVariant.ghost;

  const AppButton.accent({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.height = 28,
    this.width,
    this.isLoading = false,
    this.fontSize = 11.0,
    this.padding,
    this.borderRadius,
  }) : variant = AppButtonVariant.accent;

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
        borderSide = BorderSide(color: c.primary.withOpacity(0.6), width: 0.8);
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
      case AppButtonVariant.accent:
        bg = const Color(0xFFA855F7).withOpacity(0.18);
        fg = const Color(0xFFC084FC);
        borderSide = const BorderSide(color: Color(0xFFA855F7), width: 0.8);
        break;
    }

    final radius = borderRadius ?? BorderRadius.circular(6);

    final btnStyle = ElevatedButton.styleFrom(
      backgroundColor: bg,
      foregroundColor: fg,
      disabledBackgroundColor: bg.withOpacity(0.4),
      disabledForegroundColor: fg.withOpacity(0.4),
      elevation: 0,
      padding: padding ?? const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: borderSide,
      ),
      minimumSize: Size(width ?? 0, height),
    );

    final labelWidget = isLoading
        ? SizedBox(
            width: 13,
            height: 13,
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
              icon: Icon(icon, size: fontSize + 2.0, color: fg),
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
/// ── 🔀 APP SEGMENT BUTTON (TOOLBAR MODE & TAB SWITCHER) ────────────────────
/// ═══════════════════════════════════════════════════════════════════════════
class AppSegmentButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool isSelected;
  final Color? activeColor;
  final VoidCallback onTap;
  final double height;
  final EdgeInsetsGeometry? padding;
  final String? shortcutKey;

  const AppSegmentButton({
    super.key,
    required this.label,
    this.icon,
    required this.isSelected,
    this.activeColor,
    required this.onTap,
    this.height = 28,
    this.padding,
    this.shortcutKey,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final accent = activeColor ?? c.primary;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        height: height,
        padding: padding ?? const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? accent.withOpacity(0.18) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: isSelected ? Border.all(color: accent, width: 0.8) : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 13,
                color: isSelected ? accent : c.textSecondary,
              ),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : c.textSecondary,
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                height: 1.0,
              ),
            ),
            if (shortcutKey != null) ...[
              const SizedBox(width: 4),
              Text(
                shortcutKey!,
                style: TextStyle(
                  color: isSelected ? accent.withOpacity(0.85) : c.textMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  height: 1.0,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// ═══════════════════════════════════════════════════════════════════════════
/// ── ⚡ APP ACTION BUTTON (COLOR OUTLINE & TINT PILL) ────────────────────────
/// ═══════════════════════════════════════════════════════════════════════════
class AppActionButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color color;
  final VoidCallback? onPressed;
  final double height;
  final double? width;
  final bool isFullWidth;
  final bool isFilled;
  final double fontSize;
  final EdgeInsetsGeometry? padding;

  const AppActionButton({
    super.key,
    required this.label,
    this.icon,
    required this.color,
    this.onPressed,
    this.height = 28,
    this.width,
    this.isFullWidth = false,
    this.isFilled = false,
    this.fontSize = 11.0,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final bg = isFilled ? color : color.withOpacity(0.12);
    final fg = isFilled ? Colors.white : color;

    final btn = OutlinedButton.styleFrom(
      backgroundColor: bg,
      foregroundColor: fg,
      side: BorderSide(color: color.withOpacity(0.6), width: 0.8),
      padding: padding ?? const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      minimumSize: Size(isFullWidth ? double.infinity : (width ?? 0), height),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      elevation: 0,
    );

    final textWidget = Text(
      label,
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: FontWeight.bold,
        color: fg,
        height: 1.0,
      ),
    );

    return SizedBox(
      height: height,
      width: isFullWidth ? double.infinity : width,
      child: icon != null
          ? OutlinedButton.icon(
              style: btn,
              icon: Icon(icon, size: fontSize + 1.5, color: fg),
              label: textWidget,
              onPressed: onPressed,
            )
          : OutlinedButton(
              style: btn,
              onPressed: onPressed,
              child: textWidget,
            ),
    );
  }
}

/// ═══════════════════════════════════════════════════════════════════════════
/// ── 🏷️ APP FILTER CHIP (COMPACT PILL 24PX) ─────────────────────────────────
/// ═══════════════════════════════════════════════════════════════════════════
class AppFilterChip extends StatelessWidget {
  final String label;
  final int? count;
  final bool isSelected;
  final VoidCallback onTap;
  final Color? color;
  final double height;

  const AppFilterChip({
    super.key,
    required this.label,
    this.count,
    required this.isSelected,
    required this.onTap,
    this.color,
    this.height = 24,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final chipColor = color ?? c.primary;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: isSelected ? chipColor.withOpacity(0.18) : c.surfaceDark,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isSelected ? chipColor : c.border,
            width: 0.8,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              label,
              style: TextStyle(
                color: isSelected ? chipColor : c.textSecondary,
                fontSize: 10.5,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                height: 1.0,
              ),
            ),
            if (count != null) ...[
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: isSelected ? chipColor.withOpacity(0.3) : c.surfaceLight,
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    color: isSelected ? chipColor : c.textMuted,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    height: 1.0,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// ═══════════════════════════════════════════════════════════════════════════
/// ── 🎯 APP ICON BUTTON (STANDARDIZED MICRO ICON BUTTON) ────────────────────
/// ═══════════════════════════════════════════════════════════════════════════
class AppIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final Color? color;
  final Color? backgroundColor;
  final double size;
  final double buttonSize;
  final BorderRadius? borderRadius;
  final BorderSide? border;

  const AppIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.tooltip,
    this.color,
    this.backgroundColor,
    this.size = 14,
    this.buttonSize = 26,
    this.borderRadius,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final iconColor = color ?? c.textSecondary;
    final isEnabled = onPressed != null;

    final child = Container(
      width: buttonSize,
      height: buttonSize,
      decoration: BoxDecoration(
        color: backgroundColor ?? Colors.transparent,
        borderRadius: borderRadius ?? BorderRadius.circular(4),
        border: border != null ? Border.fromBorderSide(border!) : null,
      ),
      child: IconButton(
        icon: Icon(
          icon,
          size: size,
          color: isEnabled ? iconColor : c.textMuted.withOpacity(0.5),
        ),
        padding: EdgeInsets.zero,
        constraints: BoxConstraints(minWidth: buttonSize, minHeight: buttonSize),
        splashRadius: buttonSize / 2,
        onPressed: onPressed,
      ),
    );

    if (tooltip != null && tooltip!.isNotEmpty) {
      return Tooltip(message: tooltip!, child: child);
    }
    return child;
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
