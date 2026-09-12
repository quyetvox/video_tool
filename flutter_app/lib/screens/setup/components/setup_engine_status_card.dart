import 'package:flutter/material.dart';
import '../../../core/app_colors.dart';

class SetupEngineStatusCard extends StatelessWidget {
  const SetupEngineStatusCard({super.key});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: c.statusCompleted,
          width: 1.0,
        ),
      ),
      color: c.surface,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.statusCompletedBg,
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(
                Icons.psychology_rounded,
                color: AppColors.statusCompleted,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        '⚡ AI Core Engine (Whisper / Demucs / EdgeTTS)',
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Colors.white),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.statusCompletedBg,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'Đang Kích Hoạt',
                          style: TextStyle(fontSize: 10, color: AppColors.statusCompleted, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Sử dụng Sidecar Python Daemon hiệu năng cao nhúng sẵn (Local offline, không cần cài đặt thêm).',
                    style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
