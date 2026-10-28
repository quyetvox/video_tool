import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as p;
import '../../../core/engine_resolver.dart';
import '../../../core/python_bridge.dart';
import '../../../core/providers.dart';
import '../models/tts_models.dart';

final ttsStudioProvider =
    StateNotifierProvider<TtsStudioController, TtsStudioState>((ref) {
  return TtsStudioController(ref);
});

class TtsStudioController extends StateNotifier<TtsStudioState> {
  final Ref? _ref;
  Player? _audioPlayer;
  StreamSubscription? _playerSub;

  TtsStudioController([this._ref]) : super(const TtsStudioState()) {
    _initPlayer();
  }

  void _initPlayer() {
    _audioPlayer = Player();
    _playerSub = _audioPlayer!.stream.completed.listen((completed) {
      if (completed) {
        if (state.currentlyPlayingSegmentId != null || state.isPlayingFull) {
          state = state.copyWith(
            clearPlayingSegment: true,
            isPlayingFull: false,
          );
        }
      }
    });
  }

  String _resolveToolScript() {
    final resolved = EngineResolver.resolveScript('tts_studio_tool.py');
    if (resolved != null && resolved.existsSync()) {
      return resolved.path;
    }
    final rootDir = PythonBridge.resolveRootDir();
    final candidates = [
      p.join(rootDir, 'py_engine', 'tts_studio_tool.py'),
      p.join(rootDir, 'py_engine', 'tts_studio_tool.pyc'),
      p.join(rootDir, 'tts_studio_tool.py'),
      p.join(rootDir, 'tts_studio_tool.pyc'),
    ];
    for (final c in candidates) {
      if (File(c).existsSync()) return c;
    }
    return p.join(rootDir, 'py_engine', 'tts_studio_tool.py');
  }

  Map<String, dynamic>? _parseJsonOutput(String stdout) {
    final trimmed = stdout.trim();
    if (trimmed.isEmpty) return null;

    // 1. Thử decode toàn bộ output trực tiếp
    try {
      final res = json.decode(trimmed);
      if (res is Map<String, dynamic>) return res;
    } catch (_) {}

    // 2. Trích xuất khối JSON lớn nhất { ... } trong stdout (loại bỏ warnings/noise)
    final startIdx = stdout.indexOf('{');
    final endIdx = stdout.lastIndexOf('}');
    if (startIdx != -1 && endIdx != -1 && endIdx > startIdx) {
      try {
        final jsonSub = stdout.substring(startIdx, endIdx + 1);
        final res = json.decode(jsonSub);
        if (res is Map<String, dynamic>) return res;
      } catch (_) {}
    }

    // 3. Quét từng dòng đơn lẻ từ dưới lên
    final lines = trimmed.split('\n');
    for (final line in lines.reversed) {
      final t = line.trim();
      if (t.startsWith('{') && t.endsWith('}')) {
        try {
          final res = json.decode(t);
          if (res is Map<String, dynamic>) return res;
        } catch (_) {}
      }
    }
    return null;
  }

  @override
  void dispose() {
    _playerSub?.cancel();
    _audioPlayer?.dispose();
    super.dispose();
  }

  void setRawScript(String text) {
    state = state.copyWith(rawScript: text);
  }

  void setDefaultVoice(String voice) {
    state = state.copyWith(defaultVoice: voice);
  }

  void setDefaultSpeed(double speed) {
    state = state.copyWith(defaultSpeed: double.parse(speed.toStringAsFixed(2)));
  }

  void setDefaultPitch(int pitch) {
    state = state.copyWith(defaultPitch: pitch);
  }

  void setPauseSec(double pause) {
    state = state.copyWith(pauseSec: double.parse(pause.toStringAsFixed(2)));
  }

  void toggleLockTimeline([bool? value]) {
    state = state.copyWith(isTimelineLocked: value ?? !state.isTimelineLocked);
  }

  /// Xóa sạch kịch bản và toàn bộ các phân đoạn, đưa màn hình về trạng thái mới
  void clearAll() {
    _audioPlayer?.stop();
    state = TtsStudioState(
      availableVoices: state.availableVoices,
      defaultVoice: state.defaultVoice,
      defaultSpeed: state.defaultSpeed,
      defaultPitch: state.defaultPitch,
      pauseSec: state.pauseSec,
      isTimelineLocked: false,
      statusMessage: 'Đã làm mới không gian làm việc.',
    );
  }

