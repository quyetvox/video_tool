import React, { useState, useRef, useEffect, useMemo, useCallback } from 'react';
import {
  Scissors,
  Layers,
  Split,
  Trash2,
  Play,
  Pause,
  Plus,
  RotateCcw,
  RotateCw,
  Save,
  Download,
  Settings,
  MoreHorizontal,
  Camera,
  Maximize,
  Volume2,
  VolumeX,
  Volume1,
  Music,
  Mic,
  Sparkles,
  CheckCircle2,
  AlertTriangle,
  Clock,
  Film,
  Video as VideoIcon,
  ChevronDown,
  ChevronUp,
  X,
  GripVertical,
  HelpCircle,
  Eye,
  EyeOff,
  Lock,
  Unlock,
  FolderOpen,
  Image as ImageIcon,
  Sliders,
  Type,
  Copy,
  Info,
  History,
  FileText,
  Upload,
  ArrowUp,
  ArrowDown,
  Check,
  RefreshCw,
  Search,
  Move,
  Bold,
  Italic,
  Square,
  Minus
} from 'lucide-react';

import { 
  getMediaUrl, 
  runScript, 
  checkVideoCompatibility, 
  suggestConcatName,
  uploadAsset
} from '../services/api';
import { useModal } from './ConfirmModal';

// ── Time Formatting Utilities ────────────────────────────────────────────────
const formatTimecodeMs = (sec) => {
  if (sec === null || sec === undefined || isNaN(sec) || sec < 0) return '00:00:00.000';
  const hrs = Math.floor(sec / 3600);
  const mins = Math.floor((sec % 3600) / 60);
  const secs = Math.floor(sec % 60);
  const ms = Math.floor((sec % 1) * 1000);
  return `${hrs.toString().padStart(2, '0')}:${mins.toString().padStart(2, '0')}:${secs.toString().padStart(2, '0')}.${ms.toString().padStart(3, '0')}`;
};

const formatShortTime = (sec) => {
  if (sec === null || sec === undefined || isNaN(sec) || sec < 0) return '00:00';
  const totalSecs = Math.floor(sec);
  const mins = Math.floor(totalSecs / 60);
  const secs = totalSecs % 60;
  return `${mins.toString().padStart(2, '0')}:${secs.toString().padStart(2, '0')}`;
};

