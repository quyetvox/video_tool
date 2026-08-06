import React, { useState, useRef, useEffect } from 'react';
import { 
  Play, 
  Scissors, 
  Eye, 
  CheckCircle2, 
  Clock, 
  HardDrive, 
  Maximize2,
  RotateCcw,
  FileText,
  Image as ImageIcon,
  Loader2,
  Pencil,
  MoreVertical,
  Trash2
} from 'lucide-react';
import { getMediaUrl } from '../services/api';

export default function VideoCard({ 
  file, 
  isSelected = false,
  isProcessing = false,
  onToggleSelect,
  onTranslate, 
  onTrim, 
  onResume,
  onRename,
  onDelete,
  onPreview, 
  onViewTextContent,
  onViewImage,
  isDone = false 
}) {
  const [duration, setDuration] = useState(null);
  const [resolution, setResolution] = useState(null);
  const [isHovered, setIsHovered] = useState(false);
  const [showMenu, setShowMenu] = useState(false);
  const videoRef = useRef(null);
  const menuRef = useRef(null);

  // Close dropdown menu when clicking outside
  useEffect(() => {
    const handleClickOutside = (event) => {
      if (menuRef.current && !menuRef.current.contains(event.target)) {
        setShowMenu(false);
      }
    };
    if (showMenu) {
      document.addEventListener('mousedown', handleClickOutside);
    }
    return () => {
      document.removeEventListener('mousedown', handleClickOutside);
    };
  }, [showMenu]);

  const mediaUrl = getMediaUrl(file.relPath);
  const ext = file.name.split('.').pop().toLowerCase();
  const isImageFile = file.isImage || ['jpg', 'jpeg', 'png', 'webp', 'gif'].includes(ext);

  const handleLoadedMetadata = () => {
    if (videoRef.current) {
      const dur = videoRef.current.duration;
      const w = videoRef.current.videoWidth;
      const h = videoRef.current.videoHeight;

      if (dur && !isNaN(dur)) setDuration(dur);
      if (w && h) setResolution(`${w}x${h}`);
    }
  };

  const handleMouseEnter = () => {
    setIsHovered(true);
    if (videoRef.current && !isProcessing) {
      videoRef.current.play().catch(() => {});
    }
  };

  const handleMouseLeave = () => {
    setIsHovered(false);
    if (videoRef.current && !isProcessing) {
      videoRef.current.pause();
      videoRef.current.currentTime = 0.5;
    }
  };

  const formatDuration = (sec) => {
    if (sec === null || sec === undefined) return '--:--';
    const m = Math.floor(sec / 60);
    const s = Math.floor(sec % 60);
    return `${m.toString().padStart(2, '0')}:${s.toString().padStart(2, '0')}`;
  };

  const formatSize = (bytes) => {
    if (!bytes) return '0 MB';
    const mb = bytes / (1024 * 1024);
    return `${mb.toFixed(1)} MB`;
  };

  const handleCopyPath = () => {
    navigator.clipboard.writeText(file.relPath);
  };

  // Extract job stem name for resume (e.g. video_001.mp4 -> job_video_001)
  const getJobStem = () => {
    const stem = file.name.replace(/_vi\.[^/.]+$|\.[^/.]+$/, '');
    return `job_${stem}`;
  };

  const handleBoxClick = () => {
    if (file.isMedia) {
      onPreview(mediaUrl);
    } else if (isImageFile && onViewImage) {
      onViewImage(mediaUrl, file.name);
    } else if (onViewTextContent) {
      onViewTextContent(file.relPath);
    }
  };

  return (
    <div 
      style={{
        ...styles.card,
        ...(isDone ? styles.cardDone : {}),
        ...(isSelected ? styles.cardSelected : {}),
        ...(isProcessing ? styles.cardProcessing : {})
      }}
      onMouseEnter={handleMouseEnter}
      onMouseLeave={handleMouseLeave}
    >
      {/* Thumbnail Area */}
      <div style={styles.thumbnailBox} onClick={handleBoxClick}>
        {/* Checkbox Overlay */}
        {onToggleSelect && (
          <div 
            style={styles.checkboxBox}
            onClick={(e) => {
              e.stopPropagation();
              onToggleSelect(file.relPath);
            }}
          >
            <input
              type="checkbox"
              checked={isSelected}
              onChange={() => {}} // Handled by parent div
              disabled={isProcessing}
              style={styles.checkbox}
            />
          </div>
        )}

        {file.isMedia ? (
          <video
            ref={videoRef}
            src={`${mediaUrl}#t=0.5`}
            preload="metadata"
            muted
            playsInline
            onLoadedMetadata={handleLoadedMetadata}
            style={styles.videoThumbnail}
          />
        ) : isImageFile ? (
          <img
            src={mediaUrl}
            alt={file.name}
            style={styles.videoThumbnail}
          />
        ) : (
          <div style={styles.filePlaceholder}>
            <FileText size={36} color="#818cf8" style={{ marginBottom: 8 }} />
            <span>{file.name.split('.').pop().toUpperCase()} File</span>
          </div>
        )}

        {/* Full Processing Overlay when translating or resuming */}
        {isProcessing && (
          <div style={styles.processingOverlay}>
            <Loader2 size={36} color="#f59e0b" style={{ animation: 'spin 1s linear infinite' }} />
            <span style={styles.processingText}>⏳ ĐANG XỬ LÝ VIDEO...</span>
            <span style={styles.processingSubText}>Pipeline đang chạy ở background</span>
          </div>
        )}

        {/* Overlay Play/Eye Icon */}
        {!isProcessing && (
          <div style={{ ...styles.playOverlay, opacity: isHovered ? 1 : 0 }}>
            <Maximize2 size={24} color="#fff" />
          </div>
        )}

        {/* Top Right Status Tag */}
        {isProcessing ? (
          <div style={styles.processingBadge}>
            <Loader2 size={12} style={{ marginRight: 4, animation: 'spin 1s linear infinite' }} /> ⏳ Đang Xử Lý...
          </div>
        ) : isDone ? (
          <div style={styles.doneBadge}>
            <CheckCircle2 size={12} style={{ marginRight: 4 }} /> Output Video
          </div>
        ) : (
          <div style={styles.sizeBadge}>
            <HardDrive size={10} style={{ marginRight: 4 }} /> {formatSize(file.sizeBytes)}
          </div>
        )}

        {/* Bottom Bar overlay: Duration & Resolution */}
        {file.isMedia && (
          <div style={styles.bottomOverlayBar}>
            <span style={styles.overlayTag}>
              <Clock size={10} style={{ marginRight: 4 }} /> {formatDuration(duration)}
            </span>
            {resolution && (
              <span style={styles.overlayTag}>
                {resolution}
              </span>
            )}
          </div>
        )}
      </div>

      {/* Card Info & Details */}
      <div style={styles.cardInfo}>
        <div style={styles.fileName} title={file.name}>
          {file.name}
        </div>

        <div style={styles.metaRow}>
          <span style={styles.metaText}>💾 {formatSize(file.sizeBytes)}</span>
          <span style={styles.metaDot}>•</span>
          <span style={styles.metaText}>📅 {file.mtime ? new Date(file.mtime).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }) : ''}</span>
        </div>
      </div>

      {/* Action Buttons */}
      <div style={{ ...styles.actionRow, position: 'relative' }} ref={menuRef}>
        {file.isMedia ? (
          <>
            {!isDone && onTranslate ? (
              <button 
                style={isProcessing ? { ...styles.btnDisabled, flex: 1 } : { ...styles.btnPrimary, flex: 1 }} 
                onClick={() => !isProcessing && onTranslate(file.relPath)}
                disabled={isProcessing}
                title={isProcessing ? "Video đang được xử lý..." : "Dịch video gốc này"}
              >
                <Play size={13} style={{ marginRight: 4 }} />
                {isProcessing ? 'Đang Chạy...' : 'Dịch Video'}
              </button>
            ) : isDone && onResume ? (
              <button 
                style={isProcessing ? { ...styles.btnDisabled, flex: 1 } : { ...styles.btnWarning, flex: 1 }} 
                onClick={() => !isProcessing && onResume(getJobStem())}
                disabled={isProcessing}
                title={isProcessing ? "Job đang được xử lý..." : "Resume pipeline job cho video này"}
              >
                <RotateCcw size={13} style={{ marginRight: 4 }} />
                {isProcessing ? 'Đang Chạy...' : 'Resume Job'}
              </button>
            ) : isDone ? (
              <button 
                style={{ ...styles.btnDone, flex: 1 }} 
                onClick={() => onPreview(mediaUrl)}
                title="Xem video kết quả"
              >
                <Play size={13} style={{ marginRight: 4 }} /> Xem Video
              </button>
            ) : null}

            {onTrim && (
              <button 
                style={isProcessing ? styles.btnDisabled : styles.btnSecondary} 
                onClick={() => !isProcessing && onTrim(file.relPath)}
                disabled={isProcessing}
                title="Cắt khoảng thời gian video"
              >
                <Scissors size={13} style={{ marginRight: 3 }} /> Cắt
              </button>
            )}
          </>
        ) : isImageFile ? (
          <button 
            style={{ ...styles.btnPrimary, flex: 1, backgroundColor: '#10b981' }} 
            onClick={() => onViewImage && onViewImage(mediaUrl, file.name)}
          >
            <ImageIcon size={13} style={{ marginRight: 4 }} /> Xem Ảnh
          </button>
        ) : (
          <button 
            style={{ ...styles.btnPrimary, flex: 1, backgroundColor: '#818cf8' }} 
            onClick={() => onViewTextContent && onViewTextContent(file.relPath)}
          >
            <Eye size={13} style={{ marginRight: 4 }} /> Xem Content
          </button>
        )}

        {/* More Actions Popover Menu */}
        {(onResume || onRename || onDelete) && (
          <div style={{ position: 'relative' }}>
            <button
              style={{
                ...styles.btnIcon,
                backgroundColor: showMenu ? '#334155' : 'rgba(255, 255, 255, 0.08)',
                color: showMenu ? '#38bdf8' : '#94a3b8',
                border: '1px solid rgba(255, 255, 255, 0.1)'
              }}
              onClick={() => setShowMenu(prev => !prev)}
              title="Thao tác khác (Xem, Đổi tên, Xóa)"
            >
              <MoreVertical size={14} />
            </button>

            {showMenu && (
              <div style={styles.menuDropdown}>
                {file.isMedia && !isDone && onResume && (
                  <button
                    style={styles.menuItem}
                    onClick={() => {
                      setShowMenu(false);
                      if (!isProcessing) onResume(getJobStem());
                    }}
                    disabled={isProcessing}
                  >
                    <RotateCcw size={13} style={{ marginRight: 8, color: '#f59e0b' }} /> Resume Job
                  </button>
                )}

                {file.isMedia && isDone && (
                  <button
                    style={styles.menuItem}
                    onClick={() => {
                      setShowMenu(false);
                      onPreview(mediaUrl);
                    }}
                  >
                    <Play size={13} style={{ marginRight: 8, color: '#10b981' }} /> Xem Video
                  </button>
                )}

                {onRename && (
                  <button
                    style={styles.menuItem}
                    onClick={() => {
                      setShowMenu(false);
                      if (!isProcessing) onRename(file);
                    }}
                    disabled={isProcessing}
                  >
                    <Pencil size={13} style={{ marginRight: 8, color: '#38bdf8' }} /> Đổi Tên File
                  </button>
                )}

                {onDelete && (
                  <button
                    style={{ ...styles.menuItem, ...styles.menuItemDanger }}
                    onClick={() => {
                      setShowMenu(false);
                      if (!isProcessing) onDelete(file);
                    }}
                    disabled={isProcessing}
                  >
                    <Trash2 size={13} style={{ marginRight: 8, color: '#ef4444' }} /> Xóa File
                  </button>
                )}
              </div>
            )}
          </div>
        )}
      </div>
    </div>
  );
}

