import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/app_colors.dart';
import '../core/gcp_connection_tester.dart';
import '../core/providers.dart';
import '../core/python_bridge.dart';
import '../core/setup_service.dart';
import '../models/models_status.dart';
import '../widgets/app_kit.dart';
import '../widgets/hot_patch_manager_card.dart';
import '../core/ai_environment_service.dart';
import '../widgets/ai_setup_dialog.dart';

class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key});

  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  final TextEditingController _projectsDirController = TextEditingController();
  final TextEditingController _fontsDirController = TextEditingController();
  final TextEditingController _gcsKeyPathController = TextEditingController();
  final TextEditingController _bucketController = TextEditingController();
  final TextEditingController _prefixController = TextEditingController();

  List<String> _availableBuckets = [];
  List<String> _availablePrefixes = [];
  bool _isSaving = false;
  bool _isTestingGcp = false;
  bool _isDiscoveringGcs = false;
  bool _canListBuckets = true;
  GcpTestResult? _gcpTestResult;
  bool _isAiReady = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final pDir = await SetupService.getProjectsDir();
    final fDir = await SetupService.getFontsDir();
    final gcsKey = await SetupService.getGcsKeyPath();
    final isAi = await AiEnvironmentService.isAiReady();
    final config = ref.read(configProvider);
    if (mounted) {
      setState(() {
        _isAiReady = isAi;
        _projectsDirController.text = pDir;
        _fontsDirController.text = fDir;
        _gcsKeyPathController.text = gcsKey;
        _bucketController.text = config.storageBucketName.isNotEmpty ? config.storageBucketName : 'service-qa-beta';
        _prefixController.text = config.storageBasePrefix.isNotEmpty ? config.storageBasePrefix : 'video-tiktok-volumn';
      });

      if (gcsKey.isNotEmpty && File(gcsKey).existsSync()) {
        _discoverGcs(gcsKey, targetBucket: _bucketController.text.trim());
      }
    }
  }

  @override
  void dispose() {
    _projectsDirController.dispose();
    _fontsDirController.dispose();
    _gcsKeyPathController.dispose();
    _bucketController.dispose();
    _prefixController.dispose();
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
      dialogTitle: 'Chọn file Service Account Key JSON của Google Cloud Storage (gcp-key.json / gcs-key.json)',
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (result != null && result.files.single.path != null) {
      final path = result.files.single.path!;
      setState(() {
        _gcsKeyPathController.text = path;
        _gcpTestResult = null;
      });
      // Automatically trigger GCS discovery on file pick
      _discoverGcs(path, showFeedback: true);
    }
  }

  Future<void> _discoverGcs(
    String keyPath, {
    String? targetBucket,
    bool showFeedback = false,
    bool showDialogResult = false,
  }) async {
    final cleanKey = keyPath.trim();
    if (cleanKey.isEmpty) {
      if (showFeedback && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⚠️ Vui lòng chọn hoặc nhập đường dẫn file Service Account Key JSON trước.'),
            backgroundColor: AppColors.statusFailed,
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    setState(() {
      _isTestingGcp = true;
      _isDiscoveringGcs = true;
    });

    final args = ['discover', '--key', cleanKey];
    final bucketToQuery = (targetBucket != null && targetBucket.isNotEmpty)
        ? targetBucket
        : _bucketController.text.trim();
    if (bucketToQuery.isNotEmpty) {
      args.addAll(['--bucket', bucketToQuery]);
    }

    try {
      final res = await PythonBridge.runScript(
        'storage.py',
        args,
        jobId: 'gcs_discover_${DateTime.now().millisecondsSinceEpoch}',
      );

      String? jsonStr;
      for (final line in res.stdoutLines) {
        final t = line.trim();
        if (t.startsWith('{') && t.endsWith('}')) {
          jsonStr = t;
          break;
        }
      }

      if (jsonStr != null) {
        final data = jsonDecode(jsonStr) as Map<String, dynamic>;
        final success = data['success'] == true;
        if (success) {
          final buckets = (data['buckets'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
          final prefixes = (data['prefixes'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
          final currentBucket = data['current_bucket']?.toString() ?? '';
          final canList = data['can_list_buckets'] == true;
          final projectId = data['project_id']?.toString() ?? '';
          final clientEmail = data['client_email']?.toString() ?? '';

          if (mounted) {
            setState(() {
              _availableBuckets = buckets;
              _availablePrefixes = prefixes;
              _canListBuckets = canList;

              if (_bucketController.text.trim().isEmpty && currentBucket.isNotEmpty) {
                _bucketController.text = currentBucket;
              } else if (_bucketController.text.trim().isEmpty && projectId.isNotEmpty) {
                _bucketController.text = projectId;
              }

              if (_prefixController.text.trim().isEmpty && prefixes.isNotEmpty) {
                _prefixController.text = prefixes.first;
              }

              _gcpTestResult = GcpTestResult(
                success: true,
                message: canList
                    ? 'Kết nối GCS thành công! Đã tìm thấy ${buckets.length} buckets & ${prefixes.length} thư mục.'
                    : 'Kết nối GCS thành công! Đã tải ${prefixes.length} thư mục trong bucket.',
                projectId: projectId,
                clientEmail: clientEmail,
              );
            });

            if (showFeedback && mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('🟢 Đã quét thành công GCS! Bucket: ${_bucketController.text} (${prefixes.length} thư mục)'),
                  backgroundColor: AppColors.statusCompleted,
                  duration: const Duration(seconds: 2),
                ),
              );
            }

            if (showDialogResult && mounted) {
              _showGcpResultDialog(_gcpTestResult!);
            }
          }
        } else {
          final errorMsg = data['error']?.toString() ?? 'Không thể kết nối đến GCS.';
          final errResult = GcpTestResult(
            success: false,
            message: errorMsg,
          );
          if (mounted) {
            setState(() => _gcpTestResult = errResult);
            if (showFeedback) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('❌ Lỗi GCS: $errorMsg'),
                  backgroundColor: AppColors.statusFailed,
                  duration: const Duration(seconds: 3),
                ),
              );
            }
            if (showDialogResult) {
              _showGcpResultDialog(errResult);
            }
          }
        }
      } else {
        final fallback = await GcpConnectionTester.testKeyFile(cleanKey);
        if (mounted) {
          setState(() => _gcpTestResult = fallback);
          if (showDialogResult) {
            _showGcpResultDialog(fallback);
          }
        }
      }
    } catch (e) {
      final errResult = GcpTestResult(
        success: false,
        message: 'Lỗi thực thi kiểm tra GCS: $e',
      );
      if (mounted) {
        setState(() => _gcpTestResult = errResult);
        if (showDialogResult) {
          _showGcpResultDialog(errResult);
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _isTestingGcp = false;
          _isDiscoveringGcs = false;
        });
      }
    }
  }

  void _showGcpResultDialog(GcpTestResult res) {
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
              const SizedBox(height: 6),
              _buildGcpInfoLine('GCS Bucket:', _bucketController.text),
              const SizedBox(height: 6),
              _buildGcpInfoLine('Base Prefix:', _prefixController.text),
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
    final fDir = _fontsDirController.text.trim();
    final gcsKey = _gcsKeyPathController.text.trim();
    final bucket = _bucketController.text.trim();
    final prefix = _prefixController.text.trim();

    if (pDir.isNotEmpty) {
      await ref.read(projectsDirProvider.notifier).setDir(pDir);
    }
    if (fDir.isNotEmpty) {
      await SetupService.setFontsDir(fDir);
      ref.invalidate(availableFontsProvider);
    }
    if (gcsKey.isNotEmpty) {
      await SetupService.setGcsKeyPath(gcsKey);
    }

    // Update configProvider with storage settings and persist to config.yaml
    final configNotifier = ref.read(configProvider.notifier);
    configNotifier.setField((c) => c.copyWith(
      storageKeyFile: gcsKey.isNotEmpty ? gcsKey : c.storageKeyFile,
      storageBucketName: bucket.isNotEmpty ? bucket : c.storageBucketName,
      storageBasePrefix: prefix.isNotEmpty ? prefix : c.storageBasePrefix,
    ));
    await configNotifier.save();

    // Invalidate cloud storage to reconnect with updated credentials
    ref.read(cloudStorageProvider.notifier).invalidateAll();

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

                // 2. Fonts Directory
                AppInputGroup(
                  label: '2. Thư mục Chứa Font Chữ (.ttf, .otf):',
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

                // 3. Google Cloud Storage Service Account Key JSON
                Row(
                  children: [
                    Icon(Icons.cloud_sync_outlined, size: 15, color: c.primary),
                    const SizedBox(width: 6),
                    Text(
                      '3. Cấu hình Google Cloud Storage (gcp-key.json / gcs-key.json):',
                      style: TextStyle(fontSize: 11.5, color: c.textSecondary, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  'Khi trỏ đến file Service Account JSON, hệ thống sẽ tự động quét danh sách Bucket và Base Prefix để bạn chọn nhanh.',
                  style: TextStyle(fontSize: 10.5, color: c.textMuted),
                ),
                const SizedBox(height: 8),

                // Key file picker row
                Row(
                  children: [
                    Expanded(
                      child: AppTextField(
                        controller: _gcsKeyPathController,
                        isMonospace: true,
                        hint: 'resources/gcs-key.json',
                        onSubmitted: (val) {
                          if (val.trim().isNotEmpty) {
                            _discoverGcs(val.trim(), targetBucket: _bucketController.text.trim(), showFeedback: true);
                          }
                        },
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
                      label: _isTestingGcp || _isDiscoveringGcs ? 'Đang quét...' : 'Quét & Kiểm Tra GCS',
                      icon: Icons.network_check_rounded,
                      height: 34,
                      isLoading: _isTestingGcp || _isDiscoveringGcs,
                      onPressed: (_isTestingGcp || _isDiscoveringGcs)
                          ? null
                          : () => _discoverGcs(
                                _gcsKeyPathController.text.trim(),
                                targetBucket: _bucketController.text.trim(),
                                showFeedback: true,
                                showDialogResult: true,
                              ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Row: Bucket Name & Base Prefix
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 3.1 Bucket Name (Editable Combobox)
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                'Tên GCS Bucket:',
                                style: TextStyle(fontSize: 11, color: c.textSecondary, fontWeight: FontWeight.w500),
                              ),
                              if (_availableBuckets.isNotEmpty) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: c.primary.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    '${_availableBuckets.length} buckets',
                                    style: TextStyle(fontSize: 9.5, color: c.primary, fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ] else if (!_canListBuckets) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: AppColors.statusProcessingBg,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text(
                                    'Nhập tay bucket',
                                    style: TextStyle(fontSize: 9.5, color: AppColors.statusProcessing, fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Expanded(
                                child: AppTextField(
                                  controller: _bucketController,
                                  hint: 'service-qa-beta',
                                  isMonospace: true,
                                  onSubmitted: (val) {
                                    if (val.trim().isNotEmpty && _gcsKeyPathController.text.trim().isNotEmpty) {
                                      _discoverGcs(_gcsKeyPathController.text.trim(), targetBucket: val.trim(), showFeedback: true);
                                    }
                                  },
                                ),
                              ),
                              if (_availableBuckets.isNotEmpty) ...[
                                const SizedBox(width: 4),
                                PopupMenuButton<String>(
                                  tooltip: 'Chọn từ danh sách Bucket trên GCP',
                                  icon: Icon(Icons.arrow_drop_down_circle_outlined, size: 20, color: c.primary),
                                  onSelected: (val) {
                                    _bucketController.text = val;
                                    _discoverGcs(_gcsKeyPathController.text.trim(), targetBucket: val, showFeedback: true);
                                  },
                                  itemBuilder: (ctx) => _availableBuckets
                                      .map((b) => PopupMenuItem(
                                            value: b,
                                            child: Text(b, style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
                                          ))
                                      .toList(),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 14),

                    // 3.2 Base Prefix (Editable Combobox)
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                'Prefix Thư Mục Gốc (Base Prefix):',
                                style: TextStyle(fontSize: 11, color: c.textSecondary, fontWeight: FontWeight.w500),
                              ),
                              if (_availablePrefixes.isNotEmpty) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: c.statusCompleted.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    '${_availablePrefixes.length} folders',
                                    style: TextStyle(fontSize: 9.5, color: c.statusCompleted, fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Expanded(
                                child: AppTextField(
                                  controller: _prefixController,
                                  hint: 'video-tiktok-volumn',
                                  isMonospace: true,
                                ),
                              ),
                              if (_availablePrefixes.isNotEmpty) ...[
                                const SizedBox(width: 4),
                                PopupMenuButton<String>(
                                  tooltip: 'Chọn từ các thư mục có sẵn trong Bucket',
                                  icon: Icon(Icons.folder_shared_outlined, size: 20, color: c.statusCompleted),
                                  onSelected: (val) {
                                    setState(() => _prefixController.text = val);
                                  },
                                  itemBuilder: (ctx) => _availablePrefixes
                                      .map((p) => PopupMenuItem(
                                            value: p,
                                            child: Text(p, style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
                                          ))
                                      .toList(),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
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
            _buildCheckItem(
              context,
              Platform.isMacOS
                  ? 'Apple Vision OCR (macOS Native)'
                  : 'RapidOCR Engine (ONNX Runtime)',
              status.paddleOcrFound,
            ),
            _buildCheckItem(context, 'Python Runtime (Base Engine)', status.pythonFound),
            const SizedBox(height: 6),
            const Divider(height: 1),
            const SizedBox(height: 6),
            _buildAiRuntimeCheckItem(context),
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

  Widget _buildAiRuntimeCheckItem(BuildContext context) {
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            _isAiReady ? Icons.check_circle : Icons.warning_amber_rounded,
            color: _isAiReady ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Gói AI Nâng Cao (Torch CPU, Demucs, Whisper)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: c.textPrimary)),
                Text('Tải theo yêu cầu để giảm kích thước cài đặt ban đầu', style: TextStyle(fontSize: 11, color: c.textMuted)),
              ],
            ),
          ),
          if (!_isAiReady)
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF8B5CF6),
                side: const BorderSide(color: Color(0xFF8B5CF6), width: 0.8),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                minimumSize: const Size(0, 28),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
              ),
              icon: const Icon(Icons.cloud_download, size: 14),
              label: const Text('Cài đặt ngay', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
              onPressed: () async {
                final ok = await AiSetupDialog.show(context);
                if (ok) {
                  final ready = await AiEnvironmentService.isAiReady();
                  if (mounted) setState(() => _isAiReady = ready);
                  ref.invalidate(modelsStatusProvider);
                }
              },
            )
          else
            const Text(
              'Sẵn sàng',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Color(0xFF10B981),
              ),
            ),
        ],
      ),
    );
  }
}
