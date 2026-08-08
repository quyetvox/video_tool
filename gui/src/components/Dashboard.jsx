import React, { useState } from 'react';
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
  Pencil
} from 'lucide-react';
import { getMediaUrl, runScript, fetchFileContent, fetchWorkspaceJobFiles, deleteWorkspaceJob, deleteStepCache, renameFile, deleteFile } from '../services/api';

import VideoCard from './VideoCard';

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
  onRefresh, 
  onOpenTrimmer, 
  onSelectTab 
}) {
  const [activeTab, setActiveTab] = useState('src');
  const [viewMode, setViewMode] = useState('grid'); // 'grid' | 'list'
  const [selectedRelPaths, setSelectedRelPaths] = useState([]);
  const [previewVideo, setPreviewVideo] = useState(null);
  const [previewImage, setPreviewImage] = useState(null); // { url, title }
  const [textContentData, setTextContentData] = useState(null); // { path, content }
  const [copiedAll, setCopiedAll] = useState(false);
  const [runningJob, setRunningJob] = useState(null);

  // Workspace Job Modal State
  const [workspaceJobModal, setWorkspaceJobModal] = useState(null); // { jobId, files: [] }

  const { srcFiles = [], outputFiles = [], workspaceJobs = [] } = videos || {};

  const currentFiles = activeTab === 'src' ? srcFiles : activeTab === 'output' ? outputFiles : [];

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

  const handleToggleSelect = (relPath) => {
    if (selectedRelPaths.includes(relPath)) {
      setSelectedRelPaths(selectedRelPaths.filter(p => p !== relPath));
    } else {
      setSelectedRelPaths([...selectedRelPaths, relPath]);
    }
  };

  const handleSelectAll = () => {
    if (selectedRelPaths.length === currentFiles.length) {
      setSelectedRelPaths([]);
    } else {
      setSelectedRelPaths(currentFiles.map(f => f.relPath));
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
      onRefresh();
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
      onRefresh();
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
      onRefresh();
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


  const handleViewTextContent = async (relPath) => {
    try {
      const res = await fetchFileContent(relPath);
      let rawContent = res.content || '';
      if (typeof rawContent === 'object') {
        rawContent = JSON.stringify(rawContent, null, 2);
      } else if (typeof rawContent === 'string' && (relPath.endsWith('.json') || rawContent.trim().startsWith('{') || rawContent.trim().startsWith('['))) {
        try {
          const parsed = JSON.parse(rawContent);
          rawContent = JSON.stringify(parsed, null, 2);
        } catch (e) {}
      }
      setTextContentData({ path: relPath, content: rawContent });
    } catch (e) {
      console.error('Failed to read file content:', e);
    }
  };

  const handleOpenWorkspaceJobModal = async (jobId) => {
    try {
      const data = await fetchWorkspaceJobFiles(project, jobId);
      setWorkspaceJobModal({ jobId, files: data.files || [] });
    } catch (e) {
      console.error('Failed to fetch workspace files:', e);
    }
  };

  const handleCopyAllText = () => {
    if (textContentData) {
      navigator.clipboard.writeText(textContentData.content);
      setCopiedAll(true);
      setTimeout(() => setCopiedAll(false), 2000);
    }
  };

  const formatSize = (bytes) => {
    if (!bytes) return '0 KB';
    if (bytes > 1024 * 1024) return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
    return `${(bytes / 1024).toFixed(1)} KB`;
  };

  return (
    <div style={styles.container}>
      {/* Top Header */}
      <div style={styles.header}>
        <div>
          <h2 style={styles.title}>Dự Án: <span style={{ color: '#818cf8' }}>{project || 'Chưa chọn'}</span></h2>
          <p style={styles.subtitle}>Quản lý video gốc, chạy pipeline dịch thuật và theo dõi workspace</p>
        </div>

        <div style={{ display: 'flex', gap: 10, alignItems: 'center' }}>
          {/* View Mode Toggle Switcher */}
          <div style={styles.viewSwitcher}>
            <button
              onClick={() => setViewMode('grid')}
              style={{ ...styles.switchBtn, ...(viewMode === 'grid' ? styles.switchBtnActive : {}) }}
              title="Gallery Grid View"
            >
              <LayoutGrid size={15} />
            </button>
            <button
              onClick={() => setViewMode('list')}
              style={{ ...styles.switchBtn, ...(viewMode === 'list' ? styles.switchBtnActive : {}) }}
              title="List Table View"
            >
              <List size={15} />
            </button>
          </div>

          <button style={styles.btnSecondary} onClick={onRefresh} title="Làm mới danh sách">
            <RefreshCw size={16} style={{ marginRight: 6 }} /> Reload
          </button>

          <button style={styles.btnPrimary} onClick={handleBatchTranslate} disabled={srcFiles.length === 0}>
            <Wand2 size={16} style={{ marginRight: 6 }} /> Dịch Hàng Loạt Tất Cả ({srcFiles.length})
          </button>
        </div>
      </div>

      {/* Tabs Bar */}
      <div style={styles.tabHeader}>
        <button
          onClick={() => { setActiveTab('src'); setSelectedRelPaths([]); }}
          style={{ ...styles.tabBtn, ...(activeTab === 'src' ? styles.tabBtnActive : {}) }}
        >
          <FileVideo size={16} style={{ marginRight: 6 }} />
          Video Gốc (`src/`) [{srcFiles.length}]
        </button>

        <button
          onClick={() => { setActiveTab('output'); setSelectedRelPaths([]); }}
          style={{ ...styles.tabBtn, ...(activeTab === 'output' ? styles.tabBtnActive : {}) }}
        >
          <CheckCircle2 size={16} style={{ marginRight: 6 }} />
          Video Kết Quả (`output/`) [{outputFiles.length}]
        </button>

        <button
          onClick={() => { setActiveTab('workspace'); setSelectedRelPaths([]); }}
          style={{ ...styles.tabBtn, ...(activeTab === 'workspace' ? styles.tabBtnActive : {}) }}
        >
          <Layers size={16} style={{ marginRight: 6 }} />
          Workspace Cache Jobs [{workspaceJobs.length}]
        </button>
      </div>

      {/* Sticky Multi-Select Batch Actions Bar */}
      {selectedRelPaths.length > 0 && (
        <div style={styles.batchBar}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
            <button style={styles.btnBatchSelectAll} onClick={handleSelectAll}>
              <CheckSquare size={16} style={{ marginRight: 6 }} />
              Bỏ Chọn ({selectedRelPaths.length}/{currentFiles.length})
            </button>
            <span style={{ fontSize: 13, color: '#f8fafc', fontWeight: 'bold' }}>
              Đã chọn {selectedRelPaths.length} video
            </span>
          </div>

          <div style={{ display: 'flex', gap: 8 }}>
            <button style={styles.btnBatchActionPrimary} onClick={handleBatchTranslateSelected}>
              <Play size={14} style={{ marginRight: 6 }} /> Dịch Tuần Tự {selectedRelPaths.length} Video Đã Chọn
            </button>

            <button style={styles.btnBatchActionWarning} onClick={handleBatchResumeSelected}>
              <RotateCcw size={14} style={{ marginRight: 6 }} /> Resume Tuần Tự {selectedRelPaths.length} Video
            </button>
          </div>
        </div>
      )}

      {/* Tab Content Rendering (Src & Output) */}
      {(activeTab === 'src' || activeTab === 'output') && (
        viewMode === 'grid' ? (
          <div style={styles.grid}>
            {currentFiles.length === 0 ? (
              <div style={styles.emptyState}>Chưa có file nào trong thư mục này</div>
            ) : (
              currentFiles.map(file => (
                <VideoCard
                  key={file.name}
                  file={file}
                  isSelected={selectedRelPaths.includes(file.relPath)}
                  isProcessing={isFileProcessing(file)}
                  onToggleSelect={handleToggleSelect}
                  onTranslate={activeTab === 'src' ? handleTranslate : null}
                  onTranslateOcr={handleTranslateOcr}
                  onTrim={onOpenTrimmer}
                  onResume={handleResume}
                  onRename={handleRenameFile}
                  onDelete={handleDeleteFile}
                  onPreview={(url) => setPreviewVideo(url)}
                  onViewTextContent={handleViewTextContent}
                  onViewImage={(url, name) => setPreviewImage({ url, title: name })}
                  isDone={activeTab === 'output'}
                />
              ))
            )}
          </div>
        ) : (
          /* List Table View */
          <div style={styles.listTableContainer}>
            <table style={styles.table}>
              <thead>
                <tr>
                  <th style={{ width: 40, textAlign: 'center' }}>
                    <input
                      type="checkbox"
                      checked={selectedRelPaths.length === currentFiles.length && currentFiles.length > 0}
                      onChange={handleSelectAll}
                    />
                  </th>
                  <th>Tên File</th>
                  <th>Loại</th>
                  <th>Dung Lượng</th>
                  <th>Cập Nhật</th>
                  <th style={{ textAlign: 'right' }}>Thao Tác</th>
                </tr>
              </thead>
              <tbody>
                {currentFiles.map(file => {
                  const isSelected = selectedRelPaths.includes(file.relPath);
                  const isProcessing = isFileProcessing(file);

                  return (
                    <tr 
                      key={file.name} 
                      style={{ 
                        backgroundColor: isProcessing ? 'rgba(245, 158, 11, 0.2)' : isSelected ? 'rgba(99, 102, 241, 0.15)' : 'transparent',
                        borderLeft: isProcessing ? '3px solid #f59e0b' : 'none'
                      }}
                    >
                      <td style={{ textAlign: 'center' }}>
                        <input
                          type="checkbox"
                          checked={isSelected}
                          disabled={isProcessing}
                          onChange={() => handleToggleSelect(file.relPath)}
                        />
                      </td>
                      <td style={{ fontWeight: '600', color: '#f8fafc' }}>
                        {file.isMedia ? '🎬 ' : file.isImage ? '🖼️ ' : '📄 '}{file.name}
                        {isProcessing && <span style={{ marginLeft: 8, fontSize: 11, color: '#f59e0b', fontWeight: 'bold' }}>⏳ Đang xử lý...</span>}
                      </td>
                      <td style={{ color: '#94a3b8', fontSize: 12 }}>
                        {file.isMedia ? 'MP4 Video' : file.isImage ? 'Image' : 'Document'}
                      </td>
                      <td style={{ color: '#cbd5e1', fontSize: 12 }}>{formatSize(file.sizeBytes)}</td>
                      <td style={{ color: '#64748b', fontSize: 12 }}>
                        {file.mtime ? new Date(file.mtime).toLocaleString([], { dateStyle: 'short', timeStyle: 'short' }) : ''}
                      </td>
                      <td style={{ textAlign: 'right' }}>
                        <div style={{ display: 'flex', gap: 6, justifyContent: 'flex-end' }}>
                          {file.isMedia ? (
                            <>
                              {activeTab === 'src' ? (
                                <>
                                  <button 
                                    style={isProcessing ? styles.btnSmallSec : styles.btnSmallPrimary} 
                                    onClick={() => !isProcessing && handleTranslate(file.relPath)}
                                    disabled={isProcessing}
                                  >
                                    <Play size={11} style={{ marginRight: 3 }} /> {isProcessing ? 'Đang Chạy...' : 'Dịch'}
                                  </button>
                                  <button 
                                    style={{ ...styles.btnSmallSec, backgroundColor: 'rgba(168, 85, 247, 0.2)', color: '#d8b4fe', border: '1px solid rgba(168, 85, 247, 0.4)' }} 
                                    onClick={() => !isProcessing && handleTranslateOcr(file.relPath)}
                                    disabled={isProcessing}
                                    title="📸 Dịch Sub Cứng (Visual OCR)"
                                  >
                                    <Eye size={11} style={{ marginRight: 3 }} /> Sub Cứng
                                  </button>
                                </>
                              ) : (
                                <button 
                                  style={isProcessing ? styles.btnSmallSec : styles.btnSmallWarning} 
                                  onClick={() => !isProcessing && handleResume(getStem(file.name))}
                                  disabled={isProcessing}
                                  title="Resume pipeline job cho video này"
                                >
                                  <RotateCcw size={11} style={{ marginRight: 3 }} /> {isProcessing ? 'Đang Chạy...' : 'Resume'}
                                </button>
                              )}
                              <button 
                                style={styles.btnSmallSec} 
                                onClick={() => !isProcessing && onOpenTrimmer(file.relPath)}
                                disabled={isProcessing}
                              >
                                <Scissors size={11} style={{ marginRight: 3 }} /> Cắt
                              </button>
                              <button 
                                style={styles.btnSmallSec} 
                                onClick={() => !isProcessing && handleRenameFile(file)}
                                disabled={isProcessing}
                                title="Đổi tên file"
                              >
                                <Pencil size={11} style={{ marginRight: 3 }} /> Đổi Tên
                              </button>
                              <button 
                                style={{ ...styles.btnSmallSec, color: '#ef4444', backgroundColor: 'rgba(239, 68, 68, 0.12)', border: '1px solid rgba(239, 68, 68, 0.2)' }} 
                                onClick={() => !isProcessing && handleDeleteFile(file)}
                                disabled={isProcessing}
                                title="Xóa file"
                              >
                                <Trash2 size={11} style={{ marginRight: 3 }} /> Xóa
                              </button>
                            </>
                          ) : (
                            <>
                              <button style={styles.btnSmallPrimary} onClick={() => handleViewTextContent(file.relPath)}>
                                <Eye size={11} style={{ marginRight: 3 }} /> Xem Content
                              </button>
                              <button 
                                style={styles.btnSmallSec} 
                                onClick={() => !isProcessing && handleRenameFile(file)}
                                disabled={isProcessing}
                                title="Đổi tên file"
                              >
                                <Pencil size={11} style={{ marginRight: 3 }} /> Đổi Tên
                              </button>
                              <button 
                                style={{ ...styles.btnSmallSec, color: '#ef4444', backgroundColor: 'rgba(239, 68, 68, 0.12)', border: '1px solid rgba(239, 68, 68, 0.2)' }} 
                                onClick={() => !isProcessing && handleDeleteFile(file)}
                                disabled={isProcessing}
                                title="Xóa file"
                              >
                                <Trash2 size={11} style={{ marginRight: 3 }} /> Xóa
                              </button>
                            </>
                          )}
                        </div>
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )
      )}

      {/* Tab 3: Workspace Cache Jobs */}
      {activeTab === 'workspace' && (
        viewMode === 'grid' ? (
          <div style={styles.grid}>
            {workspaceJobs.length === 0 ? (
              <div style={styles.emptyState}>Không có job nào trong `assets/{project}/workspace/`</div>
            ) : (
              workspaceJobs.map(jobName => {
                const videoStem = jobName.replace(/^job_/, '');
                const isProcessing = runningRelPaths.some(p => p.includes(videoStem) || p === jobName);

                return (
                  <div 
                    key={jobName} 
                    style={{
                      ...styles.card,
                      ...(isProcessing ? { border: '2px solid #f59e0b', boxShadow: '0 0 16px rgba(245, 158, 11, 0.5)', backgroundColor: '#272015' } : {})
                    }}
                  >
                    <div style={styles.cardHeader}>
                      <div style={styles.fileIconBox}>
                        <Layers size={24} color="#f59e0b" />
                      </div>
                      <div style={{ overflow: 'hidden', flex: 1 }}>
                        <div style={styles.fileName} title={jobName}>
                          {jobName}
                          {isProcessing && <span style={{ marginLeft: 6, fontSize: 10, color: '#f59e0b', fontWeight: 'bold' }}>⏳ Đang chạy...</span>}
                        </div>
                        <div style={styles.fileMeta}>Pipeline State Cached</div>
                      </div>
                    </div>

                    <div style={styles.cardActions}>
                      <button 
                        style={styles.actionBtnPrimary} 
                        onClick={() => handleOpenWorkspaceJobModal(jobName)}
                      >
                        <FolderOpen size={14} style={{ marginRight: 4 }} /> Xem Chi Tiết Workspace
                      </button>

                      <button 
                        style={isProcessing ? { ...styles.actionBtnWarning, backgroundColor: '#475569', opacity: 0.6, cursor: 'not-allowed' } : styles.actionBtnWarning} 
                        onClick={() => !isProcessing && handleResume(jobName)}
                        disabled={isProcessing}
                      >
                        <RotateCcw size={14} style={{ marginRight: 4 }} /> {isProcessing ? 'Đang Chạy...' : 'Resume Job'}
                      </button>

                      <button 
                        style={{ ...styles.actionBtnPrimary, backgroundColor: '#ef4444' }} 
                        onClick={() => handleDeleteJob(jobName)}
                        title="Xóa toàn bộ thư mục workspace job này"
                      >
                        <Trash2 size={14} style={{ marginRight: 4 }} /> Xoá Job
                      </button>
                    </div>
                  </div>
                );
              })
            )}
          </div>
        ) : (
          /* Workspace List Table View */
          <div style={styles.listTableContainer}>
            <table style={styles.table}>
              <thead>
                <tr>
                  <th>Job Workspace ID</th>
                  <th>Kiểu Trạng Thái</th>
                  <th style={{ textAlign: 'right' }}>Thao Tác</th>
                </tr>
              </thead>
              <tbody>
                {workspaceJobs.map(jobName => {
                  const videoStem = jobName.replace(/^job_/, '');
                  const isProcessing = runningRelPaths.some(p => p.includes(videoStem) || p === jobName);

                  return (
                    <tr 
                      key={jobName}
                      style={{
                        backgroundColor: isProcessing ? 'rgba(245, 158, 11, 0.2)' : 'transparent',
                        borderLeft: isProcessing ? '3px solid #f59e0b' : 'none'
                      }}
                    >
                      <td style={{ fontWeight: 'bold', color: '#f59e0b' }}>
                        📂 {jobName}
                        {isProcessing && <span style={{ marginLeft: 8, fontSize: 11, color: '#f59e0b' }}>⏳ Đang xử lý...</span>}
                      </td>
                      <td style={{ color: '#94a3b8', fontSize: 12 }}>Pipeline State Cached Directory</td>
                      <td style={{ textAlign: 'right' }}>
                        <div style={{ display: 'flex', gap: 6, justifyContent: 'flex-end' }}>
                          <button style={styles.btnSmallPrimary} onClick={() => handleOpenWorkspaceJobModal(jobName)}>
                            <FolderOpen size={11} style={{ marginRight: 3 }} /> Explorer File
                          </button>
                          <button 
                            style={isProcessing ? styles.btnSmallSec : styles.btnSmallWarning} 
                            onClick={() => !isProcessing && handleResume(jobName)}
                            disabled={isProcessing}
                          >
                            <RotateCcw size={11} style={{ marginRight: 3 }} /> {isProcessing ? 'Đang Chạy...' : 'Resume Job'}
                          </button>
                          <button 
                            style={{ ...styles.btnSmallSec, backgroundColor: '#ef4444', color: '#fff' }} 
                            onClick={() => handleDeleteJob(jobName)}
                            title="Xóa toàn bộ thư mục workspace job này"
                          >
                            <Trash2 size={11} style={{ marginRight: 3 }} /> Xoá Job
                          </button>
                        </div>
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )
      )}

      {/* Video Preview Modal */}
      {previewVideo && (
        <div style={styles.modalOverlay} onClick={() => setPreviewVideo(null)}>
          <div style={styles.videoModal} onClick={e => e.stopPropagation()}>
            <video 
              src={previewVideo} 
              controls 
              autoPlay 
              style={{ width: '100%', maxHeight: '70vh', borderRadius: 8 }}
            />
            <div style={{ display: 'flex', justifyContent: 'flex-end', marginTop: 12 }}>
              <button style={styles.btnSecondary} onClick={() => setPreviewVideo(null)}>
                Đóng
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Image Viewer Modal */}
      {previewImage && (
        <div style={styles.modalOverlay} onClick={() => setPreviewImage(null)}>
          <div style={styles.imageModal} onClick={e => e.stopPropagation()}>
            <div style={styles.textModalHeader}>
              <span style={{ fontWeight: 'bold', color: '#f8fafc', fontSize: 14 }}>
                🖼️ {previewImage.title}
              </span>
              <button style={styles.btnIconClose} onClick={() => setPreviewImage(null)}>
                <X size={16} />
              </button>
            </div>
            <img 
              src={previewImage.url} 
              alt={previewImage.title} 
              style={{ maxWidth: '100%', maxHeight: '75vh', objectFit: 'contain', borderRadius: 8 }} 
            />
          </div>
        </div>
      )}

      {/* Workspace Job Explorer Modal (Table View & Step Cache Manager) */}
      {workspaceJobModal && (
        <div style={styles.modalOverlay} onClick={() => setWorkspaceJobModal(null)}>
          <div style={styles.workspaceModal} onClick={e => e.stopPropagation()}>
            <div style={styles.textModalHeader}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                <FolderOpen size={20} color="#f59e0b" />
                <div>
                  <span style={{ fontWeight: 'bold', color: '#f8fafc', fontSize: 15 }}>
                    Workspace Job: {workspaceJobModal.jobId}
                  </span>
                  <span style={{ fontSize: 12, color: '#64748b', display: 'block' }}>
                    Danh sách tất cả file cache ({workspaceJobModal.files.length} items)
                  </span>
                </div>
              </div>

              <div style={{ display: 'flex', gap: 8, alignItems: 'center' }}>
                <button
                  style={{
                    backgroundColor: '#ef4444',
                    color: '#fff',
                    border: 'none',
                    padding: '6px 12px',
                    borderRadius: 6,
                    fontSize: 11,
                    fontWeight: 'bold',
                    cursor: 'pointer',
                    display: 'flex',
                    alignItems: 'center'
                  }}
                  onClick={() => handleDeleteJob(workspaceJobModal.jobId)}
                  title="Xóa toàn bộ thư mục workspace job này"
                >
                  <Trash2 size={13} style={{ marginRight: 4 }} /> Xoá Toàn Bộ Job Workspace
                </button>
                <button style={styles.btnIconClose} onClick={() => setWorkspaceJobModal(null)}>
                  <X size={16} />
                </button>
              </div>
            </div>

            {/* Pipeline 16 Steps Cache Manager */}
            <div style={{
              backgroundColor: '#0f172a',
              borderRadius: 8,
              padding: 12,
              marginBottom: 16,
              border: '1px solid #334155'
            }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 10 }}>
                <span style={{ fontWeight: 'bold', color: '#38bdf8', fontSize: 13, display: 'flex', alignItems: 'center', gap: 6 }}>
                  <Layers size={15} color="#38bdf8" /> Quản Lý 16 Pipeline Steps Cache & Cascade Invalidation
                </span>
                <span style={{ fontSize: 11, color: '#94a3b8' }}>
                  💡 Xóa cache 1 step sẽ tự động xoá cache các step phía sau để sẵn sàng cho Resume
                </span>
              </div>

              <div style={{
                display: 'grid',
                gridTemplateColumns: 'repeat(auto-fill, minmax(250px, 1fr))',
                gap: 8,
                maxHeight: 180,
                overflowY: 'auto',
                paddingRight: 4
              }}>
                {PIPELINE_STEPS.map(step => {
                  const isDone = workspaceJobModal.files.some(f => f.basename === `${step.id}.done`);
                  return (
                    <div key={step.id} style={{
                      backgroundColor: '#1e293b',
                      borderRadius: 6,
                      padding: '6px 10px',
                      display: 'flex',
                      justifyContent: 'space-between',
                      alignItems: 'center',
                      border: isDone ? '1px solid rgba(16, 185, 129, 0.4)' : '1px solid #334155'
                    }}>
                      <div>
                        <div style={{ fontSize: 11, fontWeight: '600', color: isDone ? '#f8fafc' : '#64748b' }}>
                          {step.label}
                        </div>
                        <span style={{ fontSize: 10, color: isDone ? '#10b981' : '#64748b' }}>
                          {isDone ? '✓ Completed (Cached)' : '⏳ Pending / Cleared'}
                        </span>
                      </div>

                      {isDone && (
                        <button
                          style={{
                            backgroundColor: '#ef4444',
                            color: '#fff',
                            border: 'none',
                            padding: '3px 8px',
                            borderRadius: 4,
                            fontSize: 10,
                            fontWeight: 'bold',
                            cursor: 'pointer',
                            display: 'flex',
                            alignItems: 'center'
                          }}
                          onClick={() => handleDeleteStepCache(workspaceJobModal.jobId, step.id)}
                          title={`Xóa cache step ${step.id} và tất cả các step phía sau`}
                        >
                          <Trash2 size={10} style={{ marginRight: 3 }} /> Xoá Cache
                        </button>
                      )}
                    </div>
                  );
                })}
              </div>
            </div>

            <div style={{ maxHeight: '45vh', overflowY: 'auto' }}>
              <table style={styles.table}>
                <thead>
                  <tr>
                    <th>Tên File</th>
                    <th>Loại Item</th>
                    <th>Dung Lượng</th>
                    <th>Cập Nhật</th>
                    <th style={{ textAlign: 'right' }}>Thao Tác</th>
                  </tr>
                </thead>
                <tbody>
                  {workspaceJobModal.files.map(f => (
                    <tr key={f.relPath}>
                      <td style={{ fontWeight: '600', color: '#f8fafc' }}>
                        {f.isMedia ? '🎥 ' : f.isAudio ? '🔊 ' : f.isJson ? '🤖 ' : f.isSub ? '📝 ' : '📄 '}{f.name}
                      </td>
                      <td style={{ color: '#94a3b8', fontSize: 12 }}>
                        {f.isMedia ? 'Video Stream' : f.isAudio ? 'Audio Stream' : f.isJson ? 'JSON Data' : f.isSub ? 'Subtitle ASS/SRT' : 'Text/Log'}
                      </td>
                      <td style={{ color: '#cbd5e1', fontSize: 12 }}>{formatSize(f.sizeBytes)}</td>
                      <td style={{ color: '#64748b', fontSize: 12 }}>
                        {f.mtime ? new Date(f.mtime).toLocaleString([], { dateStyle: 'short', timeStyle: 'short' }) : ''}
                      </td>
                      <td style={{ textAlign: 'right' }}>
                        <div style={{ display: 'flex', gap: 6, justifyContent: 'flex-end' }}>
                          {f.isMedia || f.isAudio ? (
                            <button style={styles.btnSmallDone} onClick={() => setPreviewVideo(getMediaUrl(f.relPath))}>
                              <Play size={11} style={{ marginRight: 3 }} /> Nghe/Xem
                            </button>
                          ) : (
                            <button style={styles.btnSmallPrimary} onClick={() => handleViewTextContent(f.relPath)}>
                              <Eye size={11} style={{ marginRight: 3 }} /> Xem Content
                            </button>
                          )}
                        </div>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>
        </div>
      )}

      {/* Text File Content Viewer Modal (Higher Z-Index: 1200) */}
      {textContentData && (
        <div style={{ ...styles.modalOverlay, zIndex: 1200 }} onClick={() => setTextContentData(null)}>
          <div style={styles.textModal} onClick={e => e.stopPropagation()}>
            <div style={styles.textModalHeader}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                <FileText size={18} color="#818cf8" />
                <span style={{ fontWeight: 'bold', color: '#f8fafc', fontSize: 14 }}>
                  Nội Dung File: {textContentData.path}
                </span>
              </div>

              <div style={{ display: 'flex', gap: 8 }}>
                <button style={styles.btnCopyAll} onClick={handleCopyAllText}>
                  {copiedAll ? <Check size={14} style={{ marginRight: 4 }} /> : <Copy size={14} style={{ marginRight: 4 }} />}
                  {copiedAll ? 'Đã Copy Tất Cả!' : 'Copy Tất Cả'}
                </button>
                <button style={styles.btnIconClose} onClick={() => setTextContentData(null)}>
                  <X size={16} />
                </button>
              </div>
            </div>

            <p style={styles.textModalHint}>
              💡 Bạn có thể dùng chuột bôi đen để chọn & copy từng dòng văn bản tùy ý.
            </p>

            <textarea
              readOnly
              value={textContentData.content}
              style={styles.textModalArea}
              rows={18}
            />
          </div>
        </div>
      )}
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
    display: 'flex',
    justifyContent: 'space-between',
    alignItems: 'center',
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
  viewSwitcher: {
    display: 'flex',
    backgroundColor: '#1e293b',
    borderRadius: 8,
    padding: 2,
    border: '1px solid #334155'
  },
  switchBtn: {
    backgroundColor: 'transparent',
    color: '#64748b',
    border: 'none',
    padding: '6px 10px',
    borderRadius: 6,
    cursor: 'pointer',
    display: 'flex',
    alignItems: 'center'
  },
  switchBtnActive: {
    backgroundColor: '#334155',
    color: '#818cf8'
  },
  btnPrimary: {
    backgroundColor: '#6366f1',
    color: '#fff',
    border: 'none',
    padding: '8px 14px',
    borderRadius: 8,
    fontSize: 12,
    fontWeight: 'bold',
    cursor: 'pointer',
    display: 'flex',
    alignItems: 'center'
  },
  btnSecondary: {
    backgroundColor: '#1e293b',
    color: '#cbd5e1',
    border: '1px solid #334155',
    padding: '8px 12px',
    borderRadius: 8,
    fontSize: 12,
    cursor: 'pointer',
    display: 'flex',
    alignItems: 'center'
  },
  tabHeader: {
    display: 'flex',
    gap: 12,
    borderBottom: '1px solid #1e293b',
    paddingBottom: 12,
    marginBottom: 20
  },
  tabBtn: {
    backgroundColor: 'transparent',
    color: '#64748b',
    border: 'none',
    padding: '8px 14px',
    fontSize: 13,
    fontWeight: '600',
    borderRadius: 8,
    cursor: 'pointer',
    display: 'flex',
    alignItems: 'center'
  },
  tabBtnActive: {
    backgroundColor: '#1e293b',
    color: '#818cf8'
  },
  batchBar: {
    backgroundColor: '#1e293b',
    border: '1px solid #6366f1',
    borderRadius: 10,
    padding: '10px 16px',
    marginBottom: 16,
    display: 'flex',
    justifyContent: 'space-between',
    alignItems: 'center',
    boxShadow: '0 4px 12px rgba(99, 102, 241, 0.2)'
  },
  btnBatchSelectAll: {
    backgroundColor: '#334155',
    color: '#cbd5e1',
    border: 'none',
    padding: '6px 12px',
    borderRadius: 6,
    fontSize: 12,
    cursor: 'pointer',
    display: 'flex',
    alignItems: 'center'
  },
  btnBatchActionPrimary: {
    backgroundColor: '#6366f1',
    color: '#fff',
    border: 'none',
    padding: '6px 12px',
    borderRadius: 6,
    fontSize: 12,
    fontWeight: 'bold',
    cursor: 'pointer',
    display: 'flex',
    alignItems: 'center'
  },
  btnBatchActionWarning: {
    backgroundColor: '#f59e0b',
    color: '#fff',
    border: 'none',
    padding: '6px 12px',
    borderRadius: 6,
    fontSize: 12,
    fontWeight: 'bold',
    cursor: 'pointer',
    display: 'flex',
    alignItems: 'center'
  },
  grid: {
    display: 'grid',
    gridTemplateColumns: 'repeat(auto-fill, minmax(260px, 1fr))',
    gap: 20
  },
  emptyState: {
    gridColumn: '1 / -1',
    textAlign: 'center',
    padding: 60,
    color: '#64748b',
    fontSize: 14,
    backgroundColor: '#1e293b',
    borderRadius: 12,
    border: '1px dashed #334155'
  },
  listTableContainer: {
    backgroundColor: '#1e293b',
    borderRadius: 12,
    border: '1px solid #334155',
    overflow: 'hidden'
  },
  table: {
    width: '100%',
    borderCollapse: 'collapse',
    fontSize: 13,
    color: '#f8fafc',
    textAlign: 'left'
  },
  card: {
    backgroundColor: '#1e293b',
    borderRadius: 12,
    padding: 16,
    border: '1px solid #334155',
    display: 'flex',
    flexDirection: 'column',
    gap: 12
  },
  cardHeader: {
    display: 'flex',
    alignItems: 'center',
    gap: 12
  },
  fileIconBox: {
    width: 42,
    height: 42,
    borderRadius: 8,
    backgroundColor: '#0f172a',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center'
  },
  fileName: {
    fontSize: 13,
    fontWeight: 'bold',
    color: '#f8fafc',
    whiteSpace: 'nowrap',
    overflow: 'hidden',
    textOverflow: 'ellipsis'
  },
  fileMeta: {
    fontSize: 11,
    color: '#64748b'
  },
  cardActions: {
    display: 'flex',
    gap: 8
  },
  actionBtnPrimary: {
    flex: 1,
    backgroundColor: '#334155',
    color: '#f8fafc',
    border: 'none',
    padding: '8px 10px',
    borderRadius: 6,
    fontSize: 11,
    fontWeight: 'bold',
    cursor: 'pointer',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center'
  },
  actionBtnWarning: {
    backgroundColor: '#f59e0b',
    color: '#fff',
    border: 'none',
    padding: '8px 10px',
    borderRadius: 6,
    fontSize: 11,
    fontWeight: 'bold',
    cursor: 'pointer',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center'
  },
  btnSmallPrimary: {
    backgroundColor: '#6366f1',
    color: '#fff',
    border: 'none',
    padding: '4px 8px',
    borderRadius: 4,
    fontSize: 11,
    cursor: 'pointer',
    display: 'inline-flex',
    alignItems: 'center'
  },
  btnSmallDone: {
    backgroundColor: '#10b981',
    color: '#fff',
    border: 'none',
    padding: '4px 8px',
    borderRadius: 4,
    fontSize: 11,
    cursor: 'pointer',
    display: 'inline-flex',
    alignItems: 'center'
  },
  btnSmallSec: {
    backgroundColor: '#334155',
    color: '#cbd5e1',
    border: 'none',
    padding: '4px 8px',
    borderRadius: 4,
    fontSize: 11,
    cursor: 'pointer',
    display: 'inline-flex',
    alignItems: 'center'
  },
  btnSmallWarning: {
    backgroundColor: '#f59e0b',
    color: '#fff',
    border: 'none',
    padding: '4px 8px',
    borderRadius: 4,
    fontSize: 11,
    cursor: 'pointer',
    display: 'inline-flex',
    alignItems: 'center'
  },
  modalOverlay: {
    position: 'fixed',
    top: 0, left: 0, right: 0, bottom: 0,
    backgroundColor: 'rgba(0,0,0,0.85)',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    zIndex: 1000
  },
  videoModal: {
    backgroundColor: '#1e293b',
    borderRadius: 12,
    padding: 16,
    width: '80%',
    maxWidth: 800,
    border: '1px solid #334155'
  },
  imageModal: {
    backgroundColor: '#1e293b',
    borderRadius: 12,
    padding: 16,
    maxWidth: '90vw',
    maxHeight: '90vh',
    border: '1px solid #334155',
    display: 'flex',
    flexDirection: 'column'
  },
  textModal: {
    backgroundColor: '#1e293b',
    borderRadius: 12,
    padding: 20,
    width: '80%',
    maxWidth: 750,
    border: '1px solid #334155'
  },
  workspaceModal: {
    backgroundColor: '#1e293b',
    borderRadius: 12,
    padding: 20,
    width: '85%',
    maxWidth: 900,
    border: '1px solid #334155'
  },
  textModalHeader: {
    display: 'flex',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: 12,
    paddingBottom: 12,
    borderBottom: '1px solid #334155'
  },
  btnCopyAll: {
    backgroundColor: '#6366f1',
    color: '#fff',
    border: 'none',
    padding: '6px 12px',
    borderRadius: 6,
    fontSize: 12,
    fontWeight: 'bold',
    cursor: 'pointer',
    display: 'flex',
    alignItems: 'center'
  },
  btnIconClose: {
    backgroundColor: '#334155',
    color: '#94a3b8',
    border: 'none',
    padding: '6px 8px',
    borderRadius: 6,
    cursor: 'pointer'
  },
  textModalHint: {
    fontSize: 12,
    color: '#94a3b8',
    margin: '0 0 12px 0'
  },
  textModalArea: {
    width: '100%',
    backgroundColor: '#090d16',
    color: '#38bdf8',
    border: '1px solid #334155',
    borderRadius: 8,
    padding: 14,
    fontFamily: 'monospace',
    fontSize: 12,
    lineHeight: 1.6,
    boxSizing: 'border-box',
    outline: 'none'
  }
};
