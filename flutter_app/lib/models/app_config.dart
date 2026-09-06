/// Unified App Configuration Model for Sub-Video
/// Single Source of Truth matching config.yaml and configSchema.js
class AppConfig {
  // 1. App
  final String device;
  final String numWorkers;
  final String targetLang;
  final String secondaryLang;
  final bool ocrOnly;
  final String videoBitrate;
  final String outputSuffix;
  final String batchCooldownSec;

  // 2. Inpaint & SubBox
  final bool inpaintShowBox;
  final String inpaintEngine;
  final String inpaintMethod;
  final double inpaintPaddingY;
  final String inpaintColor;
  final int inpaintBlurRadius;
  final List<double>? inpaintRegion; // [top, left, bottom, right] or null for auto
  final String boxBgColor;
  final double boxBgOpacity;
  final String boxBorderColor;
  final int boxBorderWidth;
  final int boxBorderRadius;

  // 3. Subtitle Primary
  final bool showSubtitle;
  final bool subtitleShowPrimary;
  final List<double>? subtitleRegion;
  final String fontName;
  final String fontSize; // Empty string for auto-fit
  final String fontsDir; // Path to custom fonts directory (default: assets/fonts)
  final String fontColor;
  final String outlineColor;
  final double charRate;
  final double safetyMargin;
  final bool fillGap;
  final double maxGapFill;
  final double boxLeadIn;
  final double boxLeadOut;

  // 4. Subtitle Secondary
  final bool subtitleSecondaryShow;
  final String subtitleOrder; // primary_top | secondary_top
  final bool boxSplit;
  final int boxGap;
  final String subtitleSecondaryFontName;
  final double subtitleSecondaryFontScale;
  final String subtitleSecondaryFontColor;
  final String subtitleSecondaryOutlineColor;
  final List<double>? subtitleSecondaryRegion;

  // 5. Watermark & Branding
  final bool watermarkEnabled;
  final String watermarkType; // text | image
  final String watermarkText;
  final String watermarkImage;
  final String watermarkFontName;
  final String watermarkFontColor;
  final bool watermarkBlurBg;
  final double watermarkOpacity;
  final List<double> watermarkRegion;
  final String watermarkPosition; // top-right | top-left | bottom-left | bottom-right

  // 6. TTS
  final String ttsEngine;
  final String ttsVoice;
  final double ttsSpeed;
  final double ttsDelay;
  final String ttsNumWorkers;
  final bool enableGenderTts;
  final String ttsVoiceMale;
  final String ttsVoiceFemale;

  // 7. Audio Volumes & Filters
  final double ttsVol;
  final double origVoiceVol;
  final double musicVol;
  final double ambientVol;
  final double noiseReductionStrength;
  final double ambientSplitThreshold;

  // 8. ASR & OCR
  final String asrEngine;
  final String asrModel;
  final String ocrEngine;
  final String ocrNumWorkers;
  final String ocrMode;
  final double ocrDiffThreshold;
  final int ocrDiffStep;
  final double detectStartSec;
  final double detectDurationSec;

  // 9. Translator (AI)
  final String translatorType;
  final String translatorModel;
  final String translatorApiKey;
  final String translatorBaseUrl;
  final int translatorBatchSize;
  final String pronounMode; // dynamic | couple | family_parent_child | friends | formal | custom
  final String customPronounPrompt;

  // 10. Storage (GCS)
  final bool storageEnabled;
  final String storageProvider;
  final String storageKeyFile;
  final String storageBucketName;
  final String storageBasePrefix;

  // 11. Long Video & Smart Chunking
  final bool longVideoEnabled;
  final double longVideoChunkDurationMin;

