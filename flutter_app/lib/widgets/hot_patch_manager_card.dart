import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/app_colors.dart';
import '../core/engine_update_service.dart';
import '../core/providers.dart';
import '../widgets/app_kit.dart';

class HotPatchManagerCard extends ConsumerStatefulWidget {
  const HotPatchManagerCard({super.key});

  @override
  ConsumerState<HotPatchManagerCard> createState() => _HotPatchManagerCardState();
}

class _HotPatchManagerCardState extends ConsumerState<HotPatchManagerCard> {
  final TextEditingController _sourceController = TextEditingController();
  ActiveEngineInfo? _engineInfo;
  bool _isLoading = false;
  bool _isChecking = false;
  bool _isApplying = false;
  double _applyProgress = 0.0;
  String _statusMessage = '';
  EngineUpdateInfo? _availableUpdate;
  bool _showSourceConfig = false;

  @override
  void initState() {
    super.initState();
    _initData();
  }

  Future<void> _initData() async {
    final url = await EngineUpdateService.getManifestUrl();
    _sourceController.text = url;
    await _loadEngineInfo();
  }

  @override
  void dispose() {
    _sourceController.dispose();
    super.dispose();
  }

  Future<void> _loadEngineInfo() async {
    setState(() => _isLoading = true);
    final info = await EngineUpdateService.getActiveEngineInfo();
    if (mounted) {
      setState(() {
        _engineInfo = info;
        _isLoading = false;
      });
      // Synchronize global TopHeader patch badge
      ref.read(activeEngineRefreshProvider.notifier).state++;
    }
  }

