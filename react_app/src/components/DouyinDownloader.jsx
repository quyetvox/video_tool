import React, { useState, useEffect, useMemo, useCallback } from 'react';
import { 
  Download, 
  Link2, 
  Play, 
  CheckCircle2, 
  FileText, 
  RefreshCw, 
  Save, 
  Edit3, 
  ExternalLink, 
  Copy, 
  CheckSquare, 
  Square, 
  Search, 
  Filter, 
  AlertCircle, 
  Video, 
  ArrowRight, 
  Settings, 
  Trash2, 
  Folder, 
  Eye, 
  Sparkles, 
  Check, 
  ChevronDown, 
  ChevronUp,
  Sliders,
  CloudDownload,
  FileCode
} from 'lucide-react';
import { runScript, fetchFileContent, saveFileContent, fetchProjectVideos, getProxyMediaUrl } from '../services/api';
import { useModal } from './ConfirmModal';

// Helper to format date into YYYYMMDD_HHMMSS
function formatTimestampDate(date) {
  const YYYY = date.getFullYear();
  const MM = String(date.getMonth() + 1).padStart(2, '0');
  const DD = String(date.getDate()).padStart(2, '0');
  const HH = String(date.getHours()).padStart(2, '0');
  const mm = String(date.getMinutes()).padStart(2, '0');
  const ss = String(date.getSeconds()).padStart(2, '0');
  return `${YYYY}${MM}${DD}_${HH}${mm}${ss}`;
}

// Helper to parse Douyin / Direct CDN URLs and extract publishing timestamp
function parseDouyinUrl(url, index) {
  const trimmed = (url || '').trim();
  if (!trimmed || !trimmed.startsWith('http')) return null;

  try {
    const parsed = new URL(trimmed);
    const pathParts = parsed.pathname.split('/').filter(Boolean);
    const hash = pathParts[0] || `video_${String(index + 1).padStart(3, '0')}`;
    const shortHash = hash.slice(0, 8);
    const brParam = parsed.searchParams.get('br');
    const bitrate = brParam ? parseInt(brParam, 10) : 0;
    
    // Extract publishing timestamp
    let unixTs = null;
    let postTimeStr = '';

    // Strategy A: Snowflake ID
    const vidMatch = trimmed.match(/(?:video\/|modal_id=|aweme_id=)(\d{18,20})/);
    if (vidMatch) {
      try {
        const vidBig = BigInt(vidMatch[1]);
        const ts = Number(vidBig >> 32n);
        if (ts >= 1500000000 && ts <= 2500000000) {
          unixTs = ts;
          postTimeStr = formatTimestampDate(new Date(ts * 1000));
        }
      } catch (e) {}
    }

    // Strategy B: Parameter l=YYYYMMDDHHMMSS...
    if (!unixTs) {
      const lParam = parsed.searchParams.get('l');
      if (lParam && lParam.length >= 14 && /^\d{14}/.test(lParam)) {
        const Y = lParam.slice(0, 4);
        const M = lParam.slice(4, 6);
        const D = lParam.slice(6, 8);
        const h = lParam.slice(8, 10);
        const m = lParam.slice(10, 12);
        const s = lParam.slice(12, 14);
        postTimeStr = `${Y}${M}${D}_${h}${m}${s}`;
        unixTs = Math.floor(new Date(`${Y}-${M}-${D}T${h}:${m}:${s}Z`).getTime() / 1000);
      }
    }

    // Strategy C: Parameter dy_q=...
    if (!unixTs) {
      const dyq = parsed.searchParams.get('dy_q');
      if (dyq && parseInt(dyq, 10) >= 1500000000) {
        unixTs = parseInt(dyq, 10);
        postTimeStr = formatTimestampDate(new Date(unixTs * 1000));
      }
    }

    // Strategy D: Hex path timestamp
    if (!unixTs && pathParts.length > 1) {
      const hexCandidate = pathParts[1];
      if (/^[0-9a-fA-F]{8}$/.test(hexCandidate)) {
        const ts = parseInt(hexCandidate, 16);
        if (ts >= 1500000000 && ts <= 2500000000) {
          unixTs = ts;
          postTimeStr = formatTimestampDate(new Date(ts * 1000));
        }
      }
    }

    // Strategy E: Fallback to current date
    if (!unixTs) {
      const now = new Date();
      unixTs = Math.floor(now.getTime() / 1000);
      postTimeStr = formatTimestampDate(now);
    }

    const filename = `${postTimeStr}_${shortHash}.mp4`;

    let qualityLabel = 'SD';
    let qualityColor = '#94a3b8';
    if (bitrate >= 1400) {
      qualityLabel = '1080p HD';
      qualityColor = '#38bdf8';
    } else if (bitrate >= 1000) {
      qualityLabel = '720p HD';
      qualityColor = '#818cf8';
    } else if (bitrate > 0) {
      qualityLabel = `${bitrate}k`;
      qualityColor = '#34d399';
    }

    return {
      id: `${hash}_${index}`,
      index: index + 1,
      raw_url: trimmed,
      hash,
      shortHash,
      postTimeStr,
      unixTs,
      filename,
      bitrate,
      bitrateStr: bitrate ? `${(bitrate / 1000).toFixed(2)} Mbps` : 'Tự động',
      qualityLabel,
      qualityColor,
      hostname: parsed.hostname
    };
  } catch (e) {
    const now = new Date();
    const fallbackTime = formatTimestampDate(now);
    const fallbackHash = `video_${String(index + 1).padStart(3, '0')}`;
    const filename = `${fallbackTime}_${fallbackHash.slice(0, 8)}.mp4`;
    return {
      id: `url_${index}`,
      index: index + 1,
      raw_url: trimmed,
      hash: fallbackHash,
      shortHash: fallbackHash.slice(0, 8),
      postTimeStr: fallbackTime,
      unixTs: Math.floor(now.getTime() / 1000),
      filename,
      bitrate: 0,
      bitrateStr: 'Không rõ',
      qualityLabel: 'Link Direct',
      qualityColor: '#94a3b8',
      hostname: 'direct'
    };
  }
}