  /// Nạp mẫu kịch bản Tiếng Anh và tự động phân tách câu
  Future<void> loadSampleEnglishScript() async {
    const sample = '''Welcome to Sub-Video TTS Studio.
This new tool empowers you to generate crystal-clear voiceovers directly from your scripts.
You can choose from multiple British, American, and Australian neural voices with full speed control.
Every subtitle is automatically synchronized to the millisecond.
Give it a try and bring your stories to life!''';
    state = state.copyWith(
      rawScript: sample,
      defaultVoice: 'en-US-JennyNeural',
      defaultSpeed: 1.05,
    );
    await splitScript();
  }

  /// Nạp mẫu kịch bản Tiếng Việt và tự động phân tách câu
  Future<void> loadSampleVietnameseScript() async {
    const sample = '''Chào mừng bạn đến với phòng thu giọng đọc Sub-Video.
Công cụ mới này cho phép bạn tạo giọng thuyết minh chất lượng cao từ kịch bản văn bản một cách dễ dàng.
Bạn có thể nghe thử từng câu, điều chỉnh tốc độ đọc và tạo phụ đề tự động.
Chúc bạn tạo ra những video tuyệt vời cùng Sub-Video!''';
    state = state.copyWith(
      rawScript: sample,
      defaultVoice: 'vi-VN-HoaiMyNeural',
      defaultSpeed: 1.0,
    );
    await splitScript();
  }

  /// Nạp tệp kịch bản trực tiếp (.txt, .md) và phân tách kèm audio timings
  Future<void> importScriptFile(String filePath) async {
    final file = File(filePath);
    if (!file.existsSync()) {
      state = state.copyWith(statusMessage: 'Tệp không tồn tại: $filePath');
      return;
    }

    String content = '';
    try {
      content = await file.readAsString(encoding: utf8);
    } catch (_) {
      try {
        content = await file.readAsString(encoding: latin1);
      } catch (e) {
        state = state.copyWith(statusMessage: 'Không thể đọc tệp kịch bản: $e');
        return;
      }
    }

    state = state.copyWith(
      rawScript: content,
      isSplitting: true,
      statusMessage: 'Đang nạp và phân tích kịch bản: ${p.basename(filePath)}...',
    );

    try {
      final rootDir = PythonBridge.resolveRootDir();
      final pythonBin = PythonBridge.resolvePythonBin();
      final toolScript = _resolveToolScript();
      final env = PythonBridge.buildEnvironment(rootDir: rootDir, pythonBin: pythonBin);

      final res = await Process.run(
        pythonBin,
        [
          toolScript,
          '--action',
          'import_narration',
          '--input-json',
          filePath,
          '--speed',
          state.defaultSpeed.toString(),
          '--pause',
          state.pauseSec.toString(),
        ],
        environment: env,
        workingDirectory: rootDir,
      );

      final data = _parseJsonOutput(res.stdout as String);
      if (res.exitCode == 0 && data != null && data['success'] == true) {
        final rawSegs = (data['segments'] as List?) ?? [];
        final segItems = rawSegs.map((s) => TtsSegmentItem.fromJson(s as Map<String, dynamic>)).toList();
        final totalWords = segItems.fold<int>(0, (sum, item) => sum + item.wordCount);
        final hasExplicit = segItems.any((s) => s.startSec > 0 || s.endSec > 0);

        state = state.copyWith(
          rawScript: content,
          segments: segItems,
          isTimelineLocked: hasExplicit ? true : state.isTimelineLocked,
          isSplitting: false,
          statusMessage: 'Đã nhập thành công ${segItems.length} đoạn câu ($totalWords từ) từ ${p.basename(filePath)}.',
        );
        return;
      }

      state = state.copyWith(rawScript: content, isSplitting: false);
      await splitScript();
    } catch (e) {
      state = state.copyWith(
        rawScript: content,
        isSplitting: false,
        statusMessage: 'Đã nạp văn bản: $e',
      );
    }
  }

