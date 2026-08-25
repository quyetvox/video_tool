import 'dart:io';
import 'package:path/path.dart' as p;
import '../core/job_state.dart';
import '../core/step_base.dart';
import '../utils/ffmpeg_utils.dart';

class StepDemux extends StepBase {
  @override
  String get stepId => 's02_demux';

  @override
  List<String> get dependsOn => const ['s01_probe'];

  @override
  List<String> get stepConfigKeys => const ['duration'];

  @override
  Future<Map<String, dynamic>> run(
    Directory workspace,
    Map<String, dynamic> config,
    JobState jobState,
  ) async {
    final inputVideo = jobState.data['input_video'] as String? ?? '';
    final demuxDir = Directory(p.join(workspace.path, 'demux'));
    demuxDir.createSync(recursive: true);

    final videoStream = File(p.join(demuxDir.path, 'video_stream.mp4'));
    final audioStream = File(p.join(demuxDir.path, 'audio_stream.wav'));

    double? duration;
    if (config.containsKey('duration') && config['duration'] != null) {
      duration = double.tryParse(config['duration'].toString());
    }

    await FFmpegUtils.demux(
      inputVideo: inputVideo,
      outputVideo: videoStream.path,
      outputAudio: audioStream.path,
      duration: duration,
    );

    return {
      'video_stream': videoStream.path,
      'audio_stream': audioStream.path,
    };
  }
}
