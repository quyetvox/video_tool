/**
 * Unified Config Schema & Serializer for Sub-Video GUI
 * Single Source of Truth for both ConfigEditor and SubtitleInspector / VideoStudioLayout
 */

export const parseYamlRobust = (yamlStr) => {
  if (!yamlStr || typeof yamlStr !== 'string') return {};
  const lines = yamlStr.split('\n');
  const result = {};
  let currentSection = null;
  let currentSubSection = null;
  let subIndent = 0;

  for (let line of lines) {
    const rawLine = line;
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) {
      // Check commented region like # region: [0.12, 0.05, 0.22, 0.95]
      const commentMatch = trimmed.match(/^#\s*([a-zA-Z0-9_-]+):(?:\s*(.*))?$/);
      if (commentMatch && currentSection) {
        const key = commentMatch[1];
        if (key === 'region' && !result[currentSection].region) {
          result[currentSection].region = null;
        }
      }
      continue;
    }

    const indent = rawLine.search(/\S/);

    // Section header (indent 0)
    const sectionMatch = line.match(/^([a-zA-Z0-9_-]+):\s*$/);
    if (sectionMatch && indent === 0) {
      currentSection = sectionMatch[1];
      currentSubSection = null;
      if (!result[currentSection]) result[currentSection] = {};
      continue;
    }

    // Key-value pair
    const kvMatch = line.match(/^([a-zA-Z0-9_-]+):(?:\s*(.*))?$/);
    if (kvMatch && currentSection) {
      const key = kvMatch[1];
      const valStr = kvMatch[2] !== undefined ? kvMatch[2].trim() : '';

      if (valStr === '' && indent > 0) {
        currentSubSection = key;
        subIndent = indent;
        if (!result[currentSection][key]) result[currentSection][key] = {};
      } else {
        let val = valStr;
        if ((val.startsWith('"') && val.endsWith('"')) || (val.startsWith("'") && val.endsWith("'"))) {
          val = val.slice(1, -1);
        } else if (val === 'true') {
          val = true;
        } else if (val === 'false') {
          val = false;
        } else if (val.startsWith('[') && val.endsWith(']')) {
          try {
            val = JSON.parse(val);
          } catch (e) {
            val = val.slice(1, -1).split(',').map(s => {
              const num = Number(s.trim());
              return isNaN(num) ? s.trim() : num;
            });
          }
        } else if (!isNaN(val) && val !== '') {
          val = Number(val);
        }

        if (currentSubSection && indent > subIndent) {
          result[currentSection][currentSubSection][key] = val;
        } else {
          currentSubSection = null;
          result[currentSection][key] = val;
        }
      }
    }
  }
  return result;
};

/**
 * Parse YAML string to normalized unified JS config object
 */
