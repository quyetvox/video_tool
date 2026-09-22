import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import '../core/app_colors.dart';
import '../core/license_service.dart';
import '../core/media_link_service.dart';
import '../core/providers.dart';
import '../core/python_bridge.dart';
import '../models/douyin_video_item.dart';
import '../models/media_link_info.dart';
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
  final bool _isDownloadingAll = false;
  int _downloadingIndex = -1;

  // ── Lazy On-Demand Stream Probing State ──────────────────────
  bool _isProbing = false;
  String? _probeError;
  int _probeToken = 0;

  // ── Multi-selection & Sequential Download State ──────────────
  final Set<int> _selectedIndexes = {};
  bool _isDownloadingSequential = false;
  int _sequentialCurrent = 0;
  int _sequentialTotal = 0;
  String _sequentialStatus = '';
  bool _isCancelRequested = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadInitialPath());
  }

  @override
  void dispose() {
    _filePathController.dispose();
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
        _selectedIndexes.removeWhere((i) => i >= parsed.length);
      });

      if (parsed.isNotEmpty) {
        final initialItem = parsed.firstWhere(
          (it) => it.index == _selectedItem?.index,
          orElse: () => parsed.first,
        );
        _handleItemSelected(initialItem);
      }

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

  void _handleStreamPreviewReady(MediaLinkInfo info) {
    final nowStr = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final title = info.title.isNotEmpty ? info.title : 'Live Stream Video';
    const platformTag = 'stream';
    final safeTitle = info.title.trim().replaceAll(RegExp(r'[\\/*?:"<>|]'), '_');
    final filename = safeTitle.isNotEmpty ? '$safeTitle.mp4' : '${nowStr}_$platformTag.mp4';

    final newItem = DouyinVideoItem(
      index: _items.length + 1,
      rawUrl: info.rawUrl,
      directUrl: info.streamUrl,
      filename: filename,
      shortHash: platformTag,
      timestampStr: nowStr,
      resolution: info.formattedDuration.isNotEmpty ? info.formattedDuration : '1080p HD',
      bitrateStr: 'Live CDN',
      isDownloaded: false,
      localFilePath: null,
      audioUrl: info.audioUrl,
      httpHeaders: info.httpHeaders,
      title: info.title.isNotEmpty ? info.title : null,
      isProbed: true,
    );

    _probeToken++;
    setState(() {
      _selectedItem = newItem;
      _isProbing = false;
      _probeError = null;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('⚡ Đang phát xem trước trực tuyến: $title'),
        backgroundColor: const Color(0xFF2563EB),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _handleItemSelected(DouyinVideoItem it) async {
    final isLocal = it.isDownloaded &&
        it.localFilePath != null &&
        File(it.localFilePath!).existsSync();

    if (isLocal) {
      _probeToken++;
      setState(() {
        _selectedItem = it;
        _isProbing = false;
        _probeError = null;
      });
      return;
    }

    // If it's already probed or has separate audioUrl or httpHeaders
    if (it.isProbed || it.audioUrl != null || (it.httpHeaders != null && it.httpHeaders!.isNotEmpty)) {
      _probeToken++;
      setState(() {
        _selectedItem = it;
        _isProbing = false;
        _probeError = null;
      });
      return;
    }

    // Check if it is a platform web link needing probe (Bilibili, YouTube, TikTok, Douyin web)
    final lower = it.rawUrl.toLowerCase();
    final isWebLink = lower.contains('bilibili.com') ||
        lower.contains('youtube.com') ||
        lower.contains('youtu.be') ||
        lower.contains('tiktok.com') ||
        (lower.contains('douyin.com') && !lower.contains('.mp4') && !lower.contains('snssdk.com'));

    if (!isWebLink) {
      // Direct CDN MP4 or other direct stream, play directly
      _probeToken++;
      setState(() {
        _selectedItem = it;
        _isProbing = false;
        _probeError = null;
      });
      return;
    }

    // Needs on-demand probe
    final currentToken = ++_probeToken;
    setState(() {
      _selectedItem = it;
      _isProbing = true;
      _probeError = null;
    });

    final info = await MediaLinkService.probeUrl(it.rawUrl);

    if (!mounted || currentToken != _probeToken) return;

    if (info.success && info.streamUrl.isNotEmpty) {
      final safeTitle = info.title.trim().replaceAll(RegExp(r'[\\/*?:"<>|]'), '_');
      final cleanFilename = safeTitle.isNotEmpty ? '$safeTitle.mp4' : it.filename;
      final updated = it.copyWith(
        directUrl: info.streamUrl,
        audioUrl: info.audioUrl,
        httpHeaders: info.httpHeaders,
        title: info.title.isNotEmpty ? info.title : null,
        filename: cleanFilename,
        resolution: info.formattedDuration.isNotEmpty ? info.formattedDuration : it.resolution,
        isProbed: true,
      );

      final idx = _items.indexWhere((x) => x.index == it.index);
      if (idx != -1) {
        _items[idx] = updated;
      }

      setState(() {
        _selectedItem = updated;
        _isProbing = false;
        _probeError = null;
      });
    } else {
      setState(() {
        _isProbing = false;
        _probeError = info.error ?? 'Không thể bóc tách luồng xem trước video này.';
      });
    }
  }

  void _handleVideoDownloaded(String localFilePath, String videoName) {
    final nowStr = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final title = videoName.isNotEmpty ? videoName : p.basenameWithoutExtension(localFilePath);
    final filename = p.basename(localFilePath);

    final newItem = DouyinVideoItem(
      index: _items.length + 1,
      rawUrl: localFilePath,
      directUrl: '',
      filename: filename,
      shortHash: 'dl',
      timestampStr: nowStr,
      resolution: '1080p HD',
      bitrateStr: 'Local',
      isDownloaded: true,
      localFilePath: localFilePath,
    );

    setState(() {
      _items.add(newItem);
      _selectedItem = newItem;
    });

    ref.invalidate(projectVideosProvider);
    _loadLinks();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('✅ Đã tải và thêm video vào danh sách: $title'),
        backgroundColor: const Color(0xFF10B981),
        duration: const Duration(seconds: 3),
      ),
    );
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

    final lower = item.rawUrl.toLowerCase();
    final isUniversalMedia = item.audioUrl != null ||
        item.shortHash == 'stream' ||
        lower.contains('bilibili.com') ||
        lower.contains('youtube.com') ||
        lower.contains('youtu.be') ||
        lower.contains('tiktok.com') ||
        (lower.contains('douyin.com') && !lower.contains('.mp4') && !lower.contains('snssdk.com'));

    if (isUniversalMedia) {
      final customName = item.filename.endsWith('.mp4')
          ? item.filename.replaceAll(RegExp(r'\.mp4$', caseSensitive: false), '')
          : item.filename;

      await MediaLinkService.downloadVideo(
        url: item.rawUrl,
        targetDir: srcDir.path,
        customFilename: customName,
        onProgress: (progress, statusText) {},
        onCompleted: (savedFilePath) {
          setState(() => _downloadingIndex = -1);
          ref.invalidate(projectVideosProvider);
          _loadLinks();
          _handleVideoDownloaded(savedFilePath, p.basename(savedFilePath));
        },
        onError: (err) {
          setState(() => _downloadingIndex = -1);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('❌ Lỗi tải video: $err'), backgroundColor: const Color(0xFFEF4444)),
            );
          }
        },
      );
      return;
    }

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
            title: _selectedItem!.title,
            isProbed: _selectedItem!.isProbed,
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
      final displayName = item.title?.isNotEmpty == true ? item.title! : item.filename;

      setState(() {
        _downloadingIndex = item.index;
        _sequentialCurrent = i + 1;
        _sequentialStatus = 'Đang tải (${i + 1}/${itemsToDownload.length}): $displayName';
      });

      final lower = item.rawUrl.toLowerCase();
      final isUniversalMedia = item.audioUrl != null ||
          item.shortHash == 'stream' ||
          lower.contains('bilibili.com') ||
          lower.contains('youtube.com') ||
          lower.contains('youtu.be') ||
          lower.contains('tiktok.com') ||
          (lower.contains('douyin.com') && !lower.contains('.mp4') && !lower.contains('snssdk.com'));

      bool success = false;
      if (isUniversalMedia) {
        final completer = Completer<bool>();
        final customName = item.filename.endsWith('.mp4')
            ? item.filename.replaceAll(RegExp(r'\.mp4$', caseSensitive: false), '')
            : item.filename;

        await MediaLinkService.downloadVideo(
          url: item.rawUrl,
          targetDir: srcDir.path,
          customFilename: customName,
          onProgress: (progress, statusText) {
            if (mounted && !_isCancelRequested) {
              setState(() {
                final pct = (progress * 100).toStringAsFixed(0);
                _sequentialStatus = 'Đang tải (${i + 1}/${itemsToDownload.length}): $displayName ($pct% - $statusText)';
              });
            }
          },
          onCompleted: (savedFilePath) {
            ref.invalidate(projectVideosProvider);
            completer.complete(true);
          },
          onError: (err) {
            completer.complete(false);
          },
        );

        success = await completer.future;
      } else {
        final outPath = p.join(srcDir.path, item.filename);
        final res = await PythonBridge.runScript(
          'download.py',
          [item.directUrl, '-o', outPath],
          jobId: 'dl_seq_${item.shortHash}',
        );
        success = res.success;
      }

      if (success) {
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
    MediaLinkService.cancelDownload();
    setState(() {
      _isCancelRequested = true;
      _sequentialStatus = 'Đang yêu cầu dừng tải...';
    });
  }

  void _downloadAll() async {
    final activeProject = ref.read(activeProjectProvider);
    if (activeProject == null) return;

    final displayItems = _items.where((it) {
      if (_searchQuery.isEmpty) return true;
      return it.rawUrl.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          it.filename.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          it.shortHash.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          (it.title != null && it.title!.toLowerCase().contains(_searchQuery.toLowerCase()));
    }).toList();

    if (displayItems.isEmpty) return;

    setState(() {
      _selectedIndexes.clear();
      _selectedIndexes.addAll(displayItems.map((e) => e.index));
    });

    _downloadSequential();
  }

  @override
  Widget build(BuildContext context) {
    final activeProject = ref.watch(activeProjectProvider);

    final displayItems = _items.where((it) {
      if (_searchQuery.isEmpty) return true;
      return it.rawUrl.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          it.filename.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          it.shortHash.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          (it.title != null && it.title!.toLowerCase().contains(_searchQuery.toLowerCase()));
    }).toList();

    final c = AppColors.of(context);

    final projectsDir = ref.watch(projectsDirProvider);
    final targetDir = activeProject != null ? p.join(projectsDir, activeProject, 'src') : '';

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

            // 2. Input Link File Selector Bar & Internet Video Link Bar
            DouyinUrlInputBar(
              filePathController: _filePathController,
              onFilePathSubmitted: (val) => _loadLinksFromPath(val),
              onPickLinkFile: _pickLinkFile,
              targetDir: targetDir,
              onStreamPreviewReady: _handleStreamPreviewReady,
              onVideoDownloaded: _handleVideoDownloaded,
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
                  isProbing: _isProbing,
                  probeError: _probeError,
                  onRetryProbe: _selectedItem != null ? () => _handleItemSelected(_selectedItem!) : null,
                ),
                child: DouyinVideoTable(
                  displayItems: displayItems,
                  selectedItem: _selectedItem,
                  selectedIndexes: _selectedIndexes,
                  searchQuery: _searchQuery,
                  onSearchChanged: (val) => setState(() => _searchQuery = val),
                  onToggleSelectAll: () => _toggleSelectAll(displayItems),
                  onToggleSelect: _toggleSelect,
                  onItemSelected: _handleItemSelected,
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
