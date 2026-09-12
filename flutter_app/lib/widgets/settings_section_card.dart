import 'package:flutter/material.dart';
import '../core/app_colors.dart';

/// Reusable Section Card used across Config Editor, Setup Screen, and Settings modals.
/// Adheres to Apple / Dark Cinematic aesthetic with subtle borders and primary accent icons.
class SettingsSectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final String? subtitle;
  final Widget? trailing;
  final List<Widget> children;
  final EdgeInsetsGeometry padding;

  const SettingsSectionCard({
    super.key,
    required this.title,
    required this.icon,
    this.subtitle,
    this.trailing,
    required this.children,
    this.padding = const EdgeInsets.all(14),
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);

    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.border, width: 0.8),
      ),
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Row
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: c.primary.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Icon(icon, color: c.primary, size: 15),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: c.textPrimary,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 1),
                        Text(
                          subtitle!,
                          style: TextStyle(
                            fontSize: 11,
                            color: c.textMuted,
                          ),
                        ),
                      ],
                    ],
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
