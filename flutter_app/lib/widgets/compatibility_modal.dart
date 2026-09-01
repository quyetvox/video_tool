import 'package:flutter/material.dart';
import '../core/app_colors.dart';
import 'app_kit.dart';

class CompatibilityModal extends StatelessWidget {
  final List<String> differences;
  final VoidCallback onNormalize;

  const CompatibilityModal({
    super.key,
    required this.differences,
    required this.onNormalize,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return AlertDialog(
      backgroundColor: c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: c.border),
      ),
      title: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: c.primary, size: 20),
          const SizedBox(width: 8),
          Text(
            'Phát hiện video không cùng thông số định dạng',
            style: TextStyle(color: c.textPrimary, fontSize: 13.5, fontWeight: FontWeight.bold),
          ),
        ],
      ),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Các video trong danh sách ghép có thông số kỹ thuật khác nhau, cần chuẩn hóa để ghép chuẩn xác và không bị lỗi hình/tiếng:',
              style: TextStyle(color: c.textSecondary, fontSize: 11.5),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: c.surfaceDark,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: c.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Các điểm khác biệt:',
                    style: TextStyle(color: c.statusFailed, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  ...differences.map((diff) => Padding(
                        padding: const EdgeInsets.only(left: 6, top: 2),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('• ', style: TextStyle(color: c.statusFailed, fontSize: 11)),
                            Expanded(
                              child: Text(diff, style: TextStyle(color: c.textPrimary, fontSize: 11)),
                            ),
                          ],
                        ),
                      )),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: c.info.withOpacity(0.12),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: c.info.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.lightbulb_outline, size: 14, color: c.info),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Auto-Normalize sẽ sử dụng chip Apple Silicon VideoToolbox để chuẩn hóa kích thước, FPS và âm thanh trong ~1-2 giây.',
                      style: TextStyle(color: c.info, fontSize: 10.5),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        AppButton.outlined(
          label: 'Huỷ bỏ',
          onPressed: () => Navigator.pop(context),
        ),
        const SizedBox(width: 6),
        AppButton.primary(
          icon: Icons.auto_awesome,
          label: 'Đồng ý & Tự Động Chuẩn Hóa',
          onPressed: () {
            Navigator.pop(context);
            onNormalize();
          },
        ),
      ],
    );
  }
}
