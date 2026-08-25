import 'dart:io';
import 'package:path/path.dart' as p;
import '../core/job_state.dart';
import '../core/step_base.dart';
import '../ffi/audio_dsp_bindings.dart';
import '../utils/ffmpeg_utils.dart';
import 's05_asr.dart';

class StepAudioSeparate extends StepBase {
  @override
  String get stepId => 's04_audio_separate';

  @override
  List<String> get dependsOn => const ['s02_demux'];

  @override
  List<String> get stepConfigKeys => const [
        'device',
        'noise_reduction_strength',
        'ambient_split_threshold',
        'ocr_only',
      ];

  @override
  Future<Map<String, dynamic>> run(
    Directory workspace,
    Map<String, dynamic> config,
    JobState jobState,
  ) async {
    final demuxInfo = jobState.getStepOutput('s02_demux') ?? {};
    final audioStream = demuxInfo['audio_stream'] as String?;

    if (audioStream == null || !File(audioStream).existsSync()) {
      throw ArgumentError("Audio stream '$audioStream' not found.");
    }

    final isOcrOnly = config['ocr_only'] == true;
    if (isOcrOnly) {
      return {
        'skipped': true,
        'voice': audioStream,
        'music': audioStream,
        'effect': audioStream,
        'orig_voice': audioStream,
      };
    }

    final audioDir = Directory(p.join(workspace.path, 'audio_separated'));
    audioDir.createSync(recursive: true);

    final voiceFile = File(p.join(audioDir.path, 'voice.wav'));
    final musicFile = File(p.join(audioDir.path, 'music.wav'));
    final effectFile = File(p.join(audioDir.path, 'effect.wav'));
    final origVoiceFile = File(p.join(audioDir.path, 'orig_voice.wav'));

    File(audioStream).copySync(origVoiceFile.path);

    // 1. Try Demucs AI Vocal Separation
    bool demucsSuccess = false;
    try {
      final pyBin = StepASR.resolvePythonBinary();
      await Process.run(pyBin, [
        '-m', 'demucs.separate',
        '-d', 'mps',
        '--two-stems', 'vocals',
        '-o', audioDir.path,
        audioStream,
      ]);
      final streamStem = p.basenameWithoutExtension(audioStream);
      final demucsVocals = File(p.join(audioDir.path, 'htdemucs', streamStem, 'vocals.wav'));
      final demucsNoVocals = File(p.join(audioDir.path, 'htdemucs', streamStem, 'no_vocals.wav'));
      if (demucsVocals.existsSync() && demucsVocals.lengthSync() > 1000) {
        demucsVocals.copySync(voiceFile.path);
        demucsSuccess = true;
      }
      if (demucsNoVocals.existsSync() && demucsNoVocals.lengthSync() > 1000) {
        demucsNoVocals.copySync(musicFile.path);
      }
    } catch (_) {}

    // Fallback if Demucs not available or failed: FFmpeg stereo phase cancellation
    if (!demucsSuccess) {
      final ffmpegBin = FFmpegUtils.resolveBinary('ffmpeg');
      File(audioStream).copySync(voiceFile.path);

      // Extract background music by center-channel vocal cancellation
      final cmdNoVocal = [
        '-y',
        '-i', audioStream,
        '-af', 'pan=stereo|c0=0.5*c0-0.5*c1|c1=0.5*c1-0.5*c0',
        '-c:a', 'pcm_s16le',
        musicFile.path,
      ];
      await Process.run(ffmpegBin, cmdNoVocal);
    }

    if (!musicFile.existsSync() || musicFile.lengthSync() == 0) {
      musicFile.createSync();
    }
    effectFile.createSync();

    // 2. Apply Rust Spectral Gate Noise Reduction to remove vocal ghost residue from music track
    final noiseStrength = double.tryParse(config['noise_reduction_strength']?.toString() ?? '0.9') ?? 0.9;
    if (musicFile.existsSync() && musicFile.lengthSync() > 1000) {
      final cleanedMusic = File(p.join(audioDir.path, 'music_cleaned.wav'));
      final success = AudioDspBindings.applySpectralGate(
        inputWav: musicFile.path,
        outputWav: cleanedMusic.path,
        propDecrease: noiseStrength,
      );

      if (success && cleanedMusic.existsSync() && cleanedMusic.lengthSync() > 1000) {
        cleanedMusic.renameSync(musicFile.path);
      }
    }

    return {
      'voice': voiceFile.path,
      'music': musicFile.path,
      'effect': effectFile.path,
      'orig_voice': origVoiceFile.path,
    };
  }
}
