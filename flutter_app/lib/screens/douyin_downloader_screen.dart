import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import '../core/app_colors.dart';
import '../core/license_service.dart';
import '../core/providers.dart';
import '../core/python_bridge.dart';
import '../models/douyin_video_item.dart';
import '../widgets/paywall_dialog.dart';
import '../widgets/resizable_collapsible_panel.dart';
import 'douyin_downloader/components/douyin_header_bar.dart';
import 'douyin_downloader/components/douyin_preview_panel.dart';
import 'douyin_downloader/components/douyin_url_input_bar.dart';
import 'douyin_downloader/components/douyin_video_table.dart';

class DouyinDownloaderScreen extends ConsumerStatefulWidget {
  const DouyinDownloaderScreen({super.key});

  @override
  ConsumerState<DouyinDownloaderScreen> createState() => _DouyinDownloaderScreenState();
}

class _DouyinDownloaderScreenState extends ConsumerState<DouyinDownloaderScreen> {
  static const String _prefLastLinkFilePath = 'douyin_last_link_file_path';
  final TextEditingController _filePathController = TextEditingController();
  String? _currentFilePath;
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
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadInitialPath());
  }

  @override
  void dispose() {
    _filePathController.dispose();
    _urlInputController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialPath() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefLastLinkFilePath);
    if (saved != null && saved.trim().isNotEmpty && File(saved.trim()).existsSync()) {
      _filePathController.text = saved.trim();
      _loadLinksFromPath(saved.trim(), isInitial: true);
      return;
    }

    final activeProject = ref.read(activeProjectProvider);
    final projectsDir = ref.read(projectsDirProvider);
    if (activeProject != null) {
      final p1 = p.join(projectsDir, activeProject, 'douyin-maudau.txt');
      final p2 = p.join(projectsDir, activeProject, 'src', 'douyin-video-links.txt');
      if (File(p1).existsSync()) {
        _filePathController.text = p1;
        _loadLinksFromPath(p1, isInitial: true);
        return;
      } else if (File(p2).existsSync()) {
        _filePathController.text = p2;
        _loadLinksFromPath(p2, isInitial: true);
        return;
      }
    }
  }

  Future<void> _loadLinksFromPath(String raw, {bool isInitial = false}) async {
    String cleanPath = raw.trim();
    cleanPath = cleanPath.replaceAll(RegExp(r'^["\x27]|["\x27]$'), '').trim();

    if (cleanPath.isEmpty) {
      if (!isInitial && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('⚠️ Vui lòng nhập hoặc dán đường dẫn file .txt!')),
        );
      }
      return;
    }

    final normalized = p.normalize(cleanPath);
    final file = File(normalized);
    if (!file.existsSync()) {
      if (!isInitial && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('⚠️ Không tìm thấy file tại đường dẫn:\n$normalized'),
            backgroundColor: const Color(0xFFEF4444),
            duration: const Duration(seconds: 4),
          ),
        );
      }
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefLastLinkFilePath, normalized);

    final activeProject = ref.read(activeProjectProvider);
    final projectsDir = ref.read(projectsDirProvider);
    final srcFiles = <String>[];
    if (activeProject != null) {
      final srcDir = Directory(p.join(projectsDir, activeProject, 'src'));
      if (srcDir.existsSync()) {
        srcFiles.addAll(srcDir.listSync().whereType<File>().map((f) => f.absolute.path));
      }
    }

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
        _currentFilePath = normalized;
        _filePathController.text = normalized;
        _items = parsed;
        if (parsed.isNotEmpty) {
          _selectedItem = parsed.firstWhere(
            (it) => it.index == _selectedItem?.index,
            orElse: () => parsed.first,
          );
        }
        _selectedIndexes.removeWhere((i) => i >= parsed.length);
      });

      if (!isInitial && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Đã nạp thành công ${parsed.length} liên kết từ file: ${p.basename(normalized)}'),
            backgroundColor: const Color(0xFF10B981),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (!isInitial && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Lỗi khi đọc file: $e'),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
      }
    }
  }

  Future<void> _pickLinkFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['txt'],
        dialogTitle: 'Chọn file danh sách link Douyin (.txt)',
      );
      if (result != null && result.files.isNotEmpty && result.files.single.path != null) {
        final selectedPath = result.files.single.path!;
        _filePathController.text = selectedPath;
        await _loadLinksFromPath(selectedPath);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Lỗi khi chọn file: $e'),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
      }
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
    if (_currentFilePath != null) {
      _loadLinksFromPath(_currentFilePath!, isInitial: true);
    } else if (_filePathController.text.trim().isNotEmpty) {
      _loadLinksFromPath(_filePathController.text.trim(), isInitial: true);
    }
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

    final license = ref.read(licenseInfoProvider);
    if (!license.canUseSequentialBatch) {
      PaywallDialog.show(
        context,
        featureName: 'Tải Tuần Tự Theo Hàng Đợi',
        featureDescription: 'Tự động tải và phân giải liên tục danh sách video đã chọn',
      );
      return;
    }

    final selectedItems = _items.where((it) => _selectedIndexes.contains(it.index)).toList();
    if (selectedItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ Vui lòng tích chọn ít nhất 1 video để tải!')),
      );
      return;
    }

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
    if (activeProject == null || _currentFilePath == null) return;

    final license = ref.read(licenseInfoProvider);
    if (!license.canUseSequentialBatch) {
      PaywallDialog.show(
        context,
        featureName: 'Tải Hàng Loạt Toàn Bộ Danh Sách',
        featureDescription: 'Tự động tải và phân giải toàn bộ liên kết từ file',
      );
      return;
    }

    final srcDir = Directory(p.join(projectsDir, activeProject, 'src'));
    if (!srcDir.existsSync()) srcDir.createSync(recursive: true);

    setState(() => _isDownloadingAll = true);
    final txtPath = _currentFilePath!;

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
            DouyinHeaderBar(
              activeProject: activeProject,
              currentFilePath: _currentFilePath,
              onReload: _loadLinks,
            ),

            // 2. Input Link File Selector Bar & Quick Paste Bar
            DouyinUrlInputBar(
              filePathController: _filePathController,
              urlInputController: _urlInputController,
              onFilePathSubmitted: (val) => _loadLinksFromPath(val),
              onPickLinkFile: _pickLinkFile,
              onPasteFromClipboard: _pasteFromClipboard,
              onPreviewPastedUrl: _previewPastedUrl,
            ),

            // 3. Main Split View with ResizableCollapsiblePanel
            Expanded(
              child: ResizableCollapsiblePanel(
                side: PanelSide.right,
                initialWidth: 440,
                minWidth: 320,
                maxWidth: 700,
                collapseTooltip: 'Thu gọn xem trước video',
                expandTooltip: 'Mở xem trước video',
                panel: DouyinPreviewPanel(
                  selectedItem: _selectedItem,
                  activeProject: activeProject ?? 'default',
                  onDownloadSingle: _downloadSingle,
                ),
                child: DouyinVideoTable(
                  displayItems: displayItems,
                  selectedItem: _selectedItem,
                  selectedIndexes: _selectedIndexes,
                  searchQuery: _searchQuery,
                  onSearchChanged: (val) => setState(() => _searchQuery = val),
                  onToggleSelectAll: () => _toggleSelectAll(displayItems),
                  onToggleSelect: _toggleSelect,
                  onItemSelected: (it) => setState(() => _selectedItem = it),
                  onDownloadSingle: _downloadSingle,
                  downloadingIndex: _downloadingIndex,
                  isDownloadingAll: _isDownloadingAll,
                  onDownloadAll: _downloadAll,
                  isDownloadingSequential: _isDownloadingSequential,
                  sequentialCurrent: _sequentialCurrent,
                  sequentialTotal: _sequentialTotal,
                  sequentialStatus: _sequentialStatus,
                  onDownloadSequential: _downloadSequential,
                  onCancelSequential: _cancelSequential,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
