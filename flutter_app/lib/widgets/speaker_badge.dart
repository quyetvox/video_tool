import 'package:flutter/material.dart';

/// Reusable Speaker Badge used across Video Studio, Subtitle Editor and inspectors.
/// Displays speaker persona with gender-aware colors and click-to-toggle capability.
class SpeakerBadgeWidget extends StatelessWidget {
  final String speaker;
  final String gender;
  final VoidCallback? onTap;
  final String? tooltip;
  final EdgeInsetsGeometry? margin;
  final double fontSize;

  const SpeakerBadgeWidget({
    super.key,
    required this.speaker,
    this.gender = '',
    this.onTap,
    this.tooltip,
    this.margin,
    this.fontSize = 9.5,
  });

  @override
  Widget build(BuildContext context) {
    final rawSpeaker = speaker.trim();
    final rawGender = gender.trim().toLowerCase();

    final isMale = rawSpeaker.toLowerCase() == 'nam' ||
        rawSpeaker.toLowerCase() == 'male' ||
        rawGender == 'male';
    final isFemale = rawSpeaker.toLowerCase() == 'nữ' ||
        rawSpeaker.toLowerCase() == 'nu' ||
        rawSpeaker.toLowerCase() == 'female' ||
        rawGender == 'female';

    final String label;
    final Color color;
    final Color bgColor;
    final Color borderColor;

    if (isMale) {
      label = '👨 Nam';
      color = const Color(0xFF38BDF8);
      bgColor = const Color(0xFF38BDF8).withOpacity(0.15);
      borderColor = const Color(0xFF38BDF8).withOpacity(0.4);
    } else if (isFemale) {
      label = '👩 Nữ';
      color = const Color(0xFFF472B6);
      bgColor = const Color(0xFFF472B6).withOpacity(0.15);
      borderColor = const Color(0xFFF472B6).withOpacity(0.4);
    } else if (rawSpeaker.isNotEmpty) {
      label = '👤 $rawSpeaker';
      color = const Color(0xFFA78BFA);
      bgColor = const Color(0xFFA78BFA).withOpacity(0.15);
      borderColor = const Color(0xFFA78BFA).withOpacity(0.4);
    } else {
      label = '👤 Mặc định';
      color = const Color(0xFF94A3B8);
      bgColor = const Color(0xFF94A3B8).withOpacity(0.12);
      borderColor = const Color(0xFF94A3B8).withOpacity(0.3);
    }

    final badge = Container(
      margin: margin ?? const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: borderColor, width: 0.8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );

    if (onTap == null) return badge;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Tooltip(
        message: tooltip ?? 'Click để đổi người nói (Nam ↔ Nữ)',
        waitDuration: const Duration(milliseconds: 300),
        child: badge,
      ),
    );
  }
}
