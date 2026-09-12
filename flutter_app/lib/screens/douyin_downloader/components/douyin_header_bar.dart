import 'dart:io';
import 'package:flutter/material.dart';
import '../../../core/app_colors.dart';
import '../../../widgets/douyin_raw_modal.dart';

/// Top Header for Douyin Downloader screen.
class DouyinHeaderBar extends StatelessWidget {
  final String? activeProject;
  final String? currentFilePath;
  final VoidCallback onReload;

  const DouyinHeaderBar({
    super.key,
    required this.activeProject,
    required this.currentFilePath,
    required this.onReload,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(bottom: BorderSide(color: c.border)),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: c.primary.withOpacity(0.15),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Icon(Icons.cloud_download, color: c.primary, size: 16),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'Tải Video Hàng Loạt',
                    style: TextStyle(color: c.textPrimary, fontSize: 12.5, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: c.surfaceLight, borderRadius: BorderRadius.circular(4)),
                    child: Text('📁 assets/${activeProject ?? 'default'}/', style: TextStyle(color: c.primary, fontSize: 10.5)),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                'Trích xuất, xem trước và tải video chất lượng cao từ danh sách URL Douyin vào thư mục src/',
                style: TextStyle(color: c.textSecondary, fontSize: 10.5),
              ),
            ],
          ),
          const Spacer(),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: c.textSecondary,
              side: BorderSide(color: c.border),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
            ),
            icon: const Icon(Icons.edit_note, size: 13),
            label: const Text('Sửa File Raw', style: TextStyle(fontSize: 10.5)),
            onPressed: () {
              if (currentFilePath != null && File(currentFilePath!).existsSync()) {
                showDialog(
                  context: context,
                  builder: (ctx) => DouyinRawModal(filePath: currentFilePath!, onSaved: onReload),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('⚠️ Vui lòng nạp một file .txt hợp lệ trước khi sửa!')),
                );
              }
            },
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: Icon(Icons.refresh, size: 15, color: c.textSecondary),
            tooltip: 'Tải lại danh sách từ file',
            onPressed: onReload,
          ),
        ],
      ),
    );
  }
}
