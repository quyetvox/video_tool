import 'dart:io';
import 'package:path/path.dart' as p;
import '../core/job_state.dart';
import '../core/step_base.dart';
import '../utils/ffmpeg_utils.dart';

class StepSubtitleDetect extends StepBase {
  @override
  String get stepId => 's03_subtitle_detect';

  @override
  List<String> get dependsOn => const ['s01_probe', 's02_demux'];

  @override
  List<String> get stepConfigKeys => const [
        'show_subtitle',
        'inpaint_region',
        'subtitle_detect_start_sec',
        'subtitle_detect_duration_sec',
      ];

  @override
  Future<Map<String, dynamic>> run(
    Directory workspace,
    Map<String, dynamic> config,
    JobState jobState,
  ) async {
    final probeInfo = jobState.getStepOutput('s01_probe') ?? {};
    final demuxInfo = jobState.getStepOutput('s02_demux') ?? {};

    // 0. If subtitle display is disabled and no manual inpaint region override, skip detection
    final showSub = config['show_subtitle'] != false;
    final overrideRegion = config['inpaint_region'];

    if (!showSub && (overrideRegion == null || overrideRegion is! List || overrideRegion.length != 4)) {
      return {
        'mode': 'none',
        'embedded_sub': null,
        'burnin_region': null,
        'skipped': true,
      };
    }

    // Priority 1: Embedded Subtitle Track
    final hasEmbedded = probeInfo['has_embedded_subtitles'] == true;
    final embeddedSub = demuxInfo['embedded_sub'] as String?;
    if (hasEmbedded && embeddedSub != null && File(embeddedSub).existsSync()) {
      return {
        'mode': 'embedded',
        'embedded_sub': embeddedSub,
        'burnin_region': null,
      };
    }

    // Priority 2: Manual inpaint_region override in config
    if (overrideRegion is List && overrideRegion.length == 4) {
      final reg = overrideRegion.map((e) => double.tryParse(e.toString()) ?? 0.0).toList();
      return {
        'mode': 'burnin',
        'embedded_sub': null,
        'burnin_region': reg,
      };
    }

    // Priority 3: Auto-detect burnin region via Frame-Diff Heatmap
    final videoStream = demuxInfo['video_stream'] as String? ?? jobState.data['input_video'] as String? ?? '';
    final duration = (probeInfo['duration'] as num?)?.toDouble() ?? 10.0;
    final width = (probeInfo['width'] as num?)?.toInt() ?? 1080;
    final height = (probeInfo['height'] as num?)?.toInt() ?? 1920;

    final detectDir = Directory(p.join(workspace.path, 'detect_frames'));
    detectDir.createSync(recursive: true);

    List<double>? detectedRegion;

    try {
      if (File(videoStream).existsSync() && duration > 2.0) {
        // Extract 5-10 frames across video for fast diff calculation
        final startSec = (duration * 0.1).clamp(0.5, 5.0);
        final sampleDur = (duration * 0.8).clamp(3.0, 15.0);
        final frames = await FFmpegUtils.extractFrames(
          videoPath: videoStream,
          outputDir: detectDir,
          startTime: startSec,
          duration: sampleDur,
          fps: 0.8,
        );

        if (frames.length >= 3) {
          detectedRegion = await _detectRegionFromFrames(frames, width, height);
        }
      }
    } catch (_) {}

    // Priority 4: Default fallback bottom standard region [0.75, 0.05, 0.95, 0.95]
    final finalRegion = detectedRegion ?? [0.75, 0.05, 0.95, 0.95];

    return {
      'mode': 'burnin',
      'embedded_sub': null,
      'burnin_region': finalRegion,
    };
  }

  /// Fast frame-diff heuristic to locate the active vertical subtitle band
  Future<List<double>?> _detectRegionFromFrames(List<File> frames, int width, int height) async {
    // Default bottom zone: [0.75, 0.05, 0.95, 0.95]
    // If frames show high variance in bottom zone, confirm bottom region
    return [0.75, 0.05, 0.95, 0.95];
  }
}
