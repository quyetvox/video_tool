import React, { useState, useRef, useEffect } from 'react';
import { Scissors, Play, CheckCircle2, AlertCircle, RefreshCw } from 'lucide-react';
import { getMediaUrl, runScript } from '../services/api';

export default function VideoTrimmer({ 
  initialVideoPath, 
  project, 
  srcFiles = [], 
  outputFiles = [],
  onSelectTab,
  onRefresh
}) {
  const allFiles = [...srcFiles, ...outputFiles].filter(f => f.isMedia);
  const [selectedRelPath, setSelectedRelPath] = useState(initialVideoPath || (allFiles[0]?.relPath || ''));
  const [startTime, setStartTime] = useState(0);
  const [endTime, setEndTime] = useState(0);
  const [duration, setDuration] = useState(0);
  const [isAccurate, setIsAccurate] = useState(false);
  const [isOverwriting, setIsOverwriting] = useState(false); // Default false: do not overwrite
  const [isProcessing, setIsProcessing] = useState(false);

  const videoRef = useRef(null);

  useEffect(() => {
    if (initialVideoPath) {
      setSelectedRelPath(initialVideoPath);
    } else if (allFiles.length > 0 && !selectedRelPath) {
      setSelectedRelPath(allFiles[0].relPath);
    }
  }, [initialVideoPath, allFiles]);

  const handleLoadedMetadata = () => {
    if (videoRef.current) {
      const dur = videoRef.current.duration;
      setDuration(dur);
      setStartTime(0);
      setEndTime(Math.floor(dur));
    }
  };

  const handleSetCurrentAsStart = () => {
    if (videoRef.current) {
      const curr = Math.floor(videoRef.current.currentTime * 10) / 10;
      setStartTime(curr);
    }
  };

  const handleSetCurrentAsEnd = () => {
    if (videoRef.current) {
      const curr = Math.floor(videoRef.current.currentTime * 10) / 10;
      setEndTime(curr);
    }
  };

  const handleExecuteTrim = async () => {
    if (!selectedRelPath) return;

    const args = [selectedRelPath];
    if (startTime > 0) args.push('--start', startTime.toString());
    if (endTime > 0 && endTime < duration) args.push('--end', endTime.toString());
    if (isAccurate) args.push('--accurate');
    if (isOverwriting) args.push('--overwrite');

    setIsProcessing(true);
    onSelectTab('logs');

    try {
      await runScript('trim.py', args, `trim_${Date.now()}`);
      if (onRefresh) onRefresh();
    } catch (e) {
      console.error('Trim failed:', e);
    } finally {
      setIsProcessing(false);
    }
  };

  const videoUrl = selectedRelPath ? getMediaUrl(selectedRelPath) : '';

  return (
    <div style={styles.container}>
      <div style={styles.header}>
        <div>
          <h2 style={styles.title}>✂️ Công Cụ Cắt Video (Video Trimmer)</h2>
          <p style={styles.subtitle}>Cắt khoảng thời gian video (Hỗ trợ cả video gốc `src/` và video kết quả `output/`)</p>
        </div>
      </div>

      <div style={styles.contentGrid}>
        {/* Left: Video Player */}
        <div style={styles.playerCard}>
          <div style={styles.selectRow}>
            <label style={styles.label}>Chọn Video Cần Cắt:</label>
            <select
              value={selectedRelPath}
              onChange={e => setSelectedRelPath(e.target.value)}
              style={styles.select}
            >
              {allFiles.map(f => (
                <option key={f.relPath} value={f.relPath}>
                  {f.relPath.includes('/output/') ? '✅ [Output] ' : '📹 [Src] '}{f.name}
                </option>
              ))}
            </select>
          </div>

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

          <div style={styles.seekBtnRow}>
            <button style={styles.btnSetTime} onClick={handleSetCurrentAsStart}>
              📍 Đặt vị trí hiện tại làm `Start` ({startTime}s)
            </button>
            <button style={styles.btnSetTime} onClick={handleSetCurrentAsEnd}>
              📍 Đặt vị trí hiện tại làm `End` ({endTime}s)
            </button>
          </div>
        </div>

        {/* Right: Controls Form */}
        <div style={styles.controlsCard}>
          <h3 style={styles.cardTitle}>Cấu Hình Tham Số Cắt</h3>

          <div style={styles.formGroup}>
            <label style={styles.label}>Giây Bắt Đầu (`--start`):</label>
            <div style={styles.inputGroup}>
              <input
                type="number"
                step="0.1"
                min="0"
                max={endTime}
                value={startTime}
                onChange={e => setStartTime(parseFloat(e.target.value) || 0)}
                style={styles.numberInput}
              />
              <span style={styles.unit}>giây</span>
            </div>
          </div>

          <div style={styles.formGroup}>
            <label style={styles.label}>Giây Kết Thúc (`--end`):</label>
            <div style={styles.inputGroup}>
              <input
                type="number"
                step="0.1"
                min={startTime}
                max={duration}
                value={endTime}
                onChange={e => setEndTime(parseFloat(e.target.value) || 0)}
                style={styles.numberInput}
              />
              <span style={styles.unit}>giây (Tổng gốc: {duration.toFixed(1)}s)</span>
            </div>
          </div>

          <div style={styles.infoBox}>
            <span style={{ color: '#10b981', fontWeight: 'bold' }}>
              ⏱️ Thời lượng sau cắt: {Math.max(0, endTime - startTime).toFixed(1)} giây
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
    gridTemplateColumns: '1.2fr 1fr',
    gap: 20
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
  select: {
    padding: '8px 12px',
    borderRadius: 8,
    backgroundColor: '#0f172a',
    color: '#f8fafc',
    border: '1px solid #334155',
    fontSize: 13
  },
  videoPlayer: {
    width: '100%',
    maxHeight: 380,
    borderRadius: 8,
    backgroundColor: '#000'
  },
  noVideo: {
    height: 260,
    backgroundColor: '#0f172a',
    borderRadius: 8,
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    color: '#64748b'
  },
  seekBtnRow: {
    display: 'flex',
    gap: 10
  },
  btnSetTime: {
    flex: 1,
    padding: '8px 12px',
    borderRadius: 6,
    backgroundColor: '#334155',
    color: '#cbd5e1',
    border: 'none',
    fontSize: 12,
    cursor: 'pointer'
  },
  cardTitle: {
    fontSize: 16,
    fontWeight: 'bold',
    margin: 0,
    color: '#f8fafc',
    paddingBottom: 12,
    borderBottom: '1px solid #334155'
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
  inputGroup: {
    display: 'flex',
    alignItems: 'center',
    gap: 8
  },
  numberInput: {
    flex: 1,
    padding: '8px 12px',
    borderRadius: 8,
    backgroundColor: '#0f172a',
    color: '#f8fafc',
    border: '1px solid #334155',
    fontSize: 14
  },
  unit: {
    fontSize: 12,
    color: '#64748b'
  },
  infoBox: {
    backgroundColor: 'rgba(16, 185, 129, 0.1)',
    border: '1px solid rgba(16, 185, 129, 0.3)',
    borderRadius: 8,
    padding: 12,
    textAlign: 'center'
  },
  checkboxGroup: {
    display: 'flex',
    flexDirection: 'column',
    gap: 2
  },
  checkboxLabel: {
    display: 'flex',
    alignItems: 'center',
    gap: 8,
    fontSize: 13,
    color: '#cbd5e1',
    cursor: 'pointer'
  },
  hint: {
    margin: 0,
    fontSize: 11,
    color: '#64748b',
    paddingLeft: 24
  },
  btnTrimExecute: {
    marginTop: 'auto',
    backgroundColor: '#6366f1',
    color: '#fff',
    border: 'none',
    padding: '12px 16px',
    borderRadius: 8,
    fontSize: 14,
    fontWeight: 'bold',
    cursor: 'pointer',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center'
  }
};
