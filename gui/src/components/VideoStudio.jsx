import React, { useState, useRef, useEffect } from 'react';
import { Layers, Scissors, Plus, Trash2, ArrowLeft, ArrowRight, Play, Sparkles, CheckCircle2, Video, Clock, AlertCircle, Eye, Film } from 'lucide-react';
import { getMediaUrl, runScript } from '../services/api';

import CompactVideoCard from './CompactVideoCard';
import VideoTrimmer from './VideoTrimmer';

// Helper: Format seconds float to 'mm:ss' or 'hh:mm:ss' string
const formatTimeStr = (seconds) => {
  if (seconds === null || seconds === undefined || isNaN(seconds) || seconds < 0) return '00:00';
  const totalSecs = Math.floor(seconds);
  const hrs = Math.floor(totalSecs / 3600);
  const mins = Math.floor((totalSecs % 3600) / 60);
  const secs = totalSecs % 60;
  if (hrs > 0) {
    return `${hrs.toString().padStart(2, '0')}:${mins.toString().padStart(2, '0')}:${secs.toString().padStart(2, '0')}`;
  }
  return `${mins.toString().padStart(2, '0')}:${secs.toString().padStart(2, '0')}`;
};

// Helper: Format bytes to human readable size (KB/MB/GB)
const formatSizeStr = (sizeBytes) => {
  if (!sizeBytes || isNaN(sizeBytes)) return '';
  if (sizeBytes < 1024) return `${sizeBytes} B`;
  if (sizeBytes < 1024 * 1024) return `${(sizeBytes / 1024).toFixed(1)} KB`;
  if (sizeBytes < 1024 * 1024 * 1024) return `${(sizeBytes / (1024 * 1024)).toFixed(1)} MB`;
  return `${(sizeBytes / (1024 * 1024 * 1024)).toFixed(2)} GB`;
};

// Helper: Format timestamp to time string (e.g. 11:07 AM)
const formatDateStr = (mtimeMs) => {
  if (!mtimeMs) return '';
  const d = new Date(mtimeMs);
  return d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
};