export const parseYamlToUnifiedConfig = (yamlStr) => {
  const y = parseYamlRobust(yamlStr);
  if (!y || Object.keys(y).length === 0) return getDefaultConfig();

  const app = y.app || {};
  const asr = y.asr || {};
  const sub = y.subtitle || {};
  const subSec = sub.secondary || {};
  const inp = y.inpaint || {};
  const box = inp.box || sub.box || {};
  const wm = y.watermark || {};
  const tts = y.tts || {};
  const audio = y.audio || {};
  const vols = audio.volumes || {};
  const filters = audio.filters || {};
  const trans = y.translator || {};
  const ocr = y.ocr || {};
  const storage = y.storage || {};

  const inpaintRegion = inp.region || y.inpaint_region || (Array.isArray(inp) ? inp : null);
  const wmRegion = wm.region || (Array.isArray(wm) ? wm : [0.02, 0.85, 0.05, 0.95]);
  const subRegion = sub.region || null;
  const subSecRegion = subSec.region || null;

  return {
    // App
    device: app.device || 'auto',
    target_lang: app.target_lang || 'vi',
    secondary_lang: app.secondary_lang || '',
    ocr_only: app.ocr_only ?? false,
    video_bitrate: app.video_bitrate || '4.0M',
    output_suffix: app.output_suffix || '_vi',

    // Inpaint & SubBox (Cụm 1)
    inpaint_show_box: inp.show_box ?? true,
    inpaint_engine: inp.engine || 'box_color',
    inpaint_method: inp.method || 'vertical_gradient',
    inpaint_padding_y: inp.padding_y ?? 0.02,
    inpaint_color: inp.color || 'transparent',
    inpaint_blur_radius: inp.blur_radius ?? 15,
    inpaint_region: Array.isArray(inpaintRegion) && inpaintRegion.length === 4 ? inpaintRegion : null,
    box_bg_color: box.bg_color || inp.bg_color || sub.bg_color || 'black',
    box_bg_opacity: box.bg_opacity ?? inp.bg_opacity ?? sub.bg_opacity ?? 0.75,
    box_border_color: box.border_color || inp.border_color || sub.border_color || '&H40FFFFFF',
    box_border_width: box.border_width ?? inp.border_width ?? sub.border_width ?? 2,
    box_border_radius: box.border_radius ?? inp.border_radius ?? sub.border_radius ?? 8,

    // Subtitle Primary (Cụm 2)
    show_subtitle: sub.show ?? true,
    subtitle_show_primary: sub.show_primary ?? true,
    subtitle_region: Array.isArray(subRegion) && subRegion.length === 4 ? subRegion : null,
    font_name: sub.font_name || 'Arial',
    font_size: sub.font_size || '',
    font_color: sub.font_color || '&H00FFFFFF',
    outline_color: sub.outline_color || '&H00000000',
    char_rate: sub.char_rate ?? 0.07,
    safety_margin: sub.safety_margin ?? 0.15,
    fill_gap: sub.fill_gap ?? true,

    // Subtitle Secondary (Cụm 3)
    subtitle_secondary_show: subSec.show ?? true,
    subtitle_order: sub.order || 'primary_top',
    box_split: sub.box_split ?? true,
    box_gap: sub.box_gap ?? 8,
    subtitle_secondary_font_name: subSec.font_name || '',
    subtitle_secondary_font_scale: subSec.font_size_scale ?? 0.75,
    subtitle_secondary_font_color: subSec.font_color || '&H00D0D0D0',
    subtitle_secondary_outline_color: subSec.outline_color || '&H00000000',
    subtitle_secondary_region: Array.isArray(subSecRegion) && subSecRegion.length === 4 ? subSecRegion : null,

    // Watermark & Branding (Cụm 4)
    watermark_enabled: wm.enabled ?? true,
    watermark_type: wm.image ? 'image' : 'text',
    watermark_text: wm.text !== undefined ? String(wm.text) : 'Sub-Video AI',
    watermark_image: wm.image || '',
    watermark_font_name: wm.font_name || 'Arial',
    watermark_font_color: wm.font_color || 'white',
    watermark_blur_bg: wm.blur_bg ?? true,
    watermark_opacity: wm.opacity ?? 0.85,
    watermark_region: Array.isArray(wmRegion) && wmRegion.length === 4 ? wmRegion : [0.02, 0.85, 0.05, 0.95],
    watermark_position: (() => {
      if (!Array.isArray(wmRegion) || wmRegion.length !== 4) return 'top-right';
      const [top, left] = wmRegion;
      if (top < 0.2 && left > 0.6) return 'top-right';
      if (top < 0.2 && left < 0.2) return 'top-left';
      if (top > 0.7 && left < 0.2) return 'bottom-left';
      if (top > 0.7 && left > 0.6) return 'bottom-right';
      return 'top-right';
    })(),

    // TTS
    tts_engine: tts.engine || 'preset',
    tts_voice: tts.voice !== undefined ? String(tts.voice) : 'vi',
    tts_speed: tts.speed_factor ?? 1.5,
    enable_gender_tts: tts.enable_gender ?? false,
    tts_voice_male: tts.voice_male || 'vi-VN-NamMinhNeural',
    tts_voice_female: tts.voice_female || 'vi',

    // Audio Volumes & Filters
    tts_vol: vols.tts_voice ?? 1.0,
    orig_voice_vol: vols.original_voice ?? 0.05,
    music_vol: vols.music ?? 0.5,
    ambient_vol: vols.ambient ?? 0.75,
    noise_reduction_strength: filters.noise_reduction_strength ?? 0.9,
    ambient_split_threshold: filters.ambient_split_threshold ?? 0.3,

    // ASR & OCR
    asr_engine: asr.engine || 'mlx-whisper',
    asr_model: asr.model || 'auto',
    ocr_engine: ocr.engine || 'apple_vision',
    ocr_num_workers: ocr.num_workers !== undefined ? ocr.num_workers : 'auto',
    ocr_mode: ocr.mode || 'region',
    ocr_diff_threshold: ocr.diff_threshold ?? 8.0,
    ocr_diff_step: ocr.diff_step ?? 2,
    detect_start_sec: ocr.detect_start_sec ?? 5.0,
    detect_duration_sec: ocr.detect_duration_sec ?? 10.0,

    // Translator
    translator_type: trans.type || 'ollama',
    translator_model: trans.model || 'gemma4:31b-cloud',
    translator_api_key: trans.api_key || '',
    translator_base_url: trans.base_url || 'http://localhost:11434',
    translator_batch_size: trans.batch_size || 20,

    // Storage
    storage_enabled: storage.enabled ?? true,
    storage_provider: storage.provider || 'gcs',
    storage_key_file: storage.key_file || 'assets/gcs-key.json',
    storage_bucket_name: storage.bucket_name || 'service-qa-beta',
    storage_base_prefix: storage.base_prefix || 'video-tiktok-volumn'
  };
};

