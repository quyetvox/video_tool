import React, { useState, useEffect } from 'react';
import {
  Settings,
  Save,
  Code2,
  Sliders,
  Sparkles,
  Volume2,
  Type,
  Image as ImageIcon,
  Bot,
  CheckCircle2,
  HelpCircle,
  Eye
} from 'lucide-react';
import { fetchProjectConfig, saveProjectConfig } from '../services/api';
import { unifiedConfigToYaml } from '../utils/configSchema';

export default function ConfigEditor({ project, isActive, onRefresh }) {
  const [configYaml, setConfigYaml] = useState('');
  const [mode, setMode] = useState('gui'); // 'gui' | 'raw'
  const [isSaved, setIsSaved] = useState(false);
  const [configPath, setConfigPath] = useState('');

  // 🎯 Group 1: Subtitle & Inpaint Region
  const [inpaintRegionMode, setInpaintRegionMode] = useState('auto'); // 'auto' | 'manual'
  const [inpaintRegion, setInpaintRegion] = useState([0.75, 0.05, 0.95, 0.95]);
  const [detectStartSec, setDetectStartSec] = useState(5.0);
  const [detectDurationSec, setDetectDurationSec] = useState(10.0);
  // 📦 Cụm 1: Box Che Sub Gốc
  const [inpaintShowBox, setInpaintShowBox] = useState(true);
  const [inpaintPlugin, setInpaintPlugin] = useState('box_color');
  const [inpaintMethod, setInpaintMethod] = useState('vertical_gradient');
  const [inpaintColor, setInpaintColor] = useState('black');
  const [blurRadius, setBlurRadius] = useState(15);
  const [blurBoxPaddingY, setBlurBoxPaddingY] = useState(0.02);
  const [inpaintBoxBgColor, setInpaintBoxBgColor] = useState('black');
  const [inpaintBoxBgOpacity, setInpaintBoxBgOpacity] = useState(0.75);
  const [inpaintBoxBorderColor, setInpaintBoxBorderColor] = useState('&H40FFFFFF');
  const [inpaintBoxBorderWidth, setInpaintBoxBorderWidth] = useState(2);
  const [inpaintBoxBorderRadius, setInpaintBoxBorderRadius] = useState(8);

  // 🅰️ Cụm 2: Sub Chính (Primary Subtitle)
  const [showSubtitle, setShowSubtitle] = useState(true); // Master Toggle
  const [subtitleShowPrimary, setSubtitleShowPrimary] = useState(true);
  const [subtitlePrimaryRegionMode, setSubtitlePrimaryRegionMode] = useState('auto'); // auto (đè lên box) | manual
  const [subtitlePrimaryRegion, setSubtitlePrimaryRegion] = useState([0.75, 0.05, 0.95, 0.95]);
  const [subtitleFontSize, setSubtitleFontSize] = useState('');
  const [subtitleFontName, setSubtitleFontName] = useState('Arial');
  const [subtitleFontColor, setSubtitleFontColor] = useState('&H00FFFFFF');

  // 🅱️ Cụm 3: Sub Phụ Song Ngữ (Secondary Subtitle)
  const [secondaryLang, setSecondaryLang] = useState('');
  const [subtitleSecondaryShow, setSubtitleSecondaryShow] = useState(true);
  const [subtitleOrder, setSubtitleOrder] = useState('primary_top');
  const [subtitleBoxSplit, setSubtitleBoxSplit] = useState(true);
  const [subtitleBoxGap, setSubtitleBoxGap] = useState(8);
  const [subtitleSecFontName, setSubtitleSecFontName] = useState('');
  const [subtitleSecFontScale, setSubtitleSecFontScale] = useState(0.75);
  const [subtitleSecFontColor, setSubtitleSecFontColor] = useState('&H00D0D0D0');
  const [subtitleSecRegionMode, setSubtitleSecRegionMode] = useState('auto'); // auto (bám sát sub chính) | manual
  const [subtitleSecRegion, setSubtitleSecRegion] = useState([0.03, 0.05, 0.12, 0.95]);

  // App Level
  const [targetLang, setTargetLang] = useState('vi');
  const [videoBitrate, setVideoBitrate] = useState('4.0M');

  // 🖼️ Group 2: Logo / Watermark
  const [watermarkEnable, setWatermarkEnable] = useState(true);
  const [watermarkRegion, setWatermarkRegion] = useState([0.02, 0.02, 0.08, 0.30]);
  const [watermarkImage, setWatermarkImage] = useState('');
  const [watermarkText, setWatermarkText] = useState('Sub-Video AI');
  const [watermarkFontName, setWatermarkFontName] = useState('Arial');
  const [watermarkFontColor, setWatermarkFontColor] = useState('white');
  const [watermarkOpacity, setWatermarkOpacity] = useState(0.8);
  const [watermarkBlurBg, setWatermarkBlurBg] = useState(true);

  // 🗣️ Group 3: Voice & TTS Settings
  const [ttsVoice, setTtsVoice] = useState('vi');
  const [enableGenderTts, setEnableGenderTts] = useState(false);
  const [ttsVoiceMale, setTtsVoiceMale] = useState('vi-VN-NamMinhNeural');
  const [ttsVoiceFemale, setTtsVoiceFemale] = useState('vi');
  const [ttsSpeedFactor, setTtsSpeedFactor] = useState(1.5);

  // 🎛️ Group 4: Audio Mixing
  const [ttsVoiceVolume, setTtsVoiceVolume] = useState(1.0);
  const [musicVolume, setMusicVolume] = useState(0.5);
  const [ambientVolume, setAmbientVolume] = useState(0.75);
  const [originalVoiceVolume, setOriginalVoiceVolume] = useState(0.05);
  const [noiseReductionStrength, setNoiseReductionStrength] = useState(0.9);

  // 🤖 Group 5: Translation LLM & OCR AI
  const [ocrOnly, setOcrOnly] = useState(false);
  const [ocrEngine, setOcrEngine] = useState('apple_vision');
  const [ocrNumWorkers, setOcrNumWorkers] = useState('2');
  const [ocrMode, setOcrMode] = useState('region');
  const [translatorType, setTranslatorType] = useState('ollama');
  const [translatorModel, setTranslatorModel] = useState('gemma4:31b-cloud');
  const [translatorApiKey, setTranslatorApiKey] = useState('');
  const [showApiKey, setShowApiKey] = useState(false);
  const [translatorBaseUrl, setTranslatorBaseUrl] = useState('http://localhost:11434');
  const [translatorBatchSize, setTranslatorBatchSize] = useState(20);

  useEffect(() => {
    if (project && isActive !== false) {
      loadConfig();
    }
  }, [project, isActive]);

  const loadConfig = async () => {
    try {
      const data = await fetchProjectConfig(project);
      const content = data.content || '';
      setConfigYaml(content);
      setConfigPath(data.path || '');
      parseYamlToGui(content);
    } catch (e) {
      console.error('Failed to load config:', e);
    }
  };

  const parseYamlToGui = (yamlStr) => {
    const extractBlock = (str, blockName) => {
      const match = str.match(new RegExp(`^${blockName}:\\s*\\n((?:[ \\t]+.*\\n?)*)`, 'm'));
      return match ? match[1] : '';
    };

    const getVal = (blockStr, key, defaultVal, type = 'string') => {
      const source = blockStr || yamlStr;
      const match = source.match(new RegExp(`^\\s*${key}:\\s*(.+)`, 'm'));
      if (!match) return defaultVal;
      let rawStr = match[1].trim();

      // If wrapped in double or single quotes, extract content between quotes
      if (rawStr.startsWith('"')) {
        const quoteMatch = rawStr.match(/^"([^"]*)"/);
        if (quoteMatch) rawStr = quoteMatch[1];
      } else if (rawStr.startsWith("'")) {
        const quoteMatch = rawStr.match(/^'([^']*)'/);
        if (quoteMatch) rawStr = quoteMatch[1];
      } else {
        // Otherwise remove trailing comment
        rawStr = rawStr.split(/\s+#/)[0].trim();
        rawStr = rawStr.replace(/^["']|["']$/g, '');
      }

      if (type === 'boolean') return rawStr === 'true';
      if (type === 'float') {
        const val = parseFloat(rawStr);
        return isNaN(val) ? defaultVal : val;
      }
      if (type === 'int') {
        const val = parseInt(rawStr, 10);
        return isNaN(val) ? defaultVal : val;
      }
      if (type === 'array') {
        try {
          const arrMatch = rawStr.match(/\[(.*?)\]/);
          if (arrMatch) {
            return arrMatch[1].split(',').map(v => parseFloat(v.trim()));
          }
        } catch (e) { }
        return defaultVal;
      }
      return rawStr;
    };

    // Extract blocks
    const appBlock = extractBlock(yamlStr, 'app');
    const ocrBlock = extractBlock(yamlStr, 'ocr');
    const inpaintBlock = extractBlock(yamlStr, 'inpaint');
    const subtitleBlock = extractBlock(yamlStr, 'subtitle');
    const wmBlock = extractBlock(yamlStr, 'watermark');
    const ttsBlock = extractBlock(yamlStr, 'tts');
    const audioBlock = extractBlock(yamlStr, 'audio');
    const volBlock = extractBlock(audioBlock, 'volumes') || audioBlock;
    const filterBlock = extractBlock(audioBlock, 'filters') || audioBlock;
    const translatorBlock = extractBlock(yamlStr, 'translator');

    // 1. App Block
    setTargetLang(getVal(appBlock, 'target_lang', 'vi'));
    setSecondaryLang(getVal(appBlock, 'secondary_lang', ''));
    setOcrOnly(getVal(appBlock, 'ocr_only', false, 'boolean'));
    setVideoBitrate(getVal(appBlock, 'video_bitrate', '4.0M'));

    // 2. OCR Block
    let rawOcr = getVal(ocrBlock, 'engine', getVal(yamlStr, 'ocr', 'apple_vision')).toLowerCase();
    if (rawOcr === 'paddleocr') rawOcr = 'paddle_ocr';
    else if (rawOcr === 'applevision') rawOcr = 'apple_vision';
    setOcrEngine(rawOcr);
    setOcrNumWorkers(getVal(ocrBlock, 'num_workers', 'auto'));
    setOcrMode(getVal(ocrBlock, 'mode', 'region'));
    setDetectStartSec(getVal(ocrBlock, 'detect_start_sec', getVal(yamlStr, 'subtitle_detect_start_sec', 5.0, 'float'), 'float'));
    setDetectDurationSec(getVal(ocrBlock, 'detect_duration_sec', getVal(yamlStr, 'subtitle_detect_duration_sec', 10.0, 'float'), 'float'));

    // 3. Inpaint Block (Check active vs auto mode strictly within inpaint block)
    setInpaintShowBox(getVal(inpaintBlock, 'show_box', true, 'boolean'));
    const inpaintActiveMatch = inpaintBlock.match(/^\s*region:\s*\[(.*?)\]/m) || (!inpaintBlock && yamlStr.match(/^inpaint_region:\s*\[(.*?)\]/m));
    if (inpaintActiveMatch) {
      setInpaintRegionMode('manual');
      try {
        const arr = inpaintActiveMatch[1].split(',').map(v => parseFloat(v.trim()));
        if (arr.length === 4) setInpaintRegion(arr);
      } catch (e) { }
    } else {
      setInpaintRegionMode('auto');
      const commentedMatch = inpaintBlock.match(/^\s*#\s*region:\s*\[(.*?)\]/m);
      if (commentedMatch) {
        try {
          const arr = commentedMatch[1].split(',').map(v => parseFloat(v.trim()));
          if (arr.length === 4) setInpaintRegion(arr);
        } catch (e) { }
      }
    }

    let rawInpaint = getVal(inpaintBlock, 'engine', getVal(yamlStr, 'inpaint', 'box_color'));
    if (rawInpaint === 'opencv_inpaint') rawInpaint = 'opencv';
    if (rawInpaint === 'apple_vision' || rawInpaint === 'applevision' || rawInpaint === 'apple-vision-inpaint') rawInpaint = 'apple_vision_inpaint';
    if (rawInpaint === 'blur' || rawInpaint === 'boxblur') rawInpaint = 'ffmpeg_blur';
    setInpaintPlugin(rawInpaint);
    setInpaintMethod(getVal(inpaintBlock, 'method', getVal(yamlStr, 'inpaint_method', 'vertical_gradient')));
    setInpaintColor(getVal(inpaintBlock, 'color', getVal(yamlStr, 'inpaint_color', 'transparent')));
    setBlurRadius(getVal(inpaintBlock, 'blur_radius', 15, 'int'));
    setBlurBoxPaddingY(getVal(inpaintBlock, 'padding_y', getVal(yamlStr, 'blur_box_padding_y', 0.02, 'float'), 'float'));

    const boxSubBlock = extractBlock(inpaintBlock, 'box') || '';
    setInpaintBoxBgColor(getVal(boxSubBlock, 'bg_color', 'black'));
    setInpaintBoxBgOpacity(getVal(boxSubBlock, 'bg_opacity', 0.75, 'float'));
    setInpaintBoxBorderColor(getVal(boxSubBlock, 'border_color', '&H40FFFFFF'));
    setInpaintBoxBorderWidth(getVal(boxSubBlock, 'border_width', 2, 'int'));
    setInpaintBoxBorderRadius(getVal(boxSubBlock, 'border_radius', 8, 'int'));

    // 4. Subtitle Block
    setShowSubtitle(getVal(subtitleBlock, 'show', getVal(yamlStr, 'show_subtitle', true, 'boolean'), 'boolean'));
    setSubtitleShowPrimary(getVal(subtitleBlock, 'show_primary', true, 'boolean'));

    const priRegionMatch = subtitleBlock.match(/^\s*region:\s*\[(.*?)\]/m);
    if (priRegionMatch) {
      setSubtitlePrimaryRegionMode('manual');
      try {
        const arr = priRegionMatch[1].split(',').map(v => parseFloat(v.trim()));
        if (arr.length === 4) setSubtitlePrimaryRegion(arr);
      } catch (e) { }
    } else {
      setSubtitlePrimaryRegionMode('auto');
    }

    setSubtitleOrder(getVal(subtitleBlock, 'order', 'primary_top'));
    setSubtitleBoxSplit(getVal(subtitleBlock, 'box_split', true, 'boolean'));
    setSubtitleBoxGap(getVal(subtitleBlock, 'box_gap', 8, 'int'));
    setSubtitleFontName(getVal(subtitleBlock, 'font_name', getVal(yamlStr, 'subtitle_font_name', 'Arial')));
    setSubtitleFontColor(getVal(subtitleBlock, 'font_color', getVal(yamlStr, 'subtitle_font_color', '&H00FFFFFF')));
    const activeFontSizeMatch = subtitleBlock.match(/^\s*font_size:\s*(\d+)/m) || (!subtitleBlock && yamlStr.match(/^subtitle_font_size:\s*(\d+)/m));
    if (activeFontSizeMatch) {
      setSubtitleFontSize(parseInt(activeFontSizeMatch[1], 10));
    } else {
      setSubtitleFontSize('');
    }

    const secBlock = extractBlock(subtitleBlock, 'secondary') || '';
    setSubtitleSecondaryShow(getVal(secBlock, 'show', true, 'boolean'));
    setSubtitleSecFontName(getVal(secBlock, 'font_name', ''));
    setSubtitleSecFontScale(getVal(secBlock, 'font_size_scale', 0.75, 'float'));
    setSubtitleSecFontColor(getVal(secBlock, 'font_color', '&H00D0D0D0'));

    const secRegionMatch = secBlock.match(/^\s*region:\s*\[(.*?)\]/m);
    if (secRegionMatch) {
      setSubtitleSecRegionMode('manual');
      try {
        const arr = secRegionMatch[1].split(',').map(v => parseFloat(v.trim()));
        if (arr.length === 4) setSubtitleSecRegion(arr);
      } catch (e) { }
    } else {
      setSubtitleSecRegionMode('auto');
    }

    // 5. Watermark Block
    setWatermarkEnable(getVal(wmBlock, 'enabled', getVal(yamlStr, 'watermark_enable', true, 'boolean'), 'boolean'));
    setWatermarkRegion(getVal(wmBlock, 'region', getVal(yamlStr, 'watermark_region', [0.02, 0.02, 0.08, 0.30], 'array'), 'array'));
    setWatermarkImage(getVal(wmBlock, 'image', getVal(yamlStr, 'watermark_image', '')));
    setWatermarkText(getVal(wmBlock, 'text', getVal(yamlStr, 'watermark_text', 'Sub-Video AI')));
    setWatermarkFontName(getVal(wmBlock, 'font_name', getVal(yamlStr, 'watermark_font_name', 'Arial')));
    setWatermarkFontColor(getVal(wmBlock, 'font_color', getVal(yamlStr, 'watermark_font_color', 'white')));
    setWatermarkOpacity(getVal(wmBlock, 'opacity', getVal(yamlStr, 'watermark_opacity', 0.8, 'float'), 'float'));
    setWatermarkBlurBg(getVal(wmBlock, 'blur_bg', getVal(yamlStr, 'watermark_blur_bg', true, 'boolean'), 'boolean'));

    // 6. TTS Block
    setTtsVoice(getVal(ttsBlock, 'voice', getVal(yamlStr, 'tts_voice', 'vi')));
    setEnableGenderTts(getVal(ttsBlock, 'enable_gender', getVal(yamlStr, 'enable_gender_tts', false, 'boolean'), 'boolean'));
    setTtsVoiceMale(getVal(ttsBlock, 'voice_male', getVal(yamlStr, 'tts_voice_male', 'vi-VN-NamMinhNeural')));
    setTtsVoiceFemale(getVal(ttsBlock, 'voice_female', getVal(yamlStr, 'tts_voice_female', 'vi')));
    setTtsSpeedFactor(getVal(ttsBlock, 'speed_factor', getVal(yamlStr, 'tts_speed_factor', 1.5, 'float'), 'float'));

    // 7. Audio Block
    setTtsVoiceVolume(getVal(volBlock, 'tts_voice', getVal(yamlStr, 'tts_voice_volume', 1.0, 'float'), 'float'));
    setMusicVolume(getVal(volBlock, 'music', getVal(yamlStr, 'music_volume', 0.5, 'float'), 'float'));
    setAmbientVolume(getVal(volBlock, 'ambient', getVal(yamlStr, 'ambient_volume', 0.75, 'float'), 'float'));
    setOriginalVoiceVolume(getVal(volBlock, 'original_voice', getVal(yamlStr, 'original_voice_volume', 0.05, 'float'), 'float'));
    setNoiseReductionStrength(getVal(filterBlock, 'noise_reduction_strength', getVal(yamlStr, 'noise_reduction_strength', 0.9, 'float'), 'float'));

    // 8. Translator Block
    if (translatorBlock) {
      const typeMatch = translatorBlock.match(/^\s+type:\s*["']?([^"'\s#]+)["']?/m);
      const modelMatch = translatorBlock.match(/^\s+model:\s*["']?([^"'\s#]+)["']?/m);
      const apiKeyMatch = translatorBlock.match(/^\s+api_key:\s*["']?([^"'\s#]*)["']?/m);
      const baseUrlMatch = translatorBlock.match(/^\s+base_url:\s*["']?([^"'\s#]+)["']?/m);
      const batchMatch = translatorBlock.match(/^\s+batch_size:\s*(\d+)/m);

      if (typeMatch) setTranslatorType(typeMatch[1]);
      if (modelMatch) setTranslatorModel(modelMatch[1]);
      if (apiKeyMatch) setTranslatorApiKey(apiKeyMatch[1] || '');
      if (baseUrlMatch) setTranslatorBaseUrl(baseUrlMatch[1]);
      if (batchMatch) setTranslatorBatchSize(parseInt(batchMatch[1], 10) || 20);
    }
  };

  const handleTranslatorTypeChange = (newType) => {
    setTranslatorType(newType);
    if (newType === 'ollama') {
      setTranslatorBaseUrl('http://localhost:11434');
      setTranslatorModel('gemma4:31b-cloud');
    } else if (newType === 'groq') {
      setTranslatorBaseUrl('https://api.groq.com/openai/v1');
      setTranslatorModel('llama-3.3-70b-versatile');
    } else if (newType === 'deepseek') {
      setTranslatorBaseUrl('https://api.deepseek.com/v1');
      setTranslatorModel('deepseek-chat');
    } else if (newType === 'gemini') {
      setTranslatorBaseUrl('https://generativelanguage.googleapis.com/v1beta/openai');
      setTranslatorModel('gemini-1.5-flash');
    } else if (newType === 'openai') {
      setTranslatorBaseUrl('https://api.openai.com/v1');
      setTranslatorModel('gpt-4o-mini');
    }
  };

  const handleSave = async () => {
    let finalYaml = configYaml;

    if (mode === 'gui') {
      finalYaml = unifiedConfigToYaml({
        device: 'auto',
        target_lang: targetLang,
        secondary_lang: secondaryLang,
        ocr_only: ocrOnly,
        video_bitrate: videoBitrate,
        output_suffix: '_vi',

        // Inpaint & SubBox
        inpaint_show_box: inpaintShowBox,
        inpaint_engine: inpaintPlugin,
        inpaint_method: inpaintMethod,
        inpaint_padding_y: blurBoxPaddingY,
        inpaint_color: inpaintColor,
        inpaint_blur_radius: blurRadius,
        inpaint_region: inpaintRegionMode === 'manual' && inpaintRegion?.length === 4 ? inpaintRegion : null,
        box_bg_color: inpaintBoxBgColor,
        box_bg_opacity: inpaintBoxBgOpacity,
        box_border_color: inpaintBoxBorderColor,
        box_border_width: inpaintBoxBorderWidth,
        box_border_radius: inpaintBoxBorderRadius,

        // Subtitle Primary
        show_subtitle: showSubtitle,
        subtitle_show_primary: subtitleShowPrimary,
        subtitle_region: subtitlePrimaryRegionMode === 'manual' && subtitlePrimaryRegion?.length === 4 ? subtitlePrimaryRegion : null,
        font_name: subtitleFontName,
        font_size: subtitleFontSize || '',
        font_color: subtitleFontColor,
        outline_color: '&H00000000',
        char_rate: 0.07,
        safety_margin: 0.15,
        fill_gap: true,

        // Subtitle Secondary
        subtitle_secondary_show: subtitleSecondaryShow,
        subtitle_order: subtitleOrder,
        box_split: subtitleBoxSplit,
        box_gap: subtitleBoxGap,
        subtitle_secondary_font_name: subtitleSecFontName || '',
        subtitle_secondary_font_scale: subtitleSecFontScale,
        subtitle_secondary_font_color: subtitleSecFontColor,
        subtitle_secondary_outline_color: '&H00000000',
        subtitle_secondary_region: subtitleSecRegionMode === 'manual' && subtitleSecRegion?.length === 4 ? subtitleSecRegion : null,

        // Watermark
        watermark_enabled: watermarkEnable,
        watermark_type: watermarkImage ? 'image' : 'text',
        watermark_text: watermarkText,
        watermark_image: watermarkImage,
        watermark_font_name: watermarkFontName,
        watermark_font_color: watermarkFontColor,
        watermark_blur_bg: watermarkBlurBg,
        watermark_opacity: watermarkOpacity,
        watermark_region: watermarkRegion,

        // TTS
        tts_engine: 'preset',
        tts_voice: ttsVoice,
        tts_speed: ttsSpeedFactor,
        enable_gender_tts: enableGenderTts,
        tts_voice_male: ttsVoiceMale,
        tts_voice_female: ttsVoiceFemale,

        // Audio
        tts_vol: ttsVoiceVolume,
        orig_voice_vol: originalVoiceVolume,
        music_vol: musicVolume,
        ambient_vol: ambientVolume,
        noise_reduction_strength: noiseReductionStrength,
        ambient_split_threshold: 0.3,

        // ASR & OCR
        asr_engine: 'mlx-whisper',
        asr_model: 'auto',
        ocr_engine: ocrEngine,
        ocr_num_workers: ocrNumWorkers,
        ocr_mode: ocrMode,
        ocr_diff_threshold: 8.0,
        ocr_diff_step: 2,
        detect_start_sec: detectStartSec,
        detect_duration_sec: detectDurationSec,

        // Translator
        translator_type: translatorType,
        translator_model: translatorModel,
        translator_api_key: translatorApiKey,
        translator_base_url: translatorBaseUrl,
        translator_batch_size: translatorBatchSize,
      });
    }

    try {
      await saveProjectConfig(project, finalYaml);
      setConfigYaml(finalYaml);
      setIsSaved(true);
      setTimeout(() => setIsSaved(false), 2500);
      onRefresh && onRefresh();
    } catch (e) {
      console.error('Save config failed:', e);
    }
  };

  const updateInpaintRegionCoord = (idx, val) => {
    const next = [...inpaintRegion];
    next[idx] = parseFloat(val) || 0.0;
    setInpaintRegion(next);
  };

  const updateSubtitlePrimaryRegionCoord = (idx, val) => {
    const next = [...subtitlePrimaryRegion];
    next[idx] = parseFloat(val) || 0.0;
    setSubtitlePrimaryRegion(next);
  };

  const updateSubtitleSecRegionCoord = (idx, val) => {
    const next = [...subtitleSecRegion];
    next[idx] = parseFloat(val) || 0.0;
    setSubtitleSecRegion(next);
  };

  const updateWatermarkRegionCoord = (idx, val) => {
    const next = [...watermarkRegion];
    next[idx] = parseFloat(val) || 0.0;
    setWatermarkRegion(next);
  };

  return (
    <div style={styles.container}>
      <style>{`
        input[type=number]::-webkit-inner-spin-button, 
        input[type=number]::-webkit-outer-spin-button { 
          -webkit-appearance: none; 
          margin: 0; 
        }
        input[type=number] {
          -moz-appearance: textfield;
        }
      `}</style>
      {/* Header Bar */}
      <div style={styles.header}>
        <div>
          <h2 style={styles.title}>⚙️ Cấu Hình Dự Án (`assets/{project}/config.yaml`)</h2>
          <p style={styles.subtitle}>Tùy chỉnh phân nhóm các thông số xử lý pipeline dịch thuật & xóa sub</p>
        </div>

        <div style={{ display: 'flex', gap: 10 }}>
          <div style={styles.modeToggle}>
            <button
              onClick={() => setMode('gui')}
              style={{ ...styles.modeBtn, ...(mode === 'gui' ? styles.modeBtnActive : {}) }}
            >
              <Sliders size={14} style={{ marginRight: 6 }} /> Giao Diện Đồ Họa
            </button>
            <button
              onClick={() => setMode('raw')}
              style={{ ...styles.modeBtn, ...(mode === 'raw' ? styles.modeBtnActive : {}) }}
            >
              <Code2 size={14} style={{ marginRight: 6 }} /> Code YAML Thuần
            </button>
          </div>

          <button style={styles.btnSave} onClick={handleSave}>
            <Save size={16} style={{ marginRight: 6 }} />
            {isSaved ? 'Đã Lưu Thành Công!' : 'Lưu Cấu Hình'}
          </button>
        </div>
      </div>

      {mode === 'gui' ? (
        <div style={styles.guiGrid}>
          {/* ══════════════════════════════════════════════════════════════ */}
          {/* CARD 1: 🎨 KIỂU CHỮ & HỘP NỀN CHE (STYLES & INPAINT) */}
          {/* ══════════════════════════════════════════════════════════════ */}
          <div style={styles.card}>
            <div style={styles.cardHeader}>
              <Type size={18} color="#818cf8" />
              <h3 style={styles.cardTitle}>1. Kiểu Chữ & Hộp Nền Che (Styles & Inpaint)</h3>
            </div>

            {/* 📦 CỤM 1.1: HỘP NỀN CHE SUB CŨ (INPAINT / SUBBOX) */}
            <div style={{ marginBottom: 16, padding: '14px', backgroundColor: 'rgba(255, 255, 255, 0.02)', borderRadius: 8, border: '1px solid rgba(255, 255, 255, 0.08)' }}>
              <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 10 }}>
                <div style={{ fontSize: 13, fontWeight: 700, color: '#38bdf8', display: 'flex', alignItems: 'center', gap: 6 }}>
                  📦 Cụm 1.1: Hộp Nền Che Sub Cũ (Inpaint & SubBox)
                </div>
                <label style={{ display: 'flex', alignItems: 'center', gap: 6, cursor: 'pointer', fontSize: 12, fontWeight: 600, color: inpaintShowBox ? '#38bdf8' : 'var(--text-muted)' }}>
                  <input
                    type="checkbox"
                    checked={inpaintShowBox}
                    onChange={e => setInpaintShowBox(e.target.checked)}
                    style={{ cursor: 'pointer' }}
                  />
                  {inpaintShowBox ? 'Bật Box Che' : 'Tắt Box Che'}
                </label>
              </div>

              {inpaintShowBox && (
                <>
                  <div style={styles.rowTwoCol}>
                    <div style={styles.formGroup}>
                      <label style={styles.label}>Kiểu Che Sub Gốc (`inpaint.engine`):</label>
                      <select
                        value={inpaintPlugin}
                        onChange={e => setInpaintPlugin(e.target.value)}
                        style={styles.select}
                      >
                        <option value="box_color">⬛ Hộp Màu Nền Bo Góc (box_color - Đẹp & nét nhất)</option>
                        <option value="ffmpeg_blur">🪟 Mờ Kính Mịn (ffmpeg_blur - Siêu tốc ~1s)</option>
                        <option value="apple_vision_inpaint">🍏 Xóa Chữ Apple Vision AI (~3s)</option>
                        <option value="opencv">🎨 Xóa Nét Chữ OpenCV (~15s)</option>
                      </select>
                    </div>

                    <div style={styles.formGroup}>
                      <label style={styles.label}>Vị Trí Hộp Che (`inpaint.region`):</label>
                      <div style={styles.toggleRow}>
                        <button
                          type="button"
                          onClick={() => setInpaintRegionMode('auto')}
                          style={{ ...styles.toggleBtn, ...(inpaintRegionMode === 'auto' ? styles.toggleBtnActive : {}), padding: '4px 8px', fontSize: 11 }}
                        >
                          ✨ Tự Động (Auto OCR)
                        </button>
                        <button
                          type="button"
                          onClick={() => setInpaintRegionMode('manual')}
                          style={{ ...styles.toggleBtn, ...(inpaintRegionMode === 'manual' ? styles.toggleBtnActive : {}), padding: '4px 8px', fontSize: 11 }}
                        >
                          📐 Tọa Độ Thủ Công
                        </button>
                      </div>
                    </div>
                  </div>

                  {inpaintRegionMode === 'manual' ? (
                    <div style={{ ...styles.subCardBox, marginBottom: 10 }}>
                      <label style={styles.label}>Vị trí Box che [Top, Left, Bottom, Right] (tỷ lệ 0.0 → 1.0):</label>
                      <div style={styles.coordsGrid}>
                        {['Top', 'Left', 'Bottom', 'Right'].map((label, idx) => (
                          <div key={label} style={styles.coordBox}>
                            <span style={styles.coordLabel}>{label}:</span>
                            <input
                              type="number"
                              step="0.01"
                              min="0"
                              max="1"
                              value={inpaintRegion[idx]}
                              onChange={e => updateInpaintRegionCoord(idx, e.target.value)}
                              style={styles.inputCoord}
                            />
                          </div>
                        ))}
                      </div>
                    </div>
                  ) : (
                    <div style={{ ...styles.subCardBox, marginBottom: 10 }}>
                      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 10 }}>
                        <div style={styles.formGroup}>
                          <label style={styles.label}>Giây bắt đầu quét OCR:</label>
                          <input
                            type="number"
                            step="0.5"
                            value={detectStartSec}
                            onChange={e => setDetectStartSec(parseFloat(e.target.value) || 5.0)}
                            style={styles.input}
                          />
                        </div>
                        <div style={styles.formGroup}>
                          <label style={styles.label}>Thời lượng quét OCR (giây):</label>
                          <input
                            type="number"
                            step="1"
                            value={detectDurationSec}
                            onChange={e => setDetectDurationSec(parseFloat(e.target.value) || 10.0)}
                            style={styles.input}
                          />
                        </div>
                      </div>
                    </div>
                  )}
                </>
              )}
            </div>

            {/* 🅰️ CỤM 1.2: DÒNG SUB CHÍNH (PRIMARY SUBTITLE) */}
            <div style={{ marginBottom: 16, padding: '14px', backgroundColor: 'rgba(255, 255, 255, 0.02)', borderRadius: 8, border: '1px solid rgba(255, 255, 255, 0.08)' }}>
              <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 10 }}>
                <div style={{ fontSize: 13, fontWeight: 700, color: '#facc15', display: 'flex', alignItems: 'center', gap: 6 }}>
                  🅰️ Cụm 1.2: Dòng Sub Chính (Primary Subtitle)
                </div>
                <label style={{ display: 'flex', alignItems: 'center', gap: 6, cursor: 'pointer', fontSize: 12, fontWeight: 600, color: subtitleShowPrimary ? '#facc15' : 'var(--text-muted)' }}>
                  <input
                    type="checkbox"
                    checked={subtitleShowPrimary}
                    onChange={e => setSubtitleShowPrimary(e.target.checked)}
                    style={{ cursor: 'pointer' }}
                  />
                  {subtitleShowPrimary ? 'Bật Sub Chính' : 'Tắt Sub Chính'}
                </label>
              </div>

              {subtitleShowPrimary && (
                <>
                  <div style={styles.rowTwoCol}>
                    <div style={styles.formGroup}>
                      <label style={styles.label}>Font Chữ Chính:</label>
                      <select
                        value={subtitleFontName}
                        onChange={e => setSubtitleFontName(e.target.value)}
                        style={styles.select}
                      >
                        <option value="Arial">Arial (Chuẩn nét, Unicode ổn định)</option>
                        <option value="Helvetica">Helvetica (Hiện đại, thanh lịch)</option>
                        <option value="Be Vietnam Pro">Be Vietnam Pro (Việt hóa đẹp chuẩn)</option>
                        <option value="Roboto">Roboto (Google Font phổ biến)</option>
                        <option value="Montserrat">Montserrat (Đậm nét cá tính)</option>
                        <option value="SF Pro Display">SF Pro Display (Apple Native)</option>
                        <option value="Impact">Impact (Đậm nét TikTok / Meme)</option>
                      </select>
                    </div>

                    <div style={styles.formGroup}>
                      <label style={styles.label}>Màu Chữ Chính:</label>
                      <select
                        value={subtitleFontColor}
                        onChange={e => setSubtitleFontColor(e.target.value)}
                        style={styles.select}
                      >
                        <option value="&H00FFFFFF">⚪ Trắng (&H00FFFFFF)</option>
                        <option value="&H0000FFFF">🟡 Vàng (&H0000FFFF)</option>
                        <option value="&H00FFFF00">🔵 Xanh Lơ / Cyan (&H00FFFF00)</option>
                        <option value="&H000000FF">🔴 Đỏ (&H000000FF)</option>
                        <option value="&H0000FF00">🟢 Xanh Lá (&H0000FF00)</option>
                      </select>
                    </div>
                  </div>
                </>
              )}
            </div>

            {/* 🌐 CỤM 1.3: DÒNG SUB PHỤ SONG NGỮ (SECONDARY SUBTITLE) */}
            <div style={{ marginBottom: 16, padding: '14px', backgroundColor: 'rgba(255, 255, 255, 0.02)', borderRadius: 8, border: '1px solid rgba(255, 255, 255, 0.08)' }}>
              <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 10 }}>
                <div style={{ fontSize: 13, fontWeight: 700, color: '#a78bfa', display: 'flex', alignItems: 'center', gap: 6 }}>
                  🌐 Cụm 1.3: Dòng Sub Phụ Song Ngữ (Secondary Subtitle)
                </div>
                <label style={{ display: 'flex', alignItems: 'center', gap: 6, cursor: 'pointer', fontSize: 12, fontWeight: 600, color: subtitleSecondaryShow ? '#a78bfa' : 'var(--text-muted)' }}>
                  <input
                    type="checkbox"
                    checked={subtitleSecondaryShow}
                    onChange={e => setSubtitleSecondaryShow(e.target.checked)}
                    style={{ cursor: 'pointer' }}
                  />
                  {subtitleSecondaryShow ? 'Bật Sub Phụ' : 'Tắt Sub Phụ'}
                </label>
              </div>

              {subtitleSecondaryShow && (
                <div style={styles.rowTwoCol}>
                  <div style={styles.formGroup}>
                    <label style={styles.label}>Ngôn Ngữ Phụ (`secondary_lang`):</label>
                    <select
                      value={secondaryLang}
                      onChange={e => setSecondaryLang(e.target.value)}
                      style={styles.select}
                    >
                      <option value="">🚫 Tắt (Chỉ dịch đơn ngữ)</option>
                      <option value="en">🇬🇧 Tiếng Anh (English - en)</option>
                      <option value="vi">🇻🇳 Tiếng Việt (Vietnamese - vi)</option>
                      <option value="zh">🇨🇳 Tiếng Trung (Chinese - zh)</option>
                      <option value="ja">🇯🇵 Tiếng Nhật (Japanese - ja)</option>
                      <option value="ko">🇰🇷 Tiếng Hàn (Korean - ko)</option>
                    </select>
                  </div>
                </div>
              )}
            </div>

            {/* 🖼️ CỤM 1.4: LOGO / WATERMARK THƯƠNG HIỆU */}
            <div style={{ padding: '14px', backgroundColor: 'rgba(255, 255, 255, 0.02)', borderRadius: 8, border: '1px solid rgba(255, 255, 255, 0.08)' }}>
              <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 10 }}>
                <div style={{ fontSize: 13, fontWeight: 700, color: '#10b981', display: 'flex', alignItems: 'center', gap: 6 }}>
                  🖼️ Cụm 1.4: Logo / Watermark Thương Hiệu
                </div>
                <label style={{ display: 'flex', alignItems: 'center', gap: 6, cursor: 'pointer', fontSize: 12, fontWeight: 600, color: watermarkEnable ? '#10b981' : 'var(--text-muted)' }}>
                  <input
                    type="checkbox"
                    checked={watermarkEnable}
                    onChange={e => setWatermarkEnable(e.target.checked)}
                    style={{ cursor: 'pointer' }}
                  />
                  {watermarkEnable ? 'Bật Watermark' : 'Tắt Watermark'}
                </label>
              </div>

              {watermarkEnable && (
                <>
                  <div style={styles.rowTwoCol}>
                    <div style={styles.formGroup}>
                      <label style={styles.label}>Chữ Hiển Thị Watermark:</label>
                      <input
                        type="text"
                        placeholder="Sub-Video AI..."
                        value={watermarkText}
                        onChange={e => setWatermarkText(e.target.value)}
                        style={styles.input}
                      />
                    </div>

                    <div style={styles.formGroup}>
                      <label style={styles.label}>Đường Dẫn Ảnh Logo PNG (Ưu tiên):</label>
                      <input
                        type="text"
                        placeholder="assets/logo.png (Để trống nếu dùng chữ text)..."
                        value={watermarkImage}
                        onChange={e => setWatermarkImage(e.target.value)}
                        style={styles.input}
                      />
                    </div>
                  </div>

                  <div style={styles.rowTwoCol}>
                    <div style={styles.formGroup}>
                      <label style={styles.label}>Font Chữ Watermark:</label>
                      <select
                        value={watermarkFontName}
                        onChange={e => setWatermarkFontName(e.target.value)}
                        style={styles.select}
                      >
                        <option value="Arial">Arial</option>
                        <option value="Helvetica">Helvetica</option>
                        <option value="Be Vietnam Pro">Be Vietnam Pro</option>
                        <option value="Roboto">Roboto</option>
                        <option value="Montserrat">Montserrat</option>
                        <option value="SF Pro Display">SF Pro Display</option>
                        <option value="Impact">Impact</option>
                      </select>
                    </div>

                    <div style={styles.formGroup}>
                      <label style={styles.label}>Màu Chữ Watermark:</label>
                      <select
                        value={watermarkFontColor}
                        onChange={e => setWatermarkFontColor(e.target.value)}
                        style={styles.select}
                      >
                        <option value="white">⚪ Trắng (white)</option>
                        <option value="yellow">🟡 Vàng (yellow)</option>
                        <option value="cyan">🔵 Xanh Lơ (cyan)</option>
                        <option value="black">⚫ Đen (black)</option>
                        <option value="red">🔴 Đỏ (red)</option>
                        <option value="gold">🌟 Vàng Kim (gold)</option>
                      </select>
                    </div>
                  </div>

                  <div style={styles.rowTwoCol}>
                    <div style={styles.formGroup}>
                      <div style={styles.labelWithBadge}>
                        <label style={styles.label}>Độ Đục Logo:</label>
                        <span style={styles.valueBadge}>{Math.round(watermarkOpacity * 100)}%</span>
                      </div>
                      <div style={styles.sliderWrapper}>
                        <input
                          type="range"
                          min="0.1"
                          max="1.0"
                          step="0.05"
                          value={watermarkOpacity}
                          onChange={e => setWatermarkOpacity(parseFloat(e.target.value))}
                          style={styles.slider}
                        />
                      </div>
                    </div>

                    <div style={styles.formGroup}>
                      <label style={styles.label}>Hiệu Ứng Nền Logo:</label>
                      <label style={styles.checkboxBox}>
                        <input
                          type="checkbox"
                          checked={watermarkBlurBg}
                          onChange={e => setWatermarkBlurBg(e.target.checked)}
                        />
                        <span>Làm mờ nền kính (Glassmorphism)</span>
                      </label>
                    </div>
                  </div>

                  <div style={styles.formGroup}>
                    <label style={styles.label}>Vị Trí Watermark `[Top, Left, Bottom, Right]`:</label>
                    <div style={styles.coordsGrid}>
                      {watermarkRegion.map((val, idx) => (
                        <div key={idx} style={styles.coordBox}>
                          <span style={styles.coordLabel}>{['Top', 'Left', 'Bottom', 'Right'][idx]}:</span>
                          <input
                            type="number"
                            step="0.01"
                            min="0"
                            max="1"
                            value={val}
                            onChange={e => updateWatermarkRegionCoord(idx, e.target.value)}
                            style={styles.inputCoord}
                          />
                        </div>
                      ))}
                    </div>
                  </div>
                </>
              )}
            </div>
          </div>

          {/* ══════════════════════════════════════════════════════════════ */}
          {/* CARD 2: 🎙️ GIỌNG ĐỌC & ÂM THANH (VOICE & AUDIO) */}
          {/* ══════════════════════════════════════════════════════════════ */}
          <div style={styles.card}>
            <div style={styles.cardHeader}>
              <Volume2 size={18} color="#f59e0b" />
              <h3 style={styles.cardTitle}>2. Giọng Đọc & Âm Thanh (Voice & Audio)</h3>
            </div>

            {/* 🗣️ CỤM 2.1: GIỌNG ĐỌC AI (EDGETTS) */}
            <div style={{ marginBottom: 16, padding: '14px', backgroundColor: 'rgba(255, 255, 255, 0.02)', borderRadius: 8, border: '1px solid rgba(255, 255, 255, 0.08)' }}>
              <div style={{ fontSize: 13, fontWeight: 700, color: '#fbbf24', marginBottom: 10, display: 'flex', alignItems: 'center', gap: 6 }}>
                🗣️ Cụm 2.1: Giọng Đọc AI (EdgeTTS & Phân Biệt Giới Tính)
              </div>

              <div style={styles.formGroup}>
                <label style={styles.label}>Giọng Đọc Mặc Định (`tts_voice`):</label>
                <select
                  value={ttsVoice}
                  onChange={e => setTtsVoice(e.target.value)}
                  style={styles.select}
                >
                  <option value="vi">🌸 Ban Mai Tiếng Việt (gTTS Mặc Định)</option>
                  <option value="vi-VN-NamMinhNeural">🎙️ Nam Minh Neural (EdgeTTS Giọng Nam)</option>
                  <option value="vi-VN-HoaiMyNeural">🎙️ Hoài Mỹ Neural (EdgeTTS Giọng Nữ)</option>
                  <option value="0">🔇 Tắt Giọng Đọc (0 - Giữ 100% Âm Thanh Gốc)</option>
                </select>
              </div>

              <div style={styles.formGroup}>
                <div style={styles.labelWithBadge}>
                  <label style={styles.label}>Tốc Độ Đọc TTS (`speed_factor`):</label>
                  <span style={styles.valueBadge}>{ttsSpeedFactor}x</span>
                </div>
                <div style={styles.sliderWrapper}>
                  <input
                    type="range"
                    min="0.8"
                    max="2.0"
                    step="0.05"
                    value={ttsSpeedFactor}
                    onChange={e => setTtsSpeedFactor(parseFloat(e.target.value))}
                    style={styles.slider}
                  />
                </div>
              </div>

              <div style={{ marginTop: 10 }}>
                <div style={styles.formGroup}>
                  <label style={styles.checkboxBox}>
                    <input
                      type="checkbox"
                      checked={enableGenderTts}
                      onChange={e => setEnableGenderTts(e.target.checked)}
                    />
                    <span style={{ fontWeight: 'bold' }}>Tự đổi giọng Nam/Nữ theo nhân vật (`enable_gender_tts`)</span>
                  </label>
                </div>

                {enableGenderTts && (
                  <div style={{ ...styles.subCardBox, marginTop: 8 }}>
                    <div style={styles.rowTwoCol}>
                      <div style={styles.formGroup}>
                        <label style={styles.label}>Giọng Nam (`tts_voice_male`):</label>
                        <select
                          value={ttsVoiceMale}
                          onChange={e => setTtsVoiceMale(e.target.value)}
                          style={styles.select}
                        >
                          <option value="vi-VN-NamMinhNeural">🎙️ Nam Minh (Trầm Ấm Chuẩn)</option>
                          <option value="vi-VN-HoaiMyNeural">🎙️ Hoài Mỹ</option>
                        </select>
                      </div>

                      <div style={styles.formGroup}>
                        <label style={styles.label}>Giọng Nữ (`tts_voice_female`):</label>
                        <select
                          value={ttsVoiceFemale}
                          onChange={e => setTtsVoiceFemale(e.target.value)}
                          style={styles.select}
                        >
                          <option value="vi">🌸 Ban Mai Tiếng Việt</option>
                          <option value="vi-VN-HoaiMyNeural">🎙️ Hoài Mỹ Neural</option>
                          <option value="vi-VN-NamMinhNeural">🎙️ Nam Minh Neural</option>
                        </select>
                      </div>
                    </div>
                  </div>
                )}
              </div>
            </div>

            {/* 🎛️ CỤM 2.2: ÂM LƯỢNG & BỘ LỌC */}
            <div style={{ padding: '14px', backgroundColor: 'rgba(255, 255, 255, 0.02)', borderRadius: 8, border: '1px solid rgba(255, 255, 255, 0.08)' }}>
              <div style={{ fontSize: 13, fontWeight: 700, color: '#f472b6', marginBottom: 10, display: 'flex', alignItems: 'center', gap: 6 }}>
                🎛️ Cụm 2.2: Âm Lượng & Bộ Lọc Âm Thanh
              </div>

              <div style={styles.formGroup}>
                <div style={styles.labelWithBadge}>
                  <label style={styles.label}>Âm Lượng Giọng Đọc TTS:</label>
                  <span style={styles.valueBadge}>{Math.round(ttsVoiceVolume * 100)}%</span>
                </div>
                <div style={styles.sliderWrapper}>
                  <input
                    type="range"
                    min="0.0"
                    max="2.0"
                    step="0.05"
                    value={ttsVoiceVolume}
                    onChange={e => setTtsVoiceVolume(parseFloat(e.target.value))}
                    style={styles.slider}
                  />
                </div>
                {(ttsVoiceVolume === 0 || ttsVoice === '0') && (
                  <div style={{ fontSize: 11, marginTop: 4, padding: '6px 10px', backgroundColor: 'rgba(52, 211, 153, 0.1)', border: '1px solid rgba(52, 211, 153, 0.3)', borderRadius: 6, color: '#34d399', fontWeight: 'bold' }}>
                    ⚡ Giọng đọc TTS tắt: Pipeline tự động bỏ qua s12 TTS và giữ nguyên 100% âm thanh gốc (s13).
                  </div>
                )}
              </div>

              <div style={styles.formGroup}>
                <div style={styles.labelWithBadge}>
                  <label style={styles.label}>Âm Lượng Nhạc Nền:</label>
                  <span style={styles.valueBadge}>{Math.round(musicVolume * 100)}%</span>
                </div>
                <div style={styles.sliderWrapper}>
                  <input
                    type="range"
                    min="0.0"
                    max="1.0"
                    step="0.05"
                    value={musicVolume}
                    onChange={e => setMusicVolume(parseFloat(e.target.value))}
                    style={styles.slider}
                  />
                </div>
              </div>

              <div style={styles.formGroup}>
                <div style={styles.labelWithBadge}>
                  <label style={styles.label}>Âm Lượng Giọng Gốc:</label>
                  <span style={styles.valueBadge}>{Math.round(originalVoiceVolume * 100)}%</span>
                </div>
                <div style={styles.sliderWrapper}>
                  <input
                    type="range"
                    min="0.0"
                    max="1.0"
                    step="0.05"
                    value={originalVoiceVolume}
                    onChange={e => setOriginalVoiceVolume(parseFloat(e.target.value))}
                    style={styles.slider}
                  />
                </div>
              </div>

              <div style={styles.formGroup}>
                <div style={styles.labelWithBadge}>
                  <label style={styles.label}>Âm Lượng Môi Trường (Ambient):</label>
                  <span style={styles.valueBadge}>{Math.round(ambientVolume * 100)}%</span>
                </div>
                <div style={styles.sliderWrapper}>
                  <input
                    type="range"
                    min="0.0"
                    max="1.0"
                    step="0.05"
                    value={ambientVolume}
                    onChange={e => setAmbientVolume(parseFloat(e.target.value))}
                    style={styles.slider}
                  />
                </div>
              </div>

              <div style={styles.formGroup}>
                <div style={styles.labelWithBadge}>
                  <label style={styles.label}>Bộ Lọc Khử Tiếng Ù (Spectral Gate):</label>
                  <span style={styles.valueBadge}>{Math.round(noiseReductionStrength * 100)}%</span>
                </div>
                <div style={styles.sliderWrapper}>
                  <input
                    type="range"
                    min="0.0"
                    max="1.0"
                    step="0.05"
                    value={noiseReductionStrength}
                    onChange={e => setNoiseReductionStrength(parseFloat(e.target.value))}
                    style={styles.slider}
                  />
                </div>
              </div>
            </div>
          </div>

          {/* ══════════════════════════════════════════════════════════════ */}
          {/* CARD 3: 🤖 VIDEO & AI ENGINE (VIDEO & ENGINE) */}
          {/* ══════════════════════════════════════════════════════════════ */}
          <div style={{ ...styles.card, gridColumn: '1 / -1' }}>
            <div style={styles.cardHeader}>
              <Bot size={18} color="#38bdf8" />
              <h3 style={styles.cardTitle}>3. Video & AI Engine (Video & Engine)</h3>
            </div>

            {/* 🤖 CỤM 3.1: DỊCH THUẬT AI (LLM TRANSLATOR) */}
            <div style={{ marginBottom: 16, padding: '14px', backgroundColor: 'rgba(255, 255, 255, 0.02)', borderRadius: 8, border: '1px solid rgba(255, 255, 255, 0.08)' }}>
              <div style={{ fontSize: 13, fontWeight: 700, color: '#38bdf8', marginBottom: 10, display: 'flex', alignItems: 'center', gap: 6 }}>
                🤖 Cụm 3.1: Engine Dịch Thuật AI LLM (Translator)
              </div>

              <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 16 }}>
                <div style={styles.formGroup}>
                  <label style={styles.label}>Ngôn Ngữ Dịch Chính (`target_lang`):</label>
                  <select
                    value={targetLang}
                    onChange={e => setTargetLang(e.target.value)}
                    style={styles.select}
                  >
                    <option value="vi">🇻🇳 Tiếng Việt (vi - Mặc định)</option>
                    <option value="en">🇬🇧 Tiếng Anh (en)</option>
                    <option value="zh">🇨🇳 Tiếng Trung (zh)</option>
                    <option value="ja">🇯🇵 Tiếng Nhật (ja)</option>
                    <option value="ko">🇰🇷 Tiếng Hàn (ko)</option>
                    <option value="fr">🇫🇷 Tiếng Pháp (fr)</option>
                    <option value="de">🇩🇪 Tiếng Đức (de)</option>
                    <option value="es">🇪🇸 Tiếng Tây Ban Nha (es)</option>
                  </select>
                </div>

                <div style={styles.formGroup}>
                  <label style={styles.label}>Nhà Cung Cấp AI (`translator.type`):</label>
                  <select
                    value={translatorType}
                    onChange={e => handleTranslatorTypeChange(e.target.value)}
                    style={styles.select}
                  >
                    <option value="ollama">🦙 Ollama Local LLM (Chạy trên máy local)</option>
                    <option value="groq">⚡ Groq Cloud API (Llama-3.3-70b siêu nhanh)</option>
                    <option value="deepseek">🐳 DeepSeek AI API (DeepSeek Chat V3)</option>
                    <option value="gemini">✨ Google Gemini Cloud AI (OpenAI Compatible)</option>
                    <option value="openai">🧠 OpenAI ChatGPT (GPT-4o-mini)</option>
                  </select>
                </div>

                <div style={styles.formGroup}>
                  <label style={styles.label}>Tên Mô Hình AI (`translator.model`):</label>
                  <input
                    type="text"
                    value={translatorModel}
                    onChange={e => setTranslatorModel(e.target.value)}
                    placeholder="gemma4:31b-cloud / gpt-4o-mini / llama-3.3-70b-versatile"
                    style={styles.input}
                  />
                </div>

                <div style={styles.formGroup}>
                  <div style={styles.labelWithBadge}>
                    <label style={styles.label}>API Key (`translator.api_key`):</label>
                    <button
                      type="button"
                      onClick={() => setShowApiKey(!showApiKey)}
                      style={{
                        background: 'none',
                        border: 'none',
                        color: '#818cf8',
                        cursor: 'pointer',
                        fontSize: 11,
                        display: 'flex',
                        alignItems: 'center',
                        gap: 4,
                        padding: 0
                      }}
                    >
                      <Eye size={13} />
                      {showApiKey ? 'Ẩn Key' : 'Hiện Key'}
                    </button>
                  </div>
                  <input
                    type={showApiKey ? "text" : "password"}
                    value={translatorApiKey}
                    onChange={e => setTranslatorApiKey(e.target.value)}
                    placeholder="gsk_... / sk-... / bỏ trống nếu dùng Ollama"
                    style={styles.input}
                  />
                </div>

                <div style={styles.formGroup}>
                  <label style={styles.label}>Base URL Endpoint (`translator.base_url`):</label>
                  <input
                    type="text"
                    value={translatorBaseUrl}
                    onChange={e => setTranslatorBaseUrl(e.target.value)}
                    placeholder="http://localhost:11434 hoặc https://api.groq.com/openai/v1"
                    style={styles.input}
                  />
                </div>

                <div style={styles.formGroup}>
                  <div style={styles.labelWithBadge}>
                    <label style={styles.label}>Kích Thước Batch Gom Câu:</label>
                    <span style={styles.valueBadge}>{translatorBatchSize} câu</span>
                  </div>
                  <div style={styles.sliderWrapper}>
                    <input
                      type="range"
                      min="5"
                      max="50"
                      step="5"
                      value={translatorBatchSize}
                      onChange={e => setTranslatorBatchSize(parseInt(e.target.value, 10))}
                      style={styles.slider}
                    />
                  </div>
                </div>
              </div>
            </div>

            {/* 🔍 CỤM 3.2: NHẬN DIỆN CHỮ HARDSUB (OCR AI) */}
            <div style={{ marginBottom: 16, padding: '14px', backgroundColor: 'rgba(255, 255, 255, 0.02)', borderRadius: 8, border: '1px solid rgba(255, 255, 255, 0.08)' }}>
              <div style={{ fontSize: 13, fontWeight: 700, color: '#c084fc', marginBottom: 10, display: 'flex', alignItems: 'center', gap: 6 }}>
                🔍 Cụm 3.2: Nhận Diện Chữ Hardsub (OCR AI)
              </div>

              <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 16 }}>
                <div style={styles.formGroup}>
                  <label style={styles.label}>OCR Engine Subtitle (`ocr`):</label>
                  <select
                    value={ocrEngine}
                    onChange={e => setOcrEngine(e.target.value)}
                    style={styles.select}
                  >
                    <option value="apple_vision">🍏 Apple Native Vision (GPU/ANE Native Mac, Siêu Nhanh & Nhẹ)</option>
                    <option value="paddle_ocr">🇨🇳 PaddleOCR (CPU Multi-processing Đa Nhân)</option>
                    <option value="rapid_ocr">⚡ RapidOCR (ONNX CoreML / CPU)</option>
                  </select>
                  <div style={{ fontSize: 11, marginTop: 4, color: '#94a3b8' }}>
                    {ocrEngine === 'apple_vision' && '🍏 Tận dụng GPU & Neural Engine (ANE) chính chủ trên Mac M1/M2/M3.'}
                    {ocrEngine === 'paddle_ocr' && '🇨🇳 Chạy PaddleOCR trên CPU. Kết hợp với ocr_num_workers để bật đa nhân CPU.'}
                    {ocrEngine === 'rapid_ocr' && '⚡ ONNX Engine cross-platform.'}
                  </div>
                </div>

                <div style={styles.formGroup}>
                  <label style={styles.label}>Số Worker CPU PaddleOCR (`ocr_num_workers`):</label>
                  <select
                    value={ocrNumWorkers}
                    onChange={e => setOcrNumWorkers(e.target.value)}
                    style={styles.select}
                  >
                    <option value="2">⚡ 2 CPU Workers (Mặc định tối ưu - Khuyên dùng)</option>
                    <option value="1">1 Single Worker (Tối thiểu)</option>
                    <option value="4">4 CPU Workers</option>
                    <option value="auto">🚀 Auto (Giới hạn tối đa 2 Cores)</option>
                  </select>
                  <div style={{ fontSize: 11, marginTop: 4, color: '#94a3b8' }}>
                    Chia nhỏ video thành nhiều phân đoạn để tất cả các nhân CPU cùng xử lý song song.
                  </div>
                </div>
              </div>
            </div>

            {/* 🎬 CỤM 3.3: XUẤT VIDEO & TỐI ƯU TIMING */}
            <div style={{ padding: '14px', backgroundColor: 'rgba(255, 255, 255, 0.02)', borderRadius: 8, border: '1px solid rgba(255, 255, 255, 0.08)' }}>
              <div style={{ fontSize: 13, fontWeight: 700, color: '#4ade80', marginBottom: 10, display: 'flex', alignItems: 'center', gap: 6 }}>
                🎬 Cụm 3.3: Xuất Video & Tối Ưu Timing
              </div>

              <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 16 }}>
                <div style={styles.formGroup}>
                  <label style={styles.label}>Chế Độ Dịch (`ocr_only`):</label>
                  <select
                    value={ocrOnly ? 'true' : 'false'}
                    onChange={e => setOcrOnly(e.target.value === 'true')}
                    style={{
                      ...styles.select,
                      border: ocrOnly ? '1px solid #a855f7' : '1px solid #38bdf8',
                      backgroundColor: ocrOnly ? 'rgba(168, 85, 247, 0.1)' : 'rgba(56, 189, 248, 0.1)'
                    }}
                  >
                    <option value="true">📸 Dịch Sub Cứng (Visual OCR - Giữ nguyên 100% âm thanh gốc ~5s)</option>
                    <option value="false">🎙️ Dịch Giọng Nói (Demucs AI + Whisper ASR + EdgeTTS Thuyết Minh ~15s)</option>
                  </select>
                  <div style={{
                    fontSize: 11,
                    marginTop: 6,
                    padding: '6px 10px',
                    borderRadius: 6,
                    backgroundColor: ocrOnly ? 'rgba(168, 85, 247, 0.15)' : 'rgba(56, 189, 248, 0.15)',
                    color: ocrOnly ? '#e9d5ff' : '#bae6fd',
                    border: ocrOnly ? '1px solid rgba(168, 85, 247, 0.3)' : '1px solid rgba(56, 189, 248, 0.3)'
                  }}>
                    {ocrOnly
                      ? '📸 Đang bật Dịch Sub Cứng: Trích xuất sub hình ảnh bằng OCR Engine (Apple Vision / PaddleOCR), làm mờ sub cũ, đè sub mới & giữ nguyên 100% âm thanh gốc.'
                      : '🎙️ Đang bật Dịch Giọng Nói: Tách âm thanh Demucs, Whisper ASR nhận diện thoại, lồng tiếng TTS và phối âm thanh mới.'}
                  </div>
                </div>

                <div style={styles.formGroup}>
                  <label style={styles.label}>Chất Lượng Video Output (`video_bitrate`):</label>
                  <select
                    value={videoBitrate}
                    onChange={e => setVideoBitrate(e.target.value)}
                    style={styles.select}
                  >
                    <option value="4.0M">💎 4.0M - Sắc Nét HD (Khuyên dùng đăng TikTok / Reels / Shorts)</option>
                    <option value="2.5M">🎥 2.5M - Chuẩn nét HD mượt mà</option>
                    <option value="1.5M">📦 1.5M - Nhỏ gọn tiết kiệm dung lượng</option>
                    <option value="500K">⚡ 500K - Siêu nhẹ (Xem trước nhanh, tiết kiệm dung lượng)</option>
                  </select>
                </div>
              </div>
            </div>
          </div>
        </div>
      ) : (
        <div style={styles.rawCard}>
          <textarea
            value={configYaml}
            onChange={e => setConfigYaml(e.target.value)}
            style={styles.yamlTextarea}
            rows={24}
          />
        </div>
      )}
    </div>
  );
}

