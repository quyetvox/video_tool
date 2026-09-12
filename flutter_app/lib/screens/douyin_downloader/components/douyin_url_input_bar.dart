import 'package:flutter/material.dart';
import '../../../core/app_colors.dart';

/// URL input bar component: Link file selector and quick direct paste/preview bar.
class DouyinUrlInputBar extends StatelessWidget {
  final TextEditingController filePathController;
  final TextEditingController urlInputController;
  final ValueChanged<String> onFilePathSubmitted;
  final VoidCallback onPickLinkFile;
  final VoidCallback onPasteFromClipboard;
  final VoidCallback onPreviewPastedUrl;

  const DouyinUrlInputBar({
    super.key,
    required this.filePathController,
    required this.urlInputController,
    required this.onFilePathSubmitted,
    required this.onPickLinkFile,
    required this.onPasteFromClipboard,
    required this.onPreviewPastedUrl,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);

    return Column(
      children: [
        // 1. Input Link File Selector Bar (Direct Path Input)
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

        // 2. Quick Direct Paste & Preview Bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: c.surface,
            border: Border(bottom: BorderSide(color: c.border)),
          ),
          child: Row(
            children: [
              Icon(Icons.link, size: 16, color: c.primary),
              const SizedBox(width: 8),
              Text('Dán link xem nhanh:', style: TextStyle(color: c.textSecondary, fontSize: 11.5, fontWeight: FontWeight.w500)),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  height: 28,
                  decoration: BoxDecoration(
                    color: c.surfaceDark,
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: c.border, width: 0.8),
                  ),
                  child: Row(
                    children: [
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: urlInputController,
                          style: TextStyle(fontSize: 11, color: c.textPrimary),
                          decoration: InputDecoration(
                            hintText: 'Dán URL Douyin hoặc Direct CDN link (.mp4) để xem trực tuyến...',
                            hintStyle: TextStyle(fontSize: 11, color: c.textMuted),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(vertical: 6),
                          ),
                          onSubmitted: (_) => onPreviewPastedUrl(),
                        ),
                      ),
                      if (urlInputController.text.isNotEmpty)
                        IconButton(
                          icon: Icon(Icons.clear, size: 13, color: c.textMuted),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () {
                            urlInputController.clear();
                          },
                        ),
                      const SizedBox(width: 4),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: c.textPrimary,
                  side: BorderSide(color: c.border),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: const Size(0, 28),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
                ),
                icon: const Icon(Icons.content_paste, size: 13),
                label: const Text('Dán Clipboard', style: TextStyle(fontSize: 10.5)),
                onPressed: onPasteFromClipboard,
              ),
              const SizedBox(width: 6),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: c.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  minimumSize: const Size(0, 28),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
                ),
                icon: const Icon(Icons.play_circle_fill, size: 14),
                label: const Text('⚡ Xem Thử', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                onPressed: onPreviewPastedUrl,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
