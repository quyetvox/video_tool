import 'package:flutter/material.dart';
import '../core/app_colors.dart';

class ConfirmDialog {
  static Future<bool> show(
    BuildContext context, {
    required String title,
    required String message,
    String confirmText = 'Xác nhận',
    String cancelText = 'Hủy',
    bool isDestructive = false,
    IconData icon = Icons.warning_amber_rounded,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppColors.surfaceLight,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: const BorderSide(color: AppColors.border, width: 0.8),
          ),
          title: Row(
            children: [
              Icon(
                icon,
                color: isDestructive ? const Color(0xFFEF4444) : AppColors.primary,
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
              ),
            ],
          ),
          content: Text(message, style: const TextStyle(fontSize: 12.5, height: 1.4, color: AppColors.textSecondary)),
          actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(cancelText, style: const TextStyle(color: AppColors.textMuted)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: isDestructive ? const Color(0xFFEF4444) : AppColors.primary,
                foregroundColor: isDestructive ? Colors.white : Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                elevation: 0,
              ),
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(confirmText, style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }
}
