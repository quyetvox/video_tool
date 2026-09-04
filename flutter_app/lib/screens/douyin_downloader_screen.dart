import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:intl/intl.dart';
import '../core/app_colors.dart';
import '../core/providers.dart';
import '../core/python_bridge.dart';
import '../models/douyin_video_item.dart';
import '../widgets/app_kit.dart';
import '../widgets/douyin_raw_modal.dart';
import '../widgets/video_player_widget.dart';

class DouyinDownloaderScreen extends ConsumerStatefulWidget {
  const DouyinDownloaderScreen({super.key});

  @override
  ConsumerState<DouyinDownloaderScreen> createState() => _DouyinDownloaderScreenState();
}

class _DouyinDownloaderScreenState extends ConsumerState<DouyinDownloaderScreen> {
  String? _selectedTxtFile;
  List<String> _availableTxtFiles = [];
  List<DouyinVideoItem> _items = [];
  DouyinVideoItem? _selectedItem;
  String _searchQuery = '';
  bool _isDownloadingAll = false;
  int _downloadingIndex = -1;

  // ── Multi-selection & Sequential Download State ──────────────
  final Set<int> _selectedIndexes = {};
  bool _isDownloadingSequential = false;
  int _sequentialCurrent = 0;
  int _sequentialTotal = 0;
  String _sequentialStatus = '';
  bool _isCancelRequested = false;
  final TextEditingController _urlInputController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scanTxtFiles());
  }

  @override
  void dispose() {
    _urlInputController.dispose();
    super.dispose();
  }

  void _scanTxtFiles() {
    final activeProject = ref.read(activeProjectProvider);
    final projectsDir = ref.read(projectsDirProvider);
    if (activeProject == null) return;

    final projDir = Directory(p.join(projectsDir, activeProject));
    if (!projDir.existsSync()) return;

    final txts = <String>[];
    try {
      final list = projDir.listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.txt')).toList();
      for (final f in list) {
        final rel = p.relative(f.path, from: projDir.path);
        // Ignore files inside workspace/ or hidden directories
        if (rel.startsWith('workspace') || rel.startsWith('workspace/') || rel.startsWith('workspace\\') || rel.startsWith('.')) {
          continue;
        }
        txts.add(rel);
      }
    } catch (_) {}

    setState(() {
      _availableTxtFiles = txts;
      if (txts.isNotEmpty) {
        _selectedTxtFile = txts.contains('douyin-maudau.txt')
            ? 'douyin-maudau.txt'
            : (txts.contains('src/douyin-video-links.txt') ? 'src/douyin-video-links.txt' : txts.first);
      } else {
        _selectedTxtFile = null;
      }
    });

    if (_selectedTxtFile != null) {
      _loadLinks();
    }
  }

  void _previewPastedUrl() {
    final raw = _urlInputController.text.trim();
    if (raw.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ Vui lòng dán link video hoặc URL hợp lệ!')),
      );
      return;
    }

    final urlRegex = RegExp(r'https?://[^\s]+');
    final match = urlRegex.firstMatch(raw);
    if (match == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ Link không hợp lệ (cần bắt đầu bằng http:// hoặc https://)!')),
      );
      return;
    }

    final cleanUrl = match.group(0)!;
    final activeProject = ref.read(activeProjectProvider);
    final projectsDir = ref.read(projectsDirProvider);
    final srcFiles = <String>[];
    if (activeProject != null) {
      final srcDir = Directory(p.join(projectsDir, activeProject, 'src'));
      if (srcDir.existsSync()) {
        srcFiles.addAll(srcDir.listSync().whereType<File>().map((f) => f.absolute.path));
      }
    }

    var item = DouyinVideoItem.parse(cleanUrl, _items.length, existingSrcFiles: srcFiles);
    if (item == null) {
      final uri = Uri.tryParse(cleanUrl);
      final lastSeg = uri?.pathSegments.where((s) => s.isNotEmpty).lastOrNull ?? 'video';
      final shortHash = lastSeg.length >= 8 ? lastSeg.substring(0, 8) : lastSeg;
      final nowStr = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final filename = '${nowStr}_$shortHash.mp4';

      bool isDownloaded = false;
      String? localPath;
      for (final s in srcFiles) {
        if (s.contains(shortHash) || s.contains(nowStr)) {
          isDownloaded = true;
          localPath = s;
          break;
        }
      }

      item = DouyinVideoItem(
        index: _items.length + 1,
        rawUrl: cleanUrl,
        directUrl: cleanUrl,
        filename: filename,
        shortHash: shortHash,
        timestampStr: nowStr,
        resolution: '1080p HD',
        bitrateStr: 'Auto Stream',
        isDownloaded: isDownloaded,
        localFilePath: localPath,
      );
    }

    setState(() {
      _selectedItem = item;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('⚡ Đang phát xem trước trực tuyến: ${item.filename}'),
        backgroundColor: const Color(0xFF2563EB),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data != null && data.text != null && data.text!.trim().isNotEmpty) {
      setState(() {
        _urlInputController.text = data.text!.trim();
      });
      _previewPastedUrl();
    }
  }

  void _loadLinks() {
    final activeProject = ref.read(activeProjectProvider);
    final projectsDir = ref.read(projectsDirProvider);
    if (activeProject == null || _selectedTxtFile == null) return;

    final filePath = p.join(projectsDir, activeProject, _selectedTxtFile!);
    final file = File(filePath);
    if (!file.existsSync()) {
      setState(() {
        _items = [];
        _selectedIndexes.clear();
      });
      return;
    }

    // Get existing files in src/ with absolute paths
    final srcDir = Directory(p.join(projectsDir, activeProject, 'src'));
    final srcFiles = srcDir.existsSync()
        ? srcDir.listSync().whereType<File>().map((f) => f.absolute.path).toList()
        : <String>[];

    try {
      final lines = file.readAsLinesSync();
      final parsed = <DouyinVideoItem>[];
      int idx = 0;
      for (final line in lines) {
        final item = DouyinVideoItem.parse(line, idx, existingSrcFiles: srcFiles);
        if (item != null) {
          parsed.add(item);
          idx++;
        }
      }
      setState(() {
        _items = parsed;
        if (parsed.isNotEmpty) {
          _selectedItem = parsed.firstWhere(
            (it) => it.index == _selectedItem?.index,
            orElse: () => parsed.first,
          );
        }
        _selectedIndexes.removeWhere((i) => i >= parsed.length);
      });
    } catch (_) {}
  }

  void _toggleSelect(int index) {
    setState(() {
      if (_selectedIndexes.contains(index)) {
        _selectedIndexes.remove(index);
      } else {
        _selectedIndexes.add(index);
      }
    });
  }

  void _toggleSelectAll(List<DouyinVideoItem> displayItems) {
    setState(() {
      final allDisplayIndexes = displayItems.map((e) => e.index).toSet();
      if (_selectedIndexes.containsAll(allDisplayIndexes) && allDisplayIndexes.isNotEmpty) {
        _selectedIndexes.removeAll(allDisplayIndexes);
      } else {
        _selectedIndexes.addAll(allDisplayIndexes);
      }
    });
  }

  void _downloadSingle(DouyinVideoItem item) async {
    final activeProject = ref.read(activeProjectProvider);
    final projectsDir = ref.read(projectsDirProvider);
    if (activeProject == null) return;

    setState(() => _downloadingIndex = item.index);
    final srcDir = Directory(p.join(projectsDir, activeProject, 'src'));
    if (!srcDir.existsSync()) srcDir.createSync(recursive: true);

    final outPath = p.join(srcDir.path, item.filename);

    final res = await PythonBridge.runScript(
      'download.py',
      [item.directUrl, '-o', outPath],
      jobId: 'dl_${item.shortHash}',
    );

    setState(() => _downloadingIndex = -1);

    if (res.success) {
      ref.invalidate(projectVideosProvider);
      _loadLinks();
      if (_selectedItem != null && _selectedItem!.directUrl == item.directUrl) {
        setState(() {
          _selectedItem = DouyinVideoItem(
            index: _selectedItem!.index,
            rawUrl: _selectedItem!.rawUrl,
            directUrl: _selectedItem!.directUrl,
            filename: _selectedItem!.filename,
            shortHash: _selectedItem!.shortHash,
            timestampStr: _selectedItem!.timestampStr,
            resolution: _selectedItem!.resolution,
            bitrateStr: _selectedItem!.bitrateStr,
            bitrate: _selectedItem!.bitrate,
            isDownloaded: true,
            localFilePath: outPath,
          );
        });
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('✅ Đã tải thành công ${item.filename} vào src/!'), backgroundColor: const Color(0xFF10B981)),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ Lỗi tải video: ${res.output}')));
      }
    }
  }

  void _downloadSequential() async {
    final activeProject = ref.read(activeProjectProvider);
    final projectsDir = ref.read(projectsDirProvider);
    if (activeProject == null) return;

    final selectedItems = _items.where((it) => _selectedIndexes.contains(it.index)).toList();
    if (selectedItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ Vui lòng tích chọn ít nhất 1 video để tải!')),
      );
      return;
    }

    // Smart Skip: Chỉ tải các video chưa có trong src/
    final itemsToDownload = selectedItems.where((it) => !it.isDownloaded).toList();
    if (itemsToDownload.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('ℹ️ Tất cả video đã chọn đều đã có sẵn trong thư mục src/!'),
          backgroundColor: Color(0xFF3B82F6),
        ),
      );
      return;
    }

    final srcDir = Directory(p.join(projectsDir, activeProject, 'src'));
    if (!srcDir.existsSync()) srcDir.createSync(recursive: true);

    setState(() {
      _isDownloadingSequential = true;
      _isCancelRequested = false;
      _sequentialTotal = itemsToDownload.length;
      _sequentialCurrent = 0;
      _sequentialStatus = 'Bắt đầu tải tuần tự ${itemsToDownload.length} video...';
    });

    int downloadedCount = 0;
    int failedCount = 0;

    for (int i = 0; i < itemsToDownload.length; i++) {
      if (_isCancelRequested) {
        break;
      }

      final item = itemsToDownload[i];
      setState(() {
        _downloadingIndex = item.index;
        _sequentialCurrent = i + 1;
        _sequentialStatus = 'Đang tải (${i + 1}/${itemsToDownload.length}): ${item.filename}';
      });

      final outPath = p.join(srcDir.path, item.filename);
      final res = await PythonBridge.runScript(
        'download.py',
        [item.directUrl, '-o', outPath],
        jobId: 'dl_seq_${item.shortHash}',
      );

      if (res.success) {
        downloadedCount++;
        _loadLinks();
        ref.invalidate(projectVideosProvider);
      } else {
        failedCount++;
      }
    }

    setState(() {
      _isDownloadingSequential = false;
      _downloadingIndex = -1;
      _sequentialStatus = '';
    });

    if (mounted) {
      if (_isCancelRequested) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('⏹ Đã dừng tải tuần tự (Đã tải $downloadedCount/${itemsToDownload.length} video)'),
            backgroundColor: const Color(0xFFF59E0B),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('🎉 Hoàn tất tải tuần tự: $downloadedCount thành công${failedCount > 0 ? ', $failedCount thất bại' : ''}'),
            backgroundColor: failedCount == 0 ? const Color(0xFF10B981) : const Color(0xFFEF4444),
          ),
        );
      }
    }
  }

  void _cancelSequential() {
    setState(() {
      _isCancelRequested = true;
      _sequentialStatus = 'Đang yêu cầu dừng tải...';
    });
  }

  void _downloadAll() async {
    final activeProject = ref.read(activeProjectProvider);
    final projectsDir = ref.read(projectsDirProvider);
    if (activeProject == null || _selectedTxtFile == null) return;

    final srcDir = Directory(p.join(projectsDir, activeProject, 'src'));
    if (!srcDir.existsSync()) srcDir.createSync(recursive: true);

    setState(() => _isDownloadingAll = true);
    final txtPath = p.join(projectsDir, activeProject, _selectedTxtFile!);

    final res = await PythonBridge.runScript(
      'download.py',
      [txtPath, '-o', srcDir.path],
      jobId: 'dl_batch_$activeProject',
    );

    setState(() => _isDownloadingAll = false);

    if (res.success) {
      ref.invalidate(projectVideosProvider);
      _loadLinks();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('🎉 Đã hoàn tất tải toàn bộ danh sách video vào src/!'), backgroundColor: Color(0xFF10B981)),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ Lỗi tải danh sách: ${res.output}')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeProject = ref.watch(activeProjectProvider);
    final projectsDir = ref.watch(projectsDirProvider);

    final displayItems = _items.where((it) {
      if (_searchQuery.isEmpty) return true;
      return it.rawUrl.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          it.filename.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          it.shortHash.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();

    final c = AppColors.of(context);

    return Scaffold(
      backgroundColor: c.background,
      body: Container(
        color: c.background,
        child: Column(
          children: [
            // 1. Top Downloader Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: c.surface,
                border: Border(bottom: BorderSide(color: c.border)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: c.primary.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Icon(Icons.cloud_download, color: c.primary, size: 16),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Tải Video Hàng Loạt',
                            style: TextStyle(color: c.textPrimary, fontSize: 12.5, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(color: AppColors.surfaceLight, borderRadius: BorderRadius.circular(4)),
                            child: Text('📁 assets/$activeProject/', style: const TextStyle(color: AppColors.primary, fontSize: 10.5)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Trích xuất, xem trước và tải video chất lượng cao từ danh sách URL Douyin vào thư mục src/',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 10.5),
                      ),
                    ],
                  ),
                  const Spacer(),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textSecondary,
                      side: const BorderSide(color: AppColors.border),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
                    ),
                    icon: const Icon(Icons.edit_note, size: 13),
                    label: const Text('Sửa File Raw', style: TextStyle(fontSize: 10.5)),
                    onPressed: () {
                      if (activeProject != null && _selectedTxtFile != null) {
                        final full = p.join(projectsDir, activeProject, _selectedTxtFile!);
                        showDialog(
                          context: context,
                          builder: (ctx) => DouyinRawModal(filePath: full, onSaved: _loadLinks),
                        );
                      }
                    },
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 15, color: AppColors.textSecondary),
                    tooltip: 'Tải lại',
                    onPressed: _scanTxtFiles,
                  ),
                ],
              ),
            ),

            // 2. Input Link File Selector Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: c.surfaceDark,
                border: Border(bottom: BorderSide(color: c.border)),
              ),
              child: Row(
                children: [
                  Text('Đường dẫn file link:', style: TextStyle(color: c.textSecondary, fontSize: 12)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Container(
                      height: 26,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        color: c.surface,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: c.border, width: 0.8),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedTxtFile,
                          isExpanded: true,
                          dropdownColor: c.surface,
                          style: TextStyle(color: c.textPrimary, fontSize: 10.5),
                          icon: Icon(Icons.arrow_drop_down, size: 14, color: c.textSecondary),
                          items: _availableTxtFiles.map((txt) {
                            return DropdownMenuItem(
                              value: txt,
                              child: Text('assets/$activeProject/$txt'),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setState(() => _selectedTxtFile = val);
                              _loadLinks();
                            }
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // 2b. Quick Direct Paste & Preview Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: c.surface,
                border: Border(bottom: BorderSide(color: c.border)),
              ),
              child: Row(
                children: [
                  Icon(Icons.link, size: 16, color: c.primary),
                  const SizedBox(width: 8),
                  Text('Dán link xem nhanh:', style: TextStyle(color: c.textSecondary, fontSize: 11.5, fontWeight: FontWeight.w500)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Container(
                      height: 28,
                      decoration: BoxDecoration(
                        color: c.surfaceDark,
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(color: c.border, width: 0.8),
                      ),
                      child: Row(
                        children: [
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _urlInputController,
                              style: TextStyle(fontSize: 11, color: c.textPrimary),
                              decoration: InputDecoration(
                                hintText: 'Dán URL Douyin hoặc Direct CDN link (.mp4) để xem trực tuyến...',
                                hintStyle: TextStyle(fontSize: 11, color: c.textMuted),
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(vertical: 6),
                              ),
                              onSubmitted: (_) => _previewPastedUrl(),
                            ),
                          ),
                          if (_urlInputController.text.isNotEmpty)
                            IconButton(
                              icon: Icon(Icons.clear, size: 13, color: c.textMuted),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: () {
                                setState(() {
                                  _urlInputController.clear();
                                });
                              },
                            ),
                          const SizedBox(width: 4),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: c.textPrimary,
                      side: BorderSide(color: c.border),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      minimumSize: const Size(0, 28),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
                    ),
                    icon: const Icon(Icons.content_paste, size: 13),
                    label: const Text('Dán Clipboard', style: TextStyle(fontSize: 10.5)),
                    onPressed: _pasteFromClipboard,
                  ),
                  const SizedBox(width: 6),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: c.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      minimumSize: const Size(0, 28),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
                    ),
                    icon: const Icon(Icons.play_circle_fill, size: 14),
                    label: const Text('⚡ Xem Thử', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    onPressed: _previewPastedUrl,
                  ),
                ],
              ),
            ),

            // 3. Main Split View (Left Links List & Right Live Preview)
            Expanded(
              child: Row(
                children: [
                  // Left: Extracted URLs List (55%)
                  Expanded(
                    flex: 55,
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border(right: BorderSide(color: c.border)),
                      ),
                      child: Column(
                        children: [
                          // Search & Batch Download Bar
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            child: Row(
                              children: [
                                // Checkbox Chọn Tất Cả
                                InkWell(
                                  onTap: () => _toggleSelectAll(displayItems),
                                  borderRadius: BorderRadius.circular(4),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        AppCheckbox(
                                          value: displayItems.isNotEmpty && displayItems.every((e) => _selectedIndexes.contains(e.index)),
                                          onChanged: (_) => _toggleSelectAll(displayItems),
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          'Tất cả (${displayItems.length})',
                                          style: TextStyle(color: c.textPrimary, fontSize: 11, fontWeight: FontWeight.w600),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                if (_selectedIndexes.isNotEmpty) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: AppColors.primary.withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: AppColors.primary.withOpacity(0.4), width: 0.8),
                                    ),
                                    child: Text(
                                      'Đã chọn: ${_selectedIndexes.length}',
                                      style: const TextStyle(color: AppColors.primary, fontSize: 10, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ],
                                const Spacer(),
                                if (_isDownloadingSequential) ...[
                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFFEF4444),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      minimumSize: const Size(0, 28),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
                                    ),
                                    icon: const Icon(Icons.stop_circle_outlined, size: 14),
                                    label: const Text('Dừng Tải', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                    onPressed: _cancelSequential,
                                  ),
                                ] else ...[
                                  // Nút Tải Tuần Tự các mục đã chọn
                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: _selectedIndexes.isNotEmpty ? const Color(0xFF10B981) : c.surfaceLight,
                                      foregroundColor: _selectedIndexes.isNotEmpty ? Colors.white : c.textMuted,
                                      elevation: 0,
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      minimumSize: const Size(0, 28),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
                                    ),
                                    icon: const Icon(Icons.playlist_play, size: 15),
                                    label: Text(
                                      _selectedIndexes.isEmpty
                                          ? 'Tải Đã Chọn'
                                          : 'Tải Tuần Tự (${_selectedIndexes.length})',
                                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                                    ),
                                    onPressed: _selectedIndexes.isEmpty || _isDownloadingAll ? null : _downloadSequential,
                                  ),
                                  const SizedBox(width: 6),
                                  // Nút Tải Toàn Bộ
                                  AppButton.primary(
                                    label: 'Tải Hết (${displayItems.length})',
                                    icon: Icons.download,
                                    height: 28,
                                    fontSize: 11,
                                    isLoading: _isDownloadingAll,
                                    onPressed: _isDownloadingAll || _isDownloadingSequential ? null : _downloadAll,
                                  ),
                                ],
                              ],
                            ),
                          ),

                          // Sequential Download Progress Banner
                          if (_isDownloadingSequential)
                            Container(
                              margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: const Color(0xFF10B981).withOpacity(0.12),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: const Color(0xFF10B981).withOpacity(0.35)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const SizedBox(
                                        width: 11,
                                        height: 11,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF10B981)),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          _sequentialStatus,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(color: Color(0xFF34D399), fontSize: 11, fontWeight: FontWeight.w600),
                                        ),
                                      ),
                                      Text(
                                        '$_sequentialCurrent/$_sequentialTotal',
                                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(2),
                                    child: LinearProgressIndicator(
                                      value: _sequentialTotal > 0 ? (_sequentialCurrent / _sequentialTotal) : 0,
                                      minHeight: 3,
                                      backgroundColor: Colors.black26,
                                      valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF10B981)),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                          // Search Input
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            child: AppSearchField(
                              hint: 'Lọc link theo ID, bitrate hoặc URL...',
                              onChanged: (val) => setState(() => _searchQuery = val),
                            ),
                          ),

                          const SizedBox(height: 8),

                          // Items List
                          Expanded(
                            child: ListView.builder(
                              itemCount: displayItems.length,
                              itemBuilder: (ctx, idx) {
                                final it = displayItems[idx];
                                final isSelected = _selectedItem?.index == it.index;
                                final isChecked = _selectedIndexes.contains(it.index);

                                return Container(
                                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: isSelected ? AppColors.surfaceLight : AppColors.surfaceDark,
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: isSelected
                                          ? AppColors.primary
                                          : (isChecked ? AppColors.primary.withOpacity(0.5) : AppColors.border),
                                      width: 0.8,
                                    ),
                                  ),
                                  child: ListTile(
                                    dense: true,
                                    leading: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        AppCheckbox(
                                          value: isChecked,
                                          onChanged: (_) => _toggleSelect(it.index),
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          '#${it.index.toString().padLeft(2, '0')}',
                                          style: const TextStyle(color: AppColors.textMuted, fontSize: 11, fontWeight: FontWeight.bold),
                                        ),
                                      ],
                                    ),
                                  title: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                        decoration: BoxDecoration(
                                          color: AppColors.primary.withOpacity(0.15),
                                          borderRadius: BorderRadius.circular(3),
                                        ),
                                        child: Text(it.resolution, style: const TextStyle(color: AppColors.primary, fontSize: 9.5, fontWeight: FontWeight.bold)),
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          it.filename,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w600),
                                        ),
                                      ),
                                    ],
                                  ),
                                  subtitle: Row(
                                    children: [
                                      if (it.isDownloaded)
                                        Container(
                                          margin: const EdgeInsets.only(top: 4, right: 6),
                                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                          decoration: BoxDecoration(
                                            color: AppColors.statusCompleted.withOpacity(0.2),
                                            borderRadius: BorderRadius.circular(3),
                                          ),
                                          child: const Text('✓ Đã có trong src/', style: TextStyle(color: AppColors.statusCompleted, fontSize: 9)),
                                        ),
                                      Expanded(
                                        child: Text(
                                          it.directUrl,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(color: AppColors.textMuted, fontSize: 10),
                                        ),
                                      ),
                                    ],
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.copy, size: 14, color: AppColors.textSecondary),
                                        onPressed: () {
                                          Clipboard.setData(ClipboardData(text: it.directUrl));
                                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã copy link!')));
                                        },
                                      ),
                                      IconButton(
                                        icon: _downloadingIndex == it.index
                                            ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))
                                            : const Icon(Icons.download, size: 16, color: AppColors.statusCompleted),
                                        onPressed: () => _downloadSingle(it),
                                      ),
                                    ],
                                  ),
                                  onTap: () => setState(() => _selectedItem = it),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Right: Live Video Preview (45%)
                Expanded(
                  flex: 45,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    child: _selectedItem == null
                        ? const Center(child: Text('Chọn video để xem trước', style: TextStyle(color: AppColors.textMuted)))
                        : Builder(
                            builder: (context) {
                              final isLocal = _selectedItem!.isDownloaded &&
                                  _selectedItem!.localFilePath != null &&
                                  File(_selectedItem!.localFilePath!).existsSync();
                              final targetPlayPath = isLocal ? _selectedItem!.localFilePath! : _selectedItem!.directUrl;

                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(Icons.ondemand_video, size: 16, color: AppColors.primary),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'Xem Trước Video — #${_selectedItem!.index}',
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(color: c.textPrimary, fontSize: 13, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: isLocal
                                              ? const Color(0xFF059669).withOpacity(0.2)
                                              : const Color(0xFFD97706).withOpacity(0.2),
                                          borderRadius: BorderRadius.circular(4),
                                          border: Border.all(
                                            color: isLocal ? const Color(0xFF059669) : const Color(0xFFD97706),
                                            width: 0.8,
                                          ),
                                        ),
                                        child: Text(
                                          isLocal ? '✓ File Local (src/)' : '⚡ Live Stream CDN',
                                          style: TextStyle(
                                            color: isLocal ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),

                                  // Preview Player (Local File OR Live CDN Stream)
                                  Expanded(
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: Colors.black,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: c.border),
                                      ),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: VideoPlayerWidget(
                                          key: ValueKey(targetPlayPath),
                                          videoPath: targetPlayPath,
                                          autoPlay: false,
                                        ),
                                      ),
                                    ),
                                  ),

                                  const SizedBox(height: 12),

                                  // Specs Table
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(color: c.surfaceDark, borderRadius: BorderRadius.circular(6)),
                                    child: Column(
                                      children: [
                                        _buildSpecRow('Tên file tải về:', _selectedItem!.filename),
                                        _buildSpecRow('Ngày đăng (Timestamp):', _selectedItem!.timestampStr ?? 'N/A'),
                                        _buildSpecRow('Video ID / Hash:', _selectedItem!.shortHash),
                                        _buildSpecRow('Chất lượng / Bitrate:', _selectedItem!.bitrateStr),
                                        _buildSpecRow('Lưu về thư mục:', 'resources/$activeProject/src/'),
                                      ],
                                    ),
                                  ),

                                  const SizedBox(height: 12),

                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: isLocal ? const Color(0xFF059669) : const Color(0xFF2563EB),
                                      foregroundColor: Colors.white,
                                      minimumSize: const Size(double.infinity, 38),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                    ),
                                    icon: Icon(isLocal ? Icons.check_circle : Icons.download, size: 16),
                                    label: Text(
                                      isLocal
                                          ? '✓ Đã Có Trong src/ (Tải Lại Đè Video #${_selectedItem!.index})'
                                          : '📥 Tải Ngay Video #${_selectedItem!.index} Về src/',
                                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                                    ),
                                    onPressed: () => _downloadSingle(_selectedItem!),
                                  ),
                                ],
                              );
                            },
                          ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

  Widget _buildSpecRow(String label, String val) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
          Expanded(
            child: Text(
              val,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontFamily: 'monospace', color: Colors.white, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}