  /// Gọi Python để phân đoạn kịch bản thông minh (an toàn với kịch bản lớn qua file tạm)
  Future<void> splitScript() async {
    final script = state.rawScript.trim();
    if (script.isEmpty) {
      state = state.copyWith(statusMessage: 'Vui lòng nhập kịch bản trước khi phân tách!');
      return;
    }

    state = state.copyWith(isSplitting: true, statusMessage: 'Đang phân tách kịch bản...');

    File? tempFile;
    try {
      final rootDir = PythonBridge.resolveRootDir();
      final pythonBin = PythonBridge.resolvePythonBin();
      final toolScript = _resolveToolScript();
      final env = PythonBridge.buildEnvironment(rootDir: rootDir, pythonBin: pythonBin);

      // Ghi ra file tạm để tránh giới hạn kích thước tham số CLI đối với kịch bản lớn
      final tempDir = Directory.systemTemp;
      tempFile = File(p.join(tempDir.path, 'tts_script_${DateTime.now().millisecondsSinceEpoch}.txt'));
      await tempFile.writeAsString(script, encoding: utf8);

      final res = await Process.run(
        pythonBin,
        [
          toolScript,
          '--action',
          'split_script',
          '--input-json',
          tempFile.path,
          '--speed',
          state.defaultSpeed.toString(),
          '--pause',
          state.pauseSec.toString(),
        ],
        environment: env,
        workingDirectory: rootDir,
      );

      final data = _parseJsonOutput(res.stdout as String);
      if (res.exitCode == 0 && data != null && data['success'] == true) {
        final rawSegs = (data['segments'] as List?) ?? [];
        final segItems = rawSegs.map((s) => TtsSegmentItem.fromJson(s as Map<String, dynamic>)).toList();
        final hasExplicit = segItems.any((s) => s.startSec > 0 || s.endSec > 0);

        state = state.copyWith(
          segments: segItems,
          isTimelineLocked: hasExplicit ? true : state.isTimelineLocked,
          isSplitting: false,
          statusMessage: 'Đã phân tách thành công ${segItems.length} đoạn kịch bản.',
        );
        return;
      }

      final errorMsg = data?['error']?.toString() ??
          (res.stderr.toString().trim().isNotEmpty ? res.stderr.toString().trim() : 'Lỗi phân tách không xác định');

      state = state.copyWith(
        isSplitting: false,
        statusMessage: 'Lỗi phân tách: $errorMsg',
      );
    } catch (e) {
      state = state.copyWith(
        isSplitting: false,
        statusMessage: 'Lỗi ngoại lệ khi phân tách: $e',
      );
    } finally {
      if (tempFile != null && tempFile.existsSync()) {
        try {
          tempFile.deleteSync();
        } catch (_) {}
      }
    }
  }

  void updateSegmentText(int id, String text) {
    final updated = state.segments.map((seg) {
      if (seg.id == id) {
        return seg.copyWith(text: text);
      }
      return seg;
    }).toList();
    state = state.copyWith(segments: updated);
  }

  void updateSegmentVoice(int id, String? voice) {
    final updated = state.segments.map((seg) {
      if (seg.id == id) {
        return seg.copyWith(voice: voice, clearVoice: voice == null);
      }
      return seg;
    }).toList();
    state = state.copyWith(segments: updated);
  }

  void updateSegmentSpeed(int id, double? speed) {
    final updated = state.segments.map((seg) {
      if (seg.id == id) {
        return seg.copyWith(
          speed: speed != null ? double.parse(speed.toStringAsFixed(2)) : null,
          clearSpeed: speed == null,
        );
      }
      return seg;
    }).toList();
    state = state.copyWith(segments: updated);
  }

  void deleteSegment(int id) {
    final updated = state.segments.where((s) => s.id != id).toList();
    state = state.copyWith(segments: updated);
  }

  void addSegmentBelow(int id) {
    final idx = state.segments.indexWhere((s) => s.id == id);
    if (idx == -1) return;

    final newId = state.segments.fold<int>(0, (max, s) => s.id > max ? s.id : max) + 1;
    final newSegment = TtsSegmentItem(id: newId, text: '');

    final updated = List<TtsSegmentItem>.from(state.segments);
    updated.insert(idx + 1, newSegment);
    state = state.copyWith(segments: updated);
  }

