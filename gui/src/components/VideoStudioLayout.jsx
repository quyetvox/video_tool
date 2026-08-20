import React, { useState, useEffect, useRef, forwardRef, useImperativeHandle } from 'react';
import VideoPlayerWithSubtitles from './VideoPlayerWithSubtitles';
import SubtitleInspector from './SubtitleInspector';
import { unifiedConfigToYaml as generateConfigYaml } from '../utils/configSchema';
import InteractiveTimeline from './InteractiveTimeline';
import PropertiesInspector from './PropertiesInspector';
import AssetTable from './AssetTable';
import ProcessLogsConsole from './ProcessLogsConsole';
import { useModal } from './ConfirmModal';

import {
  getMediaUrl,
  runScript,
  stopProcess,
  fetchFileContent,
  saveFileContent,
  fetchWorkspaceJobFiles,
  deleteWorkspaceJob,
  deleteStepCache,
  renameFile,
  deleteFile,
  fetchProjectConfig,
  saveProjectConfig,
  syncDownFromCloud,
  syncUpToCloud,
  offloadLocalFiles
} from '../services/api';

const getStem = (name) => {
  if (!name) return '';
  return name.replace(/\.[^/.]+$/, '').replace(/_vi$/, '');
};

const formatSecToTime = (sec) => {
  if (sec === null || sec === undefined || isNaN(sec) || sec < 0) return '00:00.000';
  const totalSecs = Math.floor(sec);
  const hrs = Math.floor(totalSecs / 3600);
  const mins = Math.floor((totalSecs % 3600) / 60);
  const secs = totalSecs % 60;
  const ms = Math.floor((sec % 1) * 1000);
  if (hrs > 0) {
    return `${hrs.toString().padStart(2, '0')}:${mins.toString().padStart(2, '0')}:${secs.toString().padStart(2, '0')}.${ms.toString().padStart(3, '0')}`;
  }
  return `${mins.toString().padStart(2, '0')}:${secs.toString().padStart(2, '0')}.${ms.toString().padStart(3, '0')}`;
};

