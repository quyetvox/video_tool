import React, { useState, useEffect, useRef } from 'react';
import TopHeader from './components/TopHeader';
import ModernSidebar from './components/ModernSidebar';
import VideoStudioLayout from './components/VideoStudioLayout';
import VideoStudio from './components/VideoStudio';
import DouyinDownloader from './components/DouyinDownloader';
import ConfigEditor from './components/ConfigEditor';
import LogConsole from './components/LogConsole';
import GoogleCloudStorage from './components/GoogleCloudStorage';
import { ConfirmProvider, useModal, useConfirm } from './components/ConfirmModal';
import { 
  fetchProjects, 
  createProject, 
  fetchProjectVideos, 
  subscribeLogs, 
  runScript,
  syncUpToCloud,
  deleteFile
} from './services/api';

const formatSizeStr = (sizeBytes) => {
  if (!sizeBytes || isNaN(sizeBytes)) return '0 MB';
  if (sizeBytes < 1024 * 1024) return `${(sizeBytes / 1024).toFixed(1)} KB`;
  if (sizeBytes < 1024 * 1024 * 1024) return `${(sizeBytes / (1024 * 1024)).toFixed(1)} MB`;
  return `${(sizeBytes / (1024 * 1024 * 1024)).toFixed(2)} GB`;
};

