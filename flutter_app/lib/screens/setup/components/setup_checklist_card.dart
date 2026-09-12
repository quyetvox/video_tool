import 'dart:io';
import 'package:flutter/material.dart';
import '../../../core/ai_environment_service.dart';
import '../../../core/app_colors.dart';
import '../../../models/models_status.dart';
import '../../../widgets/ai_setup_dialog.dart';

class SetupChecklistCard extends StatelessWidget {
  final ModelsStatus status;
  final bool isAiReady;
  final ValueChanged<bool> onAiReadyChanged;

  const SetupChecklistCard({
    super.key,
    required this.status,
    required this.isAiReady,
    required this.onAiReadyChanged,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: c.border, width: 0.8),
      ),
      color: c.surface,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.fact_check_outlined, size: 17, color: c.primary),
                const SizedBox(width: 8),
                Text(
                  'Kiểm Tra Trạng Thái Models Offline & Môi Trường',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: c.textPrimary),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _buildCheckItem(context, 'Whisper ASR Model Weights', status.whisperFound),
            _buildCheckItem(context, 'Demucs Music / Voice Separator', status.demucsFound),
            _buildCheckItem(
              context,
              Platform.isMacOS
                  ? 'Apple Vision OCR (macOS Native)'
                  : 'RapidOCR Engine (ONNX Runtime)',
              status.paddleOcrFound,
            ),
            _buildCheckItem(context, 'Python Runtime (Base Engine)', status.pythonFound),
            const SizedBox(height: 6),
            const Divider(height: 1),
            const SizedBox(height: 6),
            _buildAiRuntimeCheckItem(context),
          ],
        ),
      ),
    );
  }

  Widget _buildCheckItem(BuildContext context, String title, bool isAvailable) {
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            isAvailable ? Icons.check_circle : Icons.cancel,
            color: isAvailable ? const Color(0xFF10B981) : const Color(0xFFEF4444),
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(title, style: TextStyle(fontSize: 13, color: c.textPrimary))),
          Text(
            isAvailable ? 'Sẵn sàng' : 'Chưa có',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: isAvailable ? const Color(0xFF10B981) : const Color(0xFFEF4444),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAiRuntimeCheckItem(BuildContext context) {
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            isAiReady ? Icons.check_circle : Icons.warning_amber_rounded,
            color: isAiReady ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Gói AI Nâng Cao (Torch CPU, Demucs, Whisper)',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: c.textPrimary),
                ),
                Text(
                  'Tải theo yêu cầu để giảm kích thước cài đặt ban đầu',
                  style: TextStyle(fontSize: 11, color: c.textMuted),
                ),
              ],
            ),
          ),
          if (!isAiReady)
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF8B5CF6),
                side: const BorderSide(color: Color(0xFF8B5CF6), width: 0.8),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                minimumSize: const Size(0, 28),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
              ),
              icon: const Icon(Icons.cloud_download, size: 14),
              label: const Text('Cài đặt ngay', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
              onPressed: () async {
                final ok = await AiSetupDialog.show(context);
                if (ok) {
                  final ready = await AiEnvironmentService.isAiReady();
                  onAiReadyChanged(ready);
                }
              },
            )
          else
            const Text(
              'Sẵn sàng',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Color(0xFF10B981),
              ),
            ),
        ],
      ),
    );
  }
}
