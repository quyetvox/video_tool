import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:io';
import 'package:path/path.dart' as p;
import '../core/providers.dart';
import '../core/python_bridge.dart';
import '../models/douyin_video_item.dart';
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

    // Get existing files in src/
    final srcDir = Directory(p.join(projectsDir, activeProject, 'src'));
    final srcFiles = srcDir.existsSync()
        ? srcDir.listSync().whereType<File>().map((f) => p.basename(f.path)).toList()
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
      [item.directUrl, '--output', outPath],
      jobId: 'dl_${item.shortHash}',
    );

    setState(() => _downloadingIndex = -1);

    if (res.success) {
      ref.invalidate(projectVideosProvider);
      _loadLinks();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Đã tải thành công ${item.filename} vào src/!'), backgroundColor: const Color(0xFF10B981)),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi tải video: ${res.output}')));
      }
    }
  }

  void _downloadAll() async {
    final activeProject = ref.read(activeProjectProvider);
    final projectsDir = ref.read(projectsDirProvider);
    if (activeProject == null || _selectedTxtFile == null) return;

    setState(() => _isDownloadingAll = true);
    final txtPath = p.join(projectsDir, activeProject, _selectedTxtFile!);

    final res = await PythonBridge.runScript(
      'download.py',
      [txtPath],
      jobId: 'dl_batch_$activeProject',
    );

    setState(() => _isDownloadingAll = false);

    if (res.success) {
      ref.invalidate(projectVideosProvider);
      _loadLinks();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã hoàn tất tải toàn bộ danh sách video!'), backgroundColor: Color(0xFF10B981)),
        );
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

    return Scaffold(
      backgroundColor: const Color(0xFF0B1120),
      body: Column(
        children: [
          // 1. Top Downloader Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: Color(0xFF0F172A),
              border: Border(bottom: BorderSide(color: Color(0xFF1E293B))),
            ),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(Icons.cloud_download, color: Color(0xFF10B981), size: 18),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'Tải Video Douyin Hàng Loạt',
                          style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(4)),
                          child: Text('📁 assets/$activeProject/', style: const TextStyle(color: Color(0xFF06B6D4), fontSize: 11)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Trích xuất, xem trước và tải video chất lượng cao từ danh sách URL Douyin vào thư mục src/',
                      style: TextStyle(color: Color(0xFF64748B), fontSize: 11),
                    ),
                  ],
                ),
                const Spacer(),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFCBD5E1),
                    side: const BorderSide(color: Color(0xFF334155)),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  ),
                  icon: const Icon(Icons.edit_note, size: 14),
                  label: const Text('Sửa File Raw', style: TextStyle(fontSize: 11.5)),
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
                  icon: const Icon(Icons.refresh, size: 16, color: Color(0xFF94A3B8)),
                  tooltip: 'Tải lại',
                  onPressed: _scanTxtFiles,
                ),
              ],
            ),
          ),

          // 2. Input Link File Selector Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: const BoxDecoration(
              color: Color(0xFF0B1120),
              border: Border(bottom: BorderSide(color: Color(0xFF1E293B))),
            ),
            child: Row(
              children: [
                const Text('Đường dẫn file link:', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
                const SizedBox(width: 10),
                Expanded(
                  child: Container(
                    height: 32,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: const Color(0xFF334155)),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _selectedTxtFile,
                        isExpanded: true,
                        dropdownColor: const Color(0xFF1E293B),
                        style: const TextStyle(color: Colors.white, fontSize: 12),
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
                    decoration: const BoxDecoration(
                      border: Border(right: BorderSide(color: Color(0xFF1E293B))),
                    ),
                    child: Column(
                      children: [
                        // Search & Batch Download Bar
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              Text(
                                'Danh sách Video (${displayItems.length})',
                                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                              ),
                              const Spacer(),
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF10B981),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                ),
                                icon: _isDownloadingAll
                                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                    : const Icon(Icons.download, size: 14),
                                label: Text('📥 Tải Toàn Bộ (${displayItems.length}) Video', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                                onPressed: _isDownloadingAll ? null : _downloadAll,
                              ),
                            ],
                          ),
                        ),

                        // Search Input
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: TextField(
                            style: const TextStyle(fontSize: 12, color: Colors.white),
                            decoration: InputDecoration(
                              hintText: 'Lọc link theo ID, bitrate hoặc URL...',
                              hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 11),
                              prefixIcon: const Icon(Icons.search, size: 14, color: Color(0xFF64748B)),
                              contentPadding: EdgeInsets.zero,
                              filled: true,
                              fillColor: const Color(0xFF1E293B),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none),
                            ),
                            onChanged: (v) => setState(() => _searchQuery = v),
                          ),
                        ),

                        const SizedBox(height: 10),

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
                                  color: isSelected ? const Color(0xFF1E293B) : const Color(0xFF0F172A),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: isSelected ? const Color(0xFF06B6D4) : const Color(0xFF1E293B)),
                                ),
                                child: ListTile(
                                  dense: true,
                                  leading: Text(
                                    '#${it.index.toString().padLeft(2, '0')}',
                                    style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontWeight: FontWeight.bold),
                                  ),
                                  title: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF2563EB).withOpacity(0.2),
                                          borderRadius: BorderRadius.circular(3),
                                        ),
                                        child: Text(it.resolution, style: const TextStyle(color: Color(0xFF06B6D4), fontSize: 9.5, fontWeight: FontWeight.bold)),
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
                                            color: const Color(0xFF10B981).withOpacity(0.2),
                                            borderRadius: BorderRadius.circular(3),
                                          ),
                                          child: const Text('✓ Đã có trong src/', style: TextStyle(color: Color(0xFF10B981), fontSize: 9)),
                                        ),
                                      Expanded(
                                        child: Text(
                                          it.directUrl,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(color: Color(0xFF64748B), fontSize: 10),
                                        ),
                                      ),
                                    ],
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.copy, size: 14, color: Color(0xFF94A3B8)),
                                        onPressed: () {
                                          Clipboard.setData(ClipboardData(text: it.directUrl));
                                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã copy link!')));
                                        },
                                      ),
                                      IconButton(
                                        icon: _downloadingIndex == it.index
                                            ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2))
                                            : const Icon(Icons.download, size: 16, color: Color(0xFF10B981)),
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
                        ? const Center(child: Text('Chọn video để xem trước', style: TextStyle(color: Color(0xFF64748B))))
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.ondemand_video, size: 16, color: Color(0xFF06B6D4)),
                                  const SizedBox(width: 8),
                                  Text('Xem Trước Video (Live Preview) — #${_selectedItem!.index}', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                                ],
                              ),
                              const SizedBox(height: 12),

                              // Preview Player
                              Expanded(
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.black,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: const Color(0xFF1E293B)),
                                  ),
                                  child: _selectedItem!.localFilePath != null
                                      ? VideoPlayerWidget(videoPath: _selectedItem!.localFilePath!)
                                      : const Center(
                                          child: Text('Preview Stream CDN', style: TextStyle(color: Color(0xFF64748B), fontSize: 12)),
                                        ),
                                ),
                              ),

                              const SizedBox(height: 12),

                              // Specs Table
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(color: const Color(0xFF0F172A), borderRadius: BorderRadius.circular(6)),
                                child: Column(
                                  children: [
                                    _buildSpecRow('Tên file tải về:', _selectedItem!.filename),
                                    _buildSpecRow('Ngày đăng (Timestamp):', _selectedItem!.timestampStr ?? 'N/A'),
                                    _buildSpecRow('Video ID / Hash:', _selectedItem!.shortHash),
                                    _buildSpecRow('Chất lượng / Bitrate:', _selectedItem!.bitrateStr),
                                    _buildSpecRow('Lưu về thư mục:', 'assets/$activeProject/src/'),
                                  ],
                                ),
                              ),

                              const SizedBox(height: 12),

                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF2563EB),
                                  foregroundColor: Colors.white,
                                  minimumSize: const Size(double.infinity, 40),
                                ),
                                icon: const Icon(Icons.download, size: 16),
                                label: Text('📥 Tải Ngay Video #${_selectedItem!.index} Về src/', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                                onPressed: () => _downloadSingle(_selectedItem!),
                              ),
                            ],
                          ),
                  ),
                ),
              ],
            ),
          ),
        ],
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
