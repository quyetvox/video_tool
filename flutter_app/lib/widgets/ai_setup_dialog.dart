import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../core/ai_environment_service.dart';
import '../core/app_colors.dart';

class AiSetupDialog extends StatefulWidget {
  const AiSetupDialog({super.key});

  static Future<bool> show(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const AiSetupDialog(),
    );
    return result ?? false;
  }

  @override
  State<AiSetupDialog> createState() => _AiSetupDialogState();
}

class _AiSetupDialogState extends State<AiSetupDialog> {
  bool _isProcessing = false;
  double _progress = 0.0;
  String _statusText = 'Chưa cài đặt Gói AI Nâng Cao (PyTorch, Whisper, Demucs).';
  bool _isSuccess = false;

  Future<void> _startAutoDownload() async {
    setState(() {
      _isProcessing = true;
      _progress = 0.05;
      _statusText = 'Đang khởi tạo kết nối tải gói AI...';
    });

    final success = await AiEnvironmentService.downloadAndInstall(
      onProgress: (p, msg) {
        if (mounted) {
          setState(() {
            _progress = p;
            _statusText = msg;
          });
        }
      },
    );

    if (mounted) {
      setState(() {
        _isProcessing = false;
        _isSuccess = success;
        if (success) {
          _statusText = '🎉 Cài đặt Gói AI Nâng Cao thành công!';
        }
      });
      if (success) {
        Future.delayed(const Duration(milliseconds: 1200), () {
          if (mounted) Navigator.of(context).pop(true);
        });
      }
    }
  }

  Future<void> _pickLocalZip() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
      dialogTitle: 'Chọn tệp SubVideo-AI-Runtime Zip ngoại tuyến',
    );

    if (result == null || result.files.isEmpty || result.files.first.path == null) {
      return;
    }

    final file = File(result.files.first.path!);

    setState(() {
      _isProcessing = true;
      _progress = 0.1;
      _statusText = 'Bắt đầu giải nén từ tệp: ${result.files.first.name}...';
    });

    final success = await AiEnvironmentService.installFromLocalZip(
      file,
      onProgress: (p, msg) {
        if (mounted) {
          setState(() {
            _progress = p;
            _statusText = msg;
          });
        }
      },
    );

    if (mounted) {
      setState(() {
        _isProcessing = false;
        _isSuccess = success;
        if (success) {
          _statusText = '🎉 Cài đặt Gói AI Nâng Cao từ tệp ngoại tuyến thành công!';
        }
      });
      if (success) {
        Future.delayed(const Duration(milliseconds: 1200), () {
          if (mounted) Navigator.of(context).pop(true);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);

    return Dialog(
      backgroundColor: c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: c.border, width: 1),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFF8B5CF6).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.psychology_outlined, color: Color(0xFFA78BFA), size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Cài Đặt Gói AI Nâng Cao (AI Runtime)',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Yêu cầu để tách nhạc nền Demucs & nhận diện giọng nói Whisper',
                          style: TextStyle(fontSize: 12, color: c.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  if (!_isProcessing)
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => Navigator.of(context).pop(false),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 16),

              // Description box
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: c.surfaceLight,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: c.border, width: 0.8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.info_outline, size: 16, color: Color(0xFF60A5FA)),
                        const SizedBox(width: 8),
                        Text(
                          'Tối Ưu Hoá Kích Thước Bộ Cài Ứng Dụng',
                          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: c.textPrimary),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Để ứng dụng có dung lượng siêu nhẹ (~80MB) và cập nhật tức thì, các thư viện AI nặng (PyTorch, Demucs, Whisper, OpenCV) được tách rời và chỉ tải một lần duy nhất vào thư mục ứng dụng người dùng.',
                      style: TextStyle(fontSize: 11.5, color: c.textSecondary, height: 1.4),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        _buildBadge('PyTorch (CPU/MPS)', const Color(0xFFF97316)),
                        _buildBadge('Demucs Separator', const Color(0xFF10B981)),
                        _buildBadge('Whisper ASR', const Color(0xFF6366F1)),
                        _buildBadge('OpenCV & Scipy', const Color(0xFFEC4899)),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Progress & Status message
              Text(
                _statusText,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: _isSuccess ? FontWeight.bold : FontWeight.w500,
                  color: _isSuccess
                      ? const Color(0xFF10B981)
                      : (_isProcessing ? const Color(0xFF60A5FA) : c.textSecondary),
                ),
              ),

              if (_isProcessing) ...[
                const SizedBox(height: 10),
                LinearProgressIndicator(
                  value: _progress > 0 ? _progress : null,
                  backgroundColor: Colors.white12,
                  color: const Color(0xFF8B5CF6),
                  minHeight: 6,
                  borderRadius: BorderRadius.circular(3),
                ),
              ],

              const SizedBox(height: 20),

              // Action Buttons
              if (!_isProcessing && !_isSuccess)
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('Để Sau', style: TextStyle(color: Colors.white60)),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: BorderSide(color: c.border),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      ),
                      icon: const Icon(Icons.folder_zip_outlined, size: 16),
                      label: const Text('Cài Từ File Zip Offline', style: TextStyle(fontSize: 12)),
                      onPressed: _pickLocalZip,
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF8B5CF6),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      ),
                      icon: const Icon(Icons.cloud_download, size: 16),
                      label: const Text('Tải Tự Động (Khuyến Nghị)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      onPressed: _startAutoDownload,
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.3), width: 0.8),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 10.5, color: color, fontWeight: FontWeight.w500),
      ),
    );
  }
}
