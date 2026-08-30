import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:io';
import 'package:path/path.dart' as p;
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scanTxtFiles());
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
        txts.add(p.relative(f.path, from: projDir.path));
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

  void _loadLinks() {
    final activeProject = ref.read(activeProjectProvider);
    final projectsDir = ref.read(projectsDirProvider);
    if (activeProject == null || _selectedTxtFile == null) return;

    final filePath = p.join(projectsDir, activeProject, _selectedTxtFile!);
    final file = File(filePath);
    if (!file.existsSync()) {
      setState(() => _items = []);
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
          _selectedItem = parsed.first;
        }
      });
    } catch (_) {}
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
                            'Tải Video Douyin Hàng Loạt',
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
                            padding: const EdgeInsets.all(10),
                            child: Row(
                              children: [
                                Text(
                                  '${displayItems.length} Video tìm thấy',
                                  style: TextStyle(color: c.textPrimary, fontSize: 11, fontWeight: FontWeight.w600),
                                ),
                              const Spacer(),
                              AppButton.primary(
                                label: '📥 Tải Toàn Bộ (${displayItems.length}) Video',
                                icon: Icons.download,
                                height: 30,
                                fontSize: 11,
                                isLoading: _isDownloadingAll,
                                onPressed: _isDownloadingAll ? null : _downloadAll,
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

                              return Container(
                                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                                decoration: BoxDecoration(
                                  color: isSelected ? AppColors.surfaceLight : AppColors.surfaceDark,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: isSelected ? AppColors.primary : AppColors.border, width: 0.8),
                                ),
                                child: ListTile(
                                  dense: true,
                                  leading: Text(
                                    '#${it.index.toString().padLeft(2, '0')}',
                                    style: const TextStyle(color: AppColors.textMuted, fontSize: 11, fontWeight: FontWeight.bold),
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
