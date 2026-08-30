import 'package:flutter/material.dart';
import '../core/app_colors.dart';

/// ═══════════════════════════════════════════════════════════════════════════
/// ── 🎨 APP THEME EXTENSION (DYNAMIC COLOR TOKENS) ───────────────────────────
/// ═══════════════════════════════════════════════════════════════════════════

class AppThemeColors extends ThemeExtension<AppThemeColors> {
  final Color background;
  final Color surface;
  final Color surfaceLight;
  final Color surfaceDark;
  final Color surfaceInput;
  final Color border;
  final Color borderSubtle;
  final Color borderFocus;
  final Color primary;
  final Color primaryHover;
  final Color primaryMuted;
  final Color primaryDark;
  final Color primaryText;
  final Color statusCompleted;
  final Color statusCompletedBg;
  final Color statusProcessing;
  final Color statusProcessingBg;
  final Color statusFailed;
  final Color statusFailedBg;
  final Color info;
  final Color infoBg;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color textLight;

  const AppThemeColors({
    required this.background,
    required this.surface,
    required this.surfaceLight,
    required this.surfaceDark,
    required this.surfaceInput,
    required this.border,
    required this.borderSubtle,
    required this.borderFocus,
    required this.primary,
    required this.primaryHover,
    required this.primaryMuted,
    required this.primaryDark,
    required this.primaryText,
    required this.statusCompleted,
    required this.statusCompletedBg,
    required this.statusProcessing,
    required this.statusProcessingBg,
    required this.statusFailed,
    required this.statusFailedBg,
    required this.info,
    required this.infoBg,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.textLight,
  });

  /// 🌑 Obsidian Amber Dark Palette
  static const dark = AppThemeColors(
    background: Color(0xFF0E0F12),
    surface: Color(0xFF15171C),
    surfaceLight: Color(0xFF1C1F26),
    surfaceDark: Color(0xFF090A0D),
    surfaceInput: Color(0xFF121419),
    border: Color(0xFF23262F),
    borderSubtle: Color(0xFF1B1D24),
    borderFocus: Color(0xFFF5A623),
    primary: Color(0xFFF5A623),
    primaryHover: Color(0xFFFFB84D),
    primaryMuted: Color(0x26F5A623),
    primaryDark: Color(0xFFC77E0D),
    primaryText: Color(0xFF1A1202),
    statusCompleted: Color(0xFF34D399),
    statusCompletedBg: Color(0xFF132D22),
    statusProcessing: Color(0xFFFBBF24),
    statusProcessingBg: Color(0xFF322611),
    statusFailed: Color(0xFFF87171),
    statusFailedBg: Color(0xFF331818),
    info: Color(0xFF60A5FA),
    infoBg: Color(0xFF132338),
    textPrimary: Color(0xFFF3F4F6),
    textSecondary: Color(0xFF9CA3AF),
    textMuted: Color(0xFF6B7280),
    textLight: Color(0xFFD1D5DB),
  );

  /// ☀️ Luxury Slate Ivory Light Palette
  static const light = AppThemeColors(
    background: Color(0xFFF8FAFC),
    surface: Color(0xFFFFFFFF),
    surfaceLight: Color(0xFFF1F5F9),
    surfaceDark: Color(0xFFE2E8F0),
    surfaceInput: Color(0xFFFFFFFF),
    border: Color(0xFFE2E8F0),
    borderSubtle: Color(0xFFEDF2F7),
    borderFocus: Color(0xFFD97706),
    primary: Color(0xFFD97706),
    primaryHover: Color(0xFFB45309),
    primaryMuted: Color(0x26D97706),
    primaryDark: Color(0xFF92400E),
    primaryText: Color(0xFFFFFFFF),
    statusCompleted: Color(0xFF059669),
    statusCompletedBg: Color(0xFFD1FAE5),
    statusProcessing: Color(0xFFD97706),
    statusProcessingBg: Color(0xFFFEF3C7),
    statusFailed: Color(0xFFDC2626),
    statusFailedBg: Color(0xFFFEE2E2),
    info: Color(0xFF2563EB),
    infoBg: Color(0xFFDBEAFE),
    textPrimary: Color(0xFF0F172A),
    textSecondary: Color(0xFF475569),
    textMuted: Color(0xFF94A3B8),
    textLight: Color(0xFF334155),
  );

