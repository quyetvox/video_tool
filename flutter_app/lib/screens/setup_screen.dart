import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/app_colors.dart';
import '../core/gcp_connection_tester.dart';
import '../core/providers.dart';
import '../core/setup_service.dart';
import '../models/models_status.dart';
import '../widgets/app_kit.dart';
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
              child: const Text('Đóng', style: TextStyle(color: AppColors.primary)),
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
    final c = AppColors.of(context);
    final isDark = AppColors.isDark(context);
    final modelsStatusAsync = ref.watch(modelsStatusProvider);

    return Container(
      color: c.background,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Header
          Row(
            children: [
              Icon(Icons.hub_outlined, color: c.primary, size: 20),
              const SizedBox(width: 8),
              Text(
                'Cấu Hình Đường Dẫn Dự Án & AI Models Offline',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5, color: c.textPrimary),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // ── SECTION 0: Engine Selection Dual Mode ────────────────────
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(
                color: c.statusCompleted,
                width: 1.0,
              ),
            ),
            color: c.surface,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.statusCompletedBg,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(
                      Icons.psychology_rounded,
                      color: AppColors.statusCompleted,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text(
                              '⚡ AI Core Engine (Whisper / Demucs / EdgeTTS)',
                              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Colors.white),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.statusCompletedBg,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'Đang Kích Hoạt',
                                style: TextStyle(fontSize: 10, color: AppColors.statusCompleted, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Sử dụng Sidecar Python Daemon hiệu năng cao nhúng sẵn (Local offline, không cần cài đặt thêm).',
                          style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),

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
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: c.border, width: 0.8),
          ),
          color: c.surface,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.folder_special_outlined, size: 17, color: c.primary),
                    const SizedBox(width: 8),
                    Text('Đường Dẫn Tài Nguyên & Thư Mục Dự Án', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: c.textPrimary)),
                  ],
                ),
                const SizedBox(height: 16),

                // 1. Projects Directory
                AppInputGroup(
                  label: '1. Thư mục Dự án Mặc định (projects_dir):',
                  field: AppTextField(
                    controller: _projectsDirController,
                    isMonospace: true,
                    hint: '/path/to/Sub-Video/resources',
                  ),
                  button: AppButton.outlined(
                    label: 'Chọn thư mục',
                    icon: Icons.folder_open,
                    height: 34,
                    onPressed: _pickProjectsDir,
                  ),
                ),
                const SizedBox(height: 16),

                // 2. Models Directory
                AppInputGroup(
                  label: '2. Thư mục chứa AI Models (models/ hoặc SSD ngoài):',
                  field: AppTextField(
                    controller: _modelsDirController,
                    isMonospace: true,
                    hint: '/path/to/models',
                  ),
                  button: AppButton.outlined(
                    label: 'Chọn thư mục',
                    icon: Icons.folder_open,
                    height: 34,
                    onPressed: _pickModelsDir,
                  ),
                ),
                const SizedBox(height: 16),

                // 3. Fonts Directory
                AppInputGroup(
                  label: '3. Thư mục Chứa Font Chữ (.ttf, .otf):',
                  field: AppTextField(
                    controller: _fontsDirController,
                    isMonospace: true,
                    hint: '/path/to/assets/fonts',
                  ),
                  button: AppButton.outlined(
                    label: 'Chọn thư mục',
                    icon: Icons.folder_open,
                    height: 34,
                    onPressed: _pickFontsDir,
                  ),
                ),
                const SizedBox(height: 16),

                // 4. Google Cloud Storage Service Account Key JSON
                Text('4. Cấu hình Google Cloud Storage (gcp-key.json / gcs-key.json):', style: TextStyle(fontSize: 11.5, color: c.textSecondary, fontWeight: FontWeight.w500)),
                const SizedBox(height: 3),
                Text('File Service Account JSON để xác thực đồng bộ Cloud Storage. Bạn có thể chọn file hoặc nhập đường dẫn trực tiếp.', style: TextStyle(fontSize: 10.5, color: c.textMuted)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: AppTextField(
                        controller: _gcsKeyPathController,
                        isMonospace: true,
                        hint: 'resources/gcs-key.json',
                      ),
                    ),
                    const SizedBox(width: 8),
                    AppButton.outlined(
                      label: 'Chọn file JSON',
                      icon: Icons.folder_open,
                      height: 34,
                      onPressed: _pickGcsKeyFile,
                    ),
                    const SizedBox(width: 8),
                    AppButton.secondary(
                      label: _isTestingGcp ? 'Đang kiểm tra...' : 'Kiểm Tra Kết Nối',
                      icon: Icons.network_check_rounded,
                      height: 34,
                      isLoading: _isTestingGcp,
                      onPressed: _isTestingGcp ? null : _testGcpKey,
                    ),
                  ],
                ),
                if (_gcpTestResult != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _gcpTestResult!.success ? c.statusCompletedBg : c.statusFailedBg,
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(
                        color: _gcpTestResult!.success ? c.statusCompleted : c.statusFailed,
                        width: 0.8,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _gcpTestResult!.success ? Icons.check_circle : Icons.error_outline,
                          color: _gcpTestResult!.success ? c.statusCompleted : c.statusFailed,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _gcpTestResult!.success
                                ? '✅ Hợp lệ! Project: ${_gcpTestResult!.projectId} | ${_gcpTestResult!.clientEmail}'
                                : '❌ ${_gcpTestResult!.message}',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: _gcpTestResult!.success ? c.statusCompleted : c.statusFailed,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 20),

                // Action Buttons
                Row(
                  children: [
                    AppButton.outlined(
                      label: 'Quét lại từ đĩa',
                      icon: Icons.refresh,
                      height: 34,
                      onPressed: () {
                        _loadSettings();
                        ref.invalidate(modelsStatusProvider);
                        ref.invalidate(projectsProvider);
                      },
                    ),
                    const Spacer(),
                    AppButton.primary(
                      label: _isSaving ? 'Đang lưu...' : 'Lưu Cấu Hình & Áp Dụng Toàn Hệ Thống',
                      icon: _isSaving ? Icons.sync : Icons.save,
                      height: 34,
                      isLoading: _isSaving,
                      onPressed: _isSaving ? null : _saveAllSettings,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

  Widget _buildChecklistCard(BuildContext context, ModelsStatus status, bool isDark) {
    final c = AppColors.of(context);
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: c.border, width: 0.8),
      ),
      color: c.surface,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.fact_check_outlined, size: 17, color: c.primary),
                const SizedBox(width: 8),
                Text('Kiểm Tra Trạng Thái Models Offline & Môi Trường', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: c.textPrimary)),
              ],
            ),
            const SizedBox(height: 14),
            _buildCheckItem(context, 'Whisper ASR Model Weights', status.whisperFound),
            _buildCheckItem(context, 'Demucs Music / Voice Separator', status.demucsFound),
            _buildCheckItem(context, 'PaddleOCR / RapidOCR Weights', status.paddleOcrFound),
            _buildCheckItem(context, 'Python Runtime & ML Libraries', status.pythonFound),
            _buildCheckItem(context, 'Rust Audio DSP Engine', status.rustDspFound),
          ],
        ),
      ),
    );
  }

  Widget _buildCheckItem(BuildContext context, String title, bool isAvailable) {
    final c = AppColors.of(context);
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
          Expanded(child: Text(title, style: TextStyle(fontSize: 13, color: c.textPrimary))),
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
