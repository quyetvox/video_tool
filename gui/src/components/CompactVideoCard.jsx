import React, { useState, useRef, useEffect } from 'react';
import { Play, Check, Film, Scissors, Plus } from 'lucide-react';
import { getMediaUrl } from '../services/api';

// Inject spin keyframe once globally
if (typeof document !== 'undefined' && !document.getElementById('cvc-spin-style')) {
  const st = document.createElement('style');
  st.id = 'cvc-spin-style';
  st.textContent = '@keyframes spin { from { transform: rotate(0deg); } to { transform: rotate(360deg); } }';
  document.head.appendChild(st);
}

// Helper: Format bytes to human readable size (e.g. 20.1 MB)
const formatSizeStr = (sizeBytes) => {
  if (!sizeBytes || isNaN(sizeBytes)) return 'Media';
  if (sizeBytes < 1024) return `${sizeBytes} B`;
  if (sizeBytes < 1024 * 1024) return `${(sizeBytes / 1024).toFixed(1)} KB`;
  if (sizeBytes < 1024 * 1024 * 1024) return `${(sizeBytes / (1024 * 1024)).toFixed(1)} MB`;
  return `${(sizeBytes / (1024 * 1024 * 1024)).toFixed(2)} GB`;
};

// Helper: Format seconds float to 'mm:ss'
const formatDurationStr = (sec) => {
  if (sec === null || sec === undefined || isNaN(sec) || sec < 0) return '00:00';
  const m = Math.floor(sec / 60);
  const s = Math.floor(sec % 60);
  return `${m.toString().padStart(2, '0')}:${s.toString().padStart(2, '0')}`;
};

// Helper: Format timestamp to time string (e.g. 11:07 AM)
const formatDateStr = (mtimeMs) => {
  if (!mtimeMs) return '11:00 AM';
  const d = new Date(mtimeMs);
  return d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
};