/**
 * Returns default configuration object
 */
export const getDefaultConfig = () => ({
  device: 'auto',
  target_lang: 'vi',
  secondary_lang: '',
  ocr_only: false,
  video_bitrate: '4.0M',
  output_suffix: '_vi',

  inpaint_show_box: true,
  inpaint_engine: 'box_color',
  inpaint_method: 'vertical_gradient',
  inpaint_padding_y: 0.02,
  inpaint_color: 'transparent',
  inpaint_blur_radius: 15,
  inpaint_region: null,
  box_bg_color: 'black',
  box_bg_opacity: 0.75,
  box_border_color: '&H40FFFFFF',
  box_border_width: 2,
  box_border_radius: 8,

  show_subtitle: true,
  subtitle_show_primary: true,
  subtitle_region: null,
  font_name: 'Arial',
  font_size: '',
  font_color: '&H00FFFFFF',
  outline_color: '&H00000000',
  char_rate: 0.07,
  safety_margin: 0.15,
  fill_gap: true,

  subtitle_secondary_show: true,
  subtitle_order: 'primary_top',
  box_split: true,
  box_gap: 8,
  subtitle_secondary_font_name: '',
  subtitle_secondary_font_scale: 0.75,
  subtitle_secondary_font_color: '&H00D0D0D0',
  subtitle_secondary_outline_color: '&H00000000',
  subtitle_secondary_region: null,

  watermark_enabled: true,
  watermark_type: 'text',
  watermark_text: 'Sub-Video AI',
  watermark_image: '',
  watermark_font_name: 'Arial',
  watermark_font_color: 'white',
  watermark_blur_bg: true,
  watermark_opacity: 0.85,
  watermark_region: [0.02, 0.85, 0.05, 0.95],
  watermark_position: 'top-right',

  tts_engine: 'preset',
  tts_voice: 'vi',
  tts_speed: 1.5,
  enable_gender_tts: false,
  tts_voice_male: 'vi-VN-NamMinhNeural',
  tts_voice_female: 'vi',

  tts_vol: 1.0,
  orig_voice_vol: 0.05,
  music_vol: 0.5,
  ambient_vol: 0.75,
  noise_reduction_strength: 0.9,
  ambient_split_threshold: 0.3,

  asr_engine: 'mlx-whisper',
  asr_model: 'auto',
  ocr_engine: 'apple_vision',
  ocr_num_workers: 'auto',
  ocr_mode: 'region',
  ocr_diff_threshold: 8.0,
  ocr_diff_step: 2,
  detect_start_sec: 5.0,
  detect_duration_sec: 10.0,

  translator_type: 'ollama',
  translator_model: 'gemma4:31b-cloud',
  translator_api_key: '',
  translator_base_url: 'http://localhost:11434',
  translator_batch_size: 20,

  storage_enabled: true,
  storage_provider: 'gcs',
  storage_key_file: 'assets/gcs-key.json',
  storage_bucket_name: 'service-qa-beta',
  storage_base_prefix: 'video-tiktok-volumn'
});

