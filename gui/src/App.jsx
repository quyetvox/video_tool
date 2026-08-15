import React, { useState, useEffect, useRef } from 'react';
import Sidebar from './components/Sidebar';
import Dashboard from './components/Dashboard';
import VideoTrimmer from './components/VideoTrimmer';
import VideoStudio from './components/VideoStudio';
import DouyinDownloader from './components/DouyinDownloader';
import ConfigEditor from './components/ConfigEditor';
import LogConsole from './components/LogConsole';
import { fetchProjects, createProject, fetchProjectVideos, subscribeLogs } from './services/api';

export default function App() {
  const [projects, setProjects] = useState([]);
  const [activeProject, setActiveProject] = useState('');
  const [activeTab, setActiveTab] = useState('dashboard');
  const [videos, setVideos] = useState({ srcFiles: [], outputFiles: [], workspaceJobs: [] });
  const [trimmerTarget, setTrimmerTarget] = useState(null);

  // ── Global processing & log store (lifted up so state persists across tab switches) ──────
  const [globalLogs, setGlobalLogs] = useState([]);
  const [runningRelPaths, setRunningRelPaths] = useState([]);

  // Subscribe to SSE "global" channel ONCE at app mount — never unmount this
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
          const stem = exitData.jobId.replace(/^job_/, '').replace(/^trans_/, '').replace(/^resume_/, '').replace(/^batch_sel_/, '').replace(/^batch_/, '');
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
          const videoArg = startData.args.find(a => typeof a === 'string' && (a.includes('assets/') || a.startsWith('job_') || a.includes('.mp4')));
          if (videoArg) {
            const base = videoArg.split('/').pop();
            const stem = base.replace(/^job_/, '').replace(/_vi\.[^/.]+$|\.[^/.]+$/, '');
            setRunningRelPaths(prev => Array.from(new Set([...prev, videoArg, stem, `job_${stem}`])));
          }
        }
      }
    );
    return () => unsubscribe();
  }, [activeProject]);

  useEffect(() => {
    loadProjectsData();
  }, []);

  useEffect(() => {
    if (activeProject) {
      loadProjectVideos(activeProject);
    }
  }, [activeProject]);

  const loadProjectsData = async () => {
    try {
      const data = await fetchProjects();
      const list = data.projects || [];
      setProjects(list);
      if (list.length > 0 && !activeProject) {
        // Select xujing by default if available, else first
        const defaultProj = list.find(p => p.name === 'xujing') || list[0];
        setActiveProject(defaultProj.name);
      }
    } catch (e) {
      console.error('Failed to fetch projects:', e);
    }
  };

  const loadProjectVideos = async (projName) => {
    try {
      const data = await fetchProjectVideos(projName);
      setVideos({
        srcFiles: data.srcFiles || [],
        outputFiles: data.outputFiles || [],
        workspaceJobs: data.workspaceJobs || []
      });
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

  const handleOpenTrimmer = (relPath) => {
    setTrimmerTarget(relPath);
    setActiveTab('studio');
  };

  const handleRefresh = () => {
    loadProjectsData();
    if (activeProject) {
      loadProjectVideos(activeProject);
    }
  };

  return (
    <div style={{ display: 'flex', width: '100vw', height: '100vh', backgroundColor: '#0f172a' }}>
      <Sidebar
        projects={projects}
        activeProject={activeProject}
        onSelectProject={setActiveProject}
        onCreateProject={handleCreateProject}
        activeTab={activeTab}
        onSelectTab={setActiveTab}
      />

      <main style={{ flex: 1, display: 'flex', flexDirection: 'column', height: '100vh', overflow: 'hidden' }}>
        <div style={{ display: activeTab === 'dashboard' ? 'flex' : 'none', flex: 1, height: '100%', overflow: 'hidden' }}>
          <Dashboard
            project={activeProject}
            videos={videos}
            runningRelPaths={runningRelPaths}
            setRunningRelPaths={setRunningRelPaths}
            globalLogs={globalLogs}
            onClearLogs={() => setGlobalLogs([])}
            onRefresh={handleRefresh}
            onOpenTrimmer={handleOpenTrimmer}
            onSelectTab={setActiveTab}
          />
        </div>

        <div style={{ display: activeTab === 'studio' ? 'flex' : 'none', flex: 1, height: '100%', overflow: 'hidden' }}>
          <VideoStudio
            project={activeProject}
            srcFiles={videos.srcFiles}
            outputFiles={videos.outputFiles}
            initialTrimmerPath={trimmerTarget}
            initialSubTab={trimmerTarget ? 'multicut' : 'merge'}
            onSelectTab={setActiveTab}
            onRefresh={handleRefresh}
          />
        </div>

        <div style={{ display: activeTab === 'downloader' ? 'flex' : 'none', flex: 1, height: '100%', overflow: 'hidden' }}>
          <DouyinDownloader
            project={activeProject}
            onSelectTab={setActiveTab}
            onRefresh={handleRefresh}
          />
        </div>

        <div style={{ display: activeTab === 'config' ? 'flex' : 'none', flex: 1, height: '100%', overflow: 'hidden' }}>
          <ConfigEditor project={activeProject} />
        </div>

        {/* LogConsole always mounted but hidden when not active so SSE is now managed in App */}
        <div style={{ display: activeTab === 'logs' ? 'flex' : 'none', flex: 1, height: '100%', overflow: 'hidden' }}>
          <LogConsole
            logs={globalLogs}
            isProcessRunning={runningRelPaths.length > 0}
            onClearLogs={() => setGlobalLogs([])}
          />
        </div>
      </main>
    </div>
  );
}
