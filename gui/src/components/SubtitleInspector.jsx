import React, { useState, useEffect, useRef } from 'react';
import { 
  Languages, 
  Sparkles, 
  Plus, 
  RefreshCw, 
  Check, 
  Edit3, 
  Trash2, 
  Clock, 
  Sliders, 
  Type, 
  Palette, 
  Zap,
  CheckCircle2,
  FileText,
  Volume2,
  Settings,
  Save,
  Video,
  Eye,
  SlidersHorizontal,
  Bot
} from 'lucide-react';

const formatSubtitleTime = (sec) => {
  if (sec === null || sec === undefined || isNaN(sec) || sec < 0) return '00:00:00,000';
  const hrs = Math.floor(sec / 3600);
  const mins = Math.floor((sec % 3600) / 60);
  const secs = Math.floor(sec % 60);
  const ms = Math.floor((sec % 1) * 1000);
  return `${hrs.toString().padStart(2, '0')}:${mins.toString().padStart(2, '0')}:${secs.toString().padStart(2, '0')},${ms.toString().padStart(3, '0')}`;
};

const parseTimecodeToSeconds = (str) => {
  if (typeof str === 'number') return Math.max(0, str);
  if (!str || typeof str !== 'string') return 0;
  const s = str.trim().replace(',', '.');
  if (s.includes(':')) {
    const parts = s.split(':');
    if (parts.length === 3) {
      const h = parseFloat(parts[0]) || 0;
      const m = parseFloat(parts[1]) || 0;
      const sec = parseFloat(parts[2]) || 0;
      return Math.max(0, h * 3600 + m * 60 + sec);
    }
    if (parts.length === 2) {
      const m = parseFloat(parts[0]) || 0;
      const sec = parseFloat(parts[1]) || 0;
      return Math.max(0, m * 60 + sec);
    }
  }
  const f = parseFloat(s);
  return isNaN(f) ? 0 : Math.max(0, f);
};

