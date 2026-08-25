import 'dart:io';
import 'package:path/path.dart' as p;
import '../core/job_state.dart';
import '../core/step_base.dart';
import '../utils/ffmpeg_utils.dart';

class StepSubtitleRender extends StepBase {
  @override
  String get stepId => 's11_subtitle_render';

  @override
  List<String> get dependsOn => const ['s10_inpaint', 's09_subtitle_gen'];

  @override
  List<String> get stepConfigKeys => const ['show_subtitle', 'video_bitrate'];

  @override
  Future<Map<String, dynamic>> run(
    Directory workspace,
    Map<String, dynamic> config,
    JobState jobState,
  ) async {
    final renderedVideo = File(p.join(workspace.path, 'rendered_video.mp4'));
    final showSub = config['show_subtitle'] != false;

    final inpaintInfo = jobState.getStepOutput('s10_inpaint') ?? {};
    final subInfo = jobState.getStepOutput('s09_subtitle_gen') ?? {};
    final demuxInfo = jobState.getStepOutput('s02_demux') ?? {};

    String? cleanVideoPath = inpaintInfo['clean_video'] as String? ?? demuxInfo['video_stream'] as String?;

    // Fallback: check workspace directly if path in state is missing or stale
    if (cleanVideoPath == null || !File(cleanVideoPath).existsSync()) {
      final localClean = File(p.join(workspace.path, 'clean_video.mp4'));
      final localVideo = File(p.join(workspace.path, 'video_stream.mp4'));
      if (localClean.existsSync()) {
        cleanVideoPath = localClean.path;
      } else if (localVideo.existsSync()) {
        cleanVideoPath = localVideo.path;
      }
    }

    if (cleanVideoPath == null || !File(cleanVideoPath).existsSync()) {
      throw ArgumentError("Input clean video '$cleanVideoPath' not found in workspace: ${workspace.path}");
    }

    String? assPath = subInfo['ass_file'] as String?;
    if (assPath == null || !File(assPath).existsSync()) {
      final localAss = File(p.join(workspace.path, 'subtitles_vi.ass'));
      if (localAss.existsSync()) {
        assPath = localAss.path;
      }
    }

    if (!showSub || assPath == null || !File(assPath).existsSync() || File(assPath).lengthSync() < 100) {
      if (cleanVideoPath != renderedVideo.path) {
        File(cleanVideoPath).copySync(renderedVideo.path);
      }
      return {
        'skipped': true,
        'rendered_video': renderedVideo.path,
      };
    }

    final bitrate = config['video_bitrate']?.toString() ?? '4.0M';
    final ffmpegBin = FFmpegUtils.resolveBinary('ffmpeg');
    final escapedAss = assPath.replaceAll(r'\', r'/').replaceAll(':', r'\:').replaceAll("'", r"\'");
    final filter = "ass='$escapedAss'";

    final args = [
      '-y',
      '-i', cleanVideoPath,
      '-vf', filter,
      '-c:v', 'h264_videotoolbox',
      '-b:v', bitrate,
      '-pix_fmt', 'yuv420p',
      '-an',
      renderedVideo.path,
    ];

    final res = await Process.run(ffmpegBin, args);
    if (res.exitCode != 0) {
      // Fallback software libx264
      final swArgs = [
        '-y',
        '-i', cleanVideoPath,
        '-vf', filter,
        '-c:v', 'libx264',
        '-preset', 'fast',
        '-b:v', bitrate,
        '-pix_fmt', 'yuv420p',
        '-an',
        renderedVideo.path,
      ];
      final resSw = await Process.run(ffmpegBin, swArgs);
      if (resSw.exitCode != 0) {
        throw ProcessException(ffmpegBin, swArgs, 'Subtitle render failed: ${resSw.stderr}', resSw.exitCode);
      }
    }

    return {
      'rendered_video': renderedVideo.path,
    };
  }
}
