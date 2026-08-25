import React, { useState } from 'react';
import { 
  Play, 
  Edit3, 
  Trash2, 
  Download, 
  CloudUpload, 
  CloudDownload, 
  HardDrive, 
  RefreshCw, 
  Search, 
  List, 
  LayoutGrid, 
  MoreHorizontal, 
  CheckSquare, 
  Square, 
  Film,
  CheckCircle2,
  Clock,
  Zap,
  Scissors,
  Pencil,
  Mic,
  FileText,
  X
} from 'lucide-react';
import { getMediaUrl } from '../services/api';
import CompactVideoCard from './CompactVideoCard';

const formatDuration = (sec) => {
  if (sec === null || sec === undefined || isNaN(sec) || sec < 0) return '00:00';
  const m = Math.floor(sec / 60);
  const s = Math.floor(sec % 60);
  return `${m.toString().padStart(2, '0')}:${s.toString().padStart(2, '0')}`;
};

const formatSize = (bytes) => {
  if (!bytes || isNaN(bytes) || bytes <= 0) return '0 MB';
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  if (bytes < 1024 * 1024 * 1024) return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
  return `${(bytes / (1024 * 1024 * 1024)).toFixed(2)} GB`;
};

const formatDateRelative = (mtimeMs) => {
  if (!mtimeMs) return 'Recently';
  const diffSec = Math.floor((Date.now() - mtimeMs) / 1000);
  if (diffSec < 60) return 'Just now';
  if (diffSec < 3600) return `${Math.floor(diffSec / 60)}m ago`;
  if (diffSec < 86400) return `${Math.floor(diffSec / 3600)}h ago`;
  if (diffSec < 172800) return 'Yesterday';
  return `${Math.floor(diffSec / 86400)}d ago`;
};

