import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;

const List<String> stepOrder = [
  's01_probe',
  's02_demux',
  's03_subtitle_detect',
  's04_audio_separate',
  's05_asr',
  's05b_gender_detect',
  's06_ocr',
  's07_transcript_merge',
  's08_translation',
  's08b_metadata_gen',
  's08c_timing',
  's09_subtitle_gen',
  's10_inpaint',
  's11_subtitle_render',
  's12_tts',
  's13_audio_mix',
  's14_encode',
];

const Map<String, List<String>> stepDependencies = {
  's01_probe': [],
  's02_demux': ['s01_probe'],
  's03_subtitle_detect': ['s01_probe', 's02_demux'],
  's04_audio_separate': ['s02_demux'],
  's05_asr': ['s04_audio_separate'],
  's05b_gender_detect': ['s04_audio_separate', 's05_asr'],
  's06_ocr': ['s01_probe', 's03_subtitle_detect'],
  's07_transcript_merge': ['s05_asr', 's06_ocr'],
  's08_translation': ['s07_transcript_merge'],
  's08b_metadata_gen': ['s08_translation'],
  's08c_timing': ['s08_translation'],
  's09_subtitle_gen': ['s08_translation', 's08c_timing', 's03_subtitle_detect'],
  's10_inpaint': ['s02_demux', 's03_subtitle_detect'],
  's11_subtitle_render': ['s10_inpaint', 's09_subtitle_gen'],
  's12_tts': ['s08_translation', 's05b_gender_detect'],
  's13_audio_mix': ['s04_audio_separate', 's12_tts'],
  's14_encode': ['s11_subtitle_render', 's13_audio_mix'],
};

const Map<String, List<String>> stepArtifacts = {
  's01_probe': ['s01_probe.json', 's01_probe.done'],
  's02_demux': ['demux', 's02_demux.done'],
  's03_subtitle_detect': ['s03_subtitle_detect.done'],
  's04_audio_separate': ['audio_separated', 's04_audio_separate.done'],
  's05_asr': ['s05_asr.json', 's05_asr.done'],
  's05b_gender_detect': ['s05b_gender.json', 's05b_gender_detect.done'],
  's06_ocr': ['s06_ocr.json', 's06_ocr.done'],
  's07_transcript_merge': ['s07_transcript.json', 's07_transcript_merge.done'],
  's08_translation': ['s08_translation.json', 's08_translation.done'],
  's08b_metadata_gen': ['s08b_metadata.json', 's08b_metadata_gen.done'],
  's08c_timing': ['s08c_timing.json', 's08c_timing.done'],
  's09_subtitle_gen': ['subtitles.srt', 'subtitles_vi.srt', 'subtitles_vi.ass', 's09_subtitle_gen.done'],
  's10_inpaint': ['clean_video.mp4', 's10_inpaint.done'],
  's11_subtitle_render': ['video_with_subtitles.mp4', 'rendered_video.mp4', 's11_subtitle_render.done'],
  's12_tts': ['tts_segments', 'tts_audio.wav', 'translated_voice.wav', 's12_tts.done'],
  's13_audio_mix': ['mixed_audio.wav', 'final_mixed_audio.wav', 's13_audio_mix.done'],
  's14_encode': ['s14_encode.done'],
};

/// Finds targetStepId and all transitive downstream steps that depend on it.
List<String> getDownstreamSteps(String targetStepId) {
  if (!stepOrder.contains(targetStepId)) {
    return [targetStepId];
  }

  final affected = <String>{targetStepId};
  bool changed = true;
  while (changed) {
    changed = false;
    for (final entry in stepDependencies.entries) {
      final sId = entry.key;
      final deps = entry.value;
      if (!affected.contains(sId)) {
        if (deps.any((d) => affected.contains(d))) {
          affected.add(sId);
          changed = true;
        }
      }
    }
  }

  return stepOrder.where((s) => affected.contains(s)).toList();
}

/// Job State persistence and step execution cache manager.
class JobState {
  final Directory workspace;
  final String jobId;
  late final Directory jobDir;
  late final File stateFile;
  late Map<String, dynamic> data;

  JobState({
    required this.workspace,
    String? jobId,
    String? inputVideo,
    Map<String, dynamic>? config,
  }) : jobId = jobId ?? 'job_${DateTime.now().millisecondsSinceEpoch}' {
    jobDir = Directory(p.join(workspace.path, this.jobId));
    if (!jobDir.existsSync()) {
      jobDir.createSync(recursive: true);
    }
    stateFile = File(p.join(jobDir.path, 'state.json'));

    if (stateFile.existsSync()) {
      data = _load();
    } else {
      data = {
        'job_id': this.jobId,
        'input_video': inputVideo ?? '',
        'created_at': DateTime.now().toIso8601String(),
        'status': 'pending',
        'config': config ?? <String, dynamic>{},
        'steps': <String, dynamic>{},
      };
      _save();
    }
  }