export const parseYamlRobust = (yaml) => {
  if (!yaml || typeof yaml !== 'string') return {};
  const lines = yaml.split('\n');
  const result = {};
  let currentSection = null;
  let currentSubSection = null;
  let subIndent = 0;

  for (let rawLine of lines) {
    const lineWithoutComment = rawLine.split('#')[0];
    if (!lineWithoutComment.trim()) continue;

    const indent = rawLine.match(/^(\s*)/)[1].length;
    const line = lineWithoutComment.trim();

    const rootMatch = line.match(/^([a-zA-Z0-9_-]+):$/);
    if (indent === 0 && rootMatch) {
      currentSection = rootMatch[1];
      result[currentSection] = {};
      currentSubSection = null;
      continue;
    }

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
          } catch(e) {
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

export const parseYamlToCfg = (yamlStr) => {
  const y = parseYamlRobust(yamlStr);
  if (!y || Object.keys(y).length === 0) return {};

  const app = y.app || {};
  const sub = y.subtitle || {};
  const inp = y.inpaint || {};
  const box = inp.box || sub.box || {};
  const wm = y.watermark || {};
  const tts = y.tts || {};
  const audio = y.audio || {};
  const vols = audio.volumes || {};
  const trans = y.translator || {};

  const inpaintRegion = inp.region || y.inpaint_region || (Array.isArray(inp) ? inp : null);
  const wmRegion = wm.region || (Array.isArray(wm) ? wm : [0.02, 0.02, 0.08, 0.30]);

  return {
    video_bitrate: app.video_bitrate || '4.0M',
    ocr_only: app.ocr_only ?? false,

    // Subtitle
    show_subtitle: sub.show ?? true,
    font_name: sub.font_name || 'Arial',
    font_size: sub.font_size || '',
    font_color: sub.font_color || '&H00FFFFFF',
    outline_color: sub.outline_color || '&H00000000',
    char_rate: sub.char_rate ?? 0.07,
    fill_gap: sub.fill_gap ?? true,

    // Inpaint & Box
    inpaint_engine: inp.engine || 'box_color',
    inpaint_color: inp.color || 'transparent',
    inpaint_region: inpaintRegion,
    blur_radius: inp.blur_radius ?? 15,
    box_bg_color: box.bg_color || inp.bg_color || sub.bg_color || 'black',
    box_bg_opacity: box.bg_opacity ?? inp.bg_opacity ?? sub.bg_opacity ?? 0.75,
    box_border_color: box.border_color || inp.border_color || sub.border_color || '&H40FFFFFF',
    box_border_width: box.border_width ?? inp.border_width ?? sub.border_width ?? 2,
    box_border_radius: box.border_radius ?? inp.border_radius ?? sub.border_radius ?? 8,

    // Watermark
    watermark_enabled: wm.enabled ?? true,
    watermark_type: wm.image ? 'image' : 'text',
    watermark_text: wm.text !== undefined ? String(wm.text) : 'Sub-Video AI',
    watermark_image: wm.image || '',
    watermark_font_name: wm.font_name || 'Arial',
    watermark_font_color: wm.font_color || 'white',
    watermark_blur_bg: wm.blur_bg ?? true,
    watermark_opacity: wm.opacity ?? 0.85,
    watermark_region: wmRegion,
    watermark_position: (() => {
      const reg = wmRegion;
      if (Array.isArray(reg) && reg.length === 4) {
        const [top, left, bottom, right] = reg;
        if (left >= 0.5 && top < 0.5) return 'top-right';
        if (left < 0.5 && top >= 0.5) return 'bottom-left';
        if (left >= 0.5 && top >= 0.5) return 'bottom-right';
        return 'top-left';
      }
      return 'top-left';
    })(),

    // TTS & Audio
    tts_voice: tts.voice || 'vi',
    tts_speed: tts.speed_factor ?? 1.5,
    tts_vol: vols.tts_voice ?? 1.0,
    orig_voice_vol: vols.original_voice ?? 0.05,
    music_vol: vols.music ?? 0.5,
    ambient_vol: vols.ambient ?? 0.75,

    // Translator
    translator_type: trans.type || 'ollama',
    translator_model: trans.model || 'gemma4:31b-cloud',
    translator_batch_size: trans.batch_size ?? 20,
    translator_base_url: trans.base_url || 'http://localhost:11434',
  };
};

export const generateConfigYaml = (c) => {
  return `# AI Video Translator - Hierarchical Configuration
app:
  device: auto
  target_lang: vi
  ocr_only: ${c.ocr_only ? 'true' : 'false'}
  video_bitrate: "${c.video_bitrate || '4.0M'}"
  output_suffix: "_vi"

asr:
  engine: mlx-whisper
  model: auto

translator:
  type: "${c.translator_type || 'ollama'}"
  model: "${c.translator_model || 'gemma4:31b-cloud'}"
  base_url: "${c.translator_base_url || 'http://localhost:11434'}"
  batch_size: ${c.translator_batch_size || 20}

ocr:
  engine: apple_vision
  num_workers: 2
  mode: region
  diff_threshold: 8.0
  diff_step: 2
  detect_start_sec: 5.0
  detect_duration_sec: 10.0

inpaint:
  engine: ${c.inpaint_engine || 'box_color'}
  padding_y: 0.02
  color: "${(c.inpaint_engine === 'box_color' || c.inpaint_engine === 'boxColor') ? (c.box_bg_color || 'black') : 'transparent'}"
  blur_radius: ${c.blur_radius || 15}
  ${Array.isArray(c.inpaint_region) && c.inpaint_region.length === 4 ? `region: [${c.inpaint_region.join(', ')}]` : '# region: [0.12, 0.05, 0.22, 0.95]'}
  box:
    bg_color: "${c.box_bg_color || 'black'}"
    bg_opacity: ${c.box_bg_opacity ?? 0.75}
    border_color: "${c.box_border_color || '&H40FFFFFF'}"
    border_width: ${c.box_border_width ?? 2}
    border_radius: ${c.box_border_radius ?? 8}

subtitle:
  show: ${c.show_subtitle !== false ? 'true' : 'false'}
  font_name: "${c.font_name || 'Arial'}"
  font_color: "${c.font_color || '&H00FFFFFF'}"
  outline_color: "${c.outline_color || '&H00000000'}"
  ${c.font_size ? `font_size: ${c.font_size}` : '# font_size: 28'}
  char_rate: ${c.char_rate || 0.07}
  safety_margin: 0.15
  fill_gap: ${c.fill_gap ? 'true' : 'false'}

watermark:
  enabled: ${c.watermark_enabled !== false ? 'true' : 'false'}
  region: ${Array.isArray(c.watermark_region) && c.watermark_region.length === 4 ? `[${c.watermark_region.join(', ')}]` : c.watermark_position === 'top-right' ? '[0.02, 0.70, 0.08, 0.98]' : c.watermark_position === 'bottom-left' ? '[0.90, 0.02, 0.96, 0.30]' : c.watermark_position === 'bottom-right' ? '[0.90, 0.70, 0.96, 0.98]' : '[0.02, 0.02, 0.08, 0.30]'}
  image: "${c.watermark_type === 'image' ? (c.watermark_image || '') : ''}"
  text: "${c.watermark_text || 'Sub-Video AI'}"
  font_name: "${c.watermark_font_name || 'Arial'}"
  font_color: "${c.watermark_font_color || 'white'}"
  blur_bg: ${c.watermark_blur_bg !== false ? 'true' : 'false'}
  opacity: ${c.watermark_opacity ?? 0.85}

tts:
  engine: preset
  voice: "${c.tts_voice || 'vi'}"
  speed_factor: ${c.tts_speed || 1.5}
  enable_gender: false
  voice_male: "vi-VN-NamMinhNeural"
  voice_female: "vi"

audio:
  volumes:
    tts_voice: ${c.tts_vol ?? 1.0}
    original_voice: ${c.orig_voice_vol ?? 0.05}
    music: ${c.music_vol ?? 0.5}
    ambient: ${c.ambient_vol ?? 0.75}
  filters:
    noise_reduction_strength: 0.9
    ambient_split_threshold: 0.3

storage:
  enabled: true
  provider: "gcs"
  key_file: "assets/gcs-key.json"
  bucket_name: "service-qa-beta"
  base_prefix: "video-tiktok-volumn"
`;
};

export default function SubtitleInspector({
  subtitles = [],
  currentTime = 0,
  selectedSubIndex = null,
  onSelectSubIndex,
  onSubtitleChange,
  onSeekToSubtitle,
  onTranslateAll,
  onAutoSync,
  onSaveSubtitles,
  isSubModified = false,
  configData = {},
  onConfigChange,
  isProcessing = false
}) {
  const [activeTab, setActiveTab] = useState('subtitles'); // 'subtitles' | 'styles' | 'voice' | 'engine'
  const [editingIndex, setEditingIndex] = useState(null);
  const [sourceLang, setSourceLang] = useState('auto');
  const [targetLang, setTargetLang] = useState('vi');
  const rowRefs = useRef({});

  // Auto-scroll to selected row when selectedSubIndex changes from timeline
  useEffect(() => {
    if (selectedSubIndex !== null && rowRefs.current[selectedSubIndex]) {
      rowRefs.current[selectedSubIndex].scrollIntoView({
        behavior: 'smooth',
        block: 'nearest'
      });
    }
  }, [selectedSubIndex]);

  // Config Form State
  const [cfg, setCfg] = useState({
    video_bitrate: '4.0M',
    font_name: 'Arial',
    font_size: 28,
    font_color: '&H00FFFFFF',
    outline_color: '&H00000000',
    show_subtitle: true,
    inpaint_engine: 'box_color',
    inpaint_color: 'transparent',
    box_bg_color: 'black',
    box_bg_opacity: 0.75,
    box_border_color: '&H40FFFFFF',
    box_border_width: 2,
    box_border_radius: 8,
    blur_radius: 15,
    char_rate: 0.07,
    fill_gap: true,
    tts_voice: 'vi',
    tts_speed: 1.5,
    tts_vol: 1.0,
    orig_voice_vol: 0.05,
    music_vol: 0.5,
    ambient_vol: 0.75,
    ocr_only: false,
    translator_type: 'ollama',
    translator_model: 'gemma4:31b-cloud',
    translator_batch_size: 20,
    translator_base_url: 'http://localhost:11434',
    watermark_enabled: true,
    watermark_type: 'text',
    watermark_text: 'Sub-Video AI',
    watermark_image: '',
    watermark_position: 'top-left',
    watermark_font_name: 'Arial',
    watermark_font_color: 'white',
    watermark_blur_bg: true,
    watermark_opacity: 0.85
  });

  // Sync with incoming configData if raw YAML or structured config is passed
  useEffect(() => {
    if (configData && configData.raw) {
      const parsed = parseYamlToCfg(configData.raw);
      setCfg(prev => ({ ...prev, ...parsed }));
    } else if (configData && Object.keys(configData).length > 0) {
      setCfg(prev => ({
        ...prev,
        video_bitrate: configData.app?.video_bitrate || prev.video_bitrate,
        font_name: configData.subtitle?.font_name || prev.font_name,
        font_size: configData.subtitle?.font_size || prev.font_size,
        font_color: configData.subtitle?.font_color || prev.font_color,
        outline_color: configData.subtitle?.outline_color || prev.outline_color,
        show_subtitle: configData.subtitle?.show ?? prev.show_subtitle,
        inpaint_engine: configData.inpaint?.engine || prev.inpaint_engine,
        inpaint_color: configData.inpaint?.color || prev.inpaint_color,
        inpaint_region: configData.inpaint?.region || configData.inpaint_region || prev.inpaint_region,
        box_bg_color: configData.inpaint?.box?.bg_color || configData.subtitle?.box?.bg_color || prev.box_bg_color,
        box_bg_opacity: configData.inpaint?.box?.bg_opacity ?? configData.subtitle?.box?.bg_opacity ?? prev.box_bg_opacity,
        box_border_color: configData.inpaint?.box?.border_color || configData.subtitle?.box?.border_color || prev.box_border_color,
        box_border_width: configData.inpaint?.box?.border_width ?? configData.subtitle?.box?.border_width ?? prev.box_border_width,
        box_border_radius: configData.inpaint?.box?.border_radius ?? prev.box_border_radius,
        blur_radius: configData.inpaint?.blur_radius || prev.blur_radius,
        char_rate: configData.subtitle?.char_rate || prev.char_rate,
        fill_gap: configData.subtitle?.fill_gap ?? prev.fill_gap,
        tts_voice: configData.tts?.voice || prev.tts_voice,
        tts_speed: configData.tts?.speed_factor || prev.tts_speed,
        tts_vol: configData.audio?.volumes?.tts_voice ?? prev.tts_vol,
        orig_voice_vol: configData.audio?.volumes?.original_voice ?? prev.orig_voice_vol,
        music_vol: configData.audio?.volumes?.music ?? prev.music_vol,
        ambient_vol: configData.audio?.volumes?.ambient ?? prev.ambient_vol,
        ocr_only: configData.app?.ocr_only ?? prev.ocr_only,
        translator_type: configData.translator?.type || prev.translator_type,
        translator_model: configData.translator?.model || prev.translator_model,
        translator_batch_size: configData.translator?.batch_size || prev.translator_batch_size,
        translator_base_url: configData.translator?.base_url || prev.translator_base_url,
        watermark_enabled: configData.watermark?.enabled ?? prev.watermark_enabled,
        watermark_type: configData.watermark?.image ? 'image' : (prev.watermark_type || 'text'),
        watermark_text: configData.watermark?.text || prev.watermark_text,
        watermark_image: configData.watermark?.image || prev.watermark_image,
        watermark_region: configData.watermark?.region || prev.watermark_region,
        watermark_position: prev.watermark_position || 'top-left',
        watermark_font_name: configData.watermark?.font_name || prev.watermark_font_name,
        watermark_font_color: configData.watermark?.font_color || prev.watermark_font_color,
        watermark_blur_bg: configData.watermark?.blur_bg ?? prev.watermark_blur_bg,
        watermark_opacity: configData.watermark?.opacity ?? prev.watermark_opacity,
      }));
    }
  }, [configData]);

  const handleCfgChange = (key, val) => {
    setCfg(prev => {
      const updated = { ...prev, [key]: val };
      if (onConfigChange) {
        onConfigChange(updated);
      }
      return updated;
    });
  };

  const handleUpdateItem = (index, field, value) => {
    const updated = [...subtitles];
    const current = { ...updated[index] };
    current[field] = value;
    if (field === 'translated_text') {
      current.text_vi = value;
    } else if (field === 'text_vi') {
      current.translated_text = value;
    }
    updated[index] = current;
    if (onSubtitleChange) onSubtitleChange(updated);
  };

  const handleUpdateItemTime = (index, field, rawValue) => {
    if (index === null || !subtitles[index]) return;
    const sec = parseTimecodeToSeconds(rawValue);
    const updated = [...subtitles];
    const target = { ...updated[index] };
    
    if (field === 'start') {
      target.start = Math.round(sec * 1000) / 1000;
      if (target.start >= (Number(target.end) || 0)) {
        target.end = Math.round((target.start + 1.5) * 1000) / 1000;
      }
    } else if (field === 'end') {
      target.end = Math.round(sec * 1000) / 1000;
      if (target.end <= (Number(target.start) || 0)) {
        target.start = Math.max(0, Math.round((target.end - 1.5) * 1000) / 1000);
      }
    }

    updated[index] = target;
    // Auto-sort by start time so it jumps to the exact chronological index position
    updated.sort((a, b) => (Number(a.start) || 0) - (Number(b.start) || 0));
    const newIdx = updated.indexOf(target);
    if (newIdx !== -1) {
      setEditingIndex(newIdx);
      if (onSelectSubIndex) onSelectSubIndex(newIdx);
    }
    if (onSubtitleChange) onSubtitleChange(updated);
  };

  const handleSetTimeToCurrent = (index, field, e) => {
    e.stopPropagation();
    const curTime = Math.max(0, Math.round(currentTime * 1000) / 1000);
    handleUpdateItemTime(index, field, curTime);
  };

  const handleAddItem = () => {
    const curTime = Math.max(0, Math.round(currentTime * 1000) / 1000);
    const nextSub = subtitles.find(s => Number(s.start) > curTime);
    let dur = 2.0;
    if (nextSub) {
      const gap = Number(nextSub.start) - curTime;
      if (gap > 0.3) {
        dur = Math.min(2.0, gap);
      } else {
        dur = 0.5;
      }
    }
    const newEnd = Math.round((curTime + dur) * 1000) / 1000;

    const newItem = {
      start: curTime,
      end: newEnd,
      text: '',
      translated_text: 'Câu thoại mới',
      text_vi: 'Câu thoại mới'
    };

    const updated = [...subtitles, newItem];
    // Auto-sort by start time so it is inserted at the exact chronological index
    updated.sort((a, b) => (Number(a.start) || 0) - (Number(b.start) || 0));
    const newIdx = updated.indexOf(newItem);

    if (onSubtitleChange) onSubtitleChange(updated);
    if (onSelectSubIndex) onSelectSubIndex(newIdx);
    setEditingIndex(newIdx);
  };

  const handleDeleteItem = (index, e) => {
    e.stopPropagation();
    const updated = subtitles.filter((_, idx) => idx !== index);
    if (editingIndex === index) setEditingIndex(null);
    if (onSubtitleChange) onSubtitleChange(updated);
  };

  return (
    <div style={styles.container}>
      {/* 4 Tab Navigation Header */}
      <div style={styles.tabHeader}>
        {[
          { id: 'subtitles', label: 'Subtitles', icon: <FileText size={13} /> },
          { id: 'styles', label: 'Styles & Inpaint', icon: <Palette size={13} /> },
          { id: 'voice', label: 'Voice & Audio', icon: <Volume2 size={13} /> },
          { id: 'engine', label: 'Video & Engine', icon: <SlidersHorizontal size={13} /> }
        ].map(t => (
          <button
            key={t.id}
            style={{
              ...styles.tabBtn,
              ...(activeTab === t.id ? styles.tabBtnActive : {})
            }}
            onClick={() => setActiveTab(t.id)}
          >
            {t.icon}
            <span>{t.label}</span>
          </button>
        ))}
      </div>

      {/* 📝 Tab 1: Subtitles List (Primary Interactive Table) */}
      {activeTab === 'subtitles' && (
        <div style={styles.tabBody}>
          {/* Language Selector & Translate All CTA */}
          <div style={styles.langBar}>
            <div style={styles.langPair}>
              <span style={styles.langLabel}>From:</span>
              <select 
                value={sourceLang} 
                onChange={e => setSourceLang(e.target.value)}
                style={styles.langSelect}
              >
                <option value="auto">🌐 Auto Detect</option>
                <option value="zh">🇨🇳 Tiếng Trung</option>
                <option value="en">🇬🇧 Tiếng Anh</option>
                <option value="ja">🇯🇵 Tiếng Nhật</option>
                <option value="ko">🇰🇷 Tiếng Hàn</option>
              </select>

              <span style={styles.langLabel}>To:</span>
              <select 
                value={targetLang} 
                onChange={e => setTargetLang(e.target.value)}
                style={styles.langSelect}
              >
                <option value="vi">🇻🇳 Tiếng Việt</option>
                <option value="en">🇬🇧 English</option>
              </select>
            </div>

            <button 
              style={styles.translateAllBtn}
              onClick={() => onTranslateAll && onTranslateAll(sourceLang, targetLang)}
              disabled={isProcessing}
              title="Dịch tự động toàn bộ phụ đề sang tiếng Việt bằng AI"
            >
              <Languages size={13} />
              <span>Dịch Toàn Bộ (AI)</span>
            </button>
          </div>

          {/* Subtitle Items List */}
          <div style={styles.listContainer}>
            {(!subtitles || subtitles.length === 0) ? (
              <div style={styles.emptyState}>
                <FileText size={32} style={{ opacity: 0.3, marginBottom: 8 }} />
                <span>Chưa có dữ liệu phụ đề.</span>
                <span style={{ fontSize: 11, color: 'var(--text-dim)' }}>
                  Hãy chạy nhận diện giọng nói hoặc OCR để trích xuất phụ đề.
                </span>
              </div>
            ) : (
              subtitles.map((sub, idx) => {
                const isActive = currentTime >= (sub.start || 0) && currentTime <= (sub.end || 0);
                const isSelected = selectedSubIndex === idx;
                const isEditing = editingIndex === idx;

                return (
                  <div
                    key={idx}
                    ref={el => { rowRefs.current[idx] = el; }}
                    style={{
                      ...styles.subRow,
                      ...(isActive ? styles.subRowActive : {}),
                      ...(isSelected ? styles.subRowSelected : {})
                    }}
                    onClick={() => {
                      if (onSelectSubIndex) onSelectSubIndex(idx);
                      if (onSeekToSubtitle) onSeekToSubtitle(sub.start);
                    }}
                  >
                    {/* Index & Timecode Column */}
                    {isEditing ? (
                      <div style={styles.subIndexColEditing} onClick={e => e.stopPropagation()}>
                        <span style={styles.subNumber}>#{idx + 1}</span>
                        
                        {/* Start Time Editor with ⏱️ Current Time button */}
                        <div style={styles.timeInputRow} title="Start Time: Gõ trực tiếp hoặc bấm ⏱️ để lấy giờ video hiện tại">
                          <input
                            type="text"
                            defaultValue={formatSubtitleTime(sub.start)}
                            key={`start_${idx}_${sub.start}`}
                            onBlur={(e) => handleUpdateItemTime(idx, 'start', e.target.value)}
                            onKeyDown={(e) => {
                              if (e.key === 'Enter') {
                                handleUpdateItemTime(idx, 'start', e.target.value);
                              }
                            }}
                            placeholder="Start"
                            style={styles.timeInputEdit}
                          />
                          <button
                            style={styles.setTimeBtn}
                            onClick={(e) => handleSetTimeToCurrent(idx, 'start', e)}
                            title="Gán giờ Playhead hiện tại làm Start Time"
                          >
                            <Clock size={10} />
                          </button>
                        </div>

                        <span style={{ fontSize: 8, color: 'var(--text-dim)', margin: '1px 0' }}>➔</span>

                        {/* End Time Editor with ⏱️ Current Time button */}
                        <div style={styles.timeInputRow} title="End Time: Gõ trực tiếp hoặc bấm ⏱️ để lấy giờ video hiện tại">
                          <input
                            type="text"
                            defaultValue={formatSubtitleTime(sub.end)}
                            key={`end_${idx}_${sub.end}`}
                            onBlur={(e) => handleUpdateItemTime(idx, 'end', e.target.value)}
                            onKeyDown={(e) => {
                              if (e.key === 'Enter') {
                                handleUpdateItemTime(idx, 'end', e.target.value);
                              }
                            }}
                            placeholder="End"
                            style={styles.timeInputEdit}
                          />
                          <button
                            style={styles.setTimeBtn}
                            onClick={(e) => handleSetTimeToCurrent(idx, 'end', e)}
                            title="Gán giờ Playhead hiện tại làm End Time"
                          >
                            <Clock size={10} />
                          </button>
                        </div>
                      </div>
                    ) : (
                      <div 
                        style={styles.subIndexCol} 
                        title="Click để chỉnh sửa mốc thời gian"
                        onClick={(e) => {
                          e.stopPropagation();
                          setEditingIndex(idx);
                        }}
                      >
                        <span style={styles.subNumber}>#{idx + 1}</span>
                        <div style={styles.timeRangeBox}>
                          <span style={styles.timecodeStr}>{formatSubtitleTime(sub.start)}</span>
                          <span style={{ fontSize: 8, color: 'var(--text-dim)' }}>➔</span>
                          <span style={styles.timecodeStr}>{formatSubtitleTime(sub.end)}</span>
                        </div>
                      </div>
                    )}

                    {/* Text Content Column */}
                    <div style={styles.textContentCol}>
                      {isEditing ? (
                        <div style={styles.editFields} onClick={e => e.stopPropagation()}>
                          <input
                            type="text"
                            value={sub.text || ''}
                            onChange={(e) => handleUpdateItem(idx, 'text', e.target.value)}
                            placeholder="Văn bản gốc (OCR / ASR)..."
                            style={styles.inlineInput}
                          />
                          <input
                            type="text"
                            value={sub.translated_text || ''}
                            onChange={(e) => handleUpdateItem(idx, 'translated_text', e.target.value)}
                            placeholder="Bản dịch tiếng Việt..."
                            style={{ ...styles.inlineInput, borderColor: 'var(--primary-light)', fontWeight: 600 }}
                            autoFocus
                          />
                        </div>
                      ) : (
                        <div style={styles.textDisplay}>
                          <div style={styles.origText} title={sub.text}>
                            {sub.text || <span style={{ opacity: 0.4 }}>[Không có text gốc]</span>}
                          </div>
                          <div style={styles.transText} title={sub.translated_text}>
                            {sub.translated_text || (
                              <span style={{ color: 'var(--text-dim)', fontStyle: 'italic', fontWeight: 400 }}>
                                Chưa có bản dịch
                              </span>
                            )}
                          </div>
                        </div>
                      )}
                    </div>

                    {/* Quick Row Actions */}
                    <div style={styles.rowActions} onClick={e => e.stopPropagation()}>
                      <button
                        style={styles.iconActionBtn}
                        onClick={() => setEditingIndex(isEditing ? null : idx)}
                        title={isEditing ? 'Hoàn tất sửa' : 'Chỉnh sửa phụ đề'}
                      >
                        {isEditing ? <Check size={12} color="var(--accent-green)" /> : <Edit3 size={12} />}
                      </button>
                      <button
                        style={{ ...styles.iconActionBtn, color: 'var(--accent-red)' }}
                        onClick={(e) => handleDeleteItem(idx, e)}
                        title="Xóa phụ đề này"
                      >
                        <Trash2 size={12} />
                      </button>
                    </div>
                  </div>
                );
              })
            )}
          </div>

          {/* Bottom Action Bar */}
          <div style={styles.bottomBar}>
            <button 
              style={styles.bottomBtn}
              onClick={handleAddItem}
              title="Thêm một câu phụ đề mới tại thời điểm hiện tại"
            >
              <Plus size={13} />
              <span>Thêm Phụ Đề</span>
            </button>

            <button 
              style={{ ...styles.bottomBtn, ...styles.autoSyncBtn }}
              onClick={() => onAutoSync && onAutoSync()}
              disabled={isProcessing}
              title="Khớp lại thời gian phụ đề và sinh lại giọng đọc TTS"
            >
              <Sparkles size={13} />
              <span>Đồng Bộ TTS</span>
            </button>
          </div>
        </div>
      )}

      {/* 🎨 Tab 2: Styles & Inpaint */}
      {activeTab === 'styles' && (
        <div style={styles.configScrollBody}>
          {/* Master Toggle: Hiển Thị Sub Mới */}
          <div style={styles.configSection}>
            <h4 style={styles.configTitle}>👁️ Hiển Thị Phụ Đề Mới</h4>
            <div style={styles.formRow}>
              <label style={styles.checkboxLabel}>
                <input 
                  type="checkbox"
                  checked={cfg.show_subtitle !== false}
                  onChange={e => handleCfgChange('show_subtitle', e.target.checked)}
                  style={styles.checkboxInput}
                />
                <span>Hiển thị Sub mới & Hộp nền che lên Video</span>
              </label>
            </div>
            {cfg.show_subtitle === false && (
              <span style={{ fontSize: 11, color: 'var(--accent-yellow)', marginTop: 4 }}>
                ⚠️ Khi tắt tùy chọn này, video sẽ được xuất sạch không có chữ sub và không có hộp che.
              </span>
            )}
          </div>

          {/* Subtitle & Inpaint Settings (Only shown when show_subtitle is true) */}
          {cfg.show_subtitle !== false && (
            <>
              {/* Section 1: Subtitle Typography */}
              <div style={styles.configSection}>
                <h4 style={styles.configTitle}>🎨 Subtitle Typography</h4>
                
                <div style={styles.formRow}>
                  <label style={styles.formLabel}>Font Chữ:</label>
                  <select 
                    value={cfg.font_name} 
                    onChange={e => handleCfgChange('font_name', e.target.value)}
                    style={styles.formSelect}
                  >
                    <option value="Arial">Arial (Chuẩn sắc nét)</option>
                    <option value="Be Vietnam Pro">Be Vietnam Pro (Tiếng Việt đẹp)</option>
                    <option value="Impact">Impact (TikTok Bold)</option>
                    <option value="Roboto">Roboto</option>
                    <option value="Montserrat">Montserrat</option>
                    <option value="SF Pro Display">SF Pro Display (Apple style)</option>
                  </select>
                </div>

                <div style={styles.formRow}>
                  <label style={styles.formLabel}>Cỡ Chữ (px):</label>
                  <input 
                    type="number"
                    value={cfg.font_size || ''}
                    placeholder="Auto fit (để trống)"
                    onChange={e => handleCfgChange('font_size', e.target.value ? parseInt(e.target.value) : '')}
                    style={styles.formInput}
                  />
                </div>

                <div style={styles.formRow}>
                  <label style={styles.formLabel}>Màu Chữ Sub:</label>
                  <select 
                    value={cfg.font_color} 
                    onChange={e => handleCfgChange('font_color', e.target.value)}
                    style={styles.formSelect}
                  >
                    <option value="&H00FFFFFF">Trắng Tinh (&H00FFFFFF)</option>
                    <option value="&H0000FFFF">Vàng Rực (&H0000FFFF) - Nổi bật</option>
                    <option value="&H00FFFF00">Xanh Cyan (&H00FFFF00)</option>
                    <option value="&H000000FF">Đỏ Đậm (&H000000FF)</option>
                    <option value="&H00000000">Đen (&H00000000)</option>
                  </select>
                </div>

                <div style={styles.formRow}>
                  <label style={styles.formLabel}>Viền Chữ (Outline):</label>
                  <select 
                    value={cfg.outline_color} 
                    onChange={e => handleCfgChange('outline_color', e.target.value)}
                    style={styles.formSelect}
                  >
                    <option value="&H00000000">Đen Đậm Sắc Nét</option>
                    <option value="&H00FFFFFF">Trắng</option>
                    <option value="none">Không viền</option>
                  </select>
                </div>
              </div>

              {/* Section 2: Xóa Sub Cũ & Hộp Nền (Inpaint Engine) */}
              <div style={styles.configSection}>
                <h4 style={styles.configTitle}>🪄 Xóa Sub Cũ & Hộp Nền Che (Inpaint)</h4>
                
                <div style={styles.formRow}>
                  <label style={styles.formLabel}>Engine Xóa Sub:</label>
                  <select 
                    value={cfg.inpaint_engine || 'box_color'} 
                    onChange={e => {
                      const newEngine = e.target.value;
                      handleCfgChange('inpaint_engine', newEngine);
                      if (newEngine !== 'box_color' && newEngine !== 'boxColor') {
                        handleCfgChange('inpaint_color', 'transparent');
                      }
                    }}
                    style={styles.formSelect}
                  >
                    <option value="box_color">📦 Hộp Màu Che Sub (Box Color ~0.5s)</option>
                    <option value="ffmpeg_blur">🔮 FFmpeg BoxBlur (Mờ Kính ~1s)</option>
                    <option value="apple_vision_inpaint">🍏 Apple Vision Inpaint (~3s)</option>
                    <option value="opencv">⚡ OpenCV Inpaint (~15s)</option>
                  </select>
                </div>

                {/* 🍏 Apple Vision Inpaint Method Selector */}
                {cfg.inpaint_engine === 'apple_vision_inpaint' && (
                  <div style={styles.formRow}>
                    <label style={styles.formLabel}>Thuật Toán Inpaint:</label>
                    <select
                      value={cfg.inpaint_method || 'vertical_gradient'}
                      onChange={e => handleCfgChange('inpaint_method', e.target.value)}
                      style={styles.formSelect}
                    >
                      <option value="vertical_gradient">📐 Vertical Gradient (Phẳng Lỳ Nền Đất/Áo - Khử Gươm)</option>
                      <option value="navier_stokes">🌊 Navier-Stokes (Dòng Chảy Mượt Mà)</option>
                      <option value="telea">⚡ Telea (Fast Marching)</option>
                    </select>
                  </div>
                )}

                {/* 📍 Vị Trí Vùng Sub Cần Che (inpaint_region) - Checkbox & 1-line Title */}
                <div style={{ marginTop: 8, marginBottom: 10 }}>
                  <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 6 }}>
                    <span style={{ fontSize: 11, fontWeight: 600, color: 'var(--text-main)', whiteSpace: 'nowrap' }}>
                      Chỉnh Vùng Sub Thủ Công:
                    </span>
                    <label style={{ display: 'flex', alignItems: 'center', gap: 6, cursor: 'pointer', fontSize: 11, fontWeight: 600, color: (Array.isArray(cfg.inpaint_region) && cfg.inpaint_region.length === 4) ? 'var(--primary-light)' : 'var(--text-dim)' }}>
                      <input 
                        type="checkbox"
                        checked={Array.isArray(cfg.inpaint_region) && cfg.inpaint_region.length === 4}
                        onChange={e => {
                          if (e.target.checked) {
                            handleCfgChange('inpaint_region', [0.90, 0.10, 0.99, 0.90]);
                          } else {
                            handleCfgChange('inpaint_region', null);
                          }
                        }}
                        style={{ accentColor: 'var(--primary)', cursor: 'pointer' }}
                      />
                      <span>{Array.isArray(cfg.inpaint_region) && cfg.inpaint_region.length === 4 ? 'Bật (Manual)' : 'Tự Động (Auto)'}</span>
                    </label>
                  </div>

                  {/* When Manual Checkbox is ON: Show 4 Coordinate Inputs & Presets */}
                  {Array.isArray(cfg.inpaint_region) && cfg.inpaint_region.length === 4 ? (
                    <div style={{
                      background: 'rgba(0, 0, 0, 0.25)',
                      borderRadius: 8,
                      border: '1px solid var(--border-light)',
                      padding: '8px 10px',
                      display: 'flex',
                      flexDirection: 'column',
                      gap: 8
                    }}>
                      {/* 4 Coordinate input boxes [Top, Left, Bottom, Right] */}
                      <div style={{
                        display: 'grid',
                        gridTemplateColumns: 'repeat(4, 1fr)',
                        gap: 6
                      }}>
                        {['Top', 'Left', 'Bottom', 'Right'].map((lbl, idx) => {
                          const currentVal = cfg.inpaint_region[idx] ?? 0;
                          return (
                            <div key={lbl} style={{ display: 'flex', flexDirection: 'column', gap: 2 }}>
                              <span style={{ fontSize: 9, color: 'var(--text-dim)', textAlign: 'center', textTransform: 'uppercase' }}>{lbl}</span>
                              <input
                                type="number"
                                step="0.01"
                                min="0"
                                max="1"
                                value={currentVal}
                                onChange={e => {
                                  const val = parseFloat(e.target.value);
                                  const nextReg = [...cfg.inpaint_region];
                                  nextReg[idx] = isNaN(val) ? 0 : val;
                                  handleCfgChange('inpaint_region', nextReg);
                                }}
                                style={{
                                  padding: '4px',
                                  fontSize: 10,
                                  textAlign: 'center',
                                  borderRadius: 4,
                                  border: '1px solid var(--border)',
                                  background: 'var(--bg-app)',
                                  color: 'var(--text-main)',
                                  fontFamily: 'monospace'
                                }}
                              />
                            </div>
                          );
                        })}
                      </div>

                      {/* Quick Presets */}
                      <div style={{ display: 'flex', alignItems: 'center', gap: 4, flexWrap: 'wrap' }}>
                        <span style={{ fontSize: 10, color: 'var(--text-dim)', marginRight: 2 }}>Gợi ý:</span>
                        {[
                          { label: 'Sát Đáy', reg: [0.90, 0.10, 0.99, 0.90] },
                          { label: 'Dải Dưới', reg: [0.75, 0.05, 0.95, 0.95] },
                          { label: 'Giữa Video', reg: [0.45, 0.05, 0.55, 0.95] }
                        ].map(preset => (
                          <button
                            key={preset.label}
                            type="button"
                            onClick={() => handleCfgChange('inpaint_region', preset.reg)}
                            style={{
                              padding: '2px 6px',
                              fontSize: 9,
                              borderRadius: 4,
                              border: '1px solid var(--border)',
                              background: 'rgba(255, 255, 255, 0.05)',
                              color: 'var(--text-secondary)',
                              cursor: 'pointer'
                            }}
                          >
                            {preset.label}
                          </button>
                        ))}
                      </div>
                    </div>
                  ) : (
                    <div style={{
                      fontSize: 10,
                      color: 'var(--text-dim)',
                      background: 'rgba(59, 130, 246, 0.06)',
                      padding: '5px 8px',
                      borderRadius: 6,
                      border: '1px dashed rgba(59, 130, 246, 0.2)'
                    }}>
                      ℹ️ Tự động quét 10s đầu của video (Fast OCR) để phát hiện vị trí sub cũ.
                    </div>
                  )}
                </div>

                {/* Sub-settings when Box Color engine is selected */}
                {(cfg.inpaint_engine === 'box_color' || cfg.inpaint_engine === 'boxColor' || !cfg.inpaint_engine) && (
                  <div style={{
                    background: 'rgba(255, 255, 255, 0.03)',
                    border: '1px solid rgba(255, 255, 255, 0.08)',
                    borderRadius: 8,
                    padding: '10px 12px',
                    marginTop: 6,
                    marginBottom: 10,
                    display: 'flex',
                    flexDirection: 'column',
                    gap: 8,
                    boxSizing: 'border-box',
                    width: '100%'
                  }}>
                    <div style={{ fontSize: 11, fontWeight: 700, color: 'var(--accent-yellow)', display: 'flex', alignItems: 'center', gap: 6 }}>
                      <span>📦 Tùy Chỉnh Hộp Nền Box Color:</span>
                    </div>

                    <div style={styles.formRow}>
                      <label style={styles.formLabel}>Màu Nền Hộp:</label>
                      <select 
                        value={cfg.box_bg_color || 'black'} 
                        onChange={e => handleCfgChange('box_bg_color', e.target.value)}
                        style={styles.formSelect}
                      >
                        <option value="black">Đen Tuyệt Đối (#000000)</option>
                        <option value="#1e1e1e">Xám Đen Studio (#1e1e1e)</option>
                        <option value="#0f172a">Dark Slate (#0f172a)</option>
                        <option value="white">Trắng (#ffffff)</option>
                      </select>
                    </div>

                    <div style={styles.formRow}>
                      <label style={styles.formLabel}>
                        Độ Đậm Nền ({Math.round((cfg.box_bg_opacity ?? 0.75) * 100)}%):
                      </label>
                      <input 
                        type="range"
                        min="0.1"
                        max="1.0"
                        step="0.05"
                        value={cfg.box_bg_opacity ?? 0.75}
                        onChange={e => handleCfgChange('box_bg_opacity', parseFloat(e.target.value))}
                        style={styles.formRange}
                      />
                    </div>

                    <div style={styles.formRow}>
                      <label style={styles.formLabel}>Màu Viền Hộp:</label>
                      <select 
                        value={cfg.box_border_color || '&H40FFFFFF'} 
                        onChange={e => handleCfgChange('box_border_color', e.target.value)}
                        style={styles.formSelect}
                      >
                        <option value="&H40FFFFFF">Trắng Mờ Tinh Tế (&H40FFFFFF)</option>
                        <option value="&H00FFFFFF">Trắng Sáng Rõ (&H00FFFFFF)</option>
                        <option value="&H0000FFFF">Vàng Nổi Bật (&H0000FFFF)</option>
                        <option value="&H00FFFF00">Xanh Cyan (&H00FFFF00)</option>
                        <option value="&HFF000000">Không Viền (Trong suốt)</option>
                      </select>
                    </div>

                    <div style={styles.formRow}>
                      <label style={styles.formLabel}>Độ Dày Viền (Thin):</label>
                      <select 
                        value={cfg.box_border_width ?? 2} 
                        onChange={e => handleCfgChange('box_border_width', parseInt(e.target.value))}
                        style={styles.formSelect}
                      >
                        <option value={1}>1px (Siêu Mỏng Tinh Xảo)</option>
                        <option value={2}>2px (Chuẩn Nét Studio)</option>
                        <option value={3}>3px (Dày Đậm Nổi Bật)</option>
                      </select>
                    </div>

                    <div style={styles.formRow}>
                      <label style={styles.formLabel}>Bo Góc Hộp (Radius):</label>
                      <select 
                        value={cfg.box_border_radius ?? 8} 
                        onChange={e => handleCfgChange('box_border_radius', parseInt(e.target.value))}
                        style={styles.formSelect}
                      >
                        <option value={8}>8px (Bo Tròn Chuẩn Đẹp)</option>
                        <option value={12}>12px (Bo Tròn Nhiều)</option>
                        <option value={4}>4px (Bo Nhẹ Tinh Tế)</option>
                        <option value={0}>0px (Vuông Vức Cổ Điển)</option>
                      </select>
                    </div>
                  </div>
                )}

                {/* Sub-settings when FFmpeg BoxBlur is selected */}
                {cfg.inpaint_engine === 'ffmpeg_blur' && (
                  <div style={styles.formRow}>
                    <label style={styles.formLabel}>Độ Mờ (Blur Radius):</label>
                    <input 
                      type="number"
                      value={cfg.blur_radius || 15}
                      onChange={e => handleCfgChange('blur_radius', parseInt(e.target.value) || 15)}
                      style={styles.formInput}
                    />
                  </div>
                )}
              </div>

              {/* Section 3: Watermark & Thương Hiệu (Branding) */}
              <div style={styles.configSection}>
                <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 8 }}>
                  <h4 style={{ ...styles.configTitle, margin: 0 }}>🏷️ Watermark & Logo (Branding)</h4>
                  <label style={{ display: 'flex', alignItems: 'center', gap: 6, cursor: 'pointer', fontSize: 11, fontWeight: 600, color: cfg.watermark_enabled !== false ? 'var(--primary-light)' : 'var(--text-dim)' }}>
                    <input 
                      type="checkbox"
                      checked={cfg.watermark_enabled !== false}
                      onChange={e => handleCfgChange('watermark_enabled', e.target.checked)}
                      style={{ accentColor: 'var(--primary)', cursor: 'pointer' }}
                    />
                    <span>{cfg.watermark_enabled !== false ? 'Đang Bật' : 'Đã Tắt'}</span>
                  </label>
                </div>

                {cfg.watermark_enabled !== false && (
                  <>
                    <div style={styles.formRow}>
                      <label style={styles.formLabel}>Loại Watermark:</label>
                      <select 
                        value={cfg.watermark_type || 'text'} 
                        onChange={e => handleCfgChange('watermark_type', e.target.value)}
                        style={styles.formSelect}
                      >
                        <option value="text">Chữ (Text Watermark)</option>
                        <option value="image">Ảnh Logo PNG (Image)</option>
                      </select>
                    </div>

                    {cfg.watermark_type === 'image' ? (
                      <div style={styles.formRow}>
                        <label style={styles.formLabel}>Đường Dẫn Logo PNG:</label>
                        <input 
                          type="text"
                          placeholder="assets/images/logo.png"
                          value={cfg.watermark_image || ''}
                          onChange={e => handleCfgChange('watermark_image', e.target.value)}
                          style={styles.formInput}
                        />
                      </div>
                    ) : (
                      <>
                        <div style={styles.formRow}>
                          <label style={styles.formLabel}>Nội Dung Chữ:</label>
                          <input 
                            type="text"
                            placeholder="Sub-Video AI"
                            value={cfg.watermark_text || ''}
                            onChange={e => handleCfgChange('watermark_text', e.target.value)}
                            style={styles.formInput}
                          />
                        </div>

                        <div style={styles.formRow}>
                          <label style={styles.formLabel}>Màu Chữ Watermark:</label>
                          <select 
                            value={cfg.watermark_font_color || 'white'} 
                            onChange={e => handleCfgChange('watermark_font_color', e.target.value)}
                            style={styles.formSelect}
                          >
                            <option value="white">Trắng (White)</option>
                            <option value="yellow">Vàng Rực (Yellow)</option>
                            <option value="cyan">Xanh Cyan</option>
                            <option value="#FFD700">Vàng Kim (Gold)</option>
                            <option value="black">Đen (Black)</option>
                          </select>
                        </div>

                        <div style={styles.formRow}>
                          <label style={styles.formLabel}>Font Chữ Watermark:</label>
                          <select 
                            value={cfg.watermark_font_name || 'Arial'} 
                            onChange={e => handleCfgChange('watermark_font_name', e.target.value)}
                            style={styles.formSelect}
                          >
                            <option value="Arial">Arial (Chuẩn)</option>
                            <option value="Helvetica">Helvetica</option>
                            <option value="Be Vietnam Pro">Be Vietnam Pro (Tiếng Việt)</option>
                            <option value="Montserrat">Montserrat</option>
                            <option value="SF Pro Display">SF Pro Display (Apple)</option>
                          </select>
                        </div>
                      </>
                    )}

                    {/* Vị trí Watermark 4 Ô Tọa Độ (1-line Title) */}
                    <div style={{ marginTop: 8, marginBottom: 12 }}>
                      <div style={{ fontSize: 11, fontWeight: 600, color: 'var(--text-main)', marginBottom: 6, whiteSpace: 'nowrap' }}>
                        Vị Trí Watermark (`watermark_region`):
                      </div>

                      {/* 4 Coordinate input boxes [Top, Left, Bottom, Right] */}
                      <div style={{
                        padding: '8px 10px',
                        background: 'rgba(0, 0, 0, 0.25)',
                        borderRadius: 8,
                        border: '1px solid var(--border-light)',
                        display: 'flex',
                        flexDirection: 'column',
                        gap: 8
                      }}>
                        <div style={{
                          display: 'grid',
                          gridTemplateColumns: 'repeat(4, 1fr)',
                          gap: 6
                        }}>
                          {['Top', 'Left', 'Bottom', 'Right'].map((lbl, idx) => {
                            const currentReg = Array.isArray(cfg.watermark_region) && cfg.watermark_region.length === 4 
                              ? cfg.watermark_region 
                              : [0.02, 0.02, 0.08, 0.30];
                            return (
                              <div key={lbl} style={{ display: 'flex', flexDirection: 'column', gap: 2 }}>
                                <span style={{ fontSize: 9, color: 'var(--text-dim)', textAlign: 'center', textTransform: 'uppercase' }}>{lbl}</span>
                                <input
                                  type="number"
                                  step="0.01"
                                  min="0"
                                  max="1"
                                  value={currentReg[idx] ?? 0}
                                  onChange={e => {
                                    const val = parseFloat(e.target.value);
                                    const newReg = [...currentReg];
                                    newReg[idx] = isNaN(val) ? 0 : val;
                                    handleCfgChange('watermark_region', newReg);
                                  }}
                                  style={{
                                    padding: '4px',
                                    fontSize: 10,
                                    textAlign: 'center',
                                    borderRadius: 4,
                                    border: '1px solid var(--border)',
                                    background: 'var(--bg-app)',
                                    color: 'var(--text-main)',
                                    fontFamily: 'monospace'
                                  }}
                                />
                              </div>
                            );
                          })}
                        </div>

                        {/* Quick Presets */}
                        <div style={{ display: 'flex', alignItems: 'center', gap: 4, flexWrap: 'wrap' }}>
                          <span style={{ fontSize: 10, color: 'var(--text-dim)', marginRight: 2 }}>Gợi ý:</span>
                          {[
                            { label: '↖️ Trên Trái', reg: [0.02, 0.02, 0.08, 0.30] },
                            { label: '↗️ Trên Phải', reg: [0.02, 0.70, 0.08, 0.98] },
                            { label: '↙️ Dưới Trái', reg: [0.90, 0.02, 0.96, 0.30] },
                            { label: '↘️ Dưới Phải', reg: [0.90, 0.70, 0.96, 0.98] }
                          ].map(preset => (
                            <button
                              key={preset.label}
                              type="button"
                              onClick={() => handleCfgChange('watermark_region', preset.reg)}
                              style={{
                                padding: '2px 6px',
                                fontSize: 9,
                                borderRadius: 4,
                                border: '1px solid var(--border)',
                                background: 'rgba(255, 255, 255, 0.05)',
                                color: 'var(--text-secondary)',
                                cursor: 'pointer'
                              }}
                            >
                              {preset.label}
                            </button>
                          ))}
                        </div>
                      </div>
                    </div>

                    <div style={styles.formRow}>
                      <label style={styles.formLabel}>
                        Độ Trong Suốt ({Math.round((cfg.watermark_opacity ?? 0.85) * 100)}%):
                      </label>
                      <input 
                        type="range"
                        min="0.1"
                        max="1.0"
                        step="0.05"
                        value={cfg.watermark_opacity ?? 0.85}
                        onChange={e => handleCfgChange('watermark_opacity', parseFloat(e.target.value))}
                        style={styles.formRange}
                      />
                    </div>

                    <div style={{ ...styles.formRow, justifyContent: 'space-between' }}>
                      <label style={styles.formLabel}>Mờ Kính Nền (Blur BG):</label>
                      <label style={{ display: 'flex', alignItems: 'center', gap: 6, cursor: 'pointer', fontSize: 11 }}>
                        <input 
                          type="checkbox"
                          checked={cfg.watermark_blur_bg !== false}
                          onChange={e => handleCfgChange('watermark_blur_bg', e.target.checked)}
                          style={{ accentColor: 'var(--primary)', cursor: 'pointer' }}
                        />
                        <span style={{ color: cfg.watermark_blur_bg !== false ? 'var(--text-main)' : 'var(--text-dim)' }}>
                          {cfg.watermark_blur_bg !== false ? 'Bật Mờ Kính' : 'Tắt'}
                        </span>
                      </label>
                    </div>
                  </>
                )}
              </div>
            </>
          )}
        </div>
      )}

      {/* 🎙️ Tab 3: Voice & Audio */}
      {activeTab === 'voice' && (
        <div style={styles.configScrollBody}>
          <div style={styles.configSection}>
            <h4 style={styles.configTitle}>🎙️ Giọng Đọc AI (EdgeTTS)</h4>
            
            <div style={styles.formRow}>
              <label style={styles.formLabel}>Giọng TTS Tiếng Việt:</label>
              <select 
                value={cfg.tts_voice} 
                onChange={e => handleCfgChange('tts_voice', e.target.value)}
                style={styles.formSelect}
              >
                <option value="vi">Ban Mai Tiếng Việt (Nữ - Mặc định)</option>
                <option value="vi-VN-NamMinhNeural">Nam Minh (Nam Trầm Chuẩn)</option>
                <option value="0">Tắt TTS (Giữ 100% tiếng gốc)</option>
              </select>
            </div>

            <div style={styles.formRow}>
              <label style={styles.formLabel}>Tốc Độ Đọc (Speed):</label>
              <input 
                type="number"
                step="0.1"
                min="0.5"
                max="2.5"
                value={cfg.tts_speed || 1.5}
                onChange={e => handleCfgChange('tts_speed', parseFloat(e.target.value) || 1.5)}
                style={styles.formInput}
              />
            </div>
          </div>

          <div style={styles.configSection}>
            <h4 style={styles.configTitle}>🎛️ Âm Lượng & Cân Bằng Audio</h4>
            
            <div style={styles.formRow}>
              <label style={styles.formLabel}>Âm Lượng Giọng TTS:</label>
              <div style={{ flex: 1, display: 'flex', alignItems: 'center', gap: 8 }}>
                <input 
                  type="range"
                  min="0"
                  max="2"
                  step="0.05"
                  value={cfg.tts_vol ?? 1.0}
                  onChange={e => handleCfgChange('tts_vol', parseFloat(e.target.value))}
                  style={styles.sliderInput}
                />
                <span style={styles.sliderValue}>{Math.round((cfg.tts_vol ?? 1.0) * 100)}%</span>
              </div>
            </div>

            <div style={styles.formRow}>
              <label style={styles.formLabel}>Âm Lượng Nhạc Nền:</label>
              <div style={{ flex: 1, display: 'flex', alignItems: 'center', gap: 8 }}>
                <input 
                  type="range"
                  min="0"
                  max="1.5"
                  step="0.05"
                  value={cfg.music_vol ?? 0.5}
                  onChange={e => handleCfgChange('music_vol', parseFloat(e.target.value))}
                  style={styles.sliderInput}
                />
                <span style={styles.sliderValue}>{Math.round((cfg.music_vol ?? 0.5) * 100)}%</span>
              </div>
            </div>

            <div style={styles.formRow}>
              <label style={styles.formLabel}>Âm Lượng Giọng Gốc:</label>
              <div style={{ flex: 1, display: 'flex', alignItems: 'center', gap: 8 }}>
                <input 
                  type="range"
                  min="0"
                  max="1"
                  step="0.01"
                  value={cfg.orig_voice_vol ?? 0.05}
                  onChange={e => handleCfgChange('orig_voice_vol', parseFloat(e.target.value))}
                  style={styles.sliderInput}
                />
                <span style={styles.sliderValue}>{Math.round((cfg.orig_voice_vol ?? 0.05) * 100)}%</span>
              </div>
            </div>

            <div style={styles.formRow}>
              <label style={styles.formLabel}>Âm Lượng Môi Trường:</label>
              <div style={{ flex: 1, display: 'flex', alignItems: 'center', gap: 8 }}>
                <input 
                  type="range"
                  min="0"
                  max="1.5"
                  step="0.05"
                  value={cfg.ambient_vol ?? 0.75}
                  onChange={e => handleCfgChange('ambient_vol', parseFloat(e.target.value))}
                  style={styles.sliderInput}
                />
                <span style={styles.sliderValue}>{Math.round((cfg.ambient_vol ?? 0.75) * 100)}%</span>
              </div>
            </div>
          </div>
        </div>
      )}

      {/* ⚙️ Tab 4: Video & AI Engine */}
      {activeTab === 'engine' && (
        <div style={styles.configScrollBody}>
          <div style={styles.configSection}>
            <h4 style={styles.configTitle}>🎬 Chất Lượng Video & Bitrate</h4>
            
            <div style={styles.formRow}>
              <label style={styles.formLabel}>Video Bitrate:</label>
              <select 
                value={cfg.video_bitrate || '4.0M'} 
                onChange={e => handleCfgChange('video_bitrate', e.target.value)}
                style={styles.formSelect}
              >
                <option value="4.0M">4.0M (TikTok 1080p HD - Sắc nét nhất)</option>
                <option value="2.5M">2.5M (Chuẩn cân bằng)</option>
                <option value="1.5M">1.5M (Tiết kiệm dung lượng)</option>
                <option value="6.0M">6.0M (Ultra HD 4K/2K)</option>
              </select>
            </div>

            <div style={styles.formRow}>
              <label style={styles.formLabel}>Tốc Độ Đọc (Char Rate):</label>
              <input 
                type="number"
                step="0.01"
                value={cfg.char_rate || 0.07}
                onChange={e => handleCfgChange('char_rate', parseFloat(e.target.value) || 0.07)}
                style={styles.formInput}
              />
            </div>

            <div style={styles.formRow}>
              <label style={styles.formLabel}>Tự Động Nối Gap:</label>
              <label style={styles.checkboxLabel}>
                <input 
                  type="checkbox"
                  checked={cfg.fill_gap !== false}
                  onChange={e => handleCfgChange('fill_gap', e.target.checked)}
                  style={styles.checkboxInput}
                />
                <span>Tự động lấp khoảng trống subtitle (Fill Gap)</span>
              </label>
            </div>
          </div>

          <div style={styles.configSection}>
            <h4 style={styles.configTitle}>🤖 AI LLM Translator</h4>
            
            <div style={styles.formRow}>
              <label style={styles.formLabel}>AI Provider:</label>
              <select 
                value={cfg.translator_type} 
                onChange={e => handleCfgChange('translator_type', e.target.value)}
                style={styles.formSelect}
              >
                <option value="ollama">Ollama Local (Gemma / Qwen)</option>
                <option value="openai">OpenAI (GPT-4o / GPT-4o-mini)</option>
                <option value="deepseek">DeepSeek API</option>
                <option value="gemini">Google Gemini</option>
                <option value="groq">Groq High-Speed</option>
              </select>
            </div>

            <div style={styles.formRow}>
              <label style={styles.formLabel}>AI Model:</label>
              <input 
                type="text"
                value={cfg.translator_model}
                onChange={e => handleCfgChange('translator_model', e.target.value)}
                style={styles.formInput}
                placeholder="gemma4:31b-cloud"
              />
            </div>

            <div style={styles.formRow}>
              <label style={styles.formLabel}>Batch Size:</label>
              <input 
                type="number"
                value={cfg.translator_batch_size}
                onChange={e => handleCfgChange('translator_batch_size', parseInt(e.target.value) || 20)}
                style={styles.formInput}
              />
            </div>

            <div style={styles.formRow}>
              <label style={styles.formLabel}>Base URL:</label>
              <input 
                type="text"
                value={cfg.translator_base_url}
                onChange={e => handleCfgChange('translator_base_url', e.target.value)}
                style={styles.formInput}
              />
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

const styles = {
  container: {
    backgroundColor: 'var(--bg-card, #151D30)',
    borderRadius: 'var(--radius-md, 8px)',
    border: '1px solid var(--border-color, #263554)',
    display: 'flex',
    flexDirection: 'column',
    height: '100%',
    minHeight: 0,
    maxHeight: '100%',
    overflow: 'hidden',
    boxShadow: 'var(--shadow-md, 0 4px 6px -1px rgba(0,0,0,0.4))',
  },
  tabHeader: {
    display: 'flex',
    borderBottom: '1px solid var(--border-color, #263554)',
    backgroundColor: 'var(--bg-surface, #0f172a)',
    flexShrink: 0,
    width: '100%',
  },
  tabBtn: {
    flex: 1,
    padding: '10px 8px',
    backgroundColor: 'transparent',
    color: 'var(--text-muted, #94a3b8)',
    fontSize: 12,
    fontWeight: 600,
    border: 'none',
    borderBottom: '2px solid transparent',
    cursor: 'pointer',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 6,
    transition: 'all 0.15s ease',
    whiteSpace: 'nowrap',
  },
  tabBtnActive: {
    color: 'var(--primary-light, #818cf8)',
    borderBottomColor: 'var(--primary, #6366f1)',
    backgroundColor: 'rgba(99, 102, 241, 0.08)',
  },
  tabBody: {
    display: 'flex',
    flexDirection: 'column',
    flex: 1,
    minHeight: 0,
    height: '100%',
    overflow: 'hidden',
  },
  langBar: {
    padding: '8px 12px',
    borderBottom: '1px solid var(--border-color, #263554)',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between',
    backgroundColor: 'var(--bg-surface, #1e293b)',
    flexShrink: 0,
  },
  langPair: {
    display: 'flex',
    alignItems: 'center',
    gap: 6,
  },
  langLabel: {
    fontSize: 11,
    color: 'var(--text-dim, #64748b)',
    fontWeight: 600,
  },
  langSelect: {
    backgroundColor: 'var(--bg-input, #0b1120)',
    border: '1px solid var(--border-color, #263554)',
    color: 'var(--text-main, #e2e8f0)',
    fontSize: 11,
    fontWeight: 600,
    borderRadius: 4,
    padding: '4px 6px',
    outline: 'none',
  },
  translateAllBtn: {
    display: 'flex',
    alignItems: 'center',
    gap: 5,
    padding: '5px 10px',
    backgroundColor: 'var(--primary, #6366f1)',
    color: '#ffffff',
    border: 'none',
    borderRadius: 5,
    fontSize: 11,
    fontWeight: 700,
    cursor: 'pointer',
    boxShadow: '0 2px 6px rgba(99, 102, 241, 0.35)',
  },
  listContainer: {
    flex: 1,
    overflowY: 'auto',
    padding: '6px',
    display: 'flex',
    flexDirection: 'column',
    gap: 4,
  },
  emptyState: {
    display: 'flex',
    flexDirection: 'column',
    alignItems: 'center',
    justifyContent: 'center',
    height: '100%',
    padding: '24px 0',
  },
  addInitialBtn: {
    marginTop: 12,
    display: 'flex',
    alignItems: 'center',
    gap: 6,
    padding: '6px 14px',
    backgroundColor: 'var(--primary, #6366f1)',
    color: '#ffffff',
    border: 'none',
    borderRadius: 6,
    fontSize: 12,
    fontWeight: 600,
    cursor: 'pointer',
  },
  subRow: {
    display: 'flex',
    alignItems: 'flex-start',
    gap: 8,
    padding: '6px 8px',
    backgroundColor: 'var(--bg-surface, #0f172a)',
    border: '1px solid var(--border-color, #263554)',
    borderRadius: 6,
    cursor: 'pointer',
    transition: 'all 0.12s ease',
  },
  subRowActive: {
    borderColor: 'var(--primary, #6366f1)',
    backgroundColor: 'rgba(99, 102, 241, 0.12)',
  },
  subRowSelected: {
    borderColor: '#38bdf8',
    backgroundColor: 'rgba(56, 189, 248, 0.15)',
    boxShadow: '0 0 8px rgba(56, 189, 248, 0.25)',
  },
  subIndexCol: {
    display: 'flex',
    flexDirection: 'column',
    alignItems: 'center',
    gap: 2,
    width: 85,
    flexShrink: 0,
    cursor: 'pointer',
    padding: '2px 0',
    borderRadius: 4,
  },
  subIndexColEditing: {
    display: 'flex',
    flexDirection: 'column',
    alignItems: 'center',
    gap: 2,
    width: 120,
    flexShrink: 0,
  },
  timeInputRow: {
    display: 'flex',
    alignItems: 'center',
    gap: 3,
    width: '100%',
  },
  timeInputEdit: {
    flex: 1,
    minWidth: 0,
    padding: '2px 4px',
    fontFamily: 'monospace',
    fontSize: 9,
    fontWeight: 600,
    color: 'var(--primary-light, #818cf8)',
    backgroundColor: 'var(--bg-input, #0b1120)',
    border: '1px solid var(--border-color, #263554)',
    borderRadius: 3,
    textAlign: 'center',
    outline: 'none',
  },
  setTimeBtn: {
    backgroundColor: 'rgba(99, 102, 241, 0.15)',
    border: '1px solid rgba(99, 102, 241, 0.4)',
    borderRadius: 3,
    color: 'var(--primary-light, #818cf8)',
    padding: '2px 4px',
    cursor: 'pointer',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    flexShrink: 0,
  },
  subNumber: {
    fontSize: 10,
    fontWeight: 700,
    color: 'var(--text-dim, #64748b)',
  },
  timeRangeBox: {
    display: 'flex',
    flexDirection: 'column',
    gap: 1,
    alignItems: 'center',
  },
  timecodeStr: {
    fontSize: 9,
    fontFamily: 'monospace',
    color: 'var(--text-muted, #94a3b8)',
  },
  textContentCol: {
    flex: 1,
    overflow: 'hidden',
  },
  textDisplay: {
    display: 'flex',
    flexDirection: 'column',
    gap: 2,
  },
  origText: {
    fontSize: 11,
    color: 'var(--text-dim, #64748b)',
    whiteSpace: 'nowrap',
    overflow: 'hidden',
    textOverflow: 'ellipsis',
  },
  transText: {
    fontSize: 12,
    fontWeight: 600,
    color: 'var(--text-main, #e2e8f0)',
    whiteSpace: 'nowrap',
    overflow: 'hidden',
    textOverflow: 'ellipsis',
  },
  editFields: {
    display: 'flex',
    flexDirection: 'column',
    gap: 4,
  },
  inlineInput: {
    width: '100%',
    backgroundColor: 'var(--bg-input, #0b1120)',
    border: '1px solid var(--border-color, #263554)',
    borderRadius: 4,
    padding: '4px 6px',
    color: 'var(--text-main, #e2e8f0)',
    fontSize: 11,
    outline: 'none',
    boxSizing: 'border-box',
  },
  rowActions: {
    display: 'flex',
    alignItems: 'center',
    gap: 4,
    flexShrink: 0,
  },
  iconActionBtn: {
    background: 'none',
    border: 'none',
    color: 'var(--text-muted, #94a3b8)',
    cursor: 'pointer',
    padding: 3,
    borderRadius: 4,
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
  },
  bottomBar: {
    padding: '6px 10px',
    borderTop: '1px solid var(--border-color, #263554)',
    backgroundColor: 'var(--bg-surface, #0f172a)',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between',
    flexShrink: 0,
  },
  bottomBtn: {
    display: 'flex',
    alignItems: 'center',
    gap: 5,
    padding: '5px 10px',
    backgroundColor: 'transparent',
    border: '1px solid var(--border-color, #263554)',
    color: 'var(--text-main, #e2e8f0)',
    borderRadius: 5,
    fontSize: 11,
    fontWeight: 600,
    cursor: 'pointer',
  },
  autoSyncBtn: {
    borderColor: 'rgba(16, 185, 129, 0.4)',
    color: 'var(--accent-green, #10b981)',
    backgroundColor: 'rgba(16, 185, 129, 0.08)',
  },
  configScrollBody: {
    flex: 1,
    height: '100%',
    minHeight: 0,
    maxHeight: '100%',
    overflowY: 'auto',
    overflowX: 'hidden',
    padding: '12px',
    display: 'flex',
    flexDirection: 'column',
    gap: 14,
    boxSizing: 'border-box',
    width: '100%',
    WebkitOverflowScrolling: 'touch',
  },
  configSection: {
    backgroundColor: 'var(--bg-surface)',
    border: '1px solid var(--border-color)',
    borderRadius: 'var(--radius-md, 8px)',
    padding: '12px',
    display: 'flex',
    flexDirection: 'column',
    gap: 10,
    boxSizing: 'border-box',
    width: '100%',
    boxShadow: 'var(--shadow-sm)',
  },
  configTitle: {
    fontSize: 12,
    fontWeight: 700,
    color: 'var(--text-main)',
    margin: '0 0 4px 0',
    display: 'flex',
    alignItems: 'center',
    gap: 6,
  },
  formRow: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: 10,
    width: '100%',
    minWidth: 0,
    boxSizing: 'border-box',
  },
  formLabel: {
    fontSize: 11,
    fontWeight: 600,
    color: 'var(--text-muted)',
    width: 120,
    minWidth: 100,
    flexShrink: 0,
  },
  formSelect: {
    flex: 1,
    minWidth: 0,
    width: '100%',
    maxWidth: '100%',
    backgroundColor: 'var(--bg-input)',
    border: '1px solid var(--border-color)',
    borderRadius: 6,
    color: 'var(--text-main)',
    fontSize: 11,
    padding: '6px 8px',
    outline: 'none',
    boxSizing: 'border-box',
    textOverflow: 'ellipsis',
  },
  formInput: {
    flex: 1,
    minWidth: 0,
    width: '100%',
    maxWidth: '100%',
    backgroundColor: 'var(--bg-input)',
    border: '1px solid var(--border-color)',
    borderRadius: 6,
    color: 'var(--text-main)',
    fontSize: 11,
    padding: '6px 8px',
    outline: 'none',
    boxSizing: 'border-box',
  },
  formRange: {
    flex: 1,
    minWidth: 0,
    accentColor: 'var(--primary)',
    cursor: 'pointer',
  },
  sliderInput: {
    flex: 1,
    minWidth: 0,
    accentColor: 'var(--primary)',
    cursor: 'pointer',
  },
  sliderValue: {
    fontSize: 11,
    fontWeight: 700,
    color: 'var(--primary)',
    width: 36,
    textAlign: 'right',
  },
  checkboxLabel: {
    flex: 1,
    display: 'flex',
    alignItems: 'center',
    gap: 8,
    fontSize: 11,
    color: 'var(--text-main)',
    cursor: 'pointer',
  },
  checkboxInput: {
    accentColor: 'var(--primary)',
    cursor: 'pointer',
    transform: 'scale(1.15)',
  }
};
