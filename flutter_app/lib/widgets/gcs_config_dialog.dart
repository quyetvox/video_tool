import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:convert';
import '../core/python_bridge.dart';

class GcsConfigDialog extends StatefulWidget {
  final String initialKeyPath;
  final String initialBucket;
  final String initialPrefix;
  final Function(String keyPath, String bucket, String prefix) onSave;

  const GcsConfigDialog({
    super.key,
    required this.initialKeyPath,
    required this.initialBucket,
    required this.initialPrefix,
    required this.onSave,
  });

  static Future<bool?> show(
    BuildContext context, {
    required String initialKeyPath,
    required String initialBucket,
    required String initialPrefix,
    required Function(String keyPath, String bucket, String prefix) onSave,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => GcsConfigDialog(
        initialKeyPath: initialKeyPath,
        initialBucket: initialBucket,
        initialPrefix: initialPrefix,
        onSave: onSave,
      ),
    );
  }

  @override
  State<GcsConfigDialog> createState() => _GcsConfigDialogState();
}

class _GcsConfigDialogState extends State<GcsConfigDialog> {
  late TextEditingController _keyPathCtrl;
  late TextEditingController _bucketCtrl;
  late TextEditingController _prefixCtrl;

  bool _isTesting = false;
  bool? _testSuccess;
  String _testMessage = '';

  @override
  void initState() {
    super.initState();
    _keyPathCtrl = TextEditingController(text: widget.initialKeyPath);
    _bucketCtrl = TextEditingController(text: widget.initialBucket);
    _prefixCtrl = TextEditingController(text: widget.initialPrefix);
  }

  @override
  void dispose() {
    _keyPathCtrl.dispose();
    _bucketCtrl.dispose();
    _prefixCtrl.dispose();
    super.dispose();
  }

