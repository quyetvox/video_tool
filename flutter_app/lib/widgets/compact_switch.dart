import 'package:flutter/material.dart';
import '../core/app_colors.dart';

/// Compact, modern desktop switch for Sub-Video UI.
/// Clicking anywhere outside the switch does not trigger it.
class CompactSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  final Color activeColor;

  const CompactSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.activeColor = AppColors.primary,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onChanged(!value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeInOut,
          width: 32,
          height: 18,
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(9),
            color: value ? activeColor : AppColors.surfaceDark,
            border: Border.all(
              color: value ? activeColor : AppColors.border,
              width: 1,
            ),
          ),
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeInOut,
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: value ? AppColors.primaryText : AppColors.textSecondary,
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 2,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