const VideoStudioLayout = forwardRef(function VideoStudioLayout({
  project,
  videos = { srcFiles: [], outputFiles: [], workspaceJobs: [] },
  runningRelPaths = [],
  setRunningRelPaths = () => { },
  globalLogs = [],
  onClearLogs,
  onRefresh,
  onOpenStudioModal,
  onOpenDownloaderModal,
  onOpenConfigDrawer,
  libraryFilter = 'all',
  playerRef,
  selectedVideo = null,
  onSelectVideo = null
}, ref) {
  const { confirm, showAlert, showPrompt, showToast } = useModal();

  const { srcFiles = [], cutFiles = [], mergeFiles = [], outputFiles = [], workspaceJobs = [] } = videos || {};

  // All combined media files
  const allMediaFiles = [...srcFiles, ...cutFiles, ...mergeFiles, ...outputFiles].filter(f => f.isMedia);

  // Filtered by Library selection (All / Src / Cut / Merge / Output)
  const displayFiles = allMediaFiles.filter(f => {
    if (libraryFilter === 'src') return f.relPath.includes('/src/') || f.folder === 'src';
    if (libraryFilter === 'cut') return f.relPath.includes('/cut/') || f.folder === 'cut';
    if (libraryFilter === 'merge') return f.relPath.includes('/merge/') || f.folder === 'merge';
    if (libraryFilter === 'output') return f.relPath.includes('/output/') || f.folder === 'output';
    return true;
  });

  // ── Selected Active Video State ───────────────────────────────────────────
  const [internalSelectedFile, setInternalSelectedFile] = useState(null);
  const selectedFile = selectedVideo || internalSelectedFile;
  const setSelectedFile = (file) => {
    setInternalSelectedFile(file);
    if (onSelectVideo) onSelectVideo(file);
  };

  const [currentTime, setCurrentTime] = useState(0);
  const [duration, setDuration] = useState(0);
  const [startTime, setStartTime] = useState(0);
  const [endTime, setEndTime] = useState(5);
  const [cutMode, setCutMode] = useState('remove'); // 'remove' (Default: loại bỏ đoạn rác) | 'keep'
  const [isAccurateCut, setIsAccurateCut] = useState(false); // false: Siêu Tốc (<0.3s) | true: Chuẩn Frame (~1s)

  // Subtitle & Workspace Data State
  const [subtitles, setSubtitles] = useState([]);
  const [selectedSubIndex, setSelectedSubIndex] = useState(null);
  const [isSubModified, setIsSubModified] = useState(false);
  const [transRelPath, setTransRelPath] = useState('');
  const [jobFiles, setJobFiles] = useState([]);
  const [metadata, setMetadata] = useState(null);
  const [configData, setConfigData] = useState({});
  const [isProcessing, setIsProcessing] = useState(false);
  const [activeJobId, setActiveJobId] = useState(null);

  const handleStopProcess = async () => {
    try {
      await stopProcess(activeJobId || 'global');
    } catch (e) {
      console.error('Stop process error:', e);
    } finally {
      setIsProcessing(false);
      setActiveJobId(null);
      setRunningRelPaths([]);
    }
  };

  // Project switch vs deletion selection handler
  const currentProjectRef = useRef(project);
  useEffect(() => {
    if (currentProjectRef.current !== project) {
      currentProjectRef.current = project;
      if (displayFiles.length > 0) {
        setSelectedFile(displayFiles[0]);
      } else {
        setSelectedFile(null);
      }
    } else {
      // Same project: If current selected file was deleted from project, clear to empty state
      if (selectedFile && !allMediaFiles.some(f => f.relPath === selectedFile.relPath)) {
        setSelectedFile(null);
        setSubtitles([]);
        setSelectedSubIndex(null);
        setJobFiles([]);
        setMetadata(null);
        setCurrentTime(0);
        setDuration(0);
      }
    }
  }, [project, displayFiles, selectedFile]);

  // Load project config.yaml
  useEffect(() => {
    if (project) {
      fetchProjectConfig(project)
        .then(res => {
          if (res.content) {
            // Very simple yaml parsing or store raw text
            setConfigData({ raw: res.content });
          }
        })
        .catch(() => { });
    }
  }, [project]);

  // Reset playback position and trimmer range when selected video changes
  useEffect(() => {
    setCurrentTime(0);
    setStartTime(0);
    setSelectedSubIndex(null);
    setIsSubModified(false);
    if (selectedFile?.duration) {
      setDuration(selectedFile.duration);
      setEndTime(Math.min(selectedFile.duration, 5));
    }
  }, [selectedFile?.relPath]);

  // Load workspace job files, subtitles & metadata when selectedFile changes
  useEffect(() => {
    if (!selectedFile || !project) {
      setSubtitles([]);
      setJobFiles([]);
      setMetadata(null);
      return;
    }

    const stem = getStem(selectedFile.name);
    const jobId = `job_${stem}`;
    const transPath = `assets/${project}/workspace/${jobId}/s08_translation.json`;
    const altTranscriptPath = `assets/${project}/workspace/${jobId}/s07_transcript.json`;
    const metaPath = `assets/${project}/workspace/${jobId}/s08b_metadata.json`;

    setTransRelPath(transPath);

    // 1. Fetch Job Files
    fetchWorkspaceJobFiles(project, jobId)
      .then(res => {
        setJobFiles(res.files || []);
      })
      .catch(() => setJobFiles([]));

    // 2. Fetch Subtitles (prefer s08_translation.json, fallback s07_transcript.json)
    fetchFileContent(transPath)
      .then(res => {
        if (res.content) {
          const parsed = typeof res.content === 'string' ? JSON.parse(res.content) : res.content;
          setSubtitles(Array.isArray(parsed) ? parsed : []);
        } else {
          fetchFileContent(altTranscriptPath)
            .then(res2 => {
              if (res2.content) {
                const parsed2 = typeof res2.content === 'string' ? JSON.parse(res2.content) : res2.content;
                setSubtitles(Array.isArray(parsed2) ? parsed2 : []);
              } else {
                setSubtitles([]);
              }
            })
            .catch(() => setSubtitles([]));
        }
      })
      .catch(() => setSubtitles([]));

    // 3. Fetch AI Metadata
    fetchFileContent(metaPath)
      .then(res => {
        if (res.content) {
          const parsed = typeof res.content === 'string' ? JSON.parse(res.content) : res.content;
          setMetadata(parsed);
        } else {
          setMetadata(null);
        }
      })
      .catch(() => setMetadata(null));

  }, [selectedFile, project]);

  // Sync timeline end time when duration is loaded
  const handleDurationChange = (dur) => {
    setDuration(dur);
    if (endTime === 0 || endTime > dur) {
      setEndTime(Math.min(dur, Math.max(5, dur * 0.15)));
    }
  };

  // Seek video from subtitle click or timeline scrubber
  const handleSeek = (timeSec) => {
    setCurrentTime(timeSec);
    if (playerRef?.current) {
      playerRef.current.seekTo(timeSec);
    }
  };

  // ── Action Handlers ───────────────────────────────────────────────────────
  const handleSubtitleChange = (newSubtitles) => {
    setSubtitles(newSubtitles);
    setIsSubModified(true);
    // Auto-sync directly to workspace s08_translation.json so edits are saved instantly
    if (transRelPath && Array.isArray(newSubtitles)) {
      saveFileContent(transRelPath, JSON.stringify(newSubtitles, null, 2))
        .then(() => setIsSubModified(false))
        .catch(() => { });
    }
  };

  const handleUpdateSubtitleItem = (index, field, value) => {
    const updated = [...subtitles];
    if (updated[index]) {
      updated[index] = { ...updated[index], [field]: value };
      handleSubtitleChange(updated);
    }
  };

  const handleAddSubtitleItem = (newSub) => {
    const updated = [...subtitles, newSub].sort((a, b) => (a.start || 0) - (b.start || 0));
    handleSubtitleChange(updated);
  };

  const handleDeleteSubtitleItem = (index) => {
    const updated = subtitles.filter((_, idx) => idx !== index);
    handleSubtitleChange(updated);
    if (selectedSubIndex === index) setSelectedSubIndex(null);
  };

  const handleSplitSubtitleItem = (index, splitTime) => {
    const sub = subtitles[index];
    if (!sub) return;
    const part1 = { ...sub, end: splitTime };
    const part2 = { ...sub, start: splitTime, text: sub.text || '', translated_text: sub.translated_text || '' };
    const updated = [...subtitles.slice(0, index), part1, part2, ...subtitles.slice(index + 1)];
    handleSubtitleChange(updated);
  };

  const handleMergeSubtitleItem = (index) => {
    if (index >= subtitles.length - 1) return;
    const current = subtitles[index];
    const next = subtitles[index + 1];
    const merged = {
      ...current,
      end: next.end,
      text: `${current.text || ''} ${next.text || ''}`.trim(),
      translated_text: `${current.translated_text || ''} ${next.translated_text || ''}`.trim()
    };
    const updated = [...subtitles.slice(0, index), merged, ...subtitles.slice(index + 2)];
    handleSubtitleChange(updated);
  };

  const handleSaveSubtitles = async () => {
    if (!transRelPath || subtitles.length === 0) return;
    try {
      await saveFileContent(transRelPath, JSON.stringify(subtitles, null, 2));
      setIsSubModified(false);
      showToast({
        message: 'Đã lưu thay đổi phụ đề thành công!',
        type: 'success',
        duration: 2000
      });
    } catch (e) {
      showToast({
        message: 'Lỗi lưu phụ đề: ' + e.message,
        type: 'danger',
        duration: 3000
      });
    }
  };

  const handleExportTranslate = async () => {
    // Fallback: nếu chưa chọn file trong Asset Table thì dùng file đầu tiên trong danh sách
    const targetFile = selectedFile || allMediaFiles[0];
    if (!targetFile) return;
    const stem = getStem(targetFile.name);
    const jobId = `trans_${stem}`;
    setIsProcessing(true);
    setActiveJobId(jobId);
    setRunningRelPaths(prev => Array.from(new Set([...prev, targetFile.relPath, stem, jobId])));
    try {
      await runScript('main.py', ['translate', targetFile.relPath, '--voice'], jobId);
      await new Promise(r => setTimeout(r, 800));
      onRefresh && onRefresh();
    } finally {
      setIsProcessing(false);
      setActiveJobId(null);
      setRunningRelPaths(prev => prev.filter(p => !p.includes(stem) && !p.includes(jobId)));
    }
  };

  const handleExportOcrOnly = async () => {
    // Fallback: nếu chưa chọn file trong Asset Table thì dùng file đầu tiên trong danh sách
    const targetFile = selectedFile || allMediaFiles[0];
    if (!targetFile) return;
    const stem = getStem(targetFile.name);
    const jobId = `ocr_${stem}`;
    setIsProcessing(true);
    setActiveJobId(jobId);
    setRunningRelPaths(prev => Array.from(new Set([...prev, targetFile.relPath, stem, jobId])));
    try {
      await runScript('main.py', ['translate', targetFile.relPath, '--ocr-only'], jobId);
      await new Promise(r => setTimeout(r, 800));
      onRefresh && onRefresh();
    } finally {
      setIsProcessing(false);
      setActiveJobId(null);
      setRunningRelPaths(prev => prev.filter(p => !p.includes(stem) && !p.includes(jobId)));
    }
  };

  const handleResume = async () => {
    // Fallback: nếu chưa chọn file trong Asset Table thì dùng file đầu tiên trong danh sách
    const targetFile = selectedFile || allMediaFiles[0];
    if (!targetFile) return;
    const stem = getStem(targetFile.name);
    const jobId = `job_${stem}`;
    const runJobId = `resume_${stem}`;

    // Ensure latest subtitle edits are saved to s08_translation.json on disk before resuming
    if (transRelPath && Array.isArray(subtitles) && subtitles.length > 0) {
      try {
        await saveFileContent(transRelPath, JSON.stringify(subtitles, null, 2));
        await new Promise(r => setTimeout(r, 200));
      } catch (err) {
        console.error('Failed to save subtitles before resume:', err);
      }
    }

    // Check if job exists in workspace
    if (!jobFiles || jobFiles.length === 0) {
       showAlert({ title: 'Cảnh báo', message: 'Không tìm thấy cache job. Bạn cần chạy Translate trước.', type: 'warning' });
       return;
    }

    setIsProcessing(true);
    setActiveJobId(runJobId);
    setRunningRelPaths(prev => Array.from(new Set([...prev, targetFile.relPath, stem, jobId, runJobId])));
    try {
      await runScript('main.py', ['resume', `${project}:${jobId}`], runJobId);
      await new Promise(r => setTimeout(r, 800));
      onRefresh && onRefresh();
    } finally {
      setIsProcessing(false);
      setActiveJobId(null);
      setRunningRelPaths(prev => prev.filter(p => !p.includes(stem) && !p.includes(runJobId)));
    }
  };

  // Cutting: Default is REMOVING GARBAGE RANGE using concat.py --remove
  const handleCutTrim = async () => {
    if (!selectedFile) return;
    const stem = getStem(selectedFile.name);
    const jobId = `cut_${Date.now()}`;
    setIsProcessing(true);
    setActiveJobId(jobId);

    const startStr = formatSecToTime(startTime);
    const endStr = formatSecToTime(endTime);

    try {
      const extraArgs = isAccurateCut ? ['--accurate'] : [];
      if (cutMode === 'remove') {
        // Remove garbage range and overwrite the file directly (no new file)
        const rangeParam = `${startStr}-${endStr}`;
        await runScript('concat.py', [selectedFile.relPath, '--remove', rangeParam, '--overwrite', ...extraArgs], jobId);
      } else {
        // Keep selected range only -> Trimmer creates a new file (e.g. video_cut_1.mp4)
        await runScript('trim.py', [selectedFile.relPath, '--start', startStr, '--end', endStr, ...extraArgs], jobId);
      }
      await new Promise(r => setTimeout(r, 800));
      onRefresh && onRefresh();

      showAlert({
        title: 'Cắt Video Thành Công',
        message: cutMode === 'remove'
          ? `Đã loại bỏ đoạn rác (${startStr} → ${endStr}) khỏi video gốc!`
          : `Đã cắt và lưu đoạn video (${startStr} → ${endStr}) thành công!`,
        type: 'success'
      });

      // Reset values to default
      setStartTime(0);
      setEndTime(duration || 0);
    } catch (e) {
      showAlert({
        title: 'Lỗi Cắt Video',
        message: 'Lỗi khi cắt video: ' + e.message,
        type: 'danger'
      });
    } finally {
      setIsProcessing(false);
      setActiveJobId(null);
    }
  };

  const handleDeleteStep = async (stepId) => {
    if (!selectedFile) return;
    const stem = getStem(selectedFile.name);
    const jobId = `job_${stem}`;
    const ok = await confirm({
      title: `Xóa cache bước ${stepId}?`,
      message: `Hệ thống sẽ dọn dẹp file cache của bước này và tự động xóa (cascade) tất cả các bước phía sau để chuẩn bị chạy lại.`,
      confirmText: 'Xác Nhận Xóa Step',
      type: 'warning'
    });
    if (!ok) return;

    try {
      await deleteStepCache(project, jobId, stepId);
      const res = await fetchWorkspaceJobFiles(project, jobId);
      setJobFiles(res.files || []);
      onRefresh && onRefresh();
    } catch (e) {
      showAlert({ title: 'Lỗi', message: e.message, type: 'danger' });
    }
  };

  const handleDeleteJob = async () => {
    if (!selectedFile) return;
    const stem = getStem(selectedFile.name);
    const jobId = `job_${stem}`;
    const ok = await confirm({
      title: `Xóa toàn bộ Job Cache?`,
      message: `Toàn bộ thư mục workspace và file cache của job "${jobId}" sẽ bị xóa vĩnh viễn khỏi SSD.`,
      confirmText: 'Xóa Toàn Bộ Job',
      type: 'danger'
    });
    if (!ok) return;

    try {
      await deleteWorkspaceJob(project, jobId);
      setJobFiles([]);
      setSubtitles([]);
      setMetadata(null);
      onRefresh && onRefresh();
    } catch (e) {
      showAlert({ title: 'Lỗi', message: e.message, type: 'danger' });
    }
  };

  const handleDeleteFile = async (relPath) => {
    const fname = relPath.split('/').pop();
    const ok = await confirm({
      title: 'Xác nhận xóa vĩnh viễn video?',
      message: `File "${fname}" và toàn bộ dữ liệu workspace cache sẽ bị xóa hoàn toàn khỏi đĩa SSD.`,
      confirmText: 'Xóa Vĩnh Viễn',
      type: 'danger'
    });
    if (!ok) return;

    try {
      await deleteFile(relPath);
      if (selectedFile?.relPath === relPath) {
        setSelectedFile(null);
        setSubtitles([]);
        setSelectedSubIndex(null);
        setJobFiles([]);
        setMetadata(null);
        setCurrentTime(0);
        setDuration(0);
      }
      await new Promise(r => setTimeout(r, 200));
      onRefresh && onRefresh();
    } catch (e) {
      console.error('Lỗi khi xóa file:', e);
      showAlert({ title: 'Lỗi Xóa File', message: e.message, type: 'danger' });
    }
  };

  const handleRenameFile = async (file) => {
    if (!file || !file.name || !file.relPath) return;
    const newName = await showPrompt({
      title: 'Đổi Tên File',
      message: `Nhập tên mới cho file "${file.name}":`,
      defaultValue: file.name,
      placeholder: 'Tên file mới...',
      confirmText: 'Đổi Tên',
      type: 'info'
    });
    if (!newName || !newName.trim() || newName.trim() === file.name) return;

    try {
      const res = await renameFile(file.relPath, newName.trim());
      if (res.error) {
        showAlert({ title: 'Lỗi Đổi Tên File', message: res.error, type: 'danger' });
      } else {
        await new Promise(r => setTimeout(r, 200));
        onRefresh && onRefresh();
      }
    } catch (err) {
      showAlert({ title: 'Lỗi Đổi Tên File', message: err.message, type: 'danger' });
    }
  };

  const [currentCfg, setCurrentCfg] = useState(null);

  const handleConfigChange = (newCfg) => {
    setCurrentCfg(newCfg);
  };

  const handleSaveConfig = async (yamlStr) => {
    if (!project) return;
    try {
      let finalYaml = yamlStr;
      if (!finalYaml) {
        if (currentCfg) {
          finalYaml = generateConfigYaml(currentCfg);
        } else if (configData?.raw) {
          finalYaml = configData.raw;
        }
      }
      if (!finalYaml) return;
      await saveProjectConfig(project, finalYaml);
      setConfigData({ raw: finalYaml });
      showToast({
        message: `Đã lưu cấu hình dự án "${project}" (config.yaml)`,
        type: 'success',
        duration: 2000
      });
    } catch (err) {
      showToast({
        message: 'Lỗi lưu cấu hình: ' + err.message,
        type: 'danger',
        duration: 3000
      });
    }
  };

  useImperativeHandle(ref, () => ({
    saveConfig: handleSaveConfig,
    exportTranslate: handleExportTranslate,
    exportOcrOnly: handleExportOcrOnly,
    resume: handleResume,
    stopProcess: handleStopProcess
  }));

  // Batch actions
  const handleBatchTranslateVoice = async (relPaths) => {
    if (!relPaths || relPaths.length === 0) return;
    setIsProcessing(true);
    setRunningRelPaths(prev => Array.from(new Set([...prev, ...relPaths])));
    try {
      for (const p of relPaths) {
        const stem = getStem(p.split('/').pop());
        const jobId = `batch_voice_${stem}`;
        setActiveJobId(jobId);
        setRunningRelPaths(prev => Array.from(new Set([...prev, p, stem, jobId])));
        await runScript('main.py', ['translate', p, '--voice'], jobId);
        setRunningRelPaths(prev => prev.filter(item => item !== p && item !== stem && item !== jobId));
      }
      await new Promise(r => setTimeout(r, 800));
      onRefresh && onRefresh();
    } catch (e) {
      console.error('Batch translate voice error:', e);
      showAlert({ title: 'Lỗi Dịch Hàng Loạt', message: e.message, type: 'danger' });
    } finally {
      setIsProcessing(false);
      setActiveJobId(null);
      setRunningRelPaths([]);
    }
  };

  const handleBatchTranslateSub = async (relPaths) => {
    if (!relPaths || relPaths.length === 0) return;
    setIsProcessing(true);
    setRunningRelPaths(prev => Array.from(new Set([...prev, ...relPaths])));
    try {
      for (const p of relPaths) {
        const stem = getStem(p.split('/').pop());
        const jobId = `batch_ocr_${stem}`;
        setActiveJobId(jobId);
        setRunningRelPaths(prev => Array.from(new Set([...prev, p, stem, jobId])));
        await runScript('main.py', ['translate', p, '--ocr-only'], jobId);
        setRunningRelPaths(prev => prev.filter(item => item !== p && item !== stem && item !== jobId));
      }
      await new Promise(r => setTimeout(r, 800));
      onRefresh && onRefresh();
    } catch (e) {
      console.error('Batch translate sub error:', e);
      showAlert({ title: 'Lỗi Dịch Hàng Loạt', message: e.message, type: 'danger' });
    } finally {
      setIsProcessing(false);
      setActiveJobId(null);
      setRunningRelPaths([]);
    }
  };

  const handleBatchUploadCloud = async (relPaths) => {
    const fileNames = relPaths.map(p => p.split('/').pop());
    setIsProcessing(true);
    try {
      await syncUpToCloud(project, fileNames);
      onRefresh && onRefresh();
    } finally {
      setIsProcessing(false);
    }
  };

  const handleBatchSyncDown = async (relPaths) => {
    const fileNames = relPaths.map(p => p.split('/').pop());
    setIsProcessing(true);
    try {
      await syncDownFromCloud(project, fileNames);
      onRefresh && onRefresh();
    } finally {
      setIsProcessing(false);
    }
  };

  const handleBatchOffload = async (relPaths) => {
    const fileNames = relPaths.map(p => p.split('/').pop());
    const ok = await confirm({
      title: `Giải phóng dung lượng SSD?`,
      message: `Hệ thống sẽ xóa file cục bộ của ${fileNames.length} video đã được đồng bộ an toàn lên Google Cloud Storage.`,
      confirmText: 'Xác Nhận Offload',
      type: 'warning'
    });
    if (!ok) return;

    setIsProcessing(true);
    try {
      await offloadLocalFiles(project, fileNames);
      onRefresh && onRefresh();
    } finally {
      setIsProcessing(false);
    }
  };

  const handleBatchDelete = async (relPaths) => {
    const ok = await confirm({
      title: `Xóa vĩnh viễn ${relPaths.length} video đã chọn?`,
      message: `Tất cả ${relPaths.length} video và toàn bộ workspace cache liên quan sẽ bị xóa khỏi hệ thống.`,
      confirmText: `Xóa Tất Cả (${relPaths.length})`,
      type: 'danger'
    });
    if (!ok) return;

    for (const p of relPaths) {
      await deleteFile(p);
    }
    if (selectedFile && relPaths.includes(selectedFile.relPath)) {
      setSelectedFile(null);
      setSubtitles([]);
      setSelectedSubIndex(null);
      setJobFiles([]);
      setMetadata(null);
      setCurrentTime(0);
      setDuration(0);
    }
    await new Promise(r => setTimeout(r, 200));
    onRefresh && onRefresh();
  };

  return (
    <div style={styles.studioLayout}>
      {/* ── UPPER HALF: Studio Canvas ────────────────────────────────────────── */}
      <div style={styles.upperSection}>
        {/* Left 3/4: Player + Subtitles + Timeline */}
        <div style={styles.canvasMainCol}>
          {/* Top Row: Video Player + Subtitle Inspector */}
          <div style={styles.playerAndSubRow}>
            {/* Video Player */}
            <div style={styles.playerContainer}>
              <VideoPlayerWithSubtitles
                ref={playerRef}
                videoFile={selectedFile}
                subtitles={subtitles}
                currentTime={currentTime}
                onTimeUpdate={setCurrentTime}
                onDurationChange={handleDurationChange}
              />
            </div>

            {/* Subtitle Inspector Panel */}
            <div style={styles.subtitleContainer}>
              <SubtitleInspector
                subtitles={subtitles}
                currentTime={currentTime}
                selectedSubIndex={selectedSubIndex}
                onSelectSubIndex={setSelectedSubIndex}
                onSubtitleChange={handleSubtitleChange}
                onSeekToSubtitle={handleSeek}
                onTranslateAll={handleExportTranslate}
                onAutoSync={handleResume}
                onSaveSubtitles={handleSaveSubtitles}
                isSubModified={isSubModified}
                configData={configData}
                onConfigChange={handleConfigChange}
                isProcessing={isProcessing}
              />
            </div>
          </div>

          {/* Middle: Timeline & Range Trimmer */}
          <div style={styles.timelineRow}>
            <InteractiveTimeline
              duration={duration}
              currentTime={currentTime}
              startTime={startTime}
              endTime={endTime}
              onRangeChange={(s, e) => { setStartTime(s); setEndTime(e); }}
              onSeek={handleSeek}
              onCutTrim={handleCutTrim}
              cutMode={cutMode}
              onToggleCutMode={setCutMode}
              isAccurateCut={isAccurateCut}
              onToggleAccurateCut={setIsAccurateCut}
              isProcessing={isProcessing}
            />
          </div>
        </div>

        {/* Right 1/4: Properties & Step Inspector */}
        <div style={styles.canvasRightCol}>
          <PropertiesInspector
            videoFile={selectedFile}
            duration={duration}
            startTime={startTime}
            endTime={endTime}
            onRangeChange={(s, e) => { setStartTime(s); setEndTime(e); }}
            onCutTrim={handleCutTrim}
            cutMode={cutMode}
            jobFiles={jobFiles}
            metadata={metadata}
            onDeleteStep={handleDeleteStep}
            onDeleteJob={handleDeleteJob}
            isProcessing={isProcessing}
          />
        </div>
      </div>

      {/* ── LOWER HALF: Bottom Dual-Panel (Asset Table + Process Logs) ──────── */}
      <div style={styles.lowerSection}>
        {/* Bottom-Left: Asset Manager Table */}
        <div style={styles.bottomLeftCol}>
          <AssetTable
            files={displayFiles}
            selectedFile={selectedFile}
            onSelectFile={setSelectedFile}
            runningRelPaths={runningRelPaths}
            onRefresh={onRefresh}
            onOpenTrimmer={() => onOpenStudioModal && onOpenStudioModal(selectedFile?.relPath)}
            onDeleteFile={handleDeleteFile}
            onRenameFile={handleRenameFile}
            onBatchTranslateVoice={handleBatchTranslateVoice}
            onBatchTranslateSub={handleBatchTranslateSub}
            onBatchUploadCloud={handleBatchUploadCloud}
            onBatchSyncDown={handleBatchSyncDown}
            onBatchOffload={handleBatchOffload}
            onBatchDelete={handleBatchDelete}
          />
        </div>

        {/* Bottom-Right: Process Logs Console */}
        <div style={styles.bottomRightCol}>
          <ProcessLogsConsole
            logs={globalLogs}
            isProcessRunning={isProcessing || runningRelPaths.length > 0}
            onClearLogs={onClearLogs}
            onStopProcess={handleStopProcess}
          />
        </div>
      </div>
    </div>
  );
});

