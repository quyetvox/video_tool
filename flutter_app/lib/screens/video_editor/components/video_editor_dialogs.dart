import 'package:flutter/material.dart';
import '../../../core/app_colors.dart';
import '../../../core/file_service.dart';
import '../../../core/python_bridge.dart';
import '../../../models/app_config.dart';
import '../../../models/video_file.dart';
import '../../../widgets/app_kit.dart';

class VideoEditorDialogs {
  /// Hiển thị dialog đổi tên file video
  static void showRenameDialog({
    required BuildContext context,
    required VideoFile file,
    required VoidCallback onRenamed,
  }) {
    final controller = TextEditingController(text: file.basename);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: AppColors.border),
        ),
        title: const Text(
          'Đổi Tên File',
          style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
        ),
        content: AppTextField(
          controller: controller,
          autofocus: true,
          height: 34,
          hint: 'Nhập tên video mới...',
        ),
        actions: [
          AppButton.ghost(
            label: 'Hủy',
            onPressed: () => Navigator.pop(ctx),
          ),
          const SizedBox(width: 6),
          AppButton.primary(
            label: 'Đổi Tên',
            onPressed: () {
              final newName = controller.text.trim();
              if (newName.isNotEmpty && newName != file.basename) {
                FileService.renameVideoFile(file.fullPath, newName);
                onRenamed();
              }
              Navigator.pop(ctx);
            },
          ),
        ],
      ),
    );
  }

  /// Hạ nhiệt CPU thông minh giữa các batch translate job
  static Future<void> performBatchCooldown({
    required bool isVoice,
    required VideoFile currentFile,
    required VideoFile nextFile,
    required AppConfig config,
    required bool Function() isProcessingCheck,
  }) async {
    final cooldownSetting = config.batchCooldownSec.trim().toLowerCase();

    int cooldownSec;
    if (cooldownSetting.isEmpty || cooldownSetting == 'auto') {
      if (!isVoice) {
        cooldownSec = 2;
      } else {
        if (currentFile.sizeBytes > 50 * 1024 * 1024 ||
            (config.longVideoEnabled && currentFile.sizeBytes > 30 * 1024 * 1024)) {
          cooldownSec = 8;
        } else {
          cooldownSec = 5;
        }
      }
    } else {
      cooldownSec = int.tryParse(cooldownSetting) ?? (isVoice ? 5 : 2);
    }

    if (cooldownSec <= 0) return;

    for (int sec = cooldownSec; sec > 0; sec--) {
      if (!isProcessingCheck()) break;
      final msg = '⏳ [Smart Cooldown] Đang hạ nhiệt CPU (${sec}s) trước khi dịch: ${nextFile.name}';
      PythonBridge.addLog('cooldown', 'PROGRESS', msg);
      await Future.delayed(const Duration(seconds: 1));
    }
  }
}
