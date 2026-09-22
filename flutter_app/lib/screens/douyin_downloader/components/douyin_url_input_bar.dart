import 'package:flutter/material.dart';
import '../../../core/app_colors.dart';
import '../../../models/media_link_info.dart';
import '../../../widgets/internet_video_link_bar.dart';

/// URL input bar component: Link file selector and InternetVideoLinkBar (preview & download).
class DouyinUrlInputBar extends StatelessWidget {
  final TextEditingController filePathController;
  final ValueChanged<String> onFilePathSubmitted;
  final VoidCallback onPickLinkFile;
  final String targetDir;
  final void Function(MediaLinkInfo info)? onStreamPreviewReady;
  final void Function(String localFilePath, String videoName)? onVideoDownloaded;
  final VoidCallback? onCleared;

  const DouyinUrlInputBar({
    super.key,
    required this.filePathController,
    required this.onFilePathSubmitted,
    required this.onPickLinkFile,
    required this.targetDir,
    this.onStreamPreviewReady,
    this.onVideoDownloaded,
    this.onCleared,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);

    return Column(
      children: [
        // 1. Input Link File Selector Bar (Direct Path Input for Batch Download)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: c.surfaceDark,
            border: Border(bottom: BorderSide(color: c.border)),
          ),
          child: Row(
            children: [
              Icon(Icons.description_outlined, size: 15, color: c.primary),
              const SizedBox(width: 8),
              Text('Đường dẫn file link (.txt):', style: TextStyle(color: c.textSecondary, fontSize: 12, fontWeight: FontWeight.w500)),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  height: 28,
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: c.border, width: 0.8),
                  ),
                  child: Row(
                    children: [
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: filePathController,
                          style: TextStyle(fontSize: 11, color: c.textPrimary),
                          decoration: InputDecoration(
                            isDense: true,
                            border: InputBorder.none,
                            hintText: 'Dán hoặc nhập đường dẫn file .txt bất kỳ trong máy (ví dụ: /Users/.../links.txt hoặc C:\\...\\links.txt)',
                            hintStyle: TextStyle(fontSize: 11, color: c.textMuted),
                            contentPadding: const EdgeInsets.symmetric(vertical: 7),
                          ),
                          onSubmitted: onFilePathSubmitted,
                        ),
                      ),
                      if (filePathController.text.isNotEmpty)
                        IconButton(
                          icon: Icon(Icons.clear, size: 13, color: c.textMuted),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          tooltip: 'Xóa đường dẫn',
                          onPressed: () {
                            filePathController.clear();
                          },
                        ),
                      const SizedBox(width: 4),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: c.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  minimumSize: const Size(0, 28),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
                ),
                icon: const Icon(Icons.folder_open, size: 14),
                label: const Text('Chọn File', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                onPressed: onPickLinkFile,
              ),
            ],
          ),
        ),

        // 2. Internet Video Link Bar: Preview trực tiếp mọi nền tảng và Tải về src/
        InternetVideoLinkBar(
          targetDir: targetDir,
          onStreamPreviewReady: onStreamPreviewReady,
          onVideoDownloaded: onVideoDownloaded,
          onCleared: onCleared,
        ),
      ],
    );
  }
}
