import React, { useState, useRef, useEffect } from 'react';
import { 
  Scissors, 
  Trash2, 
  ZoomIn, 
  ZoomOut, 
  Clock, 
  Film
} from 'lucide-react';

const formatTimecodeMs = (sec) => {
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

const parseTimecodeMs = (str) => {
  if (!str) return 0;
  const s = str.trim();
  if (s.includes(':')) {
    const parts = s.split(':');
    if (parts.length === 3) {
      const h = parseFloat(parts[0]) || 0;
      const m = parseFloat(parts[1]) || 0;
      const sec = parseFloat(parts[2]) || 0;
      return h * 3600 + m * 60 + sec;
    }
    if (parts.length === 2) {
      const m = parseFloat(parts[0]) || 0;
      const sec = parseFloat(parts[1]) || 0;
      return m * 60 + sec;
    }
  }
  const f = parseFloat(s);
  return isNaN(f) ? 0 : Math.max(0, f);
};

const formatRulerLabel = (sec) => {
  const hrs = Math.floor(sec / 3600);
  const mins = Math.floor((sec % 3600) / 60);
  const secs = Math.floor(sec % 60);
  if (hrs > 0) {
    return `${hrs.toString().padStart(2, '0')}:${mins.toString().padStart(2, '0')}:${secs.toString().padStart(2, '0')}`;
  }
  return `00:${mins.toString().padStart(2, '0')}:${secs.toString().padStart(2, '0')}`;
};

export default function InteractiveTimeline({
  duration = 105,
  currentTime = 12,
  startTime = 5,
  endTime = 15,
  onRangeChange,
  onSeek,
  onCutTrim,
  cutMode = 'remove', // 'remove' | 'keep'
  onToggleCutMode,
  isAccurateCut = false,
  onToggleAccurateCut,
  isProcessing = false
}) {
  const trackRef = useRef(null);
  const [zoomLevel, setZoomLevel] = useState(1);
  const [isDraggingHandle, setIsDraggingHandle] = useState(null); // 'start' | 'end' | 'playhead'

  const [startInputVal, setStartInputVal] = useState(formatTimecodeMs(startTime));
  const [endInputVal, setEndInputVal] = useState(formatTimecodeMs(endTime));

  const effectiveDuration = duration > 0 ? duration : 100;
  const startRatio = Math.max(0, Math.min(1, startTime / effectiveDuration));
  const endRatio = Math.max(0, Math.min(1, endTime / effectiveDuration));
  const playheadRatio = Math.max(0, Math.min(1, currentTime / effectiveDuration));

  // Sync inputs when external startTime / endTime changes
  useEffect(() => {
    setStartInputVal(formatTimecodeMs(startTime));
  }, [startTime]);

  useEffect(() => {
    setEndInputVal(formatTimecodeMs(endTime));
  }, [endTime]);

  // Generate ruler markers
  const markerStep = effectiveDuration > 300 ? 60 : effectiveDuration > 60 ? 15 : 5;
  const markers = [];
  for (let s = 0; s <= effectiveDuration; s += markerStep) {
    markers.push({
      time: s,
      ratio: s / effectiveDuration,
      label: formatRulerLabel(s)
    });
  }

  // Handle Drag on Track
  const handleMouseDown = (type, e) => {
    e.stopPropagation();
    setIsDraggingHandle(type);
  };

  useEffect(() => {
    const handleMouseMove = (e) => {
      if (!isDraggingHandle || !trackRef.current) return;
      const rect = trackRef.current.getBoundingClientRect();
      const clickX = e.clientX - rect.left;
      const ratio = Math.max(0, Math.min(1, clickX / rect.width));
      const targetSec = Math.round(ratio * effectiveDuration * 1000) / 1000;

      if (isDraggingHandle === 'start') {
        const newStart = Math.min(targetSec, endTime - 0.05);
        if (onRangeChange) onRangeChange(newStart, endTime);
      } else if (isDraggingHandle === 'end') {
        const newEnd = Math.max(targetSec, startTime + 0.05);
        if (onRangeChange) onRangeChange(startTime, newEnd);
      } else if (isDraggingHandle === 'playhead') {
        if (onSeek) onSeek(targetSec);
      }
    };

    const handleMouseUp = () => {
      if (isDraggingHandle) setIsDraggingHandle(null);
    };

    if (isDraggingHandle) {
      window.addEventListener('mousemove', handleMouseMove);
      window.addEventListener('mouseup', handleMouseUp);
    }
    return () => {
      window.removeEventListener('mousemove', handleMouseMove);
      window.removeEventListener('mouseup', handleMouseUp);
    };
  }, [isDraggingHandle, effectiveDuration, startTime, endTime, onRangeChange, onSeek]);

  const handleTrackClick = (e) => {
    if (!trackRef.current || isDraggingHandle) return;
    const rect = trackRef.current.getBoundingClientRect();
    const clickX = e.clientX - rect.left;
    const ratio = Math.max(0, Math.min(1, clickX / rect.width));
    const targetSec = Math.round(ratio * effectiveDuration * 1000) / 1000;
    if (onSeek) onSeek(targetSec);
  };

  const handleStartInputBlur = () => {
    const parsed = parseTimecodeMs(startInputVal);
    const valid = Math.max(0, Math.min(parsed, endTime - 0.05));
    if (onRangeChange) onRangeChange(valid, endTime);
    setStartInputVal(formatTimecodeMs(valid));
  };

  const handleEndInputBlur = () => {
    const parsed = parseTimecodeMs(endInputVal);
    const valid = Math.max(startTime + 0.05, Math.min(parsed, effectiveDuration));
    if (onRangeChange) onRangeChange(startTime, valid);
    setEndInputVal(formatTimecodeMs(valid));
  };

  const isRemoveMode = cutMode === 'remove';

  return (
    <div style={styles.timelineContainer}>
      {/* Top Toolbar */}
      <div style={styles.toolbar}>
        {/* Left: Cut Action & Mode Toggle */}
        <div style={styles.toolGroup}>
          {/* Main Action Button */}
          <button 
            style={{
              ...styles.toolBtn,
              ...(isRemoveMode ? styles.removeCutBtn : styles.keepCutBtn)
            }}
            onClick={onCutTrim}
            disabled={isProcessing}
            title={isRemoveMode ? 'Cắt loại bỏ đoạn rác và ghi đè trực tiếp lên file video gốc' : 'Cắt trích xuất đoạn đã chọn thành 1 file video mới'}
          >
            {isRemoveMode ? <Trash2 size={14} /> : <Scissors size={14} />}
            <span>
              {isRemoveMode ? '🗑️ Cắt Bỏ Rác (Ghi Đè Gốc)' : '✂️ Trimmer Clip Mới'}
            </span>
          </button>

          {/* Mode Switcher Toggle */}
          <div style={styles.modeSwitchGroup}>
            <button
              style={{
                ...styles.modeToggleBtn,
                ...(isRemoveMode ? styles.modeToggleActiveRemove : {})
              }}
              onClick={() => onToggleCutMode && onToggleCutMode('remove')}
              title="Cắt bỏ đoạn rác và ghi đè trực tiếp lên file gốc (không tạo file mới)"
            >
              Cắt bỏ rác
            </button>
            <button
              style={{
                ...styles.modeToggleBtn,
                ...(!isRemoveMode ? styles.modeToggleActiveKeep : {})
              }}
              onClick={() => onToggleCutMode && onToggleCutMode('keep')}
              title="Trimmer: Cắt trích xuất đoạn chọn thành file mới (_cut_1.mp4)"
            >
              Trimmer
            </button>
          </div>

          {/* Speed / Accurate Toggle */}
          <div style={styles.modeSwitchGroup} title="Chế độ xử lý cắt: Siêu Tốc Stream Copy (<0.3s) hoặc Frame-Accurate Re-encode (~1s)">
            <button
              style={{
                ...styles.modeToggleBtn,
                ...(!isAccurateCut ? styles.modeToggleActiveSpeed : {})
              }}
              onClick={() => onToggleAccurateCut && onToggleAccurateCut(false)}
              title="Cắt siêu tốc bằng Stream Copy (<0.3s, Lossless 100% chất lượng)"
            >
              ⚡ Siêu Tốc (~0.3s)
            </button>
            <button
              style={{
                ...styles.modeToggleBtn,
                ...(isAccurateCut ? styles.modeToggleActiveAccurate : {})
              }}
              onClick={() => onToggleAccurateCut && onToggleAccurateCut(true)}
              title="Re-encode phần cứng VideoToolbox chính xác từng frame (~1s)"
            >
              🎯 Chuẩn Frame (~1s)
            </button>
          </div>

          {/* Precision Time Range Inputs with ms precision */}
          <div style={styles.rangeDisplay} title="Nhập mốc thời gian chính xác đến từng millisecond (hh:mm:ss.ms)">
            <span style={{ fontSize: 10, color: 'var(--text-dim)' }}>Từ:</span>
            <input
              type="text"
              value={startInputVal}
              onChange={e => setStartInputVal(e.target.value)}
              onBlur={handleStartInputBlur}
              onKeyDown={e => e.key === 'Enter' && handleStartInputBlur()}
              style={styles.timecodeMsInput}
            />
            <span style={{ color: 'var(--text-dim)' }}>—</span>
            <span style={{ fontSize: 10, color: 'var(--text-dim)' }}>Đến:</span>
            <input
              type="text"
              value={endInputVal}
              onChange={e => setEndInputVal(e.target.value)}
              onBlur={handleEndInputBlur}
              onKeyDown={e => e.key === 'Enter' && handleEndInputBlur()}
              style={styles.timecodeMsInput}
            />
          </div>
        </div>

        {/* Right: Zoom Slider */}
        <div style={styles.toolGroup}>
          <div style={styles.zoomGroup} title="Phóng to / Thu nhỏ timeline">
            <ZoomOut size={13} color="var(--text-dim)" />
            <input
              type="range"
              min="1"
              max="3"
              step="0.1"
              value={zoomLevel}
              onChange={(e) => setZoomLevel(parseFloat(e.target.value))}
              style={styles.zoomSlider}
            />
            <ZoomIn size={13} color="var(--text-dim)" />
          </div>
        </div>
      </div>

      {/* ── Visual Filmstrip Track ────────────────────────────────────────── */}
      <div style={styles.trackContainer} ref={trackRef} onClick={handleTrackClick}>
        {/* Ruler Time Markers */}
        <div style={styles.ruler}>
          {markers.map((m, idx) => (
            <div 
              key={idx} 
              style={{
                ...styles.markerItem,
                left: `${m.ratio * 100}%`
              }}
            >
              <div style={styles.markerTick} />
              <span style={styles.markerText}>{m.label}</span>
            </div>
          ))}
        </div>

        {/* Filmstrip Visual Track Strip */}
        <div style={styles.filmstripTrack}>
          <div style={styles.filmstripPattern} />

          {/* Active Range Selection Box */}
          <div 
            style={{
              ...styles.selectionBox,
              left: `${startRatio * 100}%`,
              width: `${(endRatio - startRatio) * 100}%`,
              backgroundColor: isRemoveMode ? 'rgba(239, 68, 68, 0.28)' : 'rgba(59, 130, 246, 0.22)',
              borderColor: isRemoveMode ? 'var(--accent-red)' : 'var(--primary)'
            }}
          >
            {/* Label inside selected range */}
            <div style={{
              ...styles.rangeLabelInside,
              color: isRemoveMode ? '#fca5a5' : '#93c5fd'
            }}>
              {isRemoveMode ? '🗑️ ĐOẠN RÁC SẼ BỊ CẮT BỎ' : '✂️ ĐOẠN ĐƯỢC GIỮ LẠI'}
            </div>

            {/* Left Handle */}
            <div 
              style={{
                ...styles.handleLeft,
                backgroundColor: isRemoveMode ? 'var(--accent-red)' : 'var(--primary)'
              }}
              onMouseDown={(e) => handleMouseDown('start', e)}
              title="Kéo chỉnh điểm bắt đầu"
            >
              <div style={styles.handleGrip} />
            </div>

            {/* Right Handle */}
            <div 
              style={{
                ...styles.handleRight,
                backgroundColor: isRemoveMode ? 'var(--accent-red)' : 'var(--primary)'
              }}
              onMouseDown={(e) => handleMouseDown('end', e)}
              title="Kéo chỉnh điểm kết thúc"
            >
              <div style={styles.handleGrip} />
            </div>
          </div>

          {/* Playhead White Scrubber Line */}
          <div 
            style={{
              ...styles.playheadLine,
              left: `${playheadRatio * 100}%`
            }}
            onMouseDown={(e) => handleMouseDown('playhead', e)}
          >
            <div style={styles.playheadHead} />
          </div>
        </div>
      </div>
    </div>
  );
}

const styles = {
  timelineContainer: {
    backgroundColor: 'var(--bg-card)',
    borderRadius: 'var(--radius-md)',
    border: '1px solid var(--border-color)',
    padding: '10px 14px',
    display: 'flex',
    flexDirection: 'column',
    gap: 8,
    boxShadow: 'var(--shadow-sm)',
    userSelect: 'none',
  },
  toolbar: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: 12,
    flexWrap: 'wrap',
  },
  toolGroup: {
    display: 'flex',
    alignItems: 'center',
    gap: 8,
  },
  toolBtn: {
    display: 'flex',
    alignItems: 'center',
    gap: 6,
    padding: '5px 12px',
    borderRadius: 'var(--radius-sm)',
    fontSize: 12,
    fontWeight: 600,
    border: '1px solid transparent',
  },
  removeCutBtn: {
    backgroundColor: 'rgba(239, 68, 68, 0.18)',
    color: '#f87171',
    borderColor: 'rgba(239, 68, 68, 0.5)',
    boxShadow: '0 2px 6px rgba(239, 68, 68, 0.2)',
  },
  keepCutBtn: {
    backgroundColor: 'rgba(59, 130, 246, 0.18)',
    color: 'var(--primary-light)',
    borderColor: 'rgba(59, 130, 246, 0.5)',
  },
  modeSwitchGroup: {
    display: 'flex',
    backgroundColor: 'var(--bg-input)',
    borderRadius: 'var(--radius-sm)',
    border: '1px solid var(--border-color)',
    padding: 2,
    gap: 2,
  },
  modeToggleBtn: {
    padding: '3px 8px',
    fontSize: 11,
    fontWeight: 500,
    backgroundColor: 'transparent',
    color: 'var(--text-dim)',
    borderRadius: 4,
    border: 'none',
    cursor: 'pointer',
  },
  modeToggleActiveRemove: {
    backgroundColor: 'rgba(239, 68, 68, 0.2)',
    color: '#f87171',
    fontWeight: 700,
  },
  modeToggleActiveKeep: {
    backgroundColor: 'rgba(59, 130, 246, 0.2)',
    color: 'var(--primary-light)',
    fontWeight: 700,
  },
  modeToggleActiveSpeed: {
    backgroundColor: 'rgba(16, 185, 129, 0.22)',
    color: '#34d399',
    fontWeight: 700,
  },
  modeToggleActiveAccurate: {
    backgroundColor: 'rgba(168, 85, 247, 0.22)',
    color: '#c084fc',
    fontWeight: 700,
  },
  rangeDisplay: {
    display: 'flex',
    alignItems: 'center',
    gap: 4,
    padding: '3px 8px',
    backgroundColor: 'var(--bg-input)',
    borderRadius: 'var(--radius-sm)',
    border: '1px solid var(--border-color)',
  },
  timecodeMsInput: {
    width: 105,
    padding: '2px 4px',
    fontSize: 11,
    fontFamily: 'monospace',
    fontWeight: 600,
    color: 'var(--primary-light)',
    background: 'transparent',
    border: 'none',
    textAlign: 'center',
    outline: 'none',
  },
  zoomGroup: {
    display: 'flex',
    alignItems: 'center',
    gap: 6,
  },
  zoomSlider: {
    width: 65,
    height: 3,
    accentColor: 'var(--primary)',
    cursor: 'pointer',
  },
  trackContainer: {
    position: 'relative',
    height: '64px',
    display: 'flex',
    flexDirection: 'column',
    cursor: 'crosshair',
  },
  ruler: {
    height: '18px',
    position: 'relative',
    borderBottom: '1px solid rgba(255, 255, 255, 0.08)',
  },
  markerItem: {
    position: 'absolute',
    transform: 'translateX(-50%)',
    display: 'flex',
    flexDirection: 'column',
    alignItems: 'center',
  },
  markerTick: {
    width: 1,
    height: 4,
    backgroundColor: 'var(--text-dim)',
  },
  markerText: {
    fontSize: 9,
    color: 'var(--text-dim)',
    fontFamily: 'monospace',
    marginTop: 1,
  },
  filmstripTrack: {
    flex: 1,
    position: 'relative',
    borderRadius: 'var(--radius-sm)',
    overflow: 'hidden',
    backgroundColor: 'var(--bg-input)',
    border: '1px solid var(--border-color)',
    marginTop: 2,
  },
  filmstripPattern: {
    position: 'absolute',
    top: 0,
    left: 0,
    right: 0,
    bottom: 0,
    backgroundImage: 'linear-gradient(90deg, rgba(255,255,255,0.03) 1px, transparent 1px)',
    backgroundSize: '24px 100%',
  },
  selectionBox: {
    position: 'absolute',
    top: 0,
    bottom: 0,
    borderTop: '2px solid',
    borderBottom: '2px solid',
    zIndex: 5,
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
  },
  rangeLabelInside: {
    fontSize: 10,
    fontWeight: 700,
    letterSpacing: '0.4px',
    pointerEvents: 'none',
    textAlign: 'center',
    whiteSpace: 'nowrap',
    overflow: 'hidden',
    textOverflow: 'ellipsis',
    padding: '0 12px',
  },
  handleLeft: {
    position: 'absolute',
    top: 0,
    bottom: 0,
    left: 0,
    width: 10,
    borderTopLeftRadius: 4,
    borderBottomLeftRadius: 4,
    cursor: 'ew-resize',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    zIndex: 10,
  },
  handleRight: {
    position: 'absolute',
    top: 0,
    bottom: 0,
    right: 0,
    width: 10,
    borderTopRightRadius: 4,
    borderBottomRightRadius: 4,
    cursor: 'ew-resize',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    zIndex: 10,
  },
  handleGrip: {
    width: 2,
    height: 14,
    backgroundColor: '#ffffff',
    borderRadius: 1,
  },
  playheadLine: {
    position: 'absolute',
    top: -18,
    bottom: 0,
    width: 2,
    backgroundColor: '#ffffff',
    zIndex: 20,
    transform: 'translateX(-50%)',
    cursor: 'ew-resize',
    boxShadow: '0 0 6px rgba(255, 255, 255, 0.8)',
  },
  playheadHead: {
    width: 10,
    height: 10,
    backgroundColor: '#ffffff',
    borderRadius: '2px',
    position: 'absolute',
    top: 0,
    left: '50%',
    transform: 'translateX(-50%) rotate(45deg)',
  }
};
