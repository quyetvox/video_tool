import 'dart:io';
import 'package:path/path.dart' as p;
import '../core/job_state.dart';
import '../core/step_base.dart';
import '../utils/ffmpeg_utils.dart';

class StepEncode extends StepBase {
  @override
  String get stepId => 's14_encode';

  @override
  List<String> get dependsOn => const ['s11_subtitle_render', 's13_audio_mix'];

  @override
  List<String> get stepConfigKeys => const [
        'output_suffix',
        'output_dir',
        'duration',
        'video_bitrate',
      ];

  @override
  Future<Map<String, dynamic>> run(
    Directory workspace,
    Map<String, dynamic> config,
    JobState jobState,
  ) async {
    final subInfo = jobState.getStepOutput('s11_subtitle_render') ?? {};
    final audioInfo = jobState.getStepOutput('s13_audio_mix') ?? {};
    final demuxInfo = jobState.getStepOutput('s02_demux') ?? {};

    String? videoIn = subInfo['rendered_video'] as String? ?? demuxInfo['video_stream'] as String?;
    if (videoIn == null || !File(videoIn).existsSync()) {
      final localRendered = File(p.join(workspace.path, 'rendered_video.mp4'));
      final localClean = File(p.join(workspace.path, 'clean_video.mp4'));
      final localVideo = File(p.join(workspace.path, 'video_stream.mp4'));
      if (localRendered.existsSync()) {
        videoIn = localRendered.path;
      } else if (localClean.existsSync()) {
        videoIn = localClean.path;
      } else if (localVideo.existsSync()) {
        videoIn = localVideo.path;
      }
    }

    String? audioIn = audioInfo['mixed_audio'] as String? ?? demuxInfo['audio_stream'] as String?;
    if (audioIn == null || !File(audioIn).existsSync()) {
      final localMixed = File(p.join(workspace.path, 'final_mixed_audio.wav'));
      final localAudio = File(p.join(workspace.path, 'audio_stream.wav'));
      if (localMixed.existsSync()) {
        audioIn = localMixed.path;
      } else if (localAudio.existsSync()) {
        audioIn = localAudio.path;
      }
    }

    if (videoIn == null || audioIn == null) {
      throw StateError('Missing video_in or audio_in for final encode.');
    }

    final inputVideo = jobState.data['input_video'] as String? ?? 'video.mp4';
    final stem = p.basenameWithoutExtension(inputVideo);
    final suffix = config['output_suffix']?.toString() ?? '_vi';
    final bitrate = config['video_bitrate']?.toString() ?? '4.0M';

    // Output Directory in Project (assets/<project>/output)
    Directory outDir;
    final cfgOut = config['output_dir']?.toString();
    if (cfgOut != null && cfgOut.isNotEmpty && !cfgOut.contains('/workspace/output')) {
      outDir = Directory(cfgOut);
    } else {
      final projectDir = workspace.path.contains('/workspace')
          ? Directory(workspace.path.split('/workspace').first)
          : workspace.parent;
      outDir = Directory(p.join(projectDir.path, 'output'));
    }
    outDir.createSync(recursive: true);

    final finalOutput = File(p.join(outDir.path, '$stem$suffix.mp4'));

    await FFmpegUtils.encodeFinal(
      videoIn: videoIn,
      audioIn: audioIn,
      outputFile: finalOutput.path,
      bitrate: bitrate,
    );

    return {
      'output_video': finalOutput.path,
    };
  }
}
