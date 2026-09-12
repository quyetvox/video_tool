import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
import '../widgets/resizable_collapsible_panel.dart';
import '../widgets/app_kit.dart';
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

  // Long Video Flow State
  StreamSubscription<Map<String, dynamic>>? _longVideoSub;
  Set<String> _autoSelectedChunkPaths = {};

  @override
  void initState() {
    super.initState();
    _longVideoSub = EngineBridge.longVideoEvents.listen((evt) {
      final type = evt['type']?.toString();
      if (type == 'long_video_initialized') {
        final details = evt['chunk_details'] as List?;
        final paths = <String>{};
        String? firstChunkPath;
        if (details != null) {
          for (final c in details) {
            final f = c['raw_chunk_file']?.toString();
            if (f != null && f.isNotEmpty) {
              paths.add(f);
              firstChunkPath ??= f;
            }
          }
        }
        if (mounted) {
          if (paths.isNotEmpty) {
            setState(() {
              _autoSelectedChunkPaths = paths;
            });
          }
          ref.invalidate(projectVideosProvider);
          if (firstChunkPath != null) {
            final stem = p.basenameWithoutExtension(firstChunkPath);
            ref.read(runningPathsProvider.notifier).update((set) => {...set, firstChunkPath!, stem});
          }
        }
      } else if (type == 'long_video_progress' || (type == 'progress' && evt.containsKey('chunk_id'))) {
        final rawChunk = evt['raw_chunk_file']?.toString();
        final currentStep = evt['current_step']?.toString();
        if (rawChunk != null && rawChunk.isNotEmpty) {
          final stem = p.basenameWithoutExtension(rawChunk);
          if (currentStep == 'chunk_completed') {
            ref.invalidate(projectVideosProvider);
            ref.read(runningPathsProvider.notifier).update((set) => set.where((p) => p != rawChunk && p != stem).toSet());
          } else {
            ref.read(runningPathsProvider.notifier).update((set) => {...set, rawChunk, stem});
          }
        }
      } else if (type == 'long_video_completed') {
        if (mounted) {
          setState(() {
            _autoSelectedChunkPaths = {};
          });
          ref.read(runningPathsProvider.notifier).state = {};
          ref.invalidate(projectVideosProvider);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('🎉 Video dài đã được dịch hoàn tất và ghép nối thành công!'),
              backgroundColor: AppColors.statusCompleted,
              duration: Duration(seconds: 4),
            ),
          );
        }
      }
    });
  }

  @override
  void dispose() {
    _longVideoSub?.cancel();
    super.dispose();
  }

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

    // Check if this video is a master video with chunks
    final manifestFile = File(p.join(projectsDir, activeProject, 'workspace', 'chunks', selectedVideo.stem, 'manifest.json'));
    if (manifestFile.existsSync()) {
      try {
        final manifestRaw = jsonDecode(manifestFile.readAsStringSync()) as Map<String, dynamic>;
        final chunks = manifestRaw['chunks'] as List<dynamic>? ?? [];
        if (chunks.isNotEmpty) {
          // 1. Save master unified s08c_timing.json
          final masterJobDir = Directory(p.join(projectsDir, activeProject, 'workspace', selectedVideo.jobId));
          if (!masterJobDir.existsSync()) masterJobDir.createSync(recursive: true);
          final list = _subtitles.map((s) => s.toJson()).toList();
          final jsonStr = const JsonEncoder.withIndent('  ').convert(list);
          File(p.join(masterJobDir.path, 's08c_timing.json')).writeAsStringSync(jsonStr);

          // 2. Map edited subtitles back to affected chunks
          final affectedChunks = <Map<String, dynamic>>[];
          for (final chunk in chunks) {
            final startSec = (chunk['start_sec'] as num?)?.toDouble() ?? 0.0;
            final endSec = (chunk['end_sec'] as num?)?.toDouble() ?? 0.0;
            final rawChunkFile = chunk['raw_chunk_file']?.toString() ?? '';
            final chunkStem = p.basenameWithoutExtension(rawChunkFile);
            final chunkJobId = chunk['job_id']?.toString() ?? 'job_$chunkStem';

            // Filter subtitles belonging to this chunk
            final chunkSubs = <Map<String, dynamic>>[];
            for (final sub in _subtitles) {
              if (sub.start >= startSec - 0.05 && sub.start < endSec) {
                final localJson = sub.toJson();
                localJson['start'] = (sub.start - startSec).clamp(0.0, endSec - startSec);
                localJson['end'] = (sub.end - startSec).clamp(0.0, endSec - startSec);
                chunkSubs.add(localJson);
              }
            }

            final chunkJobDir = Directory(p.join(projectsDir, activeProject, 'workspace', chunkJobId));
            if (!chunkJobDir.existsSync()) chunkJobDir.createSync(recursive: true);
            final chunkTimingFile = File(p.join(chunkJobDir.path, 's08c_timing.json'));

            String oldContent = '';
            if (chunkTimingFile.existsSync()) {
              oldContent = chunkTimingFile.readAsStringSync();
            }
            final newChunkJsonStr = const JsonEncoder.withIndent('  ').convert(chunkSubs);
            if (oldContent != newChunkJsonStr) {
              chunkTimingFile.writeAsStringSync(newChunkJsonStr);
              // Invalidate downstream render steps for this chunk
              for (final stepDone in ['s09_subtitle_gen.done', 's11_subtitle_render.done', 's12_tts.done', 's13_audio_mix.done', 's14_encode.done']) {
                final f = File(p.join(chunkJobDir.path, stepDone));
                if (f.existsSync()) f.deleteSync();
              }
              affectedChunks.add({
                'chunk': chunk,
                'chunkFile': rawChunkFile,
                'chunkJobId': chunkJobId,
                'chunkStem': chunkStem,
              });
            }
          }

          setState(() => _isSubModified = false);

          if (affectedChunks.isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('⚡ Phụ đề không có thay đổi so với các đoạn con.'),
                duration: Duration(seconds: 2),
              ),
            );
            return;
          }

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('💾 Đã cập nhật phụ đề cho ${affectedChunks.length} đoạn con. Đang re-render và tự động ghép nối...'),
              backgroundColor: AppColors.statusCompleted,
            ),
          );

          _runCascadeResumeForChunks(affectedChunks, selectedVideo.fullPath, activeProject);
          return;
        }
      } catch (e) {
        debugPrint('Error parsing master manifest: $e');
      }
    }

    // Standard video or single child chunk
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
      _checkAndAutoMergeParentVideo(selectedVideo, activeProject, projectsDir);
    });
  }

  Future<void> _runCascadeResumeForChunks(
    List<Map<String, dynamic>> affectedChunks,
    String masterVideoPath,
    String activeProject,
  ) async {
    for (final item in affectedChunks) {
      final chunkFile = item['chunkFile'] as String;
      final chunkStem = item['chunkStem'] as String;
      final chunkJobId = 'resume_sub_$chunkStem';
      ref.read(runningPathsProvider.notifier).update((set) => {...set, chunkFile, chunkStem, chunkJobId});
      await EngineBridge.resumeJob(
        chunkFile,
        projectId: activeProject,
        jobId: chunkJobId,
      );
      ref.read(runningPathsProvider.notifier).update((set) => set.where((p) => !p.contains(chunkStem) && !p.contains(chunkJobId)).toSet());
    }

    // Now re-merge master video
    final res = await EngineBridge.mergeLongVideo(masterVideoPath, projectId: activeProject);
    if (mounted) {
      ref.invalidate(projectVideosProvider);
      if (res.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🎉 Đã hoàn tất re-render và ghép nối lại video tổng thành công!'),
            backgroundColor: AppColors.statusCompleted,
            duration: Duration(seconds: 4),
          ),
        );
      }
    }
  }

  void _checkAndAutoMergeParentVideo(VideoFile childVideo, String activeProject, String projectsDir) {
    final match = RegExp(r'^(.*)_part_\d+$').firstMatch(childVideo.stem);
    if (match == null) return;
    final parentStem = match.group(1)!;
    final manifestFile = File(p.join(projectsDir, activeProject, 'workspace', 'chunks', parentStem, 'manifest.json'));
    if (!manifestFile.existsSync()) return;

    try {
      final raw = jsonDecode(manifestFile.readAsStringSync()) as Map<String, dynamic>;
      final chunks = raw['chunks'] as List<dynamic>? ?? [];
      final outputDir = Directory(p.join(projectsDir, activeProject, 'output'));
      bool allPartsExist = true;
      for (final c in chunks) {
        final outF = c['output_file']?.toString() ?? '';
        final outName = p.basename(outF);
        if (!File(p.join(outputDir.path, outName)).existsSync()) {
          allPartsExist = false;
          break;
        }
      }
      if (allPartsExist) {
        final parentVideoPath = raw['source_video_path']?.toString() ?? p.join(projectsDir, activeProject, 'src', '$parentStem.mp4');
        EngineBridge.mergeLongVideo(parentVideoPath, projectId: activeProject).then((res) {
          if (mounted && res.success) {
            ref.invalidate(projectVideosProvider);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('🎉 Đã tự động cập nhật và ghép nối lại video tổng: $parentStem'),
                backgroundColor: AppColors.statusCompleted,
                duration: const Duration(seconds: 3),
              ),
            );
          }
        });
      }
    } catch (_) {}
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
    final config = ref.read(configProvider);
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
      longVideo: config.longVideoEnabled,
      chunkDurationMin: config.longVideoChunkDurationMin,
    ).then((res) {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _activeJobId = '';
          _autoSelectedChunkPaths = {};
        });
        ref.read(runningPathsProvider.notifier).update((set) => set.where((p) => !p.contains(selectedVideo.stem) && !p.contains(jobId)).toSet());
        ref.invalidate(projectVideosProvider);
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          config.longVideoEnabled
              ? '⚡ Bắt đầu Chế Độ Video Dài: Cắt đoạn ${config.longVideoChunkDurationMin.toStringAsFixed(1)} phút -> Dịch tuần tự -> Tự động ghép nối'
              : '🚀 Đã bắt đầu dịch toàn bộ video: ${selectedVideo.basename}',
        ),
        duration: const Duration(seconds: 3),
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
      _autoSelectedChunkPaths = {};
    });
    ref.read(runningPathsProvider.notifier).state = {};
  }

  // ── BATCH ACTIONS IMPLEMENTATION ──

  Future<void> _performBatchCooldown({
    required bool isVoice,
    required VideoFile currentFile,
    required VideoFile nextFile,
  }) async {
    final config = ref.read(configProvider);
    final cooldownSetting = config.batchCooldownSec.trim().toLowerCase();

    int cooldownSec;
    if (cooldownSetting.isEmpty || cooldownSetting == 'auto') {
      if (!isVoice) {
        cooldownSec = 2; // Dịch sub nhẹ nhàng
      } else {
        // Dịch giọng đọc: nếu file > 50MB hoặc video dài thì 8s, ngược lại 5s
        if (currentFile.sizeBytes > 50 * 1024 * 1024 ||
            (config.longVideoEnabled && currentFile.sizeBytes > 30 * 1024 * 1024)) {
          cooldownSec = 8;
        } else {
          cooldownSec = 5;
        }
      }
    } else {
      cooldownSec = int.tryParse(cooldownSetting) ?? (isVoice ? 5 : 2);
    }

    if (cooldownSec <= 0) return;

    for (int sec = cooldownSec; sec > 0; sec--) {
      if (!mounted || !_isProcessing) break;
      final msg = '⏳ [Smart Cooldown] Đang hạ nhiệt CPU (${sec}s) trước khi dịch: ${nextFile.name}';
      PythonBridge.addLog('cooldown', 'PROGRESS', msg);
      await Future.delayed(const Duration(seconds: 1));
    }
  }

  void _handleBatchTranslateVoice(List<VideoFile> files) async {
    final config = ref.read(configProvider);
    for (int i = 0; i < files.length; i++) {
      if (!_isProcessing && i > 0) break;
      final f = files[i];
      final jobId = 'batch_voice_${f.stem}';
      setState(() {
        _isProcessing = true;
        _activeJobId = jobId;
      });
      ref.read(runningPathsProvider.notifier).update((set) => {...set, f.relPath, f.stem, jobId});
      await EngineBridge.translateVideo(
        f.fullPath,
        voice: true,
        jobId: jobId,
        longVideo: config.longVideoEnabled,
        chunkDurationMin: config.longVideoChunkDurationMin,
      );
      ref.read(runningPathsProvider.notifier).update((set) => set.where((p) => !p.contains(f.stem) && !p.contains(jobId)).toSet());

      if (i < files.length - 1 && _isProcessing) {
        await _performBatchCooldown(
          isVoice: true,
          currentFile: f,
          nextFile: files[i + 1],
        );
      }
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
    for (int i = 0; i < files.length; i++) {
      if (!_isProcessing && i > 0) break;
      final f = files[i];
      final jobId = 'batch_sub_${f.stem}';
      setState(() {
        _isProcessing = true;
        _activeJobId = jobId;
      });
      ref.read(runningPathsProvider.notifier).update((set) => {...set, f.relPath, f.stem, jobId});
      await EngineBridge.translateVideo(f.fullPath, ocrOnly: true, jobId: jobId);
      ref.read(runningPathsProvider.notifier).update((set) => set.where((p) => !p.contains(f.stem) && !p.contains(jobId)).toSet());

      if (i < files.length - 1 && _isProcessing) {
        await _performBatchCooldown(
          isVoice: false,
          currentFile: f,
          nextFile: files[i + 1],
        );
      }
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
        content: AppTextField(
          controller: controller,
          autofocus: true,
          height: 34,
          hint: 'Nhập tên video mới...',
        ),
        actions: [
          AppButton.ghost(
            label: 'Hủy',
            onPressed: () => Navigator.pop(ctx),
          ),
          const SizedBox(width: 6),
          AppButton.primary(
            label: 'Đổi Tên',
            onPressed: () {
              final newName = controller.text.trim();
              if (newName.isNotEmpty && newName != file.basename) {
                FileService.renameVideoFile(file.fullPath, newName);
                ref.invalidate(projectVideosProvider);
              }
              Navigator.pop(ctx);
            },
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
              // ── TOÀN BỘ KHÔNG GIAN: TẦNG TRÊN & TẦNG DƯỚI (VERTICAL RESIZABLE) ──
              // ══════════════════════════════════════════════════════════════════════
              Expanded(
                child: ResizableCollapsiblePanel(
                  side: PanelSide.bottom,
                  initialHeight: 280.0,
                  minHeight: 130.0,
                  maxHeight: 600.0,
                  collapseTooltip: 'Thu gọn danh sách video & nhật ký',
                  expandTooltip: 'Mở rộng danh sách video & nhật ký',
                  panel: ResizableCollapsiblePanel(
                    side: PanelSide.right,
                    initialWidth: 420.0,
                    minWidth: 260.0,
                    maxWidth: 750.0,
                    collapseTooltip: 'Thu gọn nhật ký',
                    expandTooltip: 'Mở rộng nhật ký',
                    panel: Container(
                      decoration: BoxDecoration(
                        color: c.surfaceDark,
                        border: Border(
                          top: BorderSide(color: c.border),
                          left: BorderSide(color: c.border),
                        ),
                      ),
                      child: ProcessLogsConsoleWidget(
                        logs: logBuffer,
                        isProcessRunning: _isProcessing || runningPaths.isNotEmpty,
                        onClearLogs: () => ref.read(logBufferProvider.notifier).clear(),
                        onStopProcess: _stopActiveProcess,
                      ),
                    ),
                    child: Container(
                      decoration: BoxDecoration(
                        color: c.surface,
                        border: Border(
                          top: BorderSide(color: c.border),
                        ),
                      ),
                      child: AssetTableWidget(
                        files: displayVideos,
                        selectedFile: selectedVideo,
                        onSelectFile: (file) {
                          ref.read(selectedVideoProvider.notifier).state = file;
                          _loadSubtitlesAndMetadata(file);
                        },
                        externalSelectedPaths: _autoSelectedChunkPaths,
                        onSelectionChanged: (paths) {
                          setState(() => _autoSelectedChunkPaths = paths);
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