  const AppConfig({
    required this.device,
    this.numWorkers = 'auto',
    required this.targetLang,
    required this.secondaryLang,
    required this.ocrOnly,
    required this.videoBitrate,
    required this.outputSuffix,
    required this.inpaintShowBox,
    required this.inpaintEngine,
    required this.inpaintMethod,
    required this.inpaintPaddingY,
    required this.inpaintColor,
    required this.inpaintBlurRadius,
    this.inpaintRegion,
    required this.boxBgColor,
    required this.boxBgOpacity,
    required this.boxBorderColor,
    required this.boxBorderWidth,
    required this.boxBorderRadius,
    required this.showSubtitle,
    required this.subtitleShowPrimary,
    this.subtitleRegion,
    required this.fontName,
    required this.fontSize,
    this.fontsDir = 'resources/fonts',
    required this.fontColor,
    required this.outlineColor,
    required this.charRate,
    required this.safetyMargin,
    required this.fillGap,
    this.maxGapFill = 0.8,
    this.boxLeadIn = 0.25,
    this.boxLeadOut = 0.15,
    required this.subtitleSecondaryShow,
    required this.subtitleOrder,
    required this.boxSplit,
    required this.boxGap,
    required this.subtitleSecondaryFontName,
    required this.subtitleSecondaryFontScale,
    required this.subtitleSecondaryFontColor,
    required this.subtitleSecondaryOutlineColor,
    this.subtitleSecondaryRegion,
    required this.watermarkEnabled,
    required this.watermarkType,
    required this.watermarkText,
    required this.watermarkImage,
    required this.watermarkFontName,
    required this.watermarkFontColor,
    required this.watermarkBlurBg,
    required this.watermarkOpacity,
    required this.watermarkRegion,
    required this.watermarkPosition,
    required this.ttsEngine,
    required this.ttsVoice,
    required this.ttsSpeed,
    this.ttsDelay = 0.25,
    this.ttsNumWorkers = 'auto',
    required this.enableGenderTts,
    required this.ttsVoiceMale,
    required this.ttsVoiceFemale,
    required this.ttsVol,
    required this.origVoiceVol,
    required this.musicVol,
    required this.ambientVol,
    required this.noiseReductionStrength,
    required this.ambientSplitThreshold,
    required this.asrEngine,
    required this.asrModel,
    required this.ocrEngine,
    required this.ocrNumWorkers,
    required this.ocrMode,
    required this.ocrDiffThreshold,
    required this.ocrDiffStep,
    required this.detectStartSec,
    required this.detectDurationSec,
    required this.translatorType,
    required this.translatorModel,
    required this.translatorApiKey,
    required this.translatorBaseUrl,
    required this.translatorBatchSize,
    this.pronounMode = 'dynamic',
    this.customPronounPrompt = '',
    required this.storageEnabled,
    required this.storageProvider,
    required this.storageKeyFile,
    required this.storageBucketName,
    required this.storageBasePrefix,
    this.longVideoEnabled = false,
    this.longVideoChunkDurationMin = 2.0,
    this.batchCooldownSec = 'auto',
  });

  double get ttsSpeedFactor => ttsSpeed;
  double get audioTtsVoiceVolume => ttsVol;
  double get audioOriginalVoiceVolume => origVoiceVol;
  double get audioMusicVolume => musicVol;
  double get audioAmbientVolume => ambientVol;
  bool get subtitleShow => showSubtitle;

