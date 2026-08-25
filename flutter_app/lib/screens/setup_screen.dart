import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/providers.dart';
import '../core/python_bridge.dart';
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
  final TextEditingController _pythonPathController = TextEditingController();
  final TextEditingController _gcsKeyPathController = TextEditingController();
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final pDir = await SetupService.getProjectsDir();
    final mDir = await SetupService.getModelsDir();
    final fDir = await SetupService.getFontsDir();
    final pyPath = await SetupService.getSavedPythonPath() ?? PythonBridge.resolvePythonBin();
    final gcsKey = await SetupService.getGcsKeyPath();
    setState(() {
      _projectsDirController.text = pDir;
      _modelsDirController.text = mDir;
      _fontsDirController.text = fDir;
      _pythonPathController.text = pyPath;
      _gcsKeyPathController.text = gcsKey;
    });
  }

  @override
  void dispose() {
    _projectsDirController.dispose();
    _modelsDirController.dispose();
    _fontsDirController.dispose();
    _pythonPathController.dispose();
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

  Future<void> _pickPythonBinary() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Chọn file thực thi Python (.venv/bin/python hoặc python.exe)',
      type: FileType.any,
    );
    if (result != null && result.files.single.path != null) {
      final path = result.files.single.path!;
      setState(() => _pythonPathController.text = path);
    }
  }

  Future<void> _pickGcsKeyFile() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Chọn file Service Account Key JSON của Google Cloud Storage (gcs-key.json)',
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (result != null && result.files.single.path != null) {
      final path = result.files.single.path!;
      setState(() => _gcsKeyPathController.text = path);
    }
  }

  Future<void> _saveAllSettings() async {
    setState(() => _isSaving = true);
    final pDir = _projectsDirController.text.trim();
    final mDir = _modelsDirController.text.trim();
    final fDir = _fontsDirController.text.trim();
    final pyPath = _pythonPathController.text.trim();
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
    if (pyPath.isNotEmpty) {
      await SetupService.setSavedPythonPath(pyPath);
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
        const SizedBox(height: 6),
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
                            '⚡ AI Core Engine (Whisper MLX / Demucs / EdgeTTS)',
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
                        'Thực thi qua Sidecar Python Engine chuẩn hóa, hỗ trợ luồng log JSON thời gian thực và cập nhật Hot-Patch siêu tốc.',
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
                const Text('Chứa các file weights offline của Whisper ASR, Demucs AI và PaddleOCR.', style: TextStyle(fontSize: 11, color: Colors.grey)),
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

                // 4. Python Path
                const Text('4. Đường dẫn file thực thi Python Core (.venv):', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                const Text('File nhị phân Python chứa các thư viện mlx, torch, demucs, paddleocr.', style: TextStyle(fontSize: 11, color: Colors.grey)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _pythonPathController,
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                        decoration: InputDecoration(
                          hintText: '/path/to/.venv/bin/python',
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.code, size: 16),
                      label: const Text('Chọn file Python'),
                      onPressed: _pickPythonBinary,
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // 4. Google Cloud Storage Service Account Key JSON
                const Text('4. Đường dẫn file Key Google Cloud Storage (gcs-key.json):', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                const Text('File Service Account JSON để xác thực đồng bộ Cloud Storage (mặc định: assets/gcs-key.json).', style: TextStyle(fontSize: 11, color: Colors.grey)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _gcsKeyPathController,
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                        decoration: InputDecoration(
                          hintText: '/path/to/assets/gcs-key.json',
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
                  ],
                ),
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
        side: BorderSide(
          color: status.allReady ? Colors.green.withOpacity(0.5) : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
        ),
      ),
      color: isDark ? const Color(0xFF1E293B) : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  status.allReady ? Icons.check_circle : Icons.warning_amber_rounded,
                  color: status.allReady ? Colors.greenAccent : Colors.orangeAccent,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Text(
                  status.allReady ? 'Tất cả Models AI & Môi Trường Đã Sẵn Sàng 100%' : 'Trạng Thái Kiểm Tra Môi Trường AI',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ],
            ),
            const SizedBox(height: 16),

            _buildStatusTile('Rust Native Audio DSP Core', status.rustDspFound, 'FFT Spectral Noise Gate, VAD Snapping & Gender Detect', 'libsub_video_audio_dsp.dylib'),
            const Divider(height: 16),
            _buildStatusTile('Whisper ASR Speech-to-Text', status.whisperFound || status.whisperGgmlFound, 'Nhận diện giọng nói MLX / Whisper GGML', 'models/ggml & HuggingFace Hub'),
            const Divider(height: 16),
            _buildStatusTile('Demucs AI Vocal Separator', status.demucsFound || status.demucsOnnxFound, 'Tách giọng nói & nhạc nền (2-Stem)', 'models/onnx & HuggingFace Hub'),
            const Divider(height: 16),
            _buildStatusTile('Apple Vision OCR / PaddleOCR', status.paddleOcrFound, 'Nhận diện chữ sub cứng trên hình ảnh', 'Apple Vision Framework & PaddleOCR'),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusTile(String title, bool isFound, String description, String path) {
    return Row(
      children: [
        Icon(
          isFound ? Icons.check_circle : Icons.cancel_outlined,
          color: isFound ? Colors.greenAccent : Colors.redAccent,
          size: 18,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 2),
              Text(description, style: const TextStyle(fontSize: 11, color: Colors.grey)),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: isFound ? Colors.green.withOpacity(0.15) : Colors.red.withOpacity(0.15),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            isFound ? 'Đã có sẵn' : 'Chưa tìm thấy',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: isFound ? Colors.greenAccent.shade400 : Colors.redAccent,
            ),
          ),
        ),
      ],
    );
  }
}
