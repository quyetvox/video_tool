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
          const outPath = path.join(projPath, 'output');
          const wsPath = path.join(projPath, 'workspace');
          const hasConfig = fs.existsSync(path.join(projPath, 'config.yaml'));

          const countFiles = (p) => fs.existsSync(p) ? fs.readdirSync(p).filter(f => !f.startsWith('.')).length : 0;

          return {
            name: e.name,
            hasConfig,
            srcCount: countFiles(srcPath),
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

    // 3. GET /api/projects/:name/videos -> List files in src, output, workspace
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
              sizeBytes: stats.size,
              mtime: stats.mtimeMs,
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
        srcFiles: listMediaFiles('src'),
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

      fs.unlinkSync(fullPath);
      res.writeHead(200, { 'Content-Type': 'application/json' });
      return res.end(JSON.stringify({ success: true, path: fileRelPath }));
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
        const end = parts[1] ? parseInt(parts[1], 10) : fileSize - 1;
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
        stdio: ['ignore', 'pipe', 'pipe'],
        env: { ...process.env, PYTHONUNBUFFERED: "1", PAGER: "cat" }
      });

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
        console.error('Failed to start process:', err);
        sendSSE(currentJobId, 'log', { type: 'stderr', text: `Lỗi khởi chạy tiến trình: ${err.message}` });
        sendSSE(currentJobId, 'exit', { code: 1, success: false });
      });

      pyProcess.on('close', (code) => {
        sendSSE(currentJobId, 'exit', { code, success: code === 0 });
      });

      res.writeHead(200, { 'Content-Type': 'application/json' });
      return res.end(JSON.stringify({ success: true, jobId: currentJobId }));
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
