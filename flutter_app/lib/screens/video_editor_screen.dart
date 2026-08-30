import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart' as p;
import '../core/app_colors.dart';
import '../core/providers.dart';
import '../core/file_service.dart';
import '../core/python_bridge.dart';
import '../core/engine_bridge.dart';
import '../models/video_file.dart';
import '../models/subtitle_segment.dart';
import '../widgets/video_player_widget.dart';
import '../widgets/subtitle_inspector_widget.dart';
import '../widgets/properties_inspector_widget.dart';
import '../widgets/asset_table_widget.dart';
import '../widgets/process_logs_console_widget.dart';
import '../widgets/confirm_dialog.dart';
import '../utils/time_format_utils.dart';

class VideoEditorScreen extends ConsumerStatefulWidget {
  final String? libraryFilter;

  const VideoEditorScreen({super.key, this.libraryFilter = 'all'});

  @override
  ConsumerState<VideoEditorScreen> createState() => _VideoEditorScreenState();
}

class _VideoEditorScreenState extends ConsumerState<VideoEditorScreen> {
  double _currentTime = 0.0;
  double _duration = 0.0;
  final double _startTime = 0.0;
  double _endTime = 5.0;
  final bool _isAccurateCut = true;
  bool _isProcessing = false;
  bool _isPlayerFullscreen = false;
  final GlobalKey<VideoPlayerWidgetState> _playerKey = GlobalKey<VideoPlayerWidgetState>();

  List<SubtitleSegment> _subtitles = [];
  bool _isSubModified = false;
  String _activeJobId = '';

  // AI Metadata
  String _metaTitle = '';
  String _metaDesc = '';
  List<String> _metaHashtags = [];

  void _loadSubtitlesAndMetadata(VideoFile video) {
    final activeProject = ref.read(activeProjectProvider);
    final projectsDir = ref.read(projectsDirProvider);
    if (activeProject == null) return;

    final jobDir = Directory(p.join(projectsDir, activeProject, 'workspace', video.jobId));
    final timingFile = File(p.join(jobDir.path, 's08c_timing.json'));
    final subFile = File(p.join(jobDir.path, 's08_translation.json'));
    final altSubFile = File(p.join(jobDir.path, 's07_transcript.json'));
    final metaFile = File(p.join(jobDir.path, 's08b_metadata.json'));

    File? targetFile;
    if (timingFile.existsSync()) {
      targetFile = timingFile;
    } else if (subFile.existsSync()) {
      targetFile = subFile;
    } else if (altSubFile.existsSync()) {
      targetFile = altSubFile;
    }

    if (targetFile != null) {
      try {
        final content = targetFile.readAsStringSync();
        final List<dynamic> data = jsonDecode(content);
        setState(() {
          _subtitles = data.asMap().entries.map((e) => SubtitleSegment.fromJson(e.value, e.key)).toList();
        });
      } catch (_) {
        setState(() => _subtitles = []);
      }
    } else {
      setState(() => _subtitles = []);
    }

    if (metaFile.existsSync()) {
      try {
        final content = metaFile.readAsStringSync();
        final data = jsonDecode(content);
        setState(() {
          _metaTitle = data['title'] ?? '';
          _metaDesc = data['description'] ?? '';
          _metaHashtags = List<String>.from(data['hashtags'] ?? []);
        });
      } catch (_) {
        setState(() {
          _metaTitle = '';
          _metaDesc = '';
          _metaHashtags = [];
        });
      }
    } else {
      setState(() {
        _metaTitle = '';
        _metaDesc = '';
        _metaHashtags = [];
      });
    }
  }

