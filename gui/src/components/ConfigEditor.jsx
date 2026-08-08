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

export default function ConfigEditor({ project }) {
  const [configYaml, setConfigYaml] = useState('');
  const [mode, setMode] = useState('gui'); // 'gui' | 'raw'
  const [isSaved, setIsSaved] = useState(false);
  const [configPath, setConfigPath] = useState('');

  // 🎯 Group 1: Subtitle & Inpaint Region
  const [inpaintRegionMode, setInpaintRegionMode] = useState('auto'); // 'auto' | 'manual'
  const [inpaintRegion, setInpaintRegion] = useState([0.67, 0.05, 0.75, 0.95]);
  const [detectStartSec, setDetectStartSec] = useState(5.0);
  const [detectDurationSec, setDetectDurationSec] = useState(10.0);
  const [inpaintPlugin, setInpaintPlugin] = useState('ffmpeg_blur');
  const [blurRadius, setBlurRadius] = useState(15);
  const [subtitleFontSize, setSubtitleFontSize] = useState(28);
  const [showSubtitle, setShowSubtitle] = useState(true);

  // 🖼️ Group 2: Logo / Watermark
  const [watermarkEnable, setWatermarkEnable] = useState(true);
  const [watermarkRegion, setWatermarkRegion] = useState([0.02, 0.85, 0.05, 0.95]);
  const [watermarkImage, setWatermarkImage] = useState('');
  const [watermarkText, setWatermarkText] = useState('Sub-Video AI');
  const [watermarkFontColor, setWatermarkFontColor] = useState('white');
  const [watermarkOpacity, setWatermarkOpacity] = useState(0.85);
  const [watermarkBlurBg, setWatermarkBlurBg] = useState(true);

  // 🗣️ Group 3: Voice & TTS Settings
  const [ttsVoice, setTtsVoice] = useState('vi');
  const [enableGenderTts, setEnableGenderTts] = useState(false);
  const [ttsVoiceMale, setTtsVoiceMale] = useState('vi-VN-NamMinhNeural');
  const [ttsVoiceFemale, setTtsVoiceFemale] = useState('vi');
  const [ttsSpeedFactor, setTtsSpeedFactor] = useState(1.2);

  // 🎛️ Group 4: Audio Mixing
  const [ttsVoiceVolume, setTtsVoiceVolume] = useState(1.0);
  const [musicVolume, setMusicVolume] = useState(0.5);
  const [ambientVolume, setAmbientVolume] = useState(0.75);
  const [originalVoiceVolume, setOriginalVoiceVolume] = useState(0.05);
  const [noiseReductionStrength, setNoiseReductionStrength] = useState(0.9);

  // 🤖 Group 5: Translation LLM & OCR AI
  const [ocrOnly, setOcrOnly] = useState(true);
  const [ocrMode, setOcrMode] = useState('region');
  const [translatorType, setTranslatorType] = useState('ollama');
  const [translatorModel, setTranslatorModel] = useState('gemma4:31b-cloud');
  const [translatorApiKey, setTranslatorApiKey] = useState('');
  const [translatorBaseUrl, setTranslatorBaseUrl] = useState('http://localhost:11434');
  const [translatorBatchSize, setTranslatorBatchSize] = useState(20);

  useEffect(() => {
    if (project) {
      loadConfig();
    }
  }, [project]);

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
    const getValue = (key, defaultVal, type = 'string') => {
      // Find un-commented key
      const match = yamlStr.match(new RegExp(`^${key}:\\s*(.+)`, 'm'));
      if (!match) return defaultVal;
      let rawStr = match[1].split('#')[0].trim();
      rawStr = rawStr.replace(/^["']|["']$/g, '');

      if (type === 'boolean') return rawStr === 'true';
      if (type === 'float') return parseFloat(rawStr) || defaultVal;
      if (type === 'int') return parseInt(rawStr, 10) || defaultVal;
      if (type === 'array') {
        try {
          const arrMatch = rawStr.match(/\[(.*?)\]/);
          if (arrMatch) {
            return arrMatch[1].split(',').map(v => parseFloat(v.trim()));
          }
        } catch (e) {}
        return defaultVal;
      }
      return rawStr;
    };

    // Check if inpaint_region is active (un-commented) or auto (commented)
    const inpaintActiveMatch = yamlStr.match(/^inpaint_region:\s*\[(.*?)\]/m);
    if (inpaintActiveMatch) {
      setInpaintRegionMode('manual');
      try {
        const arr = inpaintActiveMatch[1].split(',').map(v => parseFloat(v.trim()));
        if (arr.length === 4) setInpaintRegion(arr);
      } catch (e) {}
    } else {
      setInpaintRegionMode('auto');
    }

    setDetectStartSec(getValue('subtitle_detect_start_sec', 5.0, 'float'));
    setDetectDurationSec(getValue('subtitle_detect_duration_sec', 10.0, 'float'));
    setInpaintPlugin(getValue('inpaint', 'ffmpeg_blur'));
    setBlurRadius(getValue('blur_radius', 15, 'int'));
    setSubtitleFontSize(getValue('subtitle_font_size', 28, 'int'));
    setShowSubtitle(getValue('show_subtitle', true, 'boolean'));

    setWatermarkEnable(getValue('watermark_enable', true, 'boolean'));
    setWatermarkRegion(getValue('watermark_region', [0.02, 0.85, 0.05, 0.95], 'array'));
    setWatermarkImage(getValue('watermark_image', ''));
    setWatermarkText(getValue('watermark_text', 'Sub-Video AI'));
    setWatermarkFontColor(getValue('watermark_font_color', 'white'));
    setWatermarkOpacity(getValue('watermark_opacity', 0.85, 'float'));
    setWatermarkBlurBg(getValue('watermark_blur_bg', true, 'boolean'));

    setTtsVoice(getValue('tts_voice', 'vi'));
    setEnableGenderTts(getValue('enable_gender_tts', false, 'boolean'));
    setTtsVoiceMale(getValue('tts_voice_male', 'vi-VN-NamMinhNeural'));
    setTtsVoiceFemale(getValue('tts_voice_female', 'vi'));
    setTtsSpeedFactor(getValue('tts_speed_factor', 1.2, 'float'));

    setTtsVoiceVolume(getValue('tts_voice_volume', 1.0, 'float'));
    setMusicVolume(getValue('music_volume', 0.5, 'float'));
    setAmbientVolume(getValue('ambient_volume', 0.75, 'float'));
    setOriginalVoiceVolume(getValue('original_voice_volume', 0.05, 'float'));
    setNoiseReductionStrength(getValue('noise_reduction_strength', 0.9, 'float'));

    setOcrOnly(getValue('ocr_only', true, 'boolean'));
    setOcrMode(getValue('ocr_mode', 'region'));

    // Parse unified translator block
    const translatorBlockMatch = yamlStr.match(/^translator:\s*\n((?:\s+.*\n?)*)/m);
    if (translatorBlockMatch) {
      const blockStr = translatorBlockMatch[1];
      const typeMatch = blockStr.match(/^\s+type:\s*["']?([^"'\s#]+)["']?/m);
      const modelMatch = blockStr.match(/^\s+model:\s*["']?([^"'\s#]+)["']?/m);
      const apiKeyMatch = blockStr.match(/^\s+api_key:\s*["']?([^"'\s#]*)["']?/m);
      const baseUrlMatch = blockStr.match(/^\s+base_url:\s*["']?([^"'\s#]+)["']?/m);
      const batchMatch = blockStr.match(/^\s+batch_size:\s*(\d+)/m);

      if (typeMatch) setTranslatorType(typeMatch[1]);
      if (modelMatch) setTranslatorModel(modelMatch[1]);
      if (apiKeyMatch) setTranslatorApiKey(apiKeyMatch[1] || '');
      if (baseUrlMatch) setTranslatorBaseUrl(baseUrlMatch[1]);
      if (batchMatch) setTranslatorBatchSize(parseInt(batchMatch[1], 10) || 20);
    } else {
      setTranslatorType(getValue('translator', 'ollama'));
      setTranslatorModel(getValue('translator_model', 'gemma4:31b-cloud'));
      setTranslatorApiKey(getValue('openai_api_key', ''));
      setTranslatorBaseUrl(getValue('openai_base_url', '') || getValue('ollama_host', 'http://localhost:11434'));
      setTranslatorBatchSize(getValue('translator_batch_size', 20, 'int'));
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

  const updateYamlValue = (yamlStr, key, val, isCommented = false) => {
    let formattedVal = val;
    if (typeof val === 'string' && !val.startsWith('[')) {
      formattedVal = `"${val}"`;
    } else if (Array.isArray(val)) {
      formattedVal = `[${val.map(v => typeof v === 'number' ? v.toFixed(2) : v).join(', ')}]`;
    }

    const regexActive = new RegExp(`^${key}:.*`, 'm');
    const regexCommented = new RegExp(`^#\\s*${key}:.*`, 'm');

    if (isCommented) {
      if (regexActive.test(yamlStr)) {
        return yamlStr.replace(regexActive, `# ${key}: ${formattedVal}`);
      } else if (regexCommented.test(yamlStr)) {
        return yamlStr.replace(regexCommented, `# ${key}: ${formattedVal}`);
      } else {
        return `${yamlStr}\n# ${key}: ${formattedVal}`;
      }
    } else {
      if (regexActive.test(yamlStr)) {
        return yamlStr.replace(regexActive, `${key}: ${formattedVal}`);
      } else if (regexCommented.test(yamlStr)) {
        return yamlStr.replace(regexCommented, `${key}: ${formattedVal}`);
      } else {
        return `${yamlStr}\n${key}: ${formattedVal}`;
      }
    }
  };

  const handleSave = async () => {
    let finalYaml = configYaml;

    if (mode === 'gui') {
      if (inpaintRegionMode === 'auto') {
        finalYaml = updateYamlValue(finalYaml, 'inpaint_region', `[${inpaintRegion.join(', ')}]`, true);
      } else {
        finalYaml = updateYamlValue(finalYaml, 'inpaint_region', inpaintRegion, false);
      }

      finalYaml = updateYamlValue(finalYaml, 'subtitle_detect_start_sec', detectStartSec, false);
      finalYaml = updateYamlValue(finalYaml, 'subtitle_detect_duration_sec', detectDurationSec, false);
      finalYaml = updateYamlValue(finalYaml, 'inpaint', inpaintPlugin, false);
      finalYaml = updateYamlValue(finalYaml, 'blur_radius', blurRadius, false);
      finalYaml = updateYamlValue(finalYaml, 'subtitle_font_size', subtitleFontSize, false);
      finalYaml = updateYamlValue(finalYaml, 'show_subtitle', showSubtitle, false);

      finalYaml = updateYamlValue(finalYaml, 'watermark_enable', watermarkEnable, false);
      finalYaml = updateYamlValue(finalYaml, 'watermark_region', watermarkRegion, false);
      finalYaml = updateYamlValue(finalYaml, 'watermark_text', watermarkText, false);
      finalYaml = updateYamlValue(finalYaml, 'watermark_image', watermarkImage, false);
      finalYaml = updateYamlValue(finalYaml, 'watermark_font_color', watermarkFontColor, false);
      finalYaml = updateYamlValue(finalYaml, 'watermark_opacity', watermarkOpacity, false);
      finalYaml = updateYamlValue(finalYaml, 'watermark_blur_bg', watermarkBlurBg, false);

      finalYaml = updateYamlValue(finalYaml, 'tts_voice', ttsVoice, false);
      finalYaml = updateYamlValue(finalYaml, 'enable_gender_tts', enableGenderTts, false);
      finalYaml = updateYamlValue(finalYaml, 'tts_voice_male', ttsVoiceMale, false);
      finalYaml = updateYamlValue(finalYaml, 'tts_voice_female', ttsVoiceFemale, false);
      finalYaml = updateYamlValue(finalYaml, 'tts_speed_factor', ttsSpeedFactor, false);

      finalYaml = updateYamlValue(finalYaml, 'tts_voice_volume', ttsVoiceVolume, false);
      finalYaml = updateYamlValue(finalYaml, 'music_volume', musicVolume, false);
      finalYaml = updateYamlValue(finalYaml, 'ambient_volume', ambientVolume, false);
      finalYaml = updateYamlValue(finalYaml, 'original_voice_volume', originalVoiceVolume, false);
      finalYaml = updateYamlValue(finalYaml, 'noise_reduction_strength', noiseReductionStrength, false);

      finalYaml = updateYamlValue(finalYaml, 'ocr_only', ocrOnly, false);
      finalYaml = updateYamlValue(finalYaml, 'ocr_mode', ocrMode, false);

      const newTranslatorBlock = [
        'translator:',
        `  type: "${translatorType}"`,
        `  model: "${translatorModel}"`,
        `  api_key: "${translatorApiKey}"`,
        `  base_url: "${translatorBaseUrl}"`,
        `  batch_size: ${translatorBatchSize}`
      ].join('\n');

      if (/^translator:\s*\n((?:\s+.*\n?)*)/m.test(finalYaml)) {
        finalYaml = finalYaml.replace(/^translator:\s*\n((?:\s+.*\n?)*)/m, `${newTranslatorBlock}\n`);
      } else if (/^translator:\s*.*/m.test(finalYaml)) {
        finalYaml = finalYaml.replace(/^translator:\s*.*/m, newTranslatorBlock);
      } else {
        finalYaml = `${finalYaml}\n\n${newTranslatorBlock}`;
      }

      finalYaml = finalYaml.replace(/^#?\s*translator_model:.*\n?/gm, '');
      finalYaml = finalYaml.replace(/^#?\s*translator_batch_size:.*\n?/gm, '');
      finalYaml = finalYaml.replace(/^#?\s*openai_api_key:.*\n?/gm, '');
      finalYaml = finalYaml.replace(/^#?\s*openai_base_url:.*\n?/gm, '');
      finalYaml = finalYaml.replace(/^#?\s*ollama_host:.*\n?/gm, '');
    }

    try {
      await saveProjectConfig(project, finalYaml);
      setConfigYaml(finalYaml);
      setIsSaved(true);
      setTimeout(() => setIsSaved(false), 2500);
    } catch (e) {
      console.error('Save config failed:', e);
    }
  };

  const updateInpaintRegionCoord = (idx, val) => {
    const next = [...inpaintRegion];
    next[idx] = parseFloat(val) || 0.0;
    setInpaintRegion(next);
  };

  const updateWatermarkRegionCoord = (idx, val) => {
    const next = [...watermarkRegion];
    next[idx] = parseFloat(val) || 0.0;
    setWatermarkRegion(next);
  };

  return (
    <div style={styles.container}>
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
          {/* Group 1: Subtitle & Inpaint Region */}
          <div style={styles.card}>
            <div style={styles.cardHeader}>
              <Type size={18} color="#818cf8" />
              <h3 style={styles.cardTitle}>1. Phụ Đề & Vùng Xóa Sub Cũ (Inpainting)</h3>
            </div>

            {/* Mode Switch: Auto vs Manual */}
            <div style={styles.formGroup}>
              <label style={styles.label}>Vị Trí Xóa Sub Cũ (`inpaint_region`):</label>
              <div style={styles.toggleRow}>
                <button
                  type="button"
                  onClick={() => setInpaintRegionMode('auto')}
                  style={{ ...styles.toggleBtn, ...(inpaintRegionMode === 'auto' ? styles.toggleBtnActive : {}) }}
                >
                  ✨ Auto Detect (Frame Diff)
                </button>
                <button
                  type="button"
                  onClick={() => setInpaintRegionMode('manual')}
                  style={{ ...styles.toggleBtn, ...(inpaintRegionMode === 'manual' ? styles.toggleBtnActive : {}) }}
                >
                  📐 Manual Override (Chỉnh Tay)
                </button>
              </div>
            </div>

            {inpaintRegionMode === 'auto' ? (
              <div style={styles.subCardBox}>
                <div style={styles.formGroup}>
                  <label style={styles.label}>Giây bắt đầu quét (`subtitle_detect_start_sec`):</label>
                  <input
                    type="number"
                    step="0.5"
                    value={detectStartSec}
                    onChange={e => setDetectStartSec(parseFloat(e.target.value) || 5.0)}
                    style={styles.input}
                  />
                  <span style={styles.hint}>Tránh các frame intro tối hoặc logo đầu video</span>
                </div>

                <div style={styles.formGroup}>
                  <label style={styles.label}>Thời gian quét (`subtitle_detect_duration_sec`):</label>
                  <input
                    type="number"
                    step="1"
                    value={detectDurationSec}
                    onChange={e => setDetectDurationSec(parseFloat(e.target.value) || 10.0)}
                    style={styles.input}
                  />
                  <span style={styles.hint}>Quét trong bao nhiêu giây để tự tính heat map vị trí sub</span>
                </div>
              </div>
            ) : (
              <div style={styles.subCardBox}>
                <label style={styles.label}>Thông số vùng manual [Top, Left, Bottom, Right] (tỷ lệ 0.0 → 1.0):</label>
                <div style={styles.coordsGrid}>
                  <div>
                    <span style={styles.coordLabel}>Top:</span>
                    <input
                      type="number"
                      step="0.01"
                      min="0"
                      max="1"
                      value={inpaintRegion[0]}
                      onChange={e => updateInpaintRegionCoord(0, e.target.value)}
                      style={styles.inputCoord}
                    />
                  </div>
                  <div>
                    <span style={styles.coordLabel}>Left:</span>
                    <input
                      type="number"
                      step="0.01"
                      min="0"
                      max="1"
                      value={inpaintRegion[1]}
                      onChange={e => updateInpaintRegionCoord(1, e.target.value)}
                      style={styles.inputCoord}
                    />
                  </div>
                  <div>
                    <span style={styles.coordLabel}>Bottom:</span>
                    <input
                      type="number"
                      step="0.01"
                      min="0"
                      max="1"
                      value={inpaintRegion[2]}
                      onChange={e => updateInpaintRegionCoord(2, e.target.value)}
                      style={styles.inputCoord}
                    />
                  </div>
                  <div>
                    <span style={styles.coordLabel}>Right:</span>
                    <input
                      type="number"
                      step="0.01"
                      min="0"
                      max="1"
                      value={inpaintRegion[3]}
                      onChange={e => updateInpaintRegionCoord(3, e.target.value)}
                      style={styles.inputCoord}
                    />
                  </div>
                </div>
              </div>
            )}

            {/* Dropdown inpaint plugin */}
            <div style={styles.formGroup}>
              <label style={styles.label}>Phương Pháp Làm Mờ (`inpaint`):</label>
              <select
                value={inpaintPlugin}
                onChange={e => setInpaintPlugin(e.target.value)}
                style={styles.select}
              >
                <option value="ffmpeg_blur">⚡ ffmpeg_blur (Siêu nhanh ~1s, dải mờ mịn)</option>
                <option value="opencv">🎨 opencv (Xóa chi tiết nét chữ ~15s)</option>
              </select>
            </div>

            <div style={styles.rowTwoCol}>
              <div style={styles.formGroup}>
                <label style={styles.label}>Độ mịn kính (`blur_radius`):</label>
                <input
                  type="number"
                  min="5"
                  max="40"
                  value={blurRadius}
                  onChange={e => setBlurRadius(parseInt(e.target.value, 10) || 15)}
                  style={styles.input}
                />
              </div>

              <div style={styles.formGroup}>
                <label style={styles.label}>Font Size sub mới (`subtitle_font_size`):</label>
                <input
                  type="number"
                  min="16"
                  max="60"
                  value={subtitleFontSize}
                  onChange={e => setSubtitleFontSize(parseInt(e.target.value, 10) || 28)}
                  style={styles.input}
                />
              </div>
            </div>

            <div style={styles.formGroup}>
              <label style={styles.checkboxLabel}>
                <input
                  type="checkbox"
                  checked={showSubtitle}
                  onChange={e => setShowSubtitle(e.target.checked)}
                />
                <span style={{ fontWeight: 'bold' }}>Hiển thị phụ đề tiếng Việt mới (`show_subtitle`)</span>
              </label>
            </div>
          </div>

          {/* Group 2: Logo / Watermark */}
          <div style={styles.card}>
            <div style={styles.cardHeader}>
              <ImageIcon size={18} color="#10b981" />
              <h3 style={styles.cardTitle}>2. Logo / Watermark Thương Hiệu</h3>
            </div>

            <div style={styles.formGroup}>
              <label style={styles.checkboxLabel}>
                <input
                  type="checkbox"
                  checked={watermarkEnable}
                  onChange={e => setWatermarkEnable(e.target.checked)}
                />
                <span style={{ fontWeight: 'bold' }}>Bật Watermark / Thương Hiệu (`watermark_enable`)</span>
              </label>
            </div>

            <div style={styles.formGroup}>
              <label style={styles.label}>Tên chữ Watermark (`watermark_text`):</label>
              <input
                type="text"
                value={watermarkText}
                onChange={e => setWatermarkText(e.target.value)}
                style={styles.input}
              />
            </div>

            <div style={styles.formGroup}>
              <label style={styles.label}>Đường dẫn ảnh Logo (Nếu có) (`watermark_image`):</label>
              <input
                type="text"
                placeholder="assets/logo.png (Để trống nếu dùng text)..."
                value={watermarkImage}
                onChange={e => setWatermarkImage(e.target.value)}
                style={styles.input}
              />
            </div>

            <div style={styles.rowTwoCol}>
              <div style={styles.formGroup}>
                <label style={styles.label}>Màu Chữ Watermark:</label>
                <select
                  value={watermarkFontColor}
                  onChange={e => setWatermarkFontColor(e.target.value)}
                  style={styles.select}
                >
                  <option value="white">⚪ Trắng (white)</option>
                  <option value="yellow">🟡 Vàng (yellow)</option>
                  <option value="black">⚫ Đen (black)</option>
                  <option value="red">🔴 Đỏ (red)</option>
                  <option value="gold">🌟 Vàng Kim (gold)</option>
                </select>
              </div>

              <div style={styles.formGroup}>
                <label style={styles.label}>Độ Đục (`watermark_opacity`): {watermarkOpacity}</label>
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
              <label style={styles.label}>Vị Trí Watermark `[top, left, bottom, right]`:</label>
              <div style={styles.coordsGrid}>
                {watermarkRegion.map((val, idx) => (
                  <div key={idx}>
                    <span style={styles.coordLabel}>{['Top', 'Left', 'Bot', 'Right'][idx]}:</span>
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
          </div>

          {/* Group 3: Voice & TTS Settings */}
          <div style={styles.card}>
            <div style={styles.cardHeader}>
              <Sparkles size={18} color="#f59e0b" />
              <h3 style={styles.cardTitle}>3. Giọng Đọc AI & Đọc Thuyết Minh (TTS)</h3>
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
              </select>
            </div>

            <div style={styles.formGroup}>
              <label style={styles.checkboxLabel}>
                <input
                  type="checkbox"
                  checked={enableGenderTts}
                  onChange={e => setEnableGenderTts(e.target.checked)}
                />
                <span style={{ fontWeight: 'bold' }}>Tự đổi giọng Nam/Nữ theo nhân vật (`enable_gender_tts`)</span>
              </label>
            </div>

            {enableGenderTts && (
              <div style={styles.subCardBox}>
                <div style={styles.formGroup}>
                  <label style={styles.label}>Giọng Nam (`tts_voice_male`):</label>
                  <select
                    value={ttsVoiceMale}
                    onChange={e => setTtsVoiceMale(e.target.value)}
                    style={styles.select}
                  >
                    <option value="vi-VN-NamMinhNeural">Nam Minh Neural (EdgeTTS)</option>
                  </select>
                </div>

                <div style={styles.formGroup}>
                  <label style={styles.label}>Giọng Nữ (`tts_voice_female`):</label>
                  <select
                    value={ttsVoiceFemale}
                    onChange={e => setTtsVoiceFemale(e.target.value)}
                    style={styles.select}
                  >
                    <option value="vi">Ban Mai gTTS</option>
                    <option value="vi-VN-HoaiMyNeural">Hoài Mỹ Neural (EdgeTTS)</option>
                  </select>
                </div>
              </div>
            )}

            <div style={styles.formGroup}>
              <label style={styles.label}>Tốc Độ Đọc TTS (`tts_speed_factor`): {ttsSpeedFactor}x</label>
              <input
                type="range"
                min="0.8"
                max="2.0"
                step="0.1"
                value={ttsSpeedFactor}
                onChange={e => setTtsSpeedFactor(parseFloat(e.target.value))}
                style={styles.slider}
              />
            </div>
          </div>

          {/* Group 4: Audio Mixing */}
          <div style={styles.card}>
            <div style={styles.cardHeader}>
              <Volume2 size={18} color="#ec4899" />
              <h3 style={styles.cardTitle}>4. Trộn Âm Thanh & Lọc Tiếng Ù (Audio Mixer)</h3>
            </div>

            <div style={styles.formGroup}>
              <label style={styles.label}>Âm Lượng Giọng Đọc TTS (`tts_voice_volume`): {ttsVoiceVolume}</label>
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

            <div style={styles.formGroup}>
              <label style={styles.label}>Âm Lượng Nhạc Nền (`music_volume`): {musicVolume}</label>
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

            <div style={styles.formGroup}>
              <label style={styles.label}>Âm Lượng Giọng Gốc (`original_voice_volume`): {originalVoiceVolume}</label>
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

            <div style={styles.formGroup}>
              <label style={styles.label}>Độ Lọc Tiếng Ù Spectral Gate (`noise_reduction_strength`): {noiseReductionStrength}</label>
              <input
                type="range"
                min="0.5"
                max="1.0"
                step="0.05"
                value={noiseReductionStrength}
                onChange={e => setNoiseReductionStrength(parseFloat(e.target.value))}
                style={styles.slider}
              />
            </div>
          </div>

          {/* Group 5: Translation LLM & OCR AI */}
          <div style={{ ...styles.card, gridColumn: '1 / -1' }}>
            <div style={styles.cardHeader}>
              <Bot size={18} color="#38bdf8" />
              <h3 style={styles.cardTitle}>5. Engine Dịch Thuật AI LLM & OCR Subtitle (Unified Provider)</h3>
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
                    ? '📸 Đang bật Dịch Sub Cứng: Trích xuất sub hình ảnh bằng PaddleOCR, làm mờ sub cũ, đè sub mới & giữ nguyên 100% âm thanh gốc.' 
                    : '🎙️ Đang bật Dịch Giọng Nói: Tách âm thanh Demucs, Whisper ASR nhận diện thoại, lồng tiếng TTS và phối âm thanh mới.'}
                </div>
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
                  style={styles.inputText}
                />
              </div>

              <div style={styles.formGroup}>
                <label style={styles.label}>API Key (`translator.api_key`):</label>
                <input
                  type="password"
                  value={translatorApiKey}
                  onChange={e => setTranslatorApiKey(e.target.value)}
                  placeholder="Bỏ trống nếu dùng Ollama hoặc đã đặt qua ENV variable"
                  style={styles.inputText}
                />
              </div>

              <div style={styles.formGroup}>
                <label style={styles.label}>Base URL Endpoint (`translator.base_url`):</label>
                <input
                  type="text"
                  value={translatorBaseUrl}
                  onChange={e => setTranslatorBaseUrl(e.target.value)}
                  placeholder="http://localhost:11434 hoặc https://api.groq.com/openai/v1"
                  style={styles.inputText}
                />
              </div>

              <div style={styles.formGroup}>
                <label style={styles.label}>Kích Thước Batch Gom Câu (`translator.batch_size`): {translatorBatchSize} câu</label>
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
    color: '#f8fafc'
  },
  subtitle: {
    fontSize: 13,
    color: '#64748b',
    margin: '4px 0 0 0'
  },
  modeToggle: {
    display: 'flex',
    backgroundColor: '#1e293b',
    borderRadius: 8,
    padding: 2,
    border: '1px solid #334155'
  },
  modeBtn: {
    backgroundColor: 'transparent',
    color: '#94a3b8',
    border: 'none',
    padding: '8px 12px',
    borderRadius: 6,
    fontSize: 12,
    cursor: 'pointer',
    display: 'flex',
    alignItems: 'center'
  },
  modeBtnActive: {
    backgroundColor: '#334155',
    color: '#818cf8',
    fontWeight: '600'
  },
  btnSave: {
    backgroundColor: '#6366f1',
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
    backgroundColor: '#1e293b',
    borderRadius: 12,
    padding: 20,
    border: '1px solid #334155',
    display: 'flex',
    flexDirection: 'column',
    gap: 16
  },
  cardHeader: {
    display: 'flex',
    alignItems: 'center',
    gap: 8,
    paddingBottom: 12,
    borderBottom: '1px solid #334155'
  },
  cardTitle: {
    fontSize: 15,
    fontWeight: 'bold',
    margin: 0,
    color: '#f8fafc'
  },
  formGroup: {
    display: 'flex',
    flexDirection: 'column',
    gap: 6
  },
  label: {
    fontSize: 12,
    fontWeight: '600',
    color: '#94a3b8'
  },
  input: {
    padding: '8px 12px',
    borderRadius: 8,
    backgroundColor: '#0f172a',
    color: '#f8fafc',
    border: '1px solid #334155',
    fontSize: 13
  },
  select: {
    padding: '8px 12px',
    borderRadius: 8,
    backgroundColor: '#0f172a',
    color: '#f8fafc',
    border: '1px solid #334155',
    fontSize: 13,
    cursor: 'pointer'
  },
  slider: {
    accentColor: '#6366f1',
    cursor: 'pointer'
  },
  checkboxLabel: {
    display: 'flex',
    alignItems: 'center',
    gap: 8,
    fontSize: 13,
    color: '#f8fafc',
    cursor: 'pointer'
  },
  hint: {
    fontSize: 11,
    color: '#64748b',
    margin: 0
  },
  toggleRow: {
    display: 'flex',
    gap: 8
  },
  toggleBtn: {
    flex: 1,
    backgroundColor: '#0f172a',
    color: '#94a3b8',
    border: '1px solid #334155',
    padding: '8px 12px',
    borderRadius: 8,
    fontSize: 12,
    cursor: 'pointer'
  },
  toggleBtnActive: {
    backgroundColor: 'rgba(99, 102, 241, 0.2)',
    color: '#818cf8',
    borderColor: '#6366f1',
    fontWeight: 'bold'
  },
  subCardBox: {
    backgroundColor: '#0f172a',
    borderRadius: 8,
    padding: 12,
    border: '1px solid #334155',
    display: 'flex',
    flexDirection: 'column',
    gap: 10
  },
  coordsGrid: {
    display: 'grid',
    gridTemplateColumns: 'repeat(4, 1fr)',
    gap: 8
  },
  coordLabel: {
    fontSize: 11,
    color: '#64748b',
    marginBottom: 2,
    display: 'block'
  },
  inputCoord: {
    width: '100%',
    padding: '6px 8px',
    borderRadius: 6,
    backgroundColor: '#1e293b',
    color: '#f8fafc',
    border: '1px solid #334155',
    fontSize: 12,
    textAlign: 'center'
  },
  rowTwoCol: {
    display: 'grid',
    gridTemplateColumns: '1fr 1fr',
    gap: 12
  },
  rawCard: {
    backgroundColor: '#1e293b',
    borderRadius: 12,
    padding: 16,
    border: '1px solid #334155'
  },
  yamlTextarea: {
    width: '100%',
    backgroundColor: '#0f172a',
    color: '#38bdf8',
    border: '1px solid #334155',
    borderRadius: 8,
    padding: 16,
    fontFamily: 'monospace',
    fontSize: 13,
    boxSizing: 'border-box',
    outline: 'none'
  }
};
