import React, { useState, useRef, useEffect, forwardRef, useImperativeHandle } from 'react';
import { 
  Play, 
  Pause, 
  RotateCcw, 
  RotateCw, 
  Volume2, 
  VolumeX, 
  Maximize, 
  Minimize, 
  Subtitles, 
  Settings2,
  Film,
  Sparkles
} from 'lucide-react';
import { getMediaUrl } from '../services/api';

const formatTime = (seconds) => {
  if (seconds === null || seconds === undefined || isNaN(seconds) || seconds < 0) return '00:00:00';
  const totalSecs = Math.floor(seconds);
  const hrs = Math.floor(totalSecs / 3600);
  const mins = Math.floor((totalSecs % 3600) / 60);
  const secs = totalSecs % 60;
  if (hrs > 0) {
    return `${hrs.toString().padStart(2, '0')}:${mins.toString().padStart(2, '0')}:${secs.toString().padStart(2, '0')}`;
  }
  return `00:${mins.toString().padStart(2, '0')}:${secs.toString().padStart(2, '0')}`;
};

const VideoPlayerWithSubtitles = forwardRef(function VideoPlayerWithSubtitles({
  videoFile,
  subtitles = [],
  currentTime = 0,
  onTimeUpdate,
  onDurationChange,
  autoPlay = false
}, ref) {
  const videoRef = useRef(null);
  const containerRef = useRef(null);

  const [isPlaying, setIsPlaying] = useState(false);
  const [duration, setDuration] = useState(0);
  const [localTime, setLocalTime] = useState(0);
  const [volume, setVolume] = useState(1);
  const [isMuted, setIsMuted] = useState(false);
  const [isFullscreen, setIsFullscreen] = useState(false);
  const [showSubtitles, setShowSubtitles] = useState(true);
  const [activeSubtitle, setActiveSubtitle] = useState(null);
  const [playbackRate, setPlaybackRate] = useState(1);
  const [showSpeedMenu, setShowSpeedMenu] = useState(false);
  const [mediaError, setMediaError] = useState(null);
  const [isLoadingMedia, setIsLoadingMedia] = useState(false);

  // Expose imperative methods (seek, play, pause)
  useImperativeHandle(ref, () => ({
    seekTo: (sec) => {
      if (videoRef.current) {
        videoRef.current.currentTime = Math.max(0, Math.min(sec, duration || 9999));
        setLocalTime(videoRef.current.currentTime);
      }
    },
    play: () => {
      if (videoRef.current) {
        videoRef.current.play().catch(() => {});
      }
    },
    pause: () => {
      if (videoRef.current) {
        videoRef.current.pause();
      }
    },
    getCurrentTime: () => videoRef.current ? videoRef.current.currentTime : 0,
    getDuration: () => duration
  }));

  const mediaUrl = videoFile ? getMediaUrl(videoFile.relPath) : '';

  // Clean reset whenever switching to another video
  useEffect(() => {
    if (videoRef.current) {
      try {
        videoRef.current.pause();
        videoRef.current.currentTime = 0;
      } catch (_) {}
    }
    setIsPlaying(false);
    setLocalTime(0);
    setDuration(0);
    setActiveSubtitle(null);
    setMediaError(null);
    setIsLoadingMedia(true);

    // Auto-disable HTML5 subtitle overlay when viewing rendered output video to prevent double sub
    const isOutputFile = videoFile?.relPath?.includes('/output/') || videoFile?.relPath?.includes('_vi.');
    setShowSubtitles(!isOutputFile);

    if (onTimeUpdate) onTimeUpdate(0);
  }, [videoFile?.relPath]);

  // Find active subtitle matching localTime
  useEffect(() => {
    if (!subtitles || subtitles.length === 0 || !showSubtitles) {
      setActiveSubtitle(null);
      return;
    }
    const current = subtitles.find(s => localTime >= s.start && localTime <= s.end);
    setActiveSubtitle(current || null);
  }, [localTime, subtitles, showSubtitles]);

  const handleLoadedMetadata = () => {
    setIsLoadingMedia(false);
    if (videoRef.current) {
      const dur = videoRef.current.duration || 0;
      setDuration(dur);
      if (onDurationChange) onDurationChange(dur);
      if (autoPlay) {
        videoRef.current.play().catch(() => {});
      }
    }
  };

  const handleTimeUpdate = () => {
    if (videoRef.current) {
      const t = videoRef.current.currentTime;
      setLocalTime(t);
      if (onTimeUpdate) onTimeUpdate(t);
    }
  };

  const togglePlay = () => {
    if (!videoRef.current) return;
    if (isPlaying) {
      videoRef.current.pause();
    } else {
      videoRef.current.play().catch(err => {
        console.warn('Playback prevented or aborted:', err);
      });
    }
  };

  const handleSeekChange = (e) => {
    const val = parseFloat(e.target.value);
    if (videoRef.current) {
      videoRef.current.currentTime = val;
      setLocalTime(val);
      if (onTimeUpdate) onTimeUpdate(val);
    }
  };

  const handleSkip = (seconds) => {
    if (videoRef.current) {
      const newTime = Math.max(0, Math.min(videoRef.current.currentTime + seconds, duration));
      videoRef.current.currentTime = newTime;
      setLocalTime(newTime);
      if (onTimeUpdate) onTimeUpdate(newTime);
    }
  };

  const toggleMute = () => {
    if (!videoRef.current) return;
    videoRef.current.muted = !isMuted;
    setIsMuted(!isMuted);
  };

  const handleVolumeChange = (e) => {
    const val = parseFloat(e.target.value);
    if (videoRef.current) {
      videoRef.current.volume = val;
      setVolume(val);
      setIsMuted(val === 0);
    }
  };

  const toggleFullscreen = () => {
    if (!containerRef.current) return;
    if (!document.fullscreenElement) {
      containerRef.current.requestFullscreen().catch(() => {});
      setIsFullscreen(true);
    } else {
      document.exitFullscreen().catch(() => {});
      setIsFullscreen(false);
    }
  };

  const changePlaybackRate = (rate) => {
    if (videoRef.current) {
      videoRef.current.playbackRate = rate;
      setPlaybackRate(rate);
      setShowSpeedMenu(false);
    }
  };

  if (!videoFile) {
    return (
      <div style={styles.placeholderContainer}>
        <div style={styles.placeholderBox}>
          <Film size={40} color="var(--text-dim)" />
          <p style={{ fontSize: 14, color: 'var(--text-muted)', marginTop: 8 }}>
            Chọn một video từ thư viện bên dưới để xem và chỉnh sửa
          </p>
        </div>
      </div>
    );
  }

  return (
    <div ref={containerRef} style={styles.playerContainer}>
      {/* Video Element */}
      <div style={styles.videoWrapper} onClick={togglePlay}>
        <video
          key={videoFile?.relPath}
          ref={videoRef}
          src={mediaUrl || undefined}
          style={styles.videoElement}
          onLoadedMetadata={handleLoadedMetadata}
          onCanPlay={() => setIsLoadingMedia(false)}
          onError={() => {
            setIsLoadingMedia(false);
            setMediaError('Không thể tải luồng video');
          }}
          onTimeUpdate={handleTimeUpdate}
          onPlay={() => setIsPlaying(true)}
          onPause={() => setIsPlaying(false)}
          playsInline
        />

        {/* Subtitle Overlay Overlaying Video */}
        {showSubtitles && activeSubtitle && (
          <div className="subtitle-overlay-container">
            {activeSubtitle.text_secondary ? (
              <div className="subtitle-bilingual-container">
                <div className="subtitle-box" style={{ padding: '5px 14px' }}>
                  <div className="subtitle-trans-text">
                    {activeSubtitle.translated_text || activeSubtitle.text_vi || activeSubtitle.text}
                  </div>
                </div>
                <div className="subtitle-box" style={{ padding: '4px 12px', background: 'rgba(0, 0, 0, 0.70)' }}>
                  <div className="subtitle-secondary-text">
                    {activeSubtitle.text_secondary}
                  </div>
                </div>
              </div>
            ) : (
              <div className="subtitle-box">
                {activeSubtitle.text && !activeSubtitle.translated_text && (
                  <div className="subtitle-orig-text">
                    {activeSubtitle.text}
                  </div>
                )}
                {activeSubtitle.translated_text && (
                  <div className="subtitle-trans-text">
                    {activeSubtitle.translated_text}
                  </div>
                )}
              </div>
            )}
          </div>
        )}

        {/* Play/Pause Large Center Overlay when paused */}
        {!isPlaying && (
          <div style={styles.centerPlayOverlay}>
            <div style={styles.centerPlayBtn}>
              <Play size={24} color="#ffffff" style={{ marginLeft: 2 }} />
            </div>
          </div>
        )}
      </div>

      {/* Scrubber Progress Bar */}
      <div style={styles.progressContainer}>
        <input
          type="range"
          min="0"
          max={duration || 100}
          step="0.05"
          value={localTime}
          onChange={handleSeekChange}
          style={styles.rangeInput}
        />
      </div>

      {/* Player Controls Bar */}
      <div style={styles.controlsBar}>
        {/* Left: Play/Pause, Rewind/Forward, Timecode */}
        <div style={styles.controlGroup}>
          <button style={styles.ctrlBtn} onClick={togglePlay} title={isPlaying ? 'Tạm dừng (Space)' : 'Phát (Space)'}>
            {isPlaying ? <Pause size={17} /> : <Play size={17} />}
          </button>

          <button style={styles.ctrlBtn} onClick={() => handleSkip(-5)} title="Lùi 5s">
            <RotateCcw size={15} />
          </button>

          <button style={styles.ctrlBtn} onClick={() => handleSkip(5)} title="Tiến 5s">
            <RotateCw size={15} />
          </button>

          <div style={styles.timeDisplay}>
            <span style={styles.timeCurrent}>{formatTime(localTime)}</span>
            <span style={styles.timeDivider}>/</span>
            <span style={styles.timeDuration}>{formatTime(duration)}</span>
          </div>
        </div>

        {/* Right: Subtitles Toggle, Volume, Speed, Fullscreen */}
        <div style={styles.controlGroup}>
          <button 
            style={{
              ...styles.ctrlBtn,
              color: showSubtitles ? 'var(--accent-yellow)' : 'var(--text-dim)'
            }}
            onClick={() => setShowSubtitles(!showSubtitles)}
            title={showSubtitles ? 'Tắt phụ đề xem trước' : 'Bật phụ đề xem trước'}
          >
            <Subtitles size={16} />
          </button>

          {/* Volume */}
          <div style={styles.volumeGroup}>
            <button style={styles.ctrlBtn} onClick={toggleMute} title={isMuted ? 'Bật âm thanh' : 'Tắt tiếng'}>
              {isMuted || volume === 0 ? <VolumeX size={16} /> : <Volume2 size={16} />}
            </button>
            <input
              type="range"
              min="0"
              max="1"
              step="0.05"
              value={isMuted ? 0 : volume}
              onChange={handleVolumeChange}
              style={styles.volumeSlider}
            />
          </div>

          {/* Speed Selector */}
          <div style={{ position: 'relative' }}>
            <button 
              style={styles.speedBtn}
              onClick={() => setShowSpeedMenu(!showSpeedMenu)}
              title="Tốc độ phát"
            >
              {playbackRate}x
            </button>

            {showSpeedMenu && (
              <div style={styles.speedMenu}>
                {[0.5, 0.75, 1, 1.25, 1.5, 2].map(r => (
                  <div 
                    key={r}
                    style={{
                      ...styles.speedMenuItem,
                      fontWeight: playbackRate === r ? 700 : 400,
                      color: playbackRate === r ? 'var(--primary-light)' : 'var(--text-main)'
                    }}
                    onClick={() => changePlaybackRate(r)}
                  >
                    {r}x
                  </div>
                ))}
              </div>
            )}
          </div>

          <button style={styles.ctrlBtn} onClick={toggleFullscreen} title="Toàn màn hình">
            {isFullscreen ? <Minimize size={16} /> : <Maximize size={16} />}
          </button>
        </div>
      </div>
    </div>
  );
});

