import '../models/app_config.dart';

/// Clean YAML Serializer for Sub-Video config.yaml
/// 1:1 Port of unifiedConfigToYaml from configSchema.js
class YamlConfigSerializer {
  static String _formatRegion(List<double>? r) {
    if (r == null || r.length != 4) return '';
    return r.map((e) => e.toStringAsFixed(2)).join(', ');
  }

  static String _cleanStr(String? s) {
    if (s == null) return '';
    var str = s.trim();
    // Strip trailing inline comments (separated by whitespace from the value)
    str = str.replaceFirst(RegExp(r'\s+#.*$'), '').trim();
    while ((str.startsWith('"') && str.endsWith('"')) ||
        (str.startsWith("'") && str.endsWith("'"))) {
      if (str.length >= 2) {
        str = str.substring(1, str.length - 1).trim();
      } else {
        break;
      }
    }
    return str;
  }

  static String serialize(AppConfig cfg) {
    final inpaintRegionLine = (cfg.inpaintRegion != null && cfg.inpaintRegion!.length == 4)
        ? '  region: [${_formatRegion(cfg.inpaintRegion)}]'
        : '  # region: [0.12, 0.05, 0.22, 0.95]';

    final subPrimaryRegionLine = (cfg.subtitleRegion != null && cfg.subtitleRegion!.length == 4)
        ? '  region: [${_formatRegion(cfg.subtitleRegion)}]'
        : '  # region: [0.75, 0.05, 0.95, 0.95]';

    final subSecRegionLine = (cfg.subtitleSecondaryRegion != null && cfg.subtitleSecondaryRegion!.length == 4)
        ? '    region: [${_formatRegion(cfg.subtitleSecondaryRegion)}]'
        : '    # region: [0.03, 0.05, 0.12, 0.95]';

    final cleanFontSize = _cleanStr(cfg.fontSize);
    final fontSizeLine = cleanFontSize.isNotEmpty
        ? '  font_size: $cleanFontSize'
        : '  # font_size: 28';

    final wmRegionStr = (cfg.watermarkRegion.length == 4)
        ? '[${_formatRegion(cfg.watermarkRegion)}]'
        : '[0.02, 0.85, 0.05, 0.95]';

    final cleanBoxBg = _cleanStr(cfg.boxBgColor);
    final colorVal = (cfg.inpaintEngine == 'box_color' || cfg.inpaintEngine == 'boxColor')
        ? (cleanBoxBg.isNotEmpty ? cleanBoxBg : 'black')
        : 'transparent';

    return '''# ==============================================================================
# SUB-VIDEO PIPELINE CONFIGURATION
# ==============================================================================

# 1. ỨNG DỤNG & THIẾT BỊ (APP)
app:
  device: ${_cleanStr(cfg.device)}
  num_workers: ${cfg.numWorkers}
  target_lang: ${_cleanStr(cfg.targetLang)}
  secondary_lang: "${_cleanStr(cfg.secondaryLang)}"
  ocr_only: ${cfg.ocrOnly ? 'true' : 'false'}
  video_bitrate: "${_cleanStr(cfg.videoBitrate)}"
  output_suffix: "${_cleanStr(cfg.outputSuffix)}"

# 2. NHẬN DIỆN GIỌNG NÓI (ASR)
asr:
  engine: ${_cleanStr(cfg.asrEngine)}
  model: ${_cleanStr(cfg.asrModel)}

# 3. DỊCH THUẬT AI (TRANSLATOR)
translator:
  type: "${_cleanStr(cfg.translatorType)}"
  model: "${_cleanStr(cfg.translatorModel)}"
  api_key: "${_cleanStr(cfg.translatorApiKey)}"
  base_url: "${_cleanStr(cfg.translatorBaseUrl)}"
  batch_size: ${cfg.translatorBatchSize}
  pronoun_mode: "${_cleanStr(cfg.pronounMode)}"
  custom_pronoun_prompt: "${_cleanStr(cfg.customPronounPrompt)}"

# 4. NHẬN DIỆN CHỮ SUB CŨ (OCR)
ocr:
  engine: ${_cleanStr(cfg.ocrEngine)}
  mode: ${_cleanStr(cfg.ocrMode)}
  diff_threshold: ${cfg.ocrDiffThreshold}
  diff_step: ${cfg.ocrDiffStep}
  detect_start_sec: ${cfg.detectStartSec}
  detect_duration_sec: ${cfg.detectDurationSec}

# 5. XÓA SUB CŨ & HỘP NỀN CHE (INPAINT)
inpaint:
  show_box: ${cfg.inpaintShowBox ? 'true' : 'false'}
  engine: ${_cleanStr(cfg.inpaintEngine)}
  method: "${_cleanStr(cfg.inpaintMethod)}"
  padding_y: ${cfg.inpaintPaddingY}
  color: "$colorVal"
  blur_radius: ${cfg.inpaintBlurRadius}
$inpaintRegionLine
  box:
    bg_color: "$cleanBoxBg"
    bg_opacity: ${cfg.boxBgOpacity}
    border_color: "${_cleanStr(cfg.boxBorderColor)}"
    border_width: ${cfg.boxBorderWidth}
    border_radius: ${cfg.boxBorderRadius}

# 6. PHỤ ĐỀ MỚI (SUBTITLE)
subtitle:
  show: ${cfg.showSubtitle ? 'true' : 'false'}
  show_primary: ${cfg.subtitleShowPrimary ? 'true' : 'false'}
$subPrimaryRegionLine
  order: "${_cleanStr(cfg.subtitleOrder)}"
  box_split: ${cfg.boxSplit ? 'true' : 'false'}
  box_gap: ${cfg.boxGap}
  font_name: "${_cleanStr(cfg.fontName)}"
  fonts_dir: "${_cleanStr(cfg.fontsDir)}"
  font_color: "${_cleanStr(cfg.fontColor)}"
  outline_color: "${_cleanStr(cfg.outlineColor)}"
$fontSizeLine
  secondary:
    show: ${cfg.subtitleSecondaryShow ? 'true' : 'false'}
    font_name: "${_cleanStr(cfg.subtitleSecondaryFontName)}"
    font_size_scale: ${cfg.subtitleSecondaryFontScale}
    font_color: "${_cleanStr(cfg.subtitleSecondaryFontColor)}"
    outline_color: "${_cleanStr(cfg.subtitleSecondaryOutlineColor)}"
$subSecRegionLine
  char_rate: ${cfg.charRate}
  safety_margin: ${cfg.safetyMargin}
  fill_gap: ${cfg.fillGap ? 'true' : 'false'}
  max_gap_fill: ${cfg.maxGapFill}
  box_lead_in: ${cfg.boxLeadIn}
  box_lead_out: ${cfg.boxLeadOut}

# 7. WATERMARK & BRANDING
watermark:
  enabled: ${cfg.watermarkEnabled ? 'true' : 'false'}
  region: $wmRegionStr
  image: "${cfg.watermarkType == 'image' ? _cleanStr(cfg.watermarkImage) : ''}"
  text: "${_cleanStr(cfg.watermarkText)}"
  font_name: "${_cleanStr(cfg.watermarkFontName)}"
  font_color: "${_cleanStr(cfg.watermarkFontColor)}"
  blur_bg: ${cfg.watermarkBlurBg ? 'true' : 'false'}
  opacity: ${cfg.watermarkOpacity}

# 8. THUYẾT MINH AI (TTS)
tts:
  engine: ${_cleanStr(cfg.ttsEngine)}
  voice: "${_cleanStr(cfg.ttsVoice)}"
  speed_factor: ${cfg.ttsSpeed}
  delay_sec: ${cfg.ttsDelay}
  enable_gender: ${cfg.enableGenderTts ? 'true' : 'false'}
  voice_male: "${_cleanStr(cfg.ttsVoiceMale)}"
  voice_female: "${_cleanStr(cfg.ttsVoiceFemale)}"

# 9. ÂM LƯỢNG & BỘ LỌC ÂM THANH (AUDIO)
audio:
  volumes:
    tts_voice: ${cfg.ttsVol}
    original_voice: ${cfg.origVoiceVol}
    music: ${cfg.musicVol}
    ambient: ${cfg.ambientVol}
  filters:
    noise_reduction_strength: ${cfg.noiseReductionStrength}
    ambient_split_threshold: ${cfg.ambientSplitThreshold}

# 10. CLOUD STORAGE (GOOGLE CLOUD STORAGE)
storage:
  enabled: ${cfg.storageEnabled ? 'true' : 'false'}
  provider: "${_cleanStr(cfg.storageProvider)}"
  key_file: "${_cleanStr(cfg.storageKeyFile)}"
  bucket_name: "${_cleanStr(cfg.storageBucketName)}"
  base_prefix: "${_cleanStr(cfg.storageBasePrefix)}"
''';
  }
}
