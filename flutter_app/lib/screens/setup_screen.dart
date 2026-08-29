import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/gcp_connection_tester.dart';
import '../core/providers.dart';
import '../core/setup_service.dart';
import '../models/models_status.dart';
import '../widgets/hot_patch_manager_card.dart';

class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key});

  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  final TextEditingController _projectsDirController = TextEditingController();
  final TextEditingController _modelsDirController = TextEditingController();
  final TextEditingController _fontsDirController = TextEditingController();
  final TextEditingController _gcsKeyPathController = TextEditingController();
  bool _isSaving = false;
  bool _isTestingGcp = false;
  GcpTestResult? _gcpTestResult;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final pDir = await SetupService.getProjectsDir();
    final mDir = await SetupService.getModelsDir();
    final fDir = await SetupService.getFontsDir();
    final gcsKey = await SetupService.getGcsKeyPath();
    setState(() {
      _projectsDirController.text = pDir;
      _modelsDirController.text = mDir;
      _fontsDirController.text = fDir;
      _gcsKeyPathController.text = gcsKey;
    });
  }

  @override
  void dispose() {
    _projectsDirController.dispose();
    _modelsDirController.dispose();
    _fontsDirController.dispose();
    _gcsKeyPathController.dispose();
    super.dispose();
  }

  Future<void> _pickProjectsDir() async {
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Chọn Thư Mục Cha Chứa Các Dự Án (assets/ hoặc Folder ngoài)',
    );
    if (result != null && result.isNotEmpty) {
      setState(() => _projectsDirController.text = result);
    }
  }

  Future<void> _pickModelsDir() async {
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Chọn Thư Mục Chứa AI Models (models/ hoặc ổ SSD ngoài)',
    );
    if (result != null && result.isNotEmpty) {
      setState(() => _modelsDirController.text = result);
    }
  }

  Future<void> _pickFontsDir() async {
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Chọn Thư Mục Chứa Font Chữ (.ttf, .otf, .ttc)',
    );
    if (result != null && result.isNotEmpty) {
      setState(() => _fontsDirController.text = result);
    }
  }

  Future<void> _pickGcsKeyFile() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Chọn file Service Account Key JSON của Google Cloud Storage (gcp-key.json)',
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (result != null && result.files.single.path != null) {
      final path = result.files.single.path!;
      setState(() {
        _gcsKeyPathController.text = path;
        _gcpTestResult = null;
      });
    }
  }

  Future<void> _testGcpKey() async {
    setState(() => _isTestingGcp = true);
    final res = await GcpConnectionTester.testKeyFile(_gcsKeyPathController.text);
    setState(() {
      _isTestingGcp = false;
      _gcpTestResult = res;
    });

    if (mounted) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF0F172A),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: Row(
            children: [
              Icon(
                res.success ? Icons.check_circle : Icons.error_outline,
                color: res.success ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                size: 24,
              ),
              const SizedBox(width: 10),
              Text(
                res.success ? 'Kết Nối GCP Hợp Lệ' : 'Kiểm Tra GCP Thất Bại',
                style: const TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                res.message,
                style: TextStyle(
                  fontSize: 13,
                  color: res.success ? const Color(0xFF34D399) : const Color(0xFFF87171),
                ),
              ),
              if (res.success) ...[
                const Divider(color: Color(0xFF1E293B), height: 24),
                _buildGcpInfoLine('Project ID:', res.projectId ?? ''),
                const SizedBox(height: 6),
                _buildGcpInfoLine('Service Account:', res.clientEmail ?? ''),
                if (res.keyId != null) ...[
                  const SizedBox(height: 6),
                  _buildGcpInfoLine('Private Key ID:', res.keyId!),
                ],
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Đóng', style: TextStyle(color: Color(0xFF06B6D4))),
            ),
          ],
        ),
      );
    }
  }

  Widget _buildGcpInfoLine(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8), fontWeight: FontWeight.bold)),
        ),
        Expanded(
          child: SelectableText(
            value,
            style: const TextStyle(fontSize: 11, color: Colors.white, fontFamily: 'monospace'),
          ),
        ),
      ],
    );
  }

  Future<void> _saveAllSettings() async {
    setState(() => _isSaving = true);
    final pDir = _projectsDirController.text.trim();
    final mDir = _modelsDirController.text.trim();
    final fDir = _fontsDirController.text.trim();
    final gcsKey = _gcsKeyPathController.text.trim();

    if (pDir.isNotEmpty) {
      await ref.read(projectsDirProvider.notifier).setDir(pDir);
    }
    if (mDir.isNotEmpty) {
      await ref.read(modelsDirProvider.notifier).setDir(mDir);
    }
    if (fDir.isNotEmpty) {
      await SetupService.setFontsDir(fDir);
      ref.invalidate(availableFontsProvider);
    }
    if (gcsKey.isNotEmpty) {
      await SetupService.setGcsKeyPath(gcsKey);
    }

    ref.invalidate(projectsProvider);
    ref.invalidate(modelsStatusProvider);
    ref.invalidate(availableFontsProvider);

    setState(() => _isSaving = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('💾 Đã lưu cấu hình đường dẫn và cập nhật toàn hệ thống thành công!'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final modelsStatusAsync = ref.watch(modelsStatusProvider);

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        // Header
        const Row(
          children: [
            Icon(Icons.hub_outlined, color: Colors.cyanAccent, size: 24),
            SizedBox(width: 10),
            Text(
              'Cấu Hình Đường Dẫn Dự Án & AI Models Offline',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // ── SECTION 0: Engine Selection Dual Mode ────────────────────
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: const BorderSide(
              color: Color(0xFF10B981),
              width: 1.2,
            ),
          ),
          color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.psychology_rounded,
                    color: Colors.greenAccent,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text(
                            '⚡ AI Core Engine (Whisper / Demucs / EdgeTTS)',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.green.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'Đang Kích Hoạt',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.greenAccent,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Thực thi qua Sidecar Python Engine chuẩn hóa, tự động nhận diện runtime độc lập và cập nhật Hot-Patch siêu tốc.',
                        style: TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // ── SECTION 1: Status Checklist ──────────────────────────────
        modelsStatusAsync.when(
          data: (status) => _buildChecklistCard(context, status, isDark),
          loading: () => const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator())),
          error: (e, _) => Center(child: Text('Lỗi: $e', style: const TextStyle(color: Colors.redAccent))),
        ),
        const SizedBox(height: 20),

        // ── SECTION: Hot-Patch Sidecar Engine Manager ────────────────
        const HotPatchManagerCard(),
        const SizedBox(height: 20),

        // ── SECTION 2: Path Settings Form ────────────────────────────
        Card(
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
          ),
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.folder_special_outlined, size: 20, color: Colors.cyanAccent),
                    SizedBox(width: 8),
                    Text('Đường Dẫn Tài Nguyên & Thư Mục Dự Án', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  ],
                ),
                const SizedBox(height: 20),

                // 1. Projects Parent Directory
                const Text('1. Thư mục Cha chứa các Dự Án (Projects / assets folder):', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                const Text('Tất cả các folder dự án sẽ được quét và tạo mới tại thư mục này.', style: TextStyle(fontSize: 11, color: Colors.grey)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _projectsDirController,
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                        decoration: InputDecoration(
                          hintText: '/path/to/Sub-Video/assets',
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.folder_open, size: 16),
                      label: const Text('Chọn thư mục'),
                      onPressed: _pickProjectsDir,
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // 2. Models Directory
                const Text('2. Thư mục chứa AI Models (models/ hoặc SSD ngoài):', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                const Text('Chứa các file weights offline của Whisper ASR, Demucs AI và PaddleOCR / RapidOCR.', style: TextStyle(fontSize: 11, color: Colors.grey)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _modelsDirController,
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                        decoration: InputDecoration(
                          hintText: '/path/to/models',
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.folder_open, size: 16),
                      label: const Text('Chọn thư mục'),
                      onPressed: _pickModelsDir,
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // 3. Fonts Directory
                const Text('3. Thư mục Chứa Font Chữ (.ttf, .otf):', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                const Text('Chứa các file Font chữ nghệ thuật dùng cho Phụ đề (Sub Chính, Sub Phụ) và Logo Watermark.', style: TextStyle(fontSize: 11, color: Colors.grey)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _fontsDirController,
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                        decoration: InputDecoration(
                          hintText: '/path/to/assets/fonts',
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.folder_open, size: 16),
                      label: const Text('Chọn thư mục'),
                      onPressed: _pickFontsDir,
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // 4. Google Cloud Storage Service Account Key JSON
                const Text('4. Cấu hình Google Cloud Storage (gcp-key.json / gcs-key.json):', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                const Text('File Service Account JSON để xác thực đồng bộ Cloud Storage. Bạn có thể chọn file hoặc nhập đường dẫn trực tiếp.', style: TextStyle(fontSize: 11, color: Colors.grey)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _gcsKeyPathController,
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                        decoration: InputDecoration(
                          hintText: '/path/to/assets/gcp-key.json',
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.cloud_queue, size: 16, color: Color(0xFF38BDF8)),
                      label: const Text('Chọn file JSON'),
                      onPressed: _pickGcsKeyFile,
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0284C7),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      ),
                      icon: _isTestingGcp
                          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.network_check_rounded, size: 16),
                      label: Text(_isTestingGcp ? 'Đang kiểm tra...' : 'Kiểm Tra Kết Nối'),
                      onPressed: _isTestingGcp ? null : _testGcpKey,
                    ),
                  ],
                ),
                if (_gcpTestResult != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _gcpTestResult!.success ? const Color(0xFF064E3B) : const Color(0xFF7F1D1D),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: _gcpTestResult!.success ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _gcpTestResult!.success ? Icons.check_circle : Icons.error_outline,
                          color: _gcpTestResult!.success ? const Color(0xFF34D399) : const Color(0xFFF87171),
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _gcpTestResult!.success
                                ? '✅ Hợp lệ! Project: ${_gcpTestResult!.projectId} | ${_gcpTestResult!.clientEmail}'
                                : '❌ ${_gcpTestResult!.message}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: _gcpTestResult!.success ? const Color(0xFFD1FAE5) : const Color(0xFFFEE2E2),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 24),

                // Action Buttons
                Row(
                  children: [
                    OutlinedButton.icon(
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('Quét lại từ đĩa'),
                      onPressed: () {
                        _loadSettings();
                        ref.invalidate(modelsStatusProvider);
                        ref.invalidate(projectsProvider);
                      },
                    ),
                    const Spacer(),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.cyan.shade700,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                      ),
                      icon: Icon(_isSaving ? Icons.sync : Icons.save),
                      label: Text(
                        _isSaving ? 'Đang lưu...' : 'Lưu Cấu Hình & Áp Dụng Toàn Hệ Thống',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      onPressed: _isSaving ? null : _saveAllSettings,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildChecklistCard(BuildContext context, ModelsStatus status, bool isDark) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
      ),
      color: isDark ? const Color(0xFF1E293B) : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.fact_check_outlined, size: 20, color: Colors.cyanAccent),
                SizedBox(width: 8),
                Text('Kiểm Tra Trạng Thái Models Offline & Môi Trường', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              ],
            ),
            const SizedBox(height: 16),
            _buildCheckItem('Whisper ASR Model Weights', status.whisperFound),
            _buildCheckItem('Demucs Music / Voice Separator', status.demucsFound),
            _buildCheckItem('PaddleOCR / RapidOCR Weights', status.paddleOcrFound),
            _buildCheckItem('Python Runtime & ML Libraries', status.pythonFound),
            _buildCheckItem('Rust Audio DSP Engine', status.rustDspFound),
          ],
        ),
      ),
    );
  }

  Widget _buildCheckItem(String title, bool isAvailable) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            isAvailable ? Icons.check_circle : Icons.cancel,
            color: isAvailable ? const Color(0xFF10B981) : const Color(0xFFEF4444),
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(title, style: const TextStyle(fontSize: 13))),
          Text(
            isAvailable ? 'Sẵn sàng' : 'Chưa có',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: isAvailable ? const Color(0xFF10B981) : const Color(0xFFEF4444),
            ),
          ),
        ],
      ),
    );
  }
}