export default function DouyinDownloader({ project = 'default', onSelectTab, onRefresh }) {
  const { confirm, showAlert, showToast } = useModal();

  // File path management
  const defaultFilePath = `assets/${project}/douyin-video-links.txt`;
  const [filePath, setFilePath] = useState(defaultFilePath);
  const [availableLinkFiles, setAvailableLinkFiles] = useState([]);
  const [rawText, setRawText] = useState('');
  const [isModified, setIsModified] = useState(false);
  const [showRawEditor, setShowRawEditor] = useState(false);
  const [isLoadingFile, setIsLoadingFile] = useState(false);
  const [isSavingFile, setIsSavingFile] = useState(false);

  // Download & Filter options
  const [searchQuery, setSearchQuery] = useState('');
  const [selectedUrls, setSelectedUrls] = useState(new Set());
  const [activeLink, setActiveLink] = useState(null);
  const [showAdvanced, setShowAdvanced] = useState(false);
  const [startIdx, setStartIdx] = useState(1);
  const [limitCount, setLimitCount] = useState(10);
  const [forceOverwrite, setForceOverwrite] = useState(false);
  const [isDownloading, setIsDownloading] = useState(false);

  // Local Project src files to detect downloaded videos
  const [srcVideos, setSrcVideos] = useState([]);

  // Sync default file path when project changes
  useEffect(() => {
    const nextPath = `assets/${project}/douyin-video-links.txt`;
    setFilePath(nextPath);
    loadProjectFiles();
    loadFileContent(nextPath);
  }, [project]);

  // Load project src videos and available .txt/.md files
  const loadProjectFiles = useCallback(async () => {
    if (!project) return;
    try {
      const data = await fetchProjectVideos(project);
      if (data && data.srcFiles) {
        setSrcVideos(data.srcFiles);
      }
      if (data && data.rootFiles) {
        const linkCandidates = data.rootFiles.filter(f => 
          f.name.endsWith('.txt') || f.name.endsWith('.md')
        );
        setAvailableLinkFiles(linkCandidates);
      }
    } catch (e) {
      console.warn('Could not load project files:', e);
    }
  }, [project]);

  // Load file content from server
  const loadFileContent = useCallback(async (targetRelPath) => {
    setIsLoadingFile(true);
    try {
      const data = await fetchFileContent(targetRelPath);
      if (data && typeof data.content === 'string') {
        setRawText(data.content);
        setIsModified(false);
      } else {
        setRawText('');
      }
    } catch (e) {
      setRawText('');
    } finally {
      setIsLoadingFile(false);
    }
  }, []);

  // Save modified raw text back to server
  const handleSaveFile = async () => {
    setIsSavingFile(true);
    try {
      await saveFileContent(filePath, rawText);
      setIsModified(false);
      showToast({ message: `Đã lưu danh sách link vào "${filePath}" thành công!`, type: 'success' });
    } catch (e) {
      showToast({ message: 'Lỗi lưu file: ' + e.message, type: 'danger' });
    } finally {
      setIsSavingFile(false);
    }
  };

  // Parse URLs from raw text
  const parsedLinks = useMemo(() => {
    if (!rawText.trim()) return [];
    const lines = rawText.split(/\r?\n/).map(l => l.trim()).filter(Boolean);
    const result = [];
    const seenHashes = new Map();

    lines.forEach((line, idx) => {
      const item = parseDouyinUrl(line, idx);
      if (item) {
        // Keep best bitrate if same hash
        if (!seenHashes.has(item.hash)) {
          seenHashes.set(item.hash, item);
          result.push(item);
        } else {
          const prev = seenHashes.get(item.hash);
          if (item.bitrate > prev.bitrate) {
            const replaceIdx = result.findIndex(x => x.hash === item.hash);
            if (replaceIdx !== -1) {
              result[replaceIdx] = item;
              seenHashes.set(item.hash, item);
            }
          }
        }
      }
    });

    return result;
  }, [rawText]);

  // Filtered links
  const filteredLinks = useMemo(() => {
    if (!searchQuery.trim()) return parsedLinks;
    const q = searchQuery.toLowerCase();
    return parsedLinks.filter(l => 
      l.raw_url.toLowerCase().includes(q) || 
      l.hash.toLowerCase().includes(q) ||
      `#${l.index}`.includes(q)
    );
  }, [parsedLinks, searchQuery]);

  // Set default active link if none selected
  useEffect(() => {
    if (parsedLinks.length > 0 && !activeLink) {
      setActiveLink(parsedLinks[0]);
    }
  }, [parsedLinks, activeLink]);

  // Selection handlers
  const handleToggleSelectAll = () => {
    if (selectedUrls.size === filteredLinks.length) {
      setSelectedUrls(new Set());
    } else {
      setSelectedUrls(new Set(filteredLinks.map(l => l.raw_url)));
    }
  };

  const handleToggleSelect = (url, e) => {
    e && e.stopPropagation();
    const next = new Set(selectedUrls);
    if (next.has(url)) {
      next.delete(url);
    } else {
      next.add(url);
    }
    setSelectedUrls(next);
  };

  // Copy helper
  const handleCopy = (text, label = 'link') => {
    navigator.clipboard.writeText(text);
    showToast({ message: `Đã sao chép ${label}!`, type: 'info' });
  };

  // Check if a link has already been downloaded into src/
  const getDownloadedFile = useCallback((link) => {
    if (!link || !srcVideos.length) return null;
    const formattedIdx = String(link.index).padStart(3, '0');
    return srcVideos.find(v => 
      v.name === link.filename ||
      (link.shortHash && v.name.includes(link.shortHash)) ||
      (link.hash && v.name.includes(link.hash)) ||
      v.name === `video_${formattedIdx}.mp4` ||
      v.name.includes(`_${link.index}.mp4`)
    );
  }, [srcVideos]);

  const checkIsDownloaded = useCallback((link) => {
    return Boolean(getDownloadedFile(link));
  }, [getDownloadedFile]);

  // Video playback stream calculation (Local file if exists, otherwise Proxy CDN)
  const activeLocalVideo = useMemo(() => {
    return getDownloadedFile(activeLink);
  }, [activeLink, getDownloadedFile]);

  const activeStreamUrl = useMemo(() => {
    if (!activeLink) return '';
    if (activeLocalVideo) {
      return `http://localhost:3001/api/media?path=${encodeURIComponent(activeLocalVideo.relPath)}`;
    }
    return getProxyMediaUrl(activeLink.raw_url);
  }, [activeLink, activeLocalVideo]);

  const [hasPlaybackError, setHasPlaybackError] = useState(false);

  // Reset error when active link changes
  useEffect(() => {
    setHasPlaybackError(false);
  }, [activeLink?.id]);

  // Download Action Execution
  const handleExecuteDownload = async (customUrls = null) => {
    if (!project) {
      showToast({ message: 'Vui lòng chọn một dự án trước khi tải!', type: 'warning' });
      return;
    }

    let targetUrls = customUrls;
    let targetFileName = filePath;

    if (!targetUrls) {
      if (selectedUrls.size > 0) {
        // Case 1: Download ticked URLs
        targetUrls = Array.from(selectedUrls);
      } else {
        // Case 2: No URLs ticked -> Ask to download ALL links in file
        const total = parsedLinks.length;
        if (total === 0) {
          showToast({ message: 'Danh sách link trống. Vui lòng thêm URL trước khi tải!', type: 'warning' });
          return;
        }

        const ok = await confirm({
          title: `Tải Toàn Bộ ${total} Video Douyin?`,
          message: `Bạn chưa chọn video nào. Bạn có muốn tải TOÀN BỘ ${total} video từ file "${filePath}" về thư mục "assets/${project}/src/" không?\n\n💡 Hệ thống sẽ tự động bỏ qua các video đã tải sẵn để tiết kiệm thời gian.`,
          confirmText: `Tải Toàn Bộ (${total} Video)`,
          type: 'info'
        });
        if (!ok) return;
        targetUrls = null; // Download whole file directly
      }
    }

    setIsDownloading(true);

    try {
      // If downloading a subset of URLs, save them to a temporary queue file
      if (targetUrls && targetUrls.length > 0) {
        targetFileName = `assets/${project}/_temp_download_queue.txt`;
        await saveFileContent(targetFileName, targetUrls.join('\n'));
      } else if (isModified) {
        // Auto-save current modified text before downloading
        await saveFileContent(filePath, rawText);
        setIsModified(false);
      }

      const args = [targetFileName, '-o', `assets/${project}/src`];
      if (startIdx > 1) {
        args.push('--start', startIdx.toString());
      }
      if (limitCount > 0 && (!targetUrls || targetUrls.length > limitCount)) {
        args.push('--limit', limitCount.toString());
      }
      if (forceOverwrite) {
        args.push('--force');
      }

      showToast({ message: `Bắt đầu tải ${targetUrls ? targetUrls.length : parsedLinks.length} video về assets/${project}/src/...`, type: 'info' });
      
      const jobId = `dl_${Date.now()}`;
      if (onSelectTab) {
        // Optionally switch to logs tab or keep in place
      }

      await runScript('download.py', args, jobId);
      
      // Clear ticks and reset download state
      setSelectedUrls(new Set());
      showToast({ message: '🎉 Hoàn tất quá trình tải video Douyin về thư mục src/!', type: 'success' });
      
      // Reload src files to update badges
      await loadProjectFiles();
      if (onRefresh) onRefresh();
    } catch (e) {
      showToast({ message: 'Lỗi trong quá trình tải: ' + e.message, type: 'danger' });
    } finally {
      setIsDownloading(false);
    }
  };

  return (
    <div style={styles.container}>
      {/* ─────────────────────────────────────────────────────────────
          HEADER BAR: Title, Project Badge, File Path & Actions
         ───────────────────────────────────────────────────────────── */}
      <div style={styles.headerBar}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 14 }}>
          <div style={styles.headerIconBox}>
            <CloudDownload size={22} color="#10b981" />
          </div>
          <div>
            <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
              <h2 style={styles.title}>Tải Video Douyin Hàng Loạt</h2>
              <span style={styles.projectBadge}>
                <Folder size={12} style={{ marginRight: 4 }} />
                assets/{project}/
              </span>
            </div>
            <p style={styles.subtitle}>
              Trích xuất, xem trước và tải video chất lượng cao từ danh sách URL Douyin vào thư mục <code>assets/{project}/src/</code>
            </p>
          </div>
        </div>

        {/* Top File Action Buttons */}
        <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
          <button 
            style={{ ...styles.btnSecondary, ...(showRawEditor ? styles.btnSecondaryActive : {}) }}
            onClick={() => setShowRawEditor(!showRawEditor)}
            title="Mở trình soạn thảo text thô"
          >
            <Edit3 size={14} style={{ marginRight: 6 }} />
            {showRawEditor ? 'Ẩn Editor' : 'Sửa File Raw'}
          </button>

          <button 
            style={styles.btnSecondary}
            onClick={() => {
              loadFileContent(filePath);
              loadProjectFiles();
              showToast({ message: 'Đã làm mới dữ liệu từ file!', type: 'info' });
            }}
            title="Tải lại nội dung từ ổ đĩa"
            disabled={isLoadingFile}
          >
            <RefreshCw size={14} className={isLoadingFile ? 'spin-icon' : ''} style={{ marginRight: 6 }} />
            Tải Lại
          </button>

          {isModified && (
            <button 
              style={styles.btnSave}
              onClick={handleSaveFile}
              disabled={isSavingFile}
            >
              <Save size={14} style={{ marginRight: 6 }} />
              {isSavingFile ? 'Đang Lưu...' : 'Lưu File'}
            </button>
          )}
        </div>
      </div>

      {/* ─────────────────────────────────────────────────────────────
          FILE PATH SELECTOR BAR
         ───────────────────────────────────────────────────────────── */}
      <div style={styles.pathSelectorBar}>
        <div style={styles.pathInputGroup}>
          <span style={styles.pathPrefix}>
            <FileCode size={14} color="#818cf8" style={{ marginRight: 6 }} />
            Đường dẫn file link:
          </span>
          
          <input
            type="text"
            value={filePath}
            onChange={(e) => {
              setFilePath(e.target.value);
            }}
            onBlur={() => {
              if (filePath.trim()) loadFileContent(filePath);
            }}
            onKeyDown={(e) => {
              if (e.key === 'Enter' && filePath.trim()) loadFileContent(filePath);
            }}
            placeholder={`assets/${project}/douyin-video-links.txt`}
            style={styles.pathInput}
          />
        </div>

        {/* Quick picker dropdown for existing project files */}
        {availableLinkFiles.length > 0 && (
          <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
            <span style={{ fontSize: 12, color: 'var(--text-dim)' }}>Gợi ý:</span>
            <select
              style={styles.filePickerSelect}
              value={filePath}
              onChange={(e) => {
                const p = e.target.value;
                setFilePath(p);
                loadFileContent(p);
              }}
            >
              <option value={`assets/${project}/douyin-video-links.txt`}>douyin-video-links.txt (Mặc định)</option>
              {availableLinkFiles
                .filter(f => f.name !== 'douyin-video-links.txt')
                .map(f => (
                  <option key={f.name} value={`assets/${project}/${f.name}`}>
                    {f.name}
                  </option>
                ))}
            </select>
          </div>
        )}
      </div>

      {/* ─────────────────────────────────────────────────────────────
          COLLAPSIBLE RAW TEXT EDITOR
         ───────────────────────────────────────────────────────────── */}
      {showRawEditor && (
        <div style={styles.rawEditorCard}>
          <div style={styles.rawEditorHeader}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
              <Edit3 size={14} color="var(--primary)" />
              <span style={{ fontSize: 13, fontWeight: 600, color: 'var(--text-main)' }}>
                Soạn thảo danh sách link trực tiếp ({parsedLinks.length} URL hợp lệ)
              </span>
            </div>
            <span style={{ fontSize: 11, color: 'var(--text-dim)' }}>
              Mỗi dòng một link URL video Douyin hoặc Direct CDN
            </span>
          </div>

          <textarea
            rows={8}
            value={rawText}
            onChange={(e) => {
              setRawText(e.target.value);
              setIsModified(true);
            }}
            placeholder="Dán các URL Douyin vào đây (mỗi dòng 1 link)..."
            style={styles.rawTextarea}
          />

          <div style={styles.rawEditorFooter}>
            <span style={{ fontSize: 12, color: isModified ? '#fbbf24' : 'var(--text-dim)' }}>
              {isModified ? '⚠️ Có thay đổi chưa lưu vào ổ đĩa' : '✓ Đã đồng bộ với file trên ổ đĩa'}
            </span>

            <div style={{ display: 'flex', gap: 8 }}>
              <button 
                style={styles.btnSave}
                onClick={handleSaveFile}
                disabled={isSavingFile || !isModified}
              >
                <Save size={13} style={{ marginRight: 6 }} />
                {isSavingFile ? 'Đang Lưu...' : 'Lưu Thay Đổi'}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* ─────────────────────────────────────────────────────────────
          2-COLUMN STUDIO WORKSPACE
         ───────────────────────────────────────────────────────────── */}
      <div style={styles.studioWorkspace}>
        {/* ═════════════════════════════════════════════════════════════
            COLUMN 1: DANH SÁCH LINK (50%)
           ═════════════════════════════════════════════════════════════ */}
        <div style={styles.leftColumn}>
          {/* Column 1 Controls Header */}
          <div style={styles.listHeader}>
            <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', width: '100%', marginBottom: 10 }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                <div 
                  style={styles.checkboxWrapper}
                  onClick={handleToggleSelectAll}
                  title="Chọn tất cả / Bỏ chọn tất cả"
                >
                  {selectedUrls.size > 0 && selectedUrls.size === filteredLinks.length ? (
                    <CheckSquare size={16} color="var(--primary-light)" />
                  ) : (
                    <Square size={16} color="var(--text-dim)" />
                  )}
                </div>
                <span style={{ fontSize: 13, fontWeight: 600, color: 'var(--text-main)' }}>
                  Danh sách Video ({filteredLinks.length})
                </span>
                {selectedUrls.size > 0 && (
                  <span style={styles.selectedCountBadge}>
                    Đã chọn {selectedUrls.size}
                  </span>
                )}
              </div>

              {/* Advanced Settings Toggle */}
              <button 
                style={styles.btnTinyToggle}
                onClick={() => setShowAdvanced(!showAdvanced)}
                title="Cấu hình nâng cao (--start, --limit, --force)"
              >
                <Sliders size={13} style={{ marginRight: 4 }} />
                Tùy chọn
                {showAdvanced ? <ChevronUp size={13} /> : <ChevronDown size={13} />}
              </button>
            </div>

            {/* Advanced Settings Drawer */}
            {showAdvanced && (
              <div style={styles.advancedDrawer}>
                <div style={styles.advFormRow}>
                  <div style={styles.advInputGroup}>
                    <label style={styles.advLabel}>Vị trí bắt đầu (--start):</label>
                    <input
                      type="number"
                      min="1"
                      value={startIdx}
                      onChange={e => setStartIdx(parseInt(e.target.value, 10) || 1)}
                      style={styles.advInput}
                    />
                  </div>

                  <div style={styles.advInputGroup}>
                    <label style={styles.advLabel}>Số lượng tối đa (--limit):</label>
                    <input
                      type="number"
                      min="1"
                      max="100"
                      value={limitCount}
                      onChange={e => setLimitCount(parseInt(e.target.value, 10) || 10)}
                      style={styles.advInput}
                    />
                  </div>

                  <div style={{ ...styles.advInputGroup, justifyContent: 'flex-end' }}>
                    <label style={{ ...styles.advLabel, display: 'flex', alignItems: 'center', gap: 6, cursor: 'pointer' }}>
                      <input
                        type="checkbox"
                        checked={forceOverwrite}
                        onChange={e => setForceOverwrite(e.target.checked)}
                      />
                      Ghi đè file cũ (--force)
                    </label>
                  </div>
                </div>
              </div>
            )}

            {/* Search Input & Big Download CTA */}
            <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
              <div style={styles.searchWrapper}>
                <Search size={14} color="var(--text-dim)" />
                <input
                  type="text"
                  placeholder="Lọc link theo ID, bitrate hoặc URL..."
                  value={searchQuery}
                  onChange={e => setSearchQuery(e.target.value)}
                  style={styles.searchInput}
                />
                {searchQuery && (
                  <button style={styles.clearSearchBtn} onClick={() => setSearchQuery('')}>×</button>
                )}
              </div>

              <button
                style={{
                  ...styles.btnDownloadPrimary,
                  opacity: isDownloading ? 0.7 : 1
                }}
                onClick={() => handleExecuteDownload()}
                disabled={isDownloading || parsedLinks.length === 0}
              >
                <Download size={15} style={{ marginRight: 6 }} className={isDownloading ? 'spin-icon' : ''} />
                {isDownloading 
                  ? 'Đang Tải...' 
                  : selectedUrls.size > 0 
                    ? `Tải (${selectedUrls.size}) Link Đã Chọn` 
                    : `Tải Toàn Bộ (${parsedLinks.length}) Video`}
              </button>
            </div>
          </div>

          {/* Scrollable Link Items List */}
          <div style={styles.linkListScroll}>
            {filteredLinks.length === 0 ? (
              <div style={styles.emptyListState}>
                <AlertCircle size={28} color="var(--text-dim)" />
                <p style={{ margin: 0, fontSize: 13, color: 'var(--text-muted)' }}>
                  {rawText.trim() ? 'Không tìm thấy link nào khớp với tìm kiếm.' : 'File danh sách link trống.'}
                </p>
                <button 
                  style={styles.btnSecondary}
                  onClick={() => setShowRawEditor(true)}
                >
                  <Edit3 size={13} style={{ marginRight: 6 }} />
                  Dán URL Douyin vào file
                </button>
              </div>
            ) : (
              filteredLinks.map(item => {
                const isSelected = selectedUrls.has(item.raw_url);
                const isActive = activeLink?.id === item.id;
                const isDownloaded = checkIsDownloaded(item);

                return (
                  <div
                    key={item.id}
                    style={{
                      ...styles.linkRow,
                      ...(isActive ? styles.linkRowActive : {}),
                      ...(isSelected ? styles.linkRowSelected : {})
                    }}
                    onClick={() => setActiveLink(item)}
                  >
                    {/* Checkbox */}
                    <div 
                      style={styles.checkboxWrapper}
                      onClick={(e) => handleToggleSelect(item.raw_url, e)}
                    >
                      {isSelected ? (
                        <CheckSquare size={16} color="var(--primary-light)" />
                      ) : (
                        <Square size={16} color="var(--text-dim)" />
                      )}
                    </div>

                    {/* Order Index Badge */}
                    <span style={styles.indexBadge}>
                      #{String(item.index).padStart(2, '0')}
                    </span>

                    {/* Main Link Info */}
                    <div style={styles.linkMainInfo}>
                      <div style={{ display: 'flex', alignItems: 'center', gap: 6, flexWrap: 'wrap' }}>
                        <span 
                          style={{ 
                            ...styles.qualityChip, 
                            color: item.qualityColor, 
                            borderColor: `${item.qualityColor}40`,
                            backgroundColor: `${item.qualityColor}15`
                          }}
                        >
                          {item.qualityLabel}
                        </span>

                        <span style={styles.bitrateText}>
                          {item.bitrateStr}
                        </span>

                        <span style={styles.filenameChip} title={`Tên file khi tải về: ${item.filename}`}>
                          {item.filename}
                        </span>

                        {isDownloaded && (
                          <span style={styles.downloadedBadge}>
                            <Check size={11} style={{ marginRight: 3 }} />
                            Đã có trong src/
                          </span>
                        )}
                      </div>

                      <span style={styles.urlSnippet} title={item.raw_url}>
                        {item.raw_url}
                      </span>
                    </div>

                    {/* Single Row Actions */}
                    <div style={styles.rowActions} onClick={e => e.stopPropagation()}>
                      <button
                        style={styles.tinyActionBtn}
                        onClick={() => handleCopy(item.raw_url, 'đường dẫn video')}
                        title="Sao chép URL"
                      >
                        <Copy size={13} />
                      </button>

                      <button
                        style={{ ...styles.tinyActionBtn, color: '#10b981' }}
                        onClick={() => handleExecuteDownload([item.raw_url])}
                        title="Tải riêng video này về src/"
                        disabled={isDownloading}
                      >
                        <Download size={13} />
                      </button>
                    </div>
                  </div>
                );
              })
            )}
          </div>
        </div>

        {/* ═════════════════════════════════════════════════════════════
            COLUMN 2: TRÌNH PHÁT XEM TRƯỚC VIDEO (50%)
           ═════════════════════════════════════════════════════════════ */}
        <div style={styles.rightColumn}>
          <div style={styles.previewHeader}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
              <Video size={16} color="var(--primary)" />
              <span style={{ fontSize: 13, fontWeight: 700, color: 'var(--text-main)' }}>
                Xem Trước Video (Live Preview)
              </span>
              {activeLink && (
                <span style={styles.previewIndexBadge}>
                  Video #{String(activeLink.index).padStart(2, '0')}
                </span>
              )}
            </div>

            {activeLink && (
              <a 
                href={activeLink.raw_url} 
                target="_blank" 
                rel="noreferrer"
                style={styles.openExternalLink}
                title="Mở xem trực tiếp trên tab mới"
              >
                <ExternalLink size={13} style={{ marginRight: 4 }} />
                Mở tab mới
              </a>
            )}
          </div>

          {/* Video Player Box */}
          <div style={styles.playerContainer}>
            {activeLink ? (
              hasPlaybackError ? (
                <div style={styles.errorOverlay}>
                  <AlertCircle size={32} color="#f59e0b" />
                  <span style={{ fontSize: 13, fontWeight: 700, color: 'var(--text-main)' }}>
                    Không Thể Phát Trực Tiếp Link Này
                  </span>
                  <span style={{ fontSize: 11.5, color: 'var(--text-dim)', textAlign: 'center', maxWidth: 320 }}>
                    Token URL CDN của Douyin có thể đã hết hạn (Time Expired). Hãy bấm tải về để xem và dịch video.
                  </span>
                  <div style={{ display: 'flex', gap: 8, marginTop: 4 }}>
                    <a 
                      href={activeLink.raw_url} 
                      target="_blank" 
                      rel="noreferrer"
                      style={styles.btnSecondary}
                    >
                      <ExternalLink size={13} style={{ marginRight: 6 }} />
                      Mở Tab Mới
                    </a>
                    <button 
                      style={styles.btnDownloadPrimary}
                      onClick={() => handleExecuteDownload([activeLink.raw_url])}
                      disabled={isDownloading}
                    >
                      <Download size={13} style={{ marginRight: 6 }} />
                      Tải Video Về src/
                    </button>
                  </div>
                </div>
              ) : (
                <div style={{ width: '100%', height: '100%', display: 'flex', flexDirection: 'column', position: 'relative' }}>
                  {/* Source origin badge */}
                  <div style={styles.streamOriginBadge}>
                    {activeLocalVideo ? (
                      <span style={{ color: '#34d399', display: 'flex', alignItems: 'center', gap: 4 }}>
                        <CheckCircle2 size={12} />
                        Phát từ file cục bộ: {activeLocalVideo.name}
                      </span>
                    ) : (
                      <span style={{ color: '#38bdf8', display: 'flex', alignItems: 'center', gap: 4 }}>
                        <Play size={12} />
                        Phát trực tiếp từ Douyin CDN
                      </span>
                    )}
                  </div>

                  <video
                    key={activeStreamUrl}
                    src={activeStreamUrl}
                    controls
                    playsInline
                    preload="metadata"
                    style={styles.videoElement}
                    onError={() => {
                      setHasPlaybackError(true);
                    }}
                  />
                </div>
              )
            ) : (
              <div style={styles.emptyPreviewBox}>
                <Play size={36} color="var(--text-dim)" style={{ opacity: 0.5 }} />
                <span style={{ fontSize: 13, color: 'var(--text-dim)', marginTop: 8 }}>
                  Chọn một video ở danh sách bên trái để phát xem trước
                </span>
              </div>
            )}
          </div>

          {/* Active Link Inspector Metadata */}
          {activeLink && (
            <div style={styles.metadataCard}>
              <div style={styles.metaRow}>
                <span style={styles.metaLabel}>Tên file tải về:</span>
                <span style={{ ...styles.metaValueCode, color: '#38bdf8', fontWeight: 700 }}>
                  {activeLink.filename}
                </span>
              </div>

              <div style={styles.metaRow}>
                <span style={styles.metaLabel}>Ngày đăng (Timestamp):</span>
                <span style={styles.metaValue}>
                  {activeLink.postTimeStr ? activeLink.postTimeStr.replace('_', ' lúc ') : 'Thời điểm hiện tại'}
                </span>
              </div>

              <div style={styles.metaRow}>
                <span style={styles.metaLabel}>Video ID / Hash:</span>
                <span style={styles.metaValueCode}>{activeLink.hash}</span>
              </div>

              <div style={styles.metaRow}>
                <span style={styles.metaLabel}>Chất lượng / Bitrate:</span>
                <span style={{ ...styles.metaValue, color: activeLink.qualityColor, fontWeight: 600 }}>
                  {activeLink.qualityLabel} ({activeLink.bitrateStr})
                </span>
              </div>

              <div style={styles.metaRow}>
                <span style={styles.metaLabel}>Lưu về thư mục:</span>
                <span style={styles.metaValue}>assets/{project}/src/</span>
              </div>

              <div style={{ ...styles.metaRow, flexDirection: 'column', alignItems: 'flex-start', gap: 6, marginTop: 4 }}>
                <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', width: '100%' }}>
                  <span style={styles.metaLabel}>URL trực tiếp:</span>
                  <button 
                    style={styles.btnCopyUrl}
                    onClick={() => handleCopy(activeLink.raw_url, 'URL video')}
                  >
                    <Copy size={12} style={{ marginRight: 4 }} />
                    Sao chép link
                  </button>
                </div>
                <div style={styles.fullUrlBox}>
                  {activeLink.raw_url}
                </div>
              </div>

              {/* Single Download Button in Preview Pane */}
              <button
                style={styles.btnDownloadSingle}
                onClick={() => handleExecuteDownload([activeLink.raw_url])}
                disabled={isDownloading}
              >
                <Download size={15} style={{ marginRight: 8 }} />
                {isDownloading ? 'Đang Tải Video...' : `Tải Ngay Video #${activeLink.index} Về assets/${project}/src/`}
              </button>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// STYLES: Dark Studio Theme with 2-Column Responsive Layout
// ─────────────────────────────────────────────────────────────────────────────
const styles = {
  container: {
    display: 'flex',
    flexDirection: 'column',
    height: '100%',
    backgroundColor: 'var(--bg-app)',
    color: 'var(--text-main)',
    overflow: 'hidden',
    boxSizing: 'border-box'
  },
  headerBar: {
    padding: '16px 20px',
    borderBottom: '1px solid var(--border-color)',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between',
    backgroundColor: 'var(--bg-header)',
    backdropFilter: 'blur(12px)',
    flexShrink: 0
  },
  headerIconBox: {
    width: 42,
    height: 42,
    borderRadius: 10,
    backgroundColor: 'rgba(16, 185, 129, 0.12)',
    border: '1px solid rgba(16, 185, 129, 0.25)',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center'
  },
  title: {
    fontSize: 18,
    fontWeight: 700,
    margin: 0,
    color: 'var(--text-main)',
    letterSpacing: '-0.01em'
  },
  subtitle: {
    fontSize: 12,
    color: 'var(--text-dim)',
    margin: '2px 0 0 0'
  },
  projectBadge: {
    display: 'inline-flex',
    alignItems: 'center',
    padding: '2px 8px',
    borderRadius: 6,
    backgroundColor: 'var(--primary-glow)',
    border: '1px solid var(--primary-glow)',
    color: 'var(--primary)',
    fontSize: 11,
    fontWeight: 600
  },
  pathSelectorBar: {
    padding: '10px 20px',
    borderBottom: '1px solid var(--border-color)',
    backgroundColor: 'var(--bg-surface)',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: 16,
    flexShrink: 0
  },
  pathInputGroup: {
    display: 'flex',
    alignItems: 'center',
    gap: 10,
    flex: 1
  },
  pathPrefix: {
    fontSize: 12,
    fontWeight: 600,
    color: 'var(--text-muted)',
    display: 'flex',
    alignItems: 'center',
    whiteSpace: 'nowrap'
  },
  pathInput: {
    flex: 1,
    backgroundColor: 'var(--bg-input)',
    border: '1px solid var(--border-color)',
    borderRadius: 6,
    padding: '6px 12px',
    color: 'var(--text-main)',
    fontSize: 12.5,
    fontFamily: 'monospace',
    outline: 'none'
  },
  filePickerSelect: {
    backgroundColor: 'var(--bg-input)',
    border: '1px solid var(--border-color)',
    borderRadius: 6,
    padding: '6px 10px',
    color: 'var(--text-main)',
    fontSize: 12,
    outline: 'none',
    cursor: 'pointer'
  },
  rawEditorCard: {
    margin: '12px 20px 0 20px',
    padding: 14,
    borderRadius: 8,
    backgroundColor: 'var(--bg-card)',
    border: '1px solid var(--border-color)',
    boxShadow: 'var(--shadow-sm)',
    display: 'flex',
    flexDirection: 'column',
    gap: 10,
    flexShrink: 0
  },
  rawEditorHeader: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between'
  },
  rawTextarea: {
    backgroundColor: 'var(--bg-input)',
    border: '1px solid var(--border-color)',
    borderRadius: 6,
    padding: 10,
    color: 'var(--text-main)',
    fontSize: 12,
    fontFamily: 'monospace',
    lineHeight: 1.5,
    outline: 'none',
    resize: 'vertical'
  },
  rawEditorFooter: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between'
  },
  studioWorkspace: {
    display: 'grid',
    gridTemplateColumns: '1fr 1fr',
    gap: 1,
    flex: 1,
    overflow: 'hidden',
    backgroundColor: 'var(--border-color)'
  },
  leftColumn: {
    display: 'flex',
    flexDirection: 'column',
    backgroundColor: 'var(--bg-card)',
    overflow: 'hidden'
  },
  listHeader: {
    padding: '12px 16px',
    borderBottom: '1px solid var(--border-color)',
    backgroundColor: 'var(--bg-surface)',
    display: 'flex',
    flexDirection: 'column',
    gap: 8,
    flexShrink: 0
  },
  selectedCountBadge: {
    fontSize: 11,
    fontWeight: 600,
    color: '#38bdf8',
    backgroundColor: 'rgba(56, 189, 248, 0.12)',
    padding: '2px 6px',
    borderRadius: 4
  },
  btnTinyToggle: {
    background: 'var(--bg-card)',
    border: '1px solid var(--border-color)',
    borderRadius: 4,
    padding: '3px 8px',
    color: 'var(--text-dim)',
    fontSize: 11,
    display: 'flex',
    alignItems: 'center',
    cursor: 'pointer'
  },
  advancedDrawer: {
    padding: 10,
    backgroundColor: 'var(--bg-surface)',
    borderRadius: 6,
    border: '1px solid var(--border-color)'
  },
  advFormRow: {
    display: 'flex',
    alignItems: 'center',
    gap: 14
  },
  advInputGroup: {
    display: 'flex',
    flexDirection: 'column',
    gap: 4
  },
  advLabel: {
    fontSize: 11,
    color: 'var(--text-dim)'
  },
  advInput: {
    width: 70,
    backgroundColor: 'var(--bg-input)',
    border: '1px solid var(--border-color)',
    borderRadius: 4,
    padding: '4px 8px',
    color: 'var(--text-main)',
    fontSize: 12
  },
  searchWrapper: {
    position: 'relative',
    display: 'flex',
    alignItems: 'center',
    flex: 1,
    backgroundColor: 'var(--bg-input)',
    border: '1px solid var(--border-color)',
    borderRadius: 6,
    padding: '0 10px',
    gap: 8,
    height: 34
  },
  searchInput: {
    background: 'transparent',
    border: 'none',
    color: 'var(--text-main)',
    fontSize: 12,
    outline: 'none',
    width: '100%'
  },
  clearSearchBtn: {
    background: 'none',
    border: 'none',
    color: 'var(--text-dim)',
    cursor: 'pointer',
    fontSize: 14
  },
  linkListScroll: {
    flex: 1,
    overflowY: 'auto',
    padding: 8,
    display: 'flex',
    flexDirection: 'column',
    gap: 4
  },
  linkRow: {
    display: 'flex',
    alignItems: 'center',
    gap: 10,
    padding: '10px 12px',
    borderRadius: 8,
    backgroundColor: 'var(--bg-surface)',
    border: '1px solid var(--border-subtle)',
    cursor: 'pointer',
    transition: 'all 0.15s ease'
  },
  linkRowActive: {
    borderColor: 'var(--primary)',
    backgroundColor: 'var(--primary-glow)',
    boxShadow: '0 0 10px rgba(99, 102, 241, 0.15)'
  },
  linkRowSelected: {
    borderColor: 'rgba(56, 189, 248, 0.4)',
    backgroundColor: 'rgba(56, 189, 248, 0.08)'
  },
  checkboxWrapper: {
    cursor: 'pointer',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center'
  },
  indexBadge: {
    fontSize: 11.5,
    fontWeight: 700,
    color: 'var(--text-dim)',
    fontFamily: 'monospace',
    minWidth: 26
  },
  linkMainInfo: {
    display: 'flex',
    flexDirection: 'column',
    gap: 3,
    flex: 1,
    minWidth: 0
  },
  qualityChip: {
    fontSize: 10,
    fontWeight: 700,
    padding: '1px 5px',
    borderRadius: 4,
    border: '1px solid'
  },
  bitrateText: {
    fontSize: 11,
    color: 'var(--text-muted)',
    fontWeight: 500
  },
  hashChip: {
    fontSize: 10.5,
    fontFamily: 'monospace',
    color: 'var(--text-dim)',
    backgroundColor: 'var(--bg-input)',
    border: '1px solid var(--border-color)',
    padding: '1px 4px',
    borderRadius: 3
  },
  filenameChip: {
    fontSize: 11,
    fontFamily: 'monospace',
    fontWeight: 600,
    color: '#38bdf8',
    backgroundColor: 'rgba(56, 189, 248, 0.1)',
    border: '1px solid rgba(56, 189, 248, 0.2)',
    padding: '1px 6px',
    borderRadius: 4
  },
  downloadedBadge: {
    display: 'inline-flex',
    alignItems: 'center',
    fontSize: 10.5,
    fontWeight: 600,
    color: '#34d399',
    backgroundColor: 'rgba(16, 185, 129, 0.15)',
    padding: '1px 6px',
    borderRadius: 4
  },
  urlSnippet: {
    fontSize: 11,
    color: 'var(--text-dim)',
    overflow: 'hidden',
    textOverflow: 'ellipsis',
    whiteSpace: 'nowrap'
  },
  rowActions: {
    display: 'flex',
    alignItems: 'center',
    gap: 4
  },
  tinyActionBtn: {
    background: 'var(--bg-card)',
    border: '1px solid var(--border-color)',
    borderRadius: 4,
    width: 24,
    height: 24,
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    color: 'var(--text-dim)',
    cursor: 'pointer',
    transition: 'all 0.15s'
  },
  emptyListState: {
    display: 'flex',
    flexDirection: 'column',
    alignItems: 'center',
    justifyContent: 'center',
    padding: '60px 20px',
    gap: 12,
    textAlign: 'center'
  },
  rightColumn: {
    display: 'flex',
    flexDirection: 'column',
    backgroundColor: 'var(--bg-card)',
    padding: 16,
    overflowY: 'auto',
    gap: 14
  },
  previewHeader: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between'
  },
  previewIndexBadge: {
    fontSize: 11,
    fontWeight: 700,
    color: '#38bdf8',
    backgroundColor: 'rgba(56, 189, 248, 0.12)',
    padding: '2px 8px',
    borderRadius: 4
  },
  openExternalLink: {
    display: 'inline-flex',
    alignItems: 'center',
    fontSize: 11.5,
    color: 'var(--primary)',
    textDecoration: 'none',
    padding: '3px 8px',
    borderRadius: 4,
    backgroundColor: 'var(--primary-glow)',
    border: '1px solid var(--primary-glow)'
  },
  playerContainer: {
    width: '100%',
    aspectRatio: '16 / 9',
    maxHeight: 340,
    backgroundColor: '#000000',
    borderRadius: 10,
    overflow: 'hidden',
    border: '1px solid var(--border-color)',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    position: 'relative'
  },
  streamOriginBadge: {
    position: 'absolute',
    top: 8,
    left: 8,
    zIndex: 10,
    backgroundColor: 'rgba(15, 23, 42, 0.85)',
    backdropFilter: 'blur(6px)',
    padding: '3px 8px',
    borderRadius: 4,
    border: '1px solid rgba(255, 255, 255, 0.1)',
    fontSize: 11,
    fontWeight: 600,
    color: '#ffffff'
  },
  errorOverlay: {
    display: 'flex',
    flexDirection: 'column',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 8,
    padding: 20,
    textAlign: 'center',
    width: '100%',
    height: '100%',
    backgroundColor: 'var(--bg-surface)'
  },
  videoElement: {
    width: '100%',
    height: '100%',
    objectFit: 'contain',
    backgroundColor: '#000000'
  },
  emptyPreviewBox: {
    display: 'flex',
    flexDirection: 'column',
    alignItems: 'center',
    justifyContent: 'center'
  },
  metadataCard: {
    padding: 14,
    borderRadius: 8,
    backgroundColor: 'var(--bg-surface)',
    border: '1px solid var(--border-color)',
    boxShadow: 'var(--shadow-sm)',
    display: 'flex',
    flexDirection: 'column',
    gap: 8
  },
  metaRow: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between',
    fontSize: 12
  },
  metaLabel: {
    color: 'var(--text-dim)',
    fontWeight: 500
  },
  metaValue: {
    color: 'var(--text-main)',
    fontWeight: 500
  },
  metaValueCode: {
    fontFamily: 'monospace',
    color: 'var(--primary)',
    backgroundColor: 'var(--primary-glow)',
    padding: '1px 6px',
    borderRadius: 4,
    fontSize: 11.5
  },
  btnCopyUrl: {
    background: 'none',
    border: 'none',
    color: 'var(--primary)',
    fontSize: 11.5,
    cursor: 'pointer',
    display: 'flex',
    alignItems: 'center'
  },
  fullUrlBox: {
    width: '100%',
    padding: '6px 8px',
    backgroundColor: 'var(--bg-input)',
    borderRadius: 4,
    border: '1px solid var(--border-color)',
    fontSize: 11,
    fontFamily: 'monospace',
    color: 'var(--text-muted)',
    wordBreak: 'break-all',
    maxHeight: 60,
    overflowY: 'auto'
  },
  btnDownloadSingle: {
    marginTop: 6,
    padding: '10px 14px',
    borderRadius: 6,
    backgroundColor: 'var(--primary)',
    border: 'none',
    color: '#ffffff',
    fontSize: 13,
    fontWeight: 700,
    cursor: 'pointer',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    transition: 'background 0.15s'
  },
  btnSecondary: {
    padding: '6px 12px',
    borderRadius: 6,
    backgroundColor: 'var(--bg-surface)',
    border: '1px solid var(--border-color)',
    color: 'var(--text-main)',
    fontSize: 12,
    fontWeight: 600,
    cursor: 'pointer',
    display: 'flex',
    alignItems: 'center'
  },
  btnSecondaryActive: {
    backgroundColor: 'var(--primary-glow)',
    borderColor: 'var(--primary)',
    color: 'var(--primary)'
  },
  btnSave: {
    padding: '6px 14px',
    borderRadius: 6,
    backgroundColor: '#3b82f6',
    border: 'none',
    color: '#ffffff',
    fontSize: 12,
    fontWeight: 700,
    cursor: 'pointer',
    display: 'flex',
    alignItems: 'center'
  },
  btnDownloadPrimary: {
    padding: '0 16px',
    height: 34,
    borderRadius: 6,
    backgroundColor: '#10b981',
    border: 'none',
    color: '#ffffff',
    fontSize: 12.5,
    fontWeight: 700,
    cursor: 'pointer',
    display: 'flex',
    alignItems: 'center',
    whiteSpace: 'nowrap'
  }
};
