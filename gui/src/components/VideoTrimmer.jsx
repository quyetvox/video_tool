import React, { useState, useRef, useEffect } from 'react';
import { Scissors, Play, CheckCircle2, AlertCircle, RefreshCw, FileVideo, Clock, Sparkles } from 'lucide-react';
import { getMediaUrl, runScript } from '../services/api';

import CompactVideoCard from './CompactVideoCard';

// Helper: Format seconds float to 'mm:ss' or 'hh:mm:ss' string
const formatTimeStr = (seconds) => {
  if (seconds === null || seconds === undefined || isNaN(seconds) || seconds < 0) {
    return '00:00';
  }
  const totalSecs = Math.floor(seconds);
  const hrs = Math.floor(totalSecs / 3600);
  const mins = Math.floor((totalSecs % 3600) / 60);
  const secs = totalSecs % 60;

  if (hrs > 0) {
    return `${hrs.toString().padStart(2, '0')}:${mins.toString().padStart(2, '0')}:${secs.toString().padStart(2, '0')}`;
  }
  return `${mins.toString().padStart(2, '0')}:${secs.toString().padStart(2, '0')}`;
};

// Helper: Parse 'mm:ss' or 'hh:mm:ss' or seconds float back to float seconds
const parseTimeStr = (val) => {
  if (val === null || val === undefined) return 0;
  if (typeof val === 'number') return Math.max(0, val);
  const str = val.toString().trim();
  if (!str) return 0;

  if (str.includes(':')) {
    const parts = str.split(':');
    if (parts.length === 2) {
      const m = parseFloat(parts[0]) || 0;
      const s = parseFloat(parts[1]) || 0;
      return m * 60 + s;
    } else if (parts.length === 3) {
      const h = parseFloat(parts[0]) || 0;
      const m = parseFloat(parts[1]) || 0;
      const s = parseFloat(parts[2]) || 0;
      return h * 3600 + m * 60 + s;
    }
  }

  const parsed = parseFloat(str);
  return isNaN(parsed) ? 0 : Math.max(0, parsed);
};

