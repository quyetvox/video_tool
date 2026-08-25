import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import '../core/job_state.dart';
import '../core/step_base.dart';
import '../utils/ffmpeg_utils.dart';

class StepTTS extends StepBase {
  @override
  String get stepId => 's12_tts';

  @override
  List<String> get dependsOn => const ['s08_translation', 's05b_gender_detect'];

  @override
  List<String> get stepConfigKeys => const [
        'tts',
        'tts_voice',
        'tts_voice_volume',
        'tts_speed_factor',
        'enable_gender_tts',
        'tts_voice_male',
        'tts_voice_female',
        'target_lang',
      ];

  static const Set<String> _fillerWords = {
    'ừm', 'a', 'ah', 'hì hì', 'ha ha', 'ừ', 'ơ', 'ồ', 'này', 'dạ', 'ừm...', 'ha',
  };

  static bool _isFiller(String text) {
    final t = text.trim().toLowerCase().replaceAll(RegExp(r'[\.,!\?]'), '');
    return _fillerWords.contains(t) || (t.length <= 1 && t != 'y' && t != 'ơ' && t != 'ô');
  }

  @override
  Future<Map<String, dynamic>> run(
    Directory workspace,
    Map<String, dynamic> config,
    JobState jobState,
  ) async {
    final finalVoiceWav = File(p.join(workspace.path, 'translated_voice.wav'));

    final ttsCfg = config['tts'] is Map ? (config['tts'] as Map) : {};
    final audioCfg = config['audio'] is Map ? (config['audio'] as Map) : {};
    final audioVols = audioCfg['volumes'] is Map ? (audioCfg['volumes'] as Map) : {};

    final ttsVol = double.tryParse((config['tts_voice_volume'] ?? audioVols['tts_voice'])?.toString() ?? '1.0') ?? 1.0;
    final isOcrOnly = config['ocr_only'] == true || config['ocr_only']?.toString().toLowerCase() == 'true';

    if (isOcrOnly || ttsVol == 0.0) {
      return {
        'skipped': true,
        'translated_voice': finalVoiceWav.path,
        'segment_count': 0,
      };
    }

    final transInfo = jobState.getStepOutput('s08_translation') ?? {};
    final transFile = transInfo['translation_file'] as String?;

    if (transFile == null || !File(transFile).existsSync()) {
      await _generateSilence(finalVoiceWav, 1.0);
      return {'translated_voice': finalVoiceWav.path, 'segment_count': 0};
    }

    final segments = (jsonDecode(File(transFile).readAsStringSync()) as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    if (segments.isEmpty) {
      await _generateSilence(finalVoiceWav, 1.0);
      return {'translated_voice': finalVoiceWav.path, 'segment_count': 0};
    }

    // Resolve Voice and Speed Factor
    final rawVoice = (config['tts_voice'] ?? ttsCfg['voice'] ?? 'vi').toString().trim();
    final speedFactor = double.tryParse((config['tts_speed_factor'] ?? ttsCfg['speed_factor'])?.toString() ?? '1.2') ?? 1.2;
    final enableGender = (config['enable_gender_tts'] ?? ttsCfg['enable_gender'] ?? false) == true;
    final voiceMale = (config['tts_voice_male'] ?? ttsCfg['voice_male'] ?? 'vi-VN-NamMinhNeural').toString().trim();
    final voiceFemale = (config['tts_voice_female'] ?? ttsCfg['voice_female'] ?? 'vi').toString().trim();

    final ttsDir = Directory(p.join(workspace.path, 'tts_segments'));
    if (ttsDir.existsSync()) {
      try { ttsDir.deleteSync(recursive: true); } catch (_) {}
    }
    ttsDir.createSync(recursive: true);

    final probeInfo = jobState.getStepOutput('s01_probe') ?? {};
    final totalDuration = (probeInfo['duration'] as num?)?.toDouble() ?? 0.0;

    final ffmpegBin = FFmpegUtils.resolveBinary('ffmpeg');
    final edgeTtsBin = _resolveEdgeTtsBinary();

    // 1. Parallel TTS Synthesis across all segments (Balanced Even Auto Cores Pool)
    final rawWorkers = (config['tts_num_workers'] ?? ttsCfg['num_workers'] ?? 'auto').toString().trim().toLowerCase();
    final rawHalf = Platform.numberOfProcessors ~/ 2;
    final autoCores = (rawHalf.isEven ? rawHalf : rawHalf - 1).clamp(2, 32);
    final poolSize = (rawWorkers == 'auto' || rawWorkers.isEmpty)
        ? autoCores
        : (int.tryParse(rawWorkers) ?? autoCores).clamp(1, 32);

    for (int i = 0; i < segments.length; i += poolSize) {
      final batch = <Future<void>>[];
      final endIdx = (i + poolSize < segments.length) ? (i + poolSize) : segments.length;
      for (int j = i; j < endIdx; j++) {
        batch.add(_synthesizeSingleSegment(
          segIndex: j,
          seg: segments[j],
          ttsDir: ttsDir,
          ffmpegBin: ffmpegBin,
          edgeTtsBin: edgeTtsBin,
          defaultVoice: rawVoice,
          enableGender: enableGender,
          voiceMale: voiceMale,
          voiceFemale: voiceFemale,
          speedFactor: speedFactor,
        ));
      }
      await Future.wait(batch);
    }

    // 2. Linear Audio Alignment & Silence Padding
    final alignedAudioFiles = <File>[];
    double currentTime = 0.0;

    for (int i = 0; i < segments.length; i++) {
      final seg = segments[i];
      final segStart = double.tryParse(seg['start']?.toString() ?? '0.0') ?? 0.0;
      final segEnd = double.tryParse(seg['end']?.toString() ?? '${segStart + 1.5}') ?? (segStart + 1.5);
      final targetDur = (segEnd - segStart).clamp(0.4, 30.0);
      final segWav = File(p.join(ttsDir.path, 'seg_${i.toString().padLeft(4, '0')}.wav'));

      if (!segWav.existsSync() || segWav.lengthSync() < 200) {
        currentTime = segStart > currentTime ? segStart : currentTime;
        continue;
      }

      // Silence padding before segment
      if (segStart > currentTime + 0.04) {
        final silenceGap = segStart - currentTime;
        final silenceFile = File(p.join(ttsDir.path, 'silence_${i.toString().padLeft(4, '0')}.wav'));
        await _generateSilence(silenceFile, silenceGap);
        alignedAudioFiles.add(silenceFile);
        currentTime = segStart;
      }

      // Measure audio duration & dynamic atempo adjustment if speech exceeds targetDur
      var audioDur = await FFmpegUtils.getAudioDuration(segWav.path);
      if (audioDur > targetDur + 0.2 && audioDur > 0.1) {
        final adjustFactor = (audioDur / targetDur).clamp(1.0, 2.0);
        final adjustedWav = File(p.join(ttsDir.path, 'adjusted_${i.toString().padLeft(4, '0')}.wav'));
        await Process.run(ffmpegBin, [
          '-y', '-i', segWav.path,
          '-filter:a', 'atempo=${adjustFactor.toStringAsFixed(2)}',
          '-ar', '44100', '-ac', '2',
          '-c:a', 'pcm_s16le',
          adjustedWav.path,
        ]);
        if (adjustedWav.existsSync() && adjustedWav.lengthSync() > 200) {
          alignedAudioFiles.add(adjustedWav);
          audioDur = await FFmpegUtils.getAudioDuration(adjustedWav.path);
          currentTime += audioDur;
          continue;
        }
      }

      alignedAudioFiles.add(segWav);
      currentTime += audioDur;
    }

    // Pad final silence up to totalDuration
    if (totalDuration > currentTime + 0.1) {
      final finalSilence = totalDuration - currentTime;
      final silenceFile = File(p.join(ttsDir.path, 'silence_final.wav'));
      await _generateSilence(silenceFile, finalSilence);
      alignedAudioFiles.add(silenceFile);
    }

    // Concat all aligned audio files into translated_voice.wav
    if (alignedAudioFiles.isNotEmpty) {
      final concatList = File(p.join(ttsDir.path, 'concat_list.txt'));
      final buf = StringBuffer();
      for (final f in alignedAudioFiles) {
        buf.writeln("file '${f.absolute.path}'");
      }
      concatList.writeAsStringSync(buf.toString());

      final concatArgs = [
        '-y',
        '-f', 'concat',
        '-safe', '0',
        '-i', concatList.path,
        '-c:a', 'pcm_s16le',
        finalVoiceWav.path,
      ];
      await Process.run(ffmpegBin, concatArgs);
    }

    if (!finalVoiceWav.existsSync() || finalVoiceWav.lengthSync() == 0) {
      await _generateSilence(finalVoiceWav, totalDuration > 0 ? totalDuration : 1.0);
    }

    return {
      'translated_voice': finalVoiceWav.path,
      'segment_count': alignedAudioFiles.length,
    };
  }

  Future<void> _synthesizeSingleSegment({
    required int segIndex,
    required Map<String, dynamic> seg,
    required Directory ttsDir,
    required String ffmpegBin,
    required String? edgeTtsBin,
    required String defaultVoice,
    required bool enableGender,
    required String voiceMale,
    required String voiceFemale,
    required double speedFactor,
  }) async {
    final text = (seg['translated_text'] ?? seg['text_vi'] ?? seg['text'] ?? '').toString().trim();
    final segStart = double.tryParse(seg['start']?.toString() ?? '0.0') ?? 0.0;
    final segEnd = double.tryParse(seg['end']?.toString() ?? '${segStart + 1.5}') ?? (segStart + 1.5);
    final targetDur = (segEnd - segStart).clamp(0.4, 30.0);

    final segMp3 = File(p.join(ttsDir.path, 'seg_${segIndex.toString().padLeft(4, '0')}.mp3'));
    final segWav = File(p.join(ttsDir.path, 'seg_${segIndex.toString().padLeft(4, '0')}.wav'));

    if (text.isEmpty || _isFiller(text)) {
      return;
    }

    String chosenVoice = defaultVoice;
    if (enableGender) {
      final segGender = (seg['gender'] ?? '').toString().toLowerCase();
      if (segGender == 'male') {
        chosenVoice = voiceMale;
      } else if (segGender == 'female') {
        chosenVoice = voiceFemale;
      }
    }

    final isGttsVoice = chosenVoice == 'vi' || chosenVoice == 'default' || chosenVoice == 'preset' || chosenVoice == 'gtts';
    bool synthesized = false;

    // 1. Python Parity Mode 1: Google TTS (gTTS - Ban Mai voice) for "vi" / "default" / "preset"
    if (isGttsVoice) {
      try {
        final url = Uri.parse('https://translate.google.com/translate_tts?ie=UTF-8&q=${Uri.encodeComponent(text)}&tl=vi&client=tw-ob');
        final resp = await http.get(url, headers: {
          'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36',
        }).timeout(const Duration(seconds: 8));

        if (resp.statusCode == 200 && resp.bodyBytes.length > 500) {
          segMp3.writeAsBytesSync(resp.bodyBytes);

          final filterArgs = (speedFactor - 1.0).abs() > 0.05
              ? ['-filter:a', 'atempo=${speedFactor.toStringAsFixed(2)}']
              : <String>[];

          await Process.run(ffmpegBin, [
            '-y', '-i', segMp3.path,
            ...filterArgs,
            '-ar', '44100', '-ac', '2',
            '-c:a', 'pcm_s16le',
            segWav.path,
          ]);
          try { segMp3.deleteSync(); } catch (_) {}
          synthesized = segWav.existsSync() && segWav.lengthSync() > 500;
        }
      } catch (_) {}
    }

    // 2. Python Parity Mode 2: EdgeTTS (Neural voices: vi-VN-NamMinhNeural / vi-VN-HoaiMyNeural)
    if (!synthesized && chosenVoice.startsWith('vi-VN-') && edgeTtsBin != null) {
      final ratePercent = ((speedFactor - 1.0) * 100).round();
      final rateStr = ratePercent >= 0 ? '+$ratePercent%' : '$ratePercent%';
      try {
        final res = await Process.run(edgeTtsBin, [
          '--voice', chosenVoice,
          '--rate', rateStr,
          '--text', text,
          '--write-media', segMp3.path,
        ]).timeout(const Duration(seconds: 10));

        if (res.exitCode == 0 && segMp3.existsSync() && segMp3.lengthSync() > 100) {
          await Process.run(ffmpegBin, [
            '-y', '-i', segMp3.path,
            '-ar', '44100', '-ac', '2',
            '-c:a', 'pcm_s16le',
            segWav.path,
          ]);
          try { segMp3.deleteSync(); } catch (_) {}
          synthesized = segWav.existsSync() && segWav.lengthSync() > 100;
        }
      } catch (_) {}
    }

    // 3. Fallback: Google TTS if EdgeTTS failed
    if (!synthesized && !isGttsVoice) {
      try {
        final url = Uri.parse('https://translate.google.com/translate_tts?ie=UTF-8&q=${Uri.encodeComponent(text)}&tl=vi&client=tw-ob');
        final resp = await http.get(url, headers: {
          'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36',
        }).timeout(const Duration(seconds: 8));

        if (resp.statusCode == 200 && resp.bodyBytes.length > 500) {
          segMp3.writeAsBytesSync(resp.bodyBytes);
          final filterArgs = (speedFactor - 1.0).abs() > 0.05
              ? ['-filter:a', 'atempo=${speedFactor.toStringAsFixed(2)}']
              : <String>[];
          await Process.run(ffmpegBin, [
            '-y', '-i', segMp3.path,
            ...filterArgs,
            '-ar', '44100', '-ac', '2',
            '-c:a', 'pcm_s16le',
            segWav.path,
          ]);
          try { segMp3.deleteSync(); } catch (_) {}
          synthesized = segWav.existsSync() && segWav.lengthSync() > 500;
        }
      } catch (_) {}
    }

    // 4. Native macOS Say Fallback (Zero Python)
    if (!synthesized && Platform.isMacOS) {
      final tempAiff = File('${segWav.path}.aiff');
      final rateWpm = (175 * speedFactor).clamp(100.0, 450.0).round();
      try {
        final res = await Process.run('say', [
          '-v', 'Linh',
          '-r', '$rateWpm',
          text,
          '-o', tempAiff.path,
        ]).timeout(const Duration(seconds: 5));

        if (res.exitCode == 0 && tempAiff.existsSync() && tempAiff.lengthSync() > 500) {
          await Process.run(ffmpegBin, [
            '-y', '-i', tempAiff.path,
            '-ar', '44100', '-ac', '2',
            '-c:a', 'pcm_s16le',
            segWav.path,
          ]);
          try { tempAiff.deleteSync(); } catch (_) {}
          synthesized = segWav.existsSync() && segWav.lengthSync() > 100;
        }
      } catch (_) {}
    }

    if (!synthesized) {
      await _generateSilence(segWav, targetDur);
    }
  }





  static String? _resolveEdgeTtsBinary() {
    final paths = [
      p.join(Directory.current.path, '.venv', 'bin', 'edge-tts'),
      p.join(Directory.current.parent.path, '.venv', 'bin', 'edge-tts'),
      '/opt/homebrew/bin/edge-tts',
      '/usr/local/bin/edge-tts',
    ];
    for (final path in paths) {
      if (File(path).existsSync()) return path;
    }
    return null;
  }

  Future<void> _generateSilence(File outFile, double duration) async {
    final ffmpegBin = FFmpegUtils.resolveBinary('ffmpeg');
    final args = [
      '-y',
      '-f', 'lavfi',
      '-i', 'anullsrc=r=44100:cl=stereo',
      '-t', duration.toStringAsFixed(3),
      '-c:a', 'pcm_s16le',
      outFile.path,
    ];
    await Process.run(ffmpegBin, args);
  }
}