export default VideoPlayerWithSubtitles;

const styles = {
  playerContainer: {
    backgroundColor: '#000000',
    borderRadius: 'var(--radius-md)',
    overflow: 'hidden',
    display: 'flex',
    flexDirection: 'column',
    position: 'relative',
    border: '1px solid var(--border-color)',
    boxShadow: 'var(--shadow-md)',
    height: '100%',
  },
  videoWrapper: {
    flex: 1,
    position: 'relative',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: '#000000',
    cursor: 'pointer',
    minHeight: '220px',
  },
  videoElement: {
    width: '100%',
    height: '100%',
    maxHeight: '100%',
    objectFit: 'contain',
  },
  centerPlayOverlay: {
    position: 'absolute',
    top: 0,
    left: 0,
    right: 0,
    bottom: 0,
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: 'rgba(0, 0, 0, 0.3)',
    pointerEvents: 'none',
  },
  centerPlayBtn: {
    width: 52,
    height: 52,
    borderRadius: '50%',
    backgroundColor: 'rgba(59, 130, 246, 0.9)',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    boxShadow: '0 4px 16px rgba(0, 0, 0, 0.6)',
  },
  progressContainer: {
    padding: '0 10px',
    backgroundColor: 'var(--bg-card)',
    display: 'flex',
    alignItems: 'center',
    height: '14px',
  },
  rangeInput: {
    width: '100%',
    height: 4,
    accentColor: 'var(--primary)',
    cursor: 'pointer',
  },
  controlsBar: {
    height: '42px',
    backgroundColor: 'var(--bg-card)',
    borderTop: '1px solid var(--border-subtle)',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between',
    padding: '0 12px',
  },
  controlGroup: {
    display: 'flex',
    alignItems: 'center',
    gap: 8,
  },
  ctrlBtn: {
    background: 'none',
    border: 'none',
    color: 'var(--text-main)',
    padding: '4px 6px',
    borderRadius: 'var(--radius-sm)',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
  },
  timeDisplay: {
    display: 'flex',
    alignItems: 'center',
    gap: 4,
    fontSize: 12,
    fontFamily: 'monospace',
    marginLeft: 6,
  },
  timeCurrent: {
    color: 'var(--primary-light)',
    fontWeight: 600,
  },
  timeDivider: {
    color: 'var(--text-dim)',
  },
  timeDuration: {
    color: 'var(--text-dim)',
  },
  volumeGroup: {
    display: 'flex',
    alignItems: 'center',
    gap: 4,
  },
  volumeSlider: {
    width: 60,
    height: 3,
    accentColor: 'var(--primary)',
    cursor: 'pointer',
  },
  speedBtn: {
    background: 'rgba(255, 255, 255, 0.08)',
    border: '1px solid var(--border-color)',
    color: 'var(--text-main)',
    padding: '2px 6px',
    borderRadius: 'var(--radius-sm)',
    fontSize: 11,
    fontWeight: 600,
  },
  speedMenu: {
    position: 'absolute',
    bottom: 'calc(100% + 6px)',
    right: 0,
    backgroundColor: 'var(--bg-card)',
    border: '1px solid var(--border-color)',
    borderRadius: 'var(--radius-sm)',
    boxShadow: 'var(--shadow-lg)',
    padding: '4px',
    display: 'flex',
    flexDirection: 'column',
    zIndex: 100,
  },
  speedMenuItem: {
    padding: '4px 10px',
    fontSize: 11,
    cursor: 'pointer',
    borderRadius: 3,
  },
  placeholderContainer: {
    height: '100%',
    backgroundColor: 'var(--bg-card)',
    borderRadius: 'var(--radius-md)',
    border: '1px dashed var(--border-color)',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    padding: 24,
  },
  placeholderBox: {
    display: 'flex',
    flexDirection: 'column',
    alignItems: 'center',
    textAlign: 'center',
  }
};
