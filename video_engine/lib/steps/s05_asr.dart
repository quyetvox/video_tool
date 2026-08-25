import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import '../core/job_state.dart';
import '../core/step_base.dart';
import '../ffi/audio_dsp_bindings.dart';
import '../utils/repetition_cleaner.dart';

class StepASR extends StepBase {
  @override
  String get stepId => 's05_asr';

  @override
  List<String> get dependsOn => const ['s04_audio_separate'];

  @override
  List<String> get stepConfigKeys => const ['asr', 'asr_model', 'ocr_only'];

  @override
  Future<Map<String, dynamic>> run(
    Directory workspace,
    Map<String, dynamic> config,
    JobState jobState,
  ) async {
    final outFile = File(p.join(workspace.path, 's05_asr.json'));

    final isOcrOnly = config['ocr_only'] == true;
    if (isOcrOnly) {
      outFile.writeAsStringSync('[]');
      return {
        'skipped': true,
        'transcript_file': outFile.path,
        'segment_count': 0,
      };
    }

    final audioDir = Directory(p.join(workspace.path, 'audio_separated'));
    final origVoiceOnDisk = File(p.join(audioDir.path, 'orig_voice.wav'));
    final demuxAudioOnDisk = File(p.join(workspace.path, 'demux', 'audio_stream.wav'));

    String voicePath = '';
    if (origVoiceOnDisk.existsSync() && origVoiceOnDisk.lengthSync() > 1000) {
      voicePath = origVoiceOnDisk.path;
    } else if (demuxAudioOnDisk.existsSync() && demuxAudioOnDisk.lengthSync() > 1000) {
      voicePath = demuxAudioOnDisk.path;
    } else {
      final audioInfo = jobState.getStepOutput('s04_audio_separate') ?? {};
      voicePath = (audioInfo['orig_voice'] as String?) ?? (audioInfo['voice'] as String?) ?? '';
    }

    if (voicePath.isEmpty || !File(voicePath).existsSync()) {
      outFile.writeAsStringSync('[]');
      return {
        'transcript_file': outFile.path,
        'segment_count': 0,
      };
    }

    List<Map<String, dynamic>> rawSegments = [];

    // 1. Execute MLX-Whisper via Python Sidecar
    final pyBin = resolvePythonBinary();
    final asrModel = (config['asr_model'] ?? (config['asr'] is Map ? config['asr']['model'] : null) ?? 'auto').toString();

    final pyScript = '''
import json, sys, os
from pathlib import Path

audio_path = sys.argv[1]
out_json_path = sys.argv[2]
model = sys.argv[3] if len(sys.argv) > 3 else "auto"

def _get_hf_repo(m_name: str) -> str:
    if m_name.startswith("mlx-community/"):
        return m_name
    if "turbo" in m_name:
        return "mlx-community/whisper-large-v3-turbo"
    if not m_name.endswith("-mlx"):
        return f"mlx-community/whisper-{m_name}-mlx"
    return f"mlx-community/whisper-{m_name}"

try:
    import mlx_whisper
    repo = _get_hf_repo(model if model != "auto" else "large-v3-turbo")
    res = mlx_whisper.transcribe(audio_path, path_or_hf_repo=repo, word_timestamps=True, condition_on_previous_text=False)
    segments = []
    for seg in res.get("segments", []):
        words = seg.get("words", [])
        if words:
            w_start = float(words[0].get("start", seg.get("start", 0.0)))
            w_end = float(words[-1].get("end", seg.get("end", 0.0)))
            s_start = min(float(seg.get("start", 0.0)), w_start) if abs(w_start - float(seg.get("start", 0.0))) > 2.0 else w_start
            s_end = max(float(seg.get("end", 0.0)), w_end)
        else:
            s_start = float(seg.get("start", 0.0))
            s_end = float(seg.get("end", 0.0))
        segments.append({
            "start": round(s_start, 3),
            "end": round(s_end, 3),
            "text": seg.get("text", "").strip()
        })
    with open(out_json_path, "w", encoding="utf-8") as f:
        json.dump(segments, f, ensure_ascii=False, indent=2)
except Exception as e:
    try:
        import whisper
        m = whisper.load_model("base")
        res = m.transcribe(audio_path)
        segments = []
        for seg in res.get("segments", []):
            segments.append({
                "start": round(float(seg.get("start", 0.0)), 3),
                "end": round(float(seg.get("end", 0.0)), 3),
                "text": seg.get("text", "").strip()
            })
        with open(out_json_path, "w", encoding="utf-8") as f:
            json.dump(segments, f, ensure_ascii=False, indent=2)
    except Exception as e2:
        sys.stderr.write(f"ASR error: {e} / {e2}\\n")
''';

    final customEnv = Map<String, String>.from(Platform.environment);
    final homebrewPath = '/opt/homebrew/bin:/usr/local/bin:/opt/homebrew/sbin';
    customEnv['PATH'] = '$homebrewPath:${customEnv['PATH'] ?? '/usr/bin:/bin'}';

    final procRes = await Process.run(
      pyBin,
      ['-c', pyScript, voicePath, outFile.path, asrModel],
      environment: customEnv,
    );
    if (procRes.exitCode != 0) {
      stderr.writeln('[s05_asr] Python error: ${procRes.stderr}');
    }

    if (outFile.existsSync() && outFile.lengthSync() > 10) {
      try {
        final parsed = jsonDecode(outFile.readAsStringSync()) as List;
        rawSegments = parsed.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      } catch (_) {}
    }

    stderr.writeln('[s05_asr] voicePath: $voicePath');
    stderr.writeln('[s05_asr] rawSegments count: ${rawSegments.length}');

    // 2. Anti-hallucination repetition cleaner
    final cleaned = RepetitionCleaner.cleanSegments(rawSegments);
    stderr.writeln('[s05_asr] cleaned count: ${cleaned.length}');

    // 3. Rust VAD Energy Snapping to snap timestamps to actual spoken onsets
    List<Map<String, dynamic>> refined = cleaned;
    try {
      final vadRes = AudioDspBindings.refineTimestamps(
        audioPath: voicePath,
        segments: cleaned,
      );
      if (vadRes.length >= cleaned.length * 0.8) {
        refined = vadRes;
      }
    } catch (_) {}
    stderr.writeln('[s05_asr] refined count: ${refined.length}');

    outFile.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(refined),
      flush: true,
    );

    return {
      'transcript_file': outFile.path,
      'segment_count': refined.length,
    };
  }

  static String resolvePythonBinary() {
    final paths = [
      p.join(Directory.current.path, '.venv', 'bin', 'python'),
      p.join(Directory.current.parent.path, '.venv', 'bin', 'python'),
      p.join(Platform.environment['HOME'] ?? '', '.venv', 'bin', 'python'),
      '/opt/homebrew/bin/python3',
      '/usr/local/bin/python3',
      '/usr/bin/python3',
    ];
    for (final path in paths) {
      if (File(path).existsSync()) return path;
    }
    return 'python3';
  }
}
