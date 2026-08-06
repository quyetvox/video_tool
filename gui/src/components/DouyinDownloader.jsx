import React, { useState } from 'react';
import { Download, Link2, Play, CheckCircle2 } from 'lucide-react';
import { runScript } from '../services/api';

export default function DouyinDownloader({ project, onSelectTab, onRefresh }) {
  const [urls, setUrls] = useState('');
  const [startIdx, setStartIdx] = useState(1);
  const [limitCount, setLimitCount] = useState(5);
  const [isDownloading, setIsDownloading] = useState(false);

  const handleDownload = async () => {
    if (!project) return;
    setIsDownloading(true);
    onSelectTab('logs');

    const linksFile = `assets/${project}/src/douyin-video-links.txt`;
    const args = [linksFile, '--start', startIdx.toString(), '--limit', limitCount.toString()];

    try {
      await runScript('download.py', args, `dl_${Date.now()}`);
      if (onRefresh) onRefresh();
    } catch (e) {
      console.error('Download failed:', e);
    } finally {
      setIsDownloading(false);
    }
  };

  return (
    <div style={styles.container}>
      <div style={styles.header}>
        <div>
          <h2 style={styles.title}>📥 Tải Video Douyin Hàng Loạt</h2>
          <p style={styles.subtitle}>Tải video gốc từ Douyin vào thư mục `assets/{project}/src/`</p>
        </div>
      </div>

      <div style={styles.card}>
        <div style={styles.formGroup}>
          <label style={styles.label}>
            <Link2 size={14} style={{ marginRight: 6 }} />
            Danh sách Link Douyin (File: `assets/{project}/src/douyin-video-links.txt`):
          </label>
          <textarea
            placeholder="Dán các URL Douyin vào đây (mỗi dòng 1 link)..."
            rows={8}
            value={urls}
            onChange={e => setUrls(e.target.value)}
            style={styles.textarea}
          />
        </div>

        <div style={styles.row}>
          <div style={styles.formGroup}>
            <label style={styles.label}>Vị trí bắt đầu (`--start`):</label>
            <input
              type="number"
              min="1"
              value={startIdx}
              onChange={e => setStartIdx(parseInt(e.target.value, 10) || 1)}
              style={styles.input}
            />
          </div>

          <div style={styles.formGroup}>
            <label style={styles.label}>Số lượng tải (`--limit`):</label>
            <input
              type="number"
              min="1"
              max="50"
              value={limitCount}
              onChange={e => setLimitCount(parseInt(e.target.value, 10) || 5)}
              style={styles.input}
            />
          </div>
        </div>

        <button
          style={styles.btnDownload}
          onClick={handleDownload}
          disabled={isDownloading}
        >
          <Download size={18} style={{ marginRight: 8 }} />
          {isDownloading ? 'Đang Tải Video...' : 'Bắt Đầu Tải Video Douyin'}
        </button>
      </div>
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
  card: {
    backgroundColor: '#1e293b',
    borderRadius: 12,
    padding: 24,
    border: '1px solid #334155',
    maxWidth: 700,
    display: 'flex',
    flexDirection: 'column',
    gap: 20
  },
  formGroup: {
    display: 'flex',
    flexDirection: 'column',
    gap: 8,
    flex: 1
  },
  label: {
    fontSize: 13,
    fontWeight: '600',
    color: '#94a3b8',
    display: 'flex',
    alignItems: 'center'
  },
  textarea: {
    padding: 12,
    borderRadius: 8,
    backgroundColor: '#0f172a',
    color: '#f8fafc',
    border: '1px solid #334155',
    fontSize: 13,
    fontFamily: 'monospace',
    outline: 'none'
  },
  row: {
    display: 'flex',
    gap: 20
  },
  input: {
    padding: '10px 12px',
    borderRadius: 8,
    backgroundColor: '#0f172a',
    color: '#f8fafc',
    border: '1px solid #334155',
    fontSize: 14
  },
  btnDownload: {
    backgroundColor: '#10b981',
    color: '#fff',
    border: 'none',
    padding: '12px 20px',
    borderRadius: 8,
    fontSize: 14,
    fontWeight: 'bold',
    cursor: 'pointer',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center'
  }
};