export default function VideoTrimmer({ 
  initialVideoPath, 
  project, 
  srcFiles = [], 
  outputFiles = [],
  onSelectTab,
  onRefresh,
  embedded = false,
  embeddedControlsOnly = false
}) {
  const allFiles = [...srcFiles, ...outputFiles].filter(f => f.isMedia);
  const [selectedRelPath, setSelectedRelPath] = useState(initialVideoPath || (allFiles[0]?.relPath || ''));
  const [folderFilter, setFolderFilter] = useState('all'); // 'all' | 'src' | 'output'
  const [searchQuery, setSearchQuery] = useState('');
  const [displayLimit, setDisplayLimit] = useState(24);
  const [startTime, setStartTime] = useState(0);
  const [endTime, setEndTime] = useState(0);
  const [duration, setDuration] = useState(0);

  const [startTimeInput, setStartTimeInput] = useState('00:00');
  const [endTimeInput, setEndTimeInput] = useState('00:00');

  const [suggestedOutput, setSuggestedOutput] = useState('');
  const [customOutput, setCustomOutput] = useState('');
  
  const [activeThumb, setActiveThumb] = useState('start');
  const [isAccurate, setIsAccurate] = useState(false);
  const [isOverwriting, setIsOverwriting] = useState(false);
  const [isProcessing, setIsProcessing] = useState(false);
  const [processingRelPath, setProcessingRelPath] = useState(null);

  const videoRef = useRef(null);

  useEffect(() => {
    if (initialVideoPath) {
      setSelectedRelPath(initialVideoPath);
    } else if (allFiles.length > 0 && !selectedRelPath) {
      setSelectedRelPath(allFiles[0].relPath);
    }
  }, [initialVideoPath, allFiles]);

  // Fetch auto-increment suggested output name when selected video changes
  useEffect(() => {
    if (!selectedRelPath) return;

    fetch('/api/suggest-trim-name', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ inputPath: selectedRelPath })
    })
      .then(res => res.json())
      .then(data => {
        if (data.success && data.suggestedPath) {
          setSuggestedOutput(data.suggestedPath);
          setCustomOutput(data.suggestedPath);
        }
      })
      .catch(err => console.error('Failed to suggest trim name:', err));
  }, [selectedRelPath]);

  const handleLoadedMetadata = () => {
    if (videoRef.current) {
      const dur = videoRef.current.duration;
      setDuration(dur);
      setStartTime(0);
      setEndTime(dur);
      setStartTimeInput('00:00');
      setEndTimeInput(formatTimeStr(dur));
    }
  };

  const handleStartSliderChange = (e) => {
    const val = parseFloat(e.target.value) || 0;
    const boundedStart = Math.min(val, Math.max(0, endTime - 0.5));
    setStartTime(boundedStart);
    setStartTimeInput(formatTimeStr(boundedStart));
    if (videoRef.current) {
      videoRef.current.currentTime = boundedStart;
    }
  };

  const handleEndSliderChange = (e) => {
    const val = parseFloat(e.target.value) || 0;
    const maxDur = duration > 0 ? duration : val;
    const boundedEnd = Math.min(maxDur, Math.max(val, startTime + 0.5));
    setEndTime(boundedEnd);
    setEndTimeInput(formatTimeStr(boundedEnd));
    if (videoRef.current) {
      videoRef.current.currentTime = boundedEnd;
    }
  };

  const handleStartInputBlur = () => {
    const parsed = parseTimeStr(startTimeInput);
    const boundedStart = Math.min(parsed, Math.max(0, endTime - 0.5));
    setStartTime(boundedStart);
    setStartTimeInput(formatTimeStr(boundedStart));
    if (videoRef.current) {
      videoRef.current.currentTime = boundedStart;
    }
  };

  const handleEndInputBlur = () => {
    const parsed = parseTimeStr(endTimeInput);
    const boundedEnd = Math.min(duration > 0 ? duration : parsed, Math.max(parsed, startTime + 0.5));
    setEndTime(boundedEnd);
    setEndTimeInput(formatTimeStr(boundedEnd));
    if (videoRef.current) {
      videoRef.current.currentTime = boundedEnd;
    }
  };

  const handleSetCurrentAsStart = () => {
    if (videoRef.current) {
      const curr = Math.floor(videoRef.current.currentTime * 10) / 10;
      const boundedStart = Math.min(curr, Math.max(0, endTime - 0.5));
      setStartTime(boundedStart);
      setStartTimeInput(formatTimeStr(boundedStart));
    }
  };

  const handleSetCurrentAsEnd = () => {
    if (videoRef.current) {
      const curr = Math.floor(videoRef.current.currentTime * 10) / 10;
      const boundedEnd = Math.max(curr, startTime + 0.5);
      setEndTime(boundedEnd);
      setEndTimeInput(formatTimeStr(boundedEnd));
    }
  };

  const handleExecuteTrim = async () => {
    if (!selectedRelPath) return;

    const args = [selectedRelPath];
    if (startTime > 0) args.push('--start', startTime.toString());
    if (endTime > 0 && endTime < duration) args.push('--end', endTime.toString());
    if (isAccurate) args.push('--accurate');
    if (customOutput) args.push('--output', customOutput);
    if (isOverwriting) args.push('--overwrite');

    setIsProcessing(true);
    setProcessingRelPath(selectedRelPath);
    onSelectTab('logs');

    try {
      await runScript('trim.py', args, `trim_${Date.now()}`);
      // Wait 800ms for filesystem to flush the new file
      await new Promise(r => setTimeout(r, 800));
      if (onRefresh) onRefresh();
      // Re-suggest output name so next trim gets a fresh auto-increment
      if (!isOverwriting && selectedRelPath) {
        fetch('/api/suggest-trim-name', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ inputPath: selectedRelPath })
        })
          .then(r => r.json())
          .then(d => { if (d.success && d.suggestedPath) { setSuggestedOutput(d.suggestedPath); setCustomOutput(d.suggestedPath); } })
          .catch(() => {});
      }
    } catch (e) {
      console.error('Trim failed:', e);
    } finally {
      setIsProcessing(false);
      setProcessingRelPath(null);
    }
  };

  const videoUrl = selectedRelPath ? getMediaUrl(selectedRelPath) : '';
  const startPercent = duration > 0 ? (startTime / duration) * 100 : 0;
  const endPercent = duration > 0 ? (endTime / duration) * 100 : 100;
  const trimmedLength = Math.max(0, endTime - startTime);

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

        .dual-range-thumb {
          position: absolute;
          width: 100%;
          top: 6px;
          height: 24px;
          -webkit-appearance: none;
          appearance: none;
          background: none;
          pointer-events: none;
          margin: 0;
        }
        .dual-range-thumb::-webkit-slider-thumb {
          -webkit-appearance: none;
          pointer-events: auto;
          width: 20px;
          height: 20px;
          border-radius: 50%;
          background: #818cf8;
          border: 2px solid #ffffff;
          cursor: pointer;
          box-shadow: 0 0 8px rgba(0,0,0,0.6);
          transition: background-color 0.15s, transform 0.15s;
        }
        .dual-range-thumb::-webkit-slider-thumb:hover {
          background: #6366f1;
          transform: scale(1.2);
        }
        .dual-range-thumb::-moz-range-thumb {
          pointer-events: auto;
          width: 20px;
          height: 20px;
          border-radius: 50%;
          background: #818cf8;
          border: 2px solid #ffffff;
          cursor: pointer;
          box-shadow: 0 0 8px rgba(0,0,0,0.6);
        }
      `}</style>

      {!embedded && (
        <div style={styles.header}>
          <div>
            <h2 style={styles.title}>✂️ Công Cụ Cắt Video (Video Trimmer)</h2>
            <p style={styles.subtitle}>Tự động sinh tên không trùng (`_cut_1.mp4`), hỗ trợ kéo Timeline trực quan & gõ phút:giây linh hoạt</p>
          </div>
        </div>
      )}

      <div style={embeddedControlsOnly ? { width: '100%' } : styles.contentGrid}>
        {/* LEFT COLUMN: Video Library Compact Gallery (2-column Grid) */}
        {!embeddedControlsOnly && (
          <div style={styles.libraryCard}>
            <div style={{ display: 'flex', flexDirection: 'column', gap: 10, marginBottom: 12 }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                <h3 style={styles.cardTitle}>📁 Kho Video ({allFiles.length})</h3>
                <select
                  value={folderFilter}
                  onChange={e => setFolderFilter(e.target.value)}
                  style={styles.folderSelect}
                >
                  <option value="all">📁 Tất cả kho ({allFiles.length})</option>
                  <option value="src">📹 Thư mục Gốc (`src/` - {srcFiles.filter(f => f.isMedia).length})</option>
                  <option value="output">✅ Thư mục Kết quả (`output/` - {outputFiles.filter(f => f.isMedia).length})</option>
                </select>
              </div>

              <input
                type="text"
                value={searchQuery}
                onChange={e => setSearchQuery(e.target.value)}
                placeholder="🔍 Tìm nhanh tên video..."
                style={styles.searchInput}
              />
            </div>

            <div style={styles.compactGrid}>
              {allFiles
                .filter(f => {
                  if (folderFilter === 'src') return f.relPath.includes('/src/');
                  if (folderFilter === 'output') return f.relPath.includes('/output/');
                  return true;
                })
                .filter(f => {
                  if (!searchQuery.trim()) return true;
                  return f.name.toLowerCase().includes(searchQuery.toLowerCase()) || f.relPath.toLowerCase().includes(searchQuery.toLowerCase());
                })
                .slice(0, displayLimit)
                .map(f => (
                  <CompactVideoCard
                    key={f.relPath}
                    file={f}
                    isSelected={selectedRelPath === f.relPath}
                    isActivePreview={selectedRelPath === f.relPath}
                    disabled={isProcessing && processingRelPath === f.relPath}
                    onSelect={relPath => { if (!isProcessing) setSelectedRelPath(relPath); }}
                    actionLabel={isProcessing && processingRelPath === f.relPath ? '⚙️ Đang xử lý...' : 'Chọn video'}
                    onAction={relPath => { if (!isProcessing) setSelectedRelPath(relPath); }}
                  />
                ))}
            </div>

            {allFiles.length > displayLimit && (
              <button
                style={styles.loadMoreBtn}
                onClick={() => setDisplayLimit(prev => prev + 24)}
              >
                Hiển thị thêm... ({Math.min(displayLimit, allFiles.length)}/{allFiles.length})
              </button>
            )}
          </div>
        )}

        {/* RIGHT COLUMN: Main Workspace (Player & Timeline on top, Controls form below) */}
        <div style={styles.mainWorkPanel}>
          {/* Top: Video Player & Timeline */}
          <div style={styles.playerCard}>

            {videoUrl ? (
              <video
                ref={videoRef}
                src={videoUrl}
                controls
                onLoadedMetadata={handleLoadedMetadata}
                style={styles.videoPlayer}
              />
            ) : (
              <div style={styles.noVideo}>Vui lòng chọn 1 video để xem trước</div>
            )}

            {/* 🎛️ Dual-Handle Interactive Timeline Track */}
            {duration > 0 && (
              <div style={styles.timelineBox}>
                <div style={styles.timelineHeader}>
                  <span style={styles.timelineBadge}>⏱️ Khung Cắt Chọn: {formatTimeStr(startTime)} ➔ {formatTimeStr(endTime)}</span>
                  <span style={{ fontSize: 12, color: '#94a3b8' }}>Tổng thời lượng: {formatTimeStr(duration)} ({duration.toFixed(1)}s)</span>
                </div>

                <div style={styles.rangeSliderContainer}>
                  {/* Highlight Track Bar */}
                  <div style={styles.trackBackground} />
                  <div
                    style={{
                      ...styles.trackHighlight,
                      left: `${startPercent}%`,
                      width: `${Math.max(0, endPercent - startPercent)}%`
                    }}
                  />

                  {/* Range Input for Start */}
                  <input
                    type="range"
                    className="dual-range-thumb"
                    min="0"
                    max={duration}
                    step="0.1"
                    value={startTime}
                    onChange={handleStartSliderChange}
                    onMouseDown={() => setActiveThumb('start')}
                    onTouchStart={() => setActiveThumb('start')}
                    style={{ zIndex: activeThumb === 'start' ? 5 : 3 }}
                  />

                  {/* Range Input for End */}
                  <input
                    type="range"
                    className="dual-range-thumb"
                    min="0"
                    max={duration}
                    step="0.1"
                    value={endTime}
                    onChange={handleEndSliderChange}
                    onMouseDown={() => setActiveThumb('end')}
                    onTouchStart={() => setActiveThumb('end')}
                    style={{ zIndex: activeThumb === 'end' ? 5 : 3 }}
                  />
                </div>

                <div style={styles.seekBtnRow}>
                  <button style={styles.btnSetTime} onClick={handleSetCurrentAsStart}>
                    📍 Đặt Vị Trí Đầu Ví Dụ (`Start` = {formatTimeStr(startTime)})
                  </button>
                  <button style={styles.btnSetTime} onClick={handleSetCurrentAsEnd}>
                    📍 Đặt Vị Trí Cuối Ví Dụ (`End` = {formatTimeStr(endTime)})
                  </button>
                </div>
              </div>
            )}
          </div>

          {/* Bottom: Controls Form */}
          <div style={styles.controlsCard}>
            <h3 style={styles.cardTitle}>⚙️ Cấu Hình Khoảng Thời Gian & File Đầu Ra</h3>

            {/* Start Time Input */}
            <div style={styles.formGroup}>
              <label style={styles.label}>Bắt Đầu Cắt (`--start`):</label>
              <div style={styles.inputGroup}>
                <input
                  type="text"
                  value={startTimeInput}
                  onChange={e => setStartTimeInput(e.target.value)}
                  onBlur={handleStartInputBlur}
                  placeholder="00:00 hoặc số giây"
                  style={styles.textInput}
                />
                <span style={styles.unit}>({startTime.toFixed(1)}s)</span>
              </div>
              <span style={styles.hint}>Nhập dạng `mm:ss` (Ví dụ: `01:30`) hoặc số giây (`90`)</span>
            </div>

            {/* End Time Input */}
            <div style={styles.formGroup}>
              <label style={styles.label}>Kết Thúc Cắt (`--end`):</label>
              <div style={styles.inputGroup}>
                <input
                  type="text"
                  value={endTimeInput}
                  onChange={e => setEndTimeInput(e.target.value)}
                  onBlur={handleEndInputBlur}
                  placeholder="00:00 hoặc số giây"
                  style={styles.textInput}
                />
                <span style={styles.unit}>({endTime.toFixed(1)}s)</span>
              </div>
              <span style={styles.hint}>Nhập dạng `mm:ss` hoặc số giây (Tổng gốc: {duration.toFixed(1)}s)</span>
            </div>

            {/* Output Filename Input */}
            <div style={styles.formGroup}>
              <label style={styles.label}>Đường Dẫn & Tên File Đầu Ra (`--output`):</label>
              <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
                <input
                  type="text"
                  value={customOutput}
                  onChange={e => setCustomOutput(e.target.value)}
                  placeholder="assets/project/src/video_cut_1.mp4"
                  style={{ ...styles.textInput, flex: 1, borderColor: '#6366f1' }}
                />
              </div>
              <span style={{ fontSize: 11, color: '#a5b4fc', marginTop: 4, display: 'flex', alignItems: 'center', gap: 4 }}>
                <Sparkles size={12} /> Tự động gợi ý tên không trùng tăng dần (`_cut_1.mp4`, `_cut_2.mp4`...)
              </span>
            </div>

            <div style={styles.infoBox}>
              <span style={{ color: '#10b981', fontWeight: 'bold' }}>
                ⏱️ Thời lượng video xuất ra: {formatTimeStr(trimmedLength)} ({trimmedLength.toFixed(1)}s)
              </span>
            </div>

            <div style={styles.checkboxGroup}>
              <label style={styles.checkboxLabel}>
                <input
                  type="checkbox"
                  checked={isAccurate}
                  onChange={e => setIsAccurate(e.target.checked)}
                />
                <span>Re-encode chính xác từng frame (`--accurate`)</span>
              </label>
              <p style={styles.hint}>Tắt = dùng FFmpeg Stream Copy siêu nhanh &lt;1s</p>
            </div>

            <div style={styles.checkboxGroup}>
              <label style={styles.checkboxLabel}>
                <input
                  type="checkbox"
                  checked={isOverwriting}
                  onChange={e => setIsOverwriting(e.target.checked)}
                />
                <span>Cho phép ghi đè file (`--overwrite`)</span>
              </label>
            </div>

            <button
              style={styles.btnTrimExecute}
              onClick={handleExecuteTrim}
              disabled={isProcessing || !selectedRelPath}
            >
              <Scissors size={18} style={{ marginRight: 8 }} />
              {isProcessing ? 'Đang Xử Lý Cắt...' : 'Bắt Đầu Cắt Video'}
            </button>
          </div>
        </div>
      </div>
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
  contentGrid: {
    display: 'grid',
    gridTemplateColumns: '1fr 1fr',
    gap: 20,
    alignItems: 'start'
  },
  mainWorkPanel: {
    display: 'flex',
    flexDirection: 'column',
    gap: 20
  },
  libraryCard: {
    backgroundColor: '#1e293b',
    borderRadius: 12,
    padding: 16,
    border: '1px solid #334155',
    display: 'flex',
    flexDirection: 'column'
  },
  compactGrid: {
    display: 'grid',
    gridTemplateColumns: 'repeat(2, minmax(0, 1fr))',
    gap: 10,
    maxHeight: 'calc(100vh - 280px)',
    overflowY: 'auto',
    paddingRight: 4
  },
  folderSelect: {
    backgroundColor: '#0f172a',
    color: '#f8fafc',
    border: '1px solid #6366f1',
    borderRadius: 6,
    padding: '4px 8px',
    fontSize: 11,
    fontWeight: 'bold',
    outline: 'none',
    cursor: 'pointer'
  },
  searchInput: {
    backgroundColor: '#0f172a',
    color: '#f8fafc',
    border: '1px solid #475569',
    borderRadius: 6,
    padding: '6px 10px',
    fontSize: 12,
    outline: 'none',
    width: '100%',
    boxSizing: 'border-box'
  },
  loadMoreBtn: {
    backgroundColor: '#334155',
    color: '#e2e8f0',
    border: 'none',
    borderRadius: 6,
    padding: '6px 10px',
    fontSize: 11,
    fontWeight: 'bold',
    cursor: 'pointer',
    marginTop: 10,
    alignSelf: 'center'
  },
  cardTitle: {
    fontSize: 15,
    fontWeight: 'bold',
    margin: 0,
    color: '#f8fafc'
  },
  playerCard: {
    backgroundColor: '#1e293b',
    borderRadius: 12,
    padding: 16,
    border: '1px solid #334155',
    display: 'flex',
    flexDirection: 'column',
    gap: 16
  },
  controlsCard: {
    backgroundColor: '#1e293b',
    borderRadius: 12,
    padding: 20,
    border: '1px solid #334155',
    display: 'flex',
    flexDirection: 'column',
    gap: 16
  },
  selectRow: {
    display: 'flex',
    flexDirection: 'column',
    gap: 6
  },
  label: {
    fontSize: 13,
    fontWeight: 'bold',
    color: '#cbd5e1'
  },
  select: {
    backgroundColor: '#0f172a',
    color: '#f8fafc',
    border: '1px solid #475569',
    borderRadius: 8,
    padding: '8px 12px',
    fontSize: 14,
    outline: 'none'
  },
  videoPlayer: {
    width: '100%',
    maxHeight: 380,
    borderRadius: 8,
    backgroundColor: '#000'
  },
  noVideo: {
    height: 240,
    backgroundColor: '#0f172a',
    borderRadius: 8,
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    color: '#64748b',
    fontSize: 14
  },
  timelineBox: {
    backgroundColor: '#0f172a',
    padding: 14,
    borderRadius: 10,
    border: '1px solid #334155',
    display: 'flex',
    flexDirection: 'column',
    gap: 12
  },
  timelineHeader: {
    display: 'flex',
    justifyContent: 'space-between',
    alignItems: 'center'
  },
  timelineBadge: {
    fontSize: 13,
    fontWeight: 'bold',
    color: '#818cf8'
  },
  rangeSliderContainer: {
    position: 'relative',
    height: 36,
    display: 'flex',
    alignItems: 'center'
  },
  trackBackground: {
    position: 'absolute',
    width: '100%',
    height: 8,
    backgroundColor: '#334155',
    borderRadius: 4,
    top: 14
  },
  trackHighlight: {
    position: 'absolute',
    height: 8,
    backgroundColor: '#6366f1',
    borderRadius: 4,
    top: 14,
    zIndex: 2
  },
  rangeInput: {
    position: 'absolute',
    width: '100%',
    top: 6,
    height: 24,
    WebkitAppearance: 'none',
    appearance: 'none',
    background: 'none',
    pointerEvents: 'auto',
    cursor: 'pointer'
  },
  seekBtnRow: {
    display: 'flex',
    gap: 10
  },
  btnSetTime: {
    flex: 1,
    backgroundColor: '#334155',
    color: '#e2e8f0',
    border: 'none',
    borderRadius: 6,
    padding: '8px 10px',
    fontSize: 12,
    cursor: 'pointer',
    textAlign: 'center'
  },
  cardTitle: {
    fontSize: 16,
    fontWeight: 'bold',
    margin: 0,
    color: '#f8fafc'
  },
  formGroup: {
    display: 'flex',
    flexDirection: 'column',
    gap: 6
  },
  inputGroup: {
    display: 'flex',
    alignItems: 'center',
    gap: 10
  },
  textInput: {
    backgroundColor: '#0f172a',
    color: '#f8fafc',
    border: '1px solid #475569',
    borderRadius: 8,
    padding: '8px 12px',
    fontSize: 14,
    outline: 'none',
    width: '100%',
    boxSizing: 'border-box'
  },
  unit: {
    fontSize: 12,
    color: '#94a3b8',
    whiteSpace: 'nowrap'
  },
  hint: {
    fontSize: 11,
    color: '#64748b',
    margin: 0
  },
  infoBox: {
    backgroundColor: 'rgba(16, 185, 129, 0.1)',
    border: '1px solid rgba(16, 185, 129, 0.3)',
    borderRadius: 8,
    padding: '10px 14px',
    fontSize: 13
  },
  checkboxGroup: {
    display: 'flex',
    flexDirection: 'column',
    gap: 4
  },
  checkboxLabel: {
    fontSize: 13,
    color: '#e2e8f0',
    display: 'flex',
    alignItems: 'center',
    gap: 8,
    cursor: 'pointer'
  },
  btnTrimExecute: {
    backgroundColor: '#6366f1',
    color: '#ffffff',
    border: 'none',
    borderRadius: 8,
    padding: '12px 16px',
    fontSize: 15,
    fontWeight: 'bold',
    cursor: 'pointer',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    marginTop: 8,
    transition: 'background-color 0.2s'
  }
};