function MainApp() {
  const { confirm, showAlert } = useModal();
  const [projects, setProjects] = useState([]);
  const [activeProject, setActiveProject] = useState('');
  const [activeTab, setActiveTab] = useState('editor'); // 'editor' | 'studio' | 'downloader' | 'config' | 'logs' | 'cloud'
  const [libraryFilter, setLibraryFilter] = useState('all'); // 'all' | 'src' | 'cut' | 'merge' | 'output'
  const [videos, setVideos] = useState({ srcFiles: [], cutFiles: [], mergeFiles: [], outputFiles: [], workspaceJobs: [] });
  const [trimmerTarget, setTrimmerTarget] = useState(null);

  // ── Global processing & log store ─────────────────────────────────────────
  const [globalLogs, setGlobalLogs] = useState([]);
  const [selectedVideo, setSelectedVideo] = useState(null);
  const [runningRelPaths, setRunningRelPaths] = useState([]);
  const [studioToolMode, setStudioToolMode] = useState('cut'); // 'cut' | 'split' | 'merge'
  const [theme, setTheme] = useState(() => {
    return localStorage.getItem('subvideo_theme') || 'dark';
  });

  useEffect(() => {
    document.documentElement.setAttribute('data-theme', theme);
    localStorage.setItem('subvideo_theme', theme);
  }, [theme]);

  const handleToggleTheme = () => {
    setTheme(prev => (prev === 'dark' ? 'light' : 'dark'));
  };

  const playerRef = useRef(null);
  const studioLayoutRef = useRef(null);
  const videoStudioRef = useRef(null);

  // Subscribe to SSE "global" channel ONCE at app mount
  useEffect(() => {
    const unsubscribe = subscribeLogs(
      'global',
      (logData) => {
        setGlobalLogs(prev => [...prev, {
          id: Date.now() + Math.random(),
          type: logData.type,
          text: logData.text,
          time: new Date().toLocaleTimeString()
        }]);
      },
      (exitData) => {
        setGlobalLogs(prev => [...prev, {
          id: Date.now() + Math.random(),
          type: exitData.success ? 'system-success' : 'system-error',
          text: exitData.success
            ? '🎉 Tiến trình hoàn thành thành công!'
            : `❌ Tiến trình kết thúc với mã lỗi ${exitData.code}`,
          time: new Date().toLocaleTimeString()
        }]);

        // Auto clean runningRelPaths and refresh videos on exit
        if (exitData.jobId) {
          const stem = exitData.jobId.replace(/^job_/, '').replace(/^trans_/, '').replace(/^resume_/, '').replace(/^ocr_/, '').replace(/^batch_sel_/, '').replace(/^batch_/, '').replace(/^dl_/, '').replace(/^trim_/, '').replace(/^cut_/, '').replace(/^studio_/, '');
          setRunningRelPaths(prev => prev.filter(p => !p.includes(stem) && !p.includes(exitData.jobId)));
        } else {
          setRunningRelPaths([]);
        }
        if (activeProject) {
          loadProjectVideos(activeProject);
        }
      },
      (startData) => {
        if (startData && startData.args && Array.isArray(startData.args)) {
          // Only track translation pipelines (main.py, ocr_translator.py, batch_translate.py) as busy video paths
          const scriptName = startData.script || '';
          if (scriptName.includes('main.py') || scriptName.includes('ocr_translator.py') || scriptName.includes('batch_translate.py')) {
            const videoArg = startData.args.find(a => typeof a === 'string' && (a.includes('assets/') || a.startsWith('job_') || a.includes('.mp4') || a.includes(':job_')));
            if (videoArg) {
              const base = videoArg.split('/').pop().split(':').pop();
              const stem = base.replace(/^job_/, '').replace(/_vi\.[^/.]+$|\.[^/.]+$/, '');
              setRunningRelPaths(prev => Array.from(new Set([...prev, videoArg, stem, `job_${stem}`, `resume_${stem}`])));
            }
          }
        }
      }
    );
    return () => unsubscribe();
  }, []);

  // Load initial projects list
  useEffect(() => {
    loadProjectsData();
  }, []);

  // Whenever activeProject changes, load its videos and auto select first video
  useEffect(() => {
    if (activeProject) {
      loadProjectVideos(activeProject, true);
    }
  }, [activeProject]);

  const loadProjectsData = async () => {
    try {
      const data = await fetchProjects();
      const list = data.projects || [];
      setProjects(list);
      if (list.length > 0 && !activeProject) {
        const defaultProj = list.find(p => p.name === 'xujing') || list[0];
        setActiveProject(defaultProj.name);
      }
    } catch (e) {
      console.error('Failed to fetch projects:', e);
    }
  };

  const loadProjectVideos = async (projName, isProjectSwitch = false) => {
    try {
      const data = await fetchProjectVideos(projName);
      const newVideos = {
        srcFiles: data.srcFiles || [],
        cutFiles: data.cutFiles || [],
        mergeFiles: data.mergeFiles || [],
        outputFiles: data.outputFiles || [],
        workspaceJobs: data.workspaceJobs || []
      };
      setVideos(newVideos);

      const allNewMedia = [
        ...newVideos.srcFiles,
        ...newVideos.cutFiles,
        ...newVideos.mergeFiles,
        ...newVideos.outputFiles
      ].filter(f => f.isMedia !== false);

      if (isProjectSwitch) {
        // When switching project: Auto-load the first video of the new project
        setSelectedVideo(allNewMedia.length > 0 ? allNewMedia[0] : null);
      } else {
        // When refreshing/deleting within same project: If previous video still exists, keep it; otherwise stay in empty state (null)
        setSelectedVideo(prev => {
          if (prev && allNewMedia.some(f => f.relPath === prev.relPath)) {
            return prev;
          }
          return null;
        });
      }
    } catch (e) {
      console.error('Failed to fetch project videos:', e);
    }
  };

  const handleCreateProject = async (name) => {
    try {
      await createProject(name);
      await loadProjectsData();
      setActiveProject(name);
    } catch (e) {
      console.error('Failed to create project:', e);
    }
  };

  const handleOpenStudio = (relPath) => {
    setTrimmerTarget(relPath || null);
    setActiveTab('studio');
  };

  const handleRefresh = () => {
    loadProjectsData();
    if (activeProject) {
      loadProjectVideos(activeProject);
    }
  };

  // Calculate storage usage
  const allMedia = [
    ...(videos.srcFiles || []),
    ...(videos.cutFiles || []),
    ...(videos.mergeFiles || []),
    ...(videos.outputFiles || [])
  ];
  const totalSrcBytes = (videos.srcFiles || []).reduce((acc, f) => acc + (f.size || f.sizeBytes || 0), 0);
  const totalCutBytes = (videos.cutFiles || []).reduce((acc, f) => acc + (f.size || f.sizeBytes || 0), 0);
  const totalMergeBytes = (videos.mergeFiles || []).reduce((acc, f) => acc + (f.size || f.sizeBytes || 0), 0);
  const totalOutBytes = (videos.outputFiles || []).reduce((acc, f) => acc + (f.size || f.sizeBytes || 0), 0);
  const totalStorageBytes = totalSrcBytes + totalCutBytes + totalMergeBytes + totalOutBytes;
  const currentVideo = selectedVideo || allMedia[0];

  const storageInfo = {
    totalStr: formatSizeStr(totalStorageBytes),
    details: `${formatSizeStr(totalSrcBytes)} (src) + ${formatSizeStr(totalCutBytes)} (cut) + ${formatSizeStr(totalMergeBytes)} (merge) + ${formatSizeStr(totalOutBytes)} (out)`
  };

  const videoCounts = {
    all: allMedia.length,
    src: (videos.srcFiles || []).length,
    cut: (videos.cutFiles || []).length,
    merge: (videos.mergeFiles || []).length,
    output: (videos.outputFiles || []).length,
    workspace: (videos.workspaceJobs || []).length
  };

  return (
    <div style={{ display: 'flex', width: '100vw', height: '100vh', backgroundColor: 'var(--bg-app)', overflow: 'hidden' }}>
      {/* 1. Left Navigation Sidebar */}
      <ModernSidebar
        projects={projects}
        activeProject={activeProject}
        onSelectProject={setActiveProject}
        onCreateProject={handleCreateProject}
        activeTab={activeTab}
        onSelectTab={setActiveTab}
        libraryFilter={libraryFilter}
        onSelectLibraryFilter={setLibraryFilter}
        videoCounts={videoCounts}
        storageInfo={storageInfo}
        onOpenUploadModal={() => showAlert({
          title: 'Tải lên Video',
          message: 'Kéo thả hoặc copy video vào thư mục assets/' + activeProject + '/src/ trên máy của bạn.',
          type: 'info'
        })}
        onOpenDouyinModal={() => setActiveTab('downloader')}
      />

      {/* 2. Main Content Canvas with Header */}
      <div style={{ flex: 1, display: 'flex', flexDirection: 'column', height: '100vh', overflow: 'hidden' }}>
        {/* Top Header Action Bar */}
        {(() => {
          const currentVideoStem = currentVideo ? currentVideo.name.replace(/\.[^/.]+$/, '') : '';
          const isCurrentVideoBusy = currentVideoStem ? runningRelPaths.some(p => p.includes(currentVideoStem)) : false;

          return (
            <TopHeader
              activeProject={activeProject}
              activeVideo={currentVideo}
              activeTab={activeTab}
              onSelectTab={setActiveTab}
              isBusy={isCurrentVideoBusy}
              runningCount={runningRelPaths.length}
              studioToolMode={studioToolMode}
              onSetStudioToolMode={setStudioToolMode}
              onStudioExport={() => {
                if (videoStudioRef.current?.handleExecuteMerge) {
                  videoStudioRef.current.handleExecuteMerge(false);
                }
              }}
              onSave={() => {
                if (studioLayoutRef.current?.saveConfig) {
                  studioLayoutRef.current.saveConfig();
                }
              }}
              onExport={() => {
                if (studioLayoutRef.current?.exportTranslate) {
                  studioLayoutRef.current.exportTranslate();
                } else if (currentVideo) {
                  const stem = currentVideo.name.replace(/\.[^/.]+$/, '').replace(/_vi$/, '');
                  setRunningRelPaths(prev => Array.from(new Set([...prev, currentVideo.relPath, stem])));
                  runScript('main.py', ['translate', currentVideo.relPath, '--voice'], `trans_${stem}`);
                }
              }}
              onExportOcrOnly={() => {
                if (studioLayoutRef.current?.exportOcrOnly) {
                  studioLayoutRef.current.exportOcrOnly();
                } else if (currentVideo) {
                  const stem = currentVideo.name.replace(/\.[^/.]+$/, '').replace(/_vi$/, '');
                  setRunningRelPaths(prev => Array.from(new Set([...prev, currentVideo.relPath, stem])));
                  runScript('main.py', ['translate', currentVideo.relPath, '--ocr-only'], `ocr_${stem}`);
                }
              }}
              onResume={() => {
                if (studioLayoutRef.current?.resume) {
                  studioLayoutRef.current.resume();
                } else if (currentVideo) {
                  const stem = currentVideo.name.replace(/\.[^/.]+$/, '').replace(/_vi$/, '');
                  setRunningRelPaths(prev => Array.from(new Set([...prev, currentVideo.relPath, stem, `job_${stem}`])));
                  runScript('main.py', ['resume', `${activeProject}:job_${stem}`], `resume_${stem}`);
                }
              }}
              onDownload={() => {
                const out = (videos.outputFiles || [])[0] || currentVideo;
                if (out) {
                  window.open(`http://localhost:3001/api/media?path=${encodeURIComponent(out.relPath)}`, '_blank');
                }
              }}
              onUploadCloud={() => {
                if (currentVideo) {
                  syncUpToCloud(activeProject, [currentVideo.name]);
                }
              }}
              onDelete={async () => {
                if (!currentVideo) return;
                const fname = currentVideo.name || currentVideo.relPath.split('/').pop();
                const ok = await confirm({
                  title: 'Xác nhận xóa vĩnh viễn video?',
                  message: `Bạn có chắc chắn muốn xóa video "${fname}"? File trên SSD và toàn bộ dữ liệu workspace cache sẽ bị xóa hoàn toàn.`,
                  confirmText: 'Xóa Vĩnh Viễn',
                  type: 'danger'
                });
                if (!ok) return;

                try {
                  await deleteFile(currentVideo.relPath);
                  setSelectedVideo(null);
                  await new Promise(r => setTimeout(r, 200));
                  handleRefresh();
                } catch (e) {
                  showAlert({
                    title: 'Lỗi Xóa File',
                    message: 'Lỗi khi xóa: ' + e.message,
                    type: 'danger'
                  });
                }
              }}
              onOpenConfig={() => setActiveTab('config')}
              onOpenStudio={() => setActiveTab('studio')}
              onOpenDownloader={() => setActiveTab('downloader')}
              onRefresh={handleRefresh}
              theme={theme}
              onToggleTheme={handleToggleTheme}
            />
          );
        })()}

        {/* Tab 1: Video Editor (All-in-One Studio Canvas) */}
        <div style={{ display: activeTab === 'editor' ? 'flex' : 'none', flex: 1, height: 'calc(100vh - 56px)', overflow: 'hidden' }}>
          <VideoStudioLayout
            ref={studioLayoutRef}
            project={activeProject}
            videos={videos}
            runningRelPaths={runningRelPaths}
            setRunningRelPaths={setRunningRelPaths}
            globalLogs={globalLogs}
            onClearLogs={() => setGlobalLogs([])}
            onRefresh={handleRefresh}
            onOpenStudioModal={handleOpenStudio}
            onOpenDownloaderModal={() => setActiveTab('downloader')}
            onOpenConfigDrawer={() => setActiveTab('config')}
            libraryFilter={libraryFilter}
            playerRef={playerRef}
            selectedVideo={selectedVideo}
            onSelectVideo={setSelectedVideo}
          />
        </div>

        {/* Tab 2: Dedicated Video Studio (Merge & Multi-Cut) */}
        <div style={{ display: activeTab === 'studio' ? 'flex' : 'none', flex: 1, height: 'calc(100vh - 56px)', overflow: 'hidden' }}>
          <VideoStudio
            ref={videoStudioRef}
            project={activeProject}
            srcFiles={videos.srcFiles}
            cutFiles={videos.cutFiles}
            mergeFiles={videos.mergeFiles}
            outputFiles={videos.outputFiles}
            studioToolMode={studioToolMode}
            onSetStudioToolMode={setStudioToolMode}
            onSelectTab={setActiveTab}
            onRefresh={handleRefresh}
          />
        </div>

        {/* Tab 3: Douyin Downloader */}
        <div style={{ display: activeTab === 'downloader' ? 'flex' : 'none', flex: 1, height: 'calc(100vh - 56px)', overflow: 'hidden' }}>
          <DouyinDownloader
            project={activeProject}
            onRefresh={handleRefresh}
          />
        </div>

        {/* Tab 4: Config Editor */}
        <div style={{ display: activeTab === 'config' ? 'flex' : 'none', flex: 1, height: 'calc(100vh - 56px)', overflow: 'hidden' }}>
          <ConfigEditor
            project={activeProject}
            isActive={activeTab === 'config'}
            onRefresh={handleRefresh}
          />
        </div>

        {/* Tab 5: Process Logs */}
        <div style={{ display: activeTab === 'logs' ? 'flex' : 'none', flex: 1, height: 'calc(100vh - 56px)', overflow: 'hidden' }}>
          <LogConsole
            logs={globalLogs}
            onClear={() => setGlobalLogs([])}
          />
        </div>

        {/* Tab 6: Google Cloud Storage (GCS) Manager */}
        <div style={{ display: activeTab === 'cloud' ? 'flex' : 'none', flex: 1, height: 'calc(100vh - 56px)', overflow: 'hidden' }}>
          <GoogleCloudStorage
            project={activeProject}
            projects={projects}
            onSelectProject={setActiveProject}
            onRefresh={handleRefresh}
          />
        </div>
      </div>
    </div>
  );
}

export default function App() {
  return (
    <ConfirmProvider>
      <MainApp />
    </ConfirmProvider>
  );
}