  dynamic _normalizePaths(dynamic val) {
    if (val is String) {
      if (val.contains('/assets/') && !File(val).existsSync()) {
        final relIdx = val.indexOf('/assets/');
        final rel = val.substring(relIdx + 1);
        final resolved = File(p.join(Directory.current.path, rel));
        if (resolved.existsSync()) {
          return resolved.path;
        }
      }
      return val;
    } else if (val is Map) {
      return val.map((k, v) => MapEntry(k.toString(), _normalizePaths(v)));
    } else if (val is List) {
      return val.map(_normalizePaths).toList();
    }
    return val;
  }

  Map<String, dynamic> _load() {
    try {
      final content = stateFile.readAsStringSync();
      final parsed = jsonDecode(content) as Map<String, dynamic>;
      return _normalizePaths(parsed) as Map<String, dynamic>;
    } catch (_) {
      return {
        'job_id': jobId,
        'status': 'pending',
        'steps': <String, dynamic>{},
      };
    }
  }

  void _save() {
    data['updated_at'] = DateTime.now().toIso8601String();
    stateFile.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(data),
      flush: true,
    );
  }

  void setStepStatus(
    String stepId,
    String status, {
    Map<String, dynamic>? output,
    String? error,
  }) {
    data.putIfAbsent('steps', () => <String, dynamic>{});
    final stepsMap = data['steps'] as Map<String, dynamic>;
    stepsMap.putIfAbsent(stepId, () => <String, dynamic>{});
    final stepInfo = stepsMap[stepId] as Map<String, dynamic>;

    stepInfo['status'] = status;
    stepInfo['updated_at'] = DateTime.now().toIso8601String();
    if (output != null) {
      stepInfo['output'] = output;
    }
    if (error != null) {
      stepInfo['error'] = error;
    }

    _save();
  }

  Map<String, dynamic>? getStepOutput(String stepId) {
    final stepsMap = data['steps'] as Map<String, dynamic>?;
    final stepInfo = stepsMap?[stepId] as Map<String, dynamic>?;
    return stepInfo?['output'] as Map<String, dynamic>?;
  }

  bool isStepDone(String stepId) {
    final stepsMap = data['steps'] as Map<String, dynamic>?;
    final stepInfo = stepsMap?[stepId] as Map<String, dynamic>?;
    return stepInfo?['status'] == 'done';
  }

  void invalidateStep(String stepId) {
    final stepsMap = data['steps'] as Map<String, dynamic>?;
    if (stepsMap != null && stepsMap.containsKey(stepId)) {
      final stepInfo = stepsMap[stepId] as Map<String, dynamic>;
      stepInfo['status'] = 'pending';
      _save();
    }
    final doneFile = File(p.join(jobDir.path, '$stepId.done'));
    if (doneFile.existsSync()) {
      doneFile.deleteSync();
    }
  }

  /// Invalidates stepId and all downstream steps, deleting their artifacts.
  List<String> clearStep(String stepId, {bool deleteArtifacts = true}) {
    final affectedSteps = getDownstreamSteps(stepId);
    final stepsMap = data['steps'] as Map<String, dynamic>?;

    for (final sId in affectedSteps) {
      if (stepsMap != null && stepsMap.containsKey(sId)) {
        final stepInfo = stepsMap[sId] as Map<String, dynamic>;
        stepInfo['status'] = 'pending';
        stepInfo.remove('error');
      }

      final doneFile = File(p.join(jobDir.path, '$sId.done'));
      if (doneFile.existsSync()) {
        doneFile.deleteSync();
      }

      if (deleteArtifacts) {
        final arts = stepArtifacts[sId] ?? [];
        for (final art in arts) {
          final artPath = p.join(jobDir.path, art);
          if (FileSystemEntity.isDirectorySync(artPath)) {
            Directory(artPath).deleteSync(recursive: true);
          } else if (FileSystemEntity.isFileSync(artPath)) {
            File(artPath).deleteSync();
          }
        }
      }
    }

    data['status'] = 'pending';
    data.remove('error');
    _save();
    return affectedSteps;
  }

  bool deleteJob() {
    if (jobDir.existsSync()) {
      jobDir.deleteSync(recursive: true);
      return true;
    }
    return false;
  }

  void markCompleted() {
    data['status'] = 'completed';
    _save();
  }

  void markFailed(String error) {
    data['status'] = 'failed';
    data['error'] = error;
    _save();
  }
}
