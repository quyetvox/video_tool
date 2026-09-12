import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../core/file_service.dart';
import '../core/providers.dart';
import '../core/engine_bridge.dart';
import '../models/subtitle_segment.dart';
import '../widgets/resizable_collapsible_panel.dart';
import '../widgets/video_player_widget.dart';
import 'subtitle_editor/components/subtitle_editor_components.dart';

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
    final wsDir = p.join(projectsDir, activeProject, 'workspace', jobId);
    
    // Priority: s08c_timing.json (Polished In/Out) -> s08_translation.json -> s07_transcript.json
    String jsonPath = p.join(wsDir, 's08c_timing.json');
    if (!File(jsonPath).existsSync()) {
      jsonPath = p.join(wsDir, 's08_translation.json');
    }
    if (!File(jsonPath).existsSync()) {
      jsonPath = p.join(wsDir, 's07_transcript.json');
    }

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

    final wsDir = p.join(projectsDir, activeProject, 'workspace', _loadedJobId!);
    final rawList = _segments.map((s) => s.toJson()).toList();

    FileService.writeJsonFile(p.join(wsDir, 's08_translation.json'), rawList);
    FileService.writeJsonFile(p.join(wsDir, 's08c_timing.json'), rawList);
    File(p.join(wsDir, 's08_translation.done')).writeAsStringSync('{"status":"done"}');
    File(p.join(wsDir, 's08c_timing.done')).writeAsStringSync('{"status":"done"}');

    // Invalidate downstream render steps so they immediately re-render with new subtitles & TTS voice
    for (final stepDone in ['s09_subtitle_gen.done', 's11_subtitle_render.done', 's12_tts.done', 's13_audio_mix.done', 's14_encode.done']) {
      final f = File(p.join(wsDir, stepDone));
      if (f.existsSync()) f.deleteSync();
    }

    setState(() => _hasUnsavedChanges = false);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('💾 Đã lưu đồng bộ phụ đề & timing thành công!'), duration: Duration(seconds: 2)),
    );

    if (resumeAfter) {
      final jobId = _loadedJobId!;
      EngineBridge.resumeJob(
        selectedVideo.fullPath,
        projectId: activeProject,
      ).then((res) {
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

  void _toggleSpeaker(int index) {
    if (index >= 0 && index < _segments.length) {
      final current = _segments[index];
      final raw = current.speaker.toLowerCase();
      final String nextSpeaker;
      final String nextGender;
      if (raw == 'nam' || raw == 'male' || current.gender == 'male') {
        nextSpeaker = 'Nữ';
        nextGender = 'female';
      } else if (raw == 'nữ' || raw == 'nu' || raw == 'female' || current.gender == 'female') {
        nextSpeaker = 'Nam';
        nextGender = 'male';
      } else {
        nextSpeaker = 'Nữ';
        nextGender = 'female';
      }
      setState(() {
        _segments[index] = current.copyWith(
          speaker: nextSpeaker,
          gender: nextGender,
        );
        _hasUnsavedChanges = true;
      });
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
        // ── TOP ACTION BAR ──
        SubtitleEditorTopBar(
          selectedVideo: selectedVideo,
          hasUnsavedChanges: _hasUnsavedChanges,
          hasSegments: _segments.isNotEmpty,
          onAddSegment: () => _addNewSegment(_segments.length),
          onReload: _loadTranslationJson,
          onSaveOnly: () => _saveTranslation(resumeAfter: false),
          onSaveAndResume: () => _saveTranslation(resumeAfter: true),
        ),

        // ── MAIN CONTENT (List on Left, Resizable Video Player on Right) ──
        Expanded(
          child: ResizableCollapsiblePanel(
            initialWidth: 440,
            minWidth: 280,
            maxWidth: 700,
            side: PanelSide.right,
            collapseTooltip: 'Thu gọn video preview',
            panel: SubtitlePreviewPanel(
              selectedVideo: selectedVideo,
              playerKey: _playerKey,
            ),
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

                          return SubtitleSegmentCard(
                            index: index,
                            seg: seg,
                            isSelected: isSelected,
                            onSeek: () {
                              setState(() => _selectedSegmentIndex = index);
                              _playerKey.currentState?.seekTo(seg.start);
                              _playerKey.currentState?.play();
                            },
                            onToggleSpeaker: () => _toggleSpeaker(index),
                            onAdjustStartMinus: () {
                              setState(() {
                                _segments[index] = seg.copyWith(
                                  start: (seg.start - 0.1).clamp(0.0, seg.end - 0.1),
                                );
                                _hasUnsavedChanges = true;
                              });
                            },
                            onAdjustEndPlus: () {
                              setState(() {
                                _segments[index] = seg.copyWith(end: seg.end + 0.1);
                                _hasUnsavedChanges = true;
                              });
                            },
                            onInsertBelow: () => _addNewSegment(index + 1),
                            onDelete: () => _deleteSegment(index),
                            onTextChanged: (val) {
                              _segments[index] = seg.copyWith(
                                translatedText: val,
                                textVi: val,
                              );
                              _hasUnsavedChanges = true;
                            },
                          );
                        },
                      ),
          ),
        ),
      ],
    );
  }
}