export default function CompactVideoCard({
  file,
  isSelected = false,
  isActivePreview = false,
  onSelect,
  onToggleCheck,
  actionLabel,
  onAction,
  disabled = false
}) {
  const [duration, setDuration] = useState(file.duration || null);
  const [resolution, setResolution] = useState(null);
  const [isHovered, setIsHovered] = useState(false);
  const [isVisible, setIsVisible] = useState(false);
  const cardRef = useRef(null);
  const videoRef = useRef(null);

  // Lazy loading observer for card visibility
  useEffect(() => {
    const el = cardRef.current;
    if (!el) return;

    const observer = new IntersectionObserver(
      (entries) => {
        if (entries[0].isIntersecting) {
          setIsVisible(true);
          observer.unobserve(el);
        }
      },
      { rootMargin: '300px' }
    );

    observer.observe(el);
    return () => {
      if (el) observer.unobserve(el);
    };
  }, []);

  const mediaUrl = getMediaUrl(file.relPath);
  const isOutput = file.relPath.includes('/output/');

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
  };

  const handleMouseLeave = () => {
    setIsHovered(false);
  };

  const handleCardClick = (e) => {
    if (disabled) return;
    if (e.target.tagName === 'INPUT' || e.target.closest('button')) return;
    if (onSelect) onSelect(file.relPath);
  };

  const isHighlighted = isSelected || isActivePreview;

  return (
    <div
      ref={cardRef}
      className="compact-video-card"
      onClick={handleCardClick}
      onMouseEnter={disabled ? undefined : handleMouseEnter}
      onMouseLeave={disabled ? undefined : handleMouseLeave}
      style={{
        backgroundColor: '#1e293b',
        border: disabled
          ? '2px solid #f59e0b'
          : isHighlighted
            ? '2px solid #818cf8'
            : '1px solid #334155',
        borderRadius: 12,
        overflow: 'hidden',
        cursor: disabled ? 'not-allowed' : 'pointer',
        display: 'flex',
        flexDirection: 'column',
        position: 'relative',
        transition: 'all 0.18s ease-in-out',
        boxShadow: disabled
          ? '0 0 16px rgba(245, 158, 11, 0.3)'
          : isHighlighted
            ? '0 0 16px rgba(129, 140, 248, 0.35)'
            : '0 2px 6px rgba(0, 0, 0, 0.25)',
        transform: (!disabled && isHovered) ? 'translateY(-2px)' : 'none',
        boxSizing: 'border-box',
        minHeight: 220,
        flexShrink: 0,
        opacity: disabled ? 0.7 : 1
      }}
    >
      {/* Processing Overlay */}
      {disabled && (
        <div style={{
          position: 'absolute',
          inset: 0,
          zIndex: 20,
          backgroundColor: 'rgba(15, 23, 42, 0.75)',
          display: 'flex',
          flexDirection: 'column',
          alignItems: 'center',
          justifyContent: 'center',
          gap: 6,
          borderRadius: 12
        }}>
          <div style={{
            width: 28,
            height: 28,
            border: '3px solid #f59e0b',
            borderTopColor: 'transparent',
            borderRadius: '50%',
            animation: 'spin 0.8s linear infinite'
          }} />
          <span style={{ fontSize: 11, color: '#fbbf24', fontWeight: 'bold' }}>⚙️ Đang Xử Lý...</span>
        </div>
      )}
      {/* 📹 Top Thumbnail Container */}
      <div
        style={{
          width: '100%',
          height: 128,
          minHeight: 128,
          flexShrink: 0,
          backgroundColor: '#0f172a',
          position: 'relative',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          overflow: 'hidden'
        }}
      >
        <Film size={32} color="#475569" style={{ position: 'absolute' }} />

        {isVisible && (
          <video
            ref={videoRef}
            src={`${mediaUrl}#t=0.5`}
            preload="metadata"
            muted
            playsInline
            onLoadedMetadata={handleLoadedMetadata}
            style={{
              width: '100%',
              height: '100%',
              objectFit: 'cover',
              position: 'relative',
              zIndex: 1,
              opacity: 0.95,
              transition: 'opacity 0.2s ease',
              backgroundColor: '#0f172a'
            }}
          />
        )}

        {/* 🔲 Top-Left: Interactive Checkmark / Checkbox Badge */}
        <div
          onClick={(e) => {
            e.stopPropagation();
            if (!disabled && onToggleCheck) onToggleCheck(file.relPath);
          }}
          title={isSelected ? "Bỏ chọn video này" : "Tick chọn video này"}
          style={{
            position: 'absolute',
            top: 8,
            left: 8,
            zIndex: 10,
            backgroundColor: isSelected ? '#6366f1' : 'rgba(15, 23, 42, 0.75)',
            backdropFilter: 'blur(4px)',
            color: '#ffffff',
            borderRadius: 6,
            width: 24,
            height: 24,
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            cursor: disabled ? 'not-allowed' : 'pointer',
            boxShadow: '0 2px 6px rgba(0,0,0,0.5)',
            border: isSelected ? '2px solid #ffffff' : '1px solid rgba(255, 255, 255, 0.4)',
            transition: 'all 0.15s ease'
          }}
        >
          {isSelected && <Check size={14} strokeWidth={3} />}
        </div>

        {/* 💾 Top-Right: Size & Cloud Status Badges */}
        <div
          style={{
            position: 'absolute',
            top: 8,
            right: 8,
            zIndex: 3,
            display: 'flex',
            alignItems: 'center',
            gap: 4
          }}
        >
          {file.cloudStatus && (
            <div
              style={{
                backgroundColor: file.cloudStatus === 'synced' ? 'rgba(16, 185, 129, 0.9)' : file.cloudStatus === 'cloud_only' ? 'rgba(59, 130, 246, 0.9)' : 'rgba(245, 158, 11, 0.9)',
                backdropFilter: 'blur(4px)',
                color: '#ffffff',
                fontSize: 10,
                fontWeight: 700,
                padding: '3px 6px',
                borderRadius: 6,
                display: 'flex',
                alignItems: 'center',
                gap: 3,
                boxShadow: '0 2px 4px rgba(0,0,0,0.3)'
              }}
              title={file.cloudStatus === 'synced' ? 'Đã đồng bộ trên GCS Cloud' : file.cloudStatus === 'cloud_only' ? 'Chỉ có trên GCS Cloud (0 Byte SSD)' : 'Chỉ có ở máy Mac'}
            >
              {file.cloudStatus === 'synced' ? '🔄 Synced' : file.cloudStatus === 'cloud_only' ? '☁️ Cloud' : '💻 Local'}
            </div>
          )}

          <div
            style={{
              backgroundColor: 'rgba(15, 23, 42, 0.85)',
              backdropFilter: 'blur(4px)',
              color: '#ffffff',
              fontSize: 11,
              fontWeight: 700,
              padding: '3px 8px',
              borderRadius: 6,
              display: 'flex',
              alignItems: 'center',
              gap: 4,
              border: '1px solid rgba(255,255,255,0.1)'
            }}
          >
            💾 {formatSizeStr(file.sizeBytes)}
          </div>
        </div>

        {/* 🏷️ Bottom-Left: SRC / OUTPUT Badge */}
        <div
          style={{
            position: 'absolute',
            bottom: 8,
            left: 8,
            zIndex: 3,
            backgroundColor: isOutput ? '#10b981' : '#6366f1',
            color: '#ffffff',
            fontSize: 10,
            fontWeight: 800,
            padding: '3px 8px',
            borderRadius: 6,
            textTransform: 'uppercase',
            letterSpacing: '0.5px',
            boxShadow: '0 2px 4px rgba(0,0,0,0.3)'
          }}
        >
          {isOutput ? '✅ OUTPUT' : '📹 SRC'}
        </div>

        {/* ⏱️ Bottom-Right: Duration Badge */}
        <div
          style={{
            position: 'absolute',
            bottom: 8,
            right: 8,
            zIndex: 3,
            backgroundColor: 'rgba(15, 23, 42, 0.85)',
            backdropFilter: 'blur(4px)',
            color: '#ffffff',
            fontSize: 11,
            fontWeight: 700,
            padding: '3px 8px',
            borderRadius: 6,
            display: 'flex',
            alignItems: 'center',
            gap: 4,
            border: '1px solid rgba(255,255,255,0.1)'
          }}
        >
          ⏱️ {formatDurationStr(duration)}
        </div>
      </div>

      {/* 📝 Meta Content & Quick Action Button */}
      <div style={{ padding: '10px 12px', flex: 1, display: 'flex', flexDirection: 'column', justifyContent: 'space-between', gap: 8 }}>
        <div>
          <div
            style={{
              color: isHighlighted ? '#818cf8' : '#ffffff',
              fontSize: 13,
              fontWeight: 700,
              whiteSpace: 'nowrap',
              overflow: 'hidden',
              textOverflow: 'ellipsis',
              lineHeight: '1.3'
            }}
            title={file.name}
          >
            {file.name}
          </div>

          <div
            style={{
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'space-between',
              fontSize: 11,
              color: '#94a3b8',
              marginTop: 5
            }}
          >
            <span>📅 {formatDateStr(file.mtime)}</span>
            <span>📐 {resolution || '1080x1920'}</span>
          </div>
        </div>

        {/* ⚡ Full-width Quick Action Button */}
        {actionLabel && (
          <button
            onClick={(e) => {
              e.stopPropagation();
              if (onAction) onAction(file.relPath);
            }}
            style={{
              width: '100%',
              backgroundColor: isHighlighted ? '#6366f1' : 'rgba(51, 65, 85, 0.6)',
              color: '#ffffff',
              border: isHighlighted ? 'none' : '1px solid #475569',
              borderRadius: 8,
              padding: '7px 10px',
              fontSize: 12,
              fontWeight: 700,
              cursor: 'pointer',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              gap: 6,
              transition: 'all 0.15s ease',
              boxShadow: isHighlighted ? '0 4px 12px rgba(99, 102, 241, 0.4)' : 'none'
            }}
            onMouseEnter={(e) => {
              if (!isHighlighted) e.currentTarget.style.backgroundColor = '#475569';
            }}
            onMouseLeave={(e) => {
              if (!isHighlighted) e.currentTarget.style.backgroundColor = 'rgba(51, 65, 85, 0.6)';
            }}
          >
            <Play size={11} fill="currentColor" />
            {actionLabel.includes('Cắt') || actionLabel.includes('Chọn') ? (
              <Scissors size={12} />
            ) : actionLabel.includes('Ghép') || actionLabel.includes('Thêm') ? (
              <Plus size={12} />
            ) : null}
            <span>{actionLabel}</span>
          </button>
        )}
      </div>
    </div>
  );
}
