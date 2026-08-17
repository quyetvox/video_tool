import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { spawn, spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const ROOT_DIR = path.resolve(__dirname, '..');
const ASSETS_DIR = path.join(ROOT_DIR, 'assets');
const VENV_PYTHON = path.join(ROOT_DIR, '.venv', 'bin', 'python');
const PYTHON_BIN = fs.existsSync(VENV_PYTHON) ? VENV_PYTHON : 'python3';

const PORT = process.env.PORT || 3001;

// Active streaming clients for SSE
const sseClients = new Map(); // jobId -> Set of res objects
const activeProcesses = new Map(); // jobId -> ChildProcess object
const finishedJobs = new Map(); // jobId -> { code, success, error, time }

process.on('uncaughtException', (err) => {
  console.warn('⚠️ Server uncaughtException safely handled:', err.message);
});
process.on('unhandledRejection', (reason) => {
  console.warn('⚠️ Server unhandledRejection safely handled:', reason);
});

function killProcessGroup(proc, signal = 'SIGINT') {
  if (!proc || !proc.pid) return;
  try {
    if (process.platform !== 'win32') {
      process.kill(-proc.pid, signal);
    } else {
      proc.kill(signal);
    }
  } catch (e) {
    try { proc.kill(signal); } catch (err) {}
  }
}

function sendSSE(jobId, type, data) {
  const payload = `event: ${type}\ndata: ${JSON.stringify(data)}\n\n`;

  // Send to jobId-specific clients
  const targetClients = sseClients.get(jobId);
  if (targetClients) {
    for (const res of targetClients) {
      try { res.write(payload); } catch (e) {}
    }
  }

  // Also broadcast to global clients
  const globalClients = sseClients.get('global');
  if (globalClients && jobId !== 'global') {
    for (const res of globalClients) {
      try { res.write(payload); } catch (e) {}
    }
  }
}

function parseJsonBody(req) {
  return new Promise((resolve, reject) => {
    let body = '';
    req.on('data', chunk => { body += chunk; });
    req.on('end', () => {
      try {
        resolve(body ? JSON.parse(body) : {});
      } catch (err) {
        reject(err);
      }
    });
    req.on('error', reject);
  });
}

const server = http.createServer(async (req, res) => {
  // CORS Headers
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

  if (req.method === 'OPTIONS') {
    res.writeHead(204);
    res.end();
    return;
  }

  const url = new URL(req.url, `http://localhost:${PORT}`);
  const pathname = url.pathname;

  try {
    // 1. GET /api/projects -> List projects in assets/
    if (req.method === 'GET' && pathname === '/api/projects') {
      if (!fs.existsSync(ASSETS_DIR)) {
        res.writeHead(200, { 'Content-Type': 'application/json' });
        return res.end(JSON.stringify({ projects: [] }));
      }
      const entries = fs.readdirSync(ASSETS_DIR, { withFileTypes: true });
      const projects = entries
        .filter(e => e.isDirectory() && !e.name.startsWith('.'))
        .map(e => {
          const projPath = path.join(ASSETS_DIR, e.name);
          const srcPath = path.join(projPath, 'src');
          const cutPath = path.join(projPath, 'cut');
          const mergePath = path.join(projPath, 'merge');
          const outPath = path.join(projPath, 'output');
          const wsPath = path.join(projPath, 'workspace');
          const hasConfig = fs.existsSync(path.join(projPath, 'config.yaml'));

          const countFiles = (p) => fs.existsSync(p) ? fs.readdirSync(p).filter(f => !f.startsWith('.')).length : 0;

          return {
            name: e.name,
            hasConfig,
            srcCount: countFiles(srcPath),
            cutCount: countFiles(cutPath),
            mergeCount: countFiles(mergePath),
            workspaceCount: countFiles(wsPath),
            outputCount: countFiles(outPath)
          };
        });

      res.writeHead(200, { 'Content-Type': 'application/json' });
      return res.end(JSON.stringify({ projects }));
    }

    // 2. POST /api/projects -> Create new project
    if (req.method === 'POST' && pathname === '/api/projects') {
      const body = await parseJsonBody(req);
      const name = (body.name || '').trim();
      if (!name) {
        res.writeHead(400, { 'Content-Type': 'application/json' });
        return res.end(JSON.stringify({ error: 'Project name is required' }));
      }
      const projDir = path.join(ASSETS_DIR, name);
      if (!fs.existsSync(projDir)) {
        fs.mkdirSync(path.join(projDir, 'src'), { recursive: true });
        fs.mkdirSync(path.join(projDir, 'cut'), { recursive: true });
        fs.mkdirSync(path.join(projDir, 'merge'), { recursive: true });
        fs.mkdirSync(path.join(projDir, 'output'), { recursive: true });
        fs.mkdirSync(path.join(projDir, 'workspace'), { recursive: true });
        // Copy root config.yaml
        const rootConfig = path.join(ROOT_DIR, 'config.yaml');
        if (fs.existsSync(rootConfig)) {
          fs.copyFileSync(rootConfig, path.join(projDir, 'config.yaml'));
        }
      }
      res.writeHead(200, { 'Content-Type': 'application/json' });
      return res.end(JSON.stringify({ success: true, name }));
    }

    // 3. GET /api/projects/:name/videos -> List files in src, cut, merge, output, workspace
    if (req.method === 'GET' && pathname.match(/^\/api\/projects\/([^/]+)\/videos$/)) {
      const projName = pathname.split('/')[3];
      const projDir = path.join(ASSETS_DIR, projName);
      if (!fs.existsSync(projDir)) {
        res.writeHead(404, { 'Content-Type': 'application/json' });
        return res.end(JSON.stringify({ error: 'Project not found' }));
      }

      const listMediaFiles = (subDir) => {
        const target = path.join(projDir, subDir);
        if (!fs.existsSync(target)) return [];
        return fs.readdirSync(target, { withFileTypes: true })
          .filter(e => e.isFile() && !e.name.startsWith('.'))
          .map(e => {
            const filePath = path.join(target, e.name);
            const stats = fs.statSync(filePath);
            const ext = path.extname(e.name).toLowerCase();
            return {
              name: e.name,
              path: filePath,
              relPath: path.relative(ROOT_DIR, filePath),
              folder: subDir,
              size: stats.size,
              sizeBytes: stats.size,
              mtime: stats.mtimeMs,
              mtimeMs: stats.mtimeMs,
              isMedia: /\.(mp4|mkv|mov|webm|avi|mp3|wav)$/i.test(e.name),
              isImage: /\.(png|jpg|jpeg|webp|gif)$/i.test(e.name),
              isJson: ext === '.json',
              isSub: ['.srt', '.ass', '.vtt'].includes(ext),
              isText: ['.txt', '.md', '.yaml', '.yml'].includes(ext)
            };
          });
      };

      res.writeHead(200, { 'Content-Type': 'application/json' });
      return res.end(JSON.stringify({
        project: projName,
        rootFiles: listMediaFiles(''),
        srcFiles: listMediaFiles('src'),
        cutFiles: listMediaFiles('cut'),
        mergeFiles: listMediaFiles('merge'),
        outputFiles: listMediaFiles('output'),
        workspaceJobs: fs.existsSync(path.join(projDir, 'workspace')) 
          ? fs.readdirSync(path.join(projDir, 'workspace')).filter(f => f.startsWith('job_'))
          : []
      }));
    }

    // 4. GET /api/projects/:name/config -> Read config.yaml
    if (req.method === 'GET' && pathname.match(/^\/api\/projects\/([^/]+)\/config$/)) {
      const projName = pathname.split('/')[3];
      const configPath = path.join(ASSETS_DIR, projName, 'config.yaml');
      const fallbackConfig = path.join(ROOT_DIR, 'config.yaml');
      const targetPath = fs.existsSync(configPath) ? configPath : fallbackConfig;
      
      const content = fs.existsSync(targetPath) ? fs.readFileSync(targetPath, 'utf-8') : '';
      res.writeHead(200, { 'Content-Type': 'application/json' });
      return res.end(JSON.stringify({ content, path: targetPath }));
    }

    // 5. POST /api/projects/:name/config -> Write config.yaml
    if (req.method === 'POST' && pathname.match(/^\/api\/projects\/([^/]+)\/config$/)) {
      const projName = pathname.split('/')[3];
      const body = await parseJsonBody(req);
      const configPath = path.join(ASSETS_DIR, projName, 'config.yaml');
      fs.writeFileSync(configPath, body.content || '', 'utf-8');
      res.writeHead(200, { 'Content-Type': 'application/json' });
      return res.end(JSON.stringify({ success: true }));
    }

    // 5b. GET /api/file-content -> Read text/JSON file content
    if (req.method === 'GET' && pathname === '/api/file-content') {
      const fileRelPath = url.searchParams.get('path');
      if (!fileRelPath) {
        res.writeHead(400, { 'Content-Type': 'application/json' });
        return res.end(JSON.stringify({ error: 'Missing path parameter' }));
      }
      const fullPath = path.resolve(ROOT_DIR, fileRelPath);
      if (!fullPath.startsWith(ROOT_DIR) || !fs.existsSync(fullPath)) {
        res.writeHead(404, { 'Content-Type': 'application/json' });
        return res.end(JSON.stringify({ error: 'File not found' }));
      }

      const content = fs.readFileSync(fullPath, 'utf-8');
      res.writeHead(200, { 'Content-Type': 'application/json' });
      return res.end(JSON.stringify({ content, path: fileRelPath }));
    }

    // 5b1. POST /api/file-content -> Write text/JSON file content
    if (req.method === 'POST' && pathname === '/api/file-content') {
      const body = await parseJsonBody(req);
      const { path: fileRelPath, content } = body;
      if (!fileRelPath) {
        res.writeHead(400, { 'Content-Type': 'application/json' });
        return res.end(JSON.stringify({ error: 'Missing path parameter' }));
      }
      const fullPath = path.resolve(ROOT_DIR, fileRelPath);
      if (!fullPath.startsWith(ROOT_DIR)) {
        res.writeHead(403, { 'Content-Type': 'application/json' });
        return res.end(JSON.stringify({ error: 'Forbidden path' }));
      }

      fs.writeFileSync(fullPath, content || '', 'utf-8');
      res.writeHead(200, { 'Content-Type': 'application/json' });
      return res.end(JSON.stringify({ success: true, path: fileRelPath }));
    }

    // 5b2. POST /api/rename-file -> Rename file in src/ or output/
    if (req.method === 'POST' && pathname === '/api/rename-file') {
      const body = await parseJsonBody(req);
      const { oldPath, newName } = body;

      if (!oldPath || !newName) {
        res.writeHead(400, { 'Content-Type': 'application/json' });
        return res.end(JSON.stringify({ error: 'Missing oldPath or newName' }));
      }

      const cleanNewName = path.basename(newName.trim());
      if (!cleanNewName) {
        res.writeHead(400, { 'Content-Type': 'application/json' });
        return res.end(JSON.stringify({ error: 'Invalid new name' }));
      }

      const oldFullPath = path.resolve(ROOT_DIR, oldPath);
      if (!oldFullPath.startsWith(ROOT_DIR) || !fs.existsSync(oldFullPath)) {
        res.writeHead(404, { 'Content-Type': 'application/json' });
        return res.end(JSON.stringify({ error: 'Source file not found' }));
      }

      const parentDir = path.dirname(oldFullPath);
      const newFullPath = path.join(parentDir, cleanNewName);

      if (fs.existsSync(newFullPath) && oldFullPath !== newFullPath) {
        res.writeHead(400, { 'Content-Type': 'application/json' });
        return res.end(JSON.stringify({ error: 'File with this name already exists' }));
      }

      fs.renameSync(oldFullPath, newFullPath);

      const newRelPath = path.relative(ROOT_DIR, newFullPath);
      res.writeHead(200, { 'Content-Type': 'application/json' });
      return res.end(JSON.stringify({ success: true, oldPath, newPath: newRelPath, newName: cleanNewName }));
    }

    // 5b3. POST/DELETE /api/delete-file -> Delete file in src/ or output/
    if ((req.method === 'POST' || req.method === 'DELETE') && pathname === '/api/delete-file') {
      const body = await parseJsonBody(req);
      const fileRelPath = body.path || url.searchParams.get('path');

      if (!fileRelPath) {
        res.writeHead(400, { 'Content-Type': 'application/json' });
        return res.end(JSON.stringify({ error: 'Missing path parameter' }));
      }

      const fullPath = path.resolve(ROOT_DIR, fileRelPath);
      if (!fullPath.startsWith(ROOT_DIR) || !fs.existsSync(fullPath)) {
        res.writeHead(404, { 'Content-Type': 'application/json' });
        return res.end(JSON.stringify({ error: 'File not found' }));
      }

      try {
        fs.unlinkSync(fullPath);

        // Also clean up associated workspace job if present
        const cleanRelPath = fileRelPath.replace(/\\/g, '/');
        const parts = cleanRelPath.split('/');
        if (parts.length >= 3 && parts[0] === 'assets') {
          const proj = parts[1];
          const filename = path.basename(cleanRelPath);
          const stem = filename.replace(/\.[^/.]+$/, '').replace(/_vi$/, '');
          const workspaceDir = path.join(ASSETS_DIR, proj, 'workspace', `job_${stem}`);
          if (fs.existsSync(workspaceDir)) {
            fs.rmSync(workspaceDir, { recursive: true, force: true });
          }
        }

        console.log(`[SERVER] 🗑️ Deleted file: ${fileRelPath}`);
        res.writeHead(200, { 'Content-Type': 'application/json' });
        return res.end(JSON.stringify({ success: true, path: fileRelPath }));
      } catch (err) {
        res.writeHead(500, { 'Content-Type': 'application/json' });
        return res.end(JSON.stringify({ error: err.message }));
      }
    }

    // 5b3b. POST /api/upload-asset -> Upload image overlay or audio file into project assets
    if (req.method === 'POST' && pathname === '/api/upload-asset') {
      try {
        const body = await parseJsonBody(req);
        const { project, fileName, fileData, folder = 'src' } = body;
        if (!project || !fileName || !fileData) {
          res.writeHead(400, { 'Content-Type': 'application/json' });
          return res.end(JSON.stringify({ error: 'Missing project, fileName, or fileData' }));
        }

        const safeFolder = ['src', 'cut', 'merge', 'workspace', 'output'].includes(folder) ? folder : 'src';
        const targetDir = path.join(ASSETS_DIR, project, safeFolder);
        if (!fs.existsSync(targetDir)) {
          fs.mkdirSync(targetDir, { recursive: true });
        }

        // Clean file name
        const cleanName = path.basename(fileName.replace(/[^\w\d._-]/g, '_'));
        const targetFilePath = path.join(targetDir, cleanName);

        // Strip data url prefix if present e.g. "data:image/png;base64,"
        const base64Data = fileData.replace(/^data:[^;]+;base64,/, '');
        const buffer = Buffer.from(base64Data, 'base64');
        fs.writeFileSync(targetFilePath, buffer);

        const relPath = path.relative(ROOT_DIR, targetFilePath);
        console.log(`[SERVER] 📥 Uploaded asset: ${relPath} (${buffer.length} bytes)`);

        res.writeHead(200, { 'Content-Type': 'application/json' });
        return res.end(JSON.stringify({
          success: true,
          fileName: cleanName,
          relPath,
          sizeBytes: buffer.length
        }));
      } catch (err) {
        console.error('[SERVER] Upload asset error:', err);
        res.writeHead(500, { 'Content-Type': 'application/json' });
        return res.end(JSON.stringify({ error: err.message }));
      }
    }

    // 5b4. POST /api/suggest-trim-name -> Get auto-increment non-colliding trim output filename
    if (req.method === 'POST' && pathname === '/api/suggest-trim-name') {
      const body = await parseJsonBody(req);
      const fileRelPath = (body.inputPath || '').trim();
      if (!fileRelPath) {
        res.writeHead(400, { 'Content-Type': 'application/json' });
        return res.end(JSON.stringify({ error: 'Missing inputPath' }));
      }
      const fullPath = path.resolve(ROOT_DIR, fileRelPath);
      if (!fs.existsSync(fullPath)) {
        res.writeHead(404, { 'Content-Type': 'application/json' });
        return res.end(JSON.stringify({ error: 'File not found' }));
      }
      const dir = path.dirname(fullPath);
      const ext = path.extname(fullPath);
      const stem = path.basename(fullPath, ext);

      const files = fs.readdirSync(dir);
      let maxN = 0;
      const regex = new RegExp(`^${stem.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}_cut(?:_(\\d+))?${ext.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}$`, 'i');

      for (const f of files) {
        const m = f.match(regex);
        if (m) {
          if (m[1]) {
            const idx = parseInt(m[1], 10);
            if (idx > maxN) maxN = idx;
          } else {
            if (maxN < 1) maxN = 1;
          }
        }
      }

      const nextN = maxN + 1;
      const suggestedName = `${stem}_cut_${nextN}${ext}`;
      const suggestedFullPath = path.join(dir, suggestedName);
      const suggestedRelPath = path.relative(ROOT_DIR, suggestedFullPath);

      res.writeHead(200, { 'Content-Type': 'application/json' });
      return res.end(JSON.stringify({
        success: true,
        suggestedName,
        suggestedPath: suggestedRelPath
      }));
    }

    // 5b5. POST /api/suggest-concat-name -> Get suggested non-colliding filename for merged video
    if (req.method === 'POST' && pathname === '/api/suggest-concat-name') {
      const body = await parseJsonBody(req);
      const fileRelPath = (body.inputPath || '').trim();
      if (!fileRelPath) {
        res.writeHead(400, { 'Content-Type': 'application/json' });
        return res.end(JSON.stringify({ error: 'Missing inputPath' }));
      }
      const fullPath = path.resolve(ROOT_DIR, fileRelPath);
      let dir = path.join(ASSETS_DIR, 'default', 'merge');
      const cleanRel = path.relative(ROOT_DIR, fullPath).replace(/\\/g, '/');
      const parts = cleanRel.split('/');
      if (parts.length >= 3 && parts[0] === 'assets') {
        dir = path.join(ASSETS_DIR, parts[1], 'merge');
      } else if (fs.existsSync(fullPath)) {
        dir = path.dirname(fullPath);
      }

      const ext = path.extname(fullPath) || '.mp4';
      const stem = fs.existsSync(fullPath) ? path.basename(fullPath, ext) : 'merged';

      if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
      const files = fs.readdirSync(dir);
      let maxN = 0;
      const regex = new RegExp(`^${stem.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}_merged(?:_(\\d+))?${ext.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}$`, 'i');

      for (const f of files) {
        const m = f.match(regex);
        if (m) {
          if (m[1]) {
            const idx = parseInt(m[1], 10);
            if (idx > maxN) maxN = idx;
          } else {
            if (maxN < 1) maxN = 1;
          }
        }
      }

      const nextN = maxN + 1;
      const suggestedName = `${stem}_merged_${nextN}${ext}`;
      const suggestedFullPath = path.join(dir, suggestedName);
      const suggestedRelPath = path.relative(ROOT_DIR, suggestedFullPath);

      res.writeHead(200, { 'Content-Type': 'application/json' });
      return res.end(JSON.stringify({
        success: true,
        suggestedName,
        suggestedPath: suggestedRelPath
      }));
    }

    // 5b6. POST /api/media/check-compatibility -> Probe and compare video specifications
    if (req.method === 'POST' && pathname === '/api/media/check-compatibility') {
      const body = await parseJsonBody(req);
      const paths = (body.videoPaths || []).filter(Boolean);
      if (!paths.length) {
        res.writeHead(400, { 'Content-Type': 'application/json' });
        return res.end(JSON.stringify({ error: 'Missing videoPaths array' }));
      }

      const pythonCode = `
import json, sys
from pathlib import Path
import utils.concat_utils as cu

paths = [Path(p).resolve() for p in json.loads(sys.argv[1])]
result = cu.check_video_compatibility(paths)
print(json.dumps(result))
`;

      const pyProcess = spawn(PYTHON_BIN, ['-c', pythonCode, JSON.stringify(paths)], {
        cwd: ROOT_DIR,
        env: { ...process.env, PYTHONPATH: path.join(ROOT_DIR, 'lib') }
      });

      let stdoutData = '';
      let stderrData = '';
      pyProcess.stdout.on('data', d => { stdoutData += d; });
      pyProcess.stderr.on('data', d => { stderrData += d; });

      pyProcess.on('close', code => {
        if (code === 0) {
          try {
            const data = JSON.parse(stdoutData.trim());
            res.writeHead(200, { 'Content-Type': 'application/json' });
            return res.end(JSON.stringify({ success: true, ...data }));
          } catch (e) {
            res.writeHead(500, { 'Content-Type': 'application/json' });
            return res.end(JSON.stringify({ error: 'Failed to parse compatibility output', raw: stdoutData }));
          }
        } else {
          res.writeHead(500, { 'Content-Type': 'application/json' });
          return res.end(JSON.stringify({ error: stderrData || 'Compatibility check failed' }));
        }
      });
      return;
    }

    // 5c. GET /api/projects/:name/workspace/:jobId -> Recursive scan files inside workspace job directory
    if (req.method === 'GET' && pathname.match(/^\/api\/projects\/([^/]+)\/workspace\/([^/]+)$/)) {
      const parts = pathname.split('/');
      const projName = parts[3];
      const jobId = parts[5];
      const jobDir = path.join(ASSETS_DIR, projName, 'workspace', jobId);

      if (!fs.existsSync(jobDir)) {
        res.writeHead(404, { 'Content-Type': 'application/json' });
        return res.end(JSON.stringify({ error: 'Job workspace not found' }));
      }

      const getAllFilesRecursively = (dir) => {
        let results = [];
        const list = fs.readdirSync(dir, { withFileTypes: true });
        list.forEach(item => {
          if (item.name.startsWith('.')) return;
          const fullPath = path.join(dir, item.name);
          if (item.isDirectory()) {
            results = results.concat(getAllFilesRecursively(fullPath));
          } else if (item.isFile()) {
            const stat = fs.statSync(fullPath);
            const relPath = path.relative(ROOT_DIR, fullPath);
            const ext = path.extname(item.name).toLowerCase();
            const relToJob = path.relative(jobDir, fullPath);

            results.push({
              name: relToJob,
              basename: item.name,
              relPath,
              sizeBytes: stat.size,
              mtime: stat.mtimeMs,
              isMedia: ['.mp4', '.mkv', '.mov', '.webm'].includes(ext),
              isAudio: ['.wav', '.mp3', '.flac', '.aac'].includes(ext),
              isImage: ['.png', '.jpg', '.jpeg', '.webp', '.gif'].includes(ext),
              isJson: ext === '.json',
              isSub: ['.srt', '.ass', '.vtt'].includes(ext),
              isText: ['.txt', '.md', '.yaml', '.yml', '.log'].includes(ext)
            });
          }
        });
        return results;
      };

      const files = getAllFilesRecursively(jobDir);
      res.writeHead(200, { 'Content-Type': 'application/json' });
      return res.end(JSON.stringify({ jobId, files }));
    }

    // 5d. DELETE /api/projects/:name/workspace/:jobId/steps/:stepId -> Delete step cache
    if (req.method === 'DELETE' && pathname.match(/^\/api\/projects\/([^/]+)\/workspace\/([^/]+)\/steps\/([^/]+)$/)) {
      const parts = pathname.split('/');
      const projName = parts[3];
      const jobId = parts[5];
      const stepId = parts[7];

      const scriptPath = path.join(ROOT_DIR, 'main.py');
      const pyProc = spawnSync(PYTHON_BIN, [scriptPath, 'delete-step', `${projName}:${jobId}`, stepId], {
        cwd: ROOT_DIR,
        encoding: 'utf-8'
      });

      if (pyProc.status === 0) {
        res.writeHead(200, { 'Content-Type': 'application/json' });
        return res.end(JSON.stringify({ success: true, message: pyProc.stdout }));
      } else {
        res.writeHead(500, { 'Content-Type': 'application/json' });
        return res.end(JSON.stringify({ error: pyProc.stderr || pyProc.stdout || 'Failed to delete step' }));
      }
    }

    // 5e. DELETE /api/projects/:name/workspace/:jobId -> Delete entire job workspace
    if (req.method === 'DELETE' && pathname.match(/^\/api\/projects\/([^/]+)\/workspace\/([^/]+)$/)) {
      const parts = pathname.split('/');
      const projName = parts[3];
      const jobId = parts[5];

      const scriptPath = path.join(ROOT_DIR, 'main.py');
      const pyProc = spawnSync(PYTHON_BIN, [scriptPath, 'delete-job', `${projName}:${jobId}`], {
        cwd: ROOT_DIR,
        encoding: 'utf-8'
      });

      if (pyProc.status === 0) {
        res.writeHead(200, { 'Content-Type': 'application/json' });
        return res.end(JSON.stringify({ success: true, message: pyProc.stdout }));
      } else {
        res.writeHead(500, { 'Content-Type': 'application/json' });
        return res.end(JSON.stringify({ error: pyProc.stderr || pyProc.stdout || 'Failed to delete job' }));
      }
    }

    // 5f. GET /api/storage/status -> Get Cloud Storage sync status and file comparison
    if (req.method === 'GET' && pathname === '/api/storage/status') {
      const projName = url.searchParams.get('project') || 'default';
      const pyCode = `import json; from lib.utils.storage_manager import StorageManager; print(json.dumps(StorageManager('${projName}').get_status()))`;
      const pyProc = spawnSync(PYTHON_BIN, ['-c', pyCode], {
        cwd: ROOT_DIR,
        encoding: 'utf-8'
      });

      if (pyProc.status === 0) {
        try {
          const data = JSON.parse(pyProc.stdout.trim());
          res.writeHead(200, { 'Content-Type': 'application/json' });
          return res.end(JSON.stringify(data));
        } catch (err) {
          res.writeHead(500, { 'Content-Type': 'application/json' });
          return res.end(JSON.stringify({ error: 'Failed to parse storage status JSON', raw: pyProc.stdout }));
        }
      } else {
        res.writeHead(500, { 'Content-Type': 'application/json' });
        return res.end(JSON.stringify({ error: pyProc.stderr || 'Failed to query storage status' }));
      }
    }

    // 5f2. GET /api/storage/browse -> Browse Cloud Storage hierarchically
    if (req.method === 'GET' && pathname === '/api/storage/browse') {
      const browsePath = url.searchParams.get('path') || '';
      const safePath = browsePath.replace(/'/g, "\\'");
      const pyCode = `import json; from lib.utils.storage_manager import StorageManager; print(json.dumps(StorageManager().browse('${safePath}')))`;
      const pyProc = spawnSync(PYTHON_BIN, ['-c', pyCode], {
        cwd: ROOT_DIR,
        encoding: 'utf-8'
      });

      if (pyProc.status === 0) {
        try {
          const data = JSON.parse(pyProc.stdout.trim());
          res.writeHead(200, { 'Content-Type': 'application/json' });
          return res.end(JSON.stringify(data));
        } catch (err) {
          res.writeHead(500, { 'Content-Type': 'application/json' });
          return res.end(JSON.stringify({ error: 'Failed to parse browse JSON', raw: pyProc.stdout }));
        }
      } else {
        res.writeHead(500, { 'Content-Type': 'application/json' });
        return res.end(JSON.stringify({ error: pyProc.stderr || 'Failed to browse storage' }));
      }
    }

    // 5g. POST /api/storage/refresh -> Refresh VFS mount cache on demand
    if (req.method === 'POST' && pathname === '/api/storage/refresh') {
      const body = await parseJsonBody(req);
      const projName = body.project || 'default';
      const pyCode = `import json; from lib.utils.storage_manager import StorageManager; print(json.dumps(StorageManager('${projName}').refresh_mount()))`;
      const pyProc = spawnSync(PYTHON_BIN, ['-c', pyCode], {
        cwd: ROOT_DIR,
        encoding: 'utf-8'
      });

      if (pyProc.status === 0) {
        try {
          const data = JSON.parse(pyProc.stdout.trim());
          res.writeHead(200, { 'Content-Type': 'application/json' });
          return res.end(JSON.stringify(data));
        } catch (err) {
          res.writeHead(200, { 'Content-Type': 'application/json' });
          return res.end(JSON.stringify({ success: true }));
        }
      } else {
        res.writeHead(500, { 'Content-Type': 'application/json' });
        return res.end(JSON.stringify({ error: pyProc.stderr || 'Failed to refresh storage mount' }));
      }
    }

    // 6. Streaming Media File for HTML5 Video Preview (Range Request Supported)
    if (req.method === 'GET' && pathname === '/api/media') {
      const fileRelPath = url.searchParams.get('path');
      if (!fileRelPath) {
        res.writeHead(400);
        return res.end('Missing path parameter');
      }
      const fullPath = path.resolve(ROOT_DIR, fileRelPath);
      if (!fullPath.startsWith(ROOT_DIR) || !fs.existsSync(fullPath)) {
        res.writeHead(404);
        return res.end('File not found');
      }

      const stat = fs.statSync(fullPath);
      const fileSize = stat.size;
      const range = req.headers.range;

      const ext = path.extname(fullPath).toLowerCase();
      const mimeTypes = {
        '.mp4': 'video/mp4',
        '.webm': 'video/webm',
        '.mkv': 'video/x-matroska',
        '.mov': 'video/quicktime',
        '.mp3': 'audio/mpeg',
        '.wav': 'audio/wav',
        '.png': 'image/png',
        '.jpg': 'image/jpeg',
        '.srt': 'text/plain'
      };
      const contentType = mimeTypes[ext] || 'application/octet-stream';

      if (range) {
        const parts = range.replace(/bytes=/, "").split("-");
        const start = parseInt(parts[0], 10);
        const end = Math.min(parts[1] ? parseInt(parts[1], 10) : fileSize - 1, fileSize - 1);
        if (isNaN(start) || start > end || start >= fileSize) {
          res.writeHead(416, { 'Content-Range': `bytes */${fileSize}` });
          res.end();
          return;
        }
        const chunksize = (end - start) + 1;
        const file = fs.createReadStream(fullPath, { start, end });
        const head = {
          'Content-Range': `bytes ${start}-${end}/${fileSize}`,
          'Accept-Ranges': 'bytes',
          'Content-Length': chunksize,
          'Content-Type': contentType,
        };
        res.writeHead(206, head);
        file.pipe(res);
      } else {
        const head = {
          'Content-Length': fileSize,
          'Content-Type': contentType,
        };
        res.writeHead(200, head);
        fs.createReadStream(fullPath).pipe(res);
      }
      return;
    }

    // 6b. Proxy Live Douyin / Remote CDN Video Preview (Bypass Referer & CORS)
    if (req.method === 'GET' && pathname === '/api/proxy-media') {
      const targetUrl = url.searchParams.get('url');
      if (!targetUrl || !targetUrl.startsWith('http')) {
        res.writeHead(400);
        return res.end('Missing or invalid target URL');
      }

      const clientHeaders = {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
        'Referer': 'https://www.douyin.com/',
        'Accept': '*/*',
        'Accept-Encoding': 'identity',
        'Connection': 'keep-alive'
      };
      if (req.headers.range) {
        clientHeaders['Range'] = req.headers.range;
      }

      try {
        const response = await fetch(targetUrl, {
          headers: clientHeaders,
          redirect: 'follow'
        });

        const status = response.status === 206 ? 206 : (response.ok ? 200 : response.status);
        const responseHeaders = {
          'Access-Control-Allow-Origin': '*',
          'Content-Type': response.headers.get('content-type') || 'video/mp4',
          'Accept-Ranges': 'bytes'
        };

        if (response.headers.get('content-range')) {
          responseHeaders['Content-Range'] = response.headers.get('content-range');
        }
        const { Readable, pipeline } = await import('node:stream');
        if (response.body) {
          const stream = Readable.fromWeb(response.body);
          stream.on('error', () => {});
          res.on('error', () => {});
          pipeline(stream, res, () => {});
        } else {
          res.end();
        }
      } catch (err) {
        if (!res.headersSent) {
          res.writeHead(502);
          res.end('Proxy streaming failed: ' + err.message);
        }
      }
      return;
    }

    // 7. SSE Stream Log Event: GET /api/exec/stream?jobId=xxx
    if (req.method === 'GET' && pathname === '/api/exec/stream') {
      const jobId = url.searchParams.get('jobId') || 'default';
      res.writeHead(200, {
        'Content-Type': 'text/event-stream',
        'Cache-Control': 'no-cache',
        'Connection': 'keep-alive',
        'Access-Control-Allow-Origin': '*'
      });
      res.write(`event: connected\ndata: ${JSON.stringify({ jobId })}\n\n`);

      if (!sseClients.has(jobId)) {
        sseClients.set(jobId, new Set());
      }
      sseClients.get(jobId).add(res);

      req.on('close', () => {
        const clients = sseClients.get(jobId);
        if (clients) {
          clients.delete(res);
          if (clients.size === 0) sseClients.delete(jobId);
        }
      });
      return;
    }

    // 8. Execute Python Commands: POST /api/exec/run
    if (req.method === 'POST' && pathname === '/api/exec/run') {
      const body = await parseJsonBody(req);
      const { script, args, jobId } = body; // e.g. script: "main.py", args: ["translate", "assets/xujing/src/video_001.mp4"]

      if (!script || !args) {
        res.writeHead(400, { 'Content-Type': 'application/json' });
        return res.end(JSON.stringify({ error: 'Missing script or args' }));
      }

      const currentJobId = jobId || `job_${Date.now()}`;
      const scriptPath = path.join(ROOT_DIR, script);

      sendSSE(currentJobId, 'start', { script, args, jobId: currentJobId });

      const pyProcess = spawn(PYTHON_BIN, [scriptPath, ...args], {
        cwd: ROOT_DIR,
        detached: process.platform !== 'win32',
        stdio: ['ignore', 'pipe', 'pipe'],
        env: { ...process.env, PYTHONUNBUFFERED: "1", PAGER: "cat" }
      });

      activeProcesses.set(currentJobId, pyProcess);

      const handleOutput = (type, chunk) => {
        const text = chunk.toString('utf-8');
        // Strip ANSI escape sequences and split lines
        const cleanText = text.replace(/\x1B\[[0-9;]*[a-zA-K]/g, '');
        const lines = cleanText.split(/\r?\n/);
        for (const line of lines) {
          if (line.length > 0) {
            sendSSE(currentJobId, 'log', { type, text: line });
          }
        }
      };

      pyProcess.stdout.on('data', (chunk) => handleOutput('stdout', chunk));
      pyProcess.stderr.on('data', (chunk) => handleOutput('stderr', chunk));

      pyProcess.on('error', (err) => {
        activeProcesses.delete(currentJobId);
        finishedJobs.set(currentJobId, { code: 1, success: false, error: err.message, jobId: currentJobId, time: Date.now() });
        console.error('Failed to start process:', err);
        sendSSE(currentJobId, 'log', { type: 'stderr', text: `Lỗi khởi chạy tiến trình: ${err.message}` });
        sendSSE(currentJobId, 'exit', { code: 1, success: false, jobId: currentJobId });
      });

      pyProcess.on('close', (code) => {
        activeProcesses.delete(currentJobId);
        finishedJobs.set(currentJobId, { code, success: code === 0, jobId: currentJobId, time: Date.now() });
        sendSSE(currentJobId, 'exit', { code, success: code === 0, jobId: currentJobId });
      });

      res.writeHead(200, { 'Content-Type': 'application/json' });
      return res.end(JSON.stringify({ success: true, jobId: currentJobId }));
    }

    // 8c. GET /api/exec/status?jobId=xxx -> Check if process is still running or already finished
    if (req.method === 'GET' && pathname === '/api/exec/status') {
      const jobId = url.searchParams.get('jobId');
      if (!jobId) {
        res.writeHead(400, { 'Content-Type': 'application/json' });
        return res.end(JSON.stringify({ error: 'Missing jobId' }));
      }
      const isRunning = activeProcesses.has(jobId);
      const finishedInfo = finishedJobs.get(jobId);
      res.writeHead(200, { 'Content-Type': 'application/json' });
      return res.end(JSON.stringify({
        jobId,
        running: isRunning,
        finished: !isRunning && !!finishedInfo,
        result: finishedInfo || null
      }));
    }

    // 8b. Stop Running Process: POST /api/exec/stop
    if (req.method === 'POST' && pathname === '/api/exec/stop') {
      const body = await parseJsonBody(req);
      const { jobId } = body;
      let count = 0;

      const stopOne = (proc, id) => {
        killProcessGroup(proc, 'SIGINT');
        sendSSE(id, 'log', { type: 'stderr', text: '⚠️ Đã gửi tín hiệu ngắt (SIGINT) đến tiến trình...' });
        sendSSE('global', 'log', { type: 'stderr', text: `⚠️ Đã gửi tín hiệu ngắt (SIGINT) đến tiến trình ${id}...` });

        // Force kill with SIGKILL after 1.2s if process hasn't exited yet
        setTimeout(() => {
          if (activeProcesses.has(id)) {
            killProcessGroup(proc, 'SIGKILL');
            activeProcesses.delete(id);
            sendSSE(id, 'exit', { code: 130, success: false });
            sendSSE('global', 'exit', { code: 130, success: false });
          }
        }, 1200);
        count++;
      };

      let targets = [];
      if (jobId && jobId !== 'global' && activeProcesses.has(jobId)) {
        targets.push([jobId, activeProcesses.get(jobId)]);
      } else if (jobId && jobId !== 'global') {
        const cleanStem = jobId.replace(/^job_/, '').replace(/^trans_/, '').replace(/^resume_/, '');
        for (const [id, proc] of activeProcesses.entries()) {
          if (id.includes(cleanStem) || id.includes(jobId)) {
            targets.push([id, proc]);
          }
        }
      }

      // If no specific target matched, kill all running processes
      if (targets.length === 0) {
        for (const [id, proc] of activeProcesses.entries()) {
          targets.push([id, proc]);
        }
      }

      for (const [id, proc] of targets) {
        stopOne(proc, id);
      }

      res.writeHead(200, { 'Content-Type': 'application/json' });
      return res.end(JSON.stringify({ success: true, stoppedCount: count }));
    }

    // 9. Serve Static GUI Dist files (production / Docker mode)
    const distDir = path.join(__dirname, 'dist');
    if (req.method === 'GET' && fs.existsSync(distDir)) {
      let reqPath = pathname === '/' ? '/index.html' : pathname;
      let staticFilePath = path.join(distDir, reqPath);

      if (staticFilePath.startsWith(distDir) && fs.existsSync(staticFilePath) && fs.statSync(staticFilePath).isFile()) {
        const ext = path.extname(staticFilePath).toLowerCase();
        const mimeTypes = {
          '.html': 'text/html; charset=utf-8',
          '.js': 'application/javascript; charset=utf-8',
          '.css': 'text/css; charset=utf-8',
          '.svg': 'image/svg+xml',
          '.png': 'image/png',
          '.jpg': 'image/jpeg',
          '.json': 'application/json'
        };
        res.writeHead(200, { 'Content-Type': mimeTypes[ext] || 'application/octet-stream' });
        fs.createReadStream(staticFilePath).pipe(res);
        return;
      }

      // SPA Fallback for client-side routing
      const indexHtmlPath = path.join(distDir, 'index.html');
      if (fs.existsSync(indexHtmlPath)) {
        res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
        fs.createReadStream(indexHtmlPath).pipe(res);
        return;
      }
    }

    // Fallback 404
    res.writeHead(404, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ error: 'Route not found' }));

  } catch (err) {
    console.error('Server error:', err);
    res.writeHead(500, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ error: err.message }));
  }
});

server.listen(PORT, () => {
  console.log(`🚀 Sub-Video Local Backend Bridge listening at http://localhost:${PORT}`);
});
