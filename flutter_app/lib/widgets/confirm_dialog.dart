import 'package:flutter/material.dart';
import '../core/app_colors.dart';
import 'app_kit.dart';

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
    final c = AppColors.of(context);
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: c.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: c.border, width: 0.8),
          ),
          title: Row(
            children: [
              Icon(
                icon,
                color: isDestructive ? c.statusFailed : c.primary,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: c.textPrimary)),
              ),
            ],
          ),
          content: Text(message, style: TextStyle(fontSize: 12, height: 1.4, color: c.textSecondary)),
          actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          actions: [
            AppButton.ghost(
              label: cancelText,
              onPressed: () => Navigator.of(context).pop(false),
            ),
            const SizedBox(width: 6),
            if (isDestructive)
              AppButton.danger(
                label: confirmText,
                onPressed: () => Navigator.of(context).pop(true),
              )
            else
              AppButton.primary(
                label: confirmText,
                onPressed: () => Navigator.of(context).pop(true),
              ),
          ],
        );
      },
    );
    return result ?? false;
  }
}
