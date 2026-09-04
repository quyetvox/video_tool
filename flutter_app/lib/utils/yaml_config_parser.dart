import 'dart:io';
import '../models/app_config.dart';

/// Robust YAML Parser for Sub-Video config.yaml
/// 1:1 Port of parseYamlRobust and parseYamlToUnifiedConfig from configSchema.js
class YamlConfigParser {
  static Map<String, dynamic> parseYamlRobust(String yamlStr) {
    if (yamlStr.trim().isEmpty) return {};
    final lines = yamlStr.split('\n');
    final Map<String, dynamic> result = {};
    String? currentSection;
    String? currentSubSection;
    int subIndent = 0;

    for (var line in lines) {
      final rawLine = line;
      final trimmed = line.trim();

      if (trimmed.isEmpty || trimmed.startsWith('#')) {
        // Check commented region like # region: [0.12, 0.05, 0.22, 0.95]
        final commentMatch = RegExp(r'^#\s*([a-zA-Z0-9_-]+):(?:\s*(.*))?$').firstMatch(trimmed);
        if (commentMatch != null && currentSection != null) {
          final key = commentMatch.group(1);
          if (key == 'region' && result[currentSection] is Map) {
            final secMap = result[currentSection] as Map<String, dynamic>;
            if (!secMap.containsKey('region')) {
              secMap['region'] = null;
            }
          }
        }
        continue;
      }

      final indent = rawLine.indexOf(RegExp(r'\S'));
      if (indent < 0) continue;

      // Section header (indent 0)
      final sectionMatch = RegExp(r'^([a-zA-Z0-9_-]+):\s*$').firstMatch(line);
      if (sectionMatch != null && indent == 0) {
        currentSection = sectionMatch.group(1);
        currentSubSection = null;
        if (currentSection != null && !result.containsKey(currentSection)) {
          result[currentSection] = <String, dynamic>{};
        }
        continue;
      }

      // Key-value pair
      final kvMatch = RegExp(r'^([a-zA-Z0-9_-]+):(?:\s*(.*))?$').firstMatch(trimmed);
      if (kvMatch != null && currentSection != null) {
        final key = kvMatch.group(1)!;
        final valStr = kvMatch.group(2) != null ? kvMatch.group(2)!.trim() : '';

        final secMap = result[currentSection] as Map<String, dynamic>;

        if (valStr.isEmpty && indent > 0) {
          currentSubSection = key;
          subIndent = indent;
          if (!secMap.containsKey(key)) {
            secMap[key] = <String, dynamic>{};
          }
        } else {
          dynamic val;
          if (valStr.startsWith('"') || valStr.startsWith("'")) {
            final quoteChar = valStr[0];
            final leadingQuotesPattern = RegExp('^${RegExp.escape(quoteChar)}+');
            final stripped = valStr.replaceFirst(leadingQuotesPattern, '');
            final endIdx = stripped.indexOf(quoteChar);
            if (endIdx != -1) {
              val = stripped.substring(0, endIdx);
            } else {
              final withoutComment = stripped.replaceFirst(RegExp(r'\s+#.*$'), '').trim();
              val = withoutComment.replaceAll(quoteChar, '');
            }
          } else if (valStr.startsWith('[')) {
            final endBracket = valStr.lastIndexOf(']');
            final arrayStr = endBracket != -1
                ? valStr.substring(0, endBracket + 1)
                : valStr.replaceFirst(RegExp(r'\s+#.*$'), '').trim();
            if (arrayStr.startsWith('[') && arrayStr.endsWith(']')) {
              final inner = arrayStr.substring(1, arrayStr.length - 1);
              final parts = inner
                  .split(',')
                  .map((s) => s.trim())
                  .where((s) => s.isNotEmpty)
                  .toList();
              val = parts.map((s) {
                final numVal = num.tryParse(s);
                return numVal != null ? numVal.toDouble() : s;
              }).toList();
            } else {
              val = arrayStr;
            }
          } else {
            final cleanValStr = valStr.replaceFirst(RegExp(r'\s+#.*$'), '').trim();
            if (cleanValStr == 'true') {
              val = true;
            } else if (cleanValStr == 'false') {
              val = false;
            } else if (cleanValStr == 'null' || cleanValStr == '~') {
              val = null;
            } else if (num.tryParse(cleanValStr) != null && cleanValStr.isNotEmpty) {
              val = num.parse(cleanValStr);
            } else {
              val = cleanValStr;
            }
          }

          if (currentSubSection != null && indent > subIndent && secMap[currentSubSection] is Map) {
            (secMap[currentSubSection] as Map<String, dynamic>)[key] = val;
          } else {
            currentSubSection = null;
            secMap[key] = val;
          }
        }
      }
    }
    return result;
  }

