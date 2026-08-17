import React, { useState } from 'react';
import { 
  FileVideo, 
  Clock, 
  HardDrive, 
  Scissors, 
  Trash2,
  Volume2, 
  VolumeX, 
  Layers, 
  Sparkles, 
  CheckCircle2, 
  Copy, 
  Check, 
  ExternalLink,
  ChevronDown,
  Info
} from 'lucide-react';

const PIPELINE_STEPS = [
  { id: 's01_probe', label: '1. Probe Video Info' },
  { id: 's02_demux', label: '2. Demux Streams' },
  { id: 's03_subtitle_detect', label: '3. Subtitle Region Detect' },
  { id: 's04_audio_separate', label: '4. Demucs Audio Separate' },
  { id: 's05_asr', label: '5. Whisper ASR' },
  { id: 's05b_gender_detect', label: '5b. Gender Detect' },
  { id: 's06_ocr', label: '6. PaddleOCR Subtitle' },
  { id: 's07_transcript_merge', label: '7. Merge ASR & OCR' },
  { id: 's08_translation', label: '8. AI LLM Translation' },
  { id: 's08b_metadata_gen', label: '8b. AI Metadata Gen' },
  { id: 's08c_timing', label: '8c. Subtitle Timing Optimizer' },
  { id: 's09_subtitle_gen', label: '9. Subtitle Gen (ASS/SRT)' },
  { id: 's10_inpaint', label: '10. Subtitle Inpaint & Blur' },
  { id: 's11_subtitle_render', label: '11. Subtitle Render' },
  { id: 's12_tts', label: '12. EdgeTTS Voice Gen' },
  { id: 's13_audio_mix', label: '13. Audio Multi-Mix' },
  { id: 's14_encode', label: '14. Final H.264 Encode' }
];

const formatDurationMs = (sec) => {
  if (sec === null || sec === undefined || isNaN(sec) || sec < 0) return '00:00:00.000';
  const hrs = Math.floor(sec / 3600);
  const mins = Math.floor((sec % 3600) / 60);
  const secs = Math.floor(sec % 60);
  const ms = Math.floor((sec % 1) * 1000);
  if (hrs > 0) {
    return `${hrs.toString().padStart(2, '0')}:${mins.toString().padStart(2, '0')}:${secs.toString().padStart(2, '0')}.${ms.toString().padStart(3, '0')}`;
  }
  return `00:${mins.toString().padStart(2, '0')}:${secs.toString().padStart(2, '0')}.${ms.toString().padStart(3, '0')}`;
};

const formatSize = (bytes) => {
  if (!bytes || isNaN(bytes) || bytes <= 0) return '0 MB';
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  if (bytes < 1024 * 1024 * 1024) return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
  return `${(bytes / (1024 * 1024 * 1024)).toFixed(2)} GB`;
};