  Future<void> _saveSource() async {
    await EngineUpdateService.setManifestUrl(_sourceController.text.trim());
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã lưu nguồn cập nhật bản vá!')),
      );
    }
  }

  Future<void> _pickLocalSource() async {
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Chọn Thư Mục Bản Vá Cục Bộ (dist/engine_patch hoặc folder chứa binary)',
    );
    if (result != null && result.isNotEmpty) {
      setState(() {
        _sourceController.text = result;
        _showSourceConfig = true;
      });
      await _saveSource();
      await _checkUpdate();
    }
  }

  Future<void> _checkUpdate() async {
    final source = _sourceController.text.trim();
    await _saveSource();

    setState(() {
      _isChecking = true;
      _statusMessage = 'Đang kiểm tra nguồn bản vá ($source)...';
      _availableUpdate = null;
    });

    try {
      final update = await EngineUpdateService.checkUpdate(customSource: source);
      if (mounted) {
        setState(() {
          _isChecking = false;
          _availableUpdate = update;
          _statusMessage = update != null
              ? '✨ Đã tìm thấy bản vá mới: ${update.version}'
              : '✅ Lõi Engine hiện tại đang là phiên bản mới nhất.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isChecking = false;
          _statusMessage = '❌ Lỗi kiểm tra cập nhật: $e';
        });
      }
    }
  }

  Future<void> _applyUpdate() async {
    if (_availableUpdate == null) return;
    setState(() {
      _isApplying = true;
      _applyProgress = 0.0;
      _statusMessage = 'Đang chuẩn bị áp dụng bản vá...';
    });

    try {
      await EngineUpdateService.applyPatch(
        _availableUpdate!,
        onProgress: (progress, status) {
          if (mounted) {
            setState(() {
              _applyProgress = progress;
              _statusMessage = status;
            });
          }
        },
      );

      await _loadEngineInfo();
      if (mounted) {
        setState(() {
          _isApplying = false;
          _availableUpdate = null;
          _statusMessage = '🎉 Đã áp dụng thành công bản vá ${_engineInfo?.version}!';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isApplying = false;
          _statusMessage = '❌ Lỗi áp dụng bản vá: $e';
        });
      }
    }
  }

  Future<void> _applyLocalZip() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Chọn File Bản Vá Engine (.zip)',
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );

    if (result != null && result.files.single.path != null) {
      setState(() {
        _isLoading = true;
        _statusMessage = 'Đang nạp bản vá từ file zip...';
      });

      try {
        await EngineUpdateService.applyLocalZipPatch(result.files.single.path!);
        await _loadEngineInfo();
        if (mounted) {
          setState(() {
            _isLoading = false;
            _statusMessage = '🎉 Đã nạp thành công bản vá từ file cục bộ!';
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _statusMessage = '❌ Nạp file thất bại: $e';
          });
        }
      }
    }
  }

  Future<void> _rollbackToBundled() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Khôi Phục Lõi Mặc Định?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Thao tác này sẽ xoá bản vá hiện tại và quay về sử dụng lõi gốc đi kèm theo App.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Huỷ', style: TextStyle(color: AppColors.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.statusFailed),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Khôi Phục', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await EngineUpdateService.rollbackPatch();
      await _loadEngineInfo();
      if (mounted) {
        setState(() {
          _statusMessage = '↩️ Đã xoá bản vá và khôi phục lõi mặc định!';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final isHotPatch = _engineInfo?.source == 'hot_patch';
    final isDevSource = _engineInfo?.source == 'dev_source';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isHotPatch
              ? c.primary.withOpacity(0.6)
              : (isDevSource ? Colors.purple.withOpacity(0.5) : c.border),
          width: 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isHotPatch ? Icons.local_fire_department : (isDevSource ? Icons.developer_mode : Icons.verified),
                color: isHotPatch ? c.primary : (isDevSource ? Colors.purpleAccent : c.primary),
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                'Lõi Xử Lý & Vá Lỗi Nhanh (Hot-Patch Engine)',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: c.textPrimary),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isHotPatch
                      ? Colors.amber.withOpacity(0.15)
                      : (isDevSource ? Colors.purple.withOpacity(0.15) : Colors.blue.withOpacity(0.15)),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _engineInfo?.version ?? 'Đang tải...',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: isHotPatch ? Colors.amber : (isDevSource ? Colors.purpleAccent : Colors.blueAccent),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            isHotPatch
                ? '🔥 Đang chạy Bản Vá Tự Động (Hot-Patch) ngoài thư mục App.'
                : (isDevSource
                    ? '⚡ Đang chạy Chế độ Phát triển (Dev Mode: đọc trực tiếp mã nguồn trên ổ cứng).'
                    : '📦 Đang chạy Lõi Gốc mặc định đi kèm trong bộ cài App.'),
            style: TextStyle(fontSize: 12, color: c.textSecondary),
          ),
          if (_engineInfo != null) ...[
            const SizedBox(height: 6),
            Text(
              'Đường dẫn thực thi: ${_engineInfo!.executablePath}',
              style: TextStyle(fontSize: 11, color: c.textMuted, fontFamily: 'monospace'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],

          // ── SOURCE CONFIG COLLAPSIBLE SECTION ─────────────────────────────
          const SizedBox(height: 10),
          InkWell(
            onTap: () => setState(() => _showSourceConfig = !_showSourceConfig),
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(
                    _showSourceConfig ? Icons.arrow_drop_down : Icons.arrow_right,
                    color: c.primary,
                    size: 18,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Cấu hình Nguồn Tải Bản Vá (Local Folder / Cloud URL)',
                    style: TextStyle(fontSize: 11, color: c.primary, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
          if (_showSourceConfig) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: c.surfaceDark,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: c.border, width: 0.8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Nguồn cập nhật bản vá (Đường dẫn folder cục bộ hoặc URL Cloud):',
                    style: TextStyle(fontSize: 10.5, color: c.textMuted),
                  ),
                  const SizedBox(height: 6),
                  AppInputGroup(
                    field: AppTextField(
                      controller: _sourceController,
                      height: 28,
                      isMonospace: true,
                      hint: 'https://.../engine_manifest.json hoặc /path/to/dist/engine_patch',
                      onSubmitted: (_) => _saveSource(),
                    ),
                    button: AppButton.outlined(
                      label: 'Chọn Folder',
                      icon: Icons.folder_open,
                      height: 28,
                      fontSize: 10.5,
                      onPressed: _pickLocalSource,
                    ),
                  ),
                ],
              ),
            ),
          ],

          if (_statusMessage.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.surfaceDark,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: AppColors.border, width: 0.8),
              ),
              child: Text(
                _statusMessage,
                style: const TextStyle(fontSize: 11, color: Colors.white),
              ),
            ),
          ],
          if (_isApplying) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: _applyProgress,
                backgroundColor: AppColors.surfaceLight,
                valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
                minHeight: 4,
              ),
            ),
          ],
          if (_availableUpdate != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.surfaceDark,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.primary.withOpacity(0.5), width: 0.8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.new_releases,
                        color: AppColors.primary,
                        size: 15,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _availableUpdate!.isLocalSource
                            ? 'Bản Vá Cục Bộ: ${_availableUpdate!.version}'
                            : 'Bản Vá Cloud Mới: ${_availableUpdate!.version}',
                        style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: AppColors.primary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    _availableUpdate!.releaseNotes,
                    style: const TextStyle(fontSize: 11, color: AppColors.textLight),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 26,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: AppColors.primaryText,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                      ),
                      onPressed: _isApplying ? null : _applyUpdate,
                      icon: Icon(
                        _availableUpdate!.isLocalSource ? Icons.copy : Icons.download,
                        size: 12.5,
                        color: Colors.black,
                      ),
                      label: Text(
                        _availableUpdate!.isLocalSource ? '📥 Sao Chép & Áp Dụng Ngay' : '📥 Tải & Vá Lỗi Ngay',
                        style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Colors.black),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              SizedBox(
                height: 26,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                    side: const BorderSide(color: AppColors.primary, width: 0.8),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  onPressed: _isChecking || _isApplying ? null : _checkUpdate,
                  icon: _isChecking
                      ? const SizedBox(
                          width: 10,
                          height: 10,
                          child: CircularProgressIndicator(strokeWidth: 1.5, color: AppColors.primary),
                        )
                      : const Icon(Icons.cloud_sync, size: 12.5, color: AppColors.primary),
                  label: const Text(
                    '🔍 Kiểm Tra Cập Nhật',
                    style: TextStyle(fontSize: 10.5, color: AppColors.primary, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              SizedBox(
                height: 26,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                    side: const BorderSide(color: AppColors.border, width: 0.8),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  onPressed: _isLoading || _isApplying ? null : _applyLocalZip,
                  icon: const Icon(Icons.folder_zip, size: 12.5, color: AppColors.textSecondary),
                  label: const Text(
                    '📂 Nạp File Zip (.zip)',
                    style: TextStyle(fontSize: 10.5, color: AppColors.textLight, fontWeight: FontWeight.w500),
                  ),
                ),
              ),
              if (isHotPatch)
                SizedBox(
                  height: 26,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                      side: const BorderSide(color: AppColors.statusFailed, width: 0.8),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    onPressed: _rollbackToBundled,
                    icon: const Icon(Icons.restore, size: 12.5, color: AppColors.statusFailed),
                    label: const Text(
                      '↩️ Khôi Phục Lõi Gốc',
                      style: TextStyle(fontSize: 10.5, color: AppColors.statusFailed, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
