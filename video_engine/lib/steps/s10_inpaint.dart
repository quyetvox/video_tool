import 'dart:io';
import 'package:path/path.dart' as p;
import '../core/job_state.dart';
import '../core/step_base.dart';
import '../utils/ffmpeg_utils.dart';

class StepInpaint extends StepBase {
  @override
  String get stepId => 's10_inpaint';

  @override
  List<String> get dependsOn => const ['s02_demux', 's03_subtitle_detect'];

  @override
  List<String> get stepConfigKeys => const [
        'inpaint_engine',
        'inpaint_method',
        'inpaint_region',
        'inpaint_blur_radius',
        'watermark_enabled',
        'watermark_region',
        'watermark_image',
        'watermark_text',
        'watermark_font_name',
        'watermark_font_color',
        'watermark_opacity',
        'watermark_blur_bg',
      ];

  @override
  Future<Map<String, dynamic>> run(
    Directory workspace,
    Map<String, dynamic> config,
    JobState jobState,
  ) async {
    final demuxInfo = jobState.getStepOutput('s02_demux') ?? {};
    final detectInfo = jobState.getStepOutput('s03_subtitle_detect') ?? {};
    final probeInfo = jobState.getStepOutput('s01_probe') ?? {};

    final videoStream = demuxInfo['video_stream'] as String?;
    if (videoStream == null || !File(videoStream).existsSync()) {
      throw ArgumentError("Video stream '$videoStream' not found.");
    }

    final cleanVideo = File(p.join(workspace.path, 'clean_video.mp4'));
    final inpaintCfg = config['inpaint'] is Map ? (config['inpaint'] as Map) : {};
    final inpaintEngine = (config['inpaint_engine'] ?? inpaintCfg['engine'] ?? 'apple_vision_inpaint').toString().toLowerCase();
    final inpaintMethod = (config['inpaint_method'] ?? inpaintCfg['method'] ?? 'vertical_gradient').toString().toLowerCase();

    // 1. If inpaint engine is box_color: SubBox is drawn via ASS Layer 0 in s09/s11
    if (inpaintEngine == 'box_color' || inpaintEngine == 'box') {
      if (videoStream != cleanVideo.path) {
        File(videoStream).copySync(cleanVideo.path);
      }
      return {
        'skipped': true,
        'clean_video': cleanVideo.path,
      };
    }

    final videoWidth = (probeInfo['width'] as num?)?.toInt() ?? 1080;
    final videoHeight = (probeInfo['height'] as num?)?.toInt() ?? 1920;

    List<double> region = [0.75, 0.05, 0.95, 0.95];
    final cfgRegion = config['inpaint_region'];
    if (cfgRegion is List && cfgRegion.length == 4) {
      region = cfgRegion.map((e) => double.tryParse(e.toString()) ?? 0.0).toList();
    } else if (detectInfo['burnin_region'] is List && (detectInfo['burnin_region'] as List).length == 4) {
      region = (detectInfo['burnin_region'] as List).map((e) => double.tryParse(e.toString()) ?? 0.0).toList();
    }

    final paddingY = double.tryParse((config['inpaint_padding_y'] ?? inpaintCfg['padding_y'] ?? config['blur_box_padding_y'])?.toString() ?? '0.005') ?? 0.005;

    // Apply padding_y
    final ymin = (region[0] - paddingY).clamp(0.0, 1.0);
    final xmin = region[1].clamp(0.0, 1.0);
    final ymax = (region[2] + paddingY).clamp(0.0, 1.0);
    final xmax = region[3].clamp(0.0, 1.0);
    final paddedRegion = [ymin, xmin, ymax, xmax];

    final tempInpainted = File(p.join(workspace.path, 'temp_inpainted.mp4'));
    final inpaintOutPath = tempInpainted.path;
    bool inpaintDone = false;

    // 2. Native Directional Vertical Gradient Inpaint (100% parity with Python apple_vision_inpaint)
    if (inpaintEngine == 'apple_vision_inpaint' || inpaintEngine == 'apple_vision' || inpaintMethod == 'vertical_gradient') {
      final inpaintBin = _resolveInpaintBinary();
      if (inpaintBin != null && File(inpaintBin).existsSync()) {
        final fps = (probeInfo['fps'] as num?)?.toDouble() ?? 30.0;
        final bitrate = config['video_bitrate']?.toString() ?? '4.0M';

        final args = [
          videoStream,
          inpaintOutPath,
          paddedRegion[0].toString(),
          paddedRegion[1].toString(),
          paddedRegion[2].toString(),
          paddedRegion[3].toString(),
          videoWidth.toString(),
          videoHeight.toString(),
          fps.toString(),
          bitrate,
        ];

        final res = await Process.run(inpaintBin, args);
        if (res.exitCode == 0 && tempInpainted.existsSync() && tempInpainted.lengthSync() > 1000) {
          inpaintDone = true;
        }
      }
    }

    // 3. Fallback / ffmpeg_blur Mode
    if (!inpaintDone) {
      final topPx = (paddedRegion[0] * videoHeight).round();
      final leftPx = (paddedRegion[1] * videoWidth).round();
      final bottomPx = (paddedRegion[2] * videoHeight).round();
      final rightPx = (paddedRegion[3] * videoWidth).round();
      final boxWidth = rightPx - leftPx;
      final boxHeight = bottomPx - topPx;

      final blurRadius = (config['inpaint_blur_radius'] as num?)?.toInt() ?? 15;
      final ffmpegBin = FFmpegUtils.resolveBinary('ffmpeg');
      final filter = '[0:v]crop=$boxWidth:$boxHeight:$leftPx:$topPx,boxblur=$blurRadius[blur];[0:v][blur]overlay=$leftPx:$topPx[vfinal]';

      final args = [
        '-y',
        '-i', videoStream,
        '-filter_complex', filter,
        '-map', '[vfinal]',
        '-c:v', 'h264_videotoolbox',
        '-b:v', config['video_bitrate']?.toString() ?? '4.0M',
        '-pix_fmt', 'yuv420p',
        '-an',
        inpaintOutPath,
      ];

      final res = await Process.run(ffmpegBin, args);
      if (res.exitCode == 0 && tempInpainted.existsSync() && tempInpainted.lengthSync() > 1000) {
        inpaintDone = true;
      }
    }

    final videoForWatermark = inpaintDone ? inpaintOutPath : videoStream;

    // 4. Apply watermark if enabled
    final wmApplied = await FFmpegUtils.applyWatermark(
      inputVideo: videoForWatermark,
      outputVideo: cleanVideo.path,
      config: config,
      width: videoWidth,
      height: videoHeight,
    );

    if (!wmApplied) {
      if (videoForWatermark != cleanVideo.path) {
        File(videoForWatermark).copySync(cleanVideo.path);
      }
    }

    if (tempInpainted.existsSync()) {
      try { tempInpainted.deleteSync(); } catch (_) {}
    }

    return {
      'clean_video': cleanVideo.path,
      'watermark_applied': wmApplied,
    };
  }

  static String? _resolveInpaintBinary() {
    final home = Platform.environment['HOME'] ?? '';
    final candidates = [
      p.join(home, 'Library', 'Application Support', 'SubVideo', 'engine', 'sub_video_inpaint'),
      p.join(File(Platform.resolvedExecutable).parent.path, 'sub_video_inpaint'),
      '/Users/voquyt/Documents/projects/video/Sub-Video/rust_native/target/release/sub_video_inpaint',
      p.join(home, 'Documents', 'projects', 'video', 'Sub-Video', 'rust_native', 'target', 'release', 'sub_video_inpaint'),
    ];

    for (final c in candidates) {
      if (File(c).existsSync()) {
        try {
          Process.runSync('chmod', ['+x', c]);
        } catch (_) {}
        return c;
      }
    }
    return null;
  }
}