export default function VideoStudio({
  project,
  srcFiles = [],
  outputFiles = [],
  initialTrimmerPath = null,
  initialSubTab = 'merge',
  onSelectTab,
  onRefresh
}) {
  const allFiles = [...srcFiles, ...outputFiles].filter(f => f.isMedia);

  const [activeSubTab, setActiveSubTab] = useState(initialSubTab || (initialTrimmerPath ? 'multicut' : 'merge')); // 'merge' | 'multicut' | 'trimmer'
  const [folderFilter, setFolderFilter] = useState('all'); // 'all' | 'src' | 'output'
  const [searchQuery, setSearchQuery] = useState('');
  const [displayLimit, setDisplayLimit] = useState(24);
  const galleryScrollRef = useRef(null);
  const sentinelRef = useRef(null);

  // Sync initialTrimmerPath to selectedCutFile when passed
  useEffect(() => {
    if (initialTrimmerPath) {
      setSelectedCutFile(initialTrimmerPath);
      setActiveSubTab(initialSubTab || 'multicut');
    }
  }, [initialTrimmerPath, initialSubTab]);

  // Filter studio files based on folder and search query
  const filteredStudioFiles = allFiles
    .filter(f => {
      if (folderFilter === 'src') return f.relPath.includes('/src/');
      if (folderFilter === 'output') return f.relPath.includes('/output/');
      return true;
    })
    .filter(f => {
      if (!searchQuery.trim()) return true;
      return f.name.toLowerCase().includes(searchQuery.toLowerCase()) || f.relPath.toLowerCase().includes(searchQuery.toLowerCase());
    });

  // Reset displayLimit on filter or search query change
  useEffect(() => {
    setDisplayLimit(24);
  }, [folderFilter, searchQuery]);

  // Infinite Scroll Observer scoped to gallery container + Scroll listener fallback
  useEffect(() => {
    const rootEl = galleryScrollRef.current;
    const targetEl = sentinelRef.current;
    if (!rootEl) return;

    let observer = null;
    if (targetEl) {
      observer = new IntersectionObserver(
        (entries) => {
          if (entries[0].isIntersecting) {
            setDisplayLimit(prev => Math.min(prev + 24, filteredStudioFiles.length));
          }
        },
        { root: rootEl, rootMargin: '250px', threshold: 0 }
      );
      observer.observe(targetEl);
    }

    const handleScroll = () => {
      if (rootEl.scrollHeight - rootEl.scrollTop - rootEl.clientHeight < 250) {
        setDisplayLimit(prev => Math.min(prev + 24, filteredStudioFiles.length));
      }
    };
    rootEl.addEventListener('scroll', handleScroll, { passive: true });

    return () => {
      if (observer && targetEl) observer.unobserve(targetEl);
      rootEl.removeEventListener('scroll', handleScroll);
    };
  }, [filteredStudioFiles.length, displayLimit]);

  // ─────────────────────────────────────────────────────────────
  // MODE 1: VIDEO MERGER STATE (Visual Storyboard & Hero Player)
  // ─────────────────────────────────────────────────────────────
  const [selectedMergeFiles, setSelectedMergeFiles] = useState([]);
  const [previewMergePath, setPreviewMergePath] = useState(allFiles[0]?.relPath || '');
  const [customMergeOutput, setCustomMergeOutput] = useState('');

  // ─────────────────────────────────────────────────────────────
  // MODE 2: MULTI-CUT STATE (Timeline Handles + Default Override)
  // ─────────────────────────────────────────────────────────────
  const [selectedCutFile, setSelectedCutFile] = useState(initialTrimmerPath || allFiles[0]?.relPath || '');
  const [duration, setDuration] = useState(0);
  const [startTime, setStartTime] = useState(0);
  const [endTime, setEndTime] = useState(0);
  const [activeThumb, setActiveThumb] = useState('start');

  const [removeRanges, setRemoveRanges] = useState([]);
  const [isOverwriting, setIsOverwriting] = useState(true); // Default TRUE: Override original video file
  const [customCutOutput, setCustomCutOutput] = useState(allFiles[0]?.relPath || '');

  const [isProcessing, setIsProcessing] = useState(false);
  const [processingRelPaths, setProcessingRelPaths] = useState(new Set());

  const heroMergeVideoRef = useRef(null);
  const cutVideoRef = useRef(null);

  // Auto suggest output name for merger (New file default)
  useEffect(() => {
    if (selectedMergeFiles.length === 0) return;
    const firstFile = selectedMergeFiles[0];
    fetch('/api/suggest-concat-name', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ inputPath: firstFile })
    })
      .then(res => res.json())
      .then(data => {
        if (data.success && data.suggestedPath) {
          setCustomMergeOutput(data.suggestedPath);
        }
      })
      .catch(err => console.error(err));
  }, [selectedMergeFiles]);

  // Update multi-cut output path when selected video or overwrite checkbox changes
  useEffect(() => {
    if (!selectedCutFile) return;
    if (isOverwriting) {
      setCustomCutOutput(selectedCutFile);
    } else {
      fetch('/api/suggest-trim-name', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ inputPath: selectedCutFile })
      })
        .then(res => res.json())
        .then(data => {
          if (data.success && data.suggestedPath) {
            setCustomCutOutput(data.suggestedPath);
          }
        })
        .catch(err => console.error(err));
    }
  }, [selectedCutFile, isOverwriting]);

  // Handle Video Metadata Loaded in Multi-Cut Tab
  const handleLoadedCutMetadata = () => {
    if (cutVideoRef.current) {
      const dur = cutVideoRef.current.duration;
      setDuration(dur);
      setStartTime(0);
      setEndTime(Math.min(dur, 10)); // Default 10s selection preview
    }
  };

  // Timeline handle change handlers for Multi-Cut
  const handleStartSliderChange = (e) => {
    const val = parseFloat(e.target.value) || 0;
    const boundedStart = Math.min(val, Math.max(0, endTime - 0.5));
    setStartTime(boundedStart);
    if (cutVideoRef.current) cutVideoRef.current.currentTime = boundedStart;
  };

  const handleEndSliderChange = (e) => {
    const val = parseFloat(e.target.value) || 0;
    const maxDur = duration > 0 ? duration : val;
    const boundedEnd = Math.min(maxDur, Math.max(val, startTime + 0.5));
    setEndTime(boundedEnd);
    if (cutVideoRef.current) cutVideoRef.current.currentTime = boundedEnd;
  };

  // Mode 1 Handlers: File selection list
  const toggleSelectMergeFile = (relPath) => {
    if (selectedMergeFiles.includes(relPath)) {
      setSelectedMergeFiles(selectedMergeFiles.filter(p => p !== relPath));
    } else {
      setSelectedMergeFiles([...selectedMergeFiles, relPath]);
      setPreviewMergePath(relPath);
    }
  };

  const moveMergeFile = (index, direction) => {
    const newArr = [...selectedMergeFiles];
    const targetIdx = index + direction;
    if (targetIdx < 0 || targetIdx >= newArr.length) return;
    const temp = newArr[index];
    newArr[index] = newArr[targetIdx];
    newArr[targetIdx] = temp;
    setSelectedMergeFiles(newArr);
  };

  const handleExecuteMerge = async () => {
    if (selectedMergeFiles.length < 2) return;
    const args = [...selectedMergeFiles];
    if (customMergeOutput) args.push('-o', customMergeOutput);

    const pathsBeingProcessed = new Set(selectedMergeFiles);
    setIsProcessing(true);
    setProcessingRelPaths(pathsBeingProcessed);
    try {
      await runScript('concat.py', args, `merge_${Date.now()}`);
      await new Promise(r => setTimeout(r, 800));
      if (onRefresh) onRefresh();
    } catch (e) {
      console.error('Merge failed:', e);
    } finally {
      setIsProcessing(false);
      setProcessingRelPaths(new Set());
    }
  };

  // Mode 2 Handlers: Multi-Cut Timeline Range Add/Remove
  const handleAddCurrentRangeAsTrash = () => {
    if (endTime <= startTime) return;
    const newRange = {
      startSec: startTime,
      endSec: endTime,
      startStr: formatTimeStr(startTime),
      endStr: formatTimeStr(endTime)
    };
    setRemoveRanges([...removeRanges, newRange]);
  };

  const removeRemoveRangeItem = (index) => {
    setRemoveRanges(removeRanges.filter((_, idx) => idx !== index));
  };

  const handleExecuteMultiCut = async () => {
    if (!selectedCutFile || removeRanges.length === 0) return;

    const removeArgs = removeRanges.map(r => `${formatTimeStr(r.startSec)}-${formatTimeStr(r.endSec)}`);
    const args = [selectedCutFile, '--remove', ...removeArgs];
    if (customCutOutput) args.push('-o', customCutOutput);

    setIsProcessing(true);
    setProcessingRelPaths(new Set([selectedCutFile]));
    try {
      await runScript('concat.py', args, `multicut_${Date.now()}`);
      await new Promise(r => setTimeout(r, 800));
      if (onRefresh) onRefresh();
      // Re-suggest output name for next operation
      if (!isOverwriting && selectedCutFile) {
        fetch('/api/suggest-trim-name', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ inputPath: selectedCutFile })
        })
          .then(r => r.json())
          .then(d => { if (d.success && d.suggestedPath) setCustomCutOutput(d.suggestedPath); })
          .catch(() => {});
      }
    } catch (e) {
      console.error('Multi-cut failed:', e);
    } finally {
      setIsProcessing(false);
      setProcessingRelPaths(new Set());
    }
  };

  const heroMergeUrl = previewMergePath ? getMediaUrl(previewMergePath) : '';
  const cutVideoUrl = selectedCutFile ? getMediaUrl(selectedCutFile) : '';
  const startPercent = duration > 0 ? (startTime / duration) * 100 : 0;
  const endPercent = duration > 0 ? (endTime / duration) * 100 : 100;

  return (
    <div style={styles.container}>
      <style>{`
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

        .video-card-hover {
          transition: transform 0.18s ease, border-color 0.18s ease, box-shadow 0.18s ease;
        }
        .video-card-hover:hover {
          transform: translateY(-2px);
          border-color: #6366f1 !important;
          box-shadow: 0 8px 20px rgba(99, 102, 241, 0.25);
        }
      `}</style>

      <div style={styles.header}>
        <div>
          <h2 style={styles.title}>🎬 Sub-Video Studio (Ghép Video & Cắt Đoạn Rác)</h2>
          <p style={styles.subtitle}>Thiết kế Storyboard trực quan với Video Thumbnail thực tế & Màn hình xem trước chuyên nghiệp</p>
        </div>
      </div>

      {/* Sub-Tab Selector */}
      <div style={styles.subTabNav}>
        <button
          style={{
            ...styles.subTabBtn,
            ...(activeSubTab === 'merge' ? styles.subTabBtnActive : {})
          }}
          onClick={() => setActiveSubTab('merge')}
        >
          <Film size={18} style={{ marginRight: 8 }} />
          Ghép Nhiều Video (Filmstrip Storyboard)
        </button>
        <button
          style={{
            ...styles.subTabBtn,
            ...(activeSubTab === 'multicut' ? styles.subTabBtnActive : {})
          }}
          onClick={() => setActiveSubTab('multicut')}
        >
          <Scissors size={18} style={{ marginRight: 8 }} />
          Cắt Loại Bỏ Đoạn Rác (Multi-Cut Removal)
        </button>
        <button
          style={{
            ...styles.subTabBtn,
            ...(activeSubTab === 'trimmer' ? styles.subTabBtnActive : {})
          }}
          onClick={() => setActiveSubTab('trimmer')}
        >
          <Clock size={18} style={{ marginRight: 8 }} />
          Cắt Video (Video Trimmer)
        </button>
      </div>

      {/* ─────────────────────────────────────────────────────────────
          UNIFIED 2-COLUMN STUDIO LAYOUT (Shared Left Panel + Dynamic Right Subtabs)
         ───────────────────────────────────────────────────────────── */}
      <div style={styles.contentGrid}>
        {/* SHARED LEFT COLUMN: Video Library Visual Card Grid (Mounted ONCE for ALL subtabs) */}
        <div style={styles.card}>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 10, marginBottom: 12 }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
              <h3 style={styles.cardTitle}>📁 Kho Video Dự Án ({allFiles.length})</h3>
              <select
                value={folderFilter}
                onChange={e => setFolderFilter(e.target.value)}
                style={{
                  backgroundColor: '#0f172a',
                  color: '#f8fafc',
                  border: '1px solid #6366f1',
                  borderRadius: 6,
                  padding: '6px 12px',
                  fontSize: 12,
                  fontWeight: 'bold',
                  outline: 'none',
                  cursor: 'pointer'
                }}
              >
                <option value="all">📁 Tất cả kho ({allFiles.length} video)</option>
                <option value="src">📹 Kho Video Gốc (`src/` - {srcFiles.filter(f => f.isMedia).length} video)</option>
                <option value="output">✅ Kho Video Kết Quả (`output/` - {outputFiles.filter(f => f.isMedia).length} video)</option>
              </select>
            </div>

            {/* Search Box Filter */}
            <input
              type="text"
              value={searchQuery}
              onChange={e => setSearchQuery(e.target.value)}
              placeholder="🔍 Tìm nhanh tên video..."
              style={{
                backgroundColor: '#0f172a',
                color: '#f8fafc',
                border: '1px solid #475569',
                borderRadius: 6,
                padding: '7px 12px',
                fontSize: 12,
                outline: 'none',
                width: '100%',
                boxSizing: 'border-box'
              }}
            />
          </div>

          <div ref={galleryScrollRef} style={styles.compactLibraryGrid}>
            {filteredStudioFiles
              .slice(0, displayLimit)
              .map(f => {
                const isSelectedInMerge = selectedMergeFiles.includes(f.relPath);
                const isSelectedInCut = selectedCutFile === f.relPath;
                const isPreviewingMerge = previewMergePath === f.relPath;

                const isSelected = activeSubTab === 'merge' ? isSelectedInMerge : isSelectedInCut;
                const isActivePreview = activeSubTab === 'merge' ? isPreviewingMerge : isSelectedInCut;

                return (
                  <CompactVideoCard
                    key={f.relPath}
                    file={f}
                    isSelected={isSelected}
                    isActivePreview={isActivePreview}
                    disabled={processingRelPaths.has(f.relPath)}
                    onSelect={(relPath) => {
                      if (isProcessing && processingRelPaths.has(relPath)) return;
                      if (activeSubTab === 'merge') {
                        setPreviewMergePath(relPath);
                      } else {
                        setSelectedCutFile(relPath);
                      }
                    }}
                    onToggleCheck={(relPath) => {
                      if (isProcessing && processingRelPaths.has(relPath)) return;
                      if (activeSubTab === 'merge') {
                        toggleSelectMergeFile(relPath);
                      } else {
                        setSelectedCutFile(relPath);
                      }
                    }}
                    actionLabel={
                      processingRelPaths.has(f.relPath)
                        ? '⚙️ Đang xử lý...'
                        : activeSubTab === 'merge'
                          ? (isSelectedInMerge ? 'Bỏ chọn' : 'Ghép video')
                          : (isSelectedInCut ? 'Đang chọn' : 'Chọn video')
                    }
                    onAction={(relPath) => {
                      if (isProcessing && processingRelPaths.has(relPath)) return;
                      if (activeSubTab === 'merge') {
                        toggleSelectMergeFile(relPath);
                      } else {
                        setSelectedCutFile(relPath);
                      }
                    }}
                  />
                );
              })}

            {/* Auto Infinite Scroll Sentinel & Load More Fallback */}
            {displayLimit < filteredStudioFiles.length && (
              <div ref={sentinelRef} style={{ gridColumn: '1 / -1', padding: '12px 0', textAlign: 'center' }}>
                <button
                  type="button"
                  onClick={() => setDisplayLimit(prev => Math.min(prev + 24, filteredStudioFiles.length))}
                  style={{
                    backgroundColor: '#1e293b',
                    color: '#94a3b8',
                    border: '1px solid #334155',
                    borderRadius: 8,
                    padding: '8px 16px',
                    fontSize: 12,
                    cursor: 'pointer',
                    display: 'inline-flex',
                    alignItems: 'center',
                    gap: 6,
                    transition: 'all 0.15s ease'
                  }}
                  onMouseEnter={e => { e.currentTarget.style.borderColor = '#6366f1'; e.currentTarget.style.color = '#f8fafc'; }}
                  onMouseLeave={e => { e.currentTarget.style.borderColor = '#334155'; e.currentTarget.style.color = '#94a3b8'; }}
                >
                  <span>⏳ Tự động tải thêm ({Math.min(displayLimit, filteredStudioFiles.length)}/{filteredStudioFiles.length})</span>
                  <span style={{ color: '#818cf8', fontWeight: 'bold' }}>• Bấm để tải ngay</span>
                </button>
              </div>
            )}
          </div>
        </div>

        {/* DYNAMIC RIGHT COLUMN (Switches instantly based on activeSubTab) */}
        <div style={{ display: 'flex', flexDirection: 'column', gap: 16, flex: 1, minWidth: 0 }}>

          {/* ─────────────────────────────────────────────────────────────
              MODE 1: VIDEO MERGER (Hero Player + Storyboard Reel)
             ───────────────────────────────────────────────────────────── */}
          {activeSubTab === 'merge' && (
            <>
              {/* Top: Hero Inspector Player */}
              <div style={styles.heroPlayerCard}>
                <div style={styles.heroHeader}>
                  <Eye size={16} color="#818cf8" />
                  <span style={{ fontSize: 13, fontWeight: 'bold', color: '#f8fafc', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                    Xem Trước: {previewMergePath ? previewMergePath.split('/').pop() : 'Chưa chọn'}
                  </span>
                </div>
                {heroMergeUrl ? (
                  <video
                    ref={heroMergeVideoRef}
                    src={heroMergeUrl}
                    controls
                    key={previewMergePath}
                    style={styles.heroVideo}
                  />
                ) : (
                  <div style={styles.noVideo}>Bấm chọn bất kỳ video nào bên trái để xem trước</div>
                )}
              </div>

              {/* Bottom: Storyboard Reel (Ordered Merge Sequence) */}
              <div style={styles.reelCard}>
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                  <h3 style={styles.cardTitle}>🎬 Chuỗi Video Nối (Storyboard Reel - {selectedMergeFiles.length} clip)</h3>
                  {selectedMergeFiles.length > 0 && (
                    <button
                      style={styles.btnClearAll}
                      onClick={() => setSelectedMergeFiles([])}
                    >
                      Bỏ chọn tất cả
                    </button>
                  )}
                </div>

                {selectedMergeFiles.length === 0 ? (
                  <div style={styles.emptyNotice}>
                    <Film size={28} style={{ marginBottom: 8, color: '#6366f1' }} />
                    <br />
                    <b>Chưa chọn video nào để ghép</b>
                    <br />
                    <span style={{ fontSize: 12, color: '#94a3b8' }}>Tích chọn các video trong Kho bên trái để tạo chuỗi phim nối</span>
                  </div>
                ) : (
                  <div style={styles.reelStrip}>
                    {selectedMergeFiles.map((relPath, index) => {
                      const fileObj = allFiles.find(f => f.relPath === relPath);
                      const isFirst = index === 0;
                      const isLast = index === selectedMergeFiles.length - 1;

                      return (
                        <div key={relPath} style={styles.reelItemCard}>
                          <div style={styles.reelBadge}>#{index + 1}</div>
                          <div style={styles.reelThumbWrapper}>
                            {fileObj && (
                              <img
                                src={`/api/thumbnail?path=${encodeURIComponent(relPath)}`}
                                alt=""
                                style={styles.reelThumbImg}
                                onError={(e) => { e.target.style.display = 'none'; }}
                              />
                            )}
                            <button
                              style={styles.reelRemoveBtn}
                              onClick={() => toggleSelectMergeFile(relPath)}
                              title="Loại khỏi danh sách ghép"
                            >
                              <X size={12} />
                            </button>
                          </div>

                          <div style={styles.reelInfo}>
                            <span style={styles.reelFilename}>{fileObj ? fileObj.name : relPath.split('/').pop()}</span>
                            <div style={styles.reelReorderBtns}>
                              <button
                                style={{ ...styles.btnReorder, opacity: isFirst ? 0.3 : 1 }}
                                disabled={isFirst}
                                onClick={() => moveMergeFile(index, -1)}
                                title="Đẩy sang trái"
                              >
                                ◀
                              </button>
                              <button
                                style={{ ...styles.btnReorder, opacity: isLast ? 0.3 : 1 }}
                                disabled={isLast}
                                onClick={() => moveMergeFile(index, 1)}
                                title="Đẩy sang phải"
                              >
                                ▶
                              </button>
                            </div>
                          </div>
                        </div>
                      );
                    })}
                  </div>
                )}

                {/* Output Path & Execution Form */}
                <div style={{ marginTop: 16, display: 'flex', flexDirection: 'column', gap: 12 }}>
                  <div style={styles.formGroup}>
                    <label style={styles.label}>Đường Dẫn & Tên File Video Kết Quả Mới (`-o`):</label>
                    <input
                      type="text"
                      value={customMergeOutput}
                      onChange={e => setCustomMergeOutput(e.target.value)}
                      placeholder="assets/project/src/video_merged_1.mp4"
                      style={styles.textInput}
                    />
                  </div>

                  <button
                    style={styles.btnExecute}
                    onClick={handleExecuteMerge}
                    disabled={isProcessing || selectedMergeFiles.length < 2}
                  >
                    <Layers size={18} style={{ marginRight: 8 }} />
                    {isProcessing ? 'Đang Xử Lý Ghép Video...' : `Bắt Đầu Ghép ${selectedMergeFiles.length} Video (Tạo File Mới)`}
                  </button>
                </div>
              </div>
            </>
          )}

          {/* ─────────────────────────────────────────────────────────────
              MODE 2: MULTI-CUT SEGMENT REMOVAL (Interactive Timeline + Override)
             ───────────────────────────────────────────────────────────── */}
          {activeSubTab === 'multicut' && (
            <div style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
              {/* Top: Video Player & Dual Slider */}
              <div style={styles.card}>
                {cutVideoUrl ? (
                  <video
                    ref={cutVideoRef}
                    src={cutVideoUrl}
                    controls
                    onLoadedMetadata={handleLoadedCutMetadata}
                    style={styles.videoPlayer}
                  />
                ) : (
                  <div style={styles.noVideo}>Vui lòng chọn 1 video để xem trước</div>
                )}

                {/* 🎛️ Dual-Handle Interactive Timeline Slider */}
                {duration > 0 && (
                  <div style={styles.timelineBox}>
                    <div style={styles.timelineHeader}>
                      <span style={styles.timelineBadge}>⏱️ Khoảng Rác Đang Chọn: {formatTimeStr(startTime)} ➔ {formatTimeStr(endTime)}</span>
                      <button style={styles.btnAddTrashBtn} onClick={handleAddCurrentRangeAsTrash}>
                        <Plus size={14} style={{ marginRight: 4 }} /> Thêm Khoảng Rác Này
                      </button>
                    </div>

                    <div style={styles.rangeSliderContainer}>
                      {/* Track Background */}
                      <div style={styles.trackBackground} />

                      {/* 🔴 Visual Red Overlay Bars for Marked Trash Segments */}
                      {removeRanges.map((r, idx) => {
                        const rStartPct = (r.startSec / duration) * 100;
                        const rWidthPct = ((r.endSec - r.startSec) / duration) * 100;
                        return (
                          <div
                            key={idx}
                            title={`Đoạn rác #${idx + 1}: ${r.startStr} -> ${r.endStr}`}
                            style={{
                              position: 'absolute',
                              left: `${rStartPct}%`,
                              width: `${Math.max(0.5, rWidthPct)}%`,
                              height: 10,
                              backgroundColor: 'rgba(239, 68, 68, 0.85)',
                              borderRadius: 3,
                              top: 13,
                              zIndex: 2,
                              border: '1px solid #ef4444'
                            }}
                          />
                        );
                      })}

                      {/* Current Active Selection Highlight */}
                      <div
                        style={{
                          ...styles.trackHighlight,
                          left: `${startPercent}%`,
                          width: `${Math.max(0, endPercent - startPercent)}%`
                        }}
                      />

                      {/* Range Input Start */}
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

                      {/* Range Input End */}
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

                    <div style={{ fontSize: 11, color: '#94a3b8', display: 'flex', justifyContent: 'space-between' }}>
                      <span>Kéo mút để chọn khoảng rác, dải đỏ = đoạn sẽ bị cắt bỏ</span>
                      <span>Tổng: {formatTimeStr(duration)}</span>
                    </div>
                  </div>
                )}
              </div>

              {/* Bottom: Remove Ranges List & Override Settings */}
              <div style={styles.card}>
                <h3 style={styles.cardTitle}>Danh Sách Các Khoảng Rác Đã Chọn ({removeRanges.length} đoạn)</h3>

                {removeRanges.length === 0 ? (
                  <div style={styles.emptyNotice}>
                    <Scissors size={28} style={{ marginBottom: 8, color: '#ef4444' }} />
                    <br />
                    Chưa có đoạn rác nào. Hãy kéo mút Timeline phía trên và bấm <b>"Thêm Khoảng Rác Này"</b>
                  </div>
                ) : (
                  <div style={styles.rangeListScroll}>
                    {removeRanges.map((range, idx) => (
                      <div key={idx} style={styles.rangeListItem}>
                        <span style={styles.trashBadge}>🔴 Đoạn rác #{idx + 1}</span>
                        <span style={{ fontSize: 13, fontWeight: 'bold', color: '#f8fafc', flex: 1 }}>
                          {range.startStr} ➔ {range.endStr} ({Math.max(0, range.endSec - range.startSec).toFixed(1)}s)
                        </span>
                        <button
                          style={styles.btnDeleteRange}
                          onClick={() => removeRemoveRangeItem(idx)}
                          title="Xóa đoạn này"
                        >
                          <Trash2 size={14} />
                        </button>
                      </div>
                    ))}
                  </div>
                )}

                {/* Default Override Checkbox */}
                <div style={styles.checkboxGroup}>
                  <label style={styles.checkboxLabel}>
                    <input
                      type="checkbox"
                      checked={isOverwriting}
                      onChange={e => setIsOverwriting(e.target.checked)}
                      style={{ width: 16, height: 16, cursor: 'pointer' }}
                    />
                    <span style={{ fontWeight: 'bold', color: '#f8fafc' }}>
                      Ghi đè trực tiếp lên file video cũ (`--overwrite`)
                    </span>
                  </label>
                  <p style={styles.hint}>Ưu tiên ghi đè file gốc để tiết kiệm bộ nhớ. Bỏ tích nếu muốn lưu thành file mới.</p>
                </div>

                <div style={styles.formGroup}>
                  <label style={styles.label}>Đường Dẫn File Kết Quả (`-o`):</label>
                  <input
                    type="text"
                    value={customCutOutput}
                    onChange={e => setCustomCutOutput(e.target.value)}
                    placeholder="assets/project/src/video_001.mp4"
                    style={{ ...styles.textInput, borderColor: isOverwriting ? '#ef4444' : '#475569' }}
                  />
                </div>

                <button
                  style={{
                    ...styles.btnExecute,
                    backgroundColor: isOverwriting ? '#dc2626' : '#6366f1'
                  }}
                  onClick={handleExecuteMultiCut}
                  disabled={isProcessing || !selectedCutFile || removeRanges.length === 0}
                >
                  <Scissors size={18} style={{ marginRight: 8 }} />
                  {isProcessing ? 'Đang Xử Lý Cắt Rác & Nối Video...' : `Bắt Đầu Cắt Bỏ ${removeRanges.length} Đoạn Rác (${isOverwriting ? 'Ghi Đè' : 'Lưu File Mới'})`}
                </button>
              </div>
            </div>
          )}

          {/* ─────────────────────────────────────────────────────────────
              MODE 3: VIDEO TRIMMER (Embedded Subtab)
             ───────────────────────────────────────────────────────────── */}
          {activeSubTab === 'trimmer' && (
            <VideoTrimmer
              initialVideoPath={initialTrimmerPath}
              project={project}
              srcFiles={srcFiles}
              outputFiles={outputFiles}
              onSelectTab={onSelectTab}
              onRefresh={onRefresh}
              embedded={true}
              embeddedControlsOnly={true}
            />
          )}

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
    marginBottom: 16
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
  subTabNav: {
    display: 'flex',
    gap: 12,
    marginBottom: 20,
    borderBottom: '1px solid #334155',
    paddingBottom: 12
  },
  subTabBtn: {
    backgroundColor: '#1e293b',
    color: '#94a3b8',
    border: '1px solid #334155',
    borderRadius: 8,
    padding: '10px 18px',
    fontSize: 14,
    fontWeight: 'bold',
    cursor: 'pointer',
    display: 'flex',
    alignItems: 'center'
  },
  subTabBtnActive: {
    backgroundColor: '#6366f1',
    color: '#ffffff',
    borderColor: '#6366f1'
  },
  heroGrid: {
    display: 'grid',
    gridTemplateColumns: '1.2fr 1fr',
    gap: 20
  },
  heroPlayerCard: {
    backgroundColor: '#1e293b',
    borderRadius: 12,
    padding: 14,
    border: '1px solid #334155',
    display: 'flex',
    flexDirection: 'column',
    gap: 10
  },
  heroHeader: {
    display: 'flex',
    alignItems: 'center',
    gap: 8,
    paddingBottom: 6,
    borderBottom: '1px solid #334155'
  },
  heroVideo: {
    width: '100%',
    maxHeight: 300,
    borderRadius: 8,
    backgroundColor: '#000'
  },
  reelCard: {
    backgroundColor: '#1e293b',
    borderRadius: 12,
    padding: 16,
    border: '1px solid #334155',
    display: 'flex',
    flexDirection: 'column',
    gap: 12
  },
  emptyReelBox: {
    flex: 1,
    minHeight: 180,
    backgroundColor: '#0f172a',
    borderRadius: 10,
    border: '2px dashed #334155',
    display: 'flex',
    flexDirection: 'column',
    alignItems: 'center',
    justifyContent: 'center',
    padding: 20
  },
  reelScrollRow: {
    display: 'flex',
    gap: 12,
    overflowX: 'auto',
    paddingBottom: 8,
    minHeight: 190
  },
  reelThumbCard: {
    flexShrink: 0,
    width: 140,
    backgroundColor: '#0f172a',
    borderRadius: 8,
    border: '1px solid #334155',
    padding: 8,
    position: 'relative',
    display: 'flex',
    flexDirection: 'column',
    gap: 6,
    cursor: 'pointer'
  },
  reelThumbCardActive: {
    borderColor: '#6366f1',
    boxShadow: '0 0 10px rgba(99, 102, 241, 0.4)'
  },
  reelIndexBadge: {
    position: 'absolute',
    top: 12,
    left: 12,
    backgroundColor: '#6366f1',
    color: '#fff',
    fontSize: 10,
    fontWeight: 'bold',
    padding: '2px 6px',
    borderRadius: 4,
    zIndex: 3
  },
  reelVideoBox: {
    position: 'relative',
    width: '100%',
    height: 90,
    borderRadius: 6,
    overflow: 'hidden',
    backgroundColor: '#000'
  },
  reelVideoThumb: {
    width: '100%',
    height: '100%',
    objectFit: 'cover'
  },
  reelPlayOverlay: {
    position: 'absolute',
    inset: 0,
    backgroundColor: 'rgba(0,0,0,0.3)',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center'
  },
  reelFileName: {
    fontSize: 11,
    fontWeight: 'bold',
    color: '#f8fafc',
    overflow: 'hidden',
    textOverflow: 'ellipsis',
    whiteSpace: 'nowrap'
  },
  reelActionRow: {
    display: 'flex',
    gap: 4,
    marginTop: 'auto'
  },
  btnReelArrow: {
    backgroundColor: '#334155',
    color: '#e2e8f0',
    border: 'none',
    borderRadius: 4,
    flex: 1,
    padding: '4px 0',
    cursor: 'pointer',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center'
  },
  btnReelDelete: {
    backgroundColor: 'rgba(239, 68, 68, 0.2)',
    color: '#ef4444',
    border: '1px solid rgba(239, 68, 68, 0.4)',
    borderRadius: 4,
    width: 26,
    padding: '4px 0',
    cursor: 'pointer',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center'
  },
  btnClearAll: {
    backgroundColor: 'transparent',
    color: '#94a3b8',
    border: '1px solid #475569',
    borderRadius: 6,
    padding: '4px 10px',
    fontSize: 11,
    cursor: 'pointer'
  },
  libraryGrid: {
    display: 'grid',
    gridTemplateColumns: 'repeat(auto-fill, minmax(200px, 1fr))',
    gap: 14,
    maxHeight: 400,
    overflowY: 'auto',
    paddingRight: 4
  },
  videoGridCard: {
    backgroundColor: '#1e293b',
    borderRadius: 12,
    border: '1px solid #334155',
    overflow: 'hidden',
    cursor: 'pointer',
    display: 'flex',
    flexDirection: 'column',
    transition: 'all 0.2s ease'
  },
  videoGridCardSelected: {
    borderColor: '#6366f1',
    boxShadow: '0 0 0 2px #6366f1',
    backgroundColor: 'rgba(99, 102, 241, 0.15)'
  },
  gridThumbContainer: {
    position: 'relative',
    width: '100%',
    height: 220,
    backgroundColor: '#0f172a',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    overflow: 'hidden'
  },
  gridVideoThumb: {
    width: '100%',
    height: '100%',
    objectFit: 'cover'
  },
  gridCheckboxBox: {
    position: 'absolute',
    top: 10,
    left: 10,
    backgroundColor: 'rgba(15, 23, 42, 0.85)',
    borderRadius: 6,
    padding: 6,
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    backdropFilter: 'blur(4px)',
    zIndex: 2
  },
  gridBadgeTagTopRight: {
    position: 'absolute',
    top: 10,
    right: 10,
    backgroundColor: 'rgba(15, 23, 42, 0.85)',
    color: '#f8fafc',
    fontSize: 11,
    fontWeight: 'bold',
    padding: '4px 8px',
    borderRadius: 6,
    backdropFilter: 'blur(4px)',
    zIndex: 2
  },
  gridBadgeTagBottomLeft: {
    position: 'absolute',
    bottom: 10,
    left: 10,
    backgroundColor: 'rgba(15, 23, 42, 0.85)',
    color: '#f8fafc',
    fontSize: 11,
    fontWeight: 'bold',
    padding: '4px 8px',
    borderRadius: 6,
    backdropFilter: 'blur(4px)',
    zIndex: 2
  },
  gridBadgeTagBottomRight: {
    position: 'absolute',
    bottom: 10,
    right: 10,
    backgroundColor: 'rgba(15, 23, 42, 0.85)',
    color: '#f8fafc',
    fontSize: 11,
    fontWeight: 'bold',
    padding: '4px 8px',
    borderRadius: 6,
    backdropFilter: 'blur(4px)',
    zIndex: 2
  },
  gridMetaBox: {
    padding: '12px 14px',
    display: 'flex',
    flexDirection: 'column',
    gap: 4
  },
  gridTitle: {
    fontSize: 14,
    fontWeight: 'bold',
    color: '#f8fafc',
    overflow: 'hidden',
    textOverflow: 'ellipsis',
    whiteSpace: 'nowrap'
  },
  gridPath: {
    fontSize: 11,
    color: '#64748b',
    overflow: 'hidden',
    textOverflow: 'ellipsis',
    whiteSpace: 'nowrap'
  },
  compactLibraryGrid: {
    display: 'grid',
    gridTemplateColumns: 'repeat(2, minmax(0, 1fr))',
    gap: 10,
    maxHeight: 'calc(100vh - 280px)',
    overflowY: 'auto',
    paddingRight: 4,
    flex: 1,
    minHeight: 0
  },
  libraryGridVertical: {
    display: 'grid',
    gridTemplateColumns: 'repeat(auto-fill, minmax(210px, 1fr))',
    gap: 16,
    maxHeight: 720,
    overflowY: 'auto',
    paddingRight: 6
  },
  contentGrid: {
    display: 'grid',
    gridTemplateColumns: '1fr 1fr',
    gap: 20,
    alignItems: 'start'
  },
  card: {
    backgroundColor: '#1e293b',
    borderRadius: 12,
    padding: 18,
    border: '1px solid #334155',
    display: 'flex',
    flexDirection: 'column',
    gap: 14
  },
  cardTitle: {
    fontSize: 15,
    fontWeight: 'bold',
    margin: 0,
    color: '#f8fafc'
  },
  emptyNotice: {
    padding: 30,
    textAlign: 'center',
    color: '#64748b',
    fontSize: 13,
    backgroundColor: '#0f172a',
    borderRadius: 8
  },
  formGroup: {
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
  textInput: {
    backgroundColor: '#0f172a',
    color: '#f8fafc',
    border: '1px solid #475569',
    borderRadius: 8,
    padding: '8px 12px',
    fontSize: 14,
    outline: 'none'
  },
  btnExecute: {
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
    marginTop: 8
  },
  videoPlayer: {
    width: '100%',
    maxHeight: 320,
    borderRadius: 8,
    backgroundColor: '#000'
  },
  noVideo: {
    height: 200,
    backgroundColor: '#0f172a',
    borderRadius: 8,
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    color: '#64748b',
    fontSize: 13
  },
  timelineBox: {
    backgroundColor: '#0f172a',
    padding: 14,
    borderRadius: 10,
    border: '1px solid #334155',
    display: 'flex',
    flexDirection: 'column',
    gap: 10
  },
  timelineHeader: {
    display: 'flex',
    justifyContent: 'space-between',
    alignItems: 'center'
  },
  timelineBadge: {
    fontSize: 13,
    fontWeight: 'bold',
    color: '#ef4444'
  },
  btnAddTrashBtn: {
    backgroundColor: '#ef4444',
    color: '#ffffff',
    border: 'none',
    borderRadius: 6,
    padding: '6px 12px',
    fontSize: 12,
    fontWeight: 'bold',
    cursor: 'pointer',
    display: 'flex',
    alignItems: 'center'
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
    backgroundColor: 'rgba(99, 102, 241, 0.4)',
    borderRadius: 4,
    top: 14,
    zIndex: 1
  },
  rangeListScroll: {
    maxHeight: 240,
    overflowY: 'auto',
    display: 'flex',
    flexDirection: 'column',
    gap: 8
  },
  rangeListItem: {
    display: 'flex',
    alignItems: 'center',
    gap: 10,
    backgroundColor: '#0f172a',
    padding: '10px 12px',
    borderRadius: 8,
    border: '1px solid rgba(239, 68, 68, 0.4)'
  },
  trashBadge: {
    fontSize: 12,
    fontWeight: 'bold',
    color: '#ef4444',
    whiteSpace: 'nowrap'
  },
  btnDeleteRange: {
    backgroundColor: 'rgba(239, 68, 68, 0.15)',
    color: '#ef4444',
    border: '1px solid rgba(239, 68, 68, 0.3)',
    borderRadius: 6,
    padding: 6,
    cursor: 'pointer'
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
  hint: {
    fontSize: 11,
    color: '#94a3b8',
    margin: 0
  }
};