  void _saveSubtitlesAndCascadeResume() {
    final activeProject = ref.read(activeProjectProvider);
    final projectsDir = ref.read(projectsDirProvider);
    final selectedVideo = ref.read(selectedVideoProvider);
    if (activeProject == null || selectedVideo == null) return;

    final jobDir = Directory(p.join(projectsDir, activeProject, 'workspace', selectedVideo.jobId));
    if (!jobDir.existsSync()) jobDir.createSync(recursive: true);

    final list = _subtitles.map((s) => s.toJson()).toList();
    final jsonStr = const JsonEncoder.withIndent('  ').convert(list);
    final timingFile = File(p.join(jobDir.path, 's08c_timing.json'));
    timingFile.writeAsStringSync(jsonStr);

    // Invalidate downstream render steps so they immediately re-render with new subtitles & TTS voice
    for (final stepDone in ['s09_subtitle_gen.done', 's11_subtitle_render.done', 's12_tts.done', 's13_audio_mix.done', 's14_encode.done']) {
      final f = File(p.join(jobDir.path, stepDone));
      if (f.existsSync()) f.deleteSync();
    }

    setState(() => _isSubModified = false);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('💾 Đã lưu phụ đề. Bắt đầu tự động dựng lại từ bước Subtitle Gen!'),
        backgroundColor: AppColors.statusCompleted,
      ),
    );

    final jobId = 'resume_sub_${selectedVideo.stem}';
    ref.read(runningPathsProvider.notifier).update((set) => {...set, selectedVideo.relPath, selectedVideo.stem, jobId});

    EngineBridge.resumeJob(
      selectedVideo.fullPath,
      projectId: activeProject,
      jobId: jobId,
    ).then((_) {
      ref.read(runningPathsProvider.notifier).update((set) => set.where((p) => !p.contains(selectedVideo.stem) && !p.contains(jobId)).toSet());
    });
  }

  void _executeCutTrim() async {
    final selectedVideo = ref.read(selectedVideoProvider);
    if (selectedVideo == null) return;

    setState(() => _isProcessing = true);
    final startStr = TimeFormatUtils.formatSubtitleTime(_startTime).replaceAll(',', '.');
    final endStr = TimeFormatUtils.formatSubtitleTime(_endTime).replaceAll(',', '.');

    final extraArgs = _isAccurateCut ? ['--accurate'] : <String>[];
    
    // Trimmer keep range
    final args = [
      selectedVideo.fullPath,
      '--start',
      startStr,
      '--end',
      endStr,
      ...extraArgs,
    ];
    final result = await PythonBridge.runScript('trim.py', args, jobId: 'trim_${selectedVideo.stem}');

    setState(() => _isProcessing = false);

    if (result.success) {
      ref.invalidate(projectVideosProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('🎉 Đã cắt và lưu đoạn video ($startStr ➔ $endStr) thành công!'),
            backgroundColor: AppColors.statusCompleted,
          ),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi khi cắt video: ${result.output}'), backgroundColor: AppColors.statusFailed),
        );
      }
    }
  }

  void _triggerTranslateAll() {
    final selectedVideo = ref.read(selectedVideoProvider);
    final activeProject = ref.read(activeProjectProvider);
    if (selectedVideo == null || activeProject == null) return;

    final jobId = 'trans_${selectedVideo.stem}';
    setState(() {
      _isProcessing = true;
      _activeJobId = jobId;
    });

    ref.read(runningPathsProvider.notifier).update((set) => {...set, selectedVideo.relPath, selectedVideo.stem, jobId});

    EngineBridge.translateVideo(
      selectedVideo.fullPath,
      voice: true,
      jobId: jobId,
    ).then((res) {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _activeJobId = '';
        });
        ref.read(runningPathsProvider.notifier).update((set) => set.where((p) => !p.contains(selectedVideo.stem) && !p.contains(jobId)).toSet());
        ref.invalidate(projectVideosProvider);
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('🚀 Đã bắt đầu dịch toàn bộ video: ${selectedVideo.basename}'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _stopActiveProcess() {
    if (_activeJobId.isNotEmpty) {
      EngineBridge.cancelJob(_activeJobId);
      PythonBridge.stopJob(_activeJobId);
    }
    EngineBridge.cancelAll();
    PythonBridge.killAll();
    setState(() {
      _isProcessing = false;
      _activeJobId = '';
    });
    ref.read(runningPathsProvider.notifier).state = {};
  }

  // ── BATCH ACTIONS IMPLEMENTATION ──

  void _handleBatchTranslateVoice(List<VideoFile> files) async {
    for (final f in files) {
      final jobId = 'batch_voice_${f.stem}';
      setState(() {
        _isProcessing = true;
        _activeJobId = jobId;
      });
      ref.read(runningPathsProvider.notifier).update((set) => {...set, f.relPath, f.stem, jobId});
      await EngineBridge.translateVideo(f.fullPath, voice: true, jobId: jobId);
      ref.read(runningPathsProvider.notifier).update((set) => set.where((p) => !p.contains(f.stem) && !p.contains(jobId)).toSet());
    }
    if (mounted) {
      setState(() {
        _isProcessing = false;
        _activeJobId = '';
      });
      ref.invalidate(projectVideosProvider);
    }
  }

  void _handleBatchTranslateSub(List<VideoFile> files) async {
    for (final f in files) {
      final jobId = 'batch_sub_${f.stem}';
      setState(() {
        _isProcessing = true;
        _activeJobId = jobId;
      });
      ref.read(runningPathsProvider.notifier).update((set) => {...set, f.relPath, f.stem, jobId});
      await EngineBridge.translateVideo(f.fullPath, ocrOnly: true, jobId: jobId);
      ref.read(runningPathsProvider.notifier).update((set) => set.where((p) => !p.contains(f.stem) && !p.contains(jobId)).toSet());
    }
    if (mounted) {
      setState(() {
        _isProcessing = false;
        _activeJobId = '';
      });
      ref.invalidate(projectVideosProvider);
    }
  }

  void _handleBatchUploadCloud(List<VideoFile> files) async {
    final activeProject = ref.read(activeProjectProvider);
    if (activeProject == null) return;
    for (final f in files) {
      await PythonBridge.runScript('storage.py', ['sync-up', activeProject], jobId: 'upload_${f.stem}');
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Đã tải lên ${files.length} video lên GCS thành công!'), backgroundColor: const Color(0xFF10B981)),
      );
    }
  }

  void _handleBatchSyncDown(List<VideoFile> files) async {
    final activeProject = ref.read(activeProjectProvider);
    if (activeProject == null) return;
    await PythonBridge.runScript('storage.py', ['sync-down', activeProject], jobId: 'sync_down_batch');
    if (mounted) {
      ref.invalidate(projectVideosProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã đồng bộ video từ Cloud về local thành công!'), backgroundColor: Color(0xFF10B981)),
      );
    }
  }

  void _handleBatchOffload(List<VideoFile> files) async {
    final activeProject = ref.read(activeProjectProvider);
    if (activeProject == null) return;
    await PythonBridge.runScript('storage.py', ['offload', activeProject], jobId: 'offload_batch');
    if (mounted) {
      ref.invalidate(projectVideosProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Đã giải phóng SSD cho ${files.length} video an toàn!'), backgroundColor: const Color(0xFF10B981)),
      );
    }
  }

  void _handleBatchDelete(List<VideoFile> files) async {
    final ok = await ConfirmDialog.show(
      context,
      title: 'Xóa vĩnh viễn ${files.length} video?',
      message: 'Tất cả ${files.length} video và toàn bộ cache workspace liên quan sẽ bị xóa khỏi SSD.',
      isDestructive: true,
    );
    if (!ok) return;

    for (final f in files) {
      FileService.deleteVideoFile(f.fullPath);
    }
    ref.invalidate(projectVideosProvider);
    ref.read(selectedVideoProvider.notifier).state = null;
  }

  void _handleRenameFile(VideoFile file) {
    final controller = TextEditingController(text: file.basename);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: const BorderSide(color: AppColors.border)),
        title: const Text('Đổi Tên File', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
        content: TextField(
          controller: controller,
          autofocus: true,
          cursorColor: AppColors.primary,
          style: const TextStyle(color: Colors.white, fontSize: 12),
          decoration: InputDecoration(
            filled: true,
            fillColor: AppColors.surfaceDark,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: const BorderSide(color: AppColors.border, width: 0.8)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: const BorderSide(color: AppColors.border, width: 0.8)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: const BorderSide(color: AppColors.primary, width: 1.0)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy', style: TextStyle(color: AppColors.textSecondary))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: AppColors.primaryText),
            onPressed: () {
              final newName = controller.text.trim();
              if (newName.isNotEmpty && newName != file.basename) {
                FileService.renameVideoFile(file.fullPath, newName);
                ref.invalidate(projectVideosProvider);
              }
              Navigator.pop(ctx);
            },
            child: const Text('Đổi Tên', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  void _handleDeleteFile(VideoFile file) async {
    final ok = await ConfirmDialog.show(
      context,
      title: 'Xóa video?',
      message: 'Bạn có chắc chắn muốn xóa vĩnh viễn "${file.basename}" khỏi đĩa cứng?',
      isDestructive: true,
    );
    if (ok) {
      FileService.deleteVideoFile(file.fullPath);
      ref.invalidate(projectVideosProvider);
      if (ref.read(selectedVideoProvider)?.fullPath == file.fullPath) {
        ref.read(selectedVideoProvider.notifier).state = null;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedVideo = ref.watch(selectedVideoProvider);
    final projectVideosAsync = ref.watch(projectVideosProvider);
    final activeProject = ref.watch(activeProjectProvider);
    final projectsDir = ref.watch(projectsDirProvider);
    final runningPaths = ref.watch(runningPathsProvider);
    final logBuffer = ref.watch(logBufferProvider);

    final projectVideos = projectVideosAsync.value ?? {
      'srcFiles': <VideoFile>[],
      'cutFiles': <VideoFile>[],
      'mergeFiles': <VideoFile>[],
      'outputFiles': <VideoFile>[],
    };

    // Filter videos list based on tab
    List<VideoFile> displayVideos = [];
    final filter = widget.libraryFilter ?? 'all';
    if (filter == 'src') {
      displayVideos = projectVideos['srcFiles'] ?? [];
    } else if (filter == 'cut') {
      displayVideos = projectVideos['cutFiles'] ?? [];
    } else if (filter == 'merge') {
      displayVideos = projectVideos['mergeFiles'] ?? [];
    } else if (filter == 'output') {
      displayVideos = projectVideos['outputFiles'] ?? [];
    } else {
      displayVideos = [
        ...projectVideos['srcFiles'] ?? [],
        ...projectVideos['cutFiles'] ?? [],
        ...projectVideos['mergeFiles'] ?? [],
        ...projectVideos['outputFiles'] ?? [],
      ];
    }

    // Auto-select first video if none selected
    if (selectedVideo == null && displayVideos.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(selectedVideoProvider.notifier).state = displayVideos.first;
        _loadSubtitlesAndMetadata(displayVideos.first);
      });
    }

    final c = AppColors.of(context);

    return Scaffold(
      backgroundColor: c.background,
      body: Stack(
        children: [
          Column(
            children: [
              // ══════════════════════════════════════════════════════════════════════
              // ── TẦNG TRÊN (58%): Left 74% (Player + SubtitleInspector + Timeline) | Right 260px (PropertiesInspector) ──
              // ══════════════════════════════════════════════════════════════════════
              Expanded(
                flex: 58,
                child: Row(
                  children: [
                    // CỘT CHÍNH CANVAS (74%)
                    Expanded(
                      flex: 74,
                      child: Column(
                        children: [
                          // TOP ROW: Video Player (54%) + Subtitle Inspector (46%)
                          Expanded(
                            child: Row(
                              children: [
                                // 1. Video Player Container (54%)
                                Expanded(
                                  flex: 54,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: c.surfaceDark,
                                      border: Border(
                                        right: BorderSide(color: c.border),
                                      ),
                                    ),
                                    child: selectedVideo != null
                                        ? (!_isPlayerFullscreen
                                            ? VideoPlayerWidget(
                                                key: _playerKey,
                                                videoPath: selectedVideo.fullPath,
                                                isFullscreen: false,
                                                onToggleFullscreen: () => setState(() => _isPlayerFullscreen = true),
                                                onPositionChanged: (sec) => setState(() => _currentTime = sec),
                                                onDurationChanged: (dur) {
                                                  setState(() {
                                                    _duration = dur;
                                                    if (_endTime == 0 || _endTime > dur) {
                                                      _endTime = dur.clamp(0.0, 5.0);
                                                    }
                                                  });
                                                },
                                              )
                                            : Center(
                                                child: Text(
                                                  'Đang phát toàn màn hình...',
                                                  style: TextStyle(color: c.textMuted, fontSize: 12),
                                                ),
                                              ))
                                        : Center(
                                            child: Column(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                Icon(Icons.video_library_outlined, size: 48, color: c.textMuted),
                                                const SizedBox(height: 8),
                                                Text('Chưa chọn video nào', style: TextStyle(color: c.textSecondary, fontSize: 13)),
                                              ],
                                            ),
                                          ),
                                  ),
                                ),

                            // 2. Subtitle Inspector Panel (46%)
                            Expanded(
                              flex: 46,
                              child: SubtitleInspectorWidget(
                                subtitles: _subtitles,
                                currentTime: _currentTime,
                                onSubtitleChange: (subs) => setState(() {
                                  _subtitles = subs;
                                  _isSubModified = true;
                                }),
                                onSeekToSubtitle: (timeSec) => setState(() => _currentTime = timeSec),
                                onTranslateAll: _triggerTranslateAll,
                                onAutoSync: _saveSubtitlesAndCascadeResume,
                                onSaveSubtitles: _saveSubtitlesAndCascadeResume,
                                isSubModified: _isSubModified,
                                isProcessing: _isProcessing,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // CỘT PROPERTIES INSPECTOR (260px)
                Container(
                  width: 260,
                  decoration: BoxDecoration(
                    color: c.surface,
                    border: Border(
                      left: BorderSide(color: c.border),
                    ),
                  ),
                  child: PropertiesInspectorWidget(
                    videoFile: selectedVideo,
                    duration: _duration,
                    startTime: _startTime,
                    endTime: _endTime,
                    cutMode: 'keep',
                    onCutTrim: _executeCutTrim,
                    activeProject: activeProject,
                    projectsDir: projectsDir,
                    metaTitle: _metaTitle,
                    metaDesc: _metaDesc,
                    metaHashtags: _metaHashtags,
                    isProcessing: _isProcessing,
                  ),
                ),
              ],
            ),
          ),

          // ══════════════════════════════════════════════════════════════════════
          // ── TẦNG DƯỚI (42%): Bottom-Left 65% (AssetTable) | Bottom-Right 35% (ProcessLogs) ──
          // ══════════════════════════════════════════════════════════════════════
          Expanded(
            flex: 42,
            child: Row(
              children: [
                // 1. Asset Manager Table (65%)
                Expanded(
                  flex: 65,
                  child: Container(
                    decoration: BoxDecoration(
                      color: c.surface,
                      border: Border(
                        top: BorderSide(color: c.border),
                        right: BorderSide(color: c.border),
                      ),
                    ),
                    child: AssetTableWidget(
                      files: displayVideos,
                      selectedFile: selectedVideo,
                      onSelectFile: (file) {
                        ref.read(selectedVideoProvider.notifier).state = file;
                        _loadSubtitlesAndMetadata(file);
                      },
                      runningRelPaths: runningPaths,
                      onRefresh: () => ref.invalidate(projectVideosProvider),
                      onOpenTrimmer: (file) => _executeCutTrim(),
                      onDeleteFile: _handleDeleteFile,
                      onRenameFile: _handleRenameFile,
                      onBatchTranslateVoice: _handleBatchTranslateVoice,
                      onBatchTranslateSub: _handleBatchTranslateSub,
                      onBatchUploadCloud: _handleBatchUploadCloud,
                      onBatchSyncDown: _handleBatchSyncDown,
                      onBatchOffload: _handleBatchOffload,
                      onBatchDelete: _handleBatchDelete,
                    ),
                  ),
                ),

                // 2. Process Logs Console (35%)
                Expanded(
                  flex: 35,
                  child: Container(
                    decoration: BoxDecoration(
                      color: c.surfaceDark,
                      border: Border(
                        top: BorderSide(color: c.border),
                      ),
                    ),
                    child: ProcessLogsConsoleWidget(
                      logs: logBuffer,
                      isProcessRunning: _isProcessing || runningPaths.isNotEmpty,
                      onClearLogs: () => ref.read(logBufferProvider.notifier).clear(),
                      onStopProcess: _stopActiveProcess,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),

      // ── FULLSCREEN CINEMATIC PLAYER OVERLAY ──
      if (_isPlayerFullscreen && selectedVideo != null)
        Positioned.fill(
          child: VideoPlayerWidget(
            key: _playerKey,
            videoPath: selectedVideo.fullPath,
            isFullscreen: true,
            onToggleFullscreen: () => setState(() => _isPlayerFullscreen = false),
            onPositionChanged: (sec) => setState(() => _currentTime = sec),
            onDurationChanged: (dur) => setState(() => _duration = dur),
          ),
        ),
    ],
  ),
);
  }
}
