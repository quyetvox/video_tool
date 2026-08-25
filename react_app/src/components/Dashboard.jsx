import React, { useState, useEffect, useRef } from 'react';
import { 
  Play, 
  Layers, 
  RotateCcw, 
  CheckCircle2, 
  FileVideo, 
  Copy, 
  Scissors, 
  Wand2, 
  RefreshCw,
  Eye,
  FileText,
  X,
  Check,
  LayoutGrid,
  List,
  FolderOpen,
  Image as ImageIcon,
  CheckSquare,
  Square,
  FileCode,
  Volume2,
  Trash2,
  AlertTriangle,
  Pencil,
  Settings,
  Search,
  ChevronDown,
  ChevronRight,
  Cloud,
  CloudDownload,
  CloudUpload,
  HardDrive
} from 'lucide-react';
import { 
  getMediaUrl, 
  runScript, 
  fetchFileContent, 
  saveFileContent,
  fetchWorkspaceJobFiles, 
  deleteWorkspaceJob, 
  deleteStepCache, 
  renameFile, 
  deleteFile,
  fetchStorageStatus,
  syncDownFromCloud,
  syncUpToCloud,
  offloadLocalFiles,
  deleteCloudFiles,
  refreshStorageCache
} from '../services/api';

import CompactVideoCard from './CompactVideoCard';
import LogConsole from './LogConsole';
import { useModal } from './ConfirmModal';

const formatSizeStr = (sizeBytes) => {
  if (!sizeBytes || isNaN(sizeBytes)) return '0 B';
  if (sizeBytes < 1024) return `${sizeBytes} B`;
  if (sizeBytes < 1024 * 1024) return `${(sizeBytes / 1024).toFixed(1)} KB`;
  if (sizeBytes < 1024 * 1024 * 1024) return `${(sizeBytes / (1024 * 1024)).toFixed(1)} MB`;
  return `${(sizeBytes / (1024 * 1024 * 1024)).toFixed(2)} GB`;
};

const getStem = (name) => {
  if (!name) return '';
  return name.replace(/\.[^/.]+$/, '').replace(/_vi$/, '');
};

const STEP_LABELS = [
  { id: 's01_probe', label: '1. Probe Video Info' },
  { id: 's02_demux', label: '2. Demux Streams' },
  { id: 's03_subtitle_detect', label: '3. Subtitle Detect' },
  { id: 's04_audio_separate', label: '4. Demucs Voice Separation' },
  { id: 's05_asr', label: '5. Whisper ASR' },
  { id: 's05b_gender_detect', label: '5b. Gender Detection' },
  { id: 's06_ocr', label: '6. PaddleOCR Subtitles' },
  { id: 's07_transcript_merge', label: '7. Transcript Fusion' },
  { id: 's08_translation', label: '8. LLM Translation' },
  { id: 's08b_metadata_gen', label: '8b. AI Metadata Gen' },
  { id: 's08c_timing', label: '8c. Subtitle Timing Align' },
  { id: 's09_subtitle_gen', label: '9. Subtitle ASS Generation' },
  { id: 's10_inpaint', label: '10. BoxBlur Inpaint & Logo' },
  { id: 's11_subtitle_render', label: '11. Subtitle Burn-in' },
  { id: 's12_tts', label: '12. EdgeTTS Voice Gen' },
  { id: 's13_audio_mix', label: '13. Audio Multi-Stream Mix' },
  { id: 's14_encode', label: '14. Final H.264 Encode' }
];