const styles = {
  container: {
    padding: 24,
    overflowY: 'auto',
    flex: 1,
    boxSizing: 'border-box'
  },
  header: {
    display: 'flex',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: 20
  },
  title: {
    fontSize: 22,
    fontWeight: 'bold',
    margin: 0,
    color: 'var(--text-main)'
  },
  subtitle: {
    fontSize: 13,
    color: 'var(--text-dim)',
    margin: '4px 0 0 0'
  },
  modeToggle: {
    display: 'flex',
    backgroundColor: 'var(--bg-surface)',
    borderRadius: 8,
    padding: 2,
    border: '1px solid var(--border-color)'
  },
  modeBtn: {
    backgroundColor: 'transparent',
    color: 'var(--text-muted)',
    border: 'none',
    padding: '8px 12px',
    borderRadius: 6,
    fontSize: 12,
    cursor: 'pointer',
    display: 'flex',
    alignItems: 'center'
  },
  modeBtnActive: {
    backgroundColor: 'var(--bg-card)',
    color: 'var(--primary)',
    fontWeight: '600',
    boxShadow: 'var(--shadow-sm)'
  },
  btnSave: {
    backgroundColor: 'var(--primary)',
    color: '#fff',
    border: 'none',
    padding: '10px 18px',
    borderRadius: 8,
    fontSize: 13,
    fontWeight: 'bold',
    cursor: 'pointer',
    display: 'flex',
    alignItems: 'center'
  },
  guiGrid: {
    display: 'grid',
    gridTemplateColumns: '1fr 1fr',
    gap: 20
  },
  card: {
    backgroundColor: 'var(--bg-card)',
    borderRadius: 12,
    padding: 20,
    border: '1px solid var(--border-color)',
    display: 'flex',
    flexDirection: 'column',
    gap: 16,
    boxShadow: 'var(--shadow-sm)'
  },
  cardHeader: {
    display: 'flex',
    alignItems: 'center',
    gap: 8,
    paddingBottom: 12,
    borderBottom: '1px solid var(--border-color)'
  },
  cardTitle: {
    fontSize: 15,
    fontWeight: 'bold',
    margin: 0,
    color: 'var(--text-main)'
  },
  formGroup: {
    display: 'flex',
    flexDirection: 'column',
    gap: 6
  },
  label: {
    fontSize: 12,
    fontWeight: '600',
    color: 'var(--text-muted)',
    minHeight: 18,
    display: 'flex',
    alignItems: 'center',
    whiteSpace: 'nowrap',
    overflow: 'hidden',
    textOverflow: 'ellipsis'
  },
  labelWithBadge: {
    display: 'flex',
    justifyContent: 'space-between',
    alignItems: 'center',
    minHeight: 18
  },
  valueBadge: {
    backgroundColor: 'var(--bg-surface)',
    color: 'var(--primary)',
    padding: '2px 8px',
    borderRadius: 6,
    fontSize: 11,
    fontWeight: 'bold',
    fontFamily: 'monospace',
    border: '1px solid var(--border-color)'
  },
  sliderWrapper: {
    height: 38,
    display: 'flex',
    alignItems: 'center',
    padding: '0 2px',
    boxSizing: 'border-box'
  },
  input: {
    padding: '8px 12px',
    height: 38,
    boxSizing: 'border-box',
    borderRadius: 8,
    backgroundColor: 'var(--bg-input)',
    color: 'var(--text-main)',
    border: '1px solid var(--border-color)',
    fontSize: 13
  },
  select: {
    padding: '8px 12px',
    height: 38,
    boxSizing: 'border-box',
    borderRadius: 8,
    backgroundColor: 'var(--bg-input)',
    color: 'var(--text-main)',
    border: '1px solid var(--border-color)',
    fontSize: 13,
    cursor: 'pointer'
  },
  slider: {
    width: '100%',
    accentColor: 'var(--primary)',
    cursor: 'pointer'
  },
  checkboxLabel: {
    display: 'flex',
    alignItems: 'center',
    gap: 8,
    fontSize: 13,
    color: 'var(--text-main)',
    cursor: 'pointer'
  },
  checkboxBox: {
    display: 'flex',
    alignItems: 'center',
    gap: 8,
    padding: '0 12px',
    backgroundColor: 'var(--bg-surface)',
    border: '1px solid var(--border-color)',
    borderRadius: 8,
    fontSize: 12,
    color: 'var(--text-main)',
    cursor: 'pointer',
    height: 38,
    boxSizing: 'border-box',
    userSelect: 'none'
  },
  hint: {
    fontSize: 11,
    color: 'var(--text-dim)',
    margin: 0
  },
  toggleRow: {
    display: 'flex',
    gap: 8
  },
  toggleBtn: {
    flex: 1,
    backgroundColor: 'var(--bg-surface)',
    color: 'var(--text-muted)',
    border: '1px solid var(--border-color)',
    padding: '8px 12px',
    borderRadius: 8,
    fontSize: 12,
    cursor: 'pointer'
  },
  toggleBtnActive: {
    backgroundColor: 'var(--primary-glow)',
    color: 'var(--primary)',
    borderColor: 'var(--primary)',
    fontWeight: 'bold'
  },
  subCardBox: {
    backgroundColor: 'var(--bg-surface)',
    borderRadius: 8,
    padding: 12,
    border: '1px solid var(--border-color)',
    display: 'flex',
    flexDirection: 'column',
    gap: 10
  },
  coordsGrid: {
    display: 'grid',
    gridTemplateColumns: 'repeat(4, 1fr)',
    gap: 8
  },
  coordBox: {
    display: 'flex',
    flexDirection: 'column',
    gap: 4
  },
  coordLabel: {
    fontSize: 11,
    color: 'var(--text-dim)',
    fontWeight: '600',
    textAlign: 'center',
    display: 'block'
  },
  inputCoord: {
    width: '100%',
    padding: '8px 4px',
    borderRadius: 6,
    backgroundColor: 'var(--bg-input)',
    color: 'var(--text-main)',
    border: '1px solid var(--border-color)',
    fontSize: 13,
    textAlign: 'center',
    fontWeight: 'bold',
    boxSizing: 'border-box'
  },
  rowTwoCol: {
    display: 'grid',
    gridTemplateColumns: '1fr 1fr',
    gap: 12
  },
  rawCard: {
    backgroundColor: 'var(--bg-card)',
    borderRadius: 12,
    padding: 16,
    border: '1px solid var(--border-color)'
  },
  yamlTextarea: {
    width: '100%',
    backgroundColor: 'var(--bg-input)',
    color: 'var(--text-main)',
    border: '1px solid var(--border-color)',
    borderRadius: 8,
    padding: 16,
    fontFamily: 'monospace',
    fontSize: 13,
    boxSizing: 'border-box',
    outline: 'none'
  }
};