  /// Nghe thử âm thanh của một phân đoạn riêng lẻ
  Future<void> previewSegment(int id) async {
    final segIdx = state.segments.indexWhere((s) => s.id == id);
    if (segIdx == -1) return;
    final seg = state.segments[segIdx];

    if (seg.text.trim().isEmpty) {
      state = state.copyWith(statusMessage: 'Câu #$id chưa có nội dung!');
      return;
    }

    // Nếu đang phát chính câu này thì bấm lần nữa sẽ dừng
    if (state.currentlyPlayingSegmentId == id && _audioPlayer != null) {
      await _audioPlayer!.stop();
      state = state.copyWith(clearPlayingSegment: true);
      return;
    }

    await _audioPlayer?.stop();

    // Cập nhật trạng thái đang sinh audio
    final updatedLoading = List<TtsSegmentItem>.from(state.segments);
    updatedLoading[segIdx] = seg.copyWith(isSynthesizing: true);
    state = state.copyWith(
      segments: updatedLoading,
      currentlyPlayingSegmentId: id,
      statusMessage: 'Đang tạo âm thanh cho câu #$id...',
    );

    try {
      final rootDir = PythonBridge.resolveRootDir();
      final pythonBin = PythonBridge.resolvePythonBin();
      final toolScript = _resolveToolScript();
      final env = PythonBridge.buildEnvironment(rootDir: rootDir, pythonBin: pythonBin);

      final voice = seg.voice ?? state.defaultVoice;
      final baseSpeed = seg.speed ?? state.defaultSpeed;
      final pitch = seg.pitch ?? state.defaultPitch;

      double appliedSpeed = baseSpeed;
      if (state.isTimelineLocked && seg.endSec > seg.startSec) {
        final slotDur = seg.endSec - seg.startSec;
        final words = seg.text.trim().isEmpty ? 0 : seg.text.trim().split(RegExp(r'\s+')).length;
        final estNatDur = words > 0 ? (words / (140.0 / 60.0)) : 0.5;
        final estDurAtBase = estNatDur / baseSpeed;
        if (estDurAtBase > slotDur + 0.05) {
          appliedSpeed = estNatDur / slotDur;
        }
      }

      final res = await Process.run(
        pythonBin,
        [
          toolScript,
          '--action',
          'preview_segment',
          '--text',
          seg.text,
          '--voice',
          voice,
          '--speed',
          appliedSpeed.toStringAsFixed(2),
          '--pitch',
          pitch.toString(),
        ],
        environment: env,
        workingDirectory: rootDir,
      );

      final data = _parseJsonOutput(res.stdout as String);
      if (res.exitCode == 0 && data != null && data['success'] == true) {
        final audioPath = data['audio_path'] as String;
        final duration = (data['duration'] as num?)?.toDouble() ?? 0.0;

        final updatedSuccess = List<TtsSegmentItem>.from(state.segments);
        updatedSuccess[segIdx] = seg.copyWith(
          isSynthesizing: false,
          audioPath: audioPath,
          duration: duration,
        );

        state = state.copyWith(
          segments: updatedSuccess,
          statusMessage: 'Đang phát câu #$id (${duration.toStringAsFixed(1)}s)...',
        );

        if (File(audioPath).existsSync()) {
          _audioPlayer ??= Player();
          await _audioPlayer!.setVolume(100.0);
          await _audioPlayer!.open(Media(audioPath), play: true);
        }
        return;
      }

      final errorMsg = data?['error']?.toString() ??
          (res.stderr.toString().trim().isNotEmpty ? res.stderr.toString().trim() : 'Không thể tạo âm thanh');

      final updatedFail = List<TtsSegmentItem>.from(state.segments);
      updatedFail[segIdx] = seg.copyWith(isSynthesizing: false);
      state = state.copyWith(
        segments: updatedFail,
        clearPlayingSegment: true,
        statusMessage: 'Lỗi phát thử câu #$id: $errorMsg',
      );
    } catch (e) {
      final updatedFail = List<TtsSegmentItem>.from(state.segments);
      updatedFail[segIdx] = seg.copyWith(isSynthesizing: false);
      state = state.copyWith(
        segments: updatedFail,
        clearPlayingSegment: true,
        statusMessage: 'Ngoại lệ phát thử câu #$id: $e',
      );
    }
  }

