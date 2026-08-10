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
  ChevronRight
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
  deleteFile 
} from '../services/api';

import CompactVideoCard from './CompactVideoCard';
import LogConsole from './LogConsole';

const formatSizeStr = (sizeBytes) => {
  if (!sizeBytes || isNaN(sizeBytes)) return '0 B';
  if (sizeBytes < 1024) return `${sizeBytes} B`;
  if (sizeBytes < 1024 * 1024) return `${(sizeBytes / 1024).toFixed(1)} KB`;
  if (sizeBytes < 1024 * 1024 * 1024) return `${(sizeBytes / (1024 * 1024)).toFixed(1)} MB`;
  return `${(sizeBytes / (1024 * 1024 * 1024)).toFixed(2)} GB`;
};

const PIPELINE_STEPS = [
  { id: 's01_probe', label: '1. Probe Video Info' },
  { id: 's02_demux', label: '2. Demux Streams' },
  { id: 's03_subtitle_detect', label: '3. Subtitle Region Detect' },
  { id: 's04_audio_separate', label: '4. Audio Demucs Separate' },
  { id: 's05_asr', label: '5. Whisper ASR' },
  { id: 's05b_gender_detect', label: '5b. Gender Detect' },
  { id: 's06_ocr', label: '6. PaddleOCR Subtitle' },
  { id: 's07_transcript_merge', label: '7. Merge ASR & OCR' },
  { id: 's08_translation', label: '8. AI LLM Translation' },
  { id: 's08b_metadata_gen', label: '8b. AI Metadata Gen' },
  { id: 's09_subtitle_gen', label: '9. Subtitle Gen (ASS/SRT)' },
  { id: 's10_inpaint', label: '10. Subtitle Inpaint & Watermark' },
  { id: 's11_subtitle_render', label: '11. Subtitle Render' },
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
  const { srcFiles = [], outputFiles = [], workspaceJobs = [] } = videos || {};
  const allFiles = [...srcFiles, ...outputFiles].filter(f => f.isMedia);

  const [folderFilter, setFolderFilter] = useState('all'); // 'all' | 'src' | 'output'
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
    if (searchQuery.trim()) {
      return file.name.toLowerCase().includes(searchQuery.toLowerCase());
    }
    return true;
  });

  const visibleFiles = filteredFiles.slice(0, displayLimit);

  // Reset displayLimit on filter or search query change
  useEffect(() => {
    setDisplayLimit(24);
  }, [folderFilter, searchQuery]);

  // Infinite Scroll Observer using IntersectionObserver
  useEffect(() => {
    const observer = new IntersectionObserver(
      (entries) => {
        if (entries[0].isIntersecting) {
          setDisplayLimit(prev => Math.min(prev + 24, filteredFiles.length));
        }
      },
      { threshold: 0.1 }
    );

    if (sentinelRef.current) {
      observer.observe(sentinelRef.current);
    }

    return () => {
      if (sentinelRef.current) {
        observer.unobserve(sentinelRef.current);
      }
    };
  }, [filteredFiles.length]);

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
    if (window.confirm(`⚠️ BẠN CÓ CHẮC CHẮN MUỐN XÓA JOB WORKSPACE "${cleanJobId}" KHÔNG?\n\nToàn bộ file cache của job này trong project "${project}" sẽ bị xóa vĩnh viễn!`)) {
      try {
        await deleteWorkspaceJob(project, cleanJobId);
        if (workspaceJobModal?.jobId === cleanJobId) {
          setWorkspaceJobModal(null);
        }
        onRefresh();
      } catch (err) {
        alert('Lỗi xóa job workspace: ' + err.message);
      }
    }
  };

  const handleDeleteStepCache = async (jobId, stepId) => {
    if (!project) return;
    const cleanJobId = jobId.startsWith('job_') ? jobId : `job_${getStem(jobId)}`;
    if (window.confirm(`🧹 XÓA CACHE STEP "${stepId}" TRONG JOB "${cleanJobId}"?\n\nHệ thống sẽ dọn dẹp file cache của step này và TỰ ĐỘNG INVALIDATE tất cả các step phía sau phụ thuộc vào nó.\n\nSau khi xóa, bạn có thể bấm Resume để chạy lại từ step này!`)) {
      try {
        await deleteStepCache(project, cleanJobId, stepId);
        const res = await fetchWorkspaceJobFiles(project, cleanJobId);
        setWorkspaceJobModal(res);
        onRefresh();
      } catch (err) {
        alert('Lỗi xóa cache step: ' + err.message);
      }
    }
  };

  const handleRenameFile = async (file) => {
    if (!file || !file.name || !file.relPath) return;
    const newName = window.prompt(`✏️ Nhập tên mới cho file "${file.name}":`, file.name);
    if (!newName || !newName.trim() || newName.trim() === file.name) return;

    try {
      const res = await renameFile(file.relPath, newName.trim());
      if (res.error) {
        alert('Lỗi đổi tên file: ' + res.error);
      } else {
        onRefresh();
      }
    } catch (err) {
      alert('Lỗi đổi tên file: ' + err.message);
    }
  };

  const handleDeleteFile = async (file) => {
    if (!file || !file.name || !file.relPath) return;
    if (window.confirm(`⚠️ BẠN CÓ CHẮC CHẮN MUỐN XÓA FILE "${file.name}" KHÔNG?\n\nFile này sẽ bị xóa vĩnh viễn khỏi thư mục!`)) {
      try {
        const res = await deleteFile(file.relPath);
        if (res.error) {
          alert('Lỗi xóa file: ' + res.error);
        } else {
          onRefresh();
        }
      } catch (err) {
        alert('Lỗi xóa file: ' + err.message);
      }
    }
  };

  const handleSaveTranslation = async () => {
    if (!translationRelPath || translationContent === null) return;
    setIsSavingTranslation(true);
    try {
      await saveFileContent(translationRelPath, translationContent);
      alert('✅ Đã lưu file s08_translation.json thành công!\n\nNhấn "Resume Pipeline" để áp dụng câu dịch mới trong đúng 2 giây.');
    } catch (e) {
      alert('❌ Lỗi khi lưu bản dịch: ' + e.message);
    } finally {
      setIsSavingTranslation(false);
    }
  };

  const handleSaveVideoConfig = async () => {
    if (!videoConfigRelPath) return;
    setIsSavingConfig(true);
    try {
      await saveFileContent(videoConfigRelPath, videoConfigContent);
      alert('✅ Đã lưu config riêng cho video thành công!');
    } catch (e) {
      alert('❌ Lỗi khi lưu config video: ' + e.message);
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
            <div style={styles.batchBar}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                <button style={styles.btnBatchSelectAll} onClick={handleSelectAll}>
                  <CheckSquare size={14} style={{ marginRight: 4 }} />
                  Bỏ Chọn ({selectedRelPaths.length}/{filteredFiles.length})
                </button>
              </div>

              <div style={{ display: 'flex', gap: 6 }}>
                <button style={styles.btnBatchActionPrimary} onClick={handleBatchTranslateSelected}>
                  <Play size={13} style={{ marginRight: 4 }} /> Dịch ({selectedRelPaths.length})
                </button>

                <button style={styles.btnBatchActionWarning} onClick={handleBatchResumeSelected}>
                  <RotateCcw size={13} style={{ marginRight: 4 }} /> Resume ({selectedRelPaths.length})
                </button>
              </div>
            </div>
          )}

          {/* Video Cards 2-column Grid with Auto Infinite Scroll */}
          <div style={styles.galleryScrollContainer}>
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
                    actionLabel={
                      isFileProcessing(file)
                        ? '⚙️ Đang dịch...'
                        : activeSelectedFile?.relPath === file.relPath
                          ? '► Đang chọn'
                          : '► Chọn video'
                    }
                    onAction={() => { if (!isFileProcessing(file)) handleSelectFile(file); }}
                  />
                ))}
              </div>
            )}

            {/* Auto Infinite Scroll Sentinel */}
            <div ref={sentinelRef} style={styles.sentinel}>
              {displayLimit < filteredFiles.length && (
                <span style={{ fontSize: 11, color: '#64748b' }}>
                  ⏳ Tự động tải thêm video... ({visibleFiles.length}/{filteredFiles.length})
                </span>
              )}
            </div>
          </div>
        </div>

        {/* RIGHT COLUMN: VIDEO WORKSPACE & CONTROLS */}
        <div style={styles.cardRight}>
          
          {/* 1. Hero Preview Video Player */}
          <div style={styles.heroSection}>
            <div style={styles.sectionHeader}>
              <Eye size={16} color="#818cf8" style={{ marginRight: 6 }} />
              <span style={{ fontWeight: 'bold', fontSize: 14, color: '#f8fafc' }}>
                Xem Trước: <span style={{ color: '#818cf8' }}>{activeSelectedFile ? activeSelectedFile.name : 'Chưa chọn video'}</span>
              </span>
            </div>

            {activeSelectedFile ? (
              <div style={styles.playerWrapper}>
                <video
                  key={activeSelectedFile.relPath}
                  src={getMediaUrl(activeSelectedFile.relPath)}
                  controls
                  style={styles.videoPlayer}
                />
              </div>
            ) : (
              <div style={styles.emptyPlayer}>Tích chọn một video bên trái để xem trước</div>
            )}
          </div>

          {/* 2. Interactive Quick Action Buttons */}
          {activeSelectedFile && (
            <div style={styles.actionsCard}>
              <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8 }}>
                <button
                  style={styles.btnActionPrimary}
                  onClick={() => handleTranslate(activeSelectedFile.relPath)}
                  disabled={isFileProcessing(activeSelectedFile)}
                >
                  <Play size={14} style={{ marginRight: 4 }} /> Dịch Thuyết Minh
                </button>

                <button
                  style={styles.btnActionOcr}
                  onClick={() => handleTranslateOcr(activeSelectedFile.relPath)}
                  disabled={isFileProcessing(activeSelectedFile)}
                >
                  <Wand2 size={14} style={{ marginRight: 4 }} /> Dịch Sub Fast OCR
                </button>

                <button
                  style={styles.btnActionWarning}
                  onClick={() => handleResume(activeSelectedFile.name)}
                  disabled={isFileProcessing(activeSelectedFile)}
                >
                  <RotateCcw size={14} style={{ marginRight: 4 }} /> Resume Pipeline
                </button>

                <button
                  style={styles.btnActionSecondary}
                  onClick={() => onOpenTrimmer(activeSelectedFile.relPath)}
                >
                  <Scissors size={14} style={{ marginRight: 4 }} /> Cắt (Trimmer)
                </button>

                <button
                  style={styles.btnActionSecondary}
                  onClick={() => handleRenameFile(activeSelectedFile)}
                >
                  <Pencil size={14} style={{ marginRight: 4 }} /> Đổi Tên
                </button>

                <button
                  style={styles.btnActionDanger}
                  onClick={() => handleDeleteFile(activeSelectedFile)}
                >
                  <Trash2 size={14} style={{ marginRight: 4 }} /> Xóa Video
                </button>
              </div>
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
    backgroundColor: '#090d16',
    color: '#818cf8',
    border: '1px solid #334155',
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
    backgroundColor: '#090d16',
    borderRadius: 10,
    overflow: 'hidden',
    border: '1px solid #334155'
  }
};
