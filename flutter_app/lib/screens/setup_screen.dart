import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/ai_environment_service.dart';
import '../core/app_colors.dart';
import '../core/gcp_connection_tester.dart';
import '../core/providers.dart';
import '../core/python_bridge.dart';
import '../core/setup_service.dart';
import '../widgets/hot_patch_manager_card.dart';
import 'setup/components/setup_components.dart';

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
        _bucketController.text = config.storageBucketName;
        _prefixController.text = config.storageBasePrefix;
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

    final configNotifier = ref.read(configProvider.notifier);
    configNotifier.setField((c) => c.copyWith(
      storageKeyFile: gcsKey.isNotEmpty ? gcsKey : c.storageKeyFile,
      storageBucketName: bucket.isNotEmpty ? bucket : c.storageBucketName,
      storageBasePrefix: prefix.isNotEmpty ? prefix : c.storageBasePrefix,
    ));
    await configNotifier.save();

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

          // ── SECTION 0: Engine Selection Dual Mode ──
          const SetupEngineStatusCard(),
          const SizedBox(height: 14),

          // ── SECTION 1: Status Checklist ──
          modelsStatusAsync.when(
            data: (status) => SetupChecklistCard(
              status: status,
              isAiReady: _isAiReady,
              onAiReadyChanged: (ready) {
                setState(() => _isAiReady = ready);
                ref.invalidate(modelsStatusProvider);
              },
            ),
            loading: () => const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator())),
            error: (e, _) => Center(child: Text('Lỗi: $e', style: const TextStyle(color: Colors.redAccent))),
          ),
          const SizedBox(height: 20),

          // ── SECTION: Hot-Patch Sidecar Engine Manager ──
          const HotPatchManagerCard(),
          const SizedBox(height: 20),

          // ── SECTION 2: Path Settings Form ──
          SetupPathsCard(
            projectsDirController: _projectsDirController,
            fontsDirController: _fontsDirController,
            onPickProjectsDir: _pickProjectsDir,
            onPickFontsDir: _pickFontsDir,
          ),
          const SizedBox(height: 16),

          // ── SECTION 3: GCS Settings Form ──
          SetupGcsCard(
            gcsKeyPathController: _gcsKeyPathController,
            bucketController: _bucketController,
            prefixController: _prefixController,
            availableBuckets: _availableBuckets,
            availablePrefixes: _availablePrefixes,
            canListBuckets: _canListBuckets,
            isTestingGcp: _isTestingGcp,
            isDiscoveringGcs: _isDiscoveringGcs,
            gcpTestResult: _gcpTestResult,
            onPickGcsKeyFile: _pickGcsKeyFile,
            onDiscoverGcs: ({bool showFeedback = false, bool showDialogResult = false}) {
              _discoverGcs(
                _gcsKeyPathController.text.trim(),
                targetBucket: _bucketController.text.trim(),
                showFeedback: showFeedback,
                showDialogResult: showDialogResult,
              );
            },
            onBucketSelected: (val) {
              _bucketController.text = val;
              _discoverGcs(_gcsKeyPathController.text.trim(), targetBucket: val, showFeedback: true);
            },
            onPrefixSelected: (val) {
              setState(() => _prefixController.text = val);
            },
            onReloadSettings: () {
              _loadSettings();
              ref.invalidate(modelsStatusProvider);
              ref.invalidate(projectsProvider);
            },
            onSaveSettings: _saveAllSettings,
            isSaving: _isSaving,
          ),
        ],
      ),
    );
  }
}
