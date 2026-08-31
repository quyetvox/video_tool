import 'package:flutter/material.dart';

/// Centralized Color Tokens for Sub-Video Desktop App
/// Allows easy palette customization and ensures 100% theme consistency across all screens and widgets.
class AppColors {
  // ── Backgrounds & Surfaces (Deep Cinematic Dark) ──
  static const Color background = Color(0xFF0E0F12);       // Nền tổng thể Scaffold
  static const Color surface = Color(0xFF15171C);          // Nền Cards, Panels, Sidebars
  static const Color surfaceLight = Color(0xFF1C1F26);     // Nền Hover, Selected rows, Active controls
  static const Color surfaceDark = Color(0xFF090A0D);      // Nền Canvas Player, Inner Terminal
  static const Color surfaceInput = Color(0xFF121419);     // Nền Search box, Text inputs
  
  // ── Borders & Dividers ──
  static const Color border = Color(0xFF23262F);           // Viền Card, Panel divider
  static const Color borderSubtle = Color(0xFF1B1D24);     // Viền ngăn cách nhẹ giữa các hàng
  static const Color borderFocus = Color(0xFFF5A623);      // Viền khi focus/active

  // ── Primary Accent (Amber Gold / Vàng Hổ Phách Chủ Đạo) ──
  static const Color primary = Color(0xFFF5A623);          // Vàng Hổ Phách chính
  static const Color primaryHover = Color(0xFFFFB84D);     // Vàng sáng khi hover
  static const Color primaryMuted = Color(0x26F5A623);     // Vàng 15% opacity cho pill/badge nền
  static const Color primaryDark = Color(0xFFC77E0D);      // Vàng viền đậm
  static const Color primaryText = Color(0xFF1A1202);      // Chữ màu tối trên nút vàng

  // ── Functional / Status Colors ──
  // Completed / Success / Ready
  static const Color statusCompleted = Color(0xFF34D399);  // Xanh ngọc dịu
  static const Color statusCompletedBg = Color(0xFF132D22);// Nền pill completed

  // Processing / Running / Warning
  static const Color statusProcessing = Color(0xFFFBBF24); // Vàng cam ấm
  static const Color statusProcessingBg = Color(0xFF322611);// Nền pill processing

  // Failed / Error / Danger
  static const Color statusFailed = Color(0xFFF87171);     // Đỏ san hô
  static const Color statusFailedBg = Color(0xFF331818);   // Nền pill failed

  // Info / Cloud Blue
  static const Color info = Color(0xFF60A5FA);             // Xanh dương sáng
  static const Color infoBg = Color(0xFF132338);           // Nền pill info

  // ── Text Typography Colors ──
  static const Color textPrimary = Color(0xFFF3F4F6);      // Trắng sáng (Titles, active text)
  static const Color textSecondary = Color(0xFF9CA3AF);    // Xám bạc (Labels, headers, subtext)
  static const Color textMuted = Color(0xFF6B7280);        // Xám tối (Disabled, placeholder)
  static const Color textLight = Color(0xFFD1D5DB);        // Xám nhạt đọc dễ chịu

  /// ── 🌓 CONTEXT-AWARE DYNAMIC ACCESSOR ───────────────────────────
  /// Automatically resolves to either Dark or Light palette based on active Theme
  static bool isDark(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark;
  }

  /// Shortcut helper to access theme dynamic colors in any widget
  static dynamic of(BuildContext context) {
    final ext = Theme.of(context).extension();
    if (ext != null) return ext;
    return isDark(context) ? _darkFallback : _lightFallback;
  }

  static const _darkFallback = _AppFallbackPalette(isDark: true);
  static const _lightFallback = _AppFallbackPalette(isDark: false);
}

class _AppFallbackPalette {
  final bool isDark;
  const _AppFallbackPalette({required this.isDark});

  Color get background => isDark ? const Color(0xFF0E0F12) : const Color(0xFFF8FAFC);
  Color get surface => isDark ? const Color(0xFF15171C) : const Color(0xFFFFFFFF);
  Color get surfaceLight => isDark ? const Color(0xFF1C1F26) : const Color(0xFFF1F5F9);
  Color get surfaceDark => isDark ? const Color(0xFF090A0D) : const Color(0xFFE2E8F0);
  Color get surfaceInput => isDark ? const Color(0xFF121419) : const Color(0xFFFFFFFF);
  Color get border => isDark ? const Color(0xFF23262F) : const Color(0xFFE2E8F0);
  Color get borderLight => isDark ? const Color(0xFF333742) : const Color(0xFFCBD5E1);
  Color get borderSubtle => isDark ? const Color(0xFF1B1D24) : const Color(0xFFEDF2F7);
  Color get borderFocus => isDark ? const Color(0xFFF5A623) : const Color(0xFFD97706);
  Color get primary => isDark ? const Color(0xFFF5A623) : const Color(0xFFD97706);
  Color get primaryHover => isDark ? const Color(0xFFFFB84D) : const Color(0xFFB45309);
  Color get primaryMuted => isDark ? const Color(0x26F5A623) : const Color(0x26D97706);
  Color get primaryDark => isDark ? const Color(0xFFC77E0D) : const Color(0xFF92400E);
  Color get primaryText => isDark ? const Color(0xFF1A1202) : const Color(0xFFFFFFFF);
  Color get statusCompleted => isDark ? const Color(0xFF34D399) : const Color(0xFF059669);
  Color get statusCompletedBg => isDark ? const Color(0xFF132D22) : const Color(0xFFD1FAE5);
  Color get statusProcessing => isDark ? const Color(0xFFFBBF24) : const Color(0xFFD97706);
  Color get statusProcessingBg => isDark ? const Color(0xFF322611) : const Color(0xFFFEF3C7);
  Color get statusFailed => isDark ? const Color(0xFFF87171) : const Color(0xFFDC2626);
  Color get statusFailedBg => isDark ? const Color(0xFF331818) : const Color(0xFFFEE2E2);
  Color get info => isDark ? const Color(0xFF60A5FA) : const Color(0xFF2563EB);
  Color get infoBg => isDark ? const Color(0xFF132338) : const Color(0xFFDBEAFE);
  Color get textPrimary => isDark ? const Color(0xFFF3F4F6) : const Color(0xFF0F172A);
  Color get textSecondary => isDark ? const Color(0xFF9CA3AF) : const Color(0xFF475569);
  Color get textMuted => isDark ? const Color(0xFF6B7280) : const Color(0xFF94A3B8);
  Color get textLight => isDark ? const Color(0xFFD1D5DB) : const Color(0xFF334155);
}
