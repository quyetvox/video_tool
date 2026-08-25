import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import '../core/job_state.dart';
import '../core/step_base.dart';
import '../utils/ffmpeg_utils.dart';

class StepProbe extends StepBase {
  @override
  String get stepId => 's01_probe';

  @override
  List<String> get dependsOn => const [];

  @override
  List<String> get stepConfigKeys => const ['duration'];

  @override
  Future<Map<String, dynamic>> run(
    Directory workspace,
    Map<String, dynamic> config,
    JobState jobState,
  ) async {
    final inputVideo = jobState.data['input_video'] as String? ?? '';
    if (inputVideo.isEmpty || !File(inputVideo).existsSync()) {
      throw ArgumentError("Input video '$inputVideo' does not exist.");
    }

    final probeInfo = await FFmpegUtils.probe(inputVideo);
    final outFile = File(p.join(workspace.path, 's01_probe.json'));

    final outData = {
      'input_video': inputVideo,
      'duration': probeInfo.duration,
      'width': probeInfo.width,
      'height': probeInfo.height,
      'fps': probeInfo.fps,
      'has_audio': probeInfo.hasAudio,
      'has_video': probeInfo.hasVideo,
    };

    outFile.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(outData),
      flush: true,
    );

    return outData;
  }
}