export default function AssetTable({
  files = [],
  selectedFile = null,
  onSelectFile,
  runningRelPaths = [],
  onRefresh,
  onOpenTrimmer,
  onDeleteFile,
  onRenameFile,
  onBatchTranslate,
  onBatchTranslateVoice,
  onBatchTranslateSub,
  onBatchUploadCloud,
  onBatchSyncDown,
  onBatchOffload,
  onBatchDelete
}) {
  const [viewMode, setViewMode] = useState('table'); // 'table' | 'grid'
  const [searchQuery, setSearchQuery] = useState('');
  const [selectedRelPaths, setSelectedRelPaths] = useState([]);
  const [videoMetaMap, setVideoMetaMap] = useState({});

  // Filter files by search
  const filteredFiles = files.filter(f => {
    if (!searchQuery.trim()) return true;
    return f.name.toLowerCase().includes(searchQuery.toLowerCase()) || f.relPath.toLowerCase().includes(searchQuery.toLowerCase());
  });

  const isFileRunning = (file) => {
    if (!file || !runningRelPaths || runningRelPaths.length === 0) return false;
    const stem = file.name ? file.name.replace(/\.[^/.]+$/, '').replace(/_vi$/, '') : '';
    return runningRelPaths.some(p => {
      if (!p) return false;
      if (file.relPath && (file.relPath.includes(p) || p.includes(file.relPath))) return true;
      if (file.name && (file.name.includes(p) || p.includes(file.name))) return true;
      const cleanP = p.split('/').pop().split(':').pop().replace(/^job_/, '').replace(/^trans_/, '').replace(/^resume_/, '').replace(/^ocr_/, '').replace(/^batch_/, '').replace(/\.[^/.]+$/, '').replace(/_vi$/, '');
      if (stem && cleanP && (stem === cleanP || stem.includes(cleanP) || cleanP.includes(stem))) return true;
      return false;
    });
  };

  const toggleSelectAll = () => {
    if (selectedRelPaths.length === filteredFiles.length) {
      setSelectedRelPaths([]);
    } else {
      setSelectedRelPaths(filteredFiles.map(f => f.relPath));
    }
  };

  const toggleSelectRow = (relPath, e) => {
    e.stopPropagation();
    setSelectedRelPaths(prev => 
      prev.includes(relPath) ? prev.filter(p => p !== relPath) : [...prev, relPath]
    );
  };

  const handleMetadataLoaded = (relPath, e) => {
    const dur = e.target.duration;
    const w = e.target.videoWidth;
    const h = e.target.videoHeight;
    if (dur) {
      setVideoMetaMap(prev => {
        if (prev[relPath] && prev[relPath].duration === dur) return prev;
        return {
          ...prev,
          [relPath]: {
            duration: dur,
            resolution: w && h ? `${w}x${h}` : '1920x1080'
          }
        };
      });
    }
  };

  return (
    <div style={styles.container}>
      {/* Table Header Controls */}
      <div style={styles.header}>
        <div style={styles.headerLeft}>
          <h3 style={styles.tableTitle}>
            All Videos <span style={styles.countBadge}>({files.length})</span>
          </h3>
          <button 
            style={styles.iconBtn} 
            onClick={onRefresh}
            title="Làm mới danh sách video"
          >
            <RefreshCw size={13} />
            <span>Refresh</span>
          </button>
        </div>

        <div style={styles.headerRight}>
          {/* Search Box */}
          <div style={styles.searchBox}>
            <Search size={13} color="var(--text-dim)" />
            <input
              type="text"
              placeholder="Tìm kiếm video..."
              value={searchQuery}
              onChange={e => setSearchQuery(e.target.value)}
              style={styles.searchInput}
            />
          </div>

          {/* View Toggle */}
          <div style={styles.viewToggleGroup}>
            <button
              style={{
                ...styles.viewToggleBtn,
                ...(viewMode === 'table' ? styles.viewToggleActive : {})
              }}
              onClick={() => setViewMode('table')}
              title="Table View (Dạng bảng)"
            >
              <List size={14} />
            </button>
            <button
              style={{
                ...styles.viewToggleBtn,
                ...(viewMode === 'grid' ? styles.viewToggleActive : {})
              }}
              onClick={() => setViewMode('grid')}
              title="Grid View (Dạng lưới)"
            >
              <LayoutGrid size={14} />
            </button>
          </div>
        </div>
      </div>

      {/* Main Content View (Table or Grid) */}
      <div style={styles.scrollArea}>
        {viewMode === 'table' ? (
          <table style={styles.table}>
            <thead>
              <tr style={styles.thRow}>
                <th style={{ ...styles.th, width: 36, textAlign: 'center' }}>
                  <input
                    type="checkbox"
                    checked={filteredFiles.length > 0 && selectedRelPaths.length === filteredFiles.length}
                    onChange={toggleSelectAll}
                    style={{ accentColor: 'var(--primary)', cursor: 'pointer' }}
                  />
                </th>
                <th style={{ ...styles.th, width: 48 }}>Preview</th>
                <th style={styles.th}>Name</th>
                <th style={{ ...styles.th, width: 85 }}>Duration</th>
                <th style={{ ...styles.th, width: 95 }}>Resolution</th>
                <th style={{ ...styles.th, width: 85 }}>Size</th>
                <th style={{ ...styles.th, width: 100 }}>Status</th>
                <th style={{ ...styles.th, width: 105 }}>Modified</th>
                <th style={{ ...styles.th, width: 80, textAlign: 'center' }}>Actions</th>
              </tr>
            </thead>
            <tbody>
              {filteredFiles.length === 0 ? (
                <tr>
                  <td colSpan={9} style={styles.emptyTd}>
                    Không tìm thấy video nào trong thư mục này
                  </td>
                </tr>
              ) : (
                filteredFiles.map((file, idx) => {
                  const isSelected = selectedFile?.relPath === file.relPath;
                  const isChecked = selectedRelPaths.includes(file.relPath);
                  const isRunning = isFileRunning(file);
                  const isOutput = file.relPath.includes('/output/');

                  const meta = videoMetaMap[file.relPath] || {};
                  const effectiveDuration = meta.duration || file.duration || null;
                  const effectiveRes = meta.resolution || file.resolution || '1080p';
                  const effectiveSize = file.size || file.sizeBytes || 0;
                  const effectiveMtime = file.mtime || file.mtimeMs || 0;

                  return (
                    <tr
                      key={file.relPath || idx}
                      style={{
                        ...styles.tr,
                        ...(isSelected ? styles.trSelected : {}),
                        ...(isChecked ? styles.trChecked : {})
                      }}
                      onClick={() => onSelectFile && onSelectFile(file)}
                    >
                      {/* Checkbox */}
                      <td style={{ ...styles.td, textAlign: 'center' }} onClick={e => e.stopPropagation()}>
                        <input
                          type="checkbox"
                          checked={isChecked}
                          onChange={e => toggleSelectRow(file.relPath, e)}
                          style={{ accentColor: 'var(--primary)', cursor: 'pointer' }}
                        />
                      </td>

                      {/* Thumbnail Preview */}
                      <td style={styles.td}>
                        <div style={styles.thumbWrapper}>
                          <video 
                            src={getMediaUrl(file.relPath)} 
                            style={styles.thumbVideo}
                            preload="metadata"
                            onLoadedMetadata={(e) => handleMetadataLoaded(file.relPath, e)}
                          />
                          <div style={styles.thumbPlayIcon}>
                            <Play size={10} color="#ffffff" />
                          </div>
                        </div>
                      </td>

                      {/* Name */}
                      <td style={styles.td}>
                        <div style={styles.nameCell} title={file.name}>
                          <span style={styles.nameText}>{file.name}</span>
                          {file.relPath.includes('/output/') && (
                            <span style={styles.outputTag}>VI</span>
                          )}
                          {file.relPath.includes('/cut/') && (
                            <span style={{ ...styles.outputTag, backgroundColor: 'rgba(6, 182, 212, 0.15)', color: '#06b6d4', borderColor: 'rgba(6, 182, 212, 0.3)' }}>CUT</span>
                          )}
                          {file.relPath.includes('/merge/') && (
                            <span style={{ ...styles.outputTag, backgroundColor: 'rgba(192, 132, 252, 0.15)', color: '#c084fc', borderColor: 'rgba(192, 132, 252, 0.3)' }}>MERGE</span>
                          )}
                        </div>
                      </td>

                      {/* Duration */}
                      <td style={{ ...styles.td, fontFamily: 'monospace', fontSize: 11, color: 'var(--text-main)' }}>
                        {effectiveDuration ? formatDuration(effectiveDuration) : '...'}
                      </td>

                      {/* Resolution */}
                      <td style={{ ...styles.td, fontSize: 11, color: 'var(--text-dim)' }}>
                        {effectiveRes}
                      </td>

                      {/* Size */}
                      <td style={{ ...styles.td, fontSize: 11, color: 'var(--primary-light)', fontWeight: 600 }}>
                        {formatSize(effectiveSize)}
                      </td>

                      {/* Status Badge */}
                      <td style={styles.td}>
                        {isRunning ? (
                          <span className="badge badge-processing">
                            <RefreshCw size={10} className="spin-icon" /> Processing
                          </span>
                        ) : isOutput ? (
                          <span className="badge badge-success">
                            <CheckCircle2 size={10} /> Completed
                          </span>
                        ) : (
                          <span className="badge badge-neutral">
                            Ready
                          </span>
                        )}
                      </td>

                      {/* Modified Time */}
                      <td style={{ ...styles.td, fontSize: 11, color: 'var(--text-dim)' }}>
                        {formatDateRelative(effectiveMtime)}
                      </td>

                      {/* Actions */}
                      <td style={{ ...styles.td, textAlign: 'center' }} onClick={e => e.stopPropagation()}>
                        <div style={styles.actionGroup}>
                          <button
                            style={styles.rowBtn}
                            onClick={(e) => {
                              e.stopPropagation();
                              onRenameFile && onRenameFile(file);
                            }}
                            title="Đổi tên video này"
                          >
                            <Pencil size={13} />
                          </button>
                          <button
                            style={styles.rowBtn}
                            onClick={() => onOpenTrimmer && onOpenTrimmer(file.relPath)}
                            title="Cắt nhanh (Trimmer)"
                          >
                            <Scissors size={13} />
                          </button>
                          <button
                            style={{ ...styles.rowBtn, color: 'var(--accent-red)' }}
                            onClick={(e) => {
                              e.stopPropagation();
                              e.preventDefault();
                              onDeleteFile && onDeleteFile(file.relPath);
                            }}
                            title="Xóa vĩnh viễn video này"
                          >
                            <Trash2 size={13} />
                          </button>
                        </div>
                      </td>
                    </tr>
                  );
                })
              )}
            </tbody>
          </table>
        ) : (
          /* Grid View Mode */
          <div style={styles.gridContainer}>
            {filteredFiles.map(f => (
              <CompactVideoCard
                key={f.relPath}
                file={f}
                isSelected={selectedFile?.relPath === f.relPath}
                onSelect={() => onSelectFile && onSelectFile(f)}
                onRename={onRenameFile}
                disabled={isFileRunning(f)}
              />
            ))}
          </div>
        )}
      </div>

      {/* Batch Action Bar (Shown when files are selected) */}
      {selectedRelPaths.length > 0 && (
        <div style={styles.batchBar}>
          <div style={styles.batchLeft}>
            <span style={styles.batchCount}>{selectedRelPaths.length} video đã chọn</span>
            <button
              style={{
                display: 'flex',
                alignItems: 'center',
                gap: 4,
                padding: '4px 8px',
                fontSize: 11,
                fontWeight: 500,
                color: 'var(--text-secondary)',
                backgroundColor: 'rgba(255, 255, 255, 0.06)',
                border: '1px solid var(--border)',
                borderRadius: 6,
                cursor: 'pointer',
                transition: 'all 0.15s ease'
              }}
              onClick={() => setSelectedRelPaths([])}
              title="Bỏ chọn tất cả các video đã tick"
            >
              <X size={12} />
              <span>Bỏ chọn</span>
            </button>
          </div>

          <div style={styles.batchActions}>
            {/* 1. Dịch Voice (N) */}
            <button 
              style={{ ...styles.batchBtn, backgroundColor: 'var(--primary)', color: '#ffffff', fontWeight: 600 }}
              onClick={() => {
                if (onBatchTranslateVoice) onBatchTranslateVoice(selectedRelPaths);
                else if (onBatchTranslate) onBatchTranslate(selectedRelPaths, 'voice');
              }}
              title="Dịch thuyết minh giọng nói toàn diện cho các video được chọn"
            >
              <Mic size={13} />
              <span>Dịch Voice ({selectedRelPaths.length})</span>
            </button>

            {/* 2. Dịch Sub (N) */}
            <button 
              style={{ ...styles.batchBtn, backgroundColor: '#059669', color: '#ffffff', fontWeight: 600 }}
              onClick={() => {
                if (onBatchTranslateSub) onBatchTranslateSub(selectedRelPaths);
                else if (onBatchTranslate) onBatchTranslate(selectedRelPaths, 'sub');
              }}
              title="Dịch phụ đề cứng siêu tốc (OCR Only) cho các video được chọn"
            >
              <FileText size={13} />
              <span>Dịch Sub ({selectedRelPaths.length})</span>
            </button>

            <button 
              style={styles.batchBtn}
              onClick={() => onBatchUploadCloud && onBatchUploadCloud(selectedRelPaths)}
              title="Đẩy các video được tick lên GCS Cloud"
            >
              <CloudUpload size={13} color="#c084fc" />
              <span>Upload Cloud ({selectedRelPaths.length})</span>
            </button>

            <button 
              style={styles.batchBtn}
              onClick={() => onBatchSyncDown && onBatchSyncDown(selectedRelPaths)}
              title="Kéo các video được tick từ Cloud về SSD"
            >
              <CloudDownload size={13} color="#38bdf8" />
              <span>Download ({selectedRelPaths.length})</span>
            </button>

            <button 
              style={styles.batchBtn}
              onClick={() => onBatchOffload && onBatchOffload(selectedRelPaths)}
              title="Xóa local các video đã an toàn trên Cloud"
            >
              <HardDrive size={13} color="#facc15" />
              <span>Offload SSD</span>
            </button>

            <button 
              style={{ ...styles.batchBtn, color: 'var(--accent-red)', borderColor: 'rgba(239, 68, 68, 0.4)' }}
              onClick={() => {
                if (onBatchDelete && selectedRelPaths.length > 0) {
                  onBatchDelete(selectedRelPaths);
                  setSelectedRelPaths([]);
                }
              }}
              title="Xóa vĩnh viễn các file đã chọn"
            >
              <Trash2 size={13} />
              <span>Delete ({selectedRelPaths.length})</span>
            </button>
          </div>
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
    boxShadow: 'var(--shadow-sm)',
    position: 'relative',
  },
  header: {
    padding: '8px 12px',
    borderBottom: '1px solid var(--border-color)',
    backgroundColor: 'var(--bg-surface)',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  headerLeft: {
    display: 'flex',
    alignItems: 'center',
    gap: 10,
  },
  tableTitle: {
    fontSize: 13,
    fontWeight: 700,
    color: 'var(--text-main)',
  },
  countBadge: {
    color: 'var(--text-dim)',
    fontWeight: 500,
  },
  iconBtn: {
    display: 'flex',
    alignItems: 'center',
    gap: 5,
    padding: '4px 8px',
    backgroundColor: 'var(--bg-input)',
    color: 'var(--text-muted)',
    borderRadius: 'var(--radius-sm)',
    border: '1px solid var(--border-color)',
    fontSize: 11,
    fontWeight: 500,
  },
  headerRight: {
    display: 'flex',
    alignItems: 'center',
    gap: 8,
  },
  searchBox: {
    display: 'flex',
    alignItems: 'center',
    gap: 6,
    padding: '4px 8px',
    backgroundColor: 'var(--bg-input)',
    border: '1px solid var(--border-color)',
    borderRadius: 'var(--radius-sm)',
  },
  searchInput: {
    background: 'transparent',
    border: 'none',
    color: 'var(--text-main)',
    fontSize: 11,
    width: 140,
    outline: 'none',
  },
  viewToggleGroup: {
    display: 'flex',
    backgroundColor: 'var(--bg-input)',
    border: '1px solid var(--border-color)',
    borderRadius: 'var(--radius-sm)',
    overflow: 'hidden',
  },
  viewToggleBtn: {
    padding: '4px 6px',
    backgroundColor: 'transparent',
    color: 'var(--text-dim)',
    border: 'none',
    display: 'flex',
    alignItems: 'center',
  },
  viewToggleActive: {
    backgroundColor: 'var(--bg-surface-elevated)',
    color: 'var(--primary-light)',
  },
  scrollArea: {
    flex: 1,
    overflowY: 'auto',
  },
  table: {
    width: '100%',
    borderCollapse: 'collapse',
    fontSize: 12,
    textAlign: 'left',
  },
  thRow: {
    backgroundColor: 'var(--bg-surface)',
    borderBottom: '1px solid var(--border-color)',
  },
  th: {
    padding: '8px 10px',
    fontSize: 11,
    fontWeight: 600,
    color: 'var(--text-dim)',
    letterSpacing: '0.3px',
    userSelect: 'none',
  },
  tr: {
    borderBottom: '1px solid var(--border-subtle)',
    cursor: 'pointer',
    transition: 'background-color 0.15s ease',
  },
  trSelected: {
    backgroundColor: 'rgba(59, 130, 246, 0.12)',
  },
  trChecked: {
    backgroundColor: 'rgba(59, 130, 246, 0.06)',
  },
  td: {
    padding: '7px 10px',
    color: 'var(--text-main)',
    verticalAlign: 'middle',
  },
  emptyTd: {
    padding: 30,
    textAlign: 'center',
    color: 'var(--text-dim)',
  },
  thumbWrapper: {
    width: 40,
    height: 26,
    borderRadius: 4,
    overflow: 'hidden',
    backgroundColor: '#000',
    position: 'relative',
  },
  thumbVideo: {
    width: '100%',
    height: '100%',
    objectFit: 'cover',
  },
  thumbPlayIcon: {
    position: 'absolute',
    top: 0,
    left: 0,
    right: 0,
    bottom: 0,
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: 'rgba(0,0,0,0.3)',
  },
  nameCell: {
    display: 'flex',
    alignItems: 'center',
    gap: 6,
    maxWidth: 180,
  },
  nameText: {
    overflow: 'hidden',
    textOverflow: 'ellipsis',
    whiteSpace: 'nowrap',
    fontWeight: 500,
  },
  outputTag: {
    fontSize: 9,
    fontWeight: 700,
    backgroundColor: 'var(--accent-green-bg)',
    color: 'var(--accent-green)',
    padding: '1px 4px',
    borderRadius: 4,
  },
  actionGroup: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 4,
  },
  rowBtn: {
    padding: '4px',
    background: 'none',
    border: 'none',
    color: 'var(--text-muted)',
    borderRadius: 3,
  },
  gridContainer: {
    padding: 12,
    display: 'grid',
    gridTemplateColumns: 'repeat(auto-fill, minmax(200px, 1fr))',
    gap: 10,
  },
  batchBar: {
    padding: '8px 12px',
    backgroundColor: 'var(--bg-surface-elevated)',
    borderTop: '1px solid var(--primary)',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between',
    zIndex: 20,
  },
  batchLeft: {
    display: 'flex',
    alignItems: 'center',
    gap: 8,
  },
  batchCount: {
    fontSize: 12,
    fontWeight: 600,
    color: 'var(--primary-light)',
  },
  batchActions: {
    display: 'flex',
    alignItems: 'center',
    gap: 6,
  },
  batchBtn: {
    display: 'flex',
    alignItems: 'center',
    gap: 5,
    padding: '5px 10px',
    fontSize: 11,
    fontWeight: 600,
    backgroundColor: 'var(--bg-surface)',
    border: '1px solid var(--border-color)',
    color: 'var(--text-main)',
    borderRadius: 'var(--radius-sm)',
  },
  modalOverlay: {
    position: 'absolute',
    top: 0,
    left: 0,
    right: 0,
    bottom: 0,
    backgroundColor: 'rgba(0, 0, 0, 0.7)',
    backdropFilter: 'blur(4px)',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    zIndex: 100,
    padding: 16,
  },
  modalCard: {
    backgroundColor: 'var(--bg-surface-elevated)',
    border: '1px solid var(--border-color)',
    borderRadius: 'var(--radius-md)',
    padding: '18px 20px',
    maxWidth: 420,
    width: '100%',
    boxShadow: '0 10px 25px rgba(0, 0, 0, 0.5)',
    display: 'flex',
    flexDirection: 'column',
    gap: 14,
  },
  modalHeader: {
    display: 'flex',
    gap: 12,
    alignItems: 'flex-start',
  },
  modalWarningIcon: {
    padding: 8,
    borderRadius: '50%',
    backgroundColor: 'rgba(239, 68, 68, 0.15)',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    flexShrink: 0,
  },
  modalTitle: {
    fontSize: 14,
    fontWeight: 700,
    color: 'var(--text-main)',
    marginBottom: 4,
  },
  modalDesc: {
    fontSize: 12,
    color: 'var(--text-muted)',
    lineHeight: 1.4,
  },
  modalSubDesc: {
    fontSize: 11,
    color: 'var(--text-dim)',
    marginTop: 4,
  },
  modalActions: {
    display: 'flex',
    justifyContent: 'flex-end',
    gap: 8,
  },
  modalCancelBtn: {
    padding: '6px 12px',
    backgroundColor: 'var(--bg-input)',
    border: '1px solid var(--border-color)',
    color: 'var(--text-muted)',
    borderRadius: 'var(--radius-sm)',
    fontSize: 12,
    fontWeight: 600,
  },
  modalConfirmBtn: {
    padding: '6px 14px',
    backgroundColor: 'var(--accent-red)',
    border: 'none',
    color: '#ffffff',
    borderRadius: 'var(--radius-sm)',
    fontSize: 12,
    fontWeight: 600,
    display: 'flex',
    alignItems: 'center',
    gap: 6,
    boxShadow: '0 2px 6px rgba(239, 68, 68, 0.4)',
  }
};
