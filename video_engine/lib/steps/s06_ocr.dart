import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import '../core/job_state.dart';
import '../core/step_base.dart';

class StepOCR extends StepBase {
  @override
  String get stepId => 's06_ocr';

  @override
  List<String> get dependsOn => const ['s01_probe', 's03_subtitle_detect'];

  @override
  List<String> get stepConfigKeys => const [
        'ocr',
        'ocr_mode',
        'diff_threshold',
        'diff_step',
        'ocr_only',
        'inpaint_region',
      ];

  static String? _resolveNativeOCRBinary() {
    final execDir = File(Platform.resolvedExecutable).parent.path;
    final candidates = [
      p.join(execDir, 'sub_video_vision_ocr'),
      p.join(execDir, '..', 'Frameworks', 'sub_video_vision_ocr'),
      p.join(execDir, '..', 'Resources', 'sub_video_vision_ocr'),
      p.join(Directory.current.path, 'rust_native', 'target', 'release', 'sub_video_vision_ocr'),
      p.join(Directory.current.path, '..', 'rust_native', 'target', 'release', 'sub_video_vision_ocr'),
      '/Users/voquyt/Documents/projects/video/Sub-Video/rust_native/target/release/sub_video_vision_ocr',
    ];

    for (final c in candidates) {
      if (File(c).existsSync()) {
        return c;
      }
    }
    return null;
  }

  @override
  Future<Map<String, dynamic>> run(
    Directory workspace,
    Map<String, dynamic> config,
    JobState jobState,
  ) async {
    final outFile = File(p.join(workspace.path, 's06_ocr.json'));
    //final isOcrOnly = config['ocr_only'] == true;

    // Check if pre-existing or manual OCR file exists with data
    if (outFile.existsSync() && outFile.lengthSync() > 10) {
      try {
        final parsed = jsonDecode(outFile.readAsStringSync());
        if (parsed is List && parsed.isNotEmpty) {
          return {
            'ocr_file': outFile.path,
            'segment_count': parsed.length,
          };
        }
      } catch (_) {}
    }

    final detectInfo = jobState.getStepOutput('s03_subtitle_detect') ?? {};
    final demuxInfo = jobState.getStepOutput('s02_demux') ?? {};
    final videoPath = demuxInfo['video_stream'] as String? ?? jobState.data['input_video'] as String?;

    if (videoPath == null || !File(videoPath).existsSync()) {
      outFile.writeAsStringSync('[]');
      return {'ocr_file': outFile.path, 'segment_count': 0};
    }

    // Determine OCR region
    List<double> region = [0.10, 0.0, 0.95, 1.0];
    final cfgRegion = config['inpaint_region'];
    if (cfgRegion is List && cfgRegion.length == 4) {
      region = cfgRegion.map((e) => double.tryParse(e.toString()) ?? 0.0).toList();
    } else if (detectInfo['burnin_region'] is List && (detectInfo['burnin_region'] as List).length == 4) {
      region = (detectInfo['burnin_region'] as List).map((e) => double.tryParse(e.toString()) ?? 0.0).toList();
    }

    final diffThreshold = double.tryParse(config['diff_threshold']?.toString() ?? '8.0') ?? 8.0;
    final regionStr = region.join(',');

    // Execute Native Apple Vision OCR on macOS (or WinRT/ONNX on Windows/Linux)
    final ocrBin = _resolveNativeOCRBinary();
    if (ocrBin != null && File(ocrBin).existsSync()) {
      final args = [
        '--video', videoPath,
        '--region', regionStr,
        '--output', outFile.path,
        '--diff-threshold', diffThreshold.toString(),
        '--fps', '2.0',
      ];

      final res = await Process.run(ocrBin, args);
      if (res.exitCode == 0 && outFile.existsSync() && outFile.lengthSync() > 5) {
        try {
          final segments = jsonDecode(outFile.readAsStringSync()) as List;
          return {
            'ocr_file': outFile.path,
            'segment_count': segments.length,
          };
        } catch (_) {}
      }
    }

    // Default empty if OCR fails or no text
    if (!outFile.existsSync()) {
      outFile.writeAsStringSync('[]');
    }

    return {
      'ocr_file': outFile.path,
      'segment_count': 0,
    };
  }
}
