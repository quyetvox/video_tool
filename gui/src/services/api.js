const API_BASE = 'http://localhost:3001/api';

export async function fetchProjects() {
  const res = await fetch(`${API_BASE}/projects`);
  return res.json();
}

export async function createProject(name) {
  const res = await fetch(`${API_BASE}/projects`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ name })
  });
  return res.json();
}

export async function fetchProjectVideos(projectName) {
  const res = await fetch(`${API_BASE}/projects/${projectName}/videos`);
  return res.json();
}

export async function fetchProjectConfig(projectName) {
  const res = await fetch(`${API_BASE}/projects/${projectName}/config`);
  return res.json();
}

export async function saveProjectConfig(projectName, content) {
  const res = await fetch(`${API_BASE}/projects/${projectName}/config`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ content })
  });
  return res.json();
}

export async function fetchFileContent(relPath) {
  const res = await fetch(`${API_BASE}/file-content?path=${encodeURIComponent(relPath)}`);
  return res.json();
}

export async function saveFileContent(relPath, content) {
  const res = await fetch(`${API_BASE}/file-content`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ path: relPath, content })
  });
  return res.json();
}

export async function stopProcess(jobId) {
  const res = await fetch(`${API_BASE}/exec/stop`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ jobId })
  });
  return res.json();
}

export async function renameFile(oldPath, newName) {
  const res = await fetch(`${API_BASE}/rename-file`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ oldPath, newName })
  });
  return res.json();
}

export async function deleteFile(relPath) {
  const res = await fetch(`${API_BASE}/delete-file`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ path: relPath })
  });
  return res.json();
}

export async function fetchWorkspaceJobFiles(projectName, jobId) {
  const res = await fetch(`${API_BASE}/projects/${projectName}/workspace/${jobId}`);
  return res.json();
}

export async function deleteWorkspaceJob(projectName, jobId) {
  const res = await fetch(`${API_BASE}/projects/${projectName}/workspace/${jobId}`, {
    method: 'DELETE'
  });
  return res.json();
}

export async function deleteStepCache(projectName, jobId, stepId) {
  const res = await fetch(`${API_BASE}/projects/${projectName}/workspace/${jobId}/steps/${stepId}`, {
    method: 'DELETE'
  });
  return res.json();
}

/**
 * runScript: Start a Python script via the backend, then wait for the SSE
 * exit event so the caller's `await runScript(...)` resolves only when the
 * Python process actually finishes (not just when it was launched).
 *
 * We open the SSE connection BEFORE posting to /exec/run to eliminate the
 * race condition where a very fast script could exit before we subscribe.
 */
export function runScript(script, args, jobId) {
  return new Promise(async (resolve, reject) => {
    try {
      const actualJobId = jobId || `job_${Date.now()}`;
      let settled = false;
      let pollInterval = null;

      // Subscribe to jobId-specific SSE channel (which receives targeted events)
      const es = new EventSource(`${API_BASE}/exec/stream?jobId=${encodeURIComponent(actualJobId)}`);

      const finish = (result) => {
        if (settled) return;
        settled = true;
        if (pollInterval) clearInterval(pollInterval);
        try { es.close(); } catch (e) {}
        resolve(result);
      };

      es.addEventListener('exit', (event) => {
        try {
          const data = JSON.parse(event.data);
          finish(data);
        } catch {
          finish({ success: true });
        }
      });

      // Polling fallback every 500ms to guarantee instant resolution even if SSE drops
      pollInterval = setInterval(async () => {
        try {
          const statusRes = await fetch(`${API_BASE}/exec/status?jobId=${encodeURIComponent(actualJobId)}`);
          if (statusRes.ok) {
            const statusData = await statusRes.json();
            if (statusData.finished) {
              finish(statusData.result || { success: true });
            }
          }
        } catch (e) {}
      }, 500);

      // Safety timeout (3 hours max)
      setTimeout(() => finish({ timeout: true }), 3 * 60 * 60 * 1000);

      // Start the python process
      const res = await fetch(`${API_BASE}/exec/run`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ script, args, jobId: actualJobId })
      });

      if (!res.ok) {
        finish({ error: `HTTP error ${res.status}` });
      }
    } catch (err) {
      reject(err);
    }
  });
}

