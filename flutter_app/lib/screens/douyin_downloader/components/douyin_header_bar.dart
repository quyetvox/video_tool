import 'dart:io';
import 'package:flutter/material.dart';
import '../../../core/app_colors.dart';
import '../../../widgets/douyin_raw_modal.dart';
import '../../../widgets/tool_header_toolbar.dart';

/// Top Header 44px cho màn hình Douyin Downloader.
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

    return ToolHeaderToolbar(
      icon: Icon(Icons.cloud_download_outlined, color: c.primary, size: 15),
      title: 'Tải Video Hàng Loạt',
      breadcrumb: 'assets/${activeProject ?? 'default'}/',
      actions: [
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: c.textSecondary,
            side: BorderSide(color: c.border),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            minimumSize: Size.zero,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
          ),
          icon: const Icon(Icons.edit_note, size: 14),
          label: const Text('Sửa File Raw', style: TextStyle(fontSize: 11)),
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
        const SizedBox(width: 6),
        IconButton(
          icon: Icon(Icons.refresh, size: 16, color: c.textSecondary),
          tooltip: 'Tải lại danh sách từ file',
          onPressed: onReload,
        ),
      ],
    );
  }
}
