import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import '../models/studio_state.dart';
import '../models/video_file.dart';
import '../utils/time_format_utils.dart';
import 'python_bridge.dart';

class StudioExportResult {
  final bool success;
  final String output;
  final String? outputPath;

  const StudioExportResult({
    required this.success,
    required this.output,
    this.outputPath,
  });
}

class StudioExportService {
  /// Ensures standard directories exist: cut/, merge/, output/
  static Future<Map<String, Directory>> ensureDirectories(String projectDir) async {
    final cutDir = Directory(p.join(projectDir, 'cut'));
    final mergeDir = Directory(p.join(projectDir, 'merge'));
    final outDir = Directory(p.join(projectDir, 'output'));

    if (!await cutDir.exists()) await cutDir.create(recursive: true);
    if (!await mergeDir.exists()) await mergeDir.create(recursive: true);
    if (!await outDir.exists()) await outDir.create(recursive: true);

    return {
      'cut': cutDir,
      'merge': mergeDir,
      'output': outDir,
    };
  }

  /// Export Split Segments -> saves to resources/<project>/cut/part_XX_<stem>.mp4
  static Future<StudioExportResult> exportSplitSegments({
    required VideoFile video,
    required List<SplitSegment> splitSegments,
    required String projectDir,
  }) async {
    final dirs = await ensureDirectories(projectDir);
    final cutDir = dirs['cut']!;

    final results = <String>[];
    for (int i = 0; i < splitSegments.length; i++) {
      final seg = splitSegments[i];
      final partIndex = (i + 1).toString().padLeft(2, '0');
      final targetFilename = 'part_${partIndex}_${video.stem}.mp4';
      final targetPath = p.join(cutDir.path, targetFilename);

      final startSec = seg.start.toStringAsFixed(3);
      final endSec = seg.end.toStringAsFixed(3);

      final args = [
        video.fullPath,
        '-s',
        startSec,
        '-e',
        endSec,
        '-o',
        targetPath,
        '--overwrite',
      ];

      final res = await PythonBridge.runScript(
        'trim.py',
        args,
        jobId: 'studio_split_${partIndex}_${video.stem}',
      );

      if (!res.success) {
        final accurateArgs = [
          video.fullPath,
          '-s',
          startSec,
          '-e',
          endSec,
          '-o',
          targetPath,
          '--accurate',
          '--overwrite',
        ];
        await PythonBridge.runScript('trim.py', accurateArgs);
      }
      results.add(targetPath);
    }

    return StudioExportResult(
      success: true,
      output: 'Đã xuất ${splitSegments.length} phân đoạn vào thư mục cut/',
      outputPath: cutDir.path,
    );
  }

  /// Export Cut Video -> saves to cut/<stem>_cut.mp4 or overwrites src/
  static Future<StudioExportResult> exportCutVideo({
    required VideoFile video,
    required List<CutSegment> cutSegments,
    required String projectDir,
    required bool overwriteOriginal,
  }) async {
    final dirs = await ensureDirectories(projectDir);
    final cutDir = dirs['cut']!;

    final removeArgs = cutSegments.map((r) {
      final s = TimeFormatUtils.formatSubtitleTime(r.start).replaceAll(',', '.');
      final e = TimeFormatUtils.formatSubtitleTime(r.end).replaceAll(',', '.');
      return '$s-$e';
    }).toList();

    String targetOut;
    if (overwriteOriginal) {
      targetOut = video.fullPath;
    } else {
      targetOut = p.join(cutDir.path, '${video.stem}_cut.mp4');
    }

    final args = [
      video.fullPath,
      '--remove',
      ...removeArgs,
      '--output',
      targetOut,
    ];

    if (overwriteOriginal) {
      args.add('--overwrite');
    }

    final res = await PythonBridge.runScript(
      'concat.py',
      args,
      jobId: 'studio_cut_${video.stem}',
    );

    return StudioExportResult(
      success: res.success,
      output: res.output,
      outputPath: targetOut,
    );
  }

  static String _ensureMp4Extension(String name) {
    var trimmed = name.trim();
    if (!trimmed.toLowerCase().endsWith('.mp4')) {
      trimmed = '$trimmed.mp4';
    }
    return trimmed;
  }

  /// Export Merged Video -> saves to merge/<first_stem>_merged.mp4 or custom name
  static Future<StudioExportResult> exportMergeVideo({
    required List<MergeItem> mergePlaylist,
    required String projectDir,
    String? customFilename,
  }) async {
    final dirs = await ensureDirectories(projectDir);
    final mergeDir = dirs['merge']!;

    String filename;
    if (customFilename?.trim().isNotEmpty == true) {
      filename = _ensureMp4Extension(customFilename!.trim());
    } else if (mergePlaylist.isNotEmpty) {
      final firstStem = p.basenameWithoutExtension(mergePlaylist.first.fullPath);
      filename = '${firstStem}_merged.mp4';
    } else {
      filename = 'merge_${DateTime.now().millisecondsSinceEpoch}.mp4';
    }
    final targetPath = p.join(mergeDir.path, filename);

    final filePaths = mergePlaylist.map((m) => m.fullPath).toList();
    final args = [
      ...filePaths,
      '--output',
      targetPath,
      '--auto-normalize',
    ];

    final res = await PythonBridge.runScript(
      'concat.py',
      args,
      jobId: 'studio_merge_${DateTime.now().millisecondsSinceEpoch}',
    );

    return StudioExportResult(
      success: res.success,
      output: res.output,
      outputPath: targetPath,
    );
  }

  /// Export Multi-layer Composite Video (Overlay, Audio Clips, Subtitles, Mix state)
  static Future<StudioExportResult> exportCompositeVideo({
    required VideoFile video,
    required StudioSnapshot state,
    required String projectDir,
    String? customFilename,
  }) async {
    final dirs = await ensureDirectories(projectDir);
    final outDir = dirs['output']!;

    final filename = customFilename?.trim().isNotEmpty == true
        ? _ensureMp4Extension(customFilename!.trim())
        : '${video.stem}_edited.mp4';
    final targetPath = p.join(outDir.path, filename);

    final configMap = {
      'videoPath': video.fullPath,
      'outputPath': targetPath,
      'overlayClips': state.overlayClips.map((c) => c.toJson()).toList(),
      'audioClips': state.audioClips.map((a) => a.toJson()).toList(),
      'mixState': state.mixState.toJson(),
      'subtitles': state.subtitles.map((s) => s.toJson()).toList(),
      'subStyle': state.subStyle.toJson(),
    };

    final tempConfigFile = File(p.join(Directory.systemTemp.path, 'subvideo_comp_${DateTime.now().millisecondsSinceEpoch}.json'));
    await tempConfigFile.writeAsString(jsonEncode(configMap));

    try {
      final res = await PythonBridge.runScript(
        'composite_render.py',
        [tempConfigFile.path],
        jobId: 'studio_composite_${DateTime.now().millisecondsSinceEpoch}',
      );

      final fileExists = await File(targetPath).exists();
      return StudioExportResult(
        success: res.success && fileExists,
        output: res.output,
        outputPath: targetPath,
      );
    } finally {
      if (await tempConfigFile.exists()) {
        await tempConfigFile.delete().catchError((_) => tempConfigFile);
      }
    }
  }
}
