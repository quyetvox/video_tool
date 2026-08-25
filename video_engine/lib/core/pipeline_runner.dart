import 'dart:io';
import 'package:path/path.dart' as p;
import 'config_adapter.dart';
import 'job_state.dart';
import 'step_base.dart';

/// Detailed configuration keys for Smart Invalidation per Step
const Map<String, List<String>> defaultStepConfigKeys = {
  's01_probe': ['duration'],
  's02_demux': ['duration'],
  's03_subtitle_detect': [
    'inpaint_region',
    'subtitle_detect_start_sec',
    'subtitle_detect_duration_sec',
  ],
  's04_audio_separate': [
    'device',
    'noise_reduction_strength',
    'ambient_split_threshold',
    'ocr_only',
  ],
  's05_asr': ['asr', 'asr_model', 'ocr_only'],
  's05b_gender_detect': ['enable_gender_tts', 'ocr_only'],
  's06_ocr': [
    'ocr',
    'ocr_mode',
    'diff_threshold',
    'diff_step',
    'ocr_only',
    'inpaint_region',
  ],
  's07_transcript_merge': [],
  's08_translation': [
    'translator',
    'translator_model',
    'target_lang',
    'secondary_lang',
  ],
  's08b_metadata_gen': [
    'enable_metadata_gen',
    'metadata_hashtags_count',
    'target_lang',
    'translator',
    'translator_model',
  ],
  's08c_timing': [
    'subtitle_char_rate',
    'subtitle_safety_margin',
    'subtitle_fill_gap',
    'subtitle_max_gap_fill',
  ],
  's09_subtitle_gen': [
    'show_subtitle',
    'inpaint_region',
    'subtitle_font_size',
    'subtitle_font_name',
    'subtitle_font_color',
    'subtitle_outline_color',
    'inpaint_box_bg_color',
    'inpaint_box_bg_opacity',
    'inpaint_box_border_color',
    'inpaint_box_border_width',
    'inpaint_box_border_radius',
    'subtitle_order',
    'subtitle_box_split',
    'subtitle_box_gap',
    'subtitle_box_lead_in',
    'subtitle_box_lead_out',
  ],
  's10_inpaint': [
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
  ],
  's11_subtitle_render': ['show_subtitle', 'video_bitrate'],
  's12_tts': [
    'tts',
    'tts_voice',
    'tts_voice_volume',
    'tts_speed_factor',
    'enable_gender_tts',
    'tts_voice_male',
    'tts_voice_female',
    'target_lang',
  ],
  's13_audio_mix': [
    'tts_voice',
    'music_volume',
    'ambient_volume',
    'tts_voice_volume',
    'original_voice_volume',
  ],
  's14_encode': ['output_suffix', 'output_dir', 'duration', 'video_bitrate'],
};

/// Robust comparison between old step config value and current active config value.
bool isConfigChanged(dynamic oldVal, dynamic newVal) {
  if (oldVal == newVal) return false;

  // Treat null, empty string, empty list, empty map as equivalent
  final isOldEmpty = oldVal == null || oldVal == '' || (oldVal is Iterable && oldVal.isEmpty) || (oldVal is Map && oldVal.isEmpty);
  final isNewEmpty = newVal == null || newVal == '' || (newVal is Iterable && newVal.isEmpty) || (newVal is Map && newVal.isEmpty);
  if (isOldEmpty && isNewEmpty) return false;

  // Numeric comparisons with epsilon
  if (oldVal is num && newVal is num) {
    return (oldVal.toDouble() - newVal.toDouble()).abs() > 1e-5;
  }

  // String <-> Boolean comparison (e.g. "true" == true)
  if (oldVal is String && newVal is bool) {
    return (oldVal.toLowerCase() == 'true') != newVal;
  }
  if (newVal is String && oldVal is bool) {
    return (newVal.toLowerCase() == 'true') != oldVal;
  }

  // List comparison
  if (oldVal is List && newVal is List) {
    if (oldVal.length != newVal.length) return true;
    for (int i = 0; i < oldVal.length; i++) {
      if (isConfigChanged(oldVal[i], newVal[i])) return true;
    }
    return false;
  }

  // Map comparison
  if (oldVal is Map && newVal is Map) {
    if (oldVal.length != newVal.length) return true;
    for (final key in oldVal.keys) {
      if (!newVal.containsKey(key)) return true;
      if (isConfigChanged(oldVal[key], newVal[key])) return true;
    }
    return false;
  }

  return oldVal != newVal;
}

typedef PipelineLogCallback = void Function(String stepId, String message, {String type});
typedef StepStatusCallback = void Function(String stepId, String status, double progress);

