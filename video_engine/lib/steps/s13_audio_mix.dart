import 'dart:io';
import 'package:path/path.dart' as p;
import '../core/job_state.dart';
import '../core/step_base.dart';
import '../utils/ffmpeg_utils.dart';

class StepAudioMix extends StepBase {
  @override
  String get stepId => 's13_audio_mix';

  @override
  List<String> get dependsOn => const ['s04_audio_separate', 's12_tts'];

  @override
  List<String> get stepConfigKeys => const [
        'tts_voice',
        'music_volume',
        'ambient_volume',
        'tts_voice_volume',
        'original_voice_volume',
      ];

  @override
  Future<Map<String, dynamic>> run(
    Directory workspace,
    Map<String, dynamic> config,
    JobState jobState,
  ) async {
    final mixedAudio = File(p.join(workspace.path, 'final_mixed_audio.wav'));

    final audioCfg = config['audio'] is Map ? (config['audio'] as Map) : {};
    final audioVols = audioCfg['volumes'] is Map ? (audioCfg['volumes'] as Map) : {};
    final ttsCfg = config['tts'] is Map ? (config['tts'] as Map) : {};

    final ttsVol = double.tryParse((config['tts_voice_volume'] ?? audioVols['tts_voice'])?.toString() ?? '1.0') ?? 1.0;
    final ttsVoice = (config['tts_voice'] ?? ttsCfg['voice'])?.toString().toLowerCase().trim() ?? 'vi';
    final isOcrOnly = config['ocr_only'] == true || config['ocr_only']?.toString().toLowerCase() == 'true';

    if (isOcrOnly || ttsVol == 0.0 || ttsVoice == '0' || ttsVoice == 'none' || ttsVoice == 'off') {
      final demuxInfo = jobState.getStepOutput('s02_demux') ?? {};
      final audioStream = demuxInfo['audio_stream'] as String?;
      if (audioStream != null && File(audioStream).existsSync()) {
        File(audioStream).copySync(mixedAudio.path);
      }
      return {
        'skipped': true,
        'mixed_audio': mixedAudio.path,
      };
    }

    final audioInfo = jobState.getStepOutput('s04_audio_separate') ?? {};
    final ttsInfo = jobState.getStepOutput('s12_tts') ?? {};
    final probeInfo = jobState.getStepOutput('s01_probe') ?? {};

    final musicPath = audioInfo['music'] as String? ?? '';
    final voicePath = ttsInfo['translated_voice'] as String? ?? '';
    final ambientPath = audioInfo['ambient'] as String?;
    final origVoicePath = audioInfo['orig_voice'] as String?;
    final duration = (probeInfo['duration'] as num?)?.toDouble();

    final origVol = double.tryParse((config['original_voice_volume'] ?? audioVols['original_voice'])?.toString() ?? '0.05') ?? 0.05;
    final musicVol = double.tryParse((config['music_volume'] ?? audioVols['music'])?.toString() ?? '0.5') ?? 0.5;
    final ambientVol = double.tryParse((config['ambient_volume'] ?? audioVols['ambient'])?.toString() ?? '0.75') ?? 0.75;

    await FFmpegUtils.mixAudio(
      musicPath: musicPath,
      voicePath: voicePath,
      outputPath: mixedAudio.path,
      ambientPath: ambientPath,
      origVoicePath: origVoicePath,
      targetDuration: duration,
      musicVolume: musicVol,
      ambientVolume: ambientVol,
      voiceVolume: ttsVol,
      origVoiceVolume: origVol,
    );

    return {
      'mixed_audio': mixedAudio.path,
    };
  }
}
