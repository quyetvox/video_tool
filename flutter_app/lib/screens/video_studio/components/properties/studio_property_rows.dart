import 'package:flutter/material.dart';
import '../../../../core/app_colors.dart';
import '../../../../widgets/compact_switch.dart';

/// Section header with primary brand accent for Studio Properties.
class StudioSectionHeader extends StatelessWidget {
  final String title;

  const StudioSectionHeader(this.title, {super.key});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(
        title,
        style: TextStyle(
          color: c.primary,
          fontSize: 10.5,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

/// Toggle switch row with label and optional subtitle.
class StudioToggleRow extends StatelessWidget {
  final String label;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const StudioToggleRow({
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
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(color: c.textPrimary, fontSize: 10.5, fontWeight: FontWeight.w500),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 1),
                  Text(subtitle!, style: TextStyle(color: c.textMuted, fontSize: 9)),
                ],
              ],
            ),
          ),
          CompactSwitch(
            value: value,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

/// Slider row with live value display and min/max clamp.
class StudioSliderRow extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final String Function(double)? format;

  const StudioSliderRow({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.format,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final clampedVal = value.clamp(min, max);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: TextStyle(color: c.textSecondary, fontSize: 10)),
              Text(
                format != null ? format!(clampedVal) : clampedVal.toStringAsFixed(1),
                style: TextStyle(color: c.primary, fontSize: 10, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
            ),
            child: Slider(
              value: clampedVal,
              min: min,
              max: max,
              activeColor: c.primary,
              inactiveColor: c.surfaceDark,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

/// Dropdown row with label and styled dark container.
class StudioDropdownRow<T> extends StatelessWidget {
  final String label;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  const StudioDropdownRow({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: c.textSecondary, fontSize: 10)),
          const SizedBox(height: 3),
          Container(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: c.surfaceDark,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: c.border),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<T>(
                value: value,
                isExpanded: true,
                dropdownColor: c.surface,
                style: TextStyle(color: c.textPrimary, fontSize: 10.5),
                items: items,
                onChanged: onChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