/// Core pipeline orchestrator with Smart Invalidation & Cascade File Modification checks.
class PipelineRunner {
  final List<StepBase> steps;
  final PipelineLogCallback? onLog;
  final StepStatusCallback? onStepStatus;

  PipelineRunner({
    required this.steps,
    this.onLog,
    this.onStepStatus,
  });

  void _log(String stepId, String msg, {String type = 'info'}) {
    onLog?.call(stepId, msg, type: type);
  }

  /// Runs all pipeline steps for the given job.
  Future<bool> run(JobState jobState, ConfigDict config) async {
    _log('pipeline', 'Bắt đầu xử lý cho Job: ${jobState.jobId}');

    // 1. Smart Config Change Detection & Global Manual Edit Invalidation
    final invalidatedSteps = <String>{};
    final stepsMap = jobState.data['steps'] as Map<String, dynamic>? ?? {};
    final isOcrOnly = config.get('ocr_only') == true || config.get('ocr_only')?.toString().toLowerCase() == 'true';

    // Check if s08_translation.json was manually edited by comparing its mtime to s08_translation step updated_at
    bool isTranslationManuallyEdited = false;
    final transStepInfo = stepsMap['s08_translation'] as Map<String, dynamic>? ?? {};
    final transStepUpdated = transStepInfo['updated_at'] as String?;
    if (transStepUpdated != null) {
      final transFile = File(p.join(jobState.jobDir.path, 's08_translation.json'));
      if (transFile.existsSync()) {
        final transFileTs = transFile.lastModifiedSync().millisecondsSinceEpoch;
        final transStepTs = DateTime.parse(transStepUpdated).millisecondsSinceEpoch;
        if (transFileTs > transStepTs + 100) {
          isTranslationManuallyEdited = true;
          _log('s08_translation', '📝 Phát hiện file s08_translation.json được chỉnh sửa thủ công.', type: 'info');
        }
      }
    }

    // Check if s07_transcript.json was manually edited
    bool isTranscriptManuallyEdited = false;
    final mergeStepInfo = stepsMap['s07_transcript_merge'] as Map<String, dynamic>? ?? {};
    final mergeStepUpdated = mergeStepInfo['updated_at'] as String?;
    if (mergeStepUpdated != null) {
      final mergeFile = File(p.join(jobState.jobDir.path, 's07_transcript.json'));
      if (mergeFile.existsSync()) {
        final mergeFileTs = mergeFile.lastModifiedSync().millisecondsSinceEpoch;
        final mergeStepTs = DateTime.parse(mergeStepUpdated).millisecondsSinceEpoch;
        if (mergeFileTs > mergeStepTs + 100) {
          isTranscriptManuallyEdited = true;
          _log('s07_transcript_merge', '📝 Phát hiện file s07_transcript.json được chỉnh sửa thủ công.', type: 'info');
        }
      }
    }

    for (final step in steps) {
      final stepId = step.stepId;
      final relevantKeys = step.stepConfigKeys.isNotEmpty
          ? step.stepConfigKeys
          : (defaultStepConfigKeys[stepId] ?? const []);

      final depInvalidated = step.dependsOn.any((dep) => invalidatedSteps.contains(dep));
      final oldStepInfo = stepsMap[stepId] as Map<String, dynamic>? ?? {};
      final oldStepCfg = oldStepInfo['config'] as Map<String, dynamic>? ?? {};

      bool configChanged = false;
      String changedKeyName = '';

      for (final k in relevantKeys) {
        final oldVal = oldStepCfg[k];
        final newVal = config.get(k);
        if (isConfigChanged(oldVal, newVal)) {
          configChanged = true;
          changedKeyName = k;
          break;
        }
      }

      String? fileModifiedReason;

      // 1. Global manual edit triggers
      if (isTranscriptManuallyEdited && const [
        's08_translation',
        's08b_metadata_gen',
        's08c_timing',
        's09_subtitle_gen',
        's11_subtitle_render',
        's12_tts',
        's13_audio_mix',
        's14_encode'
      ].contains(stepId)) {
        fileModifiedReason = "phát hiện tệp 's07_transcript.json' được chỉnh sửa thủ công";
      }

      final affectedByTrans = isOcrOnly
          ? const ['s08c_timing', 's09_subtitle_gen', 's11_subtitle_render', 's14_encode']
          : const ['s08c_timing', 's09_subtitle_gen', 's11_subtitle_render', 's12_tts', 's13_audio_mix', 's14_encode'];

      if (fileModifiedReason == null && isTranslationManuallyEdited && affectedByTrans.contains(stepId)) {
        fileModifiedReason = "phát hiện tệp 's08_translation.json' được chỉnh sửa thủ công";
      }

      // 2. Direct dependency artifact mtime checks
      final stepUpdatedAtStr = oldStepInfo['updated_at'] as String?;
      if (fileModifiedReason == null && stepUpdatedAtStr != null && !depInvalidated) {
        try {
          final stepDt = DateTime.parse(stepUpdatedAtStr);
          final stepTs = stepDt.millisecondsSinceEpoch;

          for (final dep in step.dependsOn) {
            final depOut = jobState.getStepOutput(dep) ?? {};
            for (final val in depOut.values) {
              if (val is String && (val.endsWith('.json') || val.endsWith('.srt') || val.endsWith('.ass') || val.endsWith('.wav') || val.endsWith('.mp4'))) {
                File pFile = File(val);
                if (!pFile.isAbsolute) {
                  pFile = File(p.join(jobState.jobDir.path, val));
                }
                if (pFile.existsSync() && pFile.lastModifiedSync().millisecondsSinceEpoch > stepTs + 100) {
                  fileModifiedReason = "phát hiện tệp '${p.basename(val)}' được chỉnh sửa thủ công";
                  break;
                }
              }
            }
            if (fileModifiedReason != null) break;
          }
        } catch (_) {}
      }

      if (configChanged || depInvalidated || fileModifiedReason != null) {
        if (jobState.isStepDone(stepId)) {
          String reason;
          if (configChanged) {
            reason = "cấu hình '$changedKeyName' thay đổi (${oldStepCfg[changedKeyName]} -> ${config.get(changedKeyName)})";
          } else if (fileModifiedReason != null) {
            reason = fileModifiedReason;
          } else {
            reason = 'bước trước đó đã được cập nhật';
          }

          _log(stepId, '↺ Tự động hủy cache bước $stepId ($reason)', type: 'warning');
          jobState.invalidateStep(stepId);
        }
        invalidatedSteps.add(stepId);
      }
    }

    // 3. Step Execution Loop
    for (int i = 0; i < steps.length; i++) {
      final step = steps[i];
      final stepId = step.stepId;
      final relevantKeys = step.stepConfigKeys.isNotEmpty
          ? step.stepConfigKeys
          : (defaultStepConfigKeys[stepId] ?? const []);

      // Check dependencies
      for (final dep in step.dependsOn) {
        if (!jobState.isStepDone(dep)) {
          final errorMsg = "Bước '$stepId' phụ thuộc vào '$dep' chưa hoàn tất.";
          _log(stepId, '❌ $errorMsg', type: 'error');
          jobState.markFailed(errorMsg);
          return false;
        }
      }

      // Check if step can be skipped
      if (step.canSkip(jobState.jobDir) && jobState.isStepDone(stepId)) {
        _log(stepId, '✓ $stepId (đã cache)', type: 'cached');
        onStepStatus?.call(stepId, 'done', 1.0);
        continue;
      }

      _log(stepId, '→ Đang thực thi $stepId...', type: 'running');
      jobState.setStepStatus(stepId, 'running');
      onStepStatus?.call(stepId, 'running', 0.1);

      try {
        final output = await step.run(jobState.jobDir, config, jobState);
        step.markDone(jobState.jobDir);

        final stepCfgSnapshot = <String, dynamic>{};
        for (final k in relevantKeys) {
          final v = config.get(k);
          if (v != null) {
            stepCfgSnapshot[k] = v;
          }
        }

        jobState.data.putIfAbsent('steps', () => <String, dynamic>{});
        final stepsMap = jobState.data['steps'] as Map<String, dynamic>;
        stepsMap.putIfAbsent(stepId, () => <String, dynamic>{});
        final stepInfo = stepsMap[stepId] as Map<String, dynamic>;
        stepInfo['config'] = stepCfgSnapshot;

        jobState.setStepStatus(stepId, 'done', output: output);
        _log(stepId, '✓ $stepId hoàn thành thành công!', type: 'success');
        onStepStatus?.call(stepId, 'done', 1.0);
      } catch (e, st) {
        final errorMsg = "Bước '$stepId' gặp lỗi: $e";
        _log(stepId, '❌ $errorMsg\n$st', type: 'error');
        jobState.setStepStatus(stepId, 'failed', error: errorMsg);
        jobState.markFailed(errorMsg);
        onStepStatus?.call(stepId, 'failed', 0.0);
        return false;
      }
    }

    jobState.markCompleted();
    _log('pipeline', '🎉 Đã hoàn tất toàn bộ pipeline cho Job ${jobState.jobId}!', type: 'success');
    return true;
  }
}
