import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:convert';
import '../core/app_colors.dart';
import '../core/python_bridge.dart';
import 'app_kit.dart';

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
import json, sys, os
from pathlib import Path

cwd = Path(os.getcwd()).resolve()
candidates = [
    cwd,
    cwd.parent,
    cwd / "py_engine",
    cwd.parent / "py_engine",
]
for p in candidates:
    if p.exists():
        if (p / "utils" / "storage_manager.py").exists() and str(p) not in sys.path:
            sys.path.insert(0, str(p))
        elif (p / "py_engine" / "utils" / "storage_manager.py").exists() and str(p / "py_engine") not in sys.path:
            sys.path.insert(0, str(p / "py_engine"))

try:
    from utils.storage_manager import StorageManager
except ImportError:
    try:
        from py_engine.utils.storage_manager import StorageManager
    except ImportError as err:
        print(json.dumps({
            "connected": False,
            "error": "Không tìm thấy module storage_manager trong py_engine.",
            "bucket": "",
            "key_file": "",
            "key_exists": False
        }))
        sys.exit(0)

mgr = StorageManager()
key_path = sys.argv[1] if len(sys.argv) > 1 and sys.argv[1] else None
bucket = sys.argv[2] if len(sys.argv) > 2 and sys.argv[2] else None
prefix = sys.argv[3] if len(sys.argv) > 3 and sys.argv[3] else None

if key_path:
    mgr.key_file = mgr._resolve_key_file(key_path)
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
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: AppColors.border, width: 0.8),
      ),
      child: Container(
        width: 500,
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title Header
            Row(
              children: [
                const Icon(Icons.cloud_sync, color: AppColors.primary, size: 18),
                const SizedBox(width: 8),
                const Text(
                  'Cấu Hình Google Cloud Storage (GCS)',
                  style: TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, color: AppColors.textSecondary, size: 16),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),

            const SizedBox(height: 14),

            // 1. Key file path using AppInputGroup
            AppInputGroup(
              label: 'Đường Dẫn Service Account Key (JSON):',
              field: AppTextField(
                controller: _keyPathCtrl,
                isMonospace: true,
                hint: 'resources/gcs-key.json hoặc đường dẫn tuyệt đối...',
              ),
              button: AppButton.outlined(
                icon: Icons.folder_open,
                label: 'Chọn File',
                height: 34,
                fontSize: 11,
                onPressed: _pickKeyFile,
              ),
            ),
            const SizedBox(height: 12),

            // 2. Bucket Name
            AppTextField(
              label: 'Tên GCS Bucket:',
              controller: _bucketCtrl,
              hint: 'service-qa-beta',
            ),
            const SizedBox(height: 12),

            // 3. Base Prefix
            AppTextField(
              label: 'Prefix Thư Mục Gốc (Base Prefix):',
              controller: _prefixCtrl,
              hint: 'video-tiktok-volumn',
            ),

            const SizedBox(height: 14),

            // 4. Test connection status feedback
            if (_testMessage.isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _testSuccess == true ? AppColors.statusCompletedBg : AppColors.statusFailedBg,
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(
                    color: _testSuccess == true ? AppColors.statusCompleted : AppColors.statusFailed,
                    width: 0.8,
                  ),
                ),
                child: Text(
                  _testMessage,
                  style: TextStyle(
                    fontSize: 11,
                    color: _testSuccess == true ? AppColors.statusCompleted : AppColors.statusFailed,
                  ),
                ),
              ),

            const SizedBox(height: 16),

            // Actions: Test connection & Save using AppButton
            Row(
              children: [
                AppButton.secondary(
                  icon: Icons.bolt,
                  label: 'Kiểm Tra Kết Nối',
                  isLoading: _isTesting,
                  fontSize: 11,
                  onPressed: _isTesting ? null : _testConnection,
                ),
                const Spacer(),
                AppButton.ghost(
                  label: 'Hủy',
                  fontSize: 11.5,
                  onPressed: () => Navigator.pop(context),
                ),
                const SizedBox(width: 8),
                AppButton.primary(
                  icon: Icons.save,
                  label: 'Lưu Cấu Hình',
                  fontSize: 11.5,
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
