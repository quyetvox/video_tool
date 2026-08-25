import '../models/app_config.dart';

/// Clean YAML Serializer for Sub-Video config.yaml
/// 1:1 Port of unifiedConfigToYaml from configSchema.js
class YamlConfigSerializer {
  static String _formatRegion(List<double>? r) {
    if (r == null || r.length != 4) return '';
    return r.map((e) => e.toStringAsFixed(2)).join(', ');
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

    final fontSizeLine = cfg.fontSize.trim().isNotEmpty
        ? '  font_size: ${cfg.fontSize.trim()}'
        : '  # font_size: 28';

    final wmRegionStr = (cfg.watermarkRegion.length == 4)
        ? '[${_formatRegion(cfg.watermarkRegion)}]'
        : '[0.02, 0.85, 0.05, 0.95]';

    final colorVal = (cfg.inpaintEngine == 'box_color' || cfg.inpaintEngine == 'boxColor')
        ? (cfg.boxBgColor.isNotEmpty ? cfg.boxBgColor : 'black')
        : 'transparent';

    return '''# ==============================================================================
# SUB-VIDEO PIPELINE CONFIGURATION
# ==============================================================================

# 1. ỨNG DỤNG & THIẾT BỊ (APP)
app:
  device: ${cfg.device}
  num_workers: ${cfg.numWorkers}
  target_lang: ${cfg.targetLang}
  secondary_lang: "${cfg.secondaryLang}"
  ocr_only: ${cfg.ocrOnly ? 'true' : 'false'}
  video_bitrate: "${cfg.videoBitrate}"
  output_suffix: "${cfg.outputSuffix}"

# 2. NHẬN DIỆN GIỌNG NÓI (ASR)
asr:
  engine: ${cfg.asrEngine}
  model: ${cfg.asrModel}

# 3. DỊCH THUẬT AI (TRANSLATOR)
translator:
  type: "${cfg.translatorType}"
  model: "${cfg.translatorModel}"
  api_key: "${cfg.translatorApiKey}"
  base_url: "${cfg.translatorBaseUrl}"
  batch_size: ${cfg.translatorBatchSize}

# 4. NHẬN DIỆN CHỮ SUB CŨ (OCR)
ocr:
  engine: ${cfg.ocrEngine}
  mode: ${cfg.ocrMode}
  diff_threshold: ${cfg.ocrDiffThreshold}
  diff_step: ${cfg.ocrDiffStep}
  detect_start_sec: ${cfg.detectStartSec}
  detect_duration_sec: ${cfg.detectDurationSec}

# 5. XÓA SUB CŨ & HỘP NỀN CHE (INPAINT)
inpaint:
  show_box: ${cfg.inpaintShowBox ? 'true' : 'false'}
  engine: ${cfg.inpaintEngine}
  method: "${cfg.inpaintMethod}"
  padding_y: ${cfg.inpaintPaddingY}
  color: "$colorVal"
  blur_radius: ${cfg.inpaintBlurRadius}
$inpaintRegionLine
  box:
    bg_color: "${cfg.boxBgColor}"
    bg_opacity: ${cfg.boxBgOpacity}
    border_color: "${cfg.boxBorderColor}"
    border_width: ${cfg.boxBorderWidth}
    border_radius: ${cfg.boxBorderRadius}

# 6. PHỤ ĐỀ MỚI (SUBTITLE)
subtitle:
  show: ${cfg.showSubtitle ? 'true' : 'false'}
  show_primary: ${cfg.subtitleShowPrimary ? 'true' : 'false'}
$subPrimaryRegionLine
  order: "${cfg.subtitleOrder}"
  box_split: ${cfg.boxSplit ? 'true' : 'false'}
  box_gap: ${cfg.boxGap}
  font_name: "${cfg.fontName}"
  fonts_dir: "${cfg.fontsDir}"
  font_color: "${cfg.fontColor}"
  outline_color: "${cfg.outlineColor}"
$fontSizeLine
  secondary:
    show: ${cfg.subtitleSecondaryShow ? 'true' : 'false'}
    font_name: "${cfg.subtitleSecondaryFontName}"
    font_size_scale: ${cfg.subtitleSecondaryFontScale}
    font_color: "${cfg.subtitleSecondaryFontColor}"
    outline_color: "${cfg.subtitleSecondaryOutlineColor}"
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
  image: "${cfg.watermarkType == 'image' ? cfg.watermarkImage : ''}"
  text: "${cfg.watermarkText}"
  font_name: "${cfg.watermarkFontName}"
  font_color: "${cfg.watermarkFontColor}"
  blur_bg: ${cfg.watermarkBlurBg ? 'true' : 'false'}
  opacity: ${cfg.watermarkOpacity}

# 8. THUYẾT MINH AI (TTS)
tts:
  engine: ${cfg.ttsEngine}
  voice: "${cfg.ttsVoice}"
  speed_factor: ${cfg.ttsSpeed}
  enable_gender: ${cfg.enableGenderTts ? 'true' : 'false'}
  voice_male: "${cfg.ttsVoiceMale}"
  voice_female: "${cfg.ttsVoiceFemale}"

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
  provider: "${cfg.storageProvider}"
  key_file: "${cfg.storageKeyFile}"
  bucket_name: "${cfg.storageBucketName}"
  base_prefix: "${cfg.storageBasePrefix}"
''';
  }
}
