import 'package:flutter/material.dart';

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
    return AlertDialog(
      backgroundColor: const Color(0xFF0F172A),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: Color(0xFF1E293B)),
      ),
      title: const Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: Color(0xFFF59E0B), size: 20),
          SizedBox(width: 8),
          Text(
            'Phát hiện video không cùng thông số định dạng',
            style: TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.bold),
          ),
        ],
      ),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Các video trong danh sách ghép có thông số kỹ thuật khác nhau, cần chuẩn hóa để ghép chuẩn xác và không bị lỗi hình/tiếng:',
              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11.5),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF0B1120),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFF334155)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Các điểm khác biệt:',
                    style: TextStyle(color: Color(0xFFF87171), fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  ...differences.map((diff) => Padding(
                        padding: const EdgeInsets.only(left: 6, top: 2),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('• ', style: TextStyle(color: Color(0xFFF87171), fontSize: 11)),
                            Expanded(
                              child: Text(diff, style: const TextStyle(color: Colors.white, fontSize: 11)),
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
                color: const Color(0xFF0284C7).withOpacity(0.12),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFF0284C7).withOpacity(0.3)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.lightbulb_outline, size: 14, color: Color(0xFF38BDF8)),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Auto-Normalize sẽ sử dụng chip Apple Silicon VideoToolbox để chuẩn hóa kích thước, FPS và âm thanh trong ~1-2 giây.',
                      style: TextStyle(color: Color(0xFFBAE6FD), fontSize: 10.5),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        OutlinedButton(
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF94A3B8),
            side: const BorderSide(color: Color(0xFF334155)),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          ),
          onPressed: () => Navigator.pop(context),
          child: const Text('Huỷ bỏ', style: TextStyle(fontSize: 11)),
        ),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF8B5CF6),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          ),
          icon: const Icon(Icons.auto_awesome, size: 13),
          label: const Text(
            'Đồng ý & Tự Động Chuẩn Hóa',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
          ),
          onPressed: () {
            Navigator.pop(context);
            onNormalize();
          },
        ),
      ],
    );
  }
}