const parseTimecode = (str) => {
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

const formatFileSize = (bytes) => {
  if (!bytes || isNaN(bytes) || bytes <= 0) return '0 MB';
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  if (bytes < 1024 * 1024 * 1024) return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
  return `${(bytes / (1024 * 1024 * 1024)).toFixed(2)} GB`;
};

// ── Real Typography CSS Font-Family Mapper ───────────────────────────────────
const getFontFamilyCSS = (fontName) => {
  switch (fontName) {
    case 'Be Vietnam Pro':
      return "'Be Vietnam Pro', sans-serif";
    case 'Montserrat':
      return "'Montserrat', sans-serif";
    case 'Anton':
    case 'Impact':
      return "'Anton', Impact, 'Arial Black', sans-serif";
    case 'Plus Jakarta Sans':
      return "'Plus Jakarta Sans', sans-serif";
    case 'Roboto':
      return "'Roboto', sans-serif";
    case 'SF Pro Display':
      return "-apple-system, BlinkMacSystemFont, 'SF Pro Display', sans-serif";
    case 'Arial':
    default:
      return "Arial, Helvetica, sans-serif";
  }
};

export default function VideoStudio({
  project,
  srcFiles = [],
  cutFiles = [],
  mergeFiles = [],
  outputFiles = [],
  onSelectTab,
  onRefresh,
  studioToolMode,
  onSetStudioToolMode
}) {
  const { showAlert } = useModal();
  const allFiles = useMemo(
    () => [...(srcFiles || []), ...(cutFiles || []), ...(mergeFiles || []), ...(outputFiles || [])],
    [srcFiles, cutFiles, mergeFiles, outputFiles]
  );

  // ── 1. ACTIVE VIDEO SELECTION & SWITCHER ────────────────────────────────────
  const [selectedFile, setSelectedFile] = useState(allFiles[0] || null);
  const [showVideoSwitcherModal, setShowVideoSwitcherModal] = useState(false);
  const [videoSearchQuery, setVideoSearchQuery] = useState('');
  const [videoFilterTab, setVideoFilterTab] = useState('all');

  const [mediaCacheKey, setMediaCacheKey] = useState(Date.now());

  // Auto-select first video when switching project, or keep empty state when deleted
  const currentProjectRef = useRef(project);
  useEffect(() => {
    if (currentProjectRef.current !== project) {
      currentProjectRef.current = project;
      if (allFiles.length > 0) {
        setSelectedFile(allFiles[0]);
      } else {
        setSelectedFile(null);
      }
    } else {
      // Same project: If current selected file was deleted, clear to empty state
      if (selectedFile && !allFiles.some(f => f.relPath === selectedFile.relPath)) {
        setSelectedFile(null);
        setDuration(0);
        setCurrentTime(0);
        setCutSegments([]);
        setSplitSegments([]);
        setMergePlaylist([]);
        setSubtitles([]);
        setOverlayClips([]);
        setAudioClips([]);
      }
    }
  }, [project, allFiles, selectedFile]);

  // Clean video playback reset when switching or clearing selectedFile
  useEffect(() => {
    if (videoRefA.current) {
      try {
        videoRefA.current.pause();
        videoRefA.current.currentTime = 0;
        if (!selectedFile) {
          videoRefA.current.removeAttribute('src');
          videoRefA.current.load();
        }
      } catch (_) {}
    }
    if (videoRefB.current) {
      try {
        videoRefB.current.pause();
        videoRefB.current.currentTime = 0;
        if (!selectedFile) {
          videoRefB.current.removeAttribute('src');
          videoRefB.current.load();
        }
      } catch (_) {}
    }
    setIsPlaying(false);
    setCurrentTime(0);
    if (!selectedFile) {
      setDuration(0);
    }
  }, [selectedFile?.relPath]);

  // ── 2. VIDEO PLAYBACK STATE (DUAL PLAYER ENGINE A/B PING-PONG) ─────────────
  const videoRefA = useRef(null);
  const videoRefB = useRef(null);
  const [activePlayer, setActivePlayer] = useState('A'); // 'A' | 'B'
  const videoRef = activePlayer === 'A' ? videoRefA : videoRefB; // Current active video ref proxy

  const audioElementsRef = useRef({});
  const [isPlaying, setIsPlaying] = useState(false);
  const isPlayingRef = useRef(false);
  isPlayingRef.current = isPlaying;

  const [currentTime, setCurrentTime] = useState(0);
  const currentTimeRef = useRef(0);
  currentTimeRef.current = currentTime;
  const togglePlayRef = useRef(null);

  const [duration, setDuration] = useState(105);
  const [volume, setVolume] = useState(1.0);
  const [isMuted, setIsMuted] = useState(false);
  const [videoResolution, setVideoResolution] = useState('1920x1080');
  const [aspectRatio, setAspectRatio] = useState('16:9');
  const [fileSpecs, setFileSpecs] = useState({
    codec: 'h264',
    fps: 30,
    bitrate: '4.0 Mbps',
    audioCodec: 'aac',
    sampleRate: '48000 Hz',
    channels: 'Stereo (2.0)',
    fileSize: '45.2 MB'
  });

  // ── 3. TOOL MODE (3 MODES: 'cut' [Cắt bỏ] | 'split' [Chia clip] | 'merge' [Ghép video]) ──
  const [internalToolMode, setInternalToolMode] = useState('cut');
  const toolMode = studioToolMode !== undefined ? studioToolMode : internalToolMode;
  const setToolMode = useCallback((mode) => {
    setInternalToolMode(mode);
    if (mode !== 'merge') {
      setActivePlayer('A');
      setIsPlaying(false);
    }
    if (onSetStudioToolMode) onSetStudioToolMode(mode);
  }, [onSetStudioToolMode]);

  const [showCutBox, setShowCutBox] = useState(true); // Bật/tắt hiển thị khung cắt tím
  const [startTime, setStartTime] = useState(5.0); // Mặc định 5s
  const [endTime, setEndTime] = useState(15.0); // Mặc định 15s (Khoảng 10s dễ kéo)
  const [startInputStr, setStartInputStr] = useState(formatTimecodeMs(5.0));
  const [endInputStr, setEndInputStr] = useState(formatTimecodeMs(15.0));
  const [isIsolatedPreview, setIsIsolatedPreview] = useState(false);

  // Helper đặt khung cắt 10s quanh Playhead
  const handleSetCutRange10sAtCurrent = () => {
    const st = Math.max(0, Math.min(currentTime, Math.max(0, duration - 10.0)));
    const en = Math.min(duration, st + 10.0);
    setStartTime(st);
    setEndTime(en);
    setShowCutBox(true);
    recordAction(`Đặt khung cắt 10s tại ${formatShortTime(st)} - ${formatShortTime(en)}`, 'range', { startTime: st, endTime: en });
  };

  // ── 4. ACTIVE SELECTION STATE ──────────────────────────────────────────────
  const [activeSelection, setActiveSelection] = useState({ type: 'range', id: 'range' });

  // ── 5. SEGMENTS LIST & MERGE PLAYLIST (BẮT ĐẦU TRỐNG 100%) ────────────────
  const [cutSegments, setCutSegments] = useState([]); // Danh sách các đoạn rác cần CẮT BỎ (Trống 100%)
  const [splitSegments, setSplitSegments] = useState([]); // Danh sách các đoạn sau khi CHIA (Trống 100%)
  const [mergePlaylist, setMergePlaylist] = useState([]); // Danh sách các file video cần GHÉP

  // ── 6. OVERLAY TRACKS & CLIPS ARCHITECTURE (TRỐNG 100% BAN ĐẦU) ─────────────
  const [overlayTracks, setOverlayTracks] = useState([
    { id: 'track-ov-1', name: 'Lớp phủ 1', visible: true, locked: false }
  ]);
  const [selectedOverlayTrackId, setSelectedOverlayTrackId] = useState('track-ov-1');
  const [overlayClips, setOverlayClips] = useState([]); // Trống 100% ban đầu
  const [targetUploadTrackId, setTargetUploadTrackId] = useState(null);
  const [isDraggingGizmo, setIsDraggingGizmo] = useState(null);

  // ── 7. MULTI-TRACK AUDIO CLIPS & AUTO-CLAMP ENGINE (TRỐNG 100% BAN ĐẦU) ──────
  const [audioClips, setAudioClips] = useState([]); // Trống 100% ban đầu

  // Master Track Volumes & Mute States
  const [origAudioVolume, setOrigAudioVolume] = useState(100);
  const [musicVolume, setMusicVolume] = useState(80);
  const [sfxVolume, setSfxVolume] = useState(60);
  const [origAudioMuted, setOrigAudioMuted] = useState(false);
  const [musicMuted, setMusicMuted] = useState(false);
  const [sfxMuted, setSfxMuted] = useState(false);

  // ── 8. SUBTITLE TRACK CLIPS & RICH TYPOGRAPHY STYLING (TRỐNG 100% BAN ĐẦU) ───
  const [subtitles, setSubtitles] = useState([]); // Trống 100% ban đầu

  const [subtitlePos, setSubtitlePos] = useState({ x: 50, y: 85 });
  const [isDraggingSub, setIsDraggingSub] = useState(null);

  const [subStyle, setSubStyle] = useState({
    fontFamily: 'Be Vietnam Pro',
    fontSize: 22,
    fontColor: '#facc15',
    origColor: '#ffffff',
    showSubBox: true,
    boxBgColor: 'rgba(0, 0, 0, 0.75)',
    isBold: true,
    isItalic: false,
    hasDropShadow: true
  });

  const [trackStates, setTrackStates] = useState({
    video: { visible: true, locked: false },
    audio1: { visible: true, locked: false },
    audio2: { visible: true, locked: false },
    sub: { visible: true, locked: false }
  });

  const toggleTrackVisible = (t) => {
    setTrackStates(prev => ({ ...prev, [t]: { ...prev[t], visible: !prev[t].visible } }));
  };

  const toggleTrackLock = (t) => {
    setTrackStates(prev => ({ ...prev, [t]: { ...prev[t], locked: !prev[t].locked } }));
  };

  const toggleOverlayTrackVisible = (trackId) => {
    setOverlayTracks(prev => prev.map(t => t.id === trackId ? { ...t, visible: !t.visible } : t));
  };

  const toggleOverlayTrackLock = (trackId) => {
    setOverlayTracks(prev => prev.map(t => t.id === trackId ? { ...t, locked: !t.locked } : t));
  };

  const handleAddOverlayTrack = () => {
    const newTrackIndex = overlayTracks.length + 1;
    const newTrack = {
      id: `track-ov-${Date.now()}`,
      name: `Lớp phủ ${newTrackIndex}`,
      visible: true,
      locked: false
    };
    const next = [newTrack, ...overlayTracks];
    setOverlayTracks(next);
    setSelectedOverlayTrackId(newTrack.id);
    recordAction(`Thêm Làn Lớp Phủ mới: "${newTrack.name}"`, 'overlay_track', { overlayTracks: next, overlayClips });
  };

  const handleDeleteOverlayTrack = (trackId) => {
    const nextTracks = overlayTracks.filter(t => t.id !== trackId);
    const nextClips = overlayClips.filter(c => c.trackId !== trackId);
    setOverlayTracks(nextTracks);
    setOverlayClips(nextClips);
    if (selectedOverlayTrackId === trackId) {
      setSelectedOverlayTrackId(nextTracks[0]?.id || null);
    }
    recordAction('Xoá Làn Lớp Phủ', 'overlay_track', { overlayTracks: nextTracks, overlayClips: nextClips });
  };

  const handleMoveOverlayTrack = (index, direction) => {
    const newIdx = direction === 'up' ? index - 1 : index + 1;
    if (newIdx < 0 || newIdx >= overlayTracks.length) return;
    const next = [...overlayTracks];
    const temp = next[index];
    next[index] = next[newIdx];
    next[newIdx] = temp;
    setOverlayTracks(next);
    recordAction(`Đổi thứ tự Làn Track: ${temp.name} ${direction === 'up' ? 'Lên trên' : 'Xuống dưới'}`, 'overlay_track', { overlayTracks: next });
  };

  // ── 9. RIGHT INSPECTOR TABS & EXPORT STATE ─────────────────────────────────
  const [activeRightTab, setActiveRightTab] = useState('props');
  const [outputFileName, setOutputFileName] = useState('');
  const [exportResolution, setExportResolution] = useState('original');
  const [exportFps, setExportFps] = useState('original');
  const [exportAspectRatio, setExportAspectRatio] = useState('16:9');
  const [exportQuality, setExportQuality] = useState('high');

  // ── 10. ACTION HISTORY (TIME-TRAVEL LOG) ───────────────────────────────────
  const [actionHistory, setActionHistory] = useState([
    {
      id: 'act-init',
      label: 'Khởi tạo video nguyên bản',
      type: 'init',
      time: new Date().toLocaleTimeString(),
      snapshot: {
        cutSegments: [],
        splitSegments: [],
        mergePlaylist: [],
        overlayTracks: [
          { id: 'track-ov-2', name: 'Lớp phủ 2', visible: true, locked: false },
          { id: 'track-ov-1', name: 'Lớp phủ 1', visible: true, locked: false }
        ],
        overlayClips: [
          { id: 'ov-1', trackId: 'track-ov-2', name: 'Logo Watermark', start: 10.0, end: 45.0, x: 75, y: 8, width: 18, height: 18, opacity: 0.95 },
          { id: 'ov-2', trackId: 'track-ov-1', name: 'Nhãn Dán Sticker', start: 20.0, end: 60.0, x: 70, y: 12, width: 22, height: 22, opacity: 0.85 }
        ],
        subtitlePos: { x: 50, y: 85 },
        subStyle: {
          fontFamily: 'Be Vietnam Pro',
          fontSize: 22,
          fontColor: '#facc15',
          origColor: '#ffffff',
          showSubBox: true,
          boxBgColor: 'rgba(0, 0, 0, 0.75)',
          isBold: true,
          isItalic: false,
          hasDropShadow: true
        },
        origAudioMuted: true,
        musicMuted: false,
        sfxMuted: false,
        startTime: 10.0,
        endTime: 30.0
      }
    }
  ]);
  const [historyIndex, setHistoryIndex] = useState(0);

  const recordAction = useCallback((label, type, newSnapshot) => {
    const newAction = {
      id: `act-${Date.now()}`,
      label,
      type,
      time: new Date().toLocaleTimeString(),
      snapshot: newSnapshot
    };
    setActionHistory(prev => {
      const sliced = prev.slice(0, historyIndex + 1);
      return [...sliced, newAction];
    });
    setHistoryIndex(prev => prev + 1);
  }, [historyIndex]);

  const restoreHistoryState = (actIndex) => {
    const act = actionHistory[actIndex];
    if (!act || !act.snapshot) return;
    const snap = act.snapshot;
    if (snap.cutSegments) setCutSegments(snap.cutSegments);
    if (snap.splitSegments) setSplitSegments(snap.splitSegments);
    if (snap.mergePlaylist) setMergePlaylist(snap.mergePlaylist);
    if (snap.overlayTracks) setOverlayTracks(snap.overlayTracks);
    if (snap.overlayClips) setOverlayClips(snap.overlayClips);
    if (snap.audioClips) setAudioClips(snap.audioClips);
    if (snap.subtitles) setSubtitles(snap.subtitles);
    if (snap.subtitlePos) setSubtitlePos(snap.subtitlePos);
    if (snap.subStyle) setSubStyle(snap.subStyle);
    if (snap.origAudioMuted !== undefined) setOrigAudioMuted(snap.origAudioMuted);
    if (snap.musicMuted !== undefined) setMusicMuted(snap.musicMuted);
    if (snap.sfxMuted !== undefined) setSfxMuted(snap.sfxMuted);
    if (snap.startTime !== undefined) setStartTime(snap.startTime);
    if (snap.endTime !== undefined) setEndTime(snap.endTime);
    setHistoryIndex(actIndex);
  };

  const handleUndo = () => {
    if (historyIndex > 0) restoreHistoryState(historyIndex - 1);
  };

  const handleRedo = () => {
    if (historyIndex < actionHistory.length - 1) restoreHistoryState(historyIndex + 1);
  };

  // ── 11. GLOBAL DELETE KEY HANDLER ──────────────────────────────────────────
  useEffect(() => {
    const handleKeyDown = (e) => {
      if (['INPUT', 'TEXTAREA', 'SELECT'].includes(document.activeElement?.tagName) || document.activeElement?.isContentEditable) {
        return;
      }

      if (e.key === 'Delete' || e.key === 'Backspace') {
        if (!activeSelection || !activeSelection.id) return;
        e.preventDefault();

        if (activeSelection.type === 'video_clip') {
          if (toolMode === 'merge') {
            const next = mergePlaylist.filter(m => m.id !== activeSelection.id);
            setMergePlaylist(next);
            recordAction(`Xoá video khỏi danh sách ghép`, 'merge', { mergePlaylist: next });
          } else if (splitSegments.length > 0) {
            const next = splitSegments.filter(s => s.id !== activeSelection.id);
            setSplitSegments(next);
            recordAction(`Xoá đoạn clip khỏi timeline`, 'split', { splitSegments: next });
          }
          setActiveSelection({ type: 'range', id: 'range' });
        } else if (activeSelection.type === 'cut_segment') {
          const next = cutSegments.filter(s => s.id !== activeSelection.id);
          setCutSegments(next);
          recordAction('Xoá đoạn rác khỏi danh sách cắt', 'cut_segment', { cutSegments: next });
          setActiveSelection({ type: 'range', id: 'range' });
        } else if (activeSelection.type === 'split_segment') {
          const next = splitSegments.filter(s => s.id !== activeSelection.id);
          setSplitSegments(next);
          recordAction('Xoá đoạn chia khỏi sequence', 'split_segment', { splitSegments: next });
          setActiveSelection({ type: 'range', id: 'range' });
        } else if (activeSelection.type === 'merge_item') {
          const next = mergePlaylist.filter(s => s.id !== activeSelection.id);
          setMergePlaylist(next);
          recordAction('Xoá video khỏi danh sách ghép', 'merge_item', { mergePlaylist: next });
          setActiveSelection({ type: 'range', id: 'range' });
        } else if (activeSelection.type === 'overlay') {
          const next = overlayClips.filter(o => o.id !== activeSelection.id);
          setOverlayClips(next);
          recordAction('Xoá hình ảnh lớp phủ', 'overlay', { overlayClips: next });
          setActiveSelection({ type: 'range', id: 'range' });
        } else if (activeSelection.type === 'audio') {
          const next = audioClips.filter(a => a.id !== activeSelection.id);
          setAudioClips(next);
          recordAction('Xoá audio', 'audio', { audioClips: next });
          setActiveSelection({ type: 'range', id: 'range' });
        } else if (activeSelection.type === 'sub') {
          const next = subtitles.filter(s => s.id !== activeSelection.id);
          setSubtitles(next);
          recordAction('Xoá câu phụ đề', 'subtitle', { subtitles: next });
          setActiveSelection({ type: 'range', id: 'range' });
        }
      } else if (e.key === ' ' || e.code === 'Space') {
        e.preventDefault();
        togglePlayRef.current?.();
      } else if (e.key.toLowerCase() === 's') {
        setToolMode('split');
      } else if (e.ctrlKey && e.key.toLowerCase() === 'z') {
        e.preventDefault();
        if (e.shiftKey) handleRedo();
        else handleUndo();
      }
    };

    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [activeSelection, cutSegments, splitSegments, mergePlaylist, overlayClips, audioClips, subtitles, recordAction]);

  // ── 12. MEDIA BIN & UI MODALS ──────────────────────────────────────────────
  const [isMediaBinOpen, setIsMediaBinOpen] = useState(false);
  const [showShortcutsModal, setShowShortcutsModal] = useState(false);
  const [showMoreMenu, setShowMoreMenu] = useState(false);
  const [isProcessing, setIsProcessing] = useState(false);
  const [activeJobId, setActiveJobId] = useState(null);
  const [showCompatModal, setShowCompatModal] = useState(false);
  const [compatReport, setCompatReport] = useState(null);
  const [pendingMergeAction, setPendingMergeAction] = useState(null);

  // ── 13. TIMELINE INTERACTION & DRAG ENGINE ─────────────────────────────────
  const timelineTrackRef = useRef(null);
  const videoScreenRef = useRef(null);
  const [draggingTarget, setDraggingTarget] = useState(null);
  const [zoomLevel, setZoomLevel] = useState(1);
  const [draggedMergeIndex, setDraggedMergeIndex] = useState(null);
  const fileInputRef = useRef(null);
  const audioInputRef = useRef(null);
  const [targetAudioTrack, setTargetAudioTrack] = useState('audio1');

  const handleTriggerAddAudioToTrack = (trackId) => {
    setTargetAudioTrack(trackId);
    audioInputRef.current?.click();
  };

  // Bộ nhớ đệm lưu thời lượng chính xác tuyệt đối của từng file video
  const [videoDurationsMap, setVideoDurationsMap] = useState({});
  const inFlightProbesRef = useRef(new Set());

  // Tự động đo thời lượng chính xác (exact duration) của từng file video với cơ chế throttle & cleanup
  const probeVideoDuration = useCallback((relPath) => {
    if (!relPath || inFlightProbesRef.current.has(relPath)) return;
    inFlightProbesRef.current.add(relPath);

    const v = document.createElement('video');
    v.preload = 'metadata';
    v.muted = true;

    const cleanup = () => {
      v.removeAttribute('src');
      v.load();
      v.onloadedmetadata = null;
      v.onerror = null;
    };

    v.onloadedmetadata = () => {
      if (v.duration && !isNaN(v.duration) && v.duration > 0) {
        setVideoDurationsMap(prev => ({
          ...prev,
          [relPath]: v.duration
        }));
      }
      cleanup();
    };

    v.onerror = () => {
      cleanup();
    };

    v.src = getMediaUrl(relPath);
  }, []);

  useEffect(() => {
    // Chỉ đo thời lượng cho các video trong merge playlist chưa có duration
    mergePlaylist.forEach(item => {
      if (item.relPath && !item.duration && !videoDurationsMap[item.relPath] && !inFlightProbesRef.current.has(item.relPath)) {
        probeVideoDuration(item.relPath);
      }
    });
  }, [mergePlaylist, probeVideoDuration, videoDurationsMap]);

  // Tính toán mốc thời gian và tổng thời lượng chuỗi video ghép chính xác 100%
  const mergeSequenceWithTimings = useMemo(() => {
    let curr = 0;
    return mergePlaylist.map(item => {
      const dur = item.duration || videoDurationsMap[item.relPath] || (item.relPath === selectedFile?.relPath ? duration : 10.0);
      const start = curr;
      const end = curr + dur;
      curr = end;
      return {
        ...item,
        duration: dur,
        start,
        end
      };
    });
  }, [mergePlaylist, videoDurationsMap, selectedFile, duration]);

  const totalMergeDuration = useMemo(() => {
    if (mergeSequenceWithTimings.length === 0) return duration || 105;
    return mergeSequenceWithTimings[mergeSequenceWithTimings.length - 1].end;
  }, [mergeSequenceWithTimings, duration]);

  const effectiveDur = toolMode === 'merge' ? totalMergeDuration : (duration > 0 ? duration : 100);

  const [currentMergeIndex, setCurrentMergeIndex] = useState(0);

  // Nguồn phát cho Dual Player A & B (Player A: Clip chẵn 0,2,4... | Player B: Clip lẻ 1,3,5...)
  const playerASrc = useMemo(() => {
    if (toolMode !== 'merge') {
      return selectedFile ? getMediaUrl(selectedFile.relPath, mediaCacheKey) : '';
    }
    if (mergeSequenceWithTimings.length === 0) return '';
    if (currentMergeIndex % 2 === 0) {
      const curClip = mergeSequenceWithTimings[currentMergeIndex];
      return curClip ? getMediaUrl(curClip.relPath, mediaCacheKey) : '';
    } else {
      const nextEvenClip = mergeSequenceWithTimings[currentMergeIndex + 1];
      return nextEvenClip ? getMediaUrl(nextEvenClip.relPath, mediaCacheKey) : '';
    }
  }, [toolMode, selectedFile, mediaCacheKey, mergeSequenceWithTimings, currentMergeIndex]);

  const playerBSrc = useMemo(() => {
    if (toolMode !== 'merge') return '';
    if (mergeSequenceWithTimings.length === 0) return '';
    if (currentMergeIndex % 2 === 1) {
      const curClip = mergeSequenceWithTimings[currentMergeIndex];
      return curClip ? getMediaUrl(curClip.relPath, mediaCacheKey) : '';
    } else {
      const nextOddClip = mergeSequenceWithTimings[currentMergeIndex + 1];
      return nextOddClip ? getMediaUrl(nextOddClip.relPath, mediaCacheKey) : '';
    }
  }, [toolMode, mediaCacheKey, mergeSequenceWithTimings, currentMergeIndex]);

  // Danh sách các khối video clip hiển thị trên Track 1 (Hợp nhất giữa Ghép, Chia và Cắt)
  const activeVideoClips = useMemo(() => {
    if (toolMode === 'merge') {
      return mergeSequenceWithTimings;
    }
    if (splitSegments.length > 0) {
      return splitSegments.map((seg, idx) => ({
        id: seg.id,
        name: seg.name || `Đoạn ${idx + 1}`,
        start: seg.start,
        end: seg.end,
        duration: seg.duration,
        relPath: seg.refFile || selectedFile?.relPath
      }));
    }
    return [{
      id: 'base-clip-main',
      name: selectedFile?.name || 'Video gốc',
      start: 0,
      end: duration,
      duration: duration || 100,
      relPath: selectedFile?.relPath
    }];
  }, [toolMode, mergeSequenceWithTimings, splitSegments, selectedFile, duration]);

  useEffect(() => {
    setStartInputStr(formatTimecodeMs(startTime));
  }, [startTime]);

  useEffect(() => {
    setEndInputStr(formatTimecodeMs(endTime));
  }, [endTime]);

  useEffect(() => {
    if (selectedFile) {
      const stem = selectedFile.name.replace(/\.[^/.]+$/, '');
      setOutputFileName(`${stem}_clean.mp4`);
      setFileSpecs(prev => ({
        ...prev,
        fileSize: formatFileSize(selectedFile.size || selectedFile.sizeBytes || 45000000)
      }));
      // Tự động khởi tạo video hiện tại vào playlist ghép nếu playlist đang rỗng
      setMergePlaylist(prev => {
        if (prev.length === 0) {
          return [{
            id: `merge-${Date.now()}`,
            name: selectedFile.name,
            relPath: selectedFile.relPath,
            size: selectedFile.size || selectedFile.sizeBytes,
            duration: duration || 15.0
          }];
        }
        return prev;
      });
    }
  }, [selectedFile, duration]);

  // Khống chế nghiêm ngặt: Tất cả các lớp dưới (overlay, audio, sub) không được vượt quá thời lượng video (trừ chế độ merge)
  const clampAllLowerTracks = useCallback((maxDur) => {
    if (!maxDur || maxDur <= 0 || toolMode === 'merge') return;

    setOverlayClips(prev => prev.map(ov => {
      const safeStart = Math.max(0, Math.min(ov.start, Math.max(0, maxDur - 1)));
      const safeEnd = Math.max(safeStart + 0.5, Math.min(maxDur, ov.end));
      return (ov.start !== safeStart || ov.end !== safeEnd) ? { ...ov, start: safeStart, end: safeEnd } : ov;
    }));

    setAudioClips(prev => prev.map(aud => {
      const safeStart = Math.max(0, Math.min(aud.start, Math.max(0, maxDur - 0.5)));
      const safeDur = Math.max(0.5, Math.min(aud.duration, maxDur - safeStart));
      return (aud.start !== safeStart || aud.duration !== safeDur) ? { ...aud, start: safeStart, duration: safeDur } : aud;
    }));

    setSubtitles(prev => prev.map(sub => {
      const safeStart = Math.max(0, Math.min(sub.start, Math.max(0, maxDur - 0.5)));
      const safeEnd = Math.max(safeStart + 0.2, Math.min(maxDur, sub.end));
      return (sub.start !== safeStart || sub.end !== safeEnd) ? { ...sub, start: safeStart, end: safeEnd } : sub;
    }));

    setStartTime(prev => Math.max(0, Math.min(prev, maxDur - 0.05)));
    setEndTime(prev => Math.max(0.1, Math.min(maxDur, prev)));
  }, [toolMode]);

  const handleLoadedMetadata = (e) => {
    const targetEl = e?.target;
    if (!targetEl) return;
    const dur = targetEl.duration;
    if (!dur || isNaN(dur) || dur <= 0) return;

    // Phân tích relPath chính xác từ URL của thẻ video
    let targetRelPath = null;
    try {
      const url = new URL(targetEl.src, window.location.origin);
      targetRelPath = url.searchParams.get('file') || url.searchParams.get('path');
    } catch (err) {}

    if (!targetRelPath) {
      const matched = mergePlaylist.find(m => m.relPath && (targetEl.src.includes(encodeURIComponent(m.relPath)) || targetEl.src.includes(m.relPath)))
        || allFiles.find(f => f.relPath && (targetEl.src.includes(encodeURIComponent(f.relPath)) || targetEl.src.includes(f.relPath)));
      if (matched) targetRelPath = matched.relPath;
    }

    if (targetRelPath) {
      setVideoDurationsMap(prev => ({ ...prev, [targetRelPath]: dur }));
      setMergePlaylist(prev => prev.map(m => m.relPath === targetRelPath ? { ...m, duration: dur } : m));
      
      if (toolMode !== 'merge' && targetRelPath === selectedFile?.relPath) {
        setDuration(dur);
        clampAllLowerTracks(dur);
      }
    } else if (targetEl === (activePlayer === 'A' ? videoRefA.current : videoRefB.current) && selectedFile?.relPath) {
      setVideoDurationsMap(prev => ({ ...prev, [selectedFile.relPath]: dur }));
      if (toolMode !== 'merge') {
        setDuration(dur);
        clampAllLowerTracks(dur);
      }
    }

    if (targetEl === (activePlayer === 'A' ? videoRefA.current : videoRefB.current)) {
      const w = targetEl.videoWidth || 1920;
      const h = targetEl.videoHeight || 1080;
      setVideoResolution(`${w}x${h}`);
      setAspectRatio(w > h ? '16:9' : (h > w ? '9:16' : '1:1'));
    }
  };

  // ── 14. REALTIME AUDIO SYNC & AUTO-CLAMP ENGINE ────────────────────────────
  const syncAudioPlayback = useCallback((curTime, isPlayingState) => {
    const activeEl = activePlayer === 'A' ? videoRefA.current : videoRefB.current;
    if (activeEl) {
      const shouldMuteOrig = origAudioMuted || origAudioVolume === 0 || !trackStates.video.visible;
      activeEl.muted = shouldMuteOrig;
      if (!shouldMuteOrig) {
        activeEl.volume = Math.max(0, Math.min(1, (origAudioVolume / 100) * volume));
      }
    }

    if (!isPlayingState || curTime >= effectiveDur) {
      Object.values(audioElementsRef.current).forEach(a => {
        if (a && !a.paused) a.pause();
      });
      return;
    }

    audioClips.forEach(clip => {
      let audioEl = audioElementsRef.current[clip.id];
      const targetSrc = clip.relPath ? getMediaUrl(clip.relPath, mediaCacheKey) : clip.audioSrc;

      if (!audioEl && targetSrc) {
        audioEl = new Audio(targetSrc);
        audioEl.preload = 'auto';
        audioElementsRef.current[clip.id] = audioEl;
      }

      if (!audioEl) return;

      const trackVisible = clip.track === 'audio1' ? trackStates.audio1.visible : trackStates.audio2.visible;
      const trackMuted = clip.track === 'audio1' ? musicMuted : sfxMuted;
      const masterVol = clip.track === 'audio1' ? musicVolume : sfxVolume;

      const effectiveVol = trackVisible && !trackMuted ? (clip.volume / 100) * (masterVol / 100) : 0;
      audioEl.volume = Math.max(0, Math.min(1, effectiveVol));

      const effectiveClipEnd = clip.start + (clip.duration || 10.0);
      const isInsideClip = curTime >= clip.start && curTime <= effectiveClipEnd;

      if (isPlayingState && isInsideClip && trackVisible && !trackMuted) {
        const offset = Math.max(0, curTime - clip.start);
        if (Math.abs(audioEl.currentTime - offset) > 0.25) {
          audioEl.currentTime = offset;
        }
        if (audioEl.paused) {
          audioEl.play().catch(err => {
            console.warn('Audio playback error:', err);
          });
        }
      } else {
        if (!audioEl.paused) {
          audioEl.pause();
        }
      }
    });
  }, [audioClips, trackStates, musicMuted, sfxMuted, musicVolume, sfxVolume, origAudioMuted, origAudioVolume, volume, effectiveDur, activePlayer, mediaCacheKey]);

  const togglePlay = () => {
    if (isPlaying) {
      const activeEl = activePlayer === 'A' ? videoRefA.current : videoRefB.current;
      if (activeEl) activeEl.pause();
      setIsPlaying(false);
      syncAudioPlayback(currentTime, false);
    } else {
      if (toolMode === 'merge' && mergeSequenceWithTimings.length > 0) {
        if (currentTime >= effectiveDur - 0.1) {
          handleSeek(0);
          return;
        }
        // Tính toán đúng clip và player tương ứng với currentTime đang trỏ tới
        const targetIdx = mergeSequenceWithTimings.findIndex(v => currentTime >= v.start && currentTime < v.end);
        const safeIdx = targetIdx >= 0 ? targetIdx : (currentTime >= effectiveDur ? mergeSequenceWithTimings.length - 1 : 0);
        const curClip = mergeSequenceWithTimings[safeIdx];
        
        setCurrentMergeIndex(safeIdx);
        const requiredPlayer = safeIdx % 2 === 0 ? 'A' : 'B';
        setActivePlayer(requiredPlayer);

        const targetEl = requiredPlayer === 'A' ? videoRefA.current : videoRefB.current;
        const otherEl = requiredPlayer === 'A' ? videoRefB.current : videoRefA.current;
        if (otherEl && !otherEl.paused) otherEl.pause();

        if (targetEl && curClip) {
          const localOffset = Math.max(0, currentTime - curClip.start);
          if (Math.abs(targetEl.currentTime - localOffset) > 0.03) {
            targetEl.currentTime = localOffset;
          }
          targetEl.play().then(() => setIsPlaying(true)).catch(() => {});
        }
        syncAudioPlayback(currentTime, true);
        return;
      } else {
        const activeEl = activePlayer === 'A' ? videoRefA.current : videoRefB.current;
        if (!activeEl) return;
        if (currentTime >= duration - 0.1) {
          activeEl.currentTime = 0;
          setCurrentTime(0);
        } else {
          if (Math.abs(activeEl.currentTime - currentTime) > 0.03) {
            activeEl.currentTime = currentTime;
          }
        }
        activeEl.play().then(() => setIsPlaying(true)).catch(() => {});
        syncAudioPlayback(currentTime, true);
      }
    }
  };
  togglePlayRef.current = togglePlay;

  const handleSeek = (timeSec) => {
    const valid = Math.max(0, Math.min(timeSec, effectiveDur));
    setCurrentTime(valid);

    if (toolMode === 'merge' && mergeSequenceWithTimings.length > 0) {
      const targetIdx = mergeSequenceWithTimings.findIndex(v => valid >= v.start && valid < v.end);
      const safeIdx = targetIdx >= 0 ? targetIdx : (valid >= effectiveDur ? mergeSequenceWithTimings.length - 1 : 0);
      const targetClip = mergeSequenceWithTimings[safeIdx];
      
      if (targetClip) {
        const localOffset = Math.max(0, valid - targetClip.start);
        setCurrentMergeIndex(safeIdx);

        const requiredPlayer = safeIdx % 2 === 0 ? 'A' : 'B';
        setActivePlayer(requiredPlayer);

        const targetEl = requiredPlayer === 'A' ? videoRefA.current : videoRefB.current;
        const otherEl = requiredPlayer === 'A' ? videoRefB.current : videoRefA.current;
        if (otherEl && !otherEl.paused) otherEl.pause();

        if (targetEl) {
          targetEl.currentTime = localOffset;
          if (isPlaying) targetEl.play().catch(() => {});
        }

        const matched = allFiles.find(f => f.relPath === targetClip.relPath) || { name: targetClip.name, relPath: targetClip.relPath };
        setSelectedFile(matched);
      }
    } else {
      const activeEl = activePlayer === 'A' ? videoRefA.current : videoRefB.current;
      if (activeEl) {
        activeEl.currentTime = valid;
        if (isPlaying) activeEl.play().catch(() => {});
      }
    }

    syncAudioPlayback(valid, isPlaying);
  };

  // ── MASTER 60FPS CLOCK & DUAL-PLAYER PING-PONG ENGINE ───────────────────────
  useEffect(() => {
    if (!isPlaying) return;

    let rafId;

    const tick = () => {
      const activeEl = activePlayer === 'A' ? videoRefA.current : videoRefB.current;
      const inactiveEl = activePlayer === 'A' ? videoRefB.current : videoRefA.current;

      if (activeEl && !activeEl.paused) {
        if (toolMode === 'merge' && mergeSequenceWithTimings.length > 0) {
          const curIdx = currentMergeIndex;
          const curClip = mergeSequenceWithTimings[curIdx] || mergeSequenceWithTimings[0];
          if (curClip) {
            const curVideoTime = activeEl.currentTime;
            const globalTime = Math.min(effectiveDur, curClip.start + curVideoTime);
            setCurrentTime(globalTime);
            syncAudioPlayback(globalTime, true);

            // Tự động cuộn theo Playhead khi phóng to trục thời gian (Auto-Scroll)
            if (timelineTrackRef.current && zoomLevel > 1) {
              const container = timelineTrackRef.current;
              const totalW = container.clientWidth * zoomLevel;
              const playheadPx = (globalTime / effectiveDur) * totalW;
              const scrollL = container.scrollLeft;
              const viewW = container.clientWidth;
              if (playheadPx > scrollL + viewW - 80 || playheadPx < scrollL) {
                container.scrollLeft = Math.max(0, playheadPx - 120);
              }
            }

            // Kiểm tra ranh giới chuyển tiếp 0ms sang clip tiếp theo
            const clipDur = curClip.duration || activeEl.duration || 10;
            if (curVideoTime >= clipDur - 0.05 || activeEl.ended) {
              if (curIdx < mergeSequenceWithTimings.length - 1) {
                const nextIdx = curIdx + 1;
                const nextClip = mergeSequenceWithTimings[nextIdx];
                const nextPlayer = nextIdx % 2 === 0 ? 'A' : 'B';

                // Bật phát ngay lập tức trên inactive player (đã preloaded 0ms!)
                if (inactiveEl) {
                  inactiveEl.currentTime = 0;
                  inactiveEl.play().catch(() => {});
                }
                activeEl.pause();

                setCurrentMergeIndex(nextIdx);
                setActivePlayer(nextPlayer);

                const matched = allFiles.find(f => f.relPath === nextClip.relPath) || { name: nextClip.name, relPath: nextClip.relPath };
                setSelectedFile(matched);
              } else {
                setIsPlaying(false);
                syncAudioPlayback(effectiveDur, false);
              }
            }
          }
        } else {
          const cur = activeEl.currentTime;
          setCurrentTime(cur);
          syncAudioPlayback(cur, true);

          if (timelineTrackRef.current && zoomLevel > 1) {
            const container = timelineTrackRef.current;
            const totalW = container.clientWidth * zoomLevel;
            const playheadPx = (cur / effectiveDur) * totalW;
            const scrollL = container.scrollLeft;
            const viewW = container.clientWidth;
            if (playheadPx > scrollL + viewW - 80 || playheadPx < scrollL) {
              container.scrollLeft = Math.max(0, playheadPx - 120);
            }
          }

          if (isIsolatedPreview && cur >= endTime - 0.05) {
            activeEl.currentTime = startTime;
            setCurrentTime(startTime);
          } else if (activeEl.ended) {
            setIsPlaying(false);
            syncAudioPlayback(cur, false);
          }
        }
      }

      if (isPlayingRef.current) {
        rafId = requestAnimationFrame(tick);
      }
    };

    rafId = requestAnimationFrame(tick);
    return () => {
      if (rafId) cancelAnimationFrame(rafId);
    };
  }, [isPlaying, activePlayer, currentMergeIndex, toolMode, mergeSequenceWithTimings, effectiveDur, isIsolatedPreview, startTime, endTime, allFiles, syncAudioPlayback, zoomLevel]);

  const handleTakeSnapshot = () => {
    if (!videoRef.current) return;
    const canvas = document.createElement('canvas');
    canvas.width = videoRef.current.videoWidth || 1280;
    canvas.height = videoRef.current.videoHeight || 720;
    const ctx = canvas.getContext('2d');
    ctx.drawImage(videoRef.current, 0, 0, canvas.width, canvas.height);

    const dataUrl = canvas.toDataURL('image/png');
    const a = document.createElement('a');
    a.href = dataUrl;
    a.download = `snapshot_${Math.floor(currentTime)}s.png`;
    a.click();
  };

  // ── 15. SWITCH VIDEO ACTION ────────────────────────────────────────────────
  const handleSwitchActiveVideo = (file) => {
    if (!file) return;
    setSelectedFile(file);
    setShowVideoSwitcherModal(false);
    setCurrentTime(0);
    setIsPlaying(false);
    setIsIsolatedPreview(false);
    setCutSegments([]);
    setSplitSegments([]);
    setActivePlayer('A');

    const newDur = videoDurationsMap[file.relPath] || duration || 15.0;
    setDuration(newDur);
    setStartTime(Math.min(5.0, newDur > 5 ? 5.0 : 0));
    setEndTime(Math.min(15.0, newDur));

    if (videoRefA.current) {
      videoRefA.current.currentTime = 0;
      videoRefA.current.load();
    }
    if (videoRefB.current) {
      videoRefB.current.pause();
    }

    recordAction(`Đổi video làm việc thành "${file.name}"`, 'switch_video', { selectedFile: file });
  };

  const filteredVideos = useMemo(() => {
    return allFiles.filter(f => {
      const matchSearch = f.name.toLowerCase().includes(videoSearchQuery.toLowerCase());
      if (!matchSearch) return false;
      if (videoFilterTab === 'src') return f.relPath.includes('/src/');
      if (videoFilterTab === 'output') return f.relPath.includes('/output/');
      return true;
    });
  }, [allFiles, videoSearchQuery, videoFilterTab]);

  // ── 16A. CẮT BỎ: LOẠI BỎ ĐOẠN RÁC & NỐI LIỀN CÁC PHẦN CÒN LẠI ───────────────
  const handleAddCutTrashSegment = () => {
    const dur = Math.max(0.1, Math.round((endTime - startTime) * 1000) / 1000);
    const newSeg = {
      id: `cut-${Date.now()}`,
      name: `Đoạn rác ${cutSegments.length + 1}`,
      start: startTime,
      end: endTime,
      duration: dur,
      refFile: selectedFile?.relPath || ''
    };
    const next = [...cutSegments, newSeg];
    setCutSegments(next);
    setActiveSelection({ type: 'cut_segment', id: newSeg.id });
    recordAction(`Đã thêm đoạn rác: ${formatShortTime(startTime)} - ${formatShortTime(endTime)}`, 'cut_segment', {
      cutSegments: next
    });
  };

  const handleExecuteCutTrash = async () => {
    if (!selectedFile) return;

    let rangesToRemove = [];
    if (cutSegments.length > 0) {
      rangesToRemove = cutSegments.map(s => `${formatTimecodeMs(s.start)}-${formatTimecodeMs(s.end)}`);
    } else {
      rangesToRemove = [`${formatTimecodeMs(startTime)}-${formatTimecodeMs(endTime)}`];
    }

    const jobId = `studio_remove_${Date.now()}`;
    setIsProcessing(true);
    setActiveJobId(jobId);

    try {
      await runScript('concat.py', [selectedFile.relPath, '--remove', ...rangesToRemove, '--overwrite'], jobId);
      await new Promise(r => setTimeout(r, 800));

      const freshKey = Date.now();
      setMediaCacheKey(freshKey);
      setCutSegments([]);
      setIsIsolatedPreview(false);

      if (videoRef.current) {
        videoRef.current.src = getMediaUrl(selectedFile.relPath, freshKey);
        videoRef.current.load();
        videoRef.current.currentTime = 0;
      }

      onRefresh && onRefresh();
      showAlert({ 
        title: 'Cắt Bỏ Rác Thành Công', 
        message: `Đã loại bỏ ${rangesToRemove.length} đoạn rác. Các đoạn ngoài vùng cắt đã được ghép nối liền mạch!`, 
        type: 'success' 
      });
    } catch (err) {
      showAlert({ title: 'Lỗi Cắt Bỏ Rác', message: err.message, type: 'danger' });
    } finally {
      setIsProcessing(false);
      setActiveJobId(null);
    }
  };

  // ── 16B. CHIA CLIP: TÁCH ĐÔI TẠI PLAYHEAD & GIỮ LẠI TẤT CẢ CÁC ĐOẠN ──────────
  const handleExecuteSplit = () => {
    if (currentTime <= 0.2 || currentTime >= duration - 0.2) {
      showAlert({ title: 'Vị Trí Không Hợp Lệ', message: 'Vui lòng di chuyển Playhead đến mốc thời gian muốn chia!', type: 'warning' });
      return;
    }

    if (splitSegments.length === 0) {
      const seg1 = {
        id: `split-${Date.now()}-1`,
        name: `Đoạn 1`,
        start: 0,
        end: currentTime,
        duration: Math.round(currentTime * 1000) / 1000,
        refFile: selectedFile?.relPath
      };
      const seg2 = {
        id: `split-${Date.now()}-2`,
        name: `Đoạn 2`,
        start: currentTime,
        end: duration,
        duration: Math.round((duration - currentTime) * 1000) / 1000,
        refFile: selectedFile?.relPath
      };

      const next = [seg1, seg2];
      setSplitSegments(next);
      setActiveSelection({ type: 'video_clip', id: seg2.id });
      recordAction(`Chia video thành 2 đoạn độc lập tại ${formatShortTime(currentTime)}`, 'split', { splitSegments: next });
      showAlert({ title: 'Chia Clip Thành Công', message: `Đã chia video thành 2 đoạn độc lập tại mốc ${formatShortTime(currentTime)}. Cả 2 đoạn đã sẵn sàng trên timeline!`, type: 'success' });
    } else {
      const segIdx = splitSegments.findIndex(s => currentTime > s.start + 0.1 && currentTime < s.end - 0.1);
      if (segIdx === -1) {
        showAlert({ title: 'Vị Trí Không Hợp Lệ', message: 'Playhead đang nằm tại mép hoặc ngoài các đoạn clip!', type: 'warning' });
        return;
      }

      const targetSeg = splitSegments[segIdx];
      const segA = {
        ...targetSeg,
        id: `split-${Date.now()}-a`,
        end: currentTime,
        duration: Math.round((currentTime - targetSeg.start) * 1000) / 1000,
        name: `${targetSeg.name}.1`
      };
      const segB = {
        ...targetSeg,
        id: `split-${Date.now()}-b`,
        start: currentTime,
        duration: Math.round((targetSeg.end - currentTime) * 1000) / 1000,
        name: `${targetSeg.name}.2`
      };

      const next = [...splitSegments];
      next.splice(segIdx, 1, segA, segB);
      setSplitSegments(next);
      setActiveSelection({ type: 'video_clip', id: segB.id });
      recordAction(`Chia đoạn "${targetSeg.name}" tại ${formatShortTime(currentTime)}`, 'split', { splitSegments: next });
      showAlert({ title: 'Chia Clip Thành Công', message: `Đã chia đoạn "${targetSeg.name}" thành 2 đoạn nhỏ hơn tại mốc ${formatShortTime(currentTime)}!`, type: 'success' });
    }
  };

  // ── 16B. CHIA CLIP: TÁCH CÁC ĐOẠN ĐỘC LẬP & XUẤT HÀNG LOẠT ─────────────────
  const handleSplitClipAtCurrentTime = () => {
    const cur = Math.round(currentTime * 1000) / 1000;
    if (cur <= 0.1 || cur >= duration - 0.1) {
      showAlert({ title: 'Không Thể Chia', message: 'Vị trí con trỏ quá gần đầu hoặc cuối video!', type: 'warning' });
      return;
    }

    // Find segment containing cur
    let targetIdx = -1;
    for (let i = 0; i < splitSegments.length; i++) {
      if (cur > splitSegments[i].start + 0.1 && cur < splitSegments[i].end - 0.1) {
        targetIdx = i;
        break;
      }
    }

    if (targetIdx === -1) {
      showAlert({ title: 'Không Thể Chia', message: 'Điểm chia này đã tồn tại hoặc nằm ngoài phạm vi các đoạn!', type: 'warning' });
      return;
    }

    const target = splitSegments[targetIdx];
    const segA = {
      id: `split-${Date.now()}-A`,
      name: `Clip Part ${targetIdx + 1}A`,
      start: target.start,
      end: cur,
      duration: Math.round((cur - target.start) * 1000) / 1000,
      color: target.color || '#3b82f6'
    };
    const segB = {
      id: `split-${Date.now()}-B`,
      name: `Clip Part ${targetIdx + 1}B`,
      start: cur,
      end: target.end,
      duration: Math.round((target.end - cur) * 1000) / 1000,
      color: '#10b981'
    };

    const next = [...splitSegments];
    next.splice(targetIdx, 1, segA, segB);
    setSplitSegments(next);
    recordAction(`Chia clip tại mốc ${formatTimeSec(cur)}`, 'split_clip', { splitSegments: next });
  };

  const handleExecuteExportSplit = async () => {
    if (!selectedFile) {
      showAlert({ title: 'Chưa Chọn Video', message: 'Vui lòng chọn video cần xuất!', type: 'warning' });
      return;
    }
    if (splitSegments.length === 0) {
      showAlert({ title: 'Chưa Chia Đoạn', message: 'Vui lòng chia clip thành các đoạn trước khi xuất!', type: 'warning' });
      return;
    }

    const jobId = `studio_split_${Date.now()}`;
    setIsProcessing(true);
    setActiveJobId(jobId);

    const stem = selectedFile.name.replace(/\.[^/.]+$/, '');
    const exportedFiles = [];

    try {
      for (let i = 0; i < splitSegments.length; i++) {
        const seg = splitSegments[i];
        const outFileName = `${stem}_part${i + 1}.mp4`;
        const outRelPath = `assets/${project}/cut/${outFileName}`;
        
        const args = [
          selectedFile.relPath,
          '-s', String(Math.max(0, Math.round(seg.start * 1000) / 1000)),
          '-e', String(Math.round(seg.end * 1000) / 1000),
          '-o', outRelPath,
          '--overwrite'
        ];
        
        await runScript('trim.py', args, `${jobId}_p${i + 1}`);
        exportedFiles.push(outFileName);
      }

      await new Promise(r => setTimeout(r, 800));
      setSplitSegments([]);
      onRefresh && onRefresh();

      showAlert({
        title: 'Xuất Các Đoạn Chia Thành Công',
        message: `Đã xuất thành công ${exportedFiles.length} file video độc lập vào assets/${project}/cut/:\n${exportedFiles.join(', ')}`,
        type: 'success'
      });
    } catch (err) {
      showAlert({ title: 'Lỗi Xuất Đoạn Chia', message: err.message, type: 'danger' });
    } finally {
      setIsProcessing(false);
      setActiveJobId(null);
    }
  };

  // ── 16C. GHÉP VIDEO: NỐI TẤT CẢ FILE VIDEO VÀ SINH FILE MỚI ──────────────────
  const handleAddVideoToMerge = (file) => {
    const newItem = {
      id: `merge-${Date.now()}`,
      name: file.name,
      relPath: file.relPath,
      size: file.size || file.sizeBytes
    };
    const next = [...mergePlaylist, newItem];
    setMergePlaylist(next);
    recordAction(`Thêm video "${file.name}" vào danh sách ghép`, 'merge', { mergePlaylist: next });
  };

  const handleExecuteMerge = async (forceAutoNormalize = false) => {
    const listToMerge = mergePlaylist.length > 0 
      ? mergePlaylist.map(m => m.relPath) 
      : [selectedFile?.relPath].filter(Boolean);

    if (listToMerge.length < 2) {
      showAlert({ title: 'Cần Ít Nhất 2 Video', message: 'Vui lòng chọn từ 2 video trở lên trong danh sách để ghép!', type: 'warning' });
      return;
    }

    if (!forceAutoNormalize) {
      try {
        const compat = await checkVideoCompatibility(listToMerge);
        if (!compat.compatible) {
          setCompatReport(compat);
          setPendingMergeAction(() => () => handleExecuteMerge(true));
          setShowCompatModal(true);
          return;
        }
      } catch (e) {}
    }

    const jobId = `studio_merge_${Date.now()}`;
    setIsProcessing(true);
    setActiveJobId(jobId);
    setShowCompatModal(false);

    try {
      const args = [...listToMerge];
      if (forceAutoNormalize) args.push('--auto-normalize');
      const bitrate = exportQuality === 'high' ? '4.0M' : (exportQuality === 'medium' ? '2.5M' : '1.5M');
      args.push('-b', bitrate);

      await runScript('concat.py', args, jobId);
      await new Promise(r => setTimeout(r, 800));
      setMergePlaylist([]);
      onRefresh && onRefresh();

      showAlert({ 
        title: 'Ghép Video Mới Thành Công', 
        message: `Đã ghép ${listToMerge.length} video thành 1 file hoàn chỉnh mới trong assets/${project}/merge/!`, 
        type: 'success' 
      });
    } catch (err) {
      showAlert({ title: 'Lỗi Ghép Video', message: err.message, type: 'danger' });
    } finally {
      setIsProcessing(false);
      setActiveJobId(null);
    }
  };

  // ── 16D. TỔNG HỢP NÚT XUẤT MASTER THEO TOOL MODE ────────────────────────────
  const handleMasterExport = () => {
    if (toolMode === 'split') {
      handleExecuteExportSplit();
    } else if (toolMode === 'cut') {
      handleExecuteCutTrash();
    } else if (toolMode === 'merge') {
      handleExecuteMerge(false);
    }
  };

  // ── 17. OVERLAY ACTIONS ───────────────────────────────────────────────────
  const handleTriggerAddImageToTrack = (trackId = null) => {
    const chosenTrackId = trackId || selectedOverlayTrackId || overlayTracks[0]?.id || null;
    setTargetUploadTrackId(chosenTrackId);
    fileInputRef.current?.click();
  };

  const handleOverlayFileSelected = async (e) => {
    const file = e.target.files?.[0];
    if (!file) return;

    const reader = new FileReader();
    reader.onload = async () => {
      const base64Data = reader.result;
      try {
        const uploadRes = await uploadAsset(project, file.name, base64Data, 'src');
        let assignedTrackId = targetUploadTrackId;

        if (!assignedTrackId || !overlayTracks.some(t => t.id === assignedTrackId)) {
          const newTrack = {
            id: `track-ov-${Date.now()}`,
            name: `Lớp phủ ${overlayTracks.length + 1}`,
            visible: true,
            locked: false
          };
          setOverlayTracks(prev => [newTrack, ...prev]);
          assignedTrackId = newTrack.id;
          setSelectedOverlayTrackId(newTrack.id);
        }

        const newOverlay = {
          id: `ov-${Date.now()}`,
          trackId: assignedTrackId,
          name: file.name.replace(/\.[^/.]+$/, ''),
          imageSrc: base64Data,
          relPath: uploadRes.relPath,
          start: Math.max(0, currentTime),
          end: Math.min(duration, currentTime + 15),
          x: 50,
          y: 50,
          width: 20,
          height: 20,
          opacity: 1.0,
          borderRadius: 8
        };

        const nextClips = [...overlayClips, newOverlay];
        setOverlayClips(nextClips);
        setActiveSelection({ type: 'overlay', id: newOverlay.id });
        setActiveRightTab('overlay');
        recordAction(`Thêm hình ảnh "${file.name}" vào làn lớp phủ`, 'overlay', { overlayTracks, overlayClips: nextClips });
      } catch (err) {
        showAlert({ title: 'Lỗi Tải Ảnh Lớp Phủ', message: err.message, type: 'danger' });
      }
    };
    reader.readAsDataURL(file);
    e.target.value = '';
  };

  const handleDeleteOverlayClip = (id) => {
    const next = overlayClips.filter(o => o.id !== id);
    setOverlayClips(next);
    setActiveSelection({ type: 'range', id: 'range' });
    recordAction('Xóa hình ảnh lớp phủ', 'overlay', { overlayClips: next });
  };

  const handleChangeClipTrack = (clipId, newTrackId) => {
    setOverlayClips(prev => prev.map(c => c.id === clipId ? { ...c, trackId: newTrackId } : c));
    const targetTrack = overlayTracks.find(t => t.id === newTrackId);
    recordAction(`Chuyển hình ảnh sang ${targetTrack?.name || 'Làn khác'}`, 'overlay', { overlayClips });
  };

  const activeOverlayClip = useMemo(() => {
    if (activeSelection?.type === 'overlay') {
      return overlayClips.find(ov => ov.id === activeSelection.id);
    }
    return overlayClips.find(ov => currentTime >= ov.start && currentTime <= ov.end);
  }, [overlayClips, activeSelection, currentTime]);

  const handleGizmoMouseDown = (action, e, clip, isLocked) => {
    e.stopPropagation();
    if (isLocked) return;
    setActiveSelection({ type: 'overlay', id: clip.id });
    setIsDraggingGizmo({
      action,
      clipId: clip.id,
      startX: e.clientX,
      startY: e.clientY,
      initialX: clip.x,
      initialY: clip.y,
      initialWidth: clip.width,
      initialHeight: clip.height
    });
  };

  // ── 17b. SUBTITLE SCREEN DRAGGING HANDLER ──────────────────────────────────
  const handleSubtitleMouseDown = (e) => {
    e.stopPropagation();
    setActiveSelection({ type: 'sub', id: currentVisibleSubtitle?.id || 'sub-1' });
    setActiveRightTab('sub');
    setIsDraggingSub({
      startX: e.clientX,
      startY: e.clientY,
      initialX: subtitlePos.x,
      initialY: subtitlePos.y
    });
  };

  useEffect(() => {
    const handleMouseMove = (e) => {
      if (!videoScreenRef.current) return;
      const rect = videoScreenRef.current.getBoundingClientRect();

      if (isDraggingGizmo) {
        const targetClip = overlayClips.find(o => o.id === isDraggingGizmo.clipId);
        if (!targetClip) return;
        const track = overlayTracks.find(t => t.id === targetClip.trackId);
        if (track?.locked) return;

        const deltaXPercent = ((e.clientX - isDraggingGizmo.startX) / rect.width) * 100;
        const deltaYPercent = ((e.clientY - isDraggingGizmo.startY) / rect.height) * 100;

        if (isDraggingGizmo.action === 'move') {
          const newX = Math.max(0, Math.min(100 - targetClip.width, isDraggingGizmo.initialX + deltaXPercent));
          const newY = Math.max(0, Math.min(100 - targetClip.height, isDraggingGizmo.initialY + deltaYPercent));
          setOverlayClips(prev => prev.map(o => o.id === targetClip.id ? { ...o, x: newX, y: newY } : o));
        } else if (isDraggingGizmo.action === 'resize-br') {
          const newW = Math.max(5, Math.min(80, isDraggingGizmo.initialWidth + deltaXPercent));
          const newH = Math.max(5, Math.min(80, isDraggingGizmo.initialHeight + deltaYPercent));
          setOverlayClips(prev => prev.map(o => o.id === targetClip.id ? { ...o, width: newW, height: newH } : o));
        }
      }

      if (isDraggingSub) {
        const deltaXPercent = ((e.clientX - isDraggingSub.startX) / rect.width) * 100;
        const deltaYPercent = ((e.clientY - isDraggingSub.startY) / rect.height) * 100;
        const newX = Math.max(10, Math.min(90, Math.round((isDraggingSub.initialX + deltaXPercent) * 10) / 10));
        const newY = Math.max(5, Math.min(95, Math.round((isDraggingSub.initialY + deltaYPercent) * 10) / 10));
        setSubtitlePos({ x: newX, y: newY });
      }
    };

    const handleMouseUp = () => {
      if (isDraggingGizmo) {
        setIsDraggingGizmo(null);
        recordAction('Điều chỉnh vị trí/kích thước lớp phủ', 'overlay', { overlayClips });
      }
      if (isDraggingSub) {
        setIsDraggingSub(null);
        recordAction(`Di chuyển vị trí phụ đề: X=${Math.round(subtitlePos.x)}%, Y=${Math.round(subtitlePos.y)}%`, 'subtitle_pos', { subtitlePos });
      }
    };

    if (isDraggingGizmo || isDraggingSub) {
      window.addEventListener('mousemove', handleMouseMove);
      window.addEventListener('mouseup', handleMouseUp);
    }
    return () => {
      window.removeEventListener('mousemove', handleMouseMove);
      window.removeEventListener('mouseup', handleMouseUp);
    };
  }, [isDraggingGizmo, isDraggingSub, overlayClips, overlayTracks, subtitlePos, recordAction]);

  // ── 18. MULTI-AUDIO TRACK ACTIONS ──────────────────────────────────────────
  const handleAddAudio = () => {
    audioInputRef.current?.click();
  };

  const handleAudioFileSelected = async (e) => {
    const file = e.target.files?.[0];
    if (!file) return;

    const reader = new FileReader();
    reader.onload = async () => {
      const base64Data = reader.result;
      try {
        const uploadRes = await uploadAsset(project, file.name, base64Data, 'src');
        const audioSrcUrl = uploadRes.relPath ? getMediaUrl(uploadRes.relPath, mediaCacheKey) : base64Data;
        
        const newAudio = {
          id: `aud-${Date.now()}`,
          name: file.name,
          relPath: uploadRes.relPath,
          audioSrc: audioSrcUrl,
          start: Math.max(0, currentTime),
          duration: 10.0,
          volume: 80,
          loop: false,
          fadeIn: 0.5,
          fadeOut: 1.0,
          track: targetAudioTrack || 'audio1'
        };

        // Đo thời lượng thực tế của file âm thanh
        const tempAudio = new Audio(base64Data);
        tempAudio.preload = 'metadata';
        tempAudio.onloadedmetadata = () => {
          if (tempAudio.duration && !isNaN(tempAudio.duration) && tempAudio.duration > 0) {
            const exactDur = Math.round(tempAudio.duration * 100) / 100;
            setAudioClips(prev => prev.map(a => a.id === newAudio.id ? { ...a, duration: exactDur } : a));
          }
        };

        const next = [...audioClips, newAudio];
        setAudioClips(next);
        setActiveSelection({ type: 'audio', id: newAudio.id });
        setActiveRightTab('audio');
        recordAction(`Thêm file âm thanh: ${file.name} vào làn ${targetAudioTrack === 'audio2' ? 'Hiệu ứng' : 'Nhạc nền'}`, 'audio', { audioClips: next });
      } catch (err) {
        showAlert({ title: 'Lỗi Tải File Âm Thanh', message: err.message, type: 'danger' });
      }
    };
    reader.readAsDataURL(file);
    e.target.value = '';
  };

  const handleDeleteAudio = (id) => {
    const next = audioClips.filter(a => a.id !== id);
    setAudioClips(next);
    setActiveSelection({ type: 'range', id: 'range' });
    recordAction('Xóa file audio', 'audio', { audioClips: next });
  };

  // ── 19. SUBTITLE TRACK ACTIONS ─────────────────────────────────────────────
  const handleAddSubtitle = () => {
    const start = Math.max(0, currentTime);
    const end = Math.min(effectiveDur, start + 3.5);
    const newSub = {
      id: `sub-${Date.now()}`,
      start,
      end,
      textOrig: 'New Subtitle Cue',
      textTrans: 'Câu phụ đề mới'
    };
    const next = [...subtitles, newSub];
    setSubtitles(next);
    setActiveSelection({ type: 'sub', id: newSub.id });
    setActiveRightTab('sub');
    handleSeek(start + 0.05);
    recordAction('Thêm câu phụ đề mới', 'subtitle', { subtitles: next });
  };

  const handleDeleteSubtitle = (id) => {
    const next = subtitles.filter(s => s.id !== id);
    setSubtitles(next);
    setActiveSelection({ type: 'range', id: 'range' });
    recordAction('Xóa câu phụ đề', 'subtitle', { subtitles: next });
  };

  // Phụ đề hiển thị trên khung video: CHỈ hiển thị khi thời gian currentTime nằm chính xác trong [start, end]
  const currentVisibleSubtitle = useMemo(() => {
    return subtitles.find(s => currentTime >= (s.start - 0.05) && currentTime <= (s.end + 0.05));
  }, [subtitles, currentTime]);

  // Phụ đề đang được chọn để chỉnh sửa bên Panel Thuộc Tính
  const selectedSubtitle = useMemo(() => {
    if (activeSelection?.type === 'sub') {
      return subtitles.find(s => s.id === activeSelection.id);
    }
    return currentVisibleSubtitle;
  }, [subtitles, activeSelection, currentVisibleSubtitle]);

  // ── 20. TIMELINE DRAG CONTROLLER ──────────────────────────────────────────
  const startRatio = Math.max(0, Math.min(1, startTime / effectiveDur));
  const endRatio = Math.max(0, Math.min(1, endTime / effectiveDur));
  const playheadRatio = Math.max(0, Math.min(1, currentTime / effectiveDur));

  const handleStartTrackDrag = (type, id, mode, e) => {
    e.stopPropagation();

    let initialStart = 0;
    let initialEnd = 0;

    if (type === 'range') {
      initialStart = startTime;
      initialEnd = endTime;
    } else if (type === 'overlay') {
      setActiveSelection({ type, id });
      const target = overlayClips.find(o => o.id === id);
      if (target) {
        const track = overlayTracks.find(t => t.id === target.trackId);
        if (track?.locked) return;
        initialStart = target.start;
        initialEnd = target.end;
      }
    } else if (type === 'audio') {
      setActiveSelection({ type, id });
      const target = audioClips.find(a => a.id === id);
      if (target) { initialStart = target.start; initialEnd = target.start + target.duration; }
    } else if (type === 'sub') {
      setActiveSelection({ type, id });
      const target = subtitles.find(s => s.id === id);
      if (target) { initialStart = target.start; initialEnd = target.end; }
    }

    setDraggingTarget({
      type,
      id,
      mode,
      startX: e.clientX,
      initialStart,
      initialEnd
    });
  };

  const handleMoveMergeItem = (fromIdx, toIdx) => {
    if (toIdx < 0 || toIdx >= mergePlaylist.length || fromIdx === toIdx) return;
    const next = [...mergePlaylist];
    const [moved] = next.splice(fromIdx, 1);
    next.splice(toIdx, 0, moved);
    setMergePlaylist(next);
    recordAction(`Đổi thứ tự video ghép: "${moved.name}" sang vị trí #${toIdx + 1}`, 'merge', { mergePlaylist: next });
  };

  useEffect(() => {
    const handleMouseMove = (e) => {
      if (!draggingTarget || !timelineTrackRef.current) return;
      const rect = timelineTrackRef.current.getBoundingClientRect();
      const scrollLeft = timelineTrackRef.current.scrollLeft || 0;
      const totalWidth = rect.width * zoomLevel;
      const deltaSec = ((e.clientX - draggingTarget.startX) / totalWidth) * effectiveDur;

      if (draggingTarget.mode === 'playhead') {
        const clickX = e.clientX - rect.left + scrollLeft;
        const ratio = Math.max(0, Math.min(1, clickX / totalWidth));
        handleSeek(ratio * effectiveDur);
        return;
      }

      if (draggingTarget.type === 'range') {
        let newSt = startTime;
        let newEn = endTime;

        if (draggingTarget.mode === 'move') {
          const dur = draggingTarget.initialEnd - draggingTarget.initialStart;
          newSt = Math.max(0, Math.min(effectiveDur - dur, draggingTarget.initialStart + deltaSec));
          newEn = Math.min(effectiveDur, newSt + dur);
        } else if (draggingTarget.mode === 'left') {
          newSt = Math.max(0, Math.min(draggingTarget.initialStart + deltaSec, endTime - 0.05));
        } else if (draggingTarget.mode === 'right') {
          newEn = Math.max(startTime + 0.05, Math.min(effectiveDur, draggingTarget.initialEnd + deltaSec));
        }

        setStartTime(newSt);
        setEndTime(newEn);
      } else if (draggingTarget.type === 'overlay') {
        setOverlayClips(prev => prev.map(o => {
          if (o.id !== draggingTarget.id) return o;
          const track = overlayTracks.find(t => t.id === o.trackId);
          if (track?.locked) return o;

          if (draggingTarget.mode === 'move') {
            const dur = draggingTarget.initialEnd - draggingTarget.initialStart;
            const newSt = Math.max(0, Math.min(effectiveDur - dur, draggingTarget.initialStart + deltaSec));
            return { ...o, start: newSt, end: Math.min(effectiveDur, newSt + dur) };
          } else if (draggingTarget.mode === 'left') {
            const newSt = Math.max(0, Math.min(o.end - 0.5, draggingTarget.initialStart + deltaSec));
            return { ...o, start: newSt };
          } else if (draggingTarget.mode === 'right') {
            const newEn = Math.max(o.start + 0.5, Math.min(effectiveDur, draggingTarget.initialEnd + deltaSec));
            return { ...o, end: newEn };
          }
          return o;
        }));
      } else if (draggingTarget.type === 'audio') {
        setAudioClips(prev => prev.map(a => {
          if (a.id !== draggingTarget.id) return a;
          if (draggingTarget.mode === 'move') {
            const newSt = Math.max(0, Math.min(effectiveDur - 0.5, draggingTarget.initialStart + deltaSec));
            const newDur = Math.min(a.duration, effectiveDur - newSt);
            return { ...a, start: newSt, duration: Math.max(0.5, newDur) };
          } else if (draggingTarget.mode === 'right') {
            const requestedDur = (draggingTarget.initialEnd + deltaSec) - a.start;
            const clampedDur = Math.max(0.5, Math.min(effectiveDur - a.start, requestedDur));
            return { ...a, duration: clampedDur };
          }
          return a;
        }));
      } else if (draggingTarget.type === 'sub') {
        setSubtitles(prev => prev.map(s => {
          if (s.id !== draggingTarget.id) return s;
          if (draggingTarget.mode === 'move') {
            const dur = draggingTarget.initialEnd - draggingTarget.initialStart;
            const newSt = Math.max(0, Math.min(effectiveDur - dur, draggingTarget.initialStart + deltaSec));
            return { ...s, start: newSt, end: Math.min(effectiveDur, newSt + dur) };
          } else if (draggingTarget.mode === 'left') {
            const newSt = Math.max(0, Math.min(s.end - 0.2, draggingTarget.initialStart + deltaSec));
            return { ...s, start: newSt };
          } else if (draggingTarget.mode === 'right') {
            const newEn = Math.max(s.start + 0.2, Math.min(effectiveDur, draggingTarget.initialEnd + deltaSec));
            return { ...s, end: newEn };
          }
          return s;
        }));
      }
    };

    const handleMouseUp = () => {
      if (draggingTarget) {
        setDraggingTarget(null);
        recordAction(`Kéo chỉnh timeline: ${draggingTarget.type}`, draggingTarget.type, {
          cutSegments, splitSegments, mergePlaylist, overlayTracks, overlayClips, audioClips, subtitles, startTime, endTime
        });
      }
    };

    window.addEventListener('mousemove', handleMouseMove);
    window.addEventListener('mouseup', handleMouseUp);
    return () => {
      window.removeEventListener('mousemove', handleMouseMove);
      window.removeEventListener('mouseup', handleMouseUp);
    };
  }, [draggingTarget, effectiveDur, duration, startTime, endTime, cutSegments, splitSegments, mergePlaylist, overlayTracks, overlayClips, audioClips, subtitles, recordAction]);

  return (
    <div style={styles.container}>
      <input type="file" ref={fileInputRef} accept="image/*" style={{ display: 'none' }} onChange={handleOverlayFileSelected} />
      <input type="file" ref={audioInputRef} accept="audio/*" style={{ display: 'none' }} onChange={handleAudioFileSelected} />

      {/* ── TOP BAR HEADER ──────────────────────────────────────────────────── */}
      <header style={styles.topHeader}>
        <div style={styles.headerLeft}>
          <div style={styles.brandTitle}>Video Studio</div>
          <span style={styles.breadcrumbDivider}>&gt;</span>
          <span style={styles.breadcrumbSub}>Video Editor</span>
          <span style={styles.breadcrumbDivider}>&gt;</span>
          <span style={styles.breadcrumbActive}>
            {toolMode === 'cut' ? 'Cắt bỏ đoạn rác' : (toolMode === 'split' ? 'Chia clip' : 'Ghép video')}
          </span>
        </div>

        <div style={styles.headerCenter}>
          <button 
            style={styles.videoSwitcherBtn}
            onClick={() => setShowVideoSwitcherModal(true)}
            title="Click để đổi sang video khác trong dự án"
          >
            <VideoIcon size={14} color="#a855f7" />
            <span style={styles.fileNameText}>{selectedFile ? selectedFile.name : 'Chọn video'}</span>
            <span style={styles.switchBadge}><RefreshCw size={10} /> Đổi video</span>
          </button>

          <span style={styles.savedBadge}>Đã lưu {actionHistory[actionHistory.length - 1]?.time || '11:15'}</span>
          <div style={styles.historyIcons}>
            <button 
              style={{ ...styles.iconBtn, opacity: historyIndex > 0 ? 1 : 0.4 }} 
              onClick={handleUndo} 
              disabled={historyIndex <= 0}
              title="Hoàn tác (Ctrl+Z)"
            >
              <RotateCcw size={14} />
            </button>
            <button 
              style={{ ...styles.iconBtn, opacity: historyIndex < actionHistory.length - 1 ? 1 : 0.4 }} 
              onClick={handleRedo} 
              disabled={historyIndex >= actionHistory.length - 1}
              title="Làm lại (Ctrl+Shift+Z)"
            >
              <RotateCw size={14} />
            </button>
          </div>
        </div>

        <div style={styles.headerRight}>
          <button style={styles.draftBtn} onClick={() => showAlert({ title: 'Đã Lưu Nháp', message: 'Trạng thái chỉnh sửa đã được lưu tự động!', type: 'success' })}>
            <Save size={14} /> Lưu nháp
          </button>
          <button 
            style={styles.primaryExportBtn}
            onClick={handleMasterExport}
            disabled={isProcessing}
          >
            <Download size={14} />
            <span>{isProcessing ? 'Đang Xử Lý...' : (toolMode === 'split' ? 'Xuất các đoạn chia' : (toolMode === 'cut' ? 'Cắt bỏ & Xuất' : 'Ghép & Xuất video'))}</span>
          </button>
          <button style={styles.iconBtn} onClick={() => setShowMoreMenu(!showMoreMenu)} title="Tuỳ chọn khác">
            <MoreHorizontal size={16} />
          </button>
          <button style={styles.iconBtn} onClick={() => onSelectTab && onSelectTab('config')} title="Cấu hình (Config YAML)">
            <Settings size={15} />
          </button>
          <button style={styles.iconBtn} onClick={() => setShowShortcutsModal(true)} title="Trợ giúp & Phím tắt">
            <HelpCircle size={15} />
          </button>
        </div>
      </header>

      {/* ── MAIN STUDIO BODY ────────────────────────────────────────────────── */}
      <div style={styles.mainCanvas}>
        <div style={styles.upperSection}>
          
          {/* 1. VIDEO PREVIEW CANVAS (50%) */}
          <div style={styles.playerColumn}>
            <div style={styles.videoScreenWrapper} ref={videoScreenRef}>
              <div style={styles.resolutionBadge}>{videoResolution}</div>
              <div style={styles.aspectBadge}>{aspectRatio}</div>

              {origAudioMuted && (
                <div style={styles.audioModePill}>
                  <VolumeX size={11} color="#ef4444" />
                  <span>Video gốc: Muted (Chỉ BGM/SFX)</span>
                </div>
              )}

              {isIsolatedPreview && (
                <div style={styles.isolatedPreviewBadge}>
                  ✨ Đang xem đoạn: {formatShortTime(startTime)} - {formatShortTime(endTime)}
                  <button style={styles.closeIsolatedBtn} onClick={() => setIsIsolatedPreview(false)} title="Xem toàn bộ video">✕</button>
                </div>
              )}

              {/* EMPTY PLACEHOLDER WHEN NO VIDEO SELECTED OR VIDEO DELETED */}
              {!selectedFile && toolMode !== 'merge' && (
                <div style={{
                  position: 'absolute',
                  inset: 0,
                  display: 'flex',
                  flexDirection: 'column',
                  alignItems: 'center',
                  justifyContent: 'center',
                  background: '#090d16',
                  zIndex: 20,
                  color: 'var(--text-muted)'
                }}>
                  <Film size={44} color="var(--text-dim)" style={{ marginBottom: 12 }} />
                  <span style={{ fontSize: 14, fontWeight: 500 }}>Chưa có video nào được chọn hoặc video đã bị xóa</span>
                  <span style={{ fontSize: 12, color: 'var(--text-dim)', marginTop: 4 }}>Chọn một video từ danh sách hoặc đổi tab Thư viện</span>
                  <button
                    style={{
                      marginTop: 14,
                      padding: '7px 14px',
                      background: 'rgba(59, 130, 246, 0.15)',
                      border: '1px solid rgba(59, 130, 246, 0.4)',
                      borderRadius: 6,
                      color: '#60a5fa',
                      fontSize: 13,
                      fontWeight: 500,
                      cursor: 'pointer'
                    }}
                    onClick={() => setShowVideoSwitcherModal(true)}
                  >
                    Chọn video từ dự án
                  </button>
                </div>
              )}

              {/* DUAL PLAYER A & B PING-PONG ENGINE (CHUYỂN CẢNH 0MS LIỀN MẠCH) */}
              <video
                ref={videoRefA}
                src={playerASrc || undefined}
                style={{
                  ...styles.videoElement,
                  opacity: activePlayer === 'A' ? 1 : 0,
                  zIndex: activePlayer === 'A' ? 5 : 1,
                  pointerEvents: activePlayer === 'A' ? 'auto' : 'none'
                }}
                onLoadedMetadata={handleLoadedMetadata}
                onClick={togglePlay}
                playsInline
              />

              <video
                ref={videoRefB}
                src={playerBSrc || undefined}
                style={{
                  ...styles.videoElement,
                  position: 'absolute',
                  top: 0,
                  left: 0,
                  width: '100%',
                  height: '100%',
                  opacity: activePlayer === 'B' ? 1 : 0,
                  zIndex: activePlayer === 'B' ? 5 : 1,
                  pointerEvents: activePlayer === 'B' ? 'auto' : 'none'
                }}
                onLoadedMetadata={handleLoadedMetadata}
                onClick={togglePlay}
                playsInline
              />

              {/* Interactive Image Overlays */}
              {overlayTracks.slice().reverse().map((track, trackIdx) => {
                if (!track.visible) return null;
                const clipsInTrack = overlayClips.filter(c => c.trackId === track.id);
                const layerNumber = trackIdx + 1;
                const zIndex = 15 + layerNumber * 5;

                return clipsInTrack.map(ov => {
                  const isVisibleAtTime = currentTime >= ov.start && currentTime <= ov.end;
                  if (!isVisibleAtTime) return null;
                  const isSel = activeSelection?.type === 'overlay' && activeSelection.id === ov.id;

                  return (
                    <div
                      key={ov.id}
                      style={{
                        position: 'absolute',
                        left: `${ov.x}%`,
                        top: `${ov.y}%`,
                        width: `${ov.width}%`,
                        height: `${ov.height}%`,
                        opacity: ov.opacity,
                        border: isSel ? '2px dashed #a855f7' : '1px solid rgba(255,255,255,0.4)',
                        boxShadow: isSel ? '0 0 16px rgba(168,85,247,0.85)' : 'none',
                        cursor: track.locked ? 'default' : 'move',
                        borderRadius: ov.borderRadius,
                        overflow: 'visible',
                        zIndex
                      }}
                      onClick={(e) => {
                        e.stopPropagation();
                        setActiveSelection({ type: 'overlay', id: ov.id });
                        setActiveRightTab('overlay');
                      }}
                      onMouseDown={(e) => handleGizmoMouseDown('move', e, ov, track.locked)}
                    >
                      <img
                        src={ov.imageSrc}
                        alt={ov.name}
                        style={{ width: '100%', height: '100%', objectFit: 'contain', pointerEvents: 'none' }}
                      />
                      <span style={styles.overlayLayerBadge}>{track.name} (T{layerNumber}) {track.locked ? '🔒' : ''}</span>
                      {isSel && !track.locked && (
                        <div style={styles.gizmoHandleBR} onMouseDown={(e) => handleGizmoMouseDown('resize-br', e, ov, track.locked)} />
                      )}
                    </div>
                  );
                });
              })}

              {/* Subtitle On-Screen Overlay Preview (Chỉ hiện khi đúng mốc thời gian câu sub) */}
              {trackStates.sub.visible && currentVisibleSubtitle && (
                <div 
                  style={{
                    position: 'absolute',
                    left: `${subtitlePos.x}%`,
                    top: `${subtitlePos.y}%`,
                    transform: 'translate(-50%, -50%)',
                    display: 'flex',
                    flexDirection: 'column',
                    alignItems: 'center',
                    gap: 3,
                    zIndex: 999,
                    cursor: 'grab',
                    padding: subStyle.showSubBox ? '6px 14px' : '2px 6px',
                    borderRadius: subStyle.showSubBox ? 6 : 0,
                    backgroundColor: subStyle.showSubBox ? subStyle.boxBgColor : 'transparent',
                    border: activeSelection?.type === 'sub' && activeSelection.id === currentVisibleSubtitle.id ? '2px dashed #facc15' : '1px dashed transparent',
                    boxShadow: activeSelection?.type === 'sub' && activeSelection.id === currentVisibleSubtitle.id 
                      ? '0 0 16px rgba(250, 204, 21, 0.75)' 
                      : (subStyle.showSubBox ? '0 4px 12px rgba(0,0,0,0.5)' : 'none'),
                    userSelect: 'none'
                  }}
                  onClick={(e) => {
                    e.stopPropagation();
                    setActiveSelection({ type: 'sub', id: currentVisibleSubtitle.id });
                    setActiveRightTab('sub');
                  }}
                  onMouseDown={handleSubtitleMouseDown}
                  title="Kéo chuột để di chuyển vị trí phụ đề"
                >
                  {currentVisibleSubtitle.textOrig && (
                    <div style={{
                      fontFamily: getFontFamilyCSS(subStyle.fontFamily),
                      fontSize: Math.max(10, subStyle.fontSize - 6),
                      color: subStyle.origColor,
                      textAlign: 'center',
                      opacity: 0.85,
                      textShadow: subStyle.hasDropShadow ? '0 2px 4px rgba(0,0,0,0.9)' : 'none'
                    }}>
                      {currentVisibleSubtitle.textOrig}
                    </div>
                  )}
                  {currentVisibleSubtitle.textTrans && (
                    <div style={{
                      fontFamily: getFontFamilyCSS(subStyle.fontFamily),
                      fontSize: subStyle.fontSize,
                      color: subStyle.fontColor,
                      fontWeight: subStyle.isBold ? 700 : 500,
                      fontStyle: subStyle.isItalic ? 'italic' : 'normal',
                      textAlign: 'center',
                      lineHeight: 1.25,
                      textShadow: subStyle.hasDropShadow ? '0 2px 5px rgba(0,0,0,0.95), 0 0 2px #000' : 'none'
                    }}>
                      {currentVisibleSubtitle.textTrans}
                    </div>
                  )}
                  {activeSelection?.type === 'sub' && activeSelection.id === currentVisibleSubtitle.id && (
                    <span style={styles.subPosBadge}>💬 {subStyle.fontFamily} {subStyle.fontSize}px ({Math.round(subtitlePos.x)}%, {Math.round(subtitlePos.y)}%)</span>
                  )}
                </div>
              )}
            </div>

            {/* Video Controls Bar */}
            <div style={styles.playerControlsBar}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
                <button style={styles.playBtn} onClick={togglePlay} title="Phát / Dừng (Space)">
                  {isPlaying ? <Pause size={16} fill="white" /> : <Play size={16} fill="white" />}
                </button>
                <button style={styles.stepBtn} onClick={() => handleSeek(currentTime - 1)} title="Lùi 1s">⏮</button>
                <button style={styles.stepBtn} onClick={() => handleSeek(currentTime + 1)} title="Tiến 1s">⏭</button>
                <div style={styles.timecodeDisplay}>
                  <span style={{ color: 'white', fontWeight: 600 }}>{formatTimecodeMs(currentTime)}</span>
                  <span style={{ color: 'var(--text-dim)' }}> / {formatTimecodeMs(effectiveDur)}</span>
                </div>
              </div>

              <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
                <div style={styles.volumeGroup}>
                  <button style={styles.stepBtn} onClick={() => setIsMuted(!isMuted)}>
                    {isMuted || volume === 0 ? <VolumeX size={14} /> : (volume < 0.5 ? <Volume1 size={14} /> : <Volume2 size={14} />)}
                  </button>
                  <input
                    type="range"
                    min="0"
                    max="1"
                    step="0.05"
                    value={isMuted ? 0 : volume}
                    onChange={(e) => {
                      const v = parseFloat(e.target.value);
                      setVolume(v);
                      if (videoRef.current) videoRef.current.volume = v;
                    }}
                    style={styles.volumeSlider}
                  />
                </div>

                <button style={styles.iconBtn} onClick={handleTakeSnapshot} title="Chụp ảnh khung hình (Snapshot PNG)">
                  <Camera size={15} />
                </button>
                <button style={styles.iconBtn} onClick={() => videoRef.current?.requestFullscreen?.()} title="Toàn màn hình">
                  <Maximize size={15} />
                </button>
              </div>
            </div>
          </div>

          {/* 2. CỘT GIỮA: CÁC THAO TÁC CẮT BỎ | CHIA CLIP | GHÉP VIDEO (25%) */}
          <div style={styles.centerCutAndSegmentsColumn}>
            <div style={styles.cutToolsTopSection}>
              {/* ── CHẾ ĐỘ 1: CẮT BỎ ĐOẠN RÁC ── */}
              {toolMode === 'cut' && (
                <div style={styles.timeInputBox}>
                  <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
                    <div style={{ fontSize: 10, color: '#f87171', fontWeight: 700 }}>
                      ✂️ Khung chọn đoạn rác (Mặc định 10s):
                    </div>
                    <button
                      style={{
                        ...styles.miniToggleCutBtn,
                        backgroundColor: showCutBox ? 'rgba(239, 68, 68, 0.2)' : 'rgba(255, 255, 255, 0.06)',
                        borderColor: showCutBox ? '#ef4444' : 'rgba(255, 255, 255, 0.1)',
                        color: showCutBox ? '#f87171' : 'var(--text-dim)'
                      }}
                      onClick={() => setShowCutBox(!showCutBox)}
                      title={showCutBox ? "Ẩn khung tím trên timeline" : "Hiện khung tím trên timeline"}
                    >
                      {showCutBox ? <Eye size={11} /> : <EyeOff size={11} />}
                      <span>{showCutBox ? 'Đang hiện' : 'Đã ẩn'}</span>
                    </button>
                  </div>

                  <div style={styles.quickCutPresetRow}>
                    <button 
                      style={styles.quickCutPresetBtn}
                      onClick={handleSetCutRange10sAtCurrent}
                      title="Đặt khung cắt 10s bắt đầu từ vị trí Playhead hiện tại"
                    >
                      📍 Đặt 10s tại Playhead
                    </button>
                    <button 
                      style={styles.quickCutPresetBtn}
                      onClick={() => {
                        setStartTime(0);
                        setEndTime(Math.min(duration, 10.0));
                        setShowCutBox(true);
                      }}
                      title="Đặt khung cắt 10s ở đầu video (0s - 10s)"
                    >
                      🔄 10s đầu
                    </button>
                  </div>

                  <div style={styles.timeInputRow}>
                    <span style={styles.timeInputLabel}>Bắt đầu:</span>
                    <div style={styles.timeInputWrapper}>
                      <input
                        type="text"
                        value={startInputStr}
                        onChange={e => setStartInputStr(e.target.value)}
                        onBlur={() => {
                          const p = parseTimecode(startInputStr);
                          setStartTime(Math.max(0, Math.min(p, endTime - 0.05)));
                        }}
                        style={styles.timeTextInput}
                      />
                      <button style={styles.miniClockBtn} onClick={() => setStartTime(currentTime)} title="Lấy mốc Playhead hiện tại">
                        <Clock size={12} color="#a855f7" />
                      </button>
                    </div>
                  </div>

                  <div style={styles.timeInputRow}>
                    <span style={styles.timeInputLabel}>Kết thúc:</span>
                    <div style={styles.timeInputWrapper}>
                      <input
                        type="text"
                        value={endInputStr}
                        onChange={e => setEndInputStr(e.target.value)}
                        onBlur={() => {
                          const p = parseTimecode(endInputStr);
                          setEndTime(Math.max(startTime + 0.05, Math.min(p, duration)));
                        }}
                        style={styles.timeTextInput}
                      />
                      <button style={styles.miniClockBtn} onClick={() => setEndTime(currentTime)} title="Lấy mốc Playhead hiện tại">
                        <Clock size={12} color="#a855f7" />
                      </button>
                    </div>
                  </div>

                  <button style={styles.addToListBtn} onClick={handleAddCutTrashSegment}>
                    <Plus size={12} /> + Thêm đoạn rác này vào danh sách
                  </button>
                </div>
              )}

              {/* ── CHẾ ĐỘ 2: CHIA CLIP TẠI CHỖ ── */}
              {toolMode === 'split' && (
                <div style={styles.splitToolBox}>
                  <div style={{ fontSize: 10, color: '#60a5fa', fontWeight: 700 }}>
                    🔀 Chia clip tại vị trí con trỏ Playhead:
                  </div>
                  <div style={{ fontSize: 11, fontFamily: 'monospace', color: 'white' }}>
                    Vị trí chia: <b>{formatTimecodeMs(currentTime)}</b>
                  </div>
                  <button style={styles.splitExecuteBtn} onClick={handleExecuteSplit}>
                    <Split size={14} /> Chia đôi clip tại đây (Giữ lại tất cả)
                  </button>
                </div>
              )}

              {/* ── CHẾ ĐỘ 3: GHÉP NHIỀU VIDEO ── */}
              {toolMode === 'merge' && (
                <div style={styles.mergeToolBox}>
                  <div style={{ fontSize: 10, color: '#34d399', fontWeight: 700 }}>
                    🥞 Danh sách video cần ghép ({mergePlaylist.length} file):
                  </div>
                  <button style={styles.addVideoMergeBtn} onClick={() => setIsMediaBinOpen(true)}>
                    <Plus size={12} /> + Chọn video từ thư viện
                  </button>
                </div>
              )}
            </div>

            {/* Bottom Sub-Card: DANH SÁCH THAO TÁC THEO CHẾ ĐỘ */}
            <div style={styles.segmentsBottomSection}>
              {toolMode === 'cut' && (
                <>
                  <div style={styles.segmentHeaderRow}>
                    <div style={styles.panelTitle}>Danh sách đoạn rác cần cắt bỏ ({cutSegments.length})</div>
                  </div>

                  <div style={styles.segmentsListScroll}>
                    {cutSegments.length === 0 ? (
                      <div style={styles.emptySegmentsNotice}>
                        💡 Hãy kéo khung tím trên timeline để chọn vùng rác, sau đó bấm <b>+ Thêm đoạn rác này vào danh sách</b>.
                      </div>
                    ) : (
                      cutSegments.map((seg) => (
                        <div key={seg.id} style={styles.segmentCard}>
                          <div style={styles.segmentThumb}><Trash2 size={11} color="#f87171" /></div>
                          <div style={styles.segmentInfo}>
                            <div style={styles.segmentName}>{seg.name}</div>
                            <div style={styles.segmentRange}>{formatShortTime(seg.start)} - {formatShortTime(seg.end)} ({formatTimecodeMs(seg.duration)})</div>
                          </div>
                          <button style={styles.deleteSegmentBtn} onClick={() => setCutSegments(cutSegments.filter(s => s.id !== seg.id))}><X size={12} /></button>
                        </div>
                      ))
                    )}
                  </div>

                  <button style={styles.executeRemoveBtn} onClick={handleExecuteCutTrash} disabled={isProcessing}>
                    <Trash2 size={14} />
                    <span>{isProcessing ? 'Đang cắt bỏ...' : (cutSegments.length > 0 ? `Cắt bỏ ${cutSegments.length} đoạn rác & Nối lại` : 'Cắt bỏ đoạn rác đang chọn')}</span>
                  </button>
                </>
              )}

              {toolMode === 'split' && (
                <>
                  <div style={styles.segmentHeaderRow}>
                    <div style={styles.panelTitle}>Các đoạn sau khi chia ({splitSegments.length})</div>
                  </div>

                  <div style={styles.segmentsListScroll}>
                    {splitSegments.length === 0 ? (
                      <div style={styles.emptySegmentsNotice}>
                        💡 Di chuyển Playhead đến mốc thời gian và bấm <b>Chia đôi clip tại đây</b> để tách nhỏ video.
                      </div>
                    ) : (
                      splitSegments.map((seg) => (
                        <div key={seg.id} style={styles.segmentCard}>
                          <div style={{ ...styles.segmentThumb, backgroundColor: 'rgba(96, 165, 250, 0.15)' }}><Film size={11} color="#60a5fa" /></div>
                          <div style={styles.segmentInfo}>
                            <div style={styles.segmentName}>{seg.name}</div>
                            <div style={styles.segmentRange}>{formatShortTime(seg.start)} - {formatShortTime(seg.end)} ({formatTimecodeMs(seg.duration)})</div>
                          </div>
                          <button style={styles.deleteSegmentBtn} onClick={() => setSplitSegments(splitSegments.filter(s => s.id !== seg.id))}><X size={12} /></button>
                        </div>
                      ))
                    )}
                  </div>

                  <button 
                    style={{
                      ...styles.executeRemoveBtn,
                      backgroundColor: 'rgba(59, 130, 246, 0.2)',
                      borderColor: '#3b82f6',
                      color: '#60a5fa',
                      boxShadow: '0 2px 8px rgba(59, 130, 246, 0.3)'
                    }} 
                    onClick={handleExecuteExportSplit} 
                    disabled={isProcessing || splitSegments.length === 0}
                  >
                    <Sparkles size={14} color="#60a5fa" />
                    <span>{isProcessing ? 'Đang xuất các đoạn...' : (splitSegments.length > 0 ? `Xuất ${splitSegments.length} đoạn đã chia thành từng file riêng` : 'Hãy chia video thành các đoạn')}</span>
                  </button>
                </>
              )}

              {toolMode === 'merge' && (
                <>
                  <div style={styles.segmentHeaderRow}>
                    <div style={styles.panelTitle}>Thứ tự video ghép ({mergePlaylist.length})</div>
                  </div>

                  <div style={styles.segmentsListScroll}>
                    {mergePlaylist.length === 0 ? (
                      <div style={styles.emptySegmentsNotice}>
                        💡 Mở <b>Thư viện video</b> và click vào các video để thêm vào danh sách ghép.
                      </div>
                    ) : (
                      mergePlaylist.map((item, idx) => (
                        <div key={item.id} style={styles.segmentCard}>
                          <div style={{ ...styles.segmentThumb, backgroundColor: 'rgba(52, 211, 153, 0.15)' }}>
                            <span style={{ fontSize: 10, fontWeight: 700, color: '#34d399' }}>{idx + 1}</span>
                          </div>
                          <div style={styles.segmentInfo}>
                            <div style={styles.segmentName}>{item.name}</div>
                            <div style={styles.segmentRange}>{formatFileSize(item.size)}</div>
                          </div>
                          <button style={styles.deleteSegmentBtn} onClick={() => setMergePlaylist(mergePlaylist.filter(m => m.id !== item.id))}><X size={12} /></button>
                        </div>
                      ))
                    )}
                  </div>

                  <button style={styles.executeMergeBtn} onClick={() => handleExecuteMerge(false)} disabled={isProcessing || mergePlaylist.length < 2}>
                    <Sparkles size={14} />
                    <span>{isProcessing ? 'Đang Ghép...' : `Ghép ${mergePlaylist.length} video thành file mới`}</span>
                  </button>
                </>
              )}
            </div>
          </div>

          {/* 3. CỘT PHẢI: LỊCH SỬ THAO TÁC + THUỘC TÍNH */}
          <div style={styles.rightHistoryAndPropsColumn}>
            <div style={styles.historyPanel}>
              <div style={styles.segmentHeaderRow}>
                <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
                  <History size={13} color="#a855f7" />
                  <div style={styles.panelTitle}>Lịch sử thao tác</div>
                </div>
                <span style={{ fontSize: 9, color: 'var(--text-dim)' }}>{actionHistory.length} bước</span>
              </div>

              <div style={styles.historyListScroll}>
                {actionHistory.map((act, idx) => (
                  <div
                    key={act.id}
                    style={{
                      ...styles.historyItemCard,
                      ...(historyIndex === idx ? styles.historyItemActive : {})
                    }}
                    onClick={() => restoreHistoryState(idx)}
                    title="Click để khôi phục trạng thái này"
                  >
                    <div style={styles.historyDot} />
                    <div style={{ flex: 1, minWidth: 0 }}>
                      <div style={styles.historyLabel}>{act.label}</div>
                      <div style={styles.historyTime}>{act.time}</div>
                    </div>
                    {historyIndex === idx && <Check size={11} color="#34d399" />}
                  </div>
                ))}
              </div>
            </div>

            <div style={styles.exportPropsPanel}>
              <div style={styles.propsTabHeader}>
                <span 
                  style={activeRightTab === 'props' ? styles.propsTabActive : styles.propsTabInactive}
                  onClick={() => setActiveRightTab('props')}
                >
                  Thuộc tính
                </span>
                <span 
                  style={activeRightTab === 'sub' ? styles.propsTabActive : styles.propsTabInactive}
                  onClick={() => setActiveRightTab('sub')}
                >
                  Subtitle (Font/Size)
                </span>
                {activeOverlayClip && (
                  <span 
                    style={activeRightTab === 'overlay' ? styles.propsTabActive : styles.propsTabInactive}
                    onClick={() => setActiveRightTab('overlay')}
                  >
                    Lớp phủ
                  </span>
                )}
                {activeSelection?.type === 'audio' && (
                  <span 
                    style={activeRightTab === 'audio' ? styles.propsTabActive : styles.propsTabInactive}
                    onClick={() => setActiveRightTab('audio')}
                  >
                    Âm thanh
                  </span>
                )}
                <span 
                  style={activeRightTab === 'file_info' ? styles.propsTabActive : styles.propsTabInactive}
                  onClick={() => setActiveRightTab('file_info')}
                >
                  Info
                </span>
              </div>

              {/* TAB 1: THUỘC TÍNH XUẤT */}
              {activeRightTab === 'props' && (
                <div style={styles.propsScrollForm}>
                  <div style={styles.propItem}>
                    <span style={styles.propLabel}>Tên file xuất</span>
                    <input
                      type="text"
                      value={outputFileName}
                      onChange={e => setOutputFileName(e.target.value)}
                      style={styles.propInput}
                    />
                  </div>

                  <div style={styles.audioSyncStatusCard}>
                    <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
                      <span style={{ fontSize: 10, fontWeight: 700, color: '#34d399' }}>🔊 Âm Thanh Xuất (Live Sync):</span>
                      <span style={{ fontSize: 8, color: 'var(--text-dim)' }}>Đồng bộ loa</span>
                    </div>

                    <div style={styles.audioChannelStatusRow}>
                      <span style={{ fontSize: 9, color: '#cbd5e1' }}>📹 Video gốc:</span>
                      <button 
                        style={{ ...styles.audioStatusToggleBtn, ...(origAudioMuted || origAudioVolume === 0 ? styles.audioStatusMuted : styles.audioStatusActive) }}
                        onClick={() => setOrigAudioMuted(!origAudioMuted)}
                      >
                        {origAudioMuted || origAudioVolume === 0 ? '🔇 Tắt tiếng (Muted)' : `🔊 Bật (${origAudioVolume}%)`}
                      </button>
                    </div>

                    <div style={styles.audioChannelStatusRow}>
                      <span style={{ fontSize: 9, color: '#cbd5e1' }}>🎵 Nhạc nền:</span>
                      <button 
                        style={{ ...styles.audioStatusToggleBtn, ...(musicMuted || musicVolume === 0 ? styles.audioStatusMuted : styles.audioStatusActive) }}
                        onClick={() => setMusicMuted(!musicMuted)}
                      >
                        {musicMuted || musicVolume === 0 ? '🔇 Tắt tiếng' : `🎵 Bật (${musicVolume}%)`}
                      </button>
                    </div>

                    <div style={styles.audioChannelStatusRow}>
                      <span style={{ fontSize: 9, color: '#cbd5e1' }}>🎤 Hiệu ứng:</span>
                      <button 
                        style={{ ...styles.audioStatusToggleBtn, ...(sfxMuted || sfxVolume === 0 ? styles.audioStatusMuted : styles.audioStatusActive) }}
                        onClick={() => setSfxMuted(!sfxMuted)}
                      >
                        {sfxMuted || sfxVolume === 0 ? '🔇 Tắt tiếng' : `🎤 Bật (${sfxVolume}%)`}
                      </button>
                    </div>
                  </div>

                  <div style={styles.propItem}>
                    <span style={styles.propLabel}>Độ phân giải</span>
                    <select 
                      style={styles.propSelect}
                      value={exportResolution}
                      onChange={e => setExportResolution(e.target.value)}
                    >
                      <option value="original">Giữ nguyên ({videoResolution})</option>
                      <option value="1080p">1920x1080 (Full HD)</option>
                      <option value="720p">1280x720 (HD)</option>
                      <option value="4k">3840x2160 (4K)</option>
                    </select>
                  </div>

                  <div style={{ display: 'flex', gap: 6 }}>
                    <div style={{ ...styles.propItem, flex: 1 }}>
                      <span style={styles.propLabel}>FPS</span>
                      <select style={styles.propSelect} value={exportFps} onChange={e => setExportFps(e.target.value)}>
                        <option value="original">30 fps</option>
                        <option value="60">60 fps</option>
                      </select>
                    </div>

                    <div style={{ ...styles.propItem, flex: 1 }}>
                      <span style={styles.propLabel}>Tỷ lệ</span>
                      <select style={styles.propSelect} value={exportAspectRatio} onChange={e => setExportAspectRatio(e.target.value)}>
                        <option value="16:9">16:9 (Ngang)</option>
                        <option value="9:16">9:16 (TikTok)</option>
                        <option value="1:1">1:1 (Vuông)</option>
                      </select>
                    </div>
                  </div>

                  <div style={styles.propItem}>
                    <span style={styles.propLabel}>Chất lượng</span>
                    <select style={styles.propSelect} value={exportQuality} onChange={e => setExportQuality(e.target.value)}>
                      <option value="high">Cao (4.0M HD Sắc Nét)</option>
                      <option value="medium">Trung bình (2.5M)</option>
                      <option value="low">Tiết kiệm (1.5M)</option>
                    </select>
                  </div>

                  <button style={styles.bigExportCTA} onClick={handleMasterExport} disabled={isProcessing}>
                    <Download size={14} />
                    <span>{isProcessing ? 'Đang Xuất Video...' : (toolMode === 'split' ? `Xuất ${splitSegments.length || 0} đoạn đã chia` : (toolMode === 'cut' ? 'Cắt bỏ rác & Xuất file' : 'Ghép & Xuất video'))}</span>
                  </button>
                </div>
              )}

              {/* TAB 2: DYNAMIC SUBTITLE INSPECTOR */}
              {activeRightTab === 'sub' && (
                <div style={styles.propsScrollForm}>
                  <div style={styles.typographyCard}>
                    <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
                      <span style={{ fontSize: 10, fontWeight: 700, color: '#facc15' }}>🔤 PHÔNG CHỮ &amp; KÍCH THƯỚC:</span>
                      <span style={{ fontSize: 8, color: '#38bdf8', fontWeight: 600 }}>Google Fonts</span>
                    </div>

                    <div style={styles.propItem}>
                      <span style={styles.propLabel}>Phông chữ (Font Family):</span>
                      <select 
                        style={{ ...styles.propSelect, color: '#facc15', fontWeight: 700, fontFamily: getFontFamilyCSS(subStyle.fontFamily) }}
                        value={subStyle.fontFamily}
                        onChange={e => {
                          const val = e.target.value;
                          setSubStyle(prev => ({ ...prev, fontFamily: val }));
                          recordAction(`Đổi phông chữ phụ đề: ${val}`, 'sub_style', { subStyle: { ...subStyle, fontFamily: val } });
                        }}
                      >
                        <option value="Be Vietnam Pro">🇻🇳 Be Vietnam Pro (Chuẩn TV Tiếng Việt)</option>
                        <option value="Montserrat">🔥 Montserrat (Hiện đại / Đậm chất)</option>
                        <option value="Anton">⚡ Anton / Impact (TikTok Viral Bold)</option>
                        <option value="Plus Jakarta Sans">✨ Plus Jakarta Sans (Gọn gàng)</option>
                        <option value="Roboto">🌐 Roboto (Google Clean)</option>
                        <option value="SF Pro Display">🍎 SF Pro Display (Apple Style)</option>
                        <option value="Arial">📄 Arial (Cơ bản)</option>
                      </select>
                    </div>

                    <div style={styles.propItem}>
                      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                        <span style={styles.propLabel}>Cỡ chữ: <b>{subStyle.fontSize} px</b></span>
                        <div style={{ display: 'flex', gap: 3 }}>
                          <button 
                            style={styles.stepSizeBtn} 
                            onClick={() => setSubStyle(prev => ({ ...prev, fontSize: Math.max(12, prev.fontSize - 2) }))}
                          >
                            A-
                          </button>
                          <button 
                            style={styles.stepSizeBtn} 
                            onClick={() => setSubStyle(prev => ({ ...prev, fontSize: Math.min(48, prev.fontSize + 2) }))}
                          >
                            A+
                          </button>
                        </div>
                      </div>
                      <input 
                        type="range" 
                        min="12" 
                        max="48" 
                        step="1" 
                        value={subStyle.fontSize} 
                        onChange={e => setSubStyle(prev => ({ ...prev, fontSize: parseInt(e.target.value) }))}
                        style={{ width: '100%', accentColor: '#facc15' }}
                      />
                    </div>

                    <div style={styles.propItem}>
                      <span style={styles.propLabel}>Màu chữ dịch:</span>
                      <div style={styles.colorPaletteRow}>
                        {[
                          { color: '#facc15', label: 'Vàng' },
                          { color: '#ffffff', label: 'Trắng' },
                          { color: '#38bdf8', label: 'Cyan' },
                          { color: '#f87171', label: 'Đỏ' },
                          { color: '#4ade80', label: 'Lá' },
                          { color: '#000000', label: 'Đen' }
                        ].map(c => (
                          <button
                            key={c.color}
                            style={{
                              ...styles.colorCircleBtn,
                              backgroundColor: c.color,
                              border: subStyle.fontColor === c.color ? '2px solid white' : '1px solid rgba(255,255,255,0.2)',
                              transform: subStyle.fontColor === c.color ? 'scale(1.2)' : 'scale(1)'
                            }}
                            onClick={() => setSubStyle(prev => ({ ...prev, fontColor: c.color }))}
                            title={c.label}
                          />
                        ))}
                        <input 
                          type="color" 
                          value={subStyle.fontColor} 
                          onChange={e => setSubStyle(prev => ({ ...prev, fontColor: e.target.value }))}
                          style={styles.colorPickerNative}
                        />
                      </div>
                    </div>

                    <div style={styles.styleTogglesRow}>
                      <button 
                        style={{ ...styles.styleToggleBtn, ...(subStyle.isBold ? styles.styleToggleActive : {}) }}
                        onClick={() => setSubStyle(prev => ({ ...prev, isBold: !prev.isBold }))}
                      >
                        <Bold size={11} /> <b>B</b>
                      </button>
                      <button 
                        style={{ ...styles.styleToggleBtn, ...(subStyle.isItalic ? styles.styleToggleActive : {}) }}
                        onClick={() => setSubStyle(prev => ({ ...prev, isItalic: !prev.isItalic }))}
                      >
                        <Italic size={11} /> <i>I</i>
                      </button>
                      <button 
                        style={{ ...styles.styleToggleBtn, ...(subStyle.showSubBox ? styles.styleToggleActive : {}) }}
                        onClick={() => setSubStyle(prev => ({ ...prev, showSubBox: !prev.showSubBox }))}
                      >
                        <Square size={11} /> Hộp nền
                      </button>
                      <button 
                        style={{ ...styles.styleToggleBtn, ...(subStyle.hasDropShadow ? styles.styleToggleActive : {}) }}
                        onClick={() => setSubStyle(prev => ({ ...prev, hasDropShadow: !prev.hasDropShadow }))}
                      >
                        <Sparkles size={11} /> Đổ bóng
                      </button>
                    </div>
                  </div>

                  <div style={styles.subtitlePositionBox}>
                    <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
                      <span style={{ fontSize: 10, fontWeight: 700, color: '#facc15' }}>📍 Vị trí hiển thị Subtitle:</span>
                      <span style={{ fontSize: 9, fontFamily: 'monospace', color: 'white' }}>X: {Math.round(subtitlePos.x)}% | Y: {Math.round(subtitlePos.y)}%</span>
                    </div>

                    <div style={styles.quickAlignGrid}>
                      <button style={styles.alignPresetBtn} onClick={() => setSubtitlePos({ x: 50, y: 85 })}>⬇️ Đáy</button>
                      <button style={styles.alignPresetBtn} onClick={() => setSubtitlePos({ x: 50, y: 15 })}>⬆️ Đỉnh</button>
                      <button style={styles.alignPresetBtn} onClick={() => setSubtitlePos({ x: 50, y: 50 })}>⏹ Giữa</button>
                      <button style={styles.alignPresetBtn} onClick={() => setSubtitlePos(prev => ({ ...prev, x: 25 }))}>⬅ Trái</button>
                      <button style={styles.alignPresetBtn} onClick={() => setSubtitlePos(prev => ({ ...prev, x: 75 }))}>➡ Phải</button>
                    </div>

                    <div style={{ display: 'flex', gap: 6, marginTop: 4 }}>
                      <div style={{ flex: 1, display: 'flex', flexDirection: 'column', gap: 2 }}>
                        <span style={{ fontSize: 8, color: 'var(--text-dim)' }}>X: {Math.round(subtitlePos.x)}%</span>
                        <input 
                          type="range" min="10" max="90" step="1" value={subtitlePos.x} 
                          onChange={e => setSubtitlePos(prev => ({ ...prev, x: parseFloat(e.target.value) }))}
                          style={{ width: '100%', accentColor: '#facc15' }}
                        />
                      </div>
                      <div style={{ flex: 1, display: 'flex', flexDirection: 'column', gap: 2 }}>
                        <span style={{ fontSize: 8, color: 'var(--text-dim)' }}>Y: {Math.round(subtitlePos.y)}%</span>
                        <input 
                          type="range" min="5" max="95" step="1" value={subtitlePos.y} 
                          onChange={e => setSubtitlePos(prev => ({ ...prev, y: parseFloat(e.target.value) }))}
                          style={{ width: '100%', accentColor: '#facc15' }}
                        />
                      </div>
                    </div>
                  </div>

                  {selectedSubtitle && (
                    <>
                      <div style={styles.propItem}>
                        <span style={styles.propLabel}>Văn bản gốc</span>
                        <input
                          type="text"
                          value={selectedSubtitle.textOrig}
                          onChange={e => {
                            const val = e.target.value;
                            setSubtitles(prev => prev.map(s => s.id === selectedSubtitle.id ? { ...s, textOrig: val } : s));
                          }}
                          style={styles.propInput}
                        />
                      </div>

                      <div style={styles.propItem}>
                        <span style={styles.propLabel}>Văn bản dịch</span>
                        <input
                          type="text"
                          value={selectedSubtitle.textTrans}
                          onChange={e => {
                            const val = e.target.value;
                            setSubtitles(prev => prev.map(s => s.id === selectedSubtitle.id ? { ...s, textTrans: val } : s));
                          }}
                          style={{ ...styles.propInput, color: subStyle.fontColor }}
                        />
                      </div>

                      <button style={styles.deleteTrackElementBtn} onClick={() => handleDeleteSubtitle(selectedSubtitle.id)}>
                        <Trash2 size={12} /> Xoá câu sub này (Delete)
                      </button>
                    </>
                  )}
                </div>
              )}

              {/* TAB 3: DYNAMIC OVERLAY CLIP INSPECTOR */}
              {activeRightTab === 'overlay' && activeOverlayClip && (
                <div style={styles.propsScrollForm}>
                  <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 4 }}>
                    <img src={activeOverlayClip.imageSrc} alt="" style={{ width: 32, height: 32, borderRadius: 4, objectFit: 'contain', backgroundColor: '#1e293b' }} />
                    <div style={{ flex: 1, minWidth: 0 }}>
                      <div style={{ fontSize: 11, fontWeight: 700, color: 'white', overflow: 'hidden', textOverflow: 'ellipsis' }}>{activeOverlayClip.name}</div>
                      <button style={styles.smallUploadBtn} onClick={() => handleTriggerAddImageToTrack(activeOverlayClip.trackId)}>+ Thay ảnh</button>
                    </div>
                  </div>

                  <div style={styles.propItem}>
                    <span style={styles.propLabel}>Thuộc Làn Track:</span>
                    <select
                      style={{ ...styles.propSelect, color: '#38bdf8', fontWeight: 700 }}
                      value={activeOverlayClip.trackId}
                      onChange={(e) => handleChangeClipTrack(activeOverlayClip.id, e.target.value)}
                    >
                      {overlayTracks.map((t, idx) => (
                        <option key={t.id} value={t.id}>{t.name} (Tầng {overlayTracks.length - idx})</option>
                      ))}
                    </select>
                  </div>

                  <div style={styles.propItem}>
                    <span style={styles.propLabel}>Độ mờ: {Math.round(activeOverlayClip.opacity * 100)}%</span>
                    <input 
                      type="range" min="0.1" max="1.0" step="0.05" value={activeOverlayClip.opacity} 
                      onChange={e => {
                        const op = parseFloat(e.target.value);
                        setOverlayClips(prev => prev.map(o => o.id === activeOverlayClip.id ? { ...o, opacity: op } : o));
                      }}
                      style={{ width: '100%', accentColor: '#38bdf8' }}
                    />
                  </div>

                  <div style={styles.propItem}>
                    <span style={styles.propLabel}>Kích thước: {Math.round(activeOverlayClip.width)}%</span>
                    <input 
                      type="range" min="5" max="80" step="1" value={activeOverlayClip.width} 
                      onChange={e => {
                        const w = parseFloat(e.target.value);
                        setOverlayClips(prev => prev.map(o => o.id === activeOverlayClip.id ? { ...o, width: w, height: w } : o));
                      }}
                      style={{ width: '100%', accentColor: '#38bdf8' }}
                    />
                  </div>

                  <button style={styles.deleteTrackElementBtn} onClick={() => handleDeleteOverlayClip(activeOverlayClip.id)}>
                    <Trash2 size={12} /> Xoá hình ảnh này (Delete)
                  </button>
                </div>
              )}

              {/* TAB 4: DYNAMIC AUDIO INSPECTOR */}
              {activeRightTab === 'audio' && (
                <div style={styles.propsScrollForm}>
                  {(() => {
                    const activeAud = audioClips.find(a => a.id === activeSelection?.id) || audioClips[0];
                    if (!activeAud) return <div style={{ color: 'var(--text-dim)', fontSize: 11 }}>Chưa chọn audio clip</div>;
                    return (
                      <>
                        <div style={{ fontSize: 11, fontWeight: 700, color: 'white', marginBottom: 4 }}>🎵 {activeAud.name}</div>
                        <div style={styles.propItem}>
                          <span style={styles.propLabel}>Âm lượng clip: {activeAud.volume}%</span>
                          <input 
                            type="range" min="0" max="200" step="5" value={activeAud.volume} 
                            onChange={e => {
                              const vol = parseInt(e.target.value);
                              setAudioClips(prev => prev.map(a => a.id === activeAud.id ? { ...a, volume: vol } : a));
                            }}
                            style={{ width: '100%', accentColor: '#34d399' }}
                          />
                        </div>

                        <div style={styles.propItem}>
                          <span style={styles.propLabel}>Điểm bắt đầu: {formatShortTime(activeAud.start)}</span>
                          <input 
                            type="range" min="0" max={duration} step="0.5" value={activeAud.start} 
                            onChange={e => {
                              const st = parseFloat(e.target.value);
                              setAudioClips(prev => prev.map(a => a.id === activeAud.id ? { ...a, start: st } : a));
                            }}
                            style={{ width: '100%', accentColor: '#34d399' }}
                          />
                        </div>

                        <button style={styles.deleteTrackElementBtn} onClick={() => handleDeleteAudio(activeAud.id)}>
                          <Trash2 size={12} /> Xoá file audio này (Delete)
                        </button>
                      </>
                    );
                  })()}
                </div>
              )}

              {/* TAB 5: THÔNG TIN FILE */}
              {activeRightTab === 'file_info' && (
                <div style={styles.propsScrollForm}>
                  <div style={styles.fileInfoGrid}>
                    <div style={styles.infoRow}><span style={styles.infoKey}>Tên file:</span><span style={styles.infoVal}>{selectedFile?.name}</span></div>
                    <div style={styles.infoRow}><span style={styles.infoKey}>Độ phân giải:</span><span style={styles.infoVal}>{videoResolution}</span></div>
                    <div style={styles.infoRow}><span style={styles.infoKey}>Thời lượng:</span><span style={styles.infoVal}>{formatTimecodeMs(duration)}</span></div>
                    <div style={styles.infoRow}><span style={styles.infoKey}>Dung lượng:</span><span style={styles.infoVal}>{fileSpecs.fileSize}</span></div>
                  </div>
                </div>
              )}
            </div>
          </div>
        </div>

        {/* ── LOWER SECTION: MULTI-TRACK INTERACTIVE TIMELINE ─────────────────── */}
        <div style={styles.lowerSection}>
          
          {/* 1. TIMELINE TOOLBAR (ĐÃ BỎ NÚT "+ THÊM ẢNH" THỪA) */}
          <div style={styles.timelineToolbar}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
              <button 
                style={{ ...styles.tlToolBtn, ...(isMediaBinOpen ? styles.tlToolBtnActive : {}) }}
                onClick={() => setIsMediaBinOpen(!isMediaBinOpen)}
                title="Mở thư viện video dự án"
              >
                <FolderOpen size={13} /> Thư viện video
              </button>

              <div style={styles.toolDivider} />

              {/* 3 Action Mode Buttons on Timeline */}
              <button 
                style={{ ...styles.tlToolBtn, ...(toolMode === 'cut' ? styles.tlToolBtnActiveCut : {}) }} 
                onClick={() => {
                  setToolMode('cut');
                  setIsIsolatedPreview(true);
                }}
                title="Chế độ Cắt bỏ đoạn rác"
              >
                <Scissors size={13} /> Cắt bỏ rác
              </button>

              <button 
                style={{ ...styles.tlToolBtn, ...(toolMode === 'split' ? styles.tlToolBtnActiveSplit : {}) }} 
                onClick={() => {
                  setToolMode('split');
                  setIsIsolatedPreview(false);
                }}
                title="Chế độ Chia clip tại chỗ"
              >
                <Split size={13} /> Chia clip (S)
              </button>

              <button 
                style={{ ...styles.tlToolBtn, ...(toolMode === 'merge' ? styles.tlToolBtnActiveMerge : {}) }} 
                onClick={() => {
                  setToolMode('merge');
                  setIsMediaBinOpen(true);
                  setIsIsolatedPreview(false);
                }}
                title="Chế độ Ghép nhiều video"
              >
                <Layers size={13} /> Ghép video
              </button>

              <div style={styles.toolDivider} />

              <button style={styles.addOverlayTrackHighlightBtn} onClick={handleAddOverlayTrack} title="Tạo một Làn Track Lớp Phủ mới">
                <Layers size={13} color="#38bdf8" /> + Track Lớp Phủ
              </button>
            </div>

            <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
              <button 
                style={{ ...styles.tlToolBtn, opacity: historyIndex > 0 ? 1 : 0.4 }} 
                onClick={handleUndo} 
                disabled={historyIndex <= 0}
                title="Hoàn tác (Ctrl+Z)"
              >
                <RotateCcw size={13} /> Undo
              </button>
              <button 
                style={{ ...styles.tlToolBtn, opacity: historyIndex < actionHistory.length - 1 ? 1 : 0.4 }} 
                onClick={handleRedo} 
                disabled={historyIndex >= actionHistory.length - 1}
                title="Làm lại (Ctrl+Shift+Z)"
              >
                <RotateCw size={13} /> Redo
              </button>

              <div style={styles.toolDivider} />

              {/* BỘ ĐIỀU KHIỂN THU PHÓNG TIMELINE TOÀN DIỆN (1.0x -> 6.0x) */}
              <div style={{ display: 'flex', alignItems: 'center', gap: 5, backgroundColor: 'rgba(255, 255, 255, 0.04)', padding: '2px 8px', borderRadius: 6, border: '1px solid rgba(255, 255, 255, 0.08)' }}>
                <button 
                  style={styles.zoomStepBtn} 
                  onClick={() => setZoomLevel(prev => Math.max(1, Math.round((prev - 0.5) * 10) / 10))}
                  title="Thu nhỏ timeline (-)"
                  disabled={zoomLevel <= 1}
                >
                  <Minus size={11} />
                </button>

                <input
                  type="range"
                  min="1"
                  max="6"
                  step="0.25"
                  value={zoomLevel}
                  onChange={e => setZoomLevel(parseFloat(e.target.value))}
                  style={{ width: 75, accentColor: '#2dd4bf', cursor: 'ew-resize' }}
                  title="Thu phóng trục thời gian (Ctrl/Cmd + Lăn chuột)"
                />

                <button 
                  style={styles.zoomStepBtn} 
                  onClick={() => setZoomLevel(prev => Math.min(6, Math.round((prev + 0.5) * 10) / 10))}
                  title="Phóng to timeline (+)"
                  disabled={zoomLevel >= 6}
                >
                  <Plus size={11} />
                </button>

                <span style={styles.zoomPctBadge}>
                  {Math.round(zoomLevel * 100)}%
                </span>

                <button 
                  style={{ ...styles.miniMoveBtn, padding: '2px 6px', fontSize: 9, fontWeight: 700, backgroundColor: zoomLevel === 1 ? 'rgba(45, 212, 191, 0.2)' : 'rgba(255, 255, 255, 0.06)', color: zoomLevel === 1 ? '#2dd4bf' : '#cbd5e1' }} 
                  onClick={() => setZoomLevel(1)} 
                  title="Căn vừa toàn bộ màn hình (Fit 100%)"
                >
                  Fit
                </button>
              </div>
            </div>
          </div>

          {/* 2. MEDIA BIN / CLIP SHELF DRAWER */}
          {isMediaBinOpen && (
            <div style={styles.mediaBinShelf}>
              <div style={styles.mediaBinHeader}>
                <span style={{ fontSize: 11, fontWeight: 700, color: 'white' }}>📁 Thư viện video dự án (Click để mở video hoặc thêm vào danh sách ghép)</span>
                <button style={styles.iconBtn} onClick={() => setIsMediaBinOpen(false)}><X size={13} /></button>
              </div>
              <div style={styles.mediaBinScroll}>
                {allFiles.map(file => (
                  <div 
                    key={file.relPath}
                    style={styles.mediaBinCard}
                    onClick={() => {
                      if (toolMode === 'merge') {
                        handleAddVideoToMerge(file);
                      } else {
                        handleSwitchActiveVideo(file);
                      }
                    }}
                  >
                    <div style={styles.mediaBinThumb}>
                      <video
                        src={`${getMediaUrl(file.relPath, mediaCacheKey)}#t=0.5`}
                        preload="metadata"
                        muted
                        playsInline
                        style={{ width: '100%', height: '100%', objectFit: 'cover' }}
                      />
                    </div>
                    <div style={{ flex: 1, minWidth: 0 }}>
                      <div style={styles.mediaBinTitle}>{file.name}</div>
                      <div style={{ fontSize: 9, color: 'var(--text-dim)' }}>
                        {file.relPath.includes('/output/') ? '✨ Đã dịch' : (file.relPath.includes('/cut/') ? '✂️ Đã cắt' : (file.relPath.includes('/merge/') ? '🥞 Đã ghép' : '📹 Gốc'))}
                      </div>
                    </div>
                    {toolMode === 'merge' && (
                      <button style={styles.addMergeItemBtn} title="Thêm vào danh sách ghép"><Plus size={11} color="#34d399" /></button>
                    )}
                  </div>
                ))}
              </div>
            </div>
          )}

          {/* 3. MULTI-TRACK INTERACTIVE TIMELINE CANVAS */}
          <div style={styles.multiTrackCanvasWrapper}>
            
            {/* Track Headers Column (Luôn hiển thị 5 tầng Track chuẩn) */}
            <div style={styles.trackHeadersCol}>
              <div style={styles.rulerHeaderSpace} />

              {/* Track 1 Header: Video Gốc / Chuỗi Video */}
              <div style={{ ...styles.trackHeaderItem, height: 38 }}>
                <div style={styles.trackTitleRow}>
                  <Film size={12} color="#a855f7" />
                  <span style={{ fontWeight: 700, color: 'white' }}>
                    {toolMode === 'merge' ? 'Video gốc' : 'Video gốc'}
                  </span>
                </div>
                <div style={styles.trackActionsRow}>
                  <button 
                    style={styles.trackMiniAction} 
                    onClick={() => {
                      const next = !origAudioMuted;
                      setOrigAudioMuted(next);
                      recordAction(`Loa Video gốc: ${next ? 'Tắt (Mute)' : 'Bật (Unmute)'}`, 'audio_mute', { origAudioMuted: next });
                    }} 
                    title={origAudioMuted ? "Bật lại âm thanh video gốc" : "Tắt tiếng video gốc"}
                  >
                    {origAudioMuted || origAudioVolume === 0 ? <VolumeX size={12} color="#ef4444" /> : <Volume2 size={12} color="#cbd5e1" />}
                  </button>
                  <button style={styles.trackMiniAction} onClick={() => toggleTrackVisible('video')} title="Ẩn/Hiện video">
                    {trackStates.video.visible ? <Eye size={12} color="#cbd5e1" /> : <EyeOff size={12} color="#ef4444" />}
                  </button>
                  <button style={styles.trackMiniAction} onClick={() => toggleTrackLock('video')} title="Khoá/Mở khoá track video">
                    {trackStates.video.locked ? <Lock size={12} color="#f59e0b" /> : <Unlock size={12} color="var(--text-dim)" />}
                  </button>
                </div>
              </div>

              {/* DYNAMIC MULTI-TRACK OVERLAY HEADERS */}
                  {toolMode !== 'merge' && overlayTracks.map((track, trackIdx) => {
                    const layerNum = overlayTracks.length - trackIdx;
                    const isTrackSelected = selectedOverlayTrackId === track.id;

                    return (
                      <div 
                        key={`header-${track.id}`} 
                        style={{
                          ...styles.trackHeaderItem,
                          ...(isTrackSelected ? styles.trackHeaderItemSelected : {})
                        }}
                        onClick={() => setSelectedOverlayTrackId(track.id)}
                        title="Click để chọn Làn Track này"
                      >
                        <div style={styles.trackTitleRow}>
                          <ImageIcon size={11} color="#38bdf8" />
                          <span style={{ fontSize: 9, fontWeight: 700, color: isTrackSelected ? '#38bdf8' : 'white', whiteSpace: 'nowrap' }}>
                            {track.name} (T{layerNum})
                          </span>
                        </div>

                        <div style={styles.trackActionsRow}>
                          <button 
                            style={styles.trackAddImageBtn} 
                            onClick={(e) => {
                              e.stopPropagation();
                              setSelectedOverlayTrackId(track.id);
                              handleTriggerAddImageToTrack(track.id);
                            }} 
                            title="Chèn ảnh vào Làn này"
                          >
                            + Ảnh
                          </button>

                          <button style={styles.trackMiniAction} onClick={(e) => { e.stopPropagation(); toggleOverlayTrackVisible(track.id); }} title="Ẩn/Hiện làn này">
                            {track.visible ? <Eye size={11} color="#cbd5e1" /> : <EyeOff size={11} color="#ef4444" />}
                          </button>
                          
                          <button style={styles.trackMiniAction} onClick={(e) => { e.stopPropagation(); toggleOverlayTrackLock(track.id); }} title="Khoá/Mở khoá làn này">
                            {track.locked ? <Lock size={11} color="#f59e0b" /> : <Unlock size={12} color="var(--text-dim)" />}
                          </button>

                          <button 
                            style={styles.trackMiniAction} 
                            onClick={(e) => { e.stopPropagation(); handleMoveOverlayTrack(trackIdx, 'up'); }} 
                            disabled={trackIdx === 0}
                            title="Đẩy Làn lên trên"
                          >
                            <ChevronUp size={11} color={trackIdx === 0 ? 'rgba(255,255,255,0.2)' : 'var(--text-dim)'} />
                          </button>
                          <button 
                            style={styles.trackMiniAction} 
                            onClick={(e) => { e.stopPropagation(); handleMoveOverlayTrack(trackIdx, 'down'); }} 
                            disabled={trackIdx === overlayTracks.length - 1}
                            title="Hạ Làn xuống dưới"
                          >
                            <ChevronDown size={11} color={trackIdx === overlayTracks.length - 1 ? 'rgba(255,255,255,0.2)' : 'var(--text-dim)'} />
                          </button>

                          <button style={styles.trackMiniAction} onClick={(e) => { e.stopPropagation(); handleDeleteOverlayTrack(track.id); }} title="Xoá Làn này">
                            <Trash2 size={10} color="#ef4444" />
                          </button>
                        </div>
                      </div>
                    );
                  })}

                  {/* Track Audio 1: Nhạc nền */}
                  {toolMode !== 'merge' && (
                    <div style={styles.trackHeaderItem}>
                      <div style={styles.trackTitleRow}>
                        <Music size={12} color="#34d399" />
                        <span>Nhạc nền</span>
                      </div>
                      <div style={styles.trackActionsRow}>
                        <button 
                          style={{ ...styles.trackAddImageBtn, backgroundColor: 'rgba(52, 211, 153, 0.15)', borderColor: 'rgba(52, 211, 153, 0.4)', color: '#34d399' }}
                          onClick={(e) => {
                            e.stopPropagation();
                            handleTriggerAddAudioToTrack('audio1');
                          }}
                          title="Thêm file nhạc nền vào Làn này"
                        >
                          + Nhạc
                        </button>
                        <button 
                          style={styles.trackMiniAction} 
                          onClick={() => {
                            const next = !musicMuted;
                            setMusicMuted(next);
                            recordAction(`Loa Nhạc nền: ${next ? 'Tắt (Mute)' : 'Bật (Unmute)'}`, 'audio_mute', { musicMuted: next });
                          }} 
                          title={musicMuted ? "Bật lại tiếng nhạc nền" : "Tắt tiếng nhạc nền"}
                        >
                          {musicMuted ? <VolumeX size={12} color="#ef4444" /> : <Volume2 size={12} color="#34d399" />}
                        </button>
                        <button style={styles.trackMiniAction} onClick={() => toggleTrackLock('audio1')}>
                          {trackStates.audio1.locked ? <Lock size={12} color="#f59e0b" /> : <Unlock size={12} color="var(--text-dim)" />}
                        </button>
                      </div>
                    </div>
                  )}

                  {/* Track Audio 2: Hiệu ứng */}
                  {toolMode !== 'merge' && (
                    <div style={styles.trackHeaderItem}>
                      <div style={styles.trackTitleRow}>
                        <Mic size={12} color="#60a5fa" />
                        <span>Hiệu ứng</span>
                      </div>
                      <div style={styles.trackActionsRow}>
                        <button 
                          style={{ ...styles.trackAddImageBtn, backgroundColor: 'rgba(96, 165, 250, 0.15)', borderColor: 'rgba(96, 165, 250, 0.4)', color: '#60a5fa' }}
                          onClick={(e) => {
                            e.stopPropagation();
                            handleTriggerAddAudioToTrack('audio2');
                          }}
                          title="Thêm file hiệu ứng âm thanh vào Làn này"
                        >
                          + FX
                        </button>
                        <button 
                          style={styles.trackMiniAction} 
                          onClick={() => {
                            const next = !sfxMuted;
                            setSfxMuted(next);
                            recordAction(`Loa Hiệu ứng: ${next ? 'Tắt (Mute)' : 'Bật (Unmute)'}`, 'audio_mute', { sfxMuted: next });
                          }} 
                          title={sfxMuted ? "Bật lại tiếng hiệu ứng" : "Tắt tiếng hiệu ứng"}
                        >
                          {sfxMuted ? <VolumeX size={12} color="#ef4444" /> : <Volume2 size={12} color="#60a5fa" />}
                        </button>
                        <button style={styles.trackMiniAction} onClick={() => toggleTrackLock('audio2')}>
                          {trackStates.audio2.locked ? <Lock size={12} color="#f59e0b" /> : <Unlock size={12} color="var(--text-dim)" />}
                        </button>
                      </div>
                    </div>
                  )}

                  {/* Track Subtitle */}
                  {toolMode !== 'merge' && (
                    <div style={styles.trackHeaderItem}>
                      <div style={styles.trackTitleRow}>
                        <Type size={12} color="#facc15" />
                        <span style={{ fontWeight: 700, color: '#facc15' }}>Subtitle (Tầng đỉnh)</span>
                      </div>
                      <div style={styles.trackActionsRow}>
                        <button 
                          style={{ ...styles.trackAddImageBtn, backgroundColor: 'rgba(250, 204, 21, 0.15)', borderColor: 'rgba(250, 204, 21, 0.4)', color: '#facc15' }}
                          onClick={(e) => {
                            e.stopPropagation();
                            handleAddSubtitle();
                          }}
                          title="Thêm câu phụ đề mới tại mốc Playhead"
                        >
                          + Sub
                        </button>
                        <button style={styles.trackMiniAction} onClick={() => toggleTrackVisible('sub')}>
                          {trackStates.sub.visible ? <Eye size={12} color="#cbd5e1" /> : <EyeOff size={12} color="#ef4444" />}
                        </button>
                        <button style={styles.trackMiniAction} onClick={() => toggleTrackLock('sub')}>
                          {trackStates.sub.locked ? <Lock size={12} color="#f59e0b" /> : <Unlock size={12} color="var(--text-dim)" />}
                        </button>
                      </div>
                    </div>
                  )}
            </div>

            {/* Scrollable Tracks Canvas (Right) */}
            <div 
              style={styles.tracksCanvasScroll} 
              ref={timelineTrackRef}
              onWheel={(e) => {
                if (e.ctrlKey || e.metaKey || e.altKey) {
                  e.preventDefault();
                  const delta = e.deltaY < 0 ? 0.25 : -0.25;
                  setZoomLevel(prev => Math.max(1, Math.min(6, Math.round((prev + delta) * 100) / 100)));
                }
              }}
              onClick={(e) => {
                if (!timelineTrackRef.current) return;
                const rect = timelineTrackRef.current.getBoundingClientRect();
                const scrollLeft = timelineTrackRef.current.scrollLeft || 0;
                const totalTrackWidth = rect.width * zoomLevel;
                const clickX = e.clientX - rect.left + scrollLeft;
                const ratio = Math.max(0, Math.min(1, clickX / totalTrackWidth));
                handleSeek(ratio * effectiveDur);
              }}
            >
              <div style={{ ...styles.timelineInnerZoomTrack, width: `${zoomLevel * 100}%`, minWidth: '100%' }}>
                {/* Time Ruler (Thước đo thời gian thích ứng tự động theo Zoom - Bấm hoặc Kéo để tua) */}
                <div 
                  style={{ ...styles.rulerContainer, cursor: 'ew-resize' }}
                  onMouseDown={(e) => {
                    if (!timelineTrackRef.current) return;
                    const rect = timelineTrackRef.current.getBoundingClientRect();
                    const scrollLeft = timelineTrackRef.current.scrollLeft || 0;
                    const totalTrackWidth = rect.width * zoomLevel;
                    const clickX = e.clientX - rect.left + scrollLeft;
                    const ratio = Math.max(0, Math.min(1, clickX / totalTrackWidth));
                    handleSeek(ratio * effectiveDur);
                    handleStartTrackDrag('timeline', 'playhead', 'playhead', e);
                  }}
                  title="Click hoặc kéo trên thước đo thời gian để di chuyển Playhead"
                >
                  {Array.from({ length: Math.max(9, Math.round(9 * zoomLevel)) }).map((_, i, arr) => {
                    const totalSteps = arr.length - 1;
                    const s = (i / totalSteps) * effectiveDur;
                    return (
                      <span key={i} style={{ ...styles.rulerMark, left: `${(i / totalSteps) * 100}%` }}>
                        {formatShortTime(s)}
                      </span>
                    );
                  })}
                </div>

                {/* 1. DẢI PHIM VIDEO NGUYÊN BẢN / CÁC ĐOẠN GHÉP / CHIA (TRACK 1 ĐỒNG NHẤT 100%) */}
                <div style={{ ...styles.trackCanvasRow, height: 42, position: 'relative', overflow: 'hidden' }}>
                  <div style={styles.videoTrackClipsFlex}>
                    {activeVideoClips.map((clip, idx) => {
                      const isSel = activeSelection?.type === 'video_clip' && activeSelection.id === clip.id;
                      const isCurrentlyPlayingThis = (currentTime >= clip.start && currentTime <= clip.end) || (selectedFile?.relPath === clip.relPath);
                      const widthPct = Math.max(8, ((clip.duration || 10) / effectiveDur) * 100);

                      return (
                        <div
                          key={clip.id}
                          draggable={activeVideoClips.length > 1}
                          onDragStart={(e) => {
                            e.dataTransfer.setData('text/plain', idx.toString());
                            setDraggedMergeIndex(idx);
                          }}
                          onDragOver={(e) => {
                            e.preventDefault();
                            e.dataTransfer.dropEffect = 'move';
                          }}
                          onDrop={(e) => {
                            e.preventDefault();
                            const from = parseInt(e.dataTransfer.getData('text/plain'), 10);
                            if (!isNaN(from) && from !== idx) {
                              if (toolMode === 'merge') handleMoveMergeItem(from, idx);
                              else if (splitSegments.length > 0) {
                                const next = [...splitSegments];
                                const [moved] = next.splice(from, 1);
                                next.splice(idx, 0, moved);
                                setSplitSegments(next);
                                recordAction(`Đổi thứ tự đoạn: "${moved.name}" sang vị trí #${idx + 1}`, 'split', { splitSegments: next });
                              }
                            }
                            setDraggedMergeIndex(null);
                          }}
                          style={{
                            ...styles.videoClipBlockItem,
                            width: `${widthPct}%`,
                            ...(isSel ? styles.videoClipBlockSelected : {}),
                            ...(isCurrentlyPlayingThis && !isSel ? styles.videoClipBlockPlaying : {}),
                            opacity: draggedMergeIndex === idx ? 0.4 : 1
                          }}
                          onClick={(e) => {
                            e.stopPropagation();
                            setActiveSelection({ type: 'video_clip', id: clip.id });
                            handleSeek(clip.start);
                          }}
                          title={`Đoạn #${idx + 1}: ${clip.name} (${formatShortTime(clip.duration)}). Click để chọn, kéo thả đổi thứ tự, bấm Delete để gỡ bỏ.`}
                        >
                          {/* Dải ảnh Filmstrip bên trong clip */}
                          <div style={styles.clipFilmstripGrid}>
                            {clip.relPath && (
                              <div style={styles.clipFilmThumbItem}>
                                <video
                                  src={`${getMediaUrl(clip.relPath, mediaCacheKey)}#t=0.5`}
                                  preload="metadata"
                                  muted
                                  playsInline
                                  style={{ width: '100%', height: '100%', objectFit: 'cover' }}
                                />
                              </div>
                            )}
                            <div style={styles.clipFilmStripSprocket} />
                          </div>

                          {/* Overlay Header thông tin clip */}
                          <div style={styles.clipHeaderOverlay}>
                            <span style={styles.clipIndexBadge}>
                              #{idx + 1} ▶ {clip.name}
                            </span>
                            <div style={{ display: 'flex', alignItems: 'center', gap: 3, pointerEvents: 'auto' }}>
                              <span style={styles.clipDurationBadge}>{formatShortTime(clip.duration)}</span>
                              {(activeVideoClips.length > 1 || splitSegments.length > 0) && (
                                <button
                                  style={styles.clipMiniDeleteBtn}
                                  onClick={(e) => {
                                    e.stopPropagation();
                                    if (toolMode === 'merge') {
                                      const next = mergePlaylist.filter(m => m.id !== clip.id);
                                      setMergePlaylist(next);
                                      recordAction(`Xoá video "${clip.name}" khỏi danh sách ghép`, 'merge', { mergePlaylist: next });
                                    } else if (splitSegments.length > 0) {
                                      const next = splitSegments.filter(s => s.id !== clip.id);
                                      setSplitSegments(next);
                                      recordAction(`Xoá đoạn "${clip.name}" khỏi timeline`, 'split', { splitSegments: next });
                                    }
                                    setActiveSelection({ type: 'range', id: 'range' });
                                  }}
                                  title="Xoá đoạn này khỏi timeline (Delete / Backspace)"
                                >
                                  ✕
                                </button>
                              )}
                            </div>
                          </div>
                        </div>
                      );
                    })}

                    {toolMode === 'merge' && (
                      <button 
                        style={styles.addMoreMergeItemMiniBtn} 
                        onClick={() => setIsMediaBinOpen(true)}
                        title="Thêm video từ thư viện"
                      >
                        <Plus size={13} color="#34d399" />
                      </button>
                    )}
                  </div>

                  {/* 2. KHUNG CHỌN CẮT BỎ RÁC MÀU TÍM (CHỈ HIỆN KHI Ở CHẾ ĐỘ 'CẮT BỎ' VÀ SHOWCUTBOX = TRUE) */}
                  {toolMode === 'cut' && showCutBox && (
                    <div
                      style={{
                        ...styles.rangeSelectionBox,
                        left: `${startRatio * 100}%`,
                        width: `${Math.max(1, (endRatio - startRatio) * 100)}%`
                      }}
                      onMouseDown={(e) => handleStartTrackDrag('range', 'range', 'move', e)}
                      title="Nắm giữa để dời vị trí đoạn rác, nắm 2 mép để co giãn thời lượng"
                    >
                      <div 
                        style={styles.handleLeft}
                        onMouseDown={(e) => handleStartTrackDrag('range', 'range', 'left', e)}
                        title="Kéo chỉnh mốc bắt đầu"
                      />
                      <div style={styles.centerScissorsMarker}>
                        <Scissors size={11} color="white" />
                      </div>
                      <div 
                        style={styles.handleRight}
                        onMouseDown={(e) => handleStartTrackDrag('range', 'range', 'right', e)}
                        title="Kéo chỉnh mốc kết thúc"
                      />
                    </div>
                  )}
                </div>

                  {/* DYNAMIC MULTI-TRACK OVERLAY CANVAS ROWS */}
                  {toolMode !== 'merge' && overlayTracks.map((track) => {
                    const clipsInThisTrack = overlayClips.filter(c => c.trackId === track.id);
                    const isTrackSelected = selectedOverlayTrackId === track.id;

                    return (
                      <div 
                        key={`canvas-${track.id}`} 
                        style={{
                          ...styles.trackCanvasRow,
                          backgroundColor: isTrackSelected ? 'rgba(56, 189, 248, 0.05)' : 'transparent'
                        }}
                        onClick={() => setSelectedOverlayTrackId(track.id)}
                      >
                        {clipsInThisTrack.map(ov => {
                          const ovStartRatio = Math.max(0, ov.start / effectiveDur);
                          const ovEndRatio = Math.min(1, ov.end / effectiveDur);
                          const ovWidthRatio = Math.max(0.02, ovEndRatio - ovStartRatio);
                          const isSel = activeSelection?.type === 'overlay' && activeSelection.id === ov.id;

                          return (
                            <div
                              key={ov.id}
                              style={{
                                ...styles.timelineClipBlock,
                                left: `${ovStartRatio * 100}%`,
                                width: `${ovWidthRatio * 100}%`,
                                backgroundColor: isSel ? 'rgba(56, 189, 248, 0.45)' : 'rgba(56, 189, 248, 0.2)',
                                borderColor: isSel ? '#38bdf8' : 'rgba(56, 189, 248, 0.5)',
                                borderWidth: isSel ? 2 : 1,
                                boxShadow: isSel ? '0 0 16px rgba(56, 189, 248, 0.9), inset 0 0 6px rgba(56, 189, 248, 0.5)' : 'none',
                                zIndex: isSel ? 35 : 10,
                                cursor: track.locked ? 'default' : 'grab'
                              }}
                              onClick={(e) => {
                                e.stopPropagation();
                                setSelectedOverlayTrackId(track.id);
                                setActiveSelection({ type: 'overlay', id: ov.id });
                                setActiveRightTab('overlay');
                                handleSeek(ov.start);
                              }}
                              onMouseDown={(e) => {
                                if (!track.locked) handleStartTrackDrag('overlay', ov.id, 'move', e);
                              }}
                            >
                              {!track.locked && (
                                <div 
                                  style={styles.clipStretchHandleLeft} 
                                  onMouseDown={(e) => handleStartTrackDrag('overlay', ov.id, 'left', e)}
                                  title="Kéo chỉnh thời gian xuất hiện"
                                />
                              )}
                              
                              <ImageIcon size={11} color="#38bdf8" />
                              <span style={{ fontSize: 10, color: 'white', fontWeight: 600, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                                {ov.name} {track.locked ? '(Khoá)' : ''}
                              </span>

                              {!track.locked && (
                                <div 
                                  style={styles.clipStretchHandleRight} 
                                  onMouseDown={(e) => handleStartTrackDrag('overlay', ov.id, 'right', e)}
                                  title="Kéo chỉnh thời gian biến mất"
                                />
                              )}
                            </div>
                          );
                        })}
                      </div>
                    );
                  })}

                  {/* Track 3: Audio 1 (BGM) */}
                  {toolMode !== 'merge' && (
                    <div style={styles.trackCanvasRow}>
                      {audioClips.filter(a => a.track === 'audio1').map(aud => {
                        const effectiveClipEnd = aud.start + (aud.duration || 10.0);
                        const aStartRatio = Math.max(0, aud.start / effectiveDur);
                        const aEndRatio = Math.min(1, effectiveClipEnd / effectiveDur);
                        const aWidthRatio = Math.max(0.02, aEndRatio - aStartRatio);
                        const isSel = activeSelection?.type === 'audio' && activeSelection.id === aud.id;

                        return (
                          <div
                            key={aud.id}
                            style={{
                              ...styles.timelineClipBlock,
                              left: `${aStartRatio * 100}%`,
                              width: `${aWidthRatio * 100}%`,
                              backgroundColor: isSel ? 'rgba(52, 211, 153, 0.45)' : 'rgba(52, 211, 153, 0.2)',
                              borderColor: isSel ? '#34d399' : 'rgba(52, 211, 153, 0.5)',
                              borderWidth: isSel ? 2 : 1,
                              boxShadow: isSel ? '0 0 16px rgba(52, 211, 153, 0.9), inset 0 0 6px rgba(52, 211, 153, 0.5)' : 'none',
                              zIndex: isSel ? 35 : 10,
                              opacity: musicMuted ? 0.45 : 1
                            }}
                            onClick={(e) => {
                              e.stopPropagation();
                              setActiveSelection({ type: 'audio', id: aud.id });
                              setActiveRightTab('audio');
                              handleSeek(aud.start);
                            }}
                            onMouseDown={(e) => handleStartTrackDrag('audio', aud.id, 'move', e)}
                          >
                            <Music size={11} color="#34d399" />
                            <div style={styles.simulatedWaveformGreen} />
                            <span style={{ fontSize: 10, color: 'white', fontWeight: 600, zIndex: 2 }}>
                              {aud.name} {musicMuted ? '(🔇 Muted)' : `(${aud.volume}%)`}
                            </span>
                            <div 
                              style={styles.clipStretchHandleRight} 
                              onMouseDown={(e) => handleStartTrackDrag('audio', aud.id, 'right', e)}
                              title="Kéo chỉnh thời lượng audio"
                            />
                          </div>
                        );
                      })}
                    </div>
                  )}

                  {/* Track 4: Audio 2 (Hiệu ứng) */}
                  {toolMode !== 'merge' && (
                    <div style={styles.trackCanvasRow}>
                      {audioClips.filter(a => a.track === 'audio2').map(aud => {
                        const effectiveClipEnd = aud.start + (aud.duration || 10.0);
                        const aStartRatio = Math.max(0, aud.start / effectiveDur);
                        const aEndRatio = Math.min(1, effectiveClipEnd / effectiveDur);
                        const aWidthRatio = Math.max(0.02, aEndRatio - aStartRatio);
                        const isSel = activeSelection?.type === 'audio' && activeSelection.id === aud.id;

                        return (
                          <div
                            key={aud.id}
                            style={{
                              ...styles.timelineClipBlock,
                              left: `${aStartRatio * 100}%`,
                              width: `${aWidthRatio * 100}%`,
                              backgroundColor: isSel ? 'rgba(96, 165, 250, 0.45)' : 'rgba(96, 165, 250, 0.2)',
                              borderColor: isSel ? '#60a5fa' : 'rgba(96, 165, 250, 0.5)',
                              borderWidth: isSel ? 2 : 1,
                              boxShadow: isSel ? '0 0 16px rgba(96, 165, 250, 0.9), inset 0 0 6px rgba(96, 165, 250, 0.5)' : 'none',
                              zIndex: isSel ? 35 : 10,
                              opacity: sfxMuted ? 0.45 : 1
                            }}
                            onClick={(e) => {
                              e.stopPropagation();
                              setActiveSelection({ type: 'audio', id: aud.id });
                              setActiveRightTab('audio');
                              handleSeek(aud.start);
                            }}
                            onMouseDown={(e) => handleStartTrackDrag('audio', aud.id, 'move', e)}
                          >
                            <Mic size={11} color="#60a5fa" />
                            <div style={styles.simulatedWaveformBlue} />
                            <span style={{ fontSize: 10, color: 'white', fontWeight: 600, zIndex: 2 }}>
                              {aud.name} {sfxMuted ? '(🔇 Muted)' : ''}
                            </span>
                            <div 
                              style={styles.clipStretchHandleRight} 
                              onMouseDown={(e) => handleStartTrackDrag('audio', aud.id, 'right', e)}
                              title="Kéo chỉnh thời lượng hiệu ứng"
                            />
                          </div>
                        );
                      })}
                    </div>
                  )}

                  {/* Track 5: Subtitle Blocks */}
                  {toolMode !== 'merge' && (
                    <div style={styles.trackCanvasRow}>
                      {subtitles.map(sub => {
                        const subStartRatio = Math.max(0, sub.start / effectiveDur);
                        const subEndRatio = Math.min(1, sub.end / effectiveDur);
                        const subWidthRatio = Math.max(0.02, subEndRatio - subStartRatio);
                        const isSel = activeSelection?.type === 'sub' && activeSelection.id === sub.id;

                        return (
                          <div
                            key={sub.id}
                            style={{
                              ...styles.timelineClipBlock,
                              left: `${subStartRatio * 100}%`,
                              width: `${subWidthRatio * 100}%`,
                              backgroundColor: isSel ? 'rgba(250, 204, 21, 0.45)' : 'rgba(250, 204, 21, 0.2)',
                              borderColor: isSel ? '#facc15' : 'rgba(250, 204, 21, 0.5)',
                              borderWidth: isSel ? 2 : 1,
                              boxShadow: isSel ? '0 0 16px rgba(250, 204, 21, 0.9), inset 0 0 6px rgba(250, 204, 21, 0.5)' : 'none',
                              zIndex: isSel ? 35 : 10
                            }}
                            onClick={(e) => {
                              e.stopPropagation();
                              setActiveSelection({ type: 'sub', id: sub.id });
                              setActiveRightTab('sub');
                              handleSeek(sub.start);
                            }}
                            onMouseDown={(e) => handleStartTrackDrag('sub', sub.id, 'move', e)}
                          >
                            <div 
                              style={styles.clipStretchHandleLeft} 
                              onMouseDown={(e) => handleStartTrackDrag('sub', sub.id, 'left', e)}
                              title="Kéo chỉnh thời điểm hiện sub"
                            />

                            <Type size={10} color="#facc15" />
                            <span style={{ fontSize: 9, color: 'white', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                              {sub.textTrans || sub.textOrig}
                            </span>

                            <div 
                              style={styles.clipStretchHandleRight} 
                              onMouseDown={(e) => handleStartTrackDrag('sub', sub.id, 'right', e)}
                              title="Kéo chỉnh thời điểm ẩn sub"
                            />
                          </div>
                        );
                      })}
                    </div>
                  )}

                  {/* Playhead Scrubber Line - Kéo bất kỳ điểm nào trên thân hoặc cục tam giác đỉnh */}
                  <div 
                    style={{ ...styles.playheadLine, left: `${playheadRatio * 100}%` }}
                    onMouseDown={(e) => handleStartTrackDrag('timeline', 'playhead', 'playhead', e)}
                    title="Kéo con trỏ Playhead để tua video"
                  >
                    <div 
                      style={styles.playheadHeadHitArea}
                      onMouseDown={(e) => handleStartTrackDrag('timeline', 'playhead', 'playhead', e)}
                      title="Nắm kéo cục trắng này để di chuyển Playhead / Điểm chia video"
                    >
                      <div style={styles.playheadHead} />
                    </div>
                  </div>
                </div>
              </div>
            </div>

          {/* 4. AUDIO MIXER CONSOLE (BOTTOM BAR) - TỰ ĐỘNG ẨN KHI Ở CHẾ ĐỘ GHÉP VIDEO */}
          {toolMode !== 'merge' && (
            <div style={styles.audioMixerBar}>
              <div style={styles.mixerHeading}>MIXER ÂM THANH</div>

              <div style={styles.mixerChannelsRow}>
                <div style={styles.mixerChannel}>
                  <span style={{ ...styles.channelLabel, color: origAudioMuted || origAudioVolume === 0 ? '#ef4444' : '#cbd5e1' }}>
                    Video {origAudioMuted || origAudioVolume === 0 ? '(🔇 Đã tắt)' : '(🔊 Bật)'}
                  </span>
                  <input
                    type="range"
                    min="0"
                    max="200"
                    step="5"
                    value={origAudioMuted ? 0 : origAudioVolume}
                    onChange={(e) => {
                      const v = parseInt(e.target.value);
                      setOrigAudioVolume(v);
                      if (v > 0 && origAudioMuted) setOrigAudioMuted(false);
                    }}
                    style={{ ...styles.mixerSlider, accentColor: origAudioMuted ? '#ef4444' : '#a855f7' }}
                  />
                  <span style={styles.channelValue}>{origAudioMuted ? 'Muted' : `${origAudioVolume}%`}</span>
                  <button 
                    style={{ ...styles.channelMuteBtn, color: origAudioMuted ? '#ef4444' : '#cbd5e1' }} 
                    onClick={() => {
                      const next = !origAudioMuted;
                      setOrigAudioMuted(next);
                      recordAction(`Loa Video gốc: ${next ? 'Tắt (Mute)' : 'Bật (Unmute)'}`, 'audio_mute', { origAudioMuted: next });
                    }}
                    title={origAudioMuted ? "Bật lại tiếng video gốc" : "Tắt tiếng video gốc"}
                  >
                    {origAudioMuted ? <VolumeX size={13} color="#ef4444" /> : <Volume2 size={13} />}
                  </button>
                </div>

                <div style={styles.mixerChannel}>
                  <span style={{ ...styles.channelLabel, color: musicMuted || musicVolume === 0 ? '#ef4444' : '#cbd5e1' }}>
                    Nhạc nền {musicMuted || musicVolume === 0 ? '(🔇 Đã tắt)' : '(🎵 Bật)'}
                  </span>
                  <input
                    type="range"
                    min="0"
                    max="200"
                    step="5"
                    value={musicMuted ? 0 : musicVolume}
                    onChange={(e) => {
                      const v = parseInt(e.target.value);
                      setMusicVolume(v);
                      if (v > 0 && musicMuted) setMusicMuted(false);
                    }}
                    style={{ ...styles.mixerSlider, accentColor: '#34d399' }}
                  />
                  <span style={styles.channelValue}>{musicMuted ? 'Muted' : `${musicVolume}%`}</span>
                  <button 
                    style={styles.channelMuteBtn} 
                    onClick={() => {
                      const next = !musicMuted;
                      setMusicMuted(next);
                      recordAction(`Loa Nhạc nền: ${next ? 'Tắt (Mute)' : 'Bật (Unmute)'}`, 'audio_mute', { musicMuted: next });
                    }}
                    title={musicMuted ? "Bật lại tiếng nhạc nền" : "Tắt tiếng nhạc nền"}
                  >
                    {musicMuted ? <VolumeX size={12} color="#ef4444" /> : <Volume2 size={12} color="#34d399" />}
                  </button>
                </div>

                <div style={styles.mixerChannel}>
                  <span style={{ ...styles.channelLabel, color: sfxMuted || sfxVolume === 0 ? '#ef4444' : '#cbd5e1' }}>
                    Hiệu ứng {sfxMuted || sfxVolume === 0 ? '(🔇 Đã tắt)' : '(🎤 Bật)'}
                  </span>
                  <input
                    type="range"
                    min="0"
                    max="200"
                    step="5"
                    value={sfxMuted ? 0 : sfxVolume}
                    onChange={(e) => {
                      const v = parseInt(e.target.value);
                      setSfxVolume(v);
                      if (v > 0 && sfxMuted) setSfxMuted(false);
                    }}
                    style={{ ...styles.mixerSlider, accentColor: '#60a5fa' }}
                  />
                  <span style={styles.channelValue}>{sfxMuted ? 'Muted' : `${sfxVolume}%`}</span>
                  <button 
                    style={styles.channelMuteBtn} 
                    onClick={() => {
                      const next = !sfxMuted;
                      setSfxMuted(next);
                      recordAction(`Loa Hiệu ứng: ${next ? 'Tắt (Mute)' : 'Bật (Unmute)'}`, 'audio_mute', { sfxMuted: next });
                    }}
                    title={sfxMuted ? "Bật lại tiếng hiệu ứng" : "Tắt tiếng hiệu ứng"}
                  >
                    {sfxMuted ? <VolumeX size={13} color="#ef4444" /> : <Volume2 size={13} color="#60a5fa" />}
                  </button>
                </div>

                <button style={styles.addAudioMixerBtn} onClick={handleAddAudio}>
                  <Plus size={13} /> Thêm audio
                </button>
              </div>
            </div>
          )}

        </div>
      </div>

      {/* ── QUICK VIDEO SWITCHER MODAL ──────────────────────────────────────── */}
      {showVideoSwitcherModal && (
        <div style={styles.modalOverlay} onClick={() => setShowVideoSwitcherModal(false)}>
          <div style={{ ...styles.modalContent, width: 560 }} onClick={e => e.stopPropagation()}>
            <div style={styles.modalHeader}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                <RefreshCw size={16} color="#a855f7" />
                <h3 style={styles.modalTitle}>Chọn Video Muốn Chỉnh Sửa / Cắt Ghép</h3>
              </div>
              <button style={styles.modalCloseBtn} onClick={() => setShowVideoSwitcherModal(false)}><X size={16} /></button>
            </div>

            <div style={styles.modalBody}>
              <div style={{ display: 'flex', gap: 8, alignItems: 'center' }}>
                <div style={styles.searchBox}>
                  <Search size={13} color="var(--text-dim)" />
                  <input
                    type="text"
                    placeholder="Tìm kiếm video..."
                    value={videoSearchQuery}
                    onChange={e => setVideoSearchQuery(e.target.value)}
                    style={styles.searchInput}
                  />
                </div>
                <div style={styles.filterTabs}>
                  <button 
                    style={videoFilterTab === 'all' ? styles.filterTabActive : styles.filterTab}
                    onClick={() => setVideoFilterTab('all')}
                  >
                    Tất cả ({allFiles.length})
                  </button>
                  <button 
                    style={videoFilterTab === 'src' ? styles.filterTabActive : styles.filterTab}
                    onClick={() => setVideoFilterTab('src')}
                  >
                    📹 Gốc ({srcFiles.length})
                  </button>
                  <button 
                    style={videoFilterTab === 'cut' ? styles.filterTabActive : styles.filterTab}
                    onClick={() => setVideoFilterTab('cut')}
                  >
                    ✂️ Đã cắt ({cutFiles.length})
                  </button>
                  <button 
                    style={videoFilterTab === 'merge' ? styles.filterTabActive : styles.filterTab}
                    onClick={() => setVideoFilterTab('merge')}
                  >
                    🥞 Đã ghép ({mergeFiles.length})
                  </button>
                  <button 
                    style={videoFilterTab === 'output' ? styles.filterTabActive : styles.filterTab}
                    onClick={() => setVideoFilterTab('output')}
                  >
                    ✨ Đã dịch ({outputFiles.length})
                  </button>
                </div>
              </div>

              <div style={styles.videoGridScroll}>
                {filteredVideos.map(file => {
                  const isCurrent = selectedFile?.relPath === file.relPath;
                  return (
                    <div 
                      key={file.relPath}
                      style={{
                        ...styles.videoGridCard,
                        ...(isCurrent ? styles.videoGridCardActive : {})
                      }}
                      onClick={() => handleSwitchActiveVideo(file)}
                    >
                      <div style={styles.videoCardThumb}>
                        <video
                          src={`${getMediaUrl(file.relPath, mediaCacheKey)}#t=0.5`}
                          preload="metadata"
                          muted
                          playsInline
                          style={{ width: '100%', height: '100%', objectFit: 'cover' }}
                        />
                      </div>

                      <div style={{ flex: 1, minWidth: 0 }}>
                        <div style={styles.videoCardTitle}>{file.name}</div>
                        <div style={styles.videoCardMeta}>
                          <span>
                            {file.relPath.includes('/output/') ? '✨ Đã dịch' : (file.relPath.includes('/cut/') ? '✂️ Đã cắt' : (file.relPath.includes('/merge/') ? '🥞 Đã ghép' : '📹 Video gốc'))}
                          </span>
                          <span>•</span>
                          <span>{formatFileSize(file.size || file.sizeBytes)}</span>
                        </div>
                      </div>

                      {isCurrent ? (
                        <span style={styles.currentBadge}>Đang mở</span>
                      ) : (
                        <button style={styles.selectVideoBtn}>Chọn</button>
                      )}
                    </div>
                  );
                })}
              </div>
            </div>

            <div style={styles.modalFooter}>
              <button style={styles.cancelModalBtn} onClick={() => setShowVideoSwitcherModal(false)}>Đóng</button>
            </div>
          </div>
        </div>
      )}

      {/* ── SHORTCUTS & HELP MODAL ──────────────────────────────────────────── */}
      {showShortcutsModal && (
        <div style={styles.modalOverlay} onClick={() => setShowShortcutsModal(false)}>
          <div style={styles.modalContent} onClick={e => e.stopPropagation()}>
            <div style={styles.modalHeader}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                <HelpCircle size={18} color="#a855f7" />
                <h3 style={styles.modalTitle}>Phím Tắt &amp; Hướng Dẫn Studio</h3>
              </div>
              <button style={styles.modalCloseBtn} onClick={() => setShowShortcutsModal(false)}><X size={16} /></button>
            </div>
            <div style={styles.modalBody}>
              <div style={styles.shortcutsTable}>
                <div style={styles.shortcutRow}><span style={styles.shortcutKey}>Cắt bỏ rác</span><span>Quét khung tím vào đoạn rác $\to$ Bấm Cắt bỏ để giữ lại các phần ngoài</span></div>
                <div style={styles.shortcutRow}><span style={styles.shortcutKey}>Chia clip (S)</span><span>Chia video tại mốc Playhead và giữ lại toàn bộ các đoạn</span></div>
                <div style={styles.shortcutRow}><span style={styles.shortcutKey}>Ghép video</span><span>Nối nhiều video từ thư viện thành 1 file mới</span></div>
                <div style={styles.shortcutRow}><span style={styles.shortcutKey}>Delete / Backspace</span><span>Xoá ngay đối tượng đang chọn</span></div>
                <div style={styles.shortcutRow}><span style={styles.shortcutKey}>Space</span><span>Phát / Dừng video</span></div>
                <div style={styles.shortcutRow}><span style={styles.shortcutKey}>Ctrl + Z</span><span>Hoàn tác (Undo)</span></div>
              </div>
            </div>
            <div style={styles.modalFooter}>
              <button style={styles.cancelModalBtn} onClick={() => setShowShortcutsModal(false)}>Đóng</button>
            </div>
          </div>
        </div>
      )}

      {/* ── AUTO-NORMALIZE COMPATIBILITY MODAL ──────────────────────────────── */}
      {showCompatModal && compatReport && (
        <div style={styles.modalOverlay}>
          <div style={styles.modalContent}>
            <div style={styles.modalHeader}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                <AlertTriangle size={20} color="#f59e0b" />
                <h3 style={styles.modalTitle}>Phát hiện video không cùng thông số định dạng</h3>
              </div>
              <button style={styles.modalCloseBtn} onClick={() => setShowCompatModal(false)}><X size={16} /></button>
            </div>

            <div style={styles.modalBody}>
              <p style={{ fontSize: 13, color: 'var(--text-secondary)', marginBottom: 12 }}>
                Các video trong danh sách ghép có thông số kỹ thuật khác nhau, cần chuẩn hóa để ghép chuẩn xác.
              </p>

              <div style={styles.diffsAlertBox}>
                <span style={{ fontWeight: 700, color: '#f87171', fontSize: 12 }}>Các điểm khác biệt:</span>
                <ul style={{ margin: '6px 0 0 16px', padding: 0, fontSize: 12, color: 'var(--text-primary)' }}>
                  {compatReport.diffs.map((d, i) => (
                    <li key={i}>{d}</li>
                  ))}
                </ul>
              </div>

              <div style={styles.explainNote}>
                💡 <b>Auto-Normalize</b> sẽ sử dụng chip <b>Apple Silicon VideoToolbox</b> để chuẩn hóa kích thước, FPS và âm thanh trong ~1-2 giây.
              </div>
            </div>

            <div style={styles.modalFooter}>
              <button style={styles.cancelModalBtn} onClick={() => setShowCompatModal(false)}>Huỷ bỏ</button>
              <button style={styles.confirmNormalizeBtn} onClick={() => pendingMergeAction && pendingMergeAction()}>
                <Sparkles size={14} />
                <span>Đồng ý &amp; Tự Động Chuẩn Hóa</span>
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

// ── 100% DARK STUDIO THEME CSS STYLES ───────────────────────────────────────
const styles = {
  container: {
    display: 'flex',
    flexDirection: 'column',
    width: '100%',
    height: '100%',
    backgroundColor: 'var(--bg-app)',
    color: 'var(--text-main)',
    overflow: 'hidden',
    fontFamily: 'system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif'
  },
  topHeader: {
    height: 48,
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between',
    padding: '0 16px',
    backgroundColor: 'var(--bg-header)',
    borderBottom: '1px solid var(--border-color)',
    flexShrink: 0
  },
  headerLeft: {
    display: 'flex',
    alignItems: 'center',
    gap: 8,
    fontSize: 13
  },
  brandTitle: {
    fontWeight: 800,
    color: 'var(--text-main)',
    letterSpacing: '0.3px'
  },
  breadcrumbDivider: {
    color: 'var(--text-dim)',
    fontSize: 11
  },
  breadcrumbSub: {
    color: 'var(--text-dim)',
    fontSize: 12
  },
  breadcrumbActive: {
    color: 'var(--text-main)',
    fontWeight: 600,
    fontSize: 12
  },
  headerCenter: {
    display: 'flex',
    alignItems: 'center',
    gap: 12
  },
  videoSwitcherBtn: {
    display: 'flex',
    alignItems: 'center',
    gap: 8,
    padding: '4px 10px',
    backgroundColor: 'rgba(124, 58, 237, 0.12)',
    border: '1px solid rgba(124, 58, 237, 0.35)',
    borderRadius: 6,
    cursor: 'pointer',
    transition: 'all 0.15s ease'
  },
  fileNameText: {
    fontSize: 12,
    fontWeight: 700,
    color: 'var(--text-main)',
    maxWidth: 180,
    overflow: 'hidden',
    textOverflow: 'ellipsis',
    whiteSpace: 'nowrap'
  },
  switchBadge: {
    display: 'flex',
    alignItems: 'center',
    gap: 3,
    fontSize: 9,
    fontWeight: 700,
    color: '#c084fc',
    backgroundColor: 'rgba(168, 85, 247, 0.2)',
    padding: '1px 5px',
    borderRadius: 4
  },
  savedBadge: {
    fontSize: 10,
    color: 'var(--text-dim)',
    backgroundColor: 'var(--bg-surface)',
    padding: '2px 8px',
    borderRadius: 12
  },
  historyIcons: {
    display: 'flex',
    alignItems: 'center',
    gap: 4
  },
  headerRight: {
    display: 'flex',
    alignItems: 'center',
    gap: 8
  },
  draftBtn: {
    display: 'flex',
    alignItems: 'center',
    gap: 6,
    padding: '5px 12px',
    backgroundColor: 'var(--bg-surface)',
    border: '1px solid var(--border-color)',
    borderRadius: 6,
    color: 'var(--text-main)',
    fontSize: 12,
    fontWeight: 600,
    cursor: 'pointer'
  },
  primaryExportBtn: {
    display: 'flex',
    alignItems: 'center',
    gap: 6,
    padding: '5px 14px',
    backgroundColor: '#7c3aed',
    border: 'none',
    borderRadius: 6,
    color: 'white',
    fontSize: 12,
    fontWeight: 700,
    cursor: 'pointer',
    boxShadow: '0 2px 8px rgba(124, 58, 237, 0.4)'
  },
  iconBtn: {
    padding: 6,
    backgroundColor: 'transparent',
    border: 'none',
    color: 'var(--text-muted)',
    borderRadius: 6,
    cursor: 'pointer',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center'
  },
  mainCanvas: {
    flex: 1,
    display: 'flex',
    flexDirection: 'column',
    overflow: 'hidden',
    padding: 10,
    gap: 10
  },
  upperSection: {
    display: 'flex',
    gap: 10,
    flex: '1 1 58%',
    minHeight: 310,
    maxHeight: '60%',
    overflow: 'hidden'
  },
  playerColumn: {
    flex: '1 1 50%',
    display: 'flex',
    flexDirection: 'column',
    backgroundColor: 'var(--bg-card)',
    borderRadius: 8,
    border: '1px solid var(--border-color)',
    overflow: 'hidden'
  },
  videoScreenWrapper: {
    flex: 1,
    position: 'relative',
    backgroundColor: '#000000',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    overflow: 'hidden'
  },
  resolutionBadge: {
    position: 'absolute',
    top: 10,
    left: 10,
    backgroundColor: 'rgba(0,0,0,0.65)',
    color: 'white',
    padding: '2px 8px',
    borderRadius: 4,
    fontSize: 11,
    fontWeight: 600,
    zIndex: 10
  },
  aspectBadge: {
    position: 'absolute',
    top: 10,
    right: 10,
    backgroundColor: 'rgba(0,0,0,0.65)',
    color: 'white',
    padding: '2px 8px',
    borderRadius: 4,
    fontSize: 11,
    fontWeight: 600,
    zIndex: 10
  },
  audioModePill: {
    position: 'absolute',
    top: 10,
    backgroundColor: 'rgba(239, 68, 68, 0.25)',
    border: '1px solid rgba(239, 68, 68, 0.45)',
    color: '#f87171',
    padding: '2px 8px',
    borderRadius: 12,
    fontSize: 10,
    fontWeight: 600,
    zIndex: 10,
    display: 'flex',
    alignItems: 'center',
    gap: 4
  },
  isolatedPreviewBadge: {
    position: 'absolute',
    top: 40,
    backgroundColor: 'rgba(124, 58, 237, 0.85)',
    color: 'white',
    padding: '4px 12px',
    borderRadius: 20,
    fontSize: 11,
    fontWeight: 700,
    zIndex: 15,
    display: 'flex',
    alignItems: 'center',
    gap: 8,
    boxShadow: '0 4px 12px rgba(124, 58, 237, 0.5)'
  },
  closeIsolatedBtn: {
    background: 'none',
    border: 'none',
    color: 'white',
    cursor: 'pointer',
    fontWeight: 700,
    fontSize: 11
  },
  videoElement: {
    width: '100%',
    height: '100%',
    objectFit: 'contain'
  },
  overlayLayerBadge: {
    position: 'absolute',
    bottom: -16,
    left: 0,
    backgroundColor: 'rgba(0,0,0,0.75)',
    color: '#38bdf8',
    padding: '1px 4px',
    borderRadius: 3,
    fontSize: 8,
    fontWeight: 700
  },
  subPosBadge: {
    position: 'absolute',
    bottom: -18,
    backgroundColor: 'rgba(0,0,0,0.85)',
    color: '#facc15',
    padding: '1px 6px',
    borderRadius: 3,
    fontSize: 8,
    fontWeight: 700,
    whiteSpace: 'nowrap'
  },
  playerControlsBar: {
    height: 42,
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between',
    padding: '0 12px',
    backgroundColor: 'var(--bg-card)',
    borderTop: '1px solid var(--border-color)'
  },
  playBtn: {
    width: 28,
    height: 28,
    borderRadius: '50%',
    backgroundColor: '#7c3aed',
    border: 'none',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    cursor: 'pointer'
  },
  stepBtn: {
    background: 'none',
    border: 'none',
    color: 'var(--text-muted)',
    cursor: 'pointer',
    fontSize: 13
  },
  timecodeDisplay: {
    fontSize: 11,
    fontFamily: 'monospace',
    color: 'var(--text-main)'
  },
  volumeGroup: {
    display: 'flex',
    alignItems: 'center',
    gap: 6
  },
  volumeSlider: {
    width: 55,
    height: 3,
    accentColor: '#a855f7'
  },
  centerCutAndSegmentsColumn: {
    flex: '1 1 25%',
    display: 'flex',
    flexDirection: 'column',
    gap: 10,
    overflow: 'hidden'
  },
  cutToolsTopSection: {
    backgroundColor: 'var(--bg-card)',
    borderRadius: 8,
    border: '1px solid var(--border-color)',
    padding: 10,
    display: 'flex',
    flexDirection: 'column',
    gap: 8
  },
  main3ToolsGrid: {
    display: 'grid',
    gridTemplateColumns: 'repeat(3, 1fr)',
    gap: 4
  },
  toolCardBig: {
    display: 'flex',
    flexDirection: 'column',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 3,
    padding: '6px 2px',
    backgroundColor: 'var(--bg-surface)',
    border: '1px solid var(--border-color)',
    borderRadius: 6,
    color: 'var(--text-muted)',
    fontSize: 10,
    fontWeight: 700,
    cursor: 'pointer',
    transition: 'all 0.15s ease'
  },
  toolCardActiveCut: {
    backgroundColor: 'rgba(239, 68, 68, 0.2)',
    borderColor: '#ef4444',
    color: '#f87171'
  },
  toolCardActiveSplit: {
    backgroundColor: 'rgba(96, 165, 250, 0.2)',
    borderColor: '#60a5fa',
    color: '#60a5fa'
  },
  toolCardActiveMerge: {
    backgroundColor: 'rgba(52, 211, 153, 0.2)',
    borderColor: '#34d399',
    color: '#34d399'
  },
  timeInputBox: {
    backgroundColor: 'var(--bg-surface)',
    borderRadius: 6,
    padding: 8,
    display: 'flex',
    flexDirection: 'column',
    gap: 6,
    border: '1px solid var(--border-color)'
  },
  splitToolBox: {
    backgroundColor: 'rgba(96, 165, 250, 0.08)',
    border: '1px dashed rgba(96, 165, 250, 0.3)',
    borderRadius: 6,
    padding: 8,
    display: 'flex',
    flexDirection: 'column',
    gap: 6
  },
  splitExecuteBtn: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 5,
    padding: '6px 10px',
    backgroundColor: '#3b82f6',
    border: 'none',
    borderRadius: 5,
    color: 'white',
    fontSize: 10,
    fontWeight: 700,
    cursor: 'pointer'
  },
  mergeToolBox: {
    backgroundColor: 'rgba(52, 211, 153, 0.08)',
    border: '1px dashed rgba(52, 211, 153, 0.3)',
    borderRadius: 6,
    padding: 8,
    display: 'flex',
    flexDirection: 'column',
    gap: 6
  },
  addVideoMergeBtn: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 4,
    padding: '6px 10px',
    backgroundColor: 'rgba(52, 211, 153, 0.2)',
    border: '1px solid #34d399',
    borderRadius: 5,
    color: '#34d399',
    fontSize: 10,
    fontWeight: 700,
    cursor: 'pointer'
  },
  timeInputRow: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between'
  },
  timeInputLabel: {
    fontSize: 10,
    color: 'var(--text-dim)'
  },
  timeInputWrapper: {
    display: 'flex',
    alignItems: 'center',
    gap: 4,
    backgroundColor: 'var(--bg-input)',
    padding: '2px 6px',
    borderRadius: 4,
    border: '1px solid var(--border-color)'
  },
  timeTextInput: {
    width: 80,
    background: 'transparent',
    border: 'none',
    color: 'var(--primary)',
    fontSize: 10,
    fontFamily: 'monospace',
    fontWeight: 600,
    outline: 'none',
    textAlign: 'center'
  },
  miniClockBtn: {
    background: 'none',
    border: 'none',
    cursor: 'pointer',
    padding: 1,
    display: 'flex',
    alignItems: 'center'
  },
  addToListBtn: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 4,
    padding: '6px 10px',
    backgroundColor: 'rgba(239, 68, 68, 0.2)',
    border: '1px solid #ef4444',
    borderRadius: 6,
    color: '#f87171',
    fontSize: 10,
    fontWeight: 700,
    cursor: 'pointer'
  },
  segmentsBottomSection: {
    flex: 1,
    backgroundColor: 'var(--bg-card)',
    borderRadius: 8,
    border: '1px solid var(--border-color)',
    padding: 10,
    display: 'flex',
    flexDirection: 'column',
    gap: 8,
    minHeight: 0
  },
  panelTitle: {
    fontSize: 12,
    fontWeight: 700,
    color: 'var(--text-main)'
  },
  emptySegmentsNotice: {
    fontSize: 10,
    color: 'var(--text-dim)',
    backgroundColor: 'var(--bg-surface)',
    padding: '10px 8px',
    borderRadius: 6,
    lineHeight: 1.4,
    border: '1px dashed var(--border-color)'
  },
  segmentHeaderRow: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between'
  },
  segmentsListScroll: {
    flex: 1,
    overflowY: 'auto',
    display: 'flex',
    flexDirection: 'column',
    gap: 4
  },
  segmentCard: {
    display: 'flex',
    alignItems: 'center',
    gap: 6,
    padding: '4px 6px',
    backgroundColor: 'var(--bg-surface)',
    border: '1px solid var(--border-color)',
    borderRadius: 6,
    cursor: 'pointer'
  },
  segmentThumb: {
    width: 24,
    height: 24,
    backgroundColor: 'rgba(239, 68, 68, 0.15)',
    borderRadius: 3,
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    flexShrink: 0
  },
  segmentInfo: {
    flex: 1,
    minWidth: 0
  },
  segmentName: {
    fontSize: 9,
    fontWeight: 700,
    color: 'var(--text-main)'
  },
  segmentRange: {
    fontSize: 8,
    color: 'var(--text-dim)',
    fontFamily: 'monospace'
  },
  deleteSegmentBtn: {
    background: 'none',
    border: 'none',
    color: '#ef4444',
    cursor: 'pointer',
    padding: 1
  },
  executeRemoveBtn: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 6,
    padding: '8px 12px',
    backgroundColor: 'rgba(239, 68, 68, 0.2)',
    border: '1px solid #ef4444',
    borderRadius: 6,
    color: '#f87171',
    fontSize: 11,
    fontWeight: 700,
    cursor: 'pointer',
    boxShadow: '0 2px 8px rgba(239, 68, 68, 0.3)'
  },
  executeMergeBtn: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 6,
    padding: '8px 12px',
    backgroundColor: '#059669',
    border: 'none',
    borderRadius: 6,
    color: 'white',
    fontSize: 11,
    fontWeight: 700,
    cursor: 'pointer',
    boxShadow: '0 2px 8px rgba(5, 150, 105, 0.4)'
  },
  rightHistoryAndPropsColumn: {
    flex: '1 1 25%',
    display: 'flex',
    flexDirection: 'column',
    gap: 10,
    overflow: 'hidden'
  },
  historyPanel: {
    flex: '1 1 36%',
    backgroundColor: 'var(--bg-card)',
    borderRadius: 8,
    border: '1px solid var(--border-color)',
    padding: 10,
    display: 'flex',
    flexDirection: 'column',
    gap: 6,
    minHeight: 0
  },
  historyListScroll: {
    flex: 1,
    overflowY: 'auto',
    display: 'flex',
    flexDirection: 'column',
    gap: 4
  },
  historyItemCard: {
    display: 'flex',
    alignItems: 'center',
    gap: 6,
    padding: '4px 6px',
    backgroundColor: 'var(--bg-surface)',
    border: '1px solid var(--border-color)',
    borderRadius: 4,
    cursor: 'pointer'
  },
  historyItemActive: {
    backgroundColor: 'rgba(124, 58, 237, 0.2)',
    border: '1px solid #7c3aed'
  },
  historyDot: {
    width: 5,
    height: 5,
    borderRadius: '50%',
    backgroundColor: '#a855f7'
  },
  historyLabel: {
    fontSize: 9,
    color: 'var(--text-main)',
    fontWeight: 600,
    overflow: 'hidden',
    textOverflow: 'ellipsis',
    whiteSpace: 'nowrap'
  },
  historyTime: {
    fontSize: 8,
    color: 'var(--text-dim)',
    fontFamily: 'monospace'
  },
  exportPropsPanel: {
    flex: '1 1 64%',
    backgroundColor: 'var(--bg-card)',
    borderRadius: 8,
    border: '1px solid var(--border-color)',
    padding: 10,
    display: 'flex',
    flexDirection: 'column',
    gap: 6,
    minHeight: 0
  },
  propsTabHeader: {
    display: 'flex',
    gap: 8,
    borderBottom: '1px solid var(--border-color)',
    paddingBottom: 3,
    overflowX: 'auto'
  },
  propsTabActive: {
    fontSize: 10,
    fontWeight: 700,
    color: 'var(--text-main)',
    borderBottom: '2px solid #7c3aed',
    paddingBottom: 3,
    cursor: 'pointer',
    whiteSpace: 'nowrap'
  },
  propsTabInactive: {
    fontSize: 10,
    color: 'var(--text-dim)',
    cursor: 'pointer',
    paddingBottom: 3,
    whiteSpace: 'nowrap'
  },
  propsScrollForm: {
    flex: 1,
    overflowY: 'auto',
    display: 'flex',
    flexDirection: 'column',
    gap: 6
  },
  propItem: {
    display: 'flex',
    flexDirection: 'column',
    gap: 2
  },
  propLabel: {
    fontSize: 9,
    color: 'var(--text-dim)'
  },
  propInput: {
    backgroundColor: 'var(--bg-input)',
    border: '1px solid var(--border-color)',
    borderRadius: 4,
    color: 'var(--text-main)',
    fontSize: 10,
    padding: '3px 6px',
    outline: 'none'
  },
  propSelect: {
    backgroundColor: 'var(--bg-input)',
    border: '1px solid var(--border-color)',
    borderRadius: 4,
    color: 'var(--text-main)',
    fontSize: 10,
    padding: '3px 4px',
    outline: 'none'
  },
  audioSyncStatusCard: {
    backgroundColor: 'rgba(52, 211, 153, 0.05)',
    border: '1px solid rgba(52, 211, 153, 0.25)',
    borderRadius: 6,
    padding: 6,
    display: 'flex',
    flexDirection: 'column',
    gap: 4
  },
  audioChannelStatusRow: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between',
    padding: '2px 0',
    borderBottom: '1px solid var(--border-subtle)'
  },
  audioStatusToggleBtn: {
    padding: '2px 6px',
    borderRadius: 4,
    fontSize: 9,
    fontWeight: 600,
    cursor: 'pointer',
    border: '1px solid'
  },
  audioStatusActive: {
    backgroundColor: 'rgba(52, 211, 153, 0.15)',
    borderColor: '#34d399',
    color: '#34d399'
  },
  audioStatusMuted: {
    backgroundColor: 'rgba(239, 68, 68, 0.15)',
    borderColor: '#ef4444',
    color: '#f87171'
  },
  typographyCard: {
    backgroundColor: 'var(--bg-surface)',
    border: '1px solid var(--border-color)',
    borderRadius: 6,
    padding: 6,
    display: 'flex',
    flexDirection: 'column',
    gap: 4
  },
  stepSizeBtn: {
    padding: '1px 5px',
    backgroundColor: 'var(--bg-surface)',
    border: '1px solid var(--border-color)',
    borderRadius: 3,
    color: 'var(--text-main)',
    fontSize: 9,
    fontWeight: 700,
    cursor: 'pointer'
  },
  colorPaletteRow: {
    display: 'flex',
    alignItems: 'center',
    gap: 6
  },
  colorCircleBtn: {
    width: 16,
    height: 16,
    borderRadius: '50%',
    cursor: 'pointer',
    transition: 'all 0.15s ease'
  },
  colorPickerNative: {
    width: 20,
    height: 20,
    padding: 0,
    border: 'none',
    borderRadius: 3,
    background: 'none',
    cursor: 'pointer'
  },
  styleTogglesRow: {
    display: 'flex',
    gap: 4,
    marginTop: 2
  },
  styleToggleBtn: {
    flex: 1,
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 3,
    padding: '3px 4px',
    backgroundColor: 'var(--bg-surface)',
    border: '1px solid var(--border-color)',
    borderRadius: 4,
    color: 'var(--text-dim)',
    fontSize: 9,
    fontWeight: 600,
    cursor: 'pointer'
  },
  styleToggleActive: {
    backgroundColor: 'rgba(250, 204, 21, 0.2)',
    borderColor: '#facc15',
    color: '#facc15'
  },
  subtitlePositionBox: {
    backgroundColor: 'var(--bg-surface)',
    border: '1px solid var(--border-color)',
    borderRadius: 6,
    padding: 6,
    display: 'flex',
    flexDirection: 'column',
    gap: 4
  },
  quickAlignGrid: {
    display: 'grid',
    gridTemplateColumns: 'repeat(5, 1fr)',
    gap: 3
  },
  alignPresetBtn: {
    padding: '2px 0',
    backgroundColor: 'var(--bg-surface)',
    border: '1px solid var(--border-color)',
    borderRadius: 4,
    color: 'var(--text-main)',
    fontSize: 9,
    fontWeight: 600,
    cursor: 'pointer',
    textAlign: 'center'
  },
  bigExportCTA: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 5,
    padding: '6px 10px',
    backgroundColor: '#7c3aed',
    border: 'none',
    borderRadius: 6,
    color: 'white',
    fontSize: 11,
    fontWeight: 700,
    cursor: 'pointer',
    boxShadow: '0 2px 8px rgba(124, 58, 237, 0.4)',
    marginTop: 'auto'
  },
  fileInfoGrid: {
    display: 'flex',
    flexDirection: 'column',
    gap: 4,
    padding: '2px 0'
  },
  infoRow: {
    display: 'flex',
    justifyContent: 'space-between',
    fontSize: 9,
    borderBottom: '1px solid var(--border-subtle)',
    paddingBottom: 2
  },
  infoKey: {
    color: 'var(--text-dim)'
  },
  infoVal: {
    color: 'var(--text-main)',
    fontWeight: 600,
    fontFamily: 'monospace'
  },
  smallUploadBtn: {
    fontSize: 9,
    color: '#38bdf8',
    background: 'none',
    border: 'none',
    cursor: 'pointer',
    padding: 0
  },
  deleteTrackElementBtn: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 4,
    padding: '5px 8px',
    backgroundColor: 'rgba(239, 68, 68, 0.15)',
    border: '1px solid rgba(239, 68, 68, 0.3)',
    borderRadius: 4,
    color: '#f87171',
    fontSize: 10,
    cursor: 'pointer',
    marginTop: 6
  },
  lowerSection: {
    display: 'flex',
    flexDirection: 'column',
    gap: 6,
    flex: '1 1 42%',
    minHeight: 220,
    backgroundColor: 'var(--bg-card)',
    borderRadius: 8,
    border: '1px solid var(--border-color)',
    padding: 8,
    overflow: 'hidden'
  },
  timelineToolbar: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between',
    height: 26,
    flexShrink: 0
  },
  tlToolBtn: {
    display: 'flex',
    alignItems: 'center',
    gap: 3,
    padding: '2px 6px',
    backgroundColor: 'var(--bg-surface)',
    border: '1px solid var(--border-color)',
    borderRadius: 4,
    color: 'var(--text-muted)',
    fontSize: 10,
    fontWeight: 600,
    cursor: 'pointer'
  },
  tlToolBtnActive: {
    backgroundColor: 'rgba(124, 58, 237, 0.25)',
    borderColor: '#7c3aed',
    color: '#c084fc',
    fontWeight: 700
  },
  tlToolBtnActiveCut: {
    backgroundColor: 'rgba(239, 68, 68, 0.25)',
    borderColor: '#ef4444',
    color: '#f87171',
    fontWeight: 700
  },
  tlToolBtnActiveSplit: {
    backgroundColor: 'rgba(96, 165, 250, 0.25)',
    borderColor: '#60a5fa',
    color: '#60a5fa',
    fontWeight: 700
  },
  tlToolBtnActiveMerge: {
    backgroundColor: 'rgba(52, 211, 153, 0.25)',
    borderColor: '#34d399',
    color: '#34d399',
    fontWeight: 700
  },
  addOverlayTrackHighlightBtn: {
    display: 'flex',
    alignItems: 'center',
    gap: 4,
    padding: '2px 8px',
    backgroundColor: 'rgba(56, 189, 248, 0.15)',
    border: '1px solid rgba(56, 189, 248, 0.4)',
    borderRadius: 4,
    color: '#38bdf8',
    fontSize: 10,
    fontWeight: 700,
    cursor: 'pointer',
    transition: 'all 0.15s ease'
  },
  toolDivider: {
    width: 1,
    height: 12,
    backgroundColor: 'var(--border-color)',
    margin: '0 3px'
  },
  mediaBinShelf: {
    backgroundColor: 'var(--bg-surface)',
    borderRadius: 6,
    border: '1px solid var(--border-color)',
    padding: 6,
    display: 'flex',
    flexDirection: 'column',
    gap: 4
  },
  mediaBinHeader: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between'
  },
  mediaBinScroll: {
    display: 'flex',
    gap: 6,
    overflowX: 'auto',
    padding: '2px 0'
  },
  mediaBinCard: {
    display: 'flex',
    alignItems: 'center',
    gap: 6,
    padding: '3px 6px',
    backgroundColor: 'var(--bg-card)',
    border: '1px solid var(--border-color)',
    borderRadius: 5,
    cursor: 'pointer',
    minWidth: 150,
    flexShrink: 0
  },
  mediaBinThumb: {
    width: 44,
    height: 28,
    backgroundColor: '#000000',
    borderRadius: 4,
    overflow: 'hidden',
    flexShrink: 0,
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    border: '1px solid var(--border-color)'
  },
  mediaBinTitle: {
    fontSize: 9,
    fontWeight: 700,
    color: 'var(--text-main)',
    overflow: 'hidden',
    textOverflow: 'ellipsis',
    whiteSpace: 'nowrap',
    maxWidth: 80
  },
  addMergeItemBtn: {
    background: 'none',
    border: 'none',
    cursor: 'pointer',
    padding: 2
  },
  multiTrackCanvasWrapper: {
    flex: 1,
    display: 'flex',
    overflow: 'hidden',
    backgroundColor: 'var(--bg-input)',
    borderRadius: 6,
    border: '1px solid var(--border-color)'
  },
  trackHeadersCol: {
    width: 180,
    flexShrink: 0,
    backgroundColor: 'var(--bg-surface)',
    borderRight: '1px solid var(--border-color)',
    display: 'flex',
    flexDirection: 'column'
  },
  rulerHeaderSpace: {
    height: 14,
    borderBottom: '1px solid var(--border-subtle)'
  },
  trackHeaderItem: {
    height: 24,
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between',
    padding: '0 6px',
    borderBottom: '1px solid var(--border-subtle)',
    fontSize: 9,
    fontWeight: 600,
    color: 'var(--text-main)',
    cursor: 'pointer',
    transition: 'all 0.15s ease',
    borderLeft: '3px solid transparent'
  },
  trackHeaderItemSelected: {
    backgroundColor: 'rgba(56, 189, 248, 0.12)',
    borderLeft: '3px solid #38bdf8'
  },
  trackTitleRow: {
    display: 'flex',
    alignItems: 'center',
    gap: 4,
    minWidth: 0,
    overflow: 'hidden'
  },
  trackActionsRow: {
    display: 'flex',
    alignItems: 'center',
    gap: 3,
    flexShrink: 0
  },
  trackAddImageBtn: {
    padding: '1px 5px',
    backgroundColor: 'rgba(56, 189, 248, 0.2)',
    border: '1px solid rgba(56, 189, 248, 0.4)',
    borderRadius: 3,
    color: '#38bdf8',
    fontSize: 8,
    fontWeight: 700,
    cursor: 'pointer'
  },
  trackMiniAction: {
    background: 'none',
    border: 'none',
    cursor: 'pointer',
    padding: 1,
    display: 'flex',
    alignItems: 'center'
  },
  tracksCanvasScroll: {
    flex: 1,
    position: 'relative',
    overflowX: 'auto',
    overflowY: 'hidden',
    display: 'flex',
    flexDirection: 'column'
  },
  rulerContainer: {
    height: 14,
    position: 'relative',
    borderBottom: '1px solid var(--border-subtle)'
  },
  rulerMark: {
    position: 'absolute',
    fontSize: 7,
    color: 'var(--text-dim)',
    fontFamily: 'monospace',
    transform: 'translateX(-50%)'
  },
  trackCanvasRow: {
    height: 24,
    position: 'relative',
    borderBottom: '1px solid var(--border-subtle)',
    display: 'flex',
    alignItems: 'center'
  },
  filmThumbnailsGrid: {
    position: 'absolute',
    top: 0,
    bottom: 0,
    left: 0,
    right: 0,
    display: 'grid',
    gridTemplateColumns: 'repeat(14, 1fr)',
    gap: 1
  },
  frameThumbPlaceholder: {
    backgroundColor: '#000000',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    borderRight: '1px solid rgba(0,0,0,0.6)',
    overflow: 'hidden',
    position: 'relative'
  },
  rangeSelectionBox: {
    position: 'absolute',
    top: 0,
    bottom: 0,
    border: '2px solid #ef4444',
    backgroundColor: 'rgba(239, 68, 68, 0.22)',
    boxShadow: '0 0 16px rgba(239, 68, 68, 0.85), inset 0 0 8px rgba(239, 68, 68, 0.35)',
    zIndex: 25,
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    cursor: 'grab'
  },
  handleLeft: {
    position: 'absolute',
    left: 0,
    top: 0,
    bottom: 0,
    width: 10,
    backgroundColor: '#f87171',
    cursor: 'ew-resize',
    borderRadius: '2px 0 0 2px',
    boxShadow: '2px 0 6px rgba(0,0,0,0.5)'
  },
  handleRight: {
    position: 'absolute',
    right: 0,
    top: 0,
    bottom: 0,
    width: 10,
    backgroundColor: '#f87171',
    cursor: 'ew-resize',
    borderRadius: '0 2px 2px 0',
    boxShadow: '-2px 0 6px rgba(0,0,0,0.5)'
  },
  centerScissorsMarker: {
    width: 18,
    height: 18,
    borderRadius: '50%',
    backgroundColor: '#ef4444',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    pointerEvents: 'none',
    boxShadow: '0 2px 6px rgba(0,0,0,0.6)'
  },
  miniToggleCutBtn: {
    display: 'flex',
    alignItems: 'center',
    gap: 4,
    padding: '2px 6px',
    border: '1px solid',
    borderRadius: 4,
    fontSize: 9,
    fontWeight: 700,
    cursor: 'pointer',
    transition: 'all 0.15s ease'
  },
  quickCutPresetRow: {
    display: 'flex',
    alignItems: 'center',
    gap: 6
  },
  quickCutPresetBtn: {
    flex: 1,
    padding: '3px 6px',
    backgroundColor: 'rgba(239, 68, 68, 0.1)',
    border: '1px solid rgba(239, 68, 68, 0.25)',
    borderRadius: 4,
    color: '#fca5a5',
    fontSize: 9,
    fontWeight: 600,
    cursor: 'pointer',
    textAlign: 'center',
    transition: 'all 0.15s ease'
  },
  timelineClipBlock: {
    position: 'absolute',
    top: 2,
    bottom: 2,
    borderRadius: 4,
    border: '1px solid',
    display: 'flex',
    alignItems: 'center',
    gap: 3,
    padding: '0 6px',
    cursor: 'pointer',
    overflow: 'hidden'
  },
  clipStretchHandleLeft: {
    position: 'absolute',
    left: 0,
    top: 0,
    bottom: 0,
    width: 5,
    backgroundColor: 'rgba(255,255,255,0.3)',
    cursor: 'ew-resize'
  },
  clipStretchHandleRight: {
    position: 'absolute',
    right: 0,
    top: 0,
    bottom: 0,
    width: 5,
    backgroundColor: 'rgba(255,255,255,0.3)',
    cursor: 'ew-resize'
  },
  simulatedWaveformBlue: {
    position: 'absolute',
    top: 0,
    bottom: 0,
    left: 0,
    right: 0,
    backgroundImage: 'repeating-linear-gradient(90deg, #60a5fa 0, #60a5fa 2px, transparent 2px, transparent 4px)',
    opacity: 0.4
  },
  simulatedWaveformGreen: {
    position: 'absolute',
    top: 0,
    bottom: 0,
    left: 0,
    right: 0,
    backgroundImage: 'repeating-linear-gradient(90deg, #34d399 0, #34d399 2px, transparent 2px, transparent 4px)',
    opacity: 0.4
  },
  playheadLine: {
    position: 'absolute',
    top: 0,
    bottom: 0,
    width: 2,
    backgroundColor: 'var(--text-main)',
    zIndex: 45,
    cursor: 'ew-resize',
    boxShadow: '0 0 6px rgba(255,255,255,0.95)'
  },
  playheadHeadHitArea: {
    position: 'absolute',
    top: -4,
    left: -13,
    width: 28,
    height: 20,
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    cursor: 'ew-resize',
    zIndex: 50
  },
  playheadHead: {
    width: 0,
    height: 0,
    borderLeft: '6px solid transparent',
    borderRight: '6px solid transparent',
    borderTop: '9px solid var(--text-main)',
    pointerEvents: 'none',
    filter: 'drop-shadow(0 1px 3px rgba(0,0,0,0.8))'
  },
  audioMixerBar: {
    height: 34,
    backgroundColor: 'var(--bg-surface)',
    borderRadius: 6,
    padding: '0 8px',
    display: 'flex',
    alignItems: 'center',
    gap: 12,
    border: '1px solid var(--border-color)',
    flexShrink: 0
  },
  mixerHeading: {
    fontSize: 9,
    fontWeight: 800,
    color: 'var(--text-dim)',
    letterSpacing: '0.5px'
  },
  mixerChannelsRow: {
    flex: 1,
    display: 'flex',
    alignItems: 'center',
    gap: 16
  },
  mixerChannel: {
    display: 'flex',
    alignItems: 'center',
    gap: 5
  },
  channelLabel: {
    fontSize: 9,
    color: 'var(--text-main)'
  },
  mixerSlider: {
    width: 50,
    height: 3,
    accentColor: '#a855f7'
  },
  channelValue: {
    fontSize: 9,
    color: 'var(--text-dim)',
    fontFamily: 'monospace',
    width: 28
  },
  channelMuteBtn: {
    background: 'none',
    border: 'none',
    color: 'var(--text-muted)',
    cursor: 'pointer',
    padding: 1,
    display: 'flex',
    alignItems: 'center'
  },
  addAudioMixerBtn: {
    marginLeft: 'auto',
    display: 'flex',
    alignItems: 'center',
    gap: 3,
    padding: '2px 6px',
    backgroundColor: 'var(--bg-card)',
    border: '1px solid var(--border-color)',
    borderRadius: 4,
    color: 'var(--text-main)',
    fontSize: 9,
    fontWeight: 600,
    cursor: 'pointer'
  },
  gizmoHandleBR: { position: 'absolute', bottom: -4, right: -4, width: 8, height: 8, backgroundColor: '#a855f7', border: '1px solid white', borderRadius: 2, cursor: 'nwse-resize' },
  modalOverlay: {
    position: 'fixed',
    top: 0,
    left: 0,
    right: 0,
    bottom: 0,
    backgroundColor: 'rgba(0, 0, 0, 0.65)',
    backdropFilter: 'blur(4px)',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    zIndex: 9999
  },
  modalContent: {
    width: 480,
    backgroundColor: 'var(--bg-card)',
    borderRadius: 10,
    border: '1px solid var(--border-color)',
    display: 'flex',
    flexDirection: 'column',
    overflow: 'hidden',
    boxShadow: 'var(--shadow-lg)'
  },
  modalHeader: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between',
    padding: '12px 16px',
    backgroundColor: 'var(--bg-surface)',
    borderBottom: '1px solid var(--border-color)'
  },
  modalTitle: {
    fontSize: 13,
    fontWeight: 700,
    color: 'var(--text-main)',
    margin: 0
  },
  modalCloseBtn: {
    background: 'none',
    border: 'none',
    color: 'var(--text-muted)',
    cursor: 'pointer'
  },
  modalBody: {
    padding: 16,
    display: 'flex',
    flexDirection: 'column',
    gap: 10
  },
  searchBox: {
    flex: 1,
    display: 'flex',
    alignItems: 'center',
    gap: 6,
    backgroundColor: 'var(--bg-input)',
    border: '1px solid var(--border-color)',
    borderRadius: 6,
    padding: '4px 8px'
  },
  searchInput: {
    flex: 1,
    background: 'transparent',
    border: 'none',
    color: 'var(--text-main)',
    fontSize: 11,
    outline: 'none'
  },
  filterTabs: {
    display: 'flex',
    gap: 4
  },
  filterTab: {
    padding: '4px 8px',
    backgroundColor: 'var(--bg-surface)',
    border: '1px solid var(--border-color)',
    borderRadius: 4,
    color: 'var(--text-dim)',
    fontSize: 10,
    cursor: 'pointer'
  },
  filterTabActive: {
    padding: '4px 8px',
    backgroundColor: 'rgba(124, 58, 237, 0.2)',
    border: '1px solid #7c3aed',
    borderRadius: 4,
    color: '#c084fc',
    fontSize: 10,
    fontWeight: 700,
    cursor: 'pointer'
  },
  videoGridScroll: {
    maxHeight: 280,
    overflowY: 'auto',
    display: 'flex',
    flexDirection: 'column',
    gap: 6,
    paddingRight: 4
  },
  videoGridCard: {
    display: 'flex',
    alignItems: 'center',
    gap: 10,
    padding: '6px 10px',
    backgroundColor: 'var(--bg-surface)',
    border: '1px solid var(--border-color)',
    borderRadius: 6,
    cursor: 'pointer'
  },
  videoCardThumb: {
    width: 76,
    height: 44,
    backgroundColor: '#000000',
    borderRadius: 4,
    overflow: 'hidden',
    flexShrink: 0,
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    border: '1px solid var(--border-color)'
  },
  videoCardTitle: {
    fontSize: 11,
    fontWeight: 700,
    color: 'var(--text-main)',
    overflow: 'hidden',
    textOverflow: 'ellipsis',
    whiteSpace: 'nowrap'
  },
  videoCardMeta: {
    display: 'flex',
    alignItems: 'center',
    gap: 6,
    fontSize: 9,
    color: 'var(--text-dim)'
  },
  currentBadge: {
    fontSize: 9,
    fontWeight: 700,
    color: '#34d399',
    backgroundColor: 'rgba(52, 211, 153, 0.15)',
    padding: '2px 8px',
    borderRadius: 12
  },
  selectVideoBtn: {
    padding: '3px 10px',
    backgroundColor: 'var(--bg-card)',
    border: '1px solid var(--border-color)',
    borderRadius: 4,
    color: 'var(--text-main)',
    fontSize: 10,
    fontWeight: 600,
    cursor: 'pointer'
  },
  shortcutsTable: {
    display: 'flex',
    flexDirection: 'column',
    gap: 6
  },
  shortcutRow: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between',
    fontSize: 11,
    color: 'var(--text-main)',
    borderBottom: '1px solid var(--border-subtle)',
    paddingBottom: 5
  },
  shortcutKey: {
    padding: '2px 6px',
    backgroundColor: 'var(--bg-surface)',
    borderRadius: 4,
    border: '1px solid var(--border-color)',
    color: 'var(--primary-light)',
    fontFamily: 'monospace',
    fontWeight: 700,
    fontSize: 10
  },
  diffsAlertBox: {
    backgroundColor: 'rgba(239, 68, 68, 0.12)',
    border: '1px solid rgba(239, 68, 68, 0.3)',
    borderRadius: 6,
    padding: 8
  },
  explainNote: {
    fontSize: 11,
    color: 'var(--text-muted)',
    backgroundColor: 'var(--bg-surface)',
    padding: '6px 10px',
    borderRadius: 6
  },
  modalFooter: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'flex-end',
    gap: 8,
    padding: '10px 16px',
    backgroundColor: 'var(--bg-surface)',
    borderTop: '1px solid var(--border-color)'
  },
  cancelModalBtn: {
    padding: '5px 12px',
    backgroundColor: 'var(--bg-card)',
    border: '1px solid var(--border-color)',
    borderRadius: 6,
    color: 'var(--text-main)',
    fontSize: 11,
    fontWeight: 600,
    cursor: 'pointer'
  },
  confirmNormalizeBtn: {
    display: 'flex',
    alignItems: 'center',
    gap: 5,
    padding: '5px 14px',
    backgroundColor: '#7c3aed',
    border: 'none',
    borderRadius: 6,
    color: 'white',
    fontSize: 11,
    fontWeight: 700,
    cursor: 'pointer',
    boxShadow: '0 2px 8px rgba(124, 58, 237, 0.4)'
  },
  mergeSequenceTrackRow: {
    flex: 1,
    padding: 8,
    display: 'flex',
    alignItems: 'center',
    overflowX: 'auto',
    backgroundColor: 'rgba(52, 211, 153, 0.03)',
    borderRadius: 6
  },
  emptyMergeTimelineNotice: {
    display: 'flex',
    alignItems: 'center',
    gap: 10,
    padding: '12px 18px',
    backgroundColor: 'rgba(52, 211, 153, 0.08)',
    border: '1px dashed rgba(52, 211, 153, 0.3)',
    borderRadius: 8,
    color: 'var(--text-main)',
    fontSize: 11,
    cursor: 'pointer',
    width: '100%'
  },
  mergeItemsSequenceFlex: {
    display: 'flex',
    alignItems: 'center',
    gap: 8,
    minHeight: 52
  },
  mergeSequenceCard: {
    display: 'flex',
    flexDirection: 'column',
    gap: 4,
    padding: 6,
    backgroundColor: 'var(--bg-surface)',
    border: '1px solid var(--border-color)',
    borderRadius: 6,
    cursor: 'grab',
    width: 170,
    flexShrink: 0,
    transition: 'all 0.15s ease',
    userSelect: 'none'
  },
  mergeSequenceCardActive: {
    borderColor: '#34d399',
    backgroundColor: 'rgba(52, 211, 153, 0.15)',
    boxShadow: '0 0 16px rgba(52, 211, 153, 0.8), inset 0 0 6px rgba(52, 211, 153, 0.3)'
  },
  mergeCardHeader: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between'
  },
  mergeIndexBadge: {
    fontSize: 9,
    fontWeight: 800,
    color: '#34d399',
    backgroundColor: 'rgba(52, 211, 153, 0.2)',
    padding: '1px 6px',
    borderRadius: 4
  },
  mergeShiftBtn: {
    background: 'none',
    border: 'none',
    color: 'var(--text-muted)',
    cursor: 'pointer',
    fontSize: 9,
    padding: '0 2px'
  },
  mergeDeleteBtn: {
    background: 'none',
    border: 'none',
    color: '#ef4444',
    cursor: 'pointer',
    fontSize: 10,
    padding: '0 2px',
    fontWeight: 700
  },
  mergeCardPreviewRow: {
    display: 'flex',
    alignItems: 'center',
    gap: 6
  },
  mergeCardThumb: {
    width: 48,
    height: 30,
    backgroundColor: '#000000',
    borderRadius: 4,
    overflow: 'hidden',
    flexShrink: 0,
    border: '1px solid var(--border-color)'
  },
  mergeCardMetaCol: {
    flex: 1,
    minWidth: 0,
    display: 'flex',
    flexDirection: 'column',
    gap: 1
  },
  mergeCardTitle: {
    fontSize: 9,
    fontWeight: 700,
    color: 'var(--text-main)',
    overflow: 'hidden',
    textOverflow: 'ellipsis',
    whiteSpace: 'nowrap'
  },
  mergeCardSize: {
    fontSize: 8,
    color: 'var(--text-dim)',
    fontFamily: 'monospace'
  },
  addMoreMergeItemCard: {
    display: 'flex',
    flexDirection: 'column',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 4,
    padding: '8px 16px',
    backgroundColor: 'rgba(52, 211, 153, 0.08)',
    border: '1px dashed rgba(52, 211, 153, 0.35)',
    borderRadius: 6,
    color: '#34d399',
    fontSize: 10,
    fontWeight: 700,
    cursor: 'pointer',
    height: 54,
    flexShrink: 0,
    transition: 'all 0.15s ease'
  },
  timelineInnerZoomTrack: {
    position: 'relative',
    minWidth: '100%',
    height: '100%',
    transition: 'width 0.15s ease'
  },
  videoTrackClipsFlex: {
    position: 'absolute',
    top: 0,
    bottom: 0,
    left: 0,
    right: 0,
    display: 'flex',
    alignItems: 'stretch',
    gap: 3,
    padding: '1px 0'
  },
  videoClipBlockItem: {
    position: 'relative',
    height: '100%',
    borderRadius: 4,
    border: '1.5px solid #2dd4bf',
    backgroundColor: 'var(--bg-surface)',
    overflow: 'hidden',
    cursor: 'pointer',
    flexShrink: 0,
    transition: 'all 0.15s ease',
    userSelect: 'none',
    boxSizing: 'border-box'
  },
  videoClipBlockSelected: {
    borderColor: '#38bdf8',
    borderWidth: 2,
    backgroundColor: 'rgba(56, 189, 248, 0.15)',
    boxShadow: '0 0 16px rgba(56, 189, 248, 0.85), inset 0 0 8px rgba(56, 189, 248, 0.35)',
    zIndex: 20
  },
  videoClipBlockPlaying: {
    borderColor: '#34d399',
    borderWidth: 1.5,
    backgroundColor: 'rgba(52, 211, 153, 0.1)'
  },
  clipFilmstripGrid: {
    position: 'absolute',
    top: 0,
    bottom: 0,
    left: 0,
    right: 0,
    display: 'flex',
    alignItems: 'stretch',
    overflow: 'hidden',
    opacity: 0.8
  },
  clipFilmThumbItem: {
    width: 60,
    minWidth: 40,
    maxWidth: 90,
    height: '100%',
    backgroundColor: '#000000',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    overflow: 'hidden',
    flexShrink: 0,
    borderRight: '1px solid var(--border-color)'
  },
  clipFilmStripSprocket: {
    flex: 1,
    height: '100%',
    backgroundImage: 'repeating-linear-gradient(90deg, rgba(255,255,255,0.03) 0, rgba(255,255,255,0.03) 12px, transparent 12px, transparent 24px)',
    pointerEvents: 'none'
  },
  clipHeaderOverlay: {
    position: 'absolute',
    top: 3,
    left: 6,
    right: 6,
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between',
    zIndex: 10,
    pointerEvents: 'none'
  },
  clipIndexBadge: {
    fontSize: 10,
    fontWeight: 800,
    color: '#ffffff',
    textShadow: '0 1px 3px rgba(0,0,0,0.9), 0 0 2px rgba(0,0,0,0.8)',
    overflow: 'hidden',
    textOverflow: 'ellipsis',
    whiteSpace: 'nowrap',
    maxWidth: '85%',
    letterSpacing: '0.2px'
  },
  clipDurationBadge: {
    fontSize: 8,
    fontFamily: 'monospace',
    color: '#a7f3d0',
    backgroundColor: 'rgba(0, 0, 0, 0.65)',
    padding: '1px 5px',
    borderRadius: 3
  },
  clipMiniDeleteBtn: {
    backgroundColor: 'rgba(239, 68, 68, 0.85)',
    border: 'none',
    borderRadius: 3,
    color: 'white',
    cursor: 'pointer',
    fontSize: 8,
    fontWeight: 800,
    padding: '1px 4px',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    lineHeight: 1,
    pointerEvents: 'auto',
    transition: 'all 0.15s ease'
  },
  addMoreMergeItemMiniBtn: {
    width: 24,
    height: '100%',
    backgroundColor: 'rgba(52, 211, 153, 0.1)',
    border: '1px dashed rgba(52, 211, 153, 0.4)',
    borderRadius: 4,
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    cursor: 'pointer',
    flexShrink: 0
  },
  zoomStepBtn: {
    background: 'none',
    border: 'none',
    color: 'var(--text-muted)',
    cursor: 'pointer',
    padding: '1px 3px',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    borderRadius: 3,
    transition: 'all 0.15s ease'
  },
  zoomPctBadge: {
    fontSize: 9,
    fontFamily: 'monospace',
    fontWeight: 700,
    color: 'var(--primary)',
    minWidth: 32,
    textAlign: 'center'
  }
};

