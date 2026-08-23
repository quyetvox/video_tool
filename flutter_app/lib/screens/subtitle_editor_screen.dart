import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../core/file_service.dart';
import '../core/providers.dart';
import '../core/python_bridge.dart';
import '../models/subtitle_segment.dart';
import '../utils/time_format_utils.dart';
import '../widgets/video_player_widget.dart';

class SubtitleEditorScreen extends ConsumerStatefulWidget {
  const SubtitleEditorScreen({super.key});

  @override
  ConsumerState<SubtitleEditorScreen> createState() => _SubtitleEditorScreenState();
}

class _SubtitleEditorScreenState extends ConsumerState<SubtitleEditorScreen> {
  final GlobalKey<VideoPlayerWidgetState> _playerKey = GlobalKey<VideoPlayerWidgetState>();
  List<SubtitleSegment> _segments = [];
  bool _isLoading = false;
  bool _hasUnsavedChanges = false;
  String? _loadedJobId;
  int? _selectedSegmentIndex;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadTranslationJson();
    });
  }

  void _loadTranslationJson() {
    final selectedVideo = ref.read(selectedVideoProvider);
    final activeProject = ref.read(activeProjectProvider);
    final projectsDir = ref.read(projectsDirProvider);

    if (selectedVideo == null || activeProject == null) return;

    final jobId = 'job_${selectedVideo.stem}';
    final jsonPath = p.join(projectsDir, activeProject, 'workspace', jobId, 's08_translation.json');

    setState(() {
      _isLoading = true;
      _loadedJobId = jobId;
    });

    final data = FileService.readJsonFile(jsonPath);
    final list = <SubtitleSegment>[];

    if (data is List) {
      for (int i = 0; i < data.length; i++) {
        final item = data[i];
        if (item is Map<String, dynamic>) {
          list.add(SubtitleSegment.fromJson(item, i + 1));
        }
      }
    }

    setState(() {
      _segments = list;
      _isLoading = false;
      _hasUnsavedChanges = false;
    });
  }

  Future<void> _saveTranslation({bool resumeAfter = false}) async {
    final selectedVideo = ref.read(selectedVideoProvider);
    final activeProject = ref.read(activeProjectProvider);
    final projectsDir = ref.read(projectsDirProvider);

    if (selectedVideo == null || activeProject == null || _loadedJobId == null) return;

    final jsonPath = p.join(projectsDir, activeProject, 'workspace', _loadedJobId!, 's08_translation.json');
    final rawList = _segments.map((s) => s.toJson()).toList();

    FileService.writeJsonFile(jsonPath, rawList);

    setState(() => _hasUnsavedChanges = false);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('💾 Đã lưu file s08_translation.json thành công!'), duration: Duration(seconds: 2)),
    );

    if (resumeAfter) {
      final jobId = _loadedJobId!;
      ref.read(runningPathsProvider.notifier).update((set) => {...set, selectedVideo.relPath, selectedVideo.stem, jobId});

      PythonBridge.runScript('main.py', ['resume', '$activeProject:$jobId'], jobId: 'resume_${selectedVideo.stem}').then((res) {
        ref.read(runningPathsProvider.notifier).update((set) => set.where((p) => !p.contains(selectedVideo.stem)).toSet());
        ref.invalidate(projectVideosProvider);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('🔄 Đang kích hoạt Cascade Invalidation & Resume: $activeProject:$jobId'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _addNewSegment(int atIndex) {
    double start = 0.0;
    double end = 2.0;

    if (_segments.isNotEmpty) {
      if (atIndex < _segments.length) {
        start = _segments[atIndex].end + 0.1;
        end = start + 2.0;
      } else {
        start = _segments.last.end + 0.1;
        end = start + 2.0;
      }
    }

    final newSeg = SubtitleSegment(
      id: _segments.length + 1,
      start: double.parse(start.toStringAsFixed(2)),
      end: double.parse(end.toStringAsFixed(2)),
      text: '',
      textVi: '',
    );

    setState(() {
      _segments.insert(atIndex.clamp(0, _segments.length), newSeg);
      _hasUnsavedChanges = true;
    });
  }

  void _deleteSegment(int index) {
    setState(() {
      _segments.removeAt(index);
      _hasUnsavedChanges = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final selectedVideo = ref.watch(selectedVideoProvider);

    if (selectedVideo == null) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.subtitles_outlined, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('Vui lòng chọn một video từ tab "Videos" để mở trình biên tập phụ đề.', style: TextStyle(fontSize: 14)),
          ],
        ),
      );
    }

    return Column(
      children: [
        // ── TOP ACTION BAR ───────────────────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF0F172A) : Colors.white,
            border: Border(bottom: BorderSide(color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0))),
          ),
          child: Row(
            children: [
              const Icon(Icons.edit_note, color: Colors.cyanAccent, size: 22),
              const SizedBox(width: 8),
              Text(
                'Biên tập phụ đề s08: ${selectedVideo.basename}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(width: 12),
              if (_hasUnsavedChanges)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'Chưa lưu thay đổi',
                    style: TextStyle(fontSize: 11, color: Colors.orangeAccent, fontWeight: FontWeight.bold),
                  ),
                ),
              const Spacer(),

              // Add Segment Button
              OutlinedButton.icon(
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Thêm câu'),
                onPressed: () => _addNewSegment(_segments.length),
              ),
              const SizedBox(width: 8),

              // Reload
              IconButton(
                tooltip: 'Tải lại từ file gốc',
                icon: const Icon(Icons.refresh, size: 20),
                onPressed: _loadTranslationJson,
              ),
              const SizedBox(width: 8),

              // Save Only
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueGrey.shade800,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.save_outlined, size: 16),
                label: const Text('Lưu file'),
                onPressed: _segments.isEmpty ? null : () => _saveTranslation(resumeAfter: false),
              ),
              const SizedBox(width: 8),

              // Save & Resume Pipeline
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.cyan.shade700,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.bolt, size: 16),
                label: const Text('Lưu & Render Resume (~2s)'),
                onPressed: _segments.isEmpty ? null : () => _saveTranslation(resumeAfter: true),
              ),
            ],
          ),
        ),

        // ── MAIN CONTENT (List on Left, Video Player on Right) ───────
        Expanded(
          child: Row(
            children: [
              // Segment List Editor
              Expanded(
                flex: 6,
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _segments.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.find_in_page_outlined, size: 48, color: Colors.grey),
                                const SizedBox(height: 12),
                                const Text(
                                  'Chưa tìm thấy dữ liệu dịch s08_translation.json',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 6),
                                const Text(
                                  'Hãy chạy pipeline dịch trước (bước 8), hoặc bấm "Thêm câu" để tạo phụ đề thủ công.',
                                  style: TextStyle(color: Colors.grey, fontSize: 12),
                                ),
                                const SizedBox(height: 16),
                                ElevatedButton.icon(
                                  icon: const Icon(Icons.add),
                                  label: const Text('Thêm câu đầu tiên'),
                                  onPressed: () => _addNewSegment(0),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.all(12),
                            itemCount: _segments.length,
                            itemBuilder: (context, index) {
                              final seg = _segments[index];
                              final isSelected = _selectedSegmentIndex == index;

                              return _buildSegmentCard(context, index, seg, isSelected, isDark);
                            },
                          ),
              ),

              const VerticalDivider(width: 1, thickness: 1),

              // Right Video Player Preview
              Expanded(
                flex: 4,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.ondemand_video, size: 18, color: Colors.cyanAccent),
                          SizedBox(width: 8),
                          Text('Xem trước Video', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: VideoPlayerWidget(
                          key: _playerKey,
                          videoPath: selectedVideo.fullPath,
                          autoPlay: false,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF1E293B) : Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.info_outline, size: 16, color: Colors.cyanAccent),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Mẹo: Bấm vào mốc thời gian của từng câu bên trái để tự động nhảy (Seek) video tới đúng đoạn đó.',
                                style: TextStyle(fontSize: 11, color: Colors.grey, height: 1.3),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSegmentCard(
    BuildContext context,
    int index,
    SubtitleSegment seg,
    bool isSelected,
    bool isDark,
  ) {
    final textController = TextEditingController(text: seg.displayText);
    textController.selection = TextSelection.fromPosition(TextPosition(offset: textController.text.length));

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: isSelected ? 3 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: isSelected ? Colors.cyanAccent : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
          width: isSelected ? 1.5 : 1,
        ),
      ),
      color: isDark ? const Color(0xFF1E293B) : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Row 1: Index + Timecode Range + Seek Button + Add/Delete Buttons
            Row(
              children: [
                // Index Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.cyanAccent.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '#${seg.id}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.cyanAccent),
                  ),
                ),
                const SizedBox(width: 8),

                // Timecode Seek Button
                InkWell(
                  onTap: () {
                    setState(() => _selectedSegmentIndex = index);
                    _playerKey.currentState?.seekTo(seg.start);
                    _playerKey.currentState?.play();
                  },
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.cyanAccent.withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.play_circle_fill, size: 14, color: Colors.cyanAccent),
                        const SizedBox(width: 6),
                        Text(
                          '${TimeFormatUtils.formatSubtitleTime(seg.start)} ➔ ${TimeFormatUtils.formatSubtitleTime(seg.end)}',
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 11, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '(${(seg.end - seg.start).toStringAsFixed(1)}s)',
                          style: const TextStyle(fontSize: 10, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ),

                const Spacer(),

                // Time adjust buttons (-0.1s, +0.1s)
                IconButton(
                  tooltip: 'Lùi Start 0.1s',
                  icon: const Icon(Icons.remove, size: 14),
                  onPressed: () {
                    setState(() {
                      _segments[index] = seg.copyWith(start: (seg.start - 0.1).clamp(0.0, seg.end - 0.1));
                      _hasUnsavedChanges = true;
                    });
                  },
                ),
                IconButton(
                  tooltip: 'Tăng End 0.1s',
                  icon: const Icon(Icons.add, size: 14),
                  onPressed: () {
                    setState(() {
                      _segments[index] = seg.copyWith(end: seg.end + 0.1);
                      _hasUnsavedChanges = true;
                    });
                  },
                ),

                // Insert below
                IconButton(
                  tooltip: 'Chèn câu phía dưới',
                  icon: const Icon(Icons.playlist_add, size: 16),
                  onPressed: () => _addNewSegment(index + 1),
                ),

                // Delete
                IconButton(
                  tooltip: 'Xóa câu này',
                  icon: const Icon(Icons.delete_outline, size: 16, color: Colors.redAccent),
                  onPressed: () => _deleteSegment(index),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Original Text (if exists)
            if (seg.text.isNotEmpty) ...[
              Text(
                'Gốc: ${seg.text}',
                style: const TextStyle(fontSize: 11, color: Colors.grey, fontStyle: FontStyle.italic),
              ),
              const SizedBox(height: 4),
            ],

            // Translated Text Field (Vietnamese)
            TextField(
              controller: textController,
              onChanged: (val) {
                _segments[index] = seg.copyWith(
                  translatedText: val,
                  textVi: val,
                );
                _hasUnsavedChanges = true;
              },
              maxLines: null,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
              decoration: InputDecoration(
                hintText: 'Nhập nội dung phụ đề tiếng Việt...',
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                filled: true,
                fillColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
