import 'package:flutter/material.dart';
import 'dart:io';
import '../core/app_colors.dart';
import 'app_kit.dart';

class DouyinRawModal extends StatefulWidget {
  final String filePath;
  final VoidCallback onSaved;

  const DouyinRawModal({
    super.key,
    required this.filePath,
    required this.onSaved,
  });

  @override
  State<DouyinRawModal> createState() => _DouyinRawModalState();
}

class _DouyinRawModalState extends State<DouyinRawModal> {
  late TextEditingController _controller;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    String initialContent = '';
    final file = File(widget.filePath);
    if (file.existsSync()) {
      try {
        initialContent = file.readAsStringSync();
      } catch (_) {}
    }
    _controller = TextEditingController(text: initialContent);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Container(
        width: 650,
        height: 500,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.edit_note, color: AppColors.primary, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Sửa File Link Raw: ${widget.filePath.split('/').last}',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: AppColors.textSecondary, size: 16),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => Navigator.pop(context),
                )
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Mỗi dòng là 1 đường link Douyin / TikTok hoặc URL trực tiếp:',
              style: TextStyle(color: AppColors.textMuted, fontSize: 11),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.surfaceDark,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: AppColors.border, width: 0.8),
                ),
                child: TextField(
                  controller: _controller,
                  maxLines: null,
                  expands: true,
                  cursorColor: AppColors.primary,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 11.5, color: Colors.white),
                  decoration: const InputDecoration(
                    contentPadding: EdgeInsets.all(12),
                    border: InputBorder.none,
                    hintText: 'https://v.douyin.com/...',
                    hintStyle: TextStyle(color: AppColors.textMuted),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                AppButton.ghost(
                  label: 'Hủy',
                  onPressed: () => Navigator.pop(context),
                ),
                const SizedBox(width: 8),
                AppButton.primary(
                  icon: Icons.save,
                  label: 'Lưu File',
                  isLoading: _isSaving,
                  onPressed: _isSaving
                      ? null
                      : () {
                          setState(() => _isSaving = true);
                          final file = File(widget.filePath);
                          try {
                            file.writeAsStringSync(_controller.text);
                            widget.onSaved();
                            Navigator.pop(context);
                          } catch (e) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Lỗi khi lưu file: $e')),
                            );
                          } finally {
                            if (mounted) setState(() => _isSaving = false);
                          }
                        },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
