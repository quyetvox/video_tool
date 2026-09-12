import 'package:flutter/material.dart';
import '../../../core/app_colors.dart';
import '../../../widgets/app_kit.dart';
import '../../../widgets/compact_switch.dart';

/// Standard 2-column responsive layout helper for settings rows
class ConfigRow2 extends StatelessWidget {
  final Widget w1;
  final Widget w2;

  const ConfigRow2({super.key, required this.w1, required this.w2});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: w1),
        const SizedBox(width: 14),
        Expanded(child: w2),
      ],
    );
  }
}

/// Standardized text input field with dark theme styling
class ConfigTextField extends StatelessWidget {
  final String label;
  final String value;
  final ValueChanged<String> onChanged;
  final String? placeholder;

  const ConfigTextField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.placeholder,
  });

  @override
  Widget build(BuildContext context) {
    return AppTextField(
      label: label,
      value: value,
      hint: placeholder ?? '',
      onChanged: onChanged,
    );
  }
}

/// Standardized password/API key field with obscuring
class ConfigPasswordField extends StatelessWidget {
  final String label;
  final String value;
  final ValueChanged<String> onChanged;

  const ConfigPasswordField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return AppPasswordField(
      label: label,
      value: value,
      onChanged: onChanged,
    );
  }
}

/// Standardized dropdown selector
class ConfigDropdown extends StatelessWidget {
  final String label;
  final String value;
  final List<String> options;
  final ValueChanged<String?> onChanged;

  const ConfigDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final safeValue = options.contains(value) ? value : (options.isNotEmpty ? options.first : '');
    return AppDropdown<String>(
      label: label,
      value: safeValue,
      items: options.map((opt) => DropdownMenuItem(value: opt, child: Text(opt))).toList(),
      onChanged: onChanged,
    );
  }
}

/// Worker / concurrency dropdown with hardware hints
class ConfigWorkerDropdown extends StatelessWidget {
  final String label;
  final int value;
  final int maxWorkers;
  final String hardwareHint;
  final ValueChanged<int> onChanged;

  const ConfigWorkerDropdown({
    super.key,
    required this.label,
    required this.value,
    this.maxWorkers = 8,
    required this.hardwareHint,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final clamped = value.clamp(1, maxWorkers);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label, style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.w500)),
            const Spacer(),
            Text(hardwareHint, style: TextStyle(color: c.textMuted, fontSize: 10)),
          ],
        ),
        const SizedBox(height: 5),
        AppDropdown<int>(
          value: clamped,
          items: List.generate(maxWorkers, (i) => i + 1).map((w) {
            return DropdownMenuItem(
              value: w,
              child: Text(
                '$w worker${w > 1 ? 's' : ''} ${w == 1 ? '(Tuần tự - An toàn)' : w <= 3 ? '(Khuyến nghị)' : '(Tối đa)'}',
                style: TextStyle(
                  color: w <= 3 ? c.textPrimary : c.warning,
                  fontWeight: w <= 3 ? FontWeight.normal : FontWeight.bold,
                ),
              ),
            );
          }).toList(),
          onChanged: (val) {
            if (val != null) onChanged(val);
          },
        ),
      ],
    );
  }
}

/// Slider control with numeric label
class ConfigSlider extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final String displayValue;
  final ValueChanged<double> onChanged;

  const ConfigSlider({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    this.divisions,
    required this.displayValue,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label, style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.w500)),
            const Spacer(),
            Text(displayValue, style: TextStyle(color: c.primary, fontSize: 11, fontWeight: FontWeight.bold)),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: c.primary,
            inactiveTrackColor: c.border,
            thumbColor: c.primary,
            overlayColor: c.primary.withOpacity(0.2),
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
          ),
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

/// Compact toggle row with label and optional subtitle
class ConfigToggle extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final String? subtitle;

  const ConfigToggle({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.subtitle,
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
              children: [
                Text(label, style: TextStyle(color: c.textPrimary, fontSize: 11.5, fontWeight: FontWeight.w500)),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!, style: TextStyle(color: c.textMuted, fontSize: 10)),
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
