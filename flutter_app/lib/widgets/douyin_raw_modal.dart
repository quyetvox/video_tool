import 'package:flutter/material.dart';
import 'dart:io';

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
      backgroundColor: const Color(0xFF0F172A),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: Color(0xFF334155)),
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
                const Icon(Icons.edit_note, color: Color(0xFF06B6D4)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Sửa File Link Raw: ${widget.filePath.split('/').last}',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Color(0xFF94A3B8)),
                  onPressed: () => Navigator.pop(context),
                )
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Mỗi dòng là 1 đường link Douyin / TikTok hoặc URL trực tiếp:',
              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF0B1120),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFF1E293B)),
                ),
                child: TextField(
                  controller: _controller,
                  maxLines: null,
                  expands: true,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: Colors.white),
                  decoration: const InputDecoration(
                    contentPadding: EdgeInsets.all(12),
                    border: InputBorder.none,
                    hintText: 'https://v.douyin.com/...',
                    hintStyle: TextStyle(color: Color(0xFF64748B)),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Hủy', style: TextStyle(color: Color(0xFF94A3B8))),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    foregroundColor: Colors.white,
                  ),
                  icon: _isSaving
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.save, size: 16),
                  label: const Text('Lưu File'),
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