export default VideoStudioLayout;

const styles = {
  studioLayout: {
    display: 'flex',
    flexDirection: 'column',
    width: '100%',
    height: '100%',
    backgroundColor: 'var(--bg-app)',
    padding: '10px 14px',
    gap: 10,
    overflow: 'hidden',
  },
  upperSection: {
    display: 'flex',
    gap: 10,
    flex: '1 1 58%',
    minHeight: '340px',
    maxHeight: '62%',
    overflow: 'hidden',
  },
  canvasMainCol: {
    flex: '1 1 74%',
    display: 'flex',
    flexDirection: 'column',
    gap: 8,
    minHeight: 0,
    overflow: 'hidden',
  },
  playerAndSubRow: {
    display: 'flex',
    gap: 10,
    flex: 1,
    minHeight: 0,
    overflow: 'hidden',
  },
  playerContainer: {
    flex: '1 1 54%',
    minWidth: 0,
    minHeight: 0,
    height: '100%',
    overflow: 'hidden',
  },
  subtitleContainer: {
    flex: '1 1 46%',
    minWidth: 0,
    minHeight: 0,
    height: '100%',
    overflow: 'hidden',
  },
  timelineRow: {
    height: 'auto',
    flexShrink: 0,
  },
  canvasRightCol: {
    flex: '0 0 260px',
    height: '100%',
    overflow: 'hidden',
  },
  lowerSection: {
    display: 'flex',
    gap: 10,
    flex: '1 1 42%',
    minHeight: '220px',
    overflow: 'hidden',
  },
  bottomLeftCol: {
    flex: '1 1 65%',
    minWidth: 0,
    height: '100%',
  },
  bottomRightCol: {
    flex: '1 1 35%',
    minWidth: 0,
    height: '100%',
  }
};