  factory AppConfig.defaults() => const AppConfig(
        device: 'auto',
        numWorkers: 'auto',
        targetLang: 'vi',
        secondaryLang: '',
        ocrOnly: false,
        videoBitrate: '4.0M',
        outputSuffix: '_vi',
        inpaintShowBox: true,
        inpaintEngine: 'box_color',
        inpaintMethod: 'vertical_gradient',
        inpaintPaddingY: 0.02,
        inpaintColor: 'transparent',
        inpaintBlurRadius: 15,
        inpaintRegion: null,
        boxBgColor: 'black',
        boxBgOpacity: 0.75,
        boxBorderColor: '&H40FFFFFF',
        boxBorderWidth: 2,
        boxBorderRadius: 8,
        showSubtitle: true,
        subtitleShowPrimary: true,
        subtitleRegion: null,
        fontName: 'Arial',
        fontSize: '',
        fontsDir: 'resources/fonts',
        fontColor: '&H00FFFFFF',
        outlineColor: '&H00000000',
        charRate: 0.07,
        safetyMargin: 0.15,
        fillGap: true,
        maxGapFill: 0.8,
        boxLeadIn: 0.25,
        boxLeadOut: 0.15,
        subtitleSecondaryShow: true,
        subtitleOrder: 'primary_top',
        boxSplit: true,
        boxGap: 8,
        subtitleSecondaryFontName: '',
        subtitleSecondaryFontScale: 0.75,
        subtitleSecondaryFontColor: '&H00D0D0D0',
        subtitleSecondaryOutlineColor: '&H00000000',
        subtitleSecondaryRegion: null,
        watermarkEnabled: true,
        watermarkType: 'text',
        watermarkText: 'Sub-Video AI',
        watermarkImage: '',
        watermarkFontName: 'Arial',
        watermarkFontColor: 'white',
        watermarkBlurBg: true,
        watermarkOpacity: 0.85,
        watermarkRegion: [0.02, 0.85, 0.05, 0.95],
        watermarkPosition: 'top-right',
        ttsEngine: 'preset',
        ttsVoice: 'vi-VN-BanMai',
        ttsSpeed: 1.5,
        ttsDelay: 0.25,
        ttsNumWorkers: 'auto',
        enableGenderTts: false,
        ttsVoiceMale: 'vi-VN-NamMinhNeural',
        ttsVoiceFemale: 'vi-VN-HoaiMyNeural',
        ttsVol: 1.0,
        origVoiceVol: 0.05,
        musicVol: 0.5,
        ambientVol: 0.75,
        noiseReductionStrength: 0.9,
        ambientSplitThreshold: 0.3,
        asrEngine: 'mlx-whisper',
        asrModel: 'auto',
        ocrEngine: 'apple_vision',
        ocrNumWorkers: 'auto',
        ocrMode: 'region',
        ocrDiffThreshold: 8.0,
        ocrDiffStep: 2,
        detectStartSec: 5.0,
        detectDurationSec: 10.0,
        translatorType: 'gemini',
        translatorModel: 'gemini-3.1-flash-lite',
        translatorApiKey: '',
        translatorBaseUrl: 'https://generativelanguage.googleapis.com/v1beta/openai',
        translatorBatchSize: 20,
        pronounMode: 'dynamic',
        customPronounPrompt: '',
        storageEnabled: true,
        storageProvider: 'gcs',
        storageKeyFile: 'resources/gcs-key.json',
        storageBucketName: '',
        storageBasePrefix: '',
        longVideoEnabled: false,
        longVideoChunkDurationMin: 2.0,
        batchCooldownSec: 'auto',
      );