  @override
  ThemeExtension<AppThemeColors> copyWith({
    Color? background,
    Color? surface,
    Color? surfaceLight,
    Color? surfaceDark,
    Color? surfaceInput,
    Color? border,
    Color? borderSubtle,
    Color? borderFocus,
    Color? primary,
    Color? primaryHover,
    Color? primaryMuted,
    Color? primaryDark,
    Color? primaryText,
    Color? statusCompleted,
    Color? statusCompletedBg,
    Color? statusProcessing,
    Color? statusProcessingBg,
    Color? statusFailed,
    Color? statusFailedBg,
    Color? info,
    Color? infoBg,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? textLight,
  }) {
    return AppThemeColors(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceLight: surfaceLight ?? this.surfaceLight,
      surfaceDark: surfaceDark ?? this.surfaceDark,
      surfaceInput: surfaceInput ?? this.surfaceInput,
      border: border ?? this.border,
      borderSubtle: borderSubtle ?? this.borderSubtle,
      borderFocus: borderFocus ?? this.borderFocus,
      primary: primary ?? this.primary,
      primaryHover: primaryHover ?? this.primaryHover,
      primaryMuted: primaryMuted ?? this.primaryMuted,
      primaryDark: primaryDark ?? this.primaryDark,
      primaryText: primaryText ?? this.primaryText,
      statusCompleted: statusCompleted ?? this.statusCompleted,
      statusCompletedBg: statusCompletedBg ?? this.statusCompletedBg,
      statusProcessing: statusProcessing ?? this.statusProcessing,
      statusProcessingBg: statusProcessingBg ?? this.statusProcessingBg,
      statusFailed: statusFailed ?? this.statusFailed,
      statusFailedBg: statusFailedBg ?? this.statusFailedBg,
      info: info ?? this.info,
      infoBg: infoBg ?? this.infoBg,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      textLight: textLight ?? this.textLight,
    );
  }

  @override
  ThemeExtension<AppThemeColors> lerp(covariant ThemeExtension<AppThemeColors>? other, double t) {
    if (other is! AppThemeColors) return this;
    return AppThemeColors(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceLight: Color.lerp(surfaceLight, other.surfaceLight, t)!,
      surfaceDark: Color.lerp(surfaceDark, other.surfaceDark, t)!,
      surfaceInput: Color.lerp(surfaceInput, other.surfaceInput, t)!,
      border: Color.lerp(border, other.border, t)!,
      borderSubtle: Color.lerp(borderSubtle, other.borderSubtle, t)!,
      borderFocus: Color.lerp(borderFocus, other.borderFocus, t)!,
      primary: Color.lerp(primary, other.primary, t)!,
      primaryHover: Color.lerp(primaryHover, other.primaryHover, t)!,
      primaryMuted: Color.lerp(primaryMuted, other.primaryMuted, t)!,
      primaryDark: Color.lerp(primaryDark, other.primaryDark, t)!,
      primaryText: Color.lerp(primaryText, other.primaryText, t)!,
      statusCompleted: Color.lerp(statusCompleted, other.statusCompleted, t)!,
      statusCompletedBg: Color.lerp(statusCompletedBg, other.statusCompletedBg, t)!,
      statusProcessing: Color.lerp(statusProcessing, other.statusProcessing, t)!,
      statusProcessingBg: Color.lerp(statusProcessingBg, other.statusProcessingBg, t)!,
      statusFailed: Color.lerp(statusFailed, other.statusFailed, t)!,
      statusFailedBg: Color.lerp(statusFailedBg, other.statusFailedBg, t)!,
      info: Color.lerp(info, other.info, t)!,
      infoBg: Color.lerp(infoBg, other.infoBg, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      textLight: Color.lerp(textLight, other.textLight, t)!,
    );
  }
}

/// ═══════════════════════════════════════════════════════════════════════════
/// ── 🌓 APP THEME DEFINITIONS ────────────────────────────────────────────────
/// ═══════════════════════════════════════════════════════════════════════════

class AppTheme {
  /// 🌑 Dark Theme
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppThemeColors.dark.background,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.primary,
        onPrimary: AppColors.primaryText,
        surface: AppColors.surface,
        onSurface: AppColors.textPrimary,
      ),
      extensions: const [AppThemeColors.dark],
    );
  }

  /// ☀️ Light Theme
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: AppThemeColors.light.background,
      colorScheme: const ColorScheme.light(
        primary: Color(0xFFD97706),
        onPrimary: Colors.white,
        surface: Color(0xFFFFFFFF),
        onSurface: Color(0xFF0F172A),
      ),
      extensions: const [AppThemeColors.light],
    );
  }
}