  /// Nghe thử nhanh 1 giọng đọc mẫu trực tiếp
  Future<void> previewVoiceSample(String voiceId) async {
    await _audioPlayer?.stop();
    state = state.copyWith(
      clearPlayingSegment: true,
      isPlayingFull: false,
      statusMessage: 'Đang tạo âm thanh mẫu cho giọng $voiceId...',
    );

    try {
      final rootDir = PythonBridge.resolveRootDir();
      final pythonBin = PythonBridge.resolvePythonBin();
      final toolScript = _resolveToolScript();
      final env = PythonBridge.buildEnvironment(rootDir: rootDir, pythonBin: pythonBin);

      final isVi = voiceId.toLowerCase().startsWith('vi-') || voiceId.toLowerCase().contains('banmai');
      final sampleText = isVi
          ? 'Xin chào, đây là giọng đọc thử nghiệm của Sub-Video.'
          : 'Hello, this is a sample of this voice on Sub-Video.';

      final res = await Process.run(
        pythonBin,
        [
          toolScript,
          '--action',
          'preview_segment',
          '--text',
          sampleText,
          '--voice',
          voiceId,
          '--speed',
          state.defaultSpeed.toStringAsFixed(2),
          '--pitch',
          state.defaultPitch.toString(),
        ],
        environment: env,
        workingDirectory: rootDir,
      );

      final data = _parseJsonOutput(res.stdout as String);
      if (res.exitCode == 0 && data != null && data['success'] == true) {
        final audioPath = data['audio_path'] as String;
        state = state.copyWith(statusMessage: 'Đang phát mẫu giọng: $voiceId');
        if (File(audioPath).existsSync()) {
          _audioPlayer ??= Player();
          await _audioPlayer!.setVolume(100.0);
          await _audioPlayer!.open(Media(audioPath), play: true);
        }
      } else {
        final err = data?['error']?.toString() ?? 'Lỗi không xác định';
        state = state.copyWith(statusMessage: 'Lỗi phát mẫu giọng: $err');
      }
    } catch (e) {
      state = state.copyWith(statusMessage: 'Lỗi phát mẫu giọng: $e');
    }
  }

  Future<void> stopAudio() async {
    await _audioPlayer?.stop();
    state = state.copyWith(
      clearPlayingSegment: true,
      isPlayingFull: false,
    );
  }