  static AppConfig parse(String yamlStr) {
    final y = parseYamlRobust(yamlStr);
    if (y.isEmpty) return AppConfig.defaults();

    final app = (y['app'] as Map<String, dynamic>?) ?? {};
    final asr = (y['asr'] as Map<String, dynamic>?) ?? {};
    final sub = (y['subtitle'] as Map<String, dynamic>?) ?? {};
    final subSec = (sub['secondary'] as Map<String, dynamic>?) ?? {};
    final inp = (y['inpaint'] as Map<String, dynamic>?) ?? {};
    final box = (inp['box'] as Map<String, dynamic>?) ?? (sub['box'] as Map<String, dynamic>?) ?? {};
    final wm = (y['watermark'] as Map<String, dynamic>?) ?? {};
    final tts = (y['tts'] as Map<String, dynamic>?) ?? {};
    final audio = (y['audio'] as Map<String, dynamic>?) ?? {};
    final vols = (audio['volumes'] as Map<String, dynamic>?) ?? {};
    final filters = (audio['filters'] as Map<String, dynamic>?) ?? {};
    final trans = (y['translator'] as Map<String, dynamic>?) ?? {};
    final ocr = (y['ocr'] as Map<String, dynamic>?) ?? {};
    final storage = (y['storage'] as Map<String, dynamic>?) ?? {};
    final longVid = (y['long_video'] as Map<String, dynamic>?) ?? {};

    List<double>? parseRegion(dynamic val) {
      if (val is List && val.length == 4) {
        try {
          return val.map((e) => (e as num).toDouble()).toList();
        } catch (_) {
          return null;
        }
      }
      return null;
    }

    final inpaintRegion = parseRegion(inp['region'] ?? y['inpaint_region']);
    final wmRegion = parseRegion(wm['region']) ?? [0.02, 0.85, 0.05, 0.95];
    final subRegion = parseRegion(sub['region']);
    final subSecRegion = parseRegion(subSec['region']);

    // Robust numeric helpers: accept both num and String from YAML
    double toDouble(dynamic val, double fallback) {
      if (val == null) return fallback;
      if (val is num) return val.toDouble();
      return double.tryParse(val.toString()) ?? fallback;
    }

    int toInt(dynamic val, int fallback) {
      if (val == null) return fallback;
      if (val is num) return val.toInt();
      return int.tryParse(val.toString()) ?? fallback;
    }

    String computeWmPos(List<double> region) {
      if (region.length != 4) return 'top-right';
      final top = region[0];
      final left = region[1];
      if (top < 0.2 && left > 0.6) return 'top-right';
      if (top < 0.2 && left < 0.2) return 'top-left';
      if (top > 0.7 && left < 0.2) return 'bottom-left';
      if (top > 0.7 && left > 0.6) return 'bottom-right';
      return 'top-right';
    }

    return AppConfig(
      // App
      device: app['device']?.toString() ?? 'auto',
      numWorkers: app['num_workers']?.toString() ?? ocr['num_workers']?.toString() ?? tts['num_workers']?.toString() ?? 'auto',
      targetLang: app['target_lang']?.toString() ?? 'vi',
      secondaryLang: app['secondary_lang']?.toString() ?? '',
      ocrOnly: app['ocr_only'] is bool ? app['ocr_only'] as bool : false,
      videoBitrate: app['video_bitrate']?.toString() ?? '4.0M',
      outputSuffix: app['output_suffix']?.toString() ?? '_vi',
      batchCooldownSec: app['batch_cooldown_sec']?.toString() ?? 'auto',

      // Inpaint & SubBox
      inpaintShowBox: inp['show_box'] != null
          ? (inp['show_box'] is bool
              ? inp['show_box'] as bool
              : inp['show_box'].toString().toLowerCase() == 'true')
          : true,
      inpaintEngine: () {
        final eng = inp['engine']?.toString();
        if (Platform.isWindows && (eng == null || eng == 'apple_vision_inpaint')) {
          return 'ffmpeg_blur';
        }
        return eng ?? 'apple_vision_inpaint';
      }(),
      inpaintMethod: inp['method']?.toString() ?? 'vertical_gradient',
      inpaintPaddingY: toDouble(inp['padding_y'], 0.02),
      inpaintColor: inp['color']?.toString() ?? 'transparent',
      inpaintBlurRadius: toInt(inp['blur_radius'], 15),
      inpaintRegion: inpaintRegion,
      boxBgColor: box['bg_color']?.toString() ?? inp['bg_color']?.toString() ?? 'black',
      boxBgOpacity: toDouble(box['bg_opacity'] ?? inp['bg_opacity'], 0.75),
      boxBorderColor: box['border_color']?.toString() ?? inp['border_color']?.toString() ?? '&H40FFFFFF',
      boxBorderWidth: toInt(box['border_width'] ?? inp['border_width'], 2),
      boxBorderRadius: toInt(box['border_radius'] ?? inp['border_radius'], 8),

      // Subtitle Primary
      showSubtitle: sub['show'] is bool ? sub['show'] as bool : true,
      subtitleShowPrimary: sub['show_primary'] is bool ? sub['show_primary'] as bool : true,
      subtitleRegion: subRegion,
      fontName: sub['font_name']?.toString() ?? 'Arial',
      fontSize: sub['font_size'] != null ? sub['font_size'].toString() : '',
      fontsDir: sub['fonts_dir']?.toString() ?? app['fonts_dir']?.toString() ?? 'resources/fonts',
      fontColor: sub['font_color']?.toString() ?? '&H00FFFFFF',
      outlineColor: sub['outline_color']?.toString() ?? '&H00000000',
      charRate: toDouble(sub['char_rate'], 0.07),
      safetyMargin: toDouble(sub['safety_margin'], 0.15),
      fillGap: sub['fill_gap'] is bool ? sub['fill_gap'] as bool : true,
      maxGapFill: toDouble(sub['max_gap_fill'], 0.8),
      boxLeadIn: toDouble(sub['box_lead_in'], 0.25),
      boxLeadOut: toDouble(sub['box_lead_out'], 0.15),

      // Subtitle Secondary
      subtitleSecondaryShow: subSec['show'] is bool ? subSec['show'] as bool : (app['secondary_lang']?.toString().isNotEmpty ?? false),
      subtitleOrder: sub['order']?.toString() ?? 'primary_top',
      boxSplit: sub['box_split'] is bool ? sub['box_split'] as bool : true,
      boxGap: toInt(sub['box_gap'], 8),
      subtitleSecondaryFontName: subSec['font_name']?.toString() ?? '',
      subtitleSecondaryFontScale: toDouble(subSec['font_size_scale'], 0.75),
      subtitleSecondaryFontColor: subSec['font_color']?.toString() ?? '&H00D0D0D0',
      subtitleSecondaryOutlineColor: subSec['outline_color']?.toString() ?? '&H00000000',
      subtitleSecondaryRegion: subSecRegion,

      // Watermark
      watermarkEnabled: wm['enabled'] is bool ? wm['enabled'] as bool : false,
      watermarkType: wm['image'] != null && wm['image'].toString().isNotEmpty ? 'image' : 'text',
      watermarkText: wm['text']?.toString() ?? 'Sub-Video AI',
      watermarkImage: wm['image']?.toString() ?? '',
      watermarkFontName: wm['font_name']?.toString() ?? 'Arial',
      watermarkFontColor: wm['font_color']?.toString() ?? 'white',
      watermarkBlurBg: wm['blur_bg'] is bool ? wm['blur_bg'] as bool : true,
      watermarkOpacity: toDouble(wm['opacity'], 0.85),
      watermarkRegion: wmRegion,
      watermarkPosition: computeWmPos(wmRegion),

      // TTS
      ttsEngine: tts['engine']?.toString() ?? 'preset',
      ttsVoice: () {
        final v = tts['voice']?.toString() ?? 'vi-VN-BanMai';
        if (v.toLowerCase() == 'vi' || v.toLowerCase() == 'banmai') return 'vi-VN-BanMai';
        return v;
      }(),
      ttsSpeed: toDouble(tts['speed_factor'], 1.5),
      ttsDelay: toDouble(tts['delay_sec'], 0.25),
      ttsNumWorkers: tts['num_workers']?.toString() ?? 'auto',
      enableGenderTts: tts['enable_gender'] is bool ? tts['enable_gender'] as bool : false,
      ttsVoiceMale: tts['voice_male']?.toString() ?? 'vi-VN-NamMinhNeural',
      ttsVoiceFemale: () {
        final v = tts['voice_female']?.toString() ?? 'vi-VN-HoaiMyNeural';
        if (v.toLowerCase() == 'vi' || v.toLowerCase() == 'banmai') return 'vi-VN-BanMai';
        return v;
      }(),

      // Audio
      ttsVol: toDouble(vols['tts_voice'], 1.0),
      origVoiceVol: toDouble(vols['original_voice'], 0.05),
      musicVol: toDouble(vols['music'], 0.5),
      ambientVol: toDouble(vols['ambient'], 0.75),
      noiseReductionStrength: toDouble(filters['noise_reduction_strength'], 0.9),
      ambientSplitThreshold: toDouble(filters['ambient_split_threshold'], 0.3),

      // ASR & OCR
      asrEngine: () {
        final eng = asr['engine']?.toString();
        if (Platform.isWindows && (eng == null || eng == 'mlx-whisper')) {
          return 'whisper';
        }
        return eng ?? 'mlx-whisper';
      }(),
      asrModel: asr['model']?.toString() ?? 'auto',
      ocrEngine: () {
        final eng = ocr['engine']?.toString();
        if (Platform.isWindows && (eng == null || eng == 'apple_vision')) {
          return 'paddle_ocr';
        }
        return eng ?? 'apple_vision';
      }(),
      ocrNumWorkers: ocr['num_workers']?.toString() ?? 'auto',
      ocrMode: ocr['mode']?.toString() ?? 'region',
      ocrDiffThreshold: toDouble(ocr['diff_threshold'], 8.0),
      ocrDiffStep: toInt(ocr['diff_step'], 2),
      detectStartSec: toDouble(ocr['detect_start_sec'], 5.0),
      detectDurationSec: toDouble(ocr['detect_duration_sec'], 10.0),

      // Translator
      translatorType: trans['type']?.toString() ?? 'ollama',
      translatorModel: trans['model']?.toString() ?? 'gemma4:31b-cloud',
      translatorApiKey: trans['api_key']?.toString() ?? '',
      translatorBaseUrl: trans['base_url']?.toString() ?? 'http://localhost:11434',
      translatorBatchSize: toInt(trans['batch_size'], 20),
      pronounMode: trans['pronoun_mode']?.toString() ?? 'dynamic',
      customPronounPrompt: trans['custom_pronoun_prompt']?.toString() ?? '',

      // Storage
      storageEnabled: storage['enabled'] is bool ? storage['enabled'] as bool : true,
      storageProvider: storage['provider']?.toString() ?? 'gcs',
      storageKeyFile: storage['key_file']?.toString() ?? 'resources/gcs-key.json',
      storageBucketName: storage['bucket_name']?.toString() ?? 'service-qa-beta',
      storageBasePrefix: storage['base_prefix']?.toString() ?? 'video-tiktok-volumn',

      // Long Video & Smart Chunking
      longVideoEnabled: longVid['enabled'] is bool ? longVid['enabled'] as bool : false,
      longVideoChunkDurationMin: toDouble(longVid['chunk_duration_min'], 2.0),
    );
  }
}