export function getMediaUrl(relPath, version = null) {
  if (!relPath) return '';
  const clean = encodeURIComponent(relPath);
  return version ? `${API_BASE}/media?path=${clean}&v=${version}` : `${API_BASE}/media?path=${clean}`;
}

export function subscribeLogs(jobId, onLog, onExit, onStart) {
  const channel = jobId || 'global';
  const eventSource = new EventSource(`${API_BASE}/exec/stream?jobId=${encodeURIComponent(channel)}`);
  
  eventSource.addEventListener('start', (event) => {
    const data = JSON.parse(event.data);
    if (onStart) onStart(data);
  });

  eventSource.addEventListener('log', (event) => {
    const data = JSON.parse(event.data);
    if (onLog) onLog(data);
  });

  eventSource.addEventListener('exit', (event) => {
    const data = JSON.parse(event.data);
    if (onExit) onExit(data);
  });

  return () => {
    eventSource.close();
  };
}

export async function fetchStorageStatus(projectName) {
  const res = await fetch(`${API_BASE}/storage/status?project=${encodeURIComponent(projectName || 'default')}`);
  return res.json();
}

export async function fetchStorageBrowse(path = '') {
  const res = await fetch(`${API_BASE}/storage/browse?path=${encodeURIComponent(path || '')}`);
  return res.json();
}

export async function syncDownFromCloud(projectName, files = null, jobId = null) {
  const args = ['sync-down', projectName || 'default'];
  if (files && files.length > 0) {
    args.push('--files', ...files);
  }
  return runScript('storage.py', args, jobId || `sync_down_${Date.now()}`);
}

export async function syncUpToCloud(projectName, files = null, jobId = null) {
  const args = ['sync-up', projectName || 'default'];
  if (files && files.length > 0) {
    args.push('--files', ...files);
  }
  return runScript('storage.py', args, jobId || `sync_up_${Date.now()}`);
}

export async function offloadLocalFiles(projectName, files = null, jobId = null) {
  const args = ['offload', projectName || 'default'];
  if (files && files.length > 0) {
    args.push('--files', ...files);
  }
  return runScript('storage.py', args, jobId || `offload_${Date.now()}`);
}

export async function deleteCloudFiles(projectName, files, jobId = null) {
  const args = ['delete-cloud', projectName || 'default', '--files', ...files];
  return runScript('storage.py', args, jobId || `del_cloud_${Date.now()}`);
}

export async function deleteLocalFile(projectName, filePath) {
  const res = await fetch(`${API_BASE}/delete-file`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ project: projectName, path: filePath })
  });
  if (!res.ok) {
    const err = await res.json().catch(() => ({}));
    throw new Error(err.error || 'Xóa tệp local thất bại');
  }
  return res.json();
}

export async function refreshStorageCache(projectName) {
  const res = await fetch(`${API_BASE}/storage/refresh`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ project: projectName || 'default' })
  });
  return res.json();
}

export async function checkVideoCompatibility(videoPaths = []) {
  const res = await fetch(`${API_BASE}/media/check-compatibility`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ videoPaths })
  });
  if (!res.ok) {
    const err = await res.json().catch(() => ({}));
    throw new Error(err.error || 'Kiểm tra tương thích thất bại');
  }
  return res.json();
}

export async function suggestConcatName(inputPath) {
  const res = await fetch(`${API_BASE}/suggest-concat-name`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ inputPath })
  });
  return res.json();
}

export async function uploadAsset(project, fileName, fileData, folder = 'src') {
  const res = await fetch(`${API_BASE}/upload-asset`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ project, fileName, fileData, folder })
  });
  if (!res.ok) {
    const err = await res.json().catch(() => ({}));
    throw new Error(err.error || 'Upload asset thất bại');
  }
  return res.json();
}

export function getProxyMediaUrl(url) {
  if (!url) return '';
  return `http://localhost:3001/api/proxy-media?url=${encodeURIComponent(url)}`;
}