  /// Sinh trọn gói Audio tổng + Phụ đề SRT/VTT
  Future<bool> renderFull({String? customAudioPath, String? customSrtPath}) async {
    if (state.segments.isEmpty) {
      state = state.copyWith(statusMessage: 'Chưa có phân đoạn nào để xuất audio!');
      return false;
    }

    state = state.copyWith(
      isRenderingFull: true,
      statusMessage: 'Đang sinh và ghép nối toàn bộ âm thanh...',
    );

    try {
      final rootDir = PythonBridge.resolveRootDir();
      final pythonBin = PythonBridge.resolvePythonBin();
      final toolScript = _resolveToolScript();
      final env = PythonBridge.buildEnvironment(rootDir: rootDir, pythonBin: pythonBin);

      final tempDir = Directory(p.join(Directory.systemTemp.path, 'subvideo_tts_render_${DateTime.now().millisecondsSinceEpoch}'));
      if (!tempDir.existsSync()) tempDir.createSync(recursive: true);

      final outAudio = customAudioPath ?? p.join(tempDir.path, 'speech_full.mp3');
      final outSrt = customSrtPath ?? p.join(tempDir.path, 'speech_full.srt');
      final outVtt = p.setExtension(outSrt, '.vtt');

      final manifestData = {
        'default_voice': state.defaultVoice,
        'default_speed': state.defaultSpeed,
        'default_pitch': state.defaultPitch,
        'pause_sec': state.pauseSec,
        'lock_timeline': state.isTimelineLocked,
        'output_audio': outAudio,
        'output_srt': outSrt,
        'output_vtt': outVtt,
        'segments': state.segments.map((s) => s.toJson()).toList(),
      };

      final manifestFile = File(p.join(tempDir.path, 'render_manifest.json'));
      manifestFile.writeAsStringSync(json.encode(manifestData));

      final res = await Process.run(
        pythonBin,
        [
          toolScript,
          '--action',
          'render_full',
          '--input-json',
          manifestFile.path,
          '--output-audio',
          outAudio,
          '--output-srt',
          outSrt,
          '--output-vtt',
          outVtt,
        ],
        environment: env,
        workingDirectory: rootDir,
      );

      final data = _parseJsonOutput(res.stdout as String);
      if (res.exitCode == 0 && data != null && data['success'] == true) {
        final totalDur = (data['total_duration'] as num?)?.toDouble() ?? 0.0;
        final rawSegs = (data['segments'] as List?) ?? [];
        final updatedSegs = rawSegs.isNotEmpty
            ? rawSegs.map((s) => TtsSegmentItem.fromJson(s as Map<String, dynamic>)).toList()
            : state.segments;

        state = state.copyWith(
          isRenderingFull: false,
          fullAudioPath: outAudio,
          fullSrtPath: outSrt,
          totalDuration: totalDur,
          segments: updatedSegs,
          statusMessage: 'Đã xuất thành công audio (${totalDur.toStringAsFixed(1)}s) và phụ đề SRT!',
        );
        return true;
      }

      final errorMsg = data?['error']?.toString() ??
          (res.stderr.toString().trim().isNotEmpty ? res.stderr.toString().trim() : 'Lỗi xuất audio');

      state = state.copyWith(
        isRenderingFull: false,
        statusMessage: 'Lỗi xuất audio: $errorMsg',
      );
      return false;
    } catch (e) {
      state = state.copyWith(
        isRenderingFull: false,
        statusMessage: 'Ngoại lệ khi xuất audio: $e',
      );
      return false;
    }
  }

  /// Phát thử audio toàn bài đã ghép
  Future<void> togglePlayFullAudio() async {
    if (state.isPlayingFull) {
      await _audioPlayer?.stop();
      state = state.copyWith(isPlayingFull: false);
      return;
    }

    if (state.fullAudioPath == null || !File(state.fullAudioPath!).existsSync()) {
      // Nếu chưa render, tự động kích hoạt render trước
      final ok = await renderFull();
      if (!ok) return;
    }

    if (state.fullAudioPath != null && File(state.fullAudioPath!).existsSync()) {
      await _audioPlayer?.stop();
      state = state.copyWith(
        isPlayingFull: true,
        clearPlayingSegment: true,
        statusMessage: 'Đang phát toàn bộ bài đọc...',
      );
      _audioPlayer ??= Player();
      await _audioPlayer!.setVolume(100.0);
      await _audioPlayer!.open(Media(state.fullAudioPath!), play: true);
    }
  }

  /// Chuyển file audio và phụ đề đã tạo vào Project Workspace để dùng trong Video Studio
  Future<String?> exportToProjectWorkspace() async {
    if (state.fullAudioPath == null || !File(state.fullAudioPath!).existsSync()) {
      final ok = await renderFull();
      if (!ok) return null;
    }

    if (_ref == null) return null;
    final activeProject = _ref.read(activeProjectProvider);
    final projectsDir = _ref.read(projectsDirProvider);

    if (activeProject == null || activeProject.isEmpty) {
      return null;
    }

    final targetDir = Directory(p.join(projectsDir, activeProject, 'src'));
    if (!targetDir.existsSync()) targetDir.createSync(recursive: true);

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final destAudioPath = p.join(targetDir.path, 'tts_voiceover_$timestamp.mp3');
    final destSrtPath = p.join(targetDir.path, 'tts_voiceover_$timestamp.srt');

    File(state.fullAudioPath!).copySync(destAudioPath);
    if (state.fullSrtPath != null && File(state.fullSrtPath!).existsSync()) {
      File(state.fullSrtPath!).copySync(destSrtPath);
    }

    _ref.invalidate(projectVideosProvider);
    state = state.copyWith(
      statusMessage: 'Đã lưu file âm thanh vào thư mục src của dự án: $activeProject',
    );
    return destAudioPath;
  }
}
