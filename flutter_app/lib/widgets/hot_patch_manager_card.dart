import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../core/engine_update_service.dart';

class HotPatchManagerCard extends StatefulWidget {
  const HotPatchManagerCard({super.key});

  @override
  State<HotPatchManagerCard> createState() => _HotPatchManagerCardState();
}

class _HotPatchManagerCardState extends State<HotPatchManagerCard> {
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
          if (update != null) {
            _statusMessage = update.isLocalSource
                ? '✨ Đã phát hiện bản vá cục bộ hợp lệ: ${update.version}'
                : '✨ Đã tìm thấy bản vá Cloud mới: ${update.version}!';
          } else {
            _statusMessage = '✅ Bạn đang sử dụng bản vá mới nhất!';
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isChecking = false;
          _statusMessage = '⚠️ Kiểm tra thất bại: $e';
        });
      }
    }
  }

  Future<void> _applyUpdate() async {
    if (_availableUpdate == null) return;
    setState(() {
      _isApplying = true;
      _applyProgress = 0.0;
      _statusMessage = _availableUpdate!.isLocalSource
          ? 'Đang sao chép bản vá cục bộ...'
          : 'Bắt đầu tải bản vá từ Cloud...';
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
          _statusMessage = '🎉 Đã nạp bản vá thành công! Tất cả tác vụ tiếp theo sẽ chạy thuật toán mới.';
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
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Khôi Phục Lõi Mặc Định?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Thao tác này sẽ xoá bản vá hiện tại và quay về sử dụng lõi gốc đi kèm theo App.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Huỷ', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade800),
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
    final isHotPatch = _engineInfo?.source == 'hot_patch';
    final isDevSource = _engineInfo?.source == 'dev_source';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isHotPatch
              ? Colors.amber.withOpacity(0.5)
              : (isDevSource ? Colors.purple.withOpacity(0.5) : Colors.blue.withOpacity(0.3)),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isHotPatch ? Icons.local_fire_department : (isDevSource ? Icons.developer_mode : Icons.verified),
                color: isHotPatch ? Colors.amber : (isDevSource ? Colors.purpleAccent : Colors.blueAccent),
                size: 20,
              ),
              const SizedBox(width: 8),
              const Text(
                'Lõi Xử Lý & Vá Lỗi Nhanh (Hot-Patch Engine)',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
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
            style: const TextStyle(fontSize: 12, color: Colors.white70),
          ),
          if (_engineInfo != null) ...[
            const SizedBox(height: 6),
            Text(
              'Đường dẫn thực thi: ${_engineInfo!.executablePath}',
              style: const TextStyle(fontSize: 11, color: Colors.white38, fontFamily: 'monospace'),
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
                    color: Colors.cyanAccent,
                    size: 18,
                  ),
                  const SizedBox(width: 4),
                  const Text(
                    'Cấu hình Nguồn Tải Bản Vá (Local Folder / Cloud URL)',
                    style: TextStyle(fontSize: 11.5, color: Colors.cyanAccent, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
          if (_showSourceConfig) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Nguồn cập nhật bản vá (Đường dẫn folder cục bộ hoặc URL Cloud):',
                    style: TextStyle(fontSize: 11, color: Colors.white70),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _sourceController,
                          style: const TextStyle(fontSize: 11.5, fontFamily: 'monospace', color: Colors.white),
                          decoration: InputDecoration(
                            hintText: 'https://.../engine_manifest.json hoặc /path/to/dist/engine_patch',
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            isDense: true,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                          ),
                          onSubmitted: (_) => _saveSource(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        height: 32,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                          onPressed: _pickLocalSource,
                          icon: const Icon(Icons.folder_open, size: 14, color: Colors.cyanAccent),
                          label: const Text('Chọn Folder', style: TextStyle(fontSize: 11, color: Colors.cyanAccent)),
                        ),
                      ),
                    ],
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
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                _statusMessage,
                style: const TextStyle(fontSize: 11.5, color: Colors.white),
              ),
            ),
          ],
          if (_isApplying) ...[
            const SizedBox(height: 10),
            LinearProgressIndicator(
              value: _applyProgress,
              backgroundColor: const Color(0xFF0F172A),
              color: Colors.amber,
              minHeight: 6,
            ),
          ],
          if (_availableUpdate != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.withOpacity(0.4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        _availableUpdate!.isLocalSource ? Icons.folder : Icons.new_releases,
                        color: Colors.amber,
                        size: 16,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _availableUpdate!.isLocalSource
                            ? 'Bản Vá Cục Bộ: ${_availableUpdate!.version}'
                            : 'Bản Vá Cloud Mới: ${_availableUpdate!.version}',
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Colors.amber),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _availableUpdate!.releaseNotes,
                    style: const TextStyle(fontSize: 11.5, color: Colors.white70),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 28,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.amber.shade700,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                      ),
                      onPressed: _isApplying ? null : _applyUpdate,
                      icon: Icon(
                        _availableUpdate!.isLocalSource ? Icons.copy : Icons.download,
                        size: 13,
                        color: Colors.white,
                      ),
                      label: Text(
                        _availableUpdate!.isLocalSource ? '📥 Sao Chép & Áp Dụng Ngay' : '📥 Tải & Vá Lỗi Ngay',
                        style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              SizedBox(
                height: 28,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    side: BorderSide(color: Colors.blueAccent.withOpacity(0.5)),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                  onPressed: _isChecking || _isApplying ? null : _checkUpdate,
                  icon: _isChecking
                      ? const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.blueAccent),
                        )
                      : const Icon(Icons.cloud_sync, size: 13, color: Colors.blueAccent),
                  label: const Text(
                    '🔍 Kiểm Tra Cập Nhật',
                    style: TextStyle(fontSize: 11.5, color: Colors.blueAccent, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              SizedBox(
                height: 28,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    side: const BorderSide(color: Colors.white24),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                  onPressed: _isLoading || _isApplying ? null : _applyLocalZip,
                  icon: const Icon(Icons.folder_zip, size: 13, color: Colors.white70),
                  label: const Text(
                    '📂 Nạp File Zip (.zip)',
                    style: TextStyle(fontSize: 11.5, color: Colors.white70, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              if (isHotPatch)
                SizedBox(
                  height: 28,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      side: BorderSide(color: Colors.red.withOpacity(0.4)),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                    ),
                    onPressed: _rollbackToBundled,
                    icon: const Icon(Icons.restore, size: 13, color: Colors.redAccent),
                    label: const Text(
                      '↩️ Khôi Phục Lõi Gốc',
                      style: TextStyle(fontSize: 11.5, color: Colors.redAccent, fontWeight: FontWeight.w600),
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
