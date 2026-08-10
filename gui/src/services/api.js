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

      // Subscribe to global SSE channel which receives ALL execution events
      const es = new EventSource(`${API_BASE}/exec/stream?jobId=global`);

      const finish = (result) => {
        if (settled) return;
        settled = true;
        es.close();
        resolve(result);
      };

      es.addEventListener('exit', (event) => {
        try {
          finish(JSON.parse(event.data));
        } catch {
          finish({ success: true });
        }
      });

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

export function getMediaUrl(relPath) {
  return `${API_BASE}/media?path=${encodeURIComponent(relPath)}`;
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