export default function Dashboard({ 
  project, 
  videos, 
  runningRelPaths = [],
  setRunningRelPaths = () => {},
  globalLogs = [],
  onClearLogs,
  onRefresh, 
  onOpenTrimmer, 
  onSelectTab 
}) {
  const { confirm, showAlert, showPrompt } = useModal();
  const { srcFiles = [], outputFiles = [], workspaceJobs = [] } = videos || {};
  
  // Cloud Storage State
  const [storageStatus, setStorageStatus] = useState(null);
  const [isStorageBusy, setIsStorageBusy] = useState(false);
  const lastLoadedProjectRef = useRef(null);

  const loadStorageStatus = (force = false) => {
    if (!project) return;
    if (!force && lastLoadedProjectRef.current === project && storageStatus) return;
    lastLoadedProjectRef.current = project;
    fetchStorageStatus(project)
      .then(res => {
        if (res && res.mounted !== undefined) {
          setStorageStatus(res);
        }
      })
      .catch(() => {});
  };

  useEffect(() => {
    if (project !== lastLoadedProjectRef.current) {
      loadStorageStatus(true);
    }
  }, [project]);

  // Combine Local Media Files with Cloud Media Files and map Cloud Status
  const localMedia = [...srcFiles, ...outputFiles].filter(f => f.isMedia);
  const cloudFileMap = {};
  if (storageStatus && storageStatus.files) {
    storageStatus.files.forEach(sf => {
      cloudFileMap[sf.relPath] = sf;
      cloudFileMap[sf.name] = sf;
    });
  }

  const enrichedLocal = localMedia.map(f => {
    const relClean = f.relPath.replace(`assets/${project}/`, '');
    const matched = cloudFileMap[relClean] || cloudFileMap[f.name];
    return {
      ...f,
      cloudStatus: matched ? matched.status : 'local_only',
      isCloudOnly: false
    };
  });

  // Also include Cloud-Only media files if mounted
  const cloudOnlyItems = [];
  if (storageStatus && storageStatus.files) {
    storageStatus.files.forEach(sf => {
      if (sf.status === 'cloud_only' && sf.isMedia) {
        const isOut = sf.relPath.startsWith('output/');
        cloudOnlyItems.push({
          name: sf.name,
          path: sf.cloud ? sf.cloud.fullPath : '',
          relPath: `assets/${project}/${sf.relPath}`,
          sizeBytes: sf.sizeBytes,
          mtime: sf.cloud ? sf.cloud.mtime : Date.now(),
          isMedia: true,
          cloudStatus: 'cloud_only',
          isCloudOnly: true,
          folder: isOut ? 'output' : 'src'
        });
      }
    });
  }

  const allFiles = [...enrichedLocal, ...cloudOnlyItems];

  const [folderFilter, setFolderFilter] = useState('all'); // 'all' | 'src' | 'output' | 'cloud_only' | 'synced'
  const [searchQuery, setSearchQuery] = useState('');
  const [displayLimit, setDisplayLimit] = useState(24);
  const [selectedRelPaths, setSelectedRelPaths] = useState([]);
  
  // Selected video for Right Panel (Hero preview & action controls)
  const [activeSelectedFile, setActiveSelectedFile] = useState(allFiles[0] || null);

  // Translation Editor State for s08_translation.json
  const [showTranslationEditor, setShowTranslationEditor] = useState(false);
  const [translationContent, setTranslationContent] = useState(null);
  const [translationRelPath, setTranslationRelPath] = useState('');
  const [isSavingTranslation, setIsSavingTranslation] = useState(false);

  // Video Config Override State for video_config.yaml
  const [showConfigOverride, setShowConfigOverride] = useState(false);
  const [videoConfigContent, setVideoConfigContent] = useState('');
  const [videoConfigRelPath, setVideoConfigRelPath] = useState('');
  const [isSavingConfig, setIsSavingConfig] = useState(false);

  // Text Content Viewer Modal State
  const [textContentData, setTextContentData] = useState(null); // { path, content }
  const [copiedAll, setCopiedAll] = useState(false);
  const [runningJob, setRunningJob] = useState(null);

  // Workspace Job Modal & Accordion State
  const [workspaceJobModal, setWorkspaceJobModal] = useState(null); // { jobId, files: [] }
  const [showWorkspaceJobs, setShowWorkspaceJobs] = useState(true);

  const galleryScrollRef = useRef(null);
  const sentinelRef = useRef(null);

  // Keep activeSelectedFile synced if video list updates
  useEffect(() => {
    if (!activeSelectedFile && allFiles.length > 0) {
      setActiveSelectedFile(allFiles[0]);
    } else if (activeSelectedFile) {
      const found = allFiles.find(f => f.relPath === activeSelectedFile.relPath);
      if (found) setActiveSelectedFile(found);
    }
  }, [videos]);

  // Active selected video's workspace job files
  const [activeJobFiles, setActiveJobFiles] = useState([]);

  const loadActiveJobFiles = () => {
    if (!activeSelectedFile || !project) {
      setActiveJobFiles([]);
      return;
    }
    const stem = getStem(activeSelectedFile.name);
    const jobId = `job_${stem}`;
    fetchWorkspaceJobFiles(project, jobId)
      .then(res => {
        if (res && res.files) {
          setActiveJobFiles(res.files);
        } else {
          setActiveJobFiles([]);
        }
      })
      .catch(() => setActiveJobFiles([]));
  };

  useEffect(() => {
    loadActiveJobFiles();
  }, [activeSelectedFile, project, videos]);

  // Load s08_translation.json and video_config.yaml when activeSelectedFile changes
  useEffect(() => {
    if (!activeSelectedFile || !project) {
      setTranslationContent(null);
      setTranslationRelPath('');
      setVideoConfigContent('');
      setVideoConfigRelPath('');
      return;
    }

    const stem = getStem(activeSelectedFile.name);
    const jobId = `job_${stem}`;
    const transPath = `assets/${project}/workspace/${jobId}/s08_translation.json`;
    const cfgPath = `assets/${project}/workspace/${jobId}/video_config.yaml`;

    // 1. Load translation JSON if exists
    fetchFileContent(transPath)
      .then(res => {
        if (res.content) {
          let str = res.content;
          if (typeof str === 'object') str = JSON.stringify(str, null, 2);
          else {
            try { str = JSON.stringify(JSON.parse(str), null, 2); } catch (e) {}
          }
          setTranslationContent(str);
          setTranslationRelPath(transPath);
        } else {
          setTranslationContent(null);
          setTranslationRelPath('');
        }
      })
      .catch(() => {
        setTranslationContent(null);
        setTranslationRelPath('');
      });

    // 2. Load video config yaml if exists
    fetchFileContent(cfgPath)
      .then(res => {
        if (res.content) {
          setVideoConfigContent(res.content);
        } else {
          setVideoConfigContent('# Override config.yaml riêng cho video này\n# ocr_only: true\n# music_volume: 0.3');
        }
        setVideoConfigRelPath(cfgPath);
      })
      .catch(() => {
        setVideoConfigContent('# Override config.yaml riêng cho video này\n# ocr_only: true\n# music_volume: 0.3');
        setVideoConfigRelPath(cfgPath);
      });
  }, [activeSelectedFile, project]);

  // Filter videos based on folder & search query
  const filteredFiles = allFiles.filter(file => {
    if (folderFilter === 'src' && !file.relPath.includes('/src/')) return false;
    if (folderFilter === 'output' && !file.relPath.includes('/output/')) return false;
    if (folderFilter === 'cloud_only' && file.cloudStatus !== 'cloud_only') return false;
    if (folderFilter === 'synced' && file.cloudStatus !== 'synced') return false;
    if (searchQuery.trim()) {
      return file.name.toLowerCase().includes(searchQuery.toLowerCase());
    }
    return true;
  });

  const visibleFiles = filteredFiles.slice(0, displayLimit);

  // Cloud Storage Action Handlers
  const handleSyncDownFiles = async (files = null) => {
    if (!project) return;
    setIsStorageBusy(true);
    setRunningJob('sync_down');
    try {
      const cleanPaths = files ? files.map(p => p.replace(`assets/${project}/`, '')) : null;
      await syncDownFromCloud(project, cleanPaths, `sync_down_${Date.now()}`);
      if (files) {
        setSelectedRelPaths(prev => prev.filter(p => !files.includes(p)));
      } else {
        setSelectedRelPaths([]);
      }
    } finally {
      setIsStorageBusy(false);
      setRunningJob(null);
      await new Promise(r => setTimeout(r, 800));
      onRefresh();
      loadStorageStatus(true);
    }
  };

  const handleSyncUpFiles = async (files = null) => {
    if (!project) return;
    setIsStorageBusy(true);
    setRunningJob('sync_up');
    try {
      const cleanPaths = files ? files.map(p => p.replace(`assets/${project}/`, '')) : null;
      await syncUpToCloud(project, cleanPaths, `sync_up_${Date.now()}`);
      if (files) {
        setSelectedRelPaths(prev => prev.filter(p => !files.includes(p)));
      } else {
        setSelectedRelPaths([]);
      }
    } finally {
      setIsStorageBusy(false);
      setRunningJob(null);
      await new Promise(r => setTimeout(r, 800));
      onRefresh();
      loadStorageStatus(true);
    }
  };

  const handleOffloadFiles = async (files = null) => {
    if (!project) return;
    setIsStorageBusy(true);
    setRunningJob('offload');
    try {
      const cleanPaths = files ? files.map(p => p.replace(`assets/${project}/`, '')) : null;
      await offloadLocalFiles(project, cleanPaths, `offload_${Date.now()}`);
      if (files) {
        setSelectedRelPaths(prev => prev.filter(p => !files.includes(p)));
      } else {
        setSelectedRelPaths([]);
      }
    } finally {
      setIsStorageBusy(false);
      setRunningJob(null);
      await new Promise(r => setTimeout(r, 800));
      onRefresh();
      loadStorageStatus(true);
    }
  };

  const [isRefreshingCache, setIsRefreshingCache] = useState(false);

  const handleRefreshCache = async () => {
    if (!project) return;
    setIsRefreshingCache(true);
    try {
      await refreshStorageCache(project);
    } catch (e) {
      console.error(e);
    } finally {
      setIsRefreshingCache(false);
      await new Promise(r => setTimeout(r, 300));
      onRefresh();
      loadStorageStatus(true);
    }
  };

  // Reset displayLimit on filter or search query change
  useEffect(() => {
    setDisplayLimit(24);
  }, [folderFilter, searchQuery]);

  // Infinite Scroll Observer scoped to galleryScrollContainer + Scroll listener fallback
  useEffect(() => {
    const rootEl = galleryScrollRef.current;
    const targetEl = sentinelRef.current;
    if (!rootEl) return;

    let observer = null;
    if (targetEl) {
      observer = new IntersectionObserver(
        (entries) => {
          if (entries[0].isIntersecting) {
            setDisplayLimit(prev => Math.min(prev + 24, filteredFiles.length));
          }
        },
        { root: rootEl, rootMargin: '250px', threshold: 0 }
      );
      observer.observe(targetEl);
    }

    const handleScroll = () => {
      if (rootEl.scrollHeight - rootEl.scrollTop - rootEl.clientHeight < 250) {
        setDisplayLimit(prev => Math.min(prev + 24, filteredFiles.length));
      }
    };
    rootEl.addEventListener('scroll', handleScroll, { passive: true });

    return () => {
      if (observer && targetEl) observer.unobserve(targetEl);
      rootEl.removeEventListener('scroll', handleScroll);
    };
  }, [filteredFiles.length, displayLimit]);

  const getStem = (str) => {
    if (!str) return '';
    const base = str.split('/').pop();
    return base
      .replace(/^job_/, '')
      .replace(/_vi\.[^/.]+$|\.[^/.]+$/, '')
      .replace(/\.[^/.]+$/, '');
  };

  const isFileProcessing = (file) => {
    if (!file) return false;
    const name = file.name || '';
    const relPath = file.relPath || '';
    const fileStem = getStem(name || relPath);
    if (!fileStem) return false;

    return runningRelPaths.some(p => {
      const pStem = getStem(p);
      return pStem === fileStem || p === relPath || p === `job_${fileStem}`;
    });
  };

  const activeJobId = activeSelectedFile ? `job_${getStem(activeSelectedFile.name)}` : null;

  const handleSelectFile = (file) => {
    setActiveSelectedFile(file);
  };

  const handleToggleSelect = (relPath) => {
    if (selectedRelPaths.includes(relPath)) {
      setSelectedRelPaths(selectedRelPaths.filter(p => p !== relPath));
    } else {
      setSelectedRelPaths([...selectedRelPaths, relPath]);
    }
  };

  const handleSelectAll = () => {
    if (selectedRelPaths.length === filteredFiles.length) {
      setSelectedRelPaths([]);
    } else {
      setSelectedRelPaths(filteredFiles.map(f => f.relPath));
    }
  };

  const handleBatchTranslate = async () => {
    if (!project) return;
    setRunningJob('batch');
    const allSrcRelPaths = srcFiles.map(f => f.relPath);
    setRunningRelPaths(prev => [...prev, ...allSrcRelPaths]);
    try {
      await runScript('batch_translate.py', [`assets/${project}/src/`], `batch_${Date.now()}`);
    } finally {
      setRunningRelPaths([]);
      setRunningJob(null);
      await new Promise(r => setTimeout(r, 800));
      onRefresh();
    }
  };

  const handleBatchTranslateSelected = async () => {
    if (selectedRelPaths.length === 0) return;
    setRunningJob('batch_selected');
    setRunningRelPaths(prev => [...prev, ...selectedRelPaths]);
    try {
      for (const relPath of selectedRelPaths) {
        await runScript('main.py', ['translate', relPath], `batch_sel_${Date.now()}`);
      }
    } finally {
      setSelectedRelPaths([]);
      setRunningRelPaths([]);
      setRunningJob(null);
      await new Promise(r => setTimeout(r, 800));
      onRefresh();
    }
  };

  const handleBatchResumeSelected = async () => {
    if (selectedRelPaths.length === 0) return;
    setRunningJob('batch_resume');
    setRunningRelPaths(prev => [...prev, ...selectedRelPaths]);
    try {
      for (const relPath of selectedRelPaths) {
        const fileName = relPath.split('/').pop();
        const stem = getStem(fileName);
        const jobId = `job_${stem}`;
        await runScript('main.py', ['resume', `${project}:${jobId}`], `resume_sel_${Date.now()}`);
      }
    } finally {
      setSelectedRelPaths([]);
      setRunningRelPaths([]);
      setRunningJob(null);
      await new Promise(r => setTimeout(r, 800));
      onRefresh();
    }
  };

  const handleTranslate = async (videoRelPath) => {
    const stem = getStem(videoRelPath);
    setRunningRelPaths(prev => [...prev, videoRelPath, stem, `job_${stem}`]);
    setRunningJob(videoRelPath);
    try {
      await runScript('main.py', ['translate', videoRelPath], `trans_${Date.now()}`);
      setSelectedRelPaths(prev => prev.filter(p => p !== videoRelPath));
    } finally {
      setRunningRelPaths(prev => prev.filter(p => getStem(p) !== stem && p !== videoRelPath));
      setRunningJob(null);
      await new Promise(r => setTimeout(r, 800));
      onRefresh();
      loadActiveJobFiles();
    }
  };

  const handleTranslateOcr = async (videoRelPath) => {
    const stem = getStem(videoRelPath);
    setRunningRelPaths(prev => [...prev, videoRelPath, stem, `job_${stem}`]);
    setRunningJob(videoRelPath);
    try {
      await runScript('ocr_translator.py', [videoRelPath], `ocr_${Date.now()}`);
      setSelectedRelPaths(prev => prev.filter(p => p !== videoRelPath));
    } finally {
      setRunningRelPaths(prev => prev.filter(p => getStem(p) !== stem && p !== videoRelPath));
      setRunningJob(null);
      await new Promise(r => setTimeout(r, 800));
      onRefresh();
      loadActiveJobFiles();
    }
  };

  const handleResume = async (jobName) => {
    if (!project) return;
    const stem = getStem(jobName);
    const actualJobId = `job_${stem}`;

    setRunningRelPaths(prev => [...prev, jobName, stem, actualJobId]);
    setRunningJob(jobName);
    try {
      const targetArg = jobName.includes(':') || jobName.includes('/') ? jobName : `${project}:${actualJobId}`;
      await runScript('main.py', ['resume', targetArg], `resume_${Date.now()}`);
      setSelectedRelPaths(prev => prev.filter(p => p !== jobName && getStem(p) !== stem));
    } finally {
      setRunningRelPaths(prev => prev.filter(p => getStem(p) !== stem && p !== jobName));
      setRunningJob(null);
      await new Promise(r => setTimeout(r, 800));
      onRefresh();
      loadActiveJobFiles();
    }
  };

  const handleDeleteJob = async (jobId) => {
    if (!project) return;
    const cleanJobId = jobId.startsWith('job_') ? jobId : `job_${getStem(jobId)}`;
    const ok = await confirm({
      title: 'Xóa Job Workspace?',
      message: `Toàn bộ file cache của job "${cleanJobId}" trong project "${project}" sẽ bị xóa vĩnh viễn khỏi SSD!`,
      confirmText: 'Xóa Job',
      type: 'danger'
    });
    if (!ok) return;

    try {
      await deleteWorkspaceJob(project, cleanJobId);
      if (workspaceJobModal?.jobId === cleanJobId) {
        setWorkspaceJobModal(null);
      }
      onRefresh();
    } catch (err) {
      showAlert({ title: 'Lỗi Xóa Job', message: err.message, type: 'danger' });
    }
  };

  const handleDeleteStepCache = async (jobId, stepId) => {
    if (!project) return;
    const cleanJobId = jobId.startsWith('job_') ? jobId : `job_${getStem(jobId)}`;
    const ok = await confirm({
      title: `Xóa cache step "${stepId}"?`,
      message: `Hệ thống sẽ dọn dẹp file cache của step này trong job "${cleanJobId}" và TỰ ĐỘNG INVALIDATE tất cả các step phía sau phụ thuộc vào nó.\n\nSau khi xóa, bạn có thể bấm Resume để chạy lại từ step này!`,
      confirmText: 'Xóa Cache Step',
      type: 'warning'
    });
    if (!ok) return;

    try {
      await deleteStepCache(project, cleanJobId, stepId);
      const res = await fetchWorkspaceJobFiles(project, cleanJobId);
      setWorkspaceJobModal(res);
      onRefresh();
    } catch (err) {
      showAlert({ title: 'Lỗi Xóa Cache Step', message: err.message, type: 'danger' });
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
        onRefresh();
      }
    } catch (err) {
      showAlert({ title: 'Lỗi Đổi Tên File', message: err.message, type: 'danger' });
    }
  };

  const handleDeleteFile = async (file) => {
    if (!file || !file.name || !file.relPath) return;
    const ok = await confirm({
      title: 'Xác Nhận Xóa File',
      message: `Bạn có chắc chắn muốn xóa file "${file.name}" không?\n\nFile này sẽ bị xóa vĩnh viễn khỏi thư mục!`,
      confirmText: 'Xóa File',
      type: 'danger'
    });
    if (!ok) return;

    try {
      const res = await deleteFile(file.relPath);
      if (res.error) {
        showAlert({ title: 'Lỗi Xóa File', message: res.error, type: 'danger' });
      } else {
        setSelectedRelPaths(prev => prev.filter(p => p !== file.relPath));
        onRefresh();
      }
    } catch (err) {
      showAlert({ title: 'Lỗi Xóa File', message: err.message, type: 'danger' });
    }
  };

  const handleSaveTranslation = async () => {
    if (!translationRelPath || translationContent === null) return;
    setIsSavingTranslation(true);
    try {
      await saveFileContent(translationRelPath, translationContent);
      showAlert({
        title: 'Lưu Bản Dịch',
        message: 'Đã lưu file s08_translation.json thành công!\n\nNhấn "Resume Pipeline" để áp dụng câu dịch mới trong đúng 2 giây.',
        type: 'success'
      });
    } catch (e) {
      showAlert({ title: 'Lỗi Lưu Bản Dịch', message: e.message, type: 'danger' });
    } finally {
      setIsSavingTranslation(false);
    }
  };

  const handleSaveVideoConfig = async () => {
    if (!videoConfigRelPath) return;
    setIsSavingConfig(true);
    try {
      await saveFileContent(videoConfigRelPath, videoConfigContent);
      showAlert({
        title: 'Lưu Cấu Hình Video',
        message: 'Đã lưu config riêng cho video thành công!',
        type: 'success'
      });
    } catch (e) {
      showAlert({ title: 'Lỗi Lưu Config Video', message: e.message, type: 'danger' });
    } finally {
      setIsSavingConfig(false);
    }
  };

  return (
    <div style={styles.container}>
      {/* Header Bar */}
      <div style={styles.header}>
        <div>
          <h2 style={styles.title}>Dự Án: <span style={{ color: '#818cf8' }}>{project || 'Chưa chọn'}</span></h2>
          <p style={styles.subtitle}>Quản lý kho video, chạy pipeline AI Translator & tinh chỉnh kịch bản phụ đề</p>
        </div>

        <div style={{ display: 'flex', gap: 10, alignItems: 'center' }}>
          <button style={styles.btnSecondary} onClick={onRefresh} title="Làm mới danh sách">
            <RefreshCw size={16} style={{ marginRight: 6 }} /> Reload
          </button>

          <button style={styles.btnPrimary} onClick={handleBatchTranslate} disabled={srcFiles.length === 0}>
            <Wand2 size={16} style={{ marginRight: 6 }} /> Dịch Hàng Loạt Tất Cả ({srcFiles.length})
          </button>
        </div>
      </div>

      {/* 2-Column Studio Main Grid */}
      <div style={styles.mainGrid}>
        
        {/* LEFT COLUMN: KHO VIDEO DỰ ÁN (Gallery + Infinite Scroll) */}
        <div style={styles.cardLeft}>
          
          {/* Cloud Storage Mount Status & Global Actions */}
          <div style={{
            backgroundColor: 'rgba(15, 23, 42, 0.85)',
            border: '1px solid #334155',
            borderRadius: 10,
            padding: '8px 12px',
            marginBottom: 12,
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'space-between',
            gap: 10,
            flexWrap: 'wrap'
          }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 8, fontSize: 12 }}>
              <div style={{
                display: 'flex',
                alignItems: 'center',
                gap: 6,
                padding: '3px 8px',
                borderRadius: 6,
                backgroundColor: storageStatus?.connected ? 'rgba(16, 185, 129, 0.12)' : 'rgba(245, 158, 11, 0.12)',
                border: `1px solid ${storageStatus?.connected ? 'rgba(16, 185, 129, 0.3)' : 'rgba(245, 158, 11, 0.3)'}`,
                color: storageStatus?.connected ? '#34d399' : '#fbbf24',
                fontWeight: 600
              }}>
                <Cloud size={14} />
                <span>{storageStatus?.connected ? 'GCS Cloud (API)' : 'Mất Kết Nối'}</span>
              </div>
              {storageStatus?.connected && (
                <span style={{ fontSize: 11, color: '#94a3b8' }}>
                  {storageStatus.counts?.cloudOnly || 0} cloud · {storageStatus.counts?.synced || 0} sync · {storageStatus.counts?.localOnly || 0} local
                </span>
              )}
            </div>

            {/* Segmented Toolbar for Cloud Actions */}
            <div style={{
              display: 'flex',
              backgroundColor: 'rgba(30, 41, 59, 0.8)',
              border: '1px solid #334155',
              borderRadius: 7,
              padding: 2,
              gap: 2
            }}>
              <button
                onClick={() => handleSyncDownFiles()}
                disabled={isStorageBusy || !storageStatus?.connected}
                style={{
                  backgroundColor: 'transparent',
                  border: 'none',
                  color: (isStorageBusy || !storageStatus?.connected) ? '#475569' : '#93c5fd',
                  borderRadius: 5,
                  padding: '4px 8px',
                  fontSize: 11,
                  fontWeight: 600,
                  cursor: (isStorageBusy || !storageStatus?.connected) ? 'not-allowed' : 'pointer',
                  display: 'flex',
                  alignItems: 'center',
                  gap: 4
                }}
                title="Tải toàn bộ file trên cloud về máy để xử lý AI"
              >
                <CloudDownload size={12} /> Kéo Về
              </button>

              <button
                onClick={() => handleSyncUpFiles()}
                disabled={isStorageBusy || !storageStatus?.connected}
                style={{
                  backgroundColor: 'transparent',
                  border: 'none',
                  color: (isStorageBusy || !storageStatus?.connected) ? '#475569' : '#6ee7b7',
                  borderRadius: 5,
                  padding: '4px 8px',
                  fontSize: 11,
                  fontWeight: 600,
                  cursor: (isStorageBusy || !storageStatus?.connected) ? 'not-allowed' : 'pointer',
                  display: 'flex',
                  alignItems: 'center',
                  gap: 4
                }}
                title="Đẩy tất cả video kết quả và file src lên GCS"
              >
                <CloudUpload size={12} /> Đẩy Lên
              </button>

              <button
                onClick={() => handleOffloadFiles()}
                disabled={isStorageBusy || !storageStatus?.connected}
                style={{
                  backgroundColor: 'transparent',
                  border: 'none',
                  color: (isStorageBusy || !storageStatus?.connected) ? '#475569' : '#fca5a5',
                  borderRadius: 5,
                  padding: '4px 8px',
                  fontSize: 11,
                  fontWeight: 600,
                  cursor: (isStorageBusy || !storageStatus?.connected) ? 'not-allowed' : 'pointer',
                  display: 'flex',
                  alignItems: 'center',
                  gap: 4
                }}
                title="Xóa video local khi đã có bản sao an toàn trên cloud để giải phóng SSD"
              >
                <HardDrive size={12} /> Giải Phóng
              </button>

              <button
                onClick={handleRefreshCache}
                disabled={isRefreshingCache || !storageStatus?.connected}
                style={{
                  backgroundColor: 'transparent',
                  border: 'none',
                  color: (isRefreshingCache || !storageStatus?.connected) ? '#475569' : '#cbd5e1',
                  borderRadius: 5,
                  padding: '4px 8px',
                  fontSize: 11,
                  fontWeight: 600,
                  cursor: (isRefreshingCache || !storageStatus?.connected) ? 'not-allowed' : 'pointer',
                  display: 'flex',
                  alignItems: 'center',
                  gap: 4
                }}
                title="Làm mới bảng kê danh sách Cloud tức thì (Direct API Refresh)"
              >
                <RotateCcw size={12} style={{ animation: isRefreshingCache ? 'spin 1s linear infinite' : 'none' }} /> {isRefreshingCache ? '...' : 'Refresh'}
              </button>
            </div>
          </div>

          <div style={{ display: 'flex', flexDirection: 'column', gap: 10, marginBottom: 12 }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
              <h3 style={styles.cardTitle}>📁 Kho Video Dự Án ({allFiles.length})</h3>
              <select
                value={folderFilter}
                onChange={e => { setFolderFilter(e.target.value); setDisplayLimit(24); }}
                style={styles.folderSelect}
              >
                <option value="all">Tất cả kho ({allFiles.length} video)</option>
                <option value="src">Video Gốc (`src/`) ({srcFiles.length})</option>
                <option value="output">Video Kết Quả (`output/`) ({outputFiles.length})</option>
                <option value="cloud_only">☁️ Chỉ Trên Cloud ({storageStatus?.counts?.cloudOnly || 0})</option>
                <option value="synced">🔄 Đã Đồng Bộ ({storageStatus?.counts?.synced || 0})</option>
              </select>
            </div>

            <div style={{ position: 'relative' }}>
              <input
                type="text"
                placeholder="🔍 Tìm nhanh tên video..."
                value={searchQuery}
                onChange={e => setSearchQuery(e.target.value)}
                style={styles.searchInput}
              />
            </div>
          </div>

          {/* Sticky Multi-Select Batch Actions Bar inside Left Gallery */}
          {selectedRelPaths.length > 0 && (
            <div style={{
              backgroundColor: '#0f172a',
              borderRadius: 8,
              padding: '8px 12px',
              marginBottom: 12,
              border: '1px solid rgba(99, 102, 241, 0.4)',
              display: 'flex',
              justifyContent: 'space-between',
              alignItems: 'center',
              flexWrap: 'wrap',
              gap: 8
            }}>
              <button style={styles.btnBatchSelectAll} onClick={handleSelectAll}>
                <CheckSquare size={13} style={{ marginRight: 4 }} />
                Đã chọn: <strong style={{ color: '#fff', marginLeft: 3 }}>{selectedRelPaths.length}</strong>/{filteredFiles.length} (Bỏ chọn)
              </button>

              <div style={{ display: 'flex', alignItems: 'center', gap: 8, flexWrap: 'wrap' }}>
                {/* AI Group */}
                <div style={{ display: 'flex', gap: 4 }}>
                  <button style={styles.btnBatchActionPrimary} onClick={handleBatchTranslateSelected}>
                    <Play size={12} style={{ marginRight: 4 }} /> Dịch ({selectedRelPaths.length})
                  </button>

                  <button style={styles.btnBatchActionWarning} onClick={handleBatchResumeSelected}>
                    <RotateCcw size={12} style={{ marginRight: 4 }} /> Resume ({selectedRelPaths.length})
                  </button>
                </div>

                {/* Subtle Divider */}
                <div style={{ width: 1, height: 18, backgroundColor: '#334155' }} />

                {/* Cloud & Storage Segmented Group */}
                <div style={{
                  display: 'flex',
                  backgroundColor: '#1e293b',
                  border: '1px solid #334155',
                  borderRadius: 6,
                  padding: 2,
                  gap: 2
                }}>
                  <button
                    onClick={() => handleSyncDownFiles(selectedRelPaths)}
                    disabled={isStorageBusy}
                    style={{
                      backgroundColor: 'transparent',
                      border: 'none',
                      color: isStorageBusy ? '#475569' : '#93c5fd',
                      borderRadius: 4,
                      padding: '3px 8px',
                      fontSize: 11,
                      fontWeight: 600,
                      cursor: isStorageBusy ? 'not-allowed' : 'pointer',
                      display: 'flex',
                      alignItems: 'center',
                      gap: 4
                    }}
                    title="Tải các video đã chọn về máy"
                  >
                    <CloudDownload size={12} /> Tải Về
                  </button>

                  <button
                    onClick={() => handleSyncUpFiles(selectedRelPaths)}
                    disabled={isStorageBusy}
                    style={{
                      backgroundColor: 'transparent',
                      border: 'none',
                      color: isStorageBusy ? '#475569' : '#6ee7b7',
                      borderRadius: 4,
                      padding: '3px 8px',
                      fontSize: 11,
                      fontWeight: 600,
                      cursor: isStorageBusy ? 'not-allowed' : 'pointer',
                      display: 'flex',
                      alignItems: 'center',
                      gap: 4
                    }}
                    title="Đẩy các video đã chọn lên Cloud"
                  >
                    <CloudUpload size={12} /> Đẩy Lên
                  </button>

                  <button
                    onClick={() => handleOffloadFiles(selectedRelPaths)}
                    disabled={isStorageBusy}
                    style={{
                      backgroundColor: 'transparent',
                      border: 'none',
                      color: isStorageBusy ? '#475569' : '#fca5a5',
                      borderRadius: 4,
                      padding: '3px 8px',
                      fontSize: 11,
                      fontWeight: 600,
                      cursor: isStorageBusy ? 'not-allowed' : 'pointer',
                      display: 'flex',
                      alignItems: 'center',
                      gap: 4
                    }}
                    title="Giải phóng dung lượng SSD cho các video đã chọn"
                  >
                    <HardDrive size={12} /> Offload
                  </button>
                </div>
              </div>
            </div>
          )}

          {/* Video Cards 2-column Grid with Auto Infinite Scroll */}
          <div ref={galleryScrollRef} style={styles.galleryScrollContainer}>
            {visibleFiles.length === 0 ? (
              <div style={styles.emptyState}>Không tìm thấy video nào trong kho</div>
            ) : (
              <div style={styles.compactGrid}>
                {visibleFiles.map(file => (
                  <CompactVideoCard
                    key={file.relPath}
                    file={file}
                    isActivePreview={activeSelectedFile?.relPath === file.relPath}
                    isSelected={selectedRelPaths.includes(file.relPath)}
                    disabled={isFileProcessing(file)}
                    onSelect={() => { if (!isFileProcessing(file)) handleSelectFile(file); }}
                    onToggleCheck={() => { if (!isFileProcessing(file)) handleToggleSelect(file.relPath); }}
                    actionLabel={
                      isFileProcessing(file)
                        ? '⚙️ Đang dịch...'
                        : file.isCloudOnly
                          ? '⬇️ Tải về máy'
                          : activeSelectedFile?.relPath === file.relPath
                            ? '► Đang chọn'
                            : '► Chọn video'
                    }
                    onAction={() => {
                      if (file.isCloudOnly) {
                        handleSyncDownFiles([file.relPath || file.name]);
                      } else if (!isFileProcessing(file)) {
                        handleSelectFile(file);
                      }
                    }}
                  />
                ))}
              </div>
            )}

            {/* Auto Infinite Scroll Sentinel & Load More Fallback */}
            {displayLimit < filteredFiles.length && (
              <div ref={sentinelRef} style={styles.sentinel}>
                <button
                  type="button"
                  onClick={() => setDisplayLimit(prev => Math.min(prev + 24, filteredFiles.length))}
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
                  <span>⏳ Tự động tải thêm ({visibleFiles.length}/{filteredFiles.length})</span>
                  <span style={{ color: '#818cf8', fontWeight: 'bold' }}>• Bấm để tải ngay</span>
                </button>
              </div>
            )}
          </div>
        </div>

        {/* RIGHT COLUMN: PREVIEW + PIPELINE WORKSPACE */}
        <div style={styles.cardRight}>
          
          {/* 1. Hero Large Video Player Preview */}
          <div style={styles.previewSection}>
            <div style={styles.previewHeader}>
              <span style={{ fontWeight: 'bold', fontSize: 14, color: '#f8fafc' }}>
                Xem Trước: <span style={{ color: '#818cf8' }}>{activeSelectedFile ? activeSelectedFile.name : 'Chưa chọn video'}</span>
              </span>
              {activeSelectedFile?.cloudStatus && (
                <span style={{
                  fontSize: 11,
                  fontWeight: 600,
                  color: activeSelectedFile.cloudStatus === 'synced' ? '#34d399' : activeSelectedFile.cloudStatus === 'cloud_only' ? '#60a5fa' : '#fbbf24',
                  backgroundColor: '#0f172a',
                  padding: '2px 8px',
                  borderRadius: 4,
                  border: '1px solid #334155'
                }}>
                  {activeSelectedFile.cloudStatus === 'synced' ? '🔄 Đã Đồng Bộ GCS' : activeSelectedFile.cloudStatus === 'cloud_only' ? '☁️ Chỉ Có Trên GCS' : '💻 Chỉ Có Ở Local SSD'}
                </span>
              )}
            </div>

            {activeSelectedFile ? (
              <div style={styles.playerWrapper}>
                {activeSelectedFile.isCloudOnly ? (
                  <div style={{
                    display: 'flex',
                    flexDirection: 'column',
                    alignItems: 'center',
                    justifyContent: 'center',
                    height: 240,
                    backgroundColor: '#0f172a',
                    borderRadius: 8,
                    gap: 12,
                    color: '#94a3b8'
                  }}>
                    <Cloud size={48} color="#60a5fa" />
                    <div style={{ textAlign: 'center' }}>
                      <p style={{ fontWeight: 600, color: '#f8fafc', marginBottom: 4 }}>Video này đang lưu trên GCS Cloud (0 Byte SSD Local)</p>
                      <p style={{ fontSize: 12 }}>Tải video về máy Mac để xem trước và thực hiện dịch AI</p>
                    </div>
                    <button
                      onClick={() => handleSyncDownFiles([activeSelectedFile.relPath || activeSelectedFile.name])}
                      disabled={isStorageBusy}
                      style={{
                        backgroundColor: '#2563eb',
                        color: '#ffffff',
                        border: 'none',
                        borderRadius: 8,
                        padding: '8px 16px',
                        fontSize: 13,
                        fontWeight: 700,
                        cursor: 'pointer',
                        display: 'flex',
                        alignItems: 'center',
                        gap: 6
                      }}
                    >
                      <CloudDownload size={16} /> Tải Về Máy Ngay
                    </button>
                  </div>
                ) : (
                  <video
                    key={activeSelectedFile.relPath}
                    src={getMediaUrl(activeSelectedFile.relPath)}
                    controls
                    style={styles.videoPlayer}
                  />
                )}
              </div>
            ) : (
              <div style={styles.emptyPlayer}>Tích chọn một video bên trái để xem trước</div>
            )}
          </div>

          {/* 2. Interactive Quick Action Buttons */}
          {activeSelectedFile && (
            <div style={{
              backgroundColor: '#0f172a',
              borderRadius: 10,
              padding: '10px 12px',
              border: '1px solid #334155',
              display: 'flex',
              flexDirection: 'column',
              gap: 8
            }}>
              {activeSelectedFile.isCloudOnly ? (
                <button
                  style={{
                    backgroundColor: '#2563eb',
                    color: '#ffffff',
                    border: 'none',
                    borderRadius: 8,
                    padding: '10px 16px',
                    fontSize: 13,
                    fontWeight: 700,
                    cursor: isStorageBusy ? 'not-allowed' : 'pointer',
                    display: 'flex',
                    alignItems: 'center',
                    justifyContent: 'center',
                    gap: 8,
                    boxShadow: '0 2px 8px rgba(37, 99, 235, 0.4)'
                  }}
                  onClick={() => handleSyncDownFiles([activeSelectedFile.relPath || activeSelectedFile.name])}
                  disabled={isStorageBusy}
                >
                  <CloudDownload size={16} /> Tải Video Về Máy để Dịch AI
                </button>
              ) : (
                <>
                  {/* Row 1: AI Pipeline Core Actions (Prominent & High Visual Priority) */}
                  <div style={{
                    display: 'grid',
                    gridTemplateColumns: '1fr 1fr auto',
                    gap: 8
                  }}>
                    <button
                      style={{
                        background: 'linear-gradient(135deg, #6366f1 0%, #4f46e5 100%)',
                        color: '#ffffff',
                        border: 'none',
                        borderRadius: 8,
                        padding: '8px 12px',
                        fontSize: 12,
                        fontWeight: 700,
                        cursor: isFileProcessing(activeSelectedFile) ? 'not-allowed' : 'pointer',
                        display: 'flex',
                        alignItems: 'center',
                        justifyContent: 'center',
                        gap: 6,
                        boxShadow: '0 2px 6px rgba(99, 102, 241, 0.35)',
                        opacity: isFileProcessing(activeSelectedFile) ? 0.6 : 1
                      }}
                      onClick={() => handleTranslate(activeSelectedFile.relPath)}
                      disabled={isFileProcessing(activeSelectedFile)}
                      title="Dịch thuyết minh giọng đọc AI (ASR + EdgeTTS)"
                    >
                      <Play size={14} /> Dịch Thuyết Minh
                    </button>

                    <button
                      style={{
                        background: 'linear-gradient(135deg, #059669 0%, #047857 100%)',
                        color: '#ffffff',
                        border: 'none',
                        borderRadius: 8,
                        padding: '8px 12px',
                        fontSize: 12,
                        fontWeight: 700,
                        cursor: isFileProcessing(activeSelectedFile) ? 'not-allowed' : 'pointer',
                        display: 'flex',
                        alignItems: 'center',
                        justifyContent: 'center',
                        gap: 6,
                        boxShadow: '0 2px 6px rgba(5, 150, 105, 0.35)',
                        opacity: isFileProcessing(activeSelectedFile) ? 0.6 : 1
                      }}
                      onClick={() => handleTranslateOcr(activeSelectedFile.relPath)}
                      disabled={isFileProcessing(activeSelectedFile)}
                      title="Dịch sub cứng siêu tốc bằng Fast OCR"
                    >
                      <Wand2 size={14} /> Dịch Sub Fast OCR
                    </button>

                    <button
                      style={{
                        backgroundColor: '#334155',
                        border: '1px solid #475569',
                        color: '#f59e0b',
                        borderRadius: 8,
                        padding: '8px 14px',
                        fontSize: 12,
                        fontWeight: 700,
                        cursor: isFileProcessing(activeSelectedFile) ? 'not-allowed' : 'pointer',
                        display: 'flex',
                        alignItems: 'center',
                        justifyContent: 'center',
                        gap: 6,
                        opacity: isFileProcessing(activeSelectedFile) ? 0.6 : 1
                      }}
                      onClick={() => handleResume(activeSelectedFile.name)}
                      disabled={isFileProcessing(activeSelectedFile)}
                      title="Chạy tiếp quy trình hoặc áp dụng câu thoại mới từ s08_translation.json"
                    >
                      <RotateCcw size={14} /> Resume
                    </button>
                  </div>

                  {/* Row 2: Secondary Utilities (Cloud Storage & Video Tools) */}
                  <div style={{
                    display: 'flex',
                    justifyContent: 'space-between',
                    alignItems: 'center',
                    flexWrap: 'wrap',
                    gap: 8,
                    paddingTop: 4,
                    borderTop: '1px solid rgba(51, 65, 85, 0.5)'
                  }}>
                    {/* Cloud Storage Sub-Group */}
                    <div style={{
                      display: 'flex',
                      backgroundColor: 'rgba(30, 41, 59, 0.6)',
                      border: '1px solid #334155',
                      borderRadius: 6,
                      padding: 2,
                      gap: 2
                    }}>
                      <button
                        style={{
                          backgroundColor: 'transparent',
                          border: 'none',
                          color: (isStorageBusy || activeSelectedFile.isCloudOnly) ? '#475569' : '#60a5fa',
                          borderRadius: 4,
                          padding: '4px 8px',
                          fontSize: 11,
                          fontWeight: 600,
                          cursor: (isStorageBusy || activeSelectedFile.isCloudOnly) ? 'not-allowed' : 'pointer',
                          display: 'flex',
                          alignItems: 'center',
                          gap: 4
                        }}
                        onClick={() => handleSyncUpFiles([activeSelectedFile.relPath || activeSelectedFile.name])}
                        disabled={isStorageBusy || activeSelectedFile.isCloudOnly}
                        title="Đẩy video này lên GCS Cloud"
                      >
                        <CloudUpload size={12} /> Sync Cloud
                      </button>

                      <button
                        style={{
                          backgroundColor: 'transparent',
                          border: 'none',
                          color: (isStorageBusy || activeSelectedFile.isCloudOnly) ? '#475569' : '#f87171',
                          borderRadius: 4,
                          padding: '4px 8px',
                          fontSize: 11,
                          fontWeight: 600,
                          cursor: (isStorageBusy || activeSelectedFile.isCloudOnly) ? 'not-allowed' : 'pointer',
                          display: 'flex',
                          alignItems: 'center',
                          gap: 4
                        }}
                        onClick={() => handleOffloadFiles([activeSelectedFile.relPath || activeSelectedFile.name])}
                        disabled={isStorageBusy || activeSelectedFile.isCloudOnly}
                        title="Xoá bản copy local sau khi đã an toàn trên Cloud để giải phóng SSD"
                      >
                        <HardDrive size={12} /> Giải Phóng SSD
                      </button>
                    </div>

                    {/* Video File Utilities Sub-Group */}
                    <div style={{
                      display: 'flex',
                      backgroundColor: 'rgba(30, 41, 59, 0.6)',
                      border: '1px solid #334155',
                      borderRadius: 6,
                      padding: 2,
                      gap: 2
                    }}>
                      <button
                        style={{
                          backgroundColor: 'transparent',
                          border: 'none',
                          color: '#cbd5e1',
                          borderRadius: 4,
                          padding: '4px 8px',
                          fontSize: 11,
                          fontWeight: 600,
                          cursor: 'pointer',
                          display: 'flex',
                          alignItems: 'center',
                          gap: 4
                        }}
                        onClick={() => onOpenTrimmer(activeSelectedFile.relPath)}
                        title="Mở thanh cắt video nhanh (Trimmer)"
                      >
                        <Scissors size={12} /> Cắt
                      </button>

                      <button
                        style={{
                          backgroundColor: 'transparent',
                          border: 'none',
                          color: '#cbd5e1',
                          borderRadius: 4,
                          padding: '4px 8px',
                          fontSize: 11,
                          fontWeight: 600,
                          cursor: 'pointer',
                          display: 'flex',
                          alignItems: 'center',
                          gap: 4
                        }}
                        onClick={() => handleRenameFile(activeSelectedFile)}
                        title="Đổi tên video"
                      >
                        <Pencil size={12} /> Đổi Tên
                      </button>

                      <button
                        style={{
                          backgroundColor: 'transparent',
                          border: 'none',
                          color: '#f87171',
                          borderRadius: 4,
                          padding: '4px 8px',
                          fontSize: 11,
                          fontWeight: 600,
                          cursor: 'pointer',
                          display: 'flex',
                          alignItems: 'center',
                          gap: 4
                        }}
                        onClick={() => handleDeleteFile(activeSelectedFile)}
                        title="Xóa video khỏi dự án"
                      >
                        <Trash2 size={12} /> Xóa
                      </button>
                    </div>
                  </div>
                </>
              )}
            </div>
          )}

          {/* 3. Section Sửa File Translation s08_translation.json */}
          {activeJobId && (
            <div style={styles.editorSection}>
              <div
                style={styles.accordionHeader}
                onClick={() => setShowTranslationEditor(!showTranslationEditor)}
              >
                <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
                  <FileText size={15} color="#818cf8" />
                  <span style={{ fontWeight: 'bold', fontSize: 13, color: '#f8fafc' }}>
                    📝 Tinh Chỉnh Bản Dịch Sub (`s08_translation.json`)
                  </span>
                </div>
                <span style={{ fontSize: 11, color: '#94a3b8' }}>
                  {showTranslationEditor ? '▼ Thu gọn' : '▶ Mở rộng'}
                </span>
              </div>

              {showTranslationEditor && (
                <div style={styles.editorBody}>
                  {translationContent !== null ? (
                    <>
                      <textarea
                        value={translationContent}
                        onChange={e => setTranslationContent(e.target.value)}
                        style={styles.codeTextarea}
                        rows={7}
                      />
                      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginTop: 8 }}>
                        <span style={{ fontSize: 11, color: '#94a3b8' }}>
                          Sửa text dịch trực tiếp ➔ Lưu ➔ Nhấn Resume để áp dụng sub mới ngay lập tức
                        </span>
                        <button style={styles.btnSaveConfig} onClick={handleSaveTranslation} disabled={isSavingTranslation}>
                          <Check size={14} style={{ marginRight: 4 }} /> {isSavingTranslation ? 'Đang lưu...' : 'Lưu Bản Dịch'}
                        </button>
                      </div>
                    </>
                  ) : (
                    <div style={{ fontSize: 12, color: '#64748b' }}>Chưa có file s08_translation.json cho job này (Chạy Dịch trước để sinh file)</div>
                  )}
                </div>
              )}
            </div>
          )}

          {/* 4. Section Per-Video Config Override */}
          {activeSelectedFile && (
            <div style={styles.editorSection}>
              <div
                style={styles.accordionHeader}
                onClick={() => setShowConfigOverride(!showConfigOverride)}
              >
                <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
                  <Settings size={15} color="#818cf8" />
                  <span style={{ fontWeight: 'bold', fontSize: 13, color: '#f8fafc' }}>
                    ⚙️ Tinh Chỉnh Config Riêng Cho Video (`video_config.yaml`)
                  </span>
                </div>
                <span style={{ fontSize: 11, color: '#94a3b8' }}>
                  {showConfigOverride ? '▼ Thu gọn' : '▶ Mở rộng'}
                </span>
              </div>

              {showConfigOverride && (
                <div style={styles.editorBody}>
                  <textarea
                    value={videoConfigContent}
                    onChange={e => setVideoConfigContent(e.target.value)}
                    placeholder="# Override config.yaml cho video này&#10;ocr_only: true&#10;music_volume: 0.3"
                    style={styles.codeTextarea}
                    rows={5}
                  />
                  <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginTop: 8 }}>
                    <span style={{ fontSize: 11, color: '#94a3b8' }}>Config này sẽ được ưu tiên override khi chạy video này</span>
                    <button style={styles.btnSaveConfig} onClick={handleSaveVideoConfig} disabled={isSavingConfig}>
                      <Check size={14} style={{ marginRight: 4 }} /> {isSavingConfig ? 'Đang lưu...' : 'Lưu Config'}
                    </button>
                  </div>
                </div>
              )}
            </div>
          )}

          {/* 5. Section Tiến Độ & Cache Job của Video Đang Chọn */}
          {activeSelectedFile && (
            <div style={styles.editorSection}>
              <div
                style={styles.accordionHeader}
                onClick={() => setShowWorkspaceJobs(!showWorkspaceJobs)}
              >
                <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
                  <FolderOpen size={15} color="#818cf8" />
                  <span style={{ fontWeight: 'bold', fontSize: 13, color: '#f8fafc' }}>
                    📂 Tiến Độ & Cache Job: <span style={{ color: '#818cf8' }}>job_{getStem(activeSelectedFile.name)}</span>
                  </span>
                </div>
                <span style={{ fontSize: 11, color: '#94a3b8' }}>
                  {showWorkspaceJobs ? '▼ Thu gọn' : '▶ Mở rộng'}
                </span>
              </div>

              {showWorkspaceJobs && (
                <div style={{ padding: 12, display: 'flex', flexDirection: 'column', gap: 10 }}>
                  {/* Status header bar */}
                  <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', backgroundColor: '#0f172a', padding: '8px 12px', borderRadius: 8, border: '1px solid #334155' }}>
                    <div style={{ fontSize: 12, color: '#f8fafc', fontWeight: 'bold', display: 'flex', alignItems: 'center', gap: 6 }}>
                      <span>📁 job_{getStem(activeSelectedFile.name)}</span>
                      {activeJobFiles.length > 0 ? (
                        <span style={{ backgroundColor: '#10b981', color: '#fff', fontSize: 10, padding: '1px 6px', borderRadius: 4, fontWeight: 700 }}>
                          🟢 {activeJobFiles.length} files cache
                        </span>
                      ) : (
                        <span style={{ backgroundColor: '#475569', color: '#fff', fontSize: 10, padding: '1px 6px', borderRadius: 4, fontWeight: 700 }}>
                          ⚪ Chưa có cache
                        </span>
                      )}
                    </div>

                    <div style={{ display: 'flex', gap: 6 }}>
                      {activeJobFiles.length > 0 && (
                        <>
                          <button
                            style={{
                              backgroundColor: '#334155',
                              color: '#94a3b8',
                              border: 'none',
                              borderRadius: 6,
                              padding: '4px 8px',
                              fontSize: 11,
                              cursor: 'pointer'
                            }}
                            onClick={() => setWorkspaceJobModal({ jobId: `job_${getStem(activeSelectedFile.name)}`, files: activeJobFiles })}
                          >
                            🔍 Chi tiết files
                          </button>

                          <button
                            style={{
                              backgroundColor: 'rgba(239, 68, 68, 0.2)',
                              color: '#ef4444',
                              border: '1px solid rgba(239, 68, 68, 0.3)',
                              borderRadius: 6,
                              padding: '4px 8px',
                              fontSize: 11,
                              fontWeight: 'bold',
                              cursor: 'pointer',
                              display: 'flex',
                              alignItems: 'center'
                            }}
                            onClick={() => handleDeleteJob(`job_${getStem(activeSelectedFile.name)}`)}
                          >
                            <Trash2 size={11} style={{ marginRight: 3 }} /> Xóa Toàn Bộ Job
                          </button>
                        </>
                      )}
                    </div>
                  </div>

                  {/* 15 Steps Grid with Individual Step Delete Buttons */}
                  <div style={{ display: 'grid', gridTemplateColumns: 'repeat(2, minmax(0, 1fr))', gap: 6, maxHeight: 250, overflowY: 'auto', paddingRight: 2 }}>
                    {PIPELINE_STEPS.map(step => {
                      // Find matching cached file for this step
                      const targetFile = activeJobFiles.find(f => {
                        const fname = (f.name || f.relPath || '').toLowerCase();
                        if (step.id === 's01_probe') return fname.includes('s01') || fname.includes('state.json');
                        if (step.id === 's02_demux') return fname.includes('video_stream') || fname.includes('audio_stream');
                        if (step.id === 's03_subtitle_detect') return fname.includes('s03') || fname.includes('burnin');
                        if (step.id === 's04_audio_separate') return fname.includes('voice.wav');
                        if (step.id === 's05_asr') return fname.includes('s05_asr');
                        if (step.id === 's05b_gender_detect') return fname.includes('s05b_gender');
                        if (step.id === 's06_ocr') return fname.includes('s06_ocr');
                        if (step.id === 's07_transcript_merge') return fname.includes('s07_transcript');
                        if (step.id === 's08_translation') return fname.includes('s08_translation');
                        if (step.id === 's08b_metadata_gen') return fname.includes('s08b_metadata');
                        if (step.id === 's08c_timing') return fname.includes('s08c_timing');
                        if (step.id === 's09_subtitle_gen') return fname.includes('subtitles_vi.ass') || fname.includes('subtitles.srt');
                        if (step.id === 's10_inpaint') return fname.includes('clean_video');
                        if (step.id === 's11_subtitle_render') return fname.includes('rendered_video');
                        if (step.id === 's12_tts') return fname.includes('tts_audio');
                        if (step.id === 's13_audio_mix') return fname.includes('mixed_audio');
                        if (step.id === 's14_encode') return fname.includes('output');
                        return fname.includes(step.id);
                      });

                      const isCached = !!targetFile || activeJobFiles.some(f => (f.name || '').toLowerCase().includes(step.id));

                      return (
                        <div
                          key={step.id}
                          style={{
                            backgroundColor: isCached ? 'rgba(16, 185, 129, 0.12)' : '#0f172a',
                            border: isCached ? '1px solid rgba(16, 185, 129, 0.4)' : '1px solid #334155',
                            borderRadius: 8,
                            padding: '7px 10px',
                            display: 'flex',
                            justifyContent: 'space-between',
                            alignItems: 'center',
                            gap: 6
                          }}
                        >
                          <div style={{ display: 'flex', flexDirection: 'column', gap: 2, minWidth: 0, flex: 1 }}>
                            <span style={{ fontSize: 11, fontWeight: 'bold', color: isCached ? '#34d399' : '#94a3b8' }}>
                              {step.label}
                            </span>
                            {targetFile ? (
                              <span 
                                style={{ 
                                  fontSize: 10, 
                                  color: '#a7f3d0', 
                                  fontFamily: 'monospace',
                                  overflow: 'hidden',
                                  textOverflow: 'ellipsis',
                                  whiteSpace: 'nowrap'
                                }}
                                title={`${targetFile.basename || targetFile.name} (${formatSizeStr(targetFile.sizeBytes)})`}
                              >
                                📄 {targetFile.basename || targetFile.name} ({formatSizeStr(targetFile.sizeBytes)})
                              </span>
                            ) : (
                              <span style={{ fontSize: 10, color: isCached ? '#10b981' : '#475569' }}>
                                {isCached ? '🟢 Cached' : '⚪ Chưa chạy'}
                              </span>
                            )}
                          </div>

                          {isCached && (
                            <button
                              title={`Xóa cache bước ${step.id} và các bước phía sau`}
                              style={{
                                backgroundColor: 'rgba(239, 68, 68, 0.15)',
                                color: '#ef4444',
                                border: '1px solid rgba(239, 68, 68, 0.3)',
                                borderRadius: 4,
                                padding: '3px 6px',
                                fontSize: 10,
                                cursor: 'pointer',
                                display: 'flex',
                                alignItems: 'center',
                                flexShrink: 0
                              }}
                              onClick={() => handleDeleteStepCache(`job_${getStem(activeSelectedFile.name)}`, step.id)}
                            >
                              <Trash2 size={10} style={{ marginRight: 2 }} /> Xóa Step
                            </button>
                          )}
                        </div>
                      );
                    })}
                  </div>
                </div>
              )}
            </div>
          )}

          {/* 6. Terminal Realtime Logs Inline Panel */}
          <div style={styles.inlineTerminalSection}>
            <LogConsole
              logs={globalLogs}
              onClearLogs={onClearLogs}
              activeJobId={activeJobId || 'global'}
              isProcessRunning={runningRelPaths.length > 0}
              compact={true}
            />
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
    boxSizing: 'border-box',
    height: '100vh',
    display: 'flex',
    flexDirection: 'column'
  },
  header: {
    display: 'flex',
    justifyContent: 'space-between',
    alignItems: 'center',
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
  btnPrimary: {
    backgroundColor: '#6366f1',
    color: '#fff',
    border: 'none',
    padding: '8px 16px',
    borderRadius: 8,
    cursor: 'pointer',
    fontWeight: 'bold',
    display: 'flex',
    alignItems: 'center',
    fontSize: 13
  },
  btnSecondary: {
    backgroundColor: '#1e293b',
    color: '#94a3b8',
    border: '1px solid #334155',
    padding: '8px 14px',
    borderRadius: 8,
    cursor: 'pointer',
    fontSize: 13,
    display: 'flex',
    alignItems: 'center'
  },
  mainGrid: {
    display: 'grid',
    gridTemplateColumns: '1fr 1fr',
    gap: 20,
    flex: 1,
    minHeight: 0
  },
  cardLeft: {
    backgroundColor: '#1e293b',
    borderRadius: 12,
    padding: 16,
    border: '1px solid #334155',
    display: 'flex',
    flexDirection: 'column',
    overflow: 'hidden'
  },
  cardRight: {
    backgroundColor: '#1e293b',
    borderRadius: 12,
    padding: 16,
    border: '1px solid #334155',
    display: 'flex',
    flexDirection: 'column',
    gap: 14,
    overflowY: 'auto'
  },
  cardTitle: {
    fontSize: 15,
    fontWeight: 'bold',
    margin: 0,
    color: '#f8fafc'
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
  batchBar: {
    backgroundColor: '#0f172a',
    borderRadius: 8,
    padding: '8px 12px',
    marginBottom: 12,
    border: '1px solid #6366f1',
    display: 'flex',
    justifyContent: 'space-between',
    alignItems: 'center'
  },
  btnBatchSelectAll: {
    backgroundColor: '#334155',
    color: '#94a3b8',
    border: 'none',
    borderRadius: 6,
    padding: '4px 8px',
    fontSize: 11,
    cursor: 'pointer',
    display: 'flex',
    alignItems: 'center'
  },
  btnBatchActionPrimary: {
    backgroundColor: '#6366f1',
    color: '#ffffff',
    border: 'none',
    borderRadius: 6,
    padding: '4px 10px',
    fontSize: 11,
    fontWeight: 'bold',
    cursor: 'pointer',
    display: 'flex',
    alignItems: 'center'
  },
  btnBatchActionWarning: {
    backgroundColor: '#d97706',
    color: '#ffffff',
    border: 'none',
    borderRadius: 6,
    padding: '4px 10px',
    fontSize: 11,
    fontWeight: 'bold',
    cursor: 'pointer',
    display: 'flex',
    alignItems: 'center'
  },
  galleryScrollContainer: {
    flex: 1,
    overflowY: 'auto',
    paddingRight: 4
  },
  compactGrid: {
    display: 'grid',
    gridTemplateColumns: 'repeat(2, minmax(0, 1fr))',
    gap: 10
  },
  sentinel: {
    padding: '12px 0',
    textAlign: 'center'
  },
  emptyState: {
    color: '#64748b',
    textAlign: 'center',
    padding: 30,
    fontSize: 13
  },
  heroSection: {
    backgroundColor: '#0f172a',
    borderRadius: 10,
    padding: 12,
    border: '1px solid #334155'
  },
  sectionHeader: {
    display: 'flex',
    alignItems: 'center',
    marginBottom: 10
  },
  playerWrapper: {
    width: '100%',
    maxHeight: 320,
    backgroundColor: '#000',
    borderRadius: 8,
    overflow: 'hidden',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center'
  },
  videoPlayer: {
    width: '100%',
    maxHeight: 320,
    objectFit: 'contain'
  },
  emptyPlayer: {
    height: 180,
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    color: '#475569',
    fontSize: 13,
    fontStyle: 'italic'
  },
  actionsCard: {
    backgroundColor: '#0f172a',
    borderRadius: 10,
    padding: 12,
    border: '1px solid #334155'
  },
  btnActionPrimary: {
    backgroundColor: '#6366f1',
    color: '#fff',
    border: 'none',
    padding: '7px 12px',
    borderRadius: 6,
    fontSize: 12,
    fontWeight: 'bold',
    cursor: 'pointer',
    display: 'flex',
    alignItems: 'center'
  },
  btnActionOcr: {
    backgroundColor: '#059669',
    color: '#fff',
    border: 'none',
    padding: '7px 12px',
    borderRadius: 6,
    fontSize: 12,
    fontWeight: 'bold',
    cursor: 'pointer',
    display: 'flex',
    alignItems: 'center'
  },
  btnActionWarning: {
    backgroundColor: '#d97706',
    color: '#fff',
    border: 'none',
    padding: '7px 12px',
    borderRadius: 6,
    fontSize: 12,
    fontWeight: 'bold',
    cursor: 'pointer',
    display: 'flex',
    alignItems: 'center'
  },
  btnActionSecondary: {
    backgroundColor: '#334155',
    color: '#f8fafc',
    border: '1px solid #475569',
    padding: '7px 12px',
    borderRadius: 6,
    fontSize: 12,
    fontWeight: 'bold',
    cursor: 'pointer',
    display: 'flex',
    alignItems: 'center'
  },
  btnActionDanger: {
    backgroundColor: 'rgba(239, 68, 68, 0.15)',
    color: '#f87171',
    border: '1px solid rgba(239, 68, 68, 0.4)',
    padding: '7px 12px',
    borderRadius: 6,
    fontSize: 12,
    fontWeight: 'bold',
    cursor: 'pointer',
    display: 'flex',
    alignItems: 'center'
  },
  editorSection: {
    backgroundColor: '#0f172a',
    borderRadius: 10,
    padding: 12,
    border: '1px solid #334155'
  },
  accordionHeader: {
    display: 'flex',
    justifyContent: 'space-between',
    alignItems: 'center',
    cursor: 'pointer',
    userSelect: 'none'
  },
  editorBody: {
    paddingTop: 10
  },
  codeTextarea: {
    width: '100%',
    backgroundColor: 'var(--bg-input)',
    color: 'var(--text-main)',
    border: '1px solid var(--border-color)',
    borderRadius: 6,
    padding: 10,
    fontFamily: '"Fira Code", monospace',
    fontSize: 12,
    lineHeight: 1.5,
    outline: 'none',
    boxSizing: 'border-box',
    resize: 'vertical'
  },
  btnSaveConfig: {
    backgroundColor: '#10b981',
    color: '#ffffff',
    border: 'none',
    borderRadius: 6,
    padding: '5px 12px',
    fontSize: 11,
    fontWeight: 'bold',
    cursor: 'pointer',
    display: 'flex',
    alignItems: 'center'
  },
  inlineTerminalSection: {
    height: 260,
    minHeight: 260,
    backgroundColor: 'var(--bg-card)',
    borderRadius: 10,
    overflow: 'hidden',
    border: '1px solid var(--border-color)'
  }
};
