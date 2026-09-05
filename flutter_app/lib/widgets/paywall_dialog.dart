import 'dart:io';
import 'package:flutter/material.dart';
import '../core/app_constants.dart';

class PaywallDialog extends StatelessWidget {
  final String featureName;
  final String? featureDescription;

  const PaywallDialog({
    super.key,
    required this.featureName,
    this.featureDescription,
  });

  static Future<void> show(
    BuildContext context, {
    required String featureName,
    String? featureDescription,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => PaywallDialog(
        featureName: featureName,
        featureDescription: featureDescription,
      ),
    );
  }

  void _openBrowser(String url) {
    try {
      if (Platform.isMacOS) {
        Process.run('open', [url]);
      } else if (Platform.isWindows) {
        Process.run('cmd', ['/c', 'start', '', url]);
      } else if (Platform.isLinux) {
        Process.run('xdg-open', [url]);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Container(
        width: 480,
        decoration: BoxDecoration(
          color: const Color(0xFF131722),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFD97706).withOpacity(0.4), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFD97706).withOpacity(0.12),
              blurRadius: 28,
              spreadRadius: 2,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Header Banner
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF2A1C0E), Color(0xFF1E1914)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.vertical(top: Radius.circular(15)),
                border: Border(
                  bottom: BorderSide(color: Color(0xFF3B2A15), width: 1),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFF59E0B), Color(0xFFD97706)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFF59E0B).withOpacity(0.3),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.workspace_premium, color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text(
                              'Tính Năng Pro Studio',
                              style: TextStyle(
                                color: Color(0xFFFBBF24),
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.3,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFD97706).withOpacity(0.2),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: const Color(0xFFD97706).withOpacity(0.4), width: 0.8),
                              ),
                              child: const Text(
                                '299.000đ/năm',
                                style: TextStyle(color: Color(0xFFFCD34D), fontSize: 10, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          featureDescription ?? 'Nâng cấp để mở khóa toàn bộ sức mạnh xử lý video AI',
                          style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 11.5),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Color(0xFF9CA3AF), size: 18),
                    onPressed: () => Navigator.of(context).pop(),
                    splashRadius: 16,
                  ),
                ],
              ),
            ),

            // 2. Feature Box
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E2230),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF374151)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.lock_outline, color: Color(0xFFF59E0B), size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: RichText(
                            text: TextSpan(
                              style: const TextStyle(fontSize: 12.5, color: Color(0xFFE5E7EB), height: 1.4),
                              children: [
                                const TextSpan(text: 'Tính năng '),
                                TextSpan(
                                  text: featureName,
                                  style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFFBBF24)),
                                ),
                                const TextSpan(
                                  text: ' chỉ áp dụng cho tài khoản ',
                                ),
                                const TextSpan(
                                  text: 'Gói Pro Studio',
                                  style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                                ),
                                const TextSpan(text: ' trở lên.'),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),
                  const Text(
                    'ĐẶC QUYỀN GÓI PRO STUDIO:',
                    style: TextStyle(
                      color: Color(0xFF9CA3AF),
                      fontSize: 10.5,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 10),

                  _buildBenefitRow(Icons.auto_awesome, 'Xử lý chuyên sâu video siêu dài 2 - 3 giờ (tự động phân đoạn)'),
                  const SizedBox(height: 8),
                  _buildBenefitRow(Icons.replay_circle_filled_outlined, 'Cơ chế Resume thông minh khôi phục tiến trình khi gián đoạn'),
                  const SizedBox(height: 8),
                  _buildBenefitRow(Icons.playlist_play, 'Tải & xử lý hàng loạt video tuần tự theo danh sách'),
                  const SizedBox(height: 8),
                  _buildBenefitRow(Icons.devices, 'Kích hoạt đồng thời 2 thiết bị độc lập (1 Mac + 1 PC)'),
                  const SizedBox(height: 8),
                  _buildBenefitRow(Icons.support_agent, 'Hỗ trợ kỹ thuật cấu hình trực tiếp qua Ultraview / AnyDesk'),

                  const SizedBox(height: 22),

                  // 3. Action Buttons
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFF9CA3AF),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        ),
                        child: const Text('Để sau', style: TextStyle(fontSize: 12.5)),
                      ),
                      const SizedBox(width: 10),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFD97706),
                          foregroundColor: Colors.white,
                          elevation: 2,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        icon: const Icon(Icons.rocket_launch, size: 15, color: Colors.white),
                        label: const Text(
                          'Nâng Cấp Pro Studio Ngay',
                          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                        onPressed: () {
                          Navigator.of(context).pop();
                          _openBrowser(AppConstants.pricingUrl);
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBenefitRow(IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: const Color(0xFFF59E0B), size: 14),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(color: Color(0xFFD1D5DB), fontSize: 11.5, height: 1.3),
          ),
        ),
      ],
    );
  }
}