/**
 * Generate standard clean YAML string from normalized config object
 */
export const unifiedConfigToYaml = (c) => {
  const cfg = { ...getDefaultConfig(), ...c };

  const inpaintRegionLine = Array.isArray(cfg.inpaint_region) && cfg.inpaint_region.length === 4
    ? `  region: [${cfg.inpaint_region.join(', ')}]`
    : `  # region: [0.12, 0.05, 0.22, 0.95]`;

  const subPrimaryRegionLine = Array.isArray(cfg.subtitle_region) && cfg.subtitle_region.length === 4
    ? `  region: [${cfg.subtitle_region.join(', ')}]`
    : `  # region: [0.75, 0.05, 0.95, 0.95]`;

  const subSecRegionLine = Array.isArray(cfg.subtitle_secondary_region) && cfg.subtitle_secondary_region.length === 4
    ? `    region: [${cfg.subtitle_secondary_region.join(', ')}]`
    : `    # region: [0.03, 0.05, 0.12, 0.95]`;

  const fontSizeLine = cfg.font_size ? `  font_size: ${cfg.font_size}` : `  # font_size: 28`;

  const wmRegion = Array.isArray(cfg.watermark_region) && cfg.watermark_region.length === 4
    ? `[${cfg.watermark_region.join(', ')}]`
    : cfg.watermark_position === 'top-right' ? '[0.02, 0.85, 0.05, 0.95]'
    : cfg.watermark_position === 'bottom-left' ? '[0.90, 0.02, 0.96, 0.30]'
    : cfg.watermark_position === 'bottom-right' ? '[0.90, 0.70, 0.96, 0.98]'
    : '[0.02, 0.02, 0.08, 0.30]';

  return `# ==============================================================================
# SUB-VIDEO PIPELINE CONFIGURATION
# ==============================================================================

# 1. ỨNG DỤNG & THIẾT BỊ (APP)
app:
  device: ${cfg.device || 'auto'}
  target_lang: ${cfg.target_lang || 'vi'}
  secondary_lang: "${cfg.secondary_lang || ''}"
  ocr_only: ${cfg.ocr_only ? 'true' : 'false'}
  video_bitrate: "${cfg.video_bitrate || '4.0M'}"
  output_suffix: "${cfg.output_suffix || '_vi'}"

# 2. NHẬN DIỆN GIỌNG NÓI (ASR)
asr:
  engine: ${cfg.asr_engine || 'mlx-whisper'}
  model: ${cfg.asr_model || 'auto'}

# 3. DỊCH THUẬT AI (TRANSLATOR)
translator:
  type: "${cfg.translator_type || 'ollama'}"
  model: "${cfg.translator_model || 'gemma4:31b-cloud'}"
  api_key: "${cfg.translator_api_key || ''}"
  base_url: "${cfg.translator_base_url || 'http://localhost:11434'}"
  batch_size: ${cfg.translator_batch_size || 20}

# 4. NHẬN DIỆN CHỮ SUB CŨ (OCR)
ocr:
  engine: ${cfg.ocr_engine || 'apple_vision'}
  num_workers: ${cfg.ocr_num_workers !== undefined ? cfg.ocr_num_workers : 'auto'}
  mode: ${cfg.ocr_mode || 'region'}
  diff_threshold: ${cfg.ocr_diff_threshold ?? 8.0}
  diff_step: ${cfg.ocr_diff_step ?? 2}
  detect_start_sec: ${cfg.detect_start_sec ?? 5.0}
  detect_duration_sec: ${cfg.detect_duration_sec ?? 10.0}

# 5. XÓA SUB CŨ & HỘP NỀN CHE (INPAINT)
inpaint:
  show_box: ${cfg.inpaint_show_box !== false ? 'true' : 'false'}
  engine: ${cfg.inpaint_engine || 'box_color'}
  method: "${cfg.inpaint_method || 'vertical_gradient'}"
  padding_y: ${cfg.inpaint_padding_y ?? 0.02}
  color: "${(cfg.inpaint_engine === 'box_color' || cfg.inpaint_engine === 'boxColor') ? (cfg.box_bg_color || 'black') : 'transparent'}"
  blur_radius: ${cfg.inpaint_blur_radius || 15}
${inpaintRegionLine}
  box:
    bg_color: "${cfg.box_bg_color || 'black'}"
    bg_opacity: ${cfg.box_bg_opacity ?? 0.75}
    border_color: "${cfg.box_border_color || '&H40FFFFFF'}"
    border_width: ${cfg.box_border_width ?? 2}
    border_radius: ${cfg.box_border_radius ?? 8}

# 6. PHỤ ĐỀ MỚI (SUBTITLE)
subtitle:
  show: ${cfg.show_subtitle !== false ? 'true' : 'false'}
  show_primary: ${cfg.subtitle_show_primary !== false ? 'true' : 'false'}
${subPrimaryRegionLine}
  order: "${cfg.subtitle_order || 'primary_top'}"
  box_split: ${cfg.box_split !== false ? 'true' : 'false'}
  box_gap: ${cfg.box_gap || 8}
  font_name: "${cfg.font_name || 'Arial'}"
  font_color: "${cfg.font_color || '&H00FFFFFF'}"
  outline_color: "${cfg.outline_color || '&H00000000'}"
${fontSizeLine}
  secondary:
    show: ${cfg.subtitle_secondary_show !== false ? 'true' : 'false'}
    font_name: "${cfg.subtitle_secondary_font_name || ''}"
    font_size_scale: ${cfg.subtitle_secondary_font_scale || 0.75}
    font_color: "${cfg.subtitle_secondary_font_color || '&H00D0D0D0'}"
    outline_color: "${cfg.subtitle_secondary_outline_color || '&H00000000'}"
${subSecRegionLine}
  char_rate: ${cfg.char_rate || 0.07}
  safety_margin: ${cfg.safety_margin || 0.15}
  fill_gap: ${cfg.fill_gap !== false ? 'true' : 'false'}

# 7. WATERMARK & BRANDING
watermark:
  enabled: ${cfg.watermark_enabled !== false ? 'true' : 'false'}
  region: ${wmRegion}
  image: "${cfg.watermark_type === 'image' ? (cfg.watermark_image || '') : ''}"
  text: "${cfg.watermark_text || 'Sub-Video AI'}"
  font_name: "${cfg.watermark_font_name || 'Arial'}"
  font_color: "${cfg.watermark_font_color || 'white'}"
  blur_bg: ${cfg.watermark_blur_bg !== false ? 'true' : 'false'}
  opacity: ${cfg.watermark_opacity ?? 0.85}

# 8. THUYẾT MINH AI (TTS)
tts:
  engine: ${cfg.tts_engine || 'preset'}
  voice: "${cfg.tts_voice !== undefined ? cfg.tts_voice : 'vi'}"
  speed_factor: ${cfg.tts_speed || 1.5}
  enable_gender: ${cfg.enable_gender_tts ? 'true' : 'false'}
  voice_male: "${cfg.tts_voice_male || 'vi-VN-NamMinhNeural'}"
  voice_female: "${cfg.tts_voice_female || 'vi'}"

# 9. ÂM LƯỢNG & BỘ LỌC ÂM THANH (AUDIO)
audio:
  volumes:
    tts_voice: ${cfg.tts_vol ?? 1.0}
    original_voice: ${cfg.orig_voice_vol ?? 0.05}
    music: ${cfg.music_vol ?? 0.5}
    ambient: ${cfg.ambient_vol ?? 0.75}
  filters:
    noise_reduction_strength: ${cfg.noise_reduction_strength ?? 0.9}
    ambient_split_threshold: ${cfg.ambient_split_threshold ?? 0.3}

# 10. CLOUD STORAGE (GOOGLE CLOUD STORAGE)
storage:
  enabled: ${cfg.storage_enabled !== false ? 'true' : 'false'}
  provider: "${cfg.storage_provider || 'gcs'}"
  key_file: "${cfg.storage_key_file || 'assets/gcs-key.json'}"
  bucket_name: "${cfg.storage_bucket_name || 'service-qa-beta'}"
  base_prefix: "${cfg.storage_base_prefix || 'video-tiktok-volumn'}"
`;
};