  AppConfig copyWith({
    String? device,
    String? numWorkers,
    String? targetLang,
    String? secondaryLang,
    bool? ocrOnly,
    String? videoBitrate,
    String? outputSuffix,
    bool? inpaintShowBox,
    String? inpaintEngine,
    String? inpaintMethod,
    double? inpaintPaddingY,
    String? inpaintColor,
    int? inpaintBlurRadius,
    List<double>? inpaintRegion,
    bool setInpaintRegionNull = false,
    String? boxBgColor,
    double? boxBgOpacity,
    String? boxBorderColor,
    int? boxBorderWidth,
    int? boxBorderRadius,
    bool? showSubtitle,
    bool? subtitleShowPrimary,
    List<double>? subtitleRegion,
    bool setSubtitleRegionNull = false,
    String? fontName,
    String? fontSize,
    String? fontsDir,
    String? fontColor,
    String? outlineColor,
    double? charRate,
    double? safetyMargin,
    bool? fillGap,
    double? maxGapFill,
    double? boxLeadIn,
    double? boxLeadOut,
    bool? subtitleSecondaryShow,
    String? subtitleOrder,
    bool? boxSplit,
    int? boxGap,
    String? subtitleSecondaryFontName,
    double? subtitleSecondaryFontScale,
    String? subtitleSecondaryFontColor,
    String? subtitleSecondaryOutlineColor,
    List<double>? subtitleSecondaryRegion,
    bool setSubtitleSecondaryRegionNull = false,
    bool? watermarkEnabled,
    String? watermarkType,
    String? watermarkText,
    String? watermarkImage,
    String? watermarkFontName,
    String? watermarkFontColor,
    bool? watermarkBlurBg,
    double? watermarkOpacity,
    List<double>? watermarkRegion,
    String? watermarkPosition,
    String? ttsEngine,
    String? ttsVoice,
    double? ttsSpeed,
    double? ttsSpeedFactor,
    double? ttsDelay,
    double? ttsDelaySec,
    String? ttsNumWorkers,
    bool? enableGenderTts,
    String? ttsVoiceMale,
    String? ttsVoiceFemale,
    double? ttsVol,
    double? audioTtsVoiceVolume,
    double? origVoiceVol,
    double? audioOriginalVoiceVolume,
    double? musicVol,
    double? audioMusicVolume,
    double? ambientVol,
    double? audioAmbientVolume,
    double? noiseReductionStrength,
    double? ambientSplitThreshold,
    String? asrEngine,
    String? asrModel,
    String? ocrEngine,
    String? ocrNumWorkers,
    String? ocrMode,
    double? ocrDiffThreshold,
    int? ocrDiffStep,
    double? detectStartSec,
    double? detectDurationSec,
    String? translatorType,
    String? translatorModel,
    String? translatorApiKey,
    String? translatorBaseUrl,
    int? translatorBatchSize,
    String? pronounMode,
    String? customPronounPrompt,
    bool? storageEnabled,
    String? storageProvider,
    String? storageKeyFile,
    String? storageBucketName,
    String? storageBasePrefix,
    bool? longVideoEnabled,
    double? longVideoChunkDurationMin,
    String? batchCooldownSec,
  }) {
    return AppConfig(
      device: device ?? this.device,
      numWorkers: numWorkers ?? this.numWorkers,
      targetLang: targetLang ?? this.targetLang,
      secondaryLang: secondaryLang ?? this.secondaryLang,
      ocrOnly: ocrOnly ?? this.ocrOnly,
      videoBitrate: videoBitrate ?? this.videoBitrate,
      outputSuffix: outputSuffix ?? this.outputSuffix,
      inpaintShowBox: inpaintShowBox ?? this.inpaintShowBox,
      inpaintEngine: inpaintEngine ?? this.inpaintEngine,
      inpaintMethod: inpaintMethod ?? this.inpaintMethod,
      inpaintPaddingY: inpaintPaddingY ?? this.inpaintPaddingY,
      inpaintColor: inpaintColor ?? this.inpaintColor,
      inpaintBlurRadius: inpaintBlurRadius ?? this.inpaintBlurRadius,
      inpaintRegion: setInpaintRegionNull ? null : (inpaintRegion ?? this.inpaintRegion),
      boxBgColor: boxBgColor ?? this.boxBgColor,
      boxBgOpacity: boxBgOpacity ?? this.boxBgOpacity,
      boxBorderColor: boxBorderColor ?? this.boxBorderColor,
      boxBorderWidth: boxBorderWidth ?? this.boxBorderWidth,
      boxBorderRadius: boxBorderRadius ?? this.boxBorderRadius,
      showSubtitle: showSubtitle ?? this.showSubtitle,
      subtitleShowPrimary: subtitleShowPrimary ?? this.subtitleShowPrimary,
      subtitleRegion: setSubtitleRegionNull ? null : (subtitleRegion ?? this.subtitleRegion),
      fontName: fontName ?? this.fontName,
      fontSize: fontSize ?? this.fontSize,
      fontsDir: fontsDir ?? this.fontsDir,
      fontColor: fontColor ?? this.fontColor,
      outlineColor: outlineColor ?? this.outlineColor,
      charRate: charRate ?? this.charRate,
      safetyMargin: safetyMargin ?? this.safetyMargin,
      fillGap: fillGap ?? this.fillGap,
      maxGapFill: maxGapFill ?? this.maxGapFill,
      boxLeadIn: boxLeadIn ?? this.boxLeadIn,
      boxLeadOut: boxLeadOut ?? this.boxLeadOut,
      subtitleSecondaryShow: subtitleSecondaryShow ?? this.subtitleSecondaryShow,
      subtitleOrder: subtitleOrder ?? this.subtitleOrder,
      boxSplit: boxSplit ?? this.boxSplit,
      boxGap: boxGap ?? this.boxGap,
      subtitleSecondaryFontName: subtitleSecondaryFontName ?? this.subtitleSecondaryFontName,
      subtitleSecondaryFontScale: subtitleSecondaryFontScale ?? this.subtitleSecondaryFontScale,
      subtitleSecondaryFontColor: subtitleSecondaryFontColor ?? this.subtitleSecondaryFontColor,
      subtitleSecondaryOutlineColor: subtitleSecondaryOutlineColor ?? this.subtitleSecondaryOutlineColor,
      subtitleSecondaryRegion: setSubtitleSecondaryRegionNull ? null : (subtitleSecondaryRegion ?? this.subtitleSecondaryRegion),
      watermarkEnabled: watermarkEnabled ?? this.watermarkEnabled,
      watermarkType: watermarkType ?? this.watermarkType,
      watermarkText: watermarkText ?? this.watermarkText,
      watermarkImage: watermarkImage ?? this.watermarkImage,
      watermarkFontName: watermarkFontName ?? this.watermarkFontName,
      watermarkFontColor: watermarkFontColor ?? this.watermarkFontColor,
      watermarkBlurBg: watermarkBlurBg ?? this.watermarkBlurBg,
      watermarkOpacity: watermarkOpacity ?? this.watermarkOpacity,
      watermarkRegion: watermarkRegion ?? this.watermarkRegion,
      watermarkPosition: watermarkPosition ?? this.watermarkPosition,
      ttsEngine: ttsEngine ?? this.ttsEngine,
      ttsVoice: ttsVoice ?? this.ttsVoice,
      ttsSpeed: ttsSpeed ?? (ttsSpeedFactor ?? this.ttsSpeed),
      ttsDelay: ttsDelay ?? (ttsDelaySec ?? this.ttsDelay),
      ttsNumWorkers: ttsNumWorkers ?? this.ttsNumWorkers,
      enableGenderTts: enableGenderTts ?? this.enableGenderTts,
      ttsVoiceMale: ttsVoiceMale ?? this.ttsVoiceMale,
      ttsVoiceFemale: ttsVoiceFemale ?? this.ttsVoiceFemale,
      ttsVol: ttsVol ?? (audioTtsVoiceVolume ?? this.ttsVol),
      origVoiceVol: origVoiceVol ?? (audioOriginalVoiceVolume ?? this.origVoiceVol),
      musicVol: musicVol ?? (audioMusicVolume ?? this.musicVol),
      ambientVol: ambientVol ?? (audioAmbientVolume ?? this.ambientVol),
      noiseReductionStrength: noiseReductionStrength ?? this.noiseReductionStrength,
      ambientSplitThreshold: ambientSplitThreshold ?? this.ambientSplitThreshold,
      asrEngine: asrEngine ?? this.asrEngine,
      asrModel: asrModel ?? this.asrModel,
      ocrEngine: ocrEngine ?? this.ocrEngine,
      ocrNumWorkers: ocrNumWorkers ?? this.ocrNumWorkers,
      ocrMode: ocrMode ?? this.ocrMode,
      ocrDiffThreshold: ocrDiffThreshold ?? this.ocrDiffThreshold,
      ocrDiffStep: ocrDiffStep ?? this.ocrDiffStep,
      detectStartSec: detectStartSec ?? this.detectStartSec,
      detectDurationSec: detectDurationSec ?? this.detectDurationSec,
      translatorType: translatorType ?? this.translatorType,
      translatorModel: translatorModel ?? this.translatorModel,
      translatorApiKey: translatorApiKey ?? this.translatorApiKey,
      translatorBaseUrl: translatorBaseUrl ?? this.translatorBaseUrl,
      translatorBatchSize: translatorBatchSize ?? this.translatorBatchSize,
      pronounMode: pronounMode ?? this.pronounMode,
      customPronounPrompt: customPronounPrompt ?? this.customPronounPrompt,
      storageEnabled: storageEnabled ?? this.storageEnabled,
      storageProvider: storageProvider ?? this.storageProvider,
      storageKeyFile: storageKeyFile ?? this.storageKeyFile,
      storageBucketName: storageBucketName ?? this.storageBucketName,
      storageBasePrefix: storageBasePrefix ?? this.storageBasePrefix,
      longVideoEnabled: longVideoEnabled ?? this.longVideoEnabled,
      longVideoChunkDurationMin: longVideoChunkDurationMin ?? this.longVideoChunkDurationMin,
      batchCooldownSec: batchCooldownSec ?? this.batchCooldownSec,
    );
  }
}