  void _pickKeyFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      dialogTitle: 'Chọn file Service Account Key GCS (gcs-key.json)',
    );
    if (result != null && result.files.single.path != null) {
      setState(() {
        _keyPathCtrl.text = result.files.single.path!;
        _testSuccess = null;
        _testMessage = '';
      });
    }
  }

  void _testConnection() async {
    setState(() {
      _isTesting = true;
      _testSuccess = null;
      _testMessage = 'Đang kiểm tra kết nối GCS...';
    });

    final res = await PythonBridge.runCode('''
import json, sys
from pathlib import Path
try:
    from utils.storage_manager import StorageManager
except ImportError:
    from py_engine.utils.storage_manager import StorageManager

mgr = StorageManager()
key_path = sys.argv[1] if len(sys.argv) > 1 and sys.argv[1] else None
bucket = sys.argv[2] if len(sys.argv) > 2 and sys.argv[2] else None
prefix = sys.argv[3] if len(sys.argv) > 3 and sys.argv[3] else None

if key_path:
    mgr.key_file = Path(key_path).resolve()
if bucket:
    mgr.bucket_name = bucket
if prefix:
    mgr.base_prefix = prefix.strip("/")

connected = mgr.is_connected()
print(json.dumps({
    "connected": connected,
    "bucket": mgr.bucket_name,
    "prefix": mgr.base_prefix,
    "key_file": str(mgr.key_file) if mgr.key_file else "",
    "key_exists": bool(mgr.key_file and mgr.key_file.exists())
}))
''', extraArgs: [
      _keyPathCtrl.text.trim(),
      _bucketCtrl.text.trim(),
      _prefixCtrl.text.trim(),
    ]);

    setState(() => _isTesting = false);

    if (res.exitCode == 0) {
      try {
        final data = jsonDecode(res.stdout.toString().trim());
        final isConn = data['connected'] == true;
        setState(() {
          _testSuccess = isConn;
          if (isConn) {
            _testMessage = '🟢 Kết nối GCS thành công! Bucket: ${data["bucket"]}';
          } else {
            _testMessage = data['key_exists'] == false
                ? '❌ Không tìm thấy file key tại đường dẫn đã chỉ định.'
                : '❌ Không thể xác thực với Google Cloud Storage. Vui lòng kiểm tra quyền hạn của Service Account.';
          }
        });
      } catch (e) {
        setState(() {
          _testSuccess = false;
          _testMessage = 'Lỗi parse kết quả: $e';
        });
      }
    } else {
      setState(() {
        _testSuccess = false;
        _testMessage = 'Lỗi thực thi kiểm tra: ${res.stderr}';
      });
    }
  }

  void _handleSave() {
    widget.onSave(
      _keyPathCtrl.text.trim(),
      _bucketCtrl.text.trim(),
      _prefixCtrl.text.trim(),
    );
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF0F172A),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: Color(0xFF1E293B)),
      ),
      child: Container(
        width: 520,
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title Header
            Row(
              children: [
                const Icon(Icons.cloud_sync, color: Color(0xFF06B6D4), size: 20),
                const SizedBox(width: 8),
                const Text(
                  'Cấu Hình Google Cloud Storage (GCS)',
                  style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, color: Color(0xFF94A3B8), size: 18),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // 1. Key file path
            const Text(
              'Đường Dẫn Service Account Key (JSON):',
              style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _keyPathCtrl,
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontFamily: 'monospace'),
                    decoration: InputDecoration(
                      hintText: 'assets/gcs-key.json hoặc đường dẫn tuyệt đối...',
                      hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 11),
                      filled: true,
                      fillColor: const Color(0xFF0B1120),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: const BorderSide(color: Color(0xFF334155)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1E293B),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  ),
                  icon: const Icon(Icons.folder_open, size: 14),
                  label: const Text('Chọn File', style: TextStyle(fontSize: 11.5)),
                  onPressed: _pickKeyFile,
                ),
              ],
            ),

            const SizedBox(height: 12),

            // 2. Bucket Name
            const Text(
              'Tên GCS Bucket:',
              style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _bucketCtrl,
              style: const TextStyle(color: Colors.white, fontSize: 12),
              decoration: InputDecoration(
                hintText: 'service-qa-beta',
                hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 11),
                filled: true,
                fillColor: const Color(0xFF0B1120),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: const BorderSide(color: Color(0xFF334155)),
                ),
              ),
            ),

            const SizedBox(height: 12),

            // 3. Base Prefix
            const Text(
              'Prefix Thư Mục Gốc (Base Prefix):',
              style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _prefixCtrl,
              style: const TextStyle(color: Colors.white, fontSize: 12),
              decoration: InputDecoration(
                hintText: 'video-tiktok-volumn',
                hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 11),
                filled: true,
                fillColor: const Color(0xFF0B1120),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: const BorderSide(color: Color(0xFF334155)),
                ),
              ),
            ),

            const SizedBox(height: 14),

            // 4. Test connection status feedback
            if (_testMessage.isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _testSuccess == true
                      ? const Color(0xFF10B981).withOpacity(0.15)
                      : const Color(0xFFEF4444).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: _testSuccess == true ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                    width: 0.8,
                  ),
                ),
                child: Text(
                  _testMessage,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: _testSuccess == true ? const Color(0xFF34D399) : const Color(0xFFFCA5A5),
                  ),
                ),
              ),

            const SizedBox(height: 16),

            // Actions: Test connection & Save
            Row(
              children: [
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF06B6D4),
                    side: const BorderSide(color: Color(0xFF06B6D4)),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  icon: _isTesting
                      ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5, color: Color(0xFF06B6D4)))
                      : const Icon(Icons.bolt, size: 14),
                  label: const Text('Kiểm Tra Kết Nối', style: TextStyle(fontSize: 11.5)),
                  onPressed: _isTesting ? null : _testConnection,
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Hủy', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  ),
                  icon: const Icon(Icons.save, size: 14),
                  label: const Text('Lưu Cấu Hình', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  onPressed: _handleSave,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