const styles = {
  card: {
    backgroundColor: '#1e293b',
    borderRadius: 12,
    border: '1px solid #334155',
    overflow: 'hidden',
    display: 'flex',
    flexDirection: 'column',
    transition: 'all 0.2s ease',
    boxShadow: '0 4px 6px -1px rgba(0, 0, 0, 0.2)',
    position: 'relative'
  },
  cardDone: {
    border: '1px solid rgba(16, 185, 129, 0.4)'
  },
  cardSelected: {
    border: '2px solid #6366f1',
    boxShadow: '0 0 12px rgba(99, 102, 241, 0.4)'
  },
  cardProcessing: {
    border: '2px solid #f59e0b',
    boxShadow: '0 0 20px rgba(245, 158, 11, 0.6)',
    backgroundColor: '#272015',
    animation: 'pulseGlow 1.8s infinite ease-in-out'
  },
  processingOverlay: {
    position: 'absolute',
    top: 0, left: 0, right: 0, bottom: 0,
    backgroundColor: 'rgba(15, 23, 42, 0.88)',
    display: 'flex',
    flexDirection: 'column',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 8,
    zIndex: 20,
    backdropFilter: 'blur(4px)'
  },
  processingText: {
    color: '#fbbf24',
    fontSize: 13,
    fontWeight: '700',
    letterSpacing: '0.5px',
    animation: 'pulseGlow 1.5s infinite'
  },
  processingSubText: {
    color: '#94a3b8',
    fontSize: 11,
    fontWeight: '400'
  },
  checkboxBox: {
    position: 'absolute',
    top: 8,
    left: 8,
    zIndex: 10,
    backgroundColor: 'rgba(15, 23, 42, 0.8)',
    borderRadius: 6,
    padding: '4px 6px',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    backdropFilter: 'blur(4px)',
    cursor: 'pointer'
  },
  checkbox: {
    width: 18,
    height: 18,
    accentColor: '#6366f1',
    cursor: 'pointer'
  },
  thumbnailBox: {
    position: 'relative',
    width: '100%',
    height: 160,
    backgroundColor: '#090d16',
    cursor: 'pointer',
    overflow: 'hidden',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center'
  },
  videoThumbnail: {
    width: '100%',
    height: '100%',
    objectFit: 'cover'
  },
  filePlaceholder: {
    color: '#64748b',
    fontSize: 12,
    display: 'flex',
    flexDirection: 'column',
    alignItems: 'center'
  },
  playOverlay: {
    position: 'absolute',
    top: 0, left: 0, right: 0, bottom: 0,
    backgroundColor: 'rgba(0,0,0,0.4)',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    transition: 'opacity 0.2s ease'
  },
  processingBadge: {
    position: 'absolute',
    top: 8,
    right: 8,
    backgroundColor: 'rgba(245, 158, 11, 0.95)',
    color: '#fff',
    fontSize: 11,
    fontWeight: 'bold',
    padding: '3px 9px',
    borderRadius: 6,
    display: 'flex',
    alignItems: 'center',
    boxShadow: '0 2px 8px rgba(245, 158, 11, 0.4)'
  },
  doneBadge: {
    position: 'absolute',
    top: 8,
    right: 8,
    backgroundColor: 'rgba(16, 185, 129, 0.9)',
    color: '#fff',
    fontSize: 10,
    fontWeight: 'bold',
    padding: '3px 8px',
    borderRadius: 6,
    display: 'flex',
    alignItems: 'center'
  },
  sizeBadge: {
    position: 'absolute',
    top: 8,
    right: 8,
    backgroundColor: 'rgba(15, 23, 42, 0.8)',
    color: '#cbd5e1',
    fontSize: 10,
    fontWeight: '600',
    padding: '3px 8px',
    borderRadius: 6,
    display: 'flex',
    alignItems: 'center',
    backdropFilter: 'blur(4px)'
  },
  bottomOverlayBar: {
    position: 'absolute',
    bottom: 8,
    left: 8,
    right: 8,
    display: 'flex',
    justifyContent: 'space-between',
    pointerEvents: 'none'
  },
  overlayTag: {
    backgroundColor: 'rgba(15, 23, 42, 0.85)',
    color: '#f8fafc',
    fontSize: 10,
    fontWeight: '600',
    padding: '2px 6px',
    borderRadius: 4,
    display: 'flex',
    alignItems: 'center',
    backdropFilter: 'blur(4px)'
  },
  cardInfo: {
    padding: 12,
    display: 'flex',
    flexDirection: 'column',
    gap: 6,
    flex: 1
  },
  fileName: {
    fontSize: 13,
    fontWeight: '600',
    color: '#f8fafc',
    whiteSpace: 'nowrap',
    overflow: 'hidden',
    textOverflow: 'ellipsis'
  },
  metaRow: {
    display: 'flex',
    alignItems: 'center',
    gap: 6,
    fontSize: 11,
    color: '#94a3b8'
  },
  metaText: {
    display: 'flex',
    alignItems: 'center',
    gap: 3
  },
  metaDot: {
    color: '#475569'
  },
  actionRow: {
    padding: '0 12px 12px 12px',
    display: 'flex',
    gap: 6
  },
  btnPrimary: {
    flex: 1,
    backgroundColor: '#6366f1',
    color: '#fff',
    border: 'none',
    padding: '7px 10px',
    borderRadius: 6,
    fontSize: 11,
    fontWeight: '600',
    cursor: 'pointer',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    transition: 'background-color 0.15s ease'
  },
  btnDisabled: {
    flex: 1,
    backgroundColor: '#475569',
    color: '#94a3b8',
    border: 'none',
    padding: '7px 10px',
    borderRadius: 6,
    fontSize: 11,
    fontWeight: '600',
    cursor: 'not-allowed',
    opacity: 0.6,
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center'
  },
  btnSecondary: {
    backgroundColor: '#334155',
    color: '#cbd5e1',
    border: 'none',
    padding: '7px 10px',
    borderRadius: 6,
    fontSize: 11,
    fontWeight: '500',
    cursor: 'pointer',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    transition: 'background-color 0.15s ease'
  },
  btnDone: {
    flex: 1,
    backgroundColor: '#10b981',
    color: '#fff',
    border: 'none',
    padding: '7px 10px',
    borderRadius: 6,
    fontSize: 11,
    fontWeight: '600',
    cursor: 'pointer',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center'
  },
  btnIcon: {
    backgroundColor: '#334155',
    color: '#94a3b8',
    border: 'none',
    padding: '7px 9px',
    borderRadius: 6,
    cursor: 'pointer',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    transition: 'all 0.15s ease'
  },
  menuDropdown: {
    position: 'absolute',
    bottom: '100%',
    right: 0,
    marginBottom: 6,
    backgroundColor: '#0f172a',
    border: '1px solid #334155',
    borderRadius: 8,
    boxShadow: '0 10px 25px -5px rgba(0, 0, 0, 0.6), 0 8px 10px -6px rgba(0, 0, 0, 0.5)',
    zIndex: 40,
    minWidth: 155,
    overflow: 'hidden',
    display: 'flex',
    flexDirection: 'column',
    padding: '4px 0'
  },
  menuItem: {
    display: 'flex',
    alignItems: 'center',
    padding: '8px 12px',
    fontSize: 12,
    fontWeight: '500',
    color: '#e2e8f0',
    backgroundColor: 'transparent',
    border: 'none',
    textAlign: 'left',
    width: '100%',
    cursor: 'pointer',
    transition: 'background-color 0.15s ease'
  },
  menuItemDanger: {
    color: '#f87171'
  }
};