export default function PropertiesInspector({
  videoFile,
  duration = 0,
  startTime = 0,
  endTime = 0,
  onRangeChange,
  onCutTrim,
  cutMode = 'remove',
  jobFiles = [],
  metadata = null,
  onDeleteStep,
  onDeleteJob,
  isProcessing = false
}) {
  const [activeTab, setActiveTab] = useState('properties'); // 'properties' | 'steps' | 'metadata'
  const [copiedField, setCopiedField] = useState(null);
  const [audioVolume, setAudioVolume] = useState(100);
  const [isMuted, setIsMuted] = useState(false);

  const copyToClipboard = (text, fieldName) => {
    navigator.clipboard.writeText(text);
    setCopiedField(fieldName);
    setTimeout(() => setCopiedField(null), 2000);
  };

  const getStepCacheInfo = (stepId) => {
    if (!jobFiles || jobFiles.length === 0) return null;
    const match = jobFiles.find(f => {
      const fname = f.name.toLowerCase();
      if (stepId === 's01_probe') return fname.includes('s01') || fname.includes('probe');
      if (stepId === 's02_demux') return fname.includes('s02') || fname.includes('video_stream') || fname.includes('audio_stream');
      if (stepId === 's03_subtitle_detect') return fname.includes('s03');
      if (stepId === 's04_audio_separate') return fname.includes('s04') || fname.includes('voice.wav') || fname.includes('music.wav');
      if (stepId === 's05_asr') return fname.includes('s05_asr');
      if (stepId === 's05b_gender_detect') return fname.includes('s05b');
      if (stepId === 's06_ocr') return fname.includes('s06_ocr');
      if (stepId === 's07_transcript_merge') return fname.includes('s07_transcript');
      if (stepId === 's08_translation') return fname.includes('s08_translation');
      if (stepId === 's08b_metadata_gen') return fname.includes('s08b_metadata');
      if (stepId === 's08c_timing') return fname.includes('s08c_timing');
      if (stepId === 's09_subtitle_gen') return fname.includes('s09') || fname.includes('.ass') || fname.includes('.srt');
      if (stepId === 's10_inpaint') return fname.includes('s10') || fname.includes('clean_video');
      if (stepId === 's11_subtitle_render') return fname.includes('s11') || fname.includes('rendered_video');
      if (stepId === 's12_tts') return fname.includes('s12') || fname.includes('tts_audio');
      if (stepId === 's13_audio_mix') return fname.includes('s13') || fname.includes('mixed_audio');
      if (stepId === 's14_encode') return fname.includes('s14') || fname.includes('_vi.mp4');
      return fname.includes(stepId);
    });
    return match || null;
  };

  const isRemoveMode = cutMode === 'remove';

  return (
    <div style={styles.container}>
      {/* Tabs Header */}
      <div style={styles.tabHeader}>
        {[
          { id: 'properties', label: 'Properties' },
          { id: 'steps', label: `Steps (${jobFiles.length})` },
          { id: 'metadata', label: 'AI Metadata' }
        ].map(t => (
          <button
            key={t.id}
            style={{
              ...styles.tabBtn,
              ...(activeTab === t.id ? styles.tabBtnActive : {})
            }}
            onClick={() => setActiveTab(t.id)}
          >
            {t.label}
          </button>
        ))}
      </div>

      {/* Tab 1: Properties */}
      {activeTab === 'properties' && (
        <div style={styles.bodyScroll}>
          {/* Section: Basic */}
          <div style={styles.sectionGroup}>
            <span style={styles.sectionTitle}>Basic Info</span>
            
            <div style={styles.propItem}>
              <label style={styles.propLabel}>File Name</label>
              <input 
                type="text" 
                value={videoFile ? videoFile.name : 'Chưa chọn video'} 
                readOnly 
                style={styles.propInput} 
              />
            </div>

            <div style={styles.propItem}>
              <label style={styles.propLabel}>Resolution</label>
              <input 
                type="text"
                value={videoFile?.resolution || '1920x1080 (FHD)'}
                readOnly
                style={styles.propInput}
              />
            </div>

            <div style={styles.propRow}>
              <div style={{ flex: 1 }}>
                <label style={styles.propLabel}>FPS</label>
                <input type="text" value="30 fps" readOnly style={styles.propInput} />
              </div>
              <div style={{ flex: 1 }}>
                <label style={styles.propLabel}>Duration</label>
                <input type="text" value={formatDurationMs(duration)} readOnly style={{ ...styles.propInput, fontFamily: 'monospace' }} />
              </div>
            </div>

            <div style={styles.propItem}>
              <label style={styles.propLabel}>Size</label>
              <input 
                type="text" 
                value={videoFile ? formatSize(videoFile.size || videoFile.sizeBytes) : '0 MB'} 
                readOnly 
                style={{ ...styles.propInput, color: 'var(--primary-light)', fontWeight: 600 }} 
              />
            </div>
          </div>

          {/* Section: Edit / Trim */}
          <div style={styles.sectionGroup}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
              <span style={styles.sectionTitle}>
                {isRemoveMode ? '🗑️ Cắt Bỏ Đoạn Rác' : '✂️ Trích Đoạn Cần Giữ'}
              </span>
              <span style={{ fontSize: 10, color: 'var(--text-dim)' }}>ms accurate</span>
            </div>
            
            <div style={styles.propItem}>
              <label style={styles.propLabel}>Start Time (hh:mm:ss.ms)</label>
              <div style={styles.inputWithIcon}>
                <Clock size={13} color="var(--text-dim)" />
                <input 
                  type="text" 
                  value={formatDurationMs(startTime)} 
                  readOnly 
                  style={styles.cleanInput} 
                />
              </div>
            </div>

            <div style={styles.propItem}>
              <label style={styles.propLabel}>End Time (hh:mm:ss.ms)</label>
              <div style={styles.inputWithIcon}>
                <Clock size={13} color="var(--text-dim)" />
                <input 
                  type="text" 
                  value={formatDurationMs(endTime || duration)} 
                  readOnly 
                  style={styles.cleanInput} 
                />
              </div>
            </div>

            <button 
              style={{
                ...styles.cutActionBtn,
                ...(isRemoveMode ? styles.cutRemoveBtn : styles.cutKeepBtn)
              }}
              onClick={onCutTrim}
              disabled={isProcessing || !videoFile}
              title={isRemoveMode ? 'Cắt loại bỏ đoạn rác và ghi đè trực tiếp lên file gốc' : 'Cắt trích xuất đoạn chọn thành file mới'}
            >
              {isRemoveMode ? <Trash2 size={14} /> : <Scissors size={14} />}
              <span>{isRemoveMode ? 'Loại Bỏ Đoạn Rác (Ghi Đè)' : 'Trimmer Clip (File Mới)'}</span>
            </button>
          </div>

          {/* Section: Audio */}
          <div style={styles.sectionGroup}>
            <span style={styles.sectionTitle}>Audio Settings</span>
            
            <div style={styles.propItem}>
              <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: 4 }}>
                <label style={styles.propLabel}>Volume</label>
                <span style={{ fontSize: 11, color: 'var(--primary-light)', fontWeight: 600 }}>
                  {isMuted ? '0%' : `${audioVolume}%`}
                </span>
              </div>
              <input
                type="range"
                min="0"
                max="150"
                value={isMuted ? 0 : audioVolume}
                onChange={e => setAudioVolume(parseInt(e.target.value))}
                style={styles.rangeSlider}
              />
            </div>

            <div style={styles.checkboxRow}>
              <input
                type="checkbox"
                id="mute-check"
                checked={isMuted}
                onChange={e => setIsMuted(e.target.checked)}
                style={{ accentColor: 'var(--primary)' }}
              />
              <label htmlFor="mute-check" style={{ fontSize: 12, color: 'var(--text-muted)', cursor: 'pointer' }}>
                Mute âm thanh
              </label>
            </div>
          </div>
        </div>
      )}

      {/* Tab 2: 15 Step Badges */}
      {activeTab === 'steps' && (
        <div style={styles.bodyScroll}>
          <div style={styles.stepHeader}>
            <span style={{ fontSize: 11, color: 'var(--text-dim)' }}>
              15 Bước Pipeline Cache
            </span>
            <button 
              style={styles.deleteJobBtn}
              onClick={onDeleteJob}
              title="Xóa toàn bộ thư mục workspace của video này"
            >
              <Trash2 size={12} /> Xóa Job Cache
            </button>
          </div>

          <div style={styles.stepList}>
            {PIPELINE_STEPS.map(step => {
              const cacheInfo = getStepCacheInfo(step.id);
              const isCached = !!cacheInfo;

              return (
                <div key={step.id} style={styles.stepItem}>
                  <div style={styles.stepInfo}>
                    <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
                      <span 
                        style={{
                          ...styles.statusBadge,
                          backgroundColor: isCached ? 'var(--accent-green-bg)' : 'rgba(255,255,255,0.05)',
                          color: isCached ? 'var(--accent-green)' : 'var(--text-dim)',
                          borderColor: isCached ? 'var(--accent-green-border)' : 'transparent'
                        }}
                      >
                        {isCached ? '🟢 Cached' : '⚪ Chưa chạy'}
                      </span>
                      <span style={styles.stepLabel}>{step.label}</span>
                    </div>

                    {isCached && (
                      <span style={styles.cacheDetail}>
                        {cacheInfo.name} ({formatSize(cacheInfo.size || cacheInfo.sizeBytes)})
                      </span>
                    )}
                  </div>

                  {isCached && (
                    <button 
                      style={styles.stepDeleteBtn}
                      onClick={() => onDeleteStep && onDeleteStep(step.id)}
                      title={`Xóa cache ${step.id} (Tự động xóa các bước phụ thuộc phía sau)`}
                    >
                      <Trash2 size={12} />
                    </button>
                  )}
                </div>
              );
            })}
          </div>
        </div>
      )}

      {/* Tab 3: AI Metadata */}
      {activeTab === 'metadata' && (
        <div style={styles.bodyScroll}>
          {metadata ? (
            <div style={styles.metadataContainer}>
              {/* Title */}
              <div style={styles.metaBox}>
                <div style={styles.metaHeader}>
                  <span style={styles.metaLabel}>Tiêu đề Video AI</span>
                  <button 
                    style={styles.copyBtn}
                    onClick={() => copyToClipboard(metadata.title || '', 'title')}
                  >
                    {copiedField === 'title' ? <Check size={12} color="var(--accent-green)" /> : <Copy size={12} />}
                    <span>{copiedField === 'title' ? 'Đã chép' : 'Copy'}</span>
                  </button>
                </div>
                <div style={styles.metaContent}>{metadata.title || '(Chưa có tiêu đề)'}</div>
              </div>

              {/* Description */}
              <div style={styles.metaBox}>
                <div style={styles.metaHeader}>
                  <span style={styles.metaLabel}>Mô tả Video AI</span>
                  <button 
                    style={styles.copyBtn}
                    onClick={() => copyToClipboard(metadata.description || '', 'desc')}
                  >
                    {copiedField === 'desc' ? <Check size={12} color="var(--accent-green)" /> : <Copy size={12} />}
                    <span>{copiedField === 'desc' ? 'Đã chép' : 'Copy'}</span>
                  </button>
                </div>
                <div style={styles.metaContent}>{metadata.description || '(Chưa có mô tả)'}</div>
              </div>

              {/* Hashtags */}
              <div style={styles.metaBox}>
                <div style={styles.metaHeader}>
                  <span style={styles.metaLabel}>Hashtags Xu Hướng</span>
                  <button 
                    style={styles.copyBtn}
                    onClick={() => copyToClipboard((metadata.hashtags || []).join(' '), 'tags')}
                  >
                    {copiedField === 'tags' ? <Check size={12} color="var(--accent-green)" /> : <Copy size={12} />}
                    <span>{copiedField === 'tags' ? 'Đã chép' : 'Copy'}</span>
                  </button>
                </div>
                <div style={styles.hashtagList}>
                  {(metadata.hashtags || ['#video', '#viral', '#tiktok']).map((tag, idx) => (
                    <span key={idx} style={styles.tagPill}>{tag}</span>
                  ))}
                </div>
              </div>
            </div>
          ) : (
            <div style={styles.emptyMetadata}>
              <Sparkles size={32} color="var(--text-dim)" />
              <p style={{ fontSize: 13, color: 'var(--text-muted)', marginTop: 8 }}>
                Chưa có dữ liệu AI Metadata cho video này
              </p>
              <p style={{ fontSize: 11, color: 'var(--text-dim)', marginTop: 4 }}>
                Chạy Dịch Video (s08b_metadata_gen) để AI tự động sinh Tiêu đề, Mô tả và Hashtags.
              </p>
            </div>
          )}
        </div>
      )}
    </div>
  );
}

const styles = {
  container: {
    backgroundColor: 'var(--bg-card)',
    borderRadius: 'var(--radius-md)',
    border: '1px solid var(--border-color)',
    display: 'flex',
    flexDirection: 'column',
    height: '100%',
    overflow: 'hidden',
    boxShadow: 'var(--shadow-md)',
  },
  tabHeader: {
    display: 'flex',
    borderBottom: '1px solid var(--border-color)',
    backgroundColor: 'var(--bg-surface)',
  },
  tabBtn: {
    flex: 1,
    padding: '8px 6px',
    backgroundColor: 'transparent',
    color: 'var(--text-muted)',
    fontSize: 12,
    fontWeight: 600,
    border: 'none',
    borderBottom: '2px solid transparent',
  },
  tabBtnActive: {
    color: 'var(--primary-light)',
    borderBottom: '2px solid var(--primary)',
    backgroundColor: 'rgba(59, 130, 246, 0.08)',
  },
  bodyScroll: {
    flex: 1,
    overflowY: 'auto',
    padding: '12px 14px',
    display: 'flex',
    flexDirection: 'column',
    gap: 14,
  },
  sectionGroup: {
    display: 'flex',
    flexDirection: 'column',
    gap: 8,
  },
  sectionTitle: {
    fontSize: 12,
    fontWeight: 700,
    color: 'var(--text-main)',
    borderBottom: '1px solid var(--border-subtle)',
    paddingBottom: 4,
  },
  propItem: {
    display: 'flex',
    flexDirection: 'column',
    gap: 4,
  },
  propRow: {
    display: 'flex',
    gap: 8,
  },
  propLabel: {
    fontSize: 11,
    color: 'var(--text-dim)',
    fontWeight: 500,
  },
  propInput: {
    width: '100%',
    padding: '6px 8px',
    fontSize: 12,
    backgroundColor: 'var(--bg-input)',
    border: '1px solid var(--border-color)',
    color: 'var(--text-main)',
    borderRadius: 'var(--radius-sm)',
  },
  inputWithIcon: {
    display: 'flex',
    alignItems: 'center',
    gap: 6,
    padding: '4px 8px',
    backgroundColor: 'var(--bg-input)',
    border: '1px solid var(--border-color)',
    borderRadius: 'var(--radius-sm)',
  },
  cleanInput: {
    flex: 1,
    background: 'transparent',
    border: 'none',
    color: 'var(--text-main)',
    fontSize: 12,
    fontFamily: 'monospace',
  },
  cutActionBtn: {
    width: '100%',
    marginTop: 4,
    padding: '7px 12px',
    borderRadius: 'var(--radius-sm)',
    fontSize: 12,
    fontWeight: 600,
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 6,
    border: '1px solid transparent',
  },
  cutRemoveBtn: {
    backgroundColor: 'rgba(239, 68, 68, 0.18)',
    color: '#f87171',
    borderColor: 'rgba(239, 68, 68, 0.4)',
  },
  cutKeepBtn: {
    backgroundColor: 'rgba(59, 130, 246, 0.18)',
    color: 'var(--primary-light)',
    borderColor: 'rgba(59, 130, 246, 0.4)',
  },
  rangeSlider: {
    width: '100%',
    height: 4,
    accentColor: 'var(--primary)',
    cursor: 'pointer',
  },
  checkboxRow: {
    display: 'flex',
    alignItems: 'center',
    gap: 6,
    marginTop: 2,
  },
  stepHeader: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between',
    marginBottom: 6,
  },
  deleteJobBtn: {
    display: 'flex',
    alignItems: 'center',
    gap: 4,
    padding: '3px 8px',
    fontSize: 11,
    backgroundColor: 'rgba(239, 68, 68, 0.12)',
    color: '#f87171',
    border: '1px solid rgba(239, 68, 68, 0.3)',
    borderRadius: 'var(--radius-sm)',
  },
  stepList: {
    display: 'flex',
    flexDirection: 'column',
    gap: 6,
  },
  stepItem: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between',
    padding: '6px 8px',
    backgroundColor: 'var(--bg-surface)',
    borderRadius: 'var(--radius-sm)',
    border: '1px solid var(--border-subtle)',
  },
  stepInfo: {
    display: 'flex',
    flexDirection: 'column',
    gap: 2,
    overflow: 'hidden',
  },
  statusBadge: {
    fontSize: 10,
    fontWeight: 600,
    padding: '1px 5px',
    borderRadius: 8,
    border: '1px solid transparent',
  },
  stepLabel: {
    fontSize: 11,
    color: 'var(--text-main)',
    fontWeight: 500,
  },
  cacheDetail: {
    fontSize: 10,
    color: 'var(--text-dim)',
    fontFamily: 'monospace',
  },
  stepDeleteBtn: {
    padding: '4px',
    background: 'none',
    border: 'none',
    color: 'var(--accent-red)',
    cursor: 'pointer',
  },
  metadataContainer: {
    display: 'flex',
    flexDirection: 'column',
    gap: 10,
  },
  metaBox: {
    backgroundColor: 'var(--bg-surface)',
    padding: '10px',
    borderRadius: 'var(--radius-sm)',
    border: '1px solid var(--border-subtle)',
    display: 'flex',
    flexDirection: 'column',
    gap: 6,
  },
  metaHeader: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  metaLabel: {
    fontSize: 11,
    fontWeight: 600,
    color: 'var(--text-dim)',
  },
  copyBtn: {
    display: 'flex',
    alignItems: 'center',
    gap: 4,
    padding: '2px 6px',
    fontSize: 10,
    backgroundColor: 'var(--bg-input)',
    color: 'var(--text-muted)',
    border: '1px solid var(--border-color)',
    borderRadius: 4,
  },
  metaContent: {
    fontSize: 12,
    color: 'var(--text-main)',
    lineHeight: 1.4,
  },
  hashtagList: {
    display: 'flex',
    flexWrap: 'wrap',
    gap: 6,
  },
  tagPill: {
    fontSize: 11,
    padding: '2px 8px',
    borderRadius: 12,
    backgroundColor: 'rgba(59, 130, 246, 0.15)',
    color: 'var(--primary-light)',
    border: '1px solid rgba(59, 130, 246, 0.3)',
  },
  emptyMetadata: {
    display: 'flex',
    flexDirection: 'column',
    alignItems: 'center',
    justifyContent: 'center',
    textAlign: 'center',
    padding: 24,
  }
};
