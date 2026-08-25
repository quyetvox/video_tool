import React, { useState, useRef, useEffect } from 'react';
import { 
  Terminal, 
  Trash2, 
  Square, 
  ChevronDown, 
  Filter, 
  ArrowDown, 
  CheckCircle2, 
  AlertTriangle, 
  Info, 
  XCircle,
  Clock
} from 'lucide-react';

export default function ProcessLogsConsole({
  logs = [],
  isProcessRunning = false,
  onClearLogs,
  onStopProcess
}) {
  const [levelFilter, setLevelFilter] = useState('all'); // 'all' | 'info' | 'success' | 'error'
  const [autoScroll, setAutoScroll] = useState(true);
  const logEndRef = useRef(null);

  // Auto scroll to bottom when new logs arrive
  useEffect(() => {
    if (autoScroll && logEndRef.current) {
      logEndRef.current.scrollIntoView({ behavior: 'smooth' });
    }
  }, [logs, autoScroll]);

  const getLogType = (text = '', origType = '') => {
    if (origType === 'system-success' || text.includes('🎉') || text.includes('hoàn thành') || text.includes('thành công') || text.includes('SUCCESS')) {
      return 'SUCCESS';
    }
    if (origType === 'stderr' || origType === 'system-error' || text.includes('❌') || text.includes('ERROR') || text.includes('Failed') || text.includes('Traceback')) {
      return 'ERROR';
    }
    if (text.includes('⚠️') || text.includes('WARNING')) {
      return 'WARN';
    }
    return 'INFO';
  };

  const filteredLogs = logs.filter(log => {
    if (levelFilter === 'all') return true;
    const type = getLogType(log.text, log.type).toLowerCase();
    return type === levelFilter.toLowerCase();
  });

  return (
    <div style={styles.container}>
      {/* Header */}
      <div style={styles.header}>
        <div style={styles.headerLeft}>
          <Terminal size={14} color="var(--primary-light)" />
          <h3 style={styles.title}>Process Logs</h3>
          {isProcessRunning && (
            <span className="badge badge-processing" style={{ fontSize: 10 }}>
              <span className="spin-icon">⚙️</span> Running
            </span>
          )}
        </div>

        <div style={styles.headerRight}>
          {/* Level Filter */}
          <select
            value={levelFilter}
            onChange={e => setLevelFilter(e.target.value)}
            style={styles.filterSelect}
          >
            <option value="all">All Levels</option>
            <option value="info">INFO only</option>
            <option value="success">SUCCESS only</option>
            <option value="error">ERROR only</option>
          </select>

          {/* Stop Button */}
          {isProcessRunning && (
            <button 
              style={styles.stopBtn}
              onClick={onStopProcess}
              title="Dừng tiến trình đang chạy"
            >
              <Square size={11} fill="currentColor" />
              <span>Stop</span>
            </button>
          )}

          {/* Clear Button */}
          <button 
            style={styles.iconBtn}
            onClick={onClearLogs}
            title="Xóa màn hình log"
          >
            <Trash2 size={12} />
            <span>Clear</span>
          </button>
        </div>
      </div>

      {/* Log Stream Content */}
      <div style={styles.body}>
        {filteredLogs.length === 0 ? (
          <div style={styles.emptyState}>
            <Terminal size={24} color="var(--text-dim)" />
            <span style={{ fontSize: 11, color: 'var(--text-dim)', marginTop: 4 }}>
              Chưa có logs tiến trình nào
            </span>
          </div>
        ) : (
          <div style={styles.logList}>
            {filteredLogs.map((item, idx) => {
              const type = getLogType(item.text, item.type);

              return (
                <div key={item.id || idx} style={styles.logRow}>
                  {/* Badge */}
                  <span 
                    style={{
                      ...styles.typeBadge,
                      ...(type === 'SUCCESS' ? styles.badgeSuccess : {}),
                      ...(type === 'ERROR' ? styles.badgeError : {}),
                      ...(type === 'WARN' ? styles.badgeWarn : {}),
                      ...(type === 'INFO' ? styles.badgeInfo : {})
                    }}
                  >
                    {type}
                  </span>

                  {/* Timestamp */}
                  <span style={styles.timestamp}>
                    {item.time || '10:30:15'}
                  </span>

                  {/* Message */}
                  <span 
                    style={{
                      ...styles.logMessage,
                      ...(type === 'SUCCESS' ? { color: '#86efac' } : {}),
                      ...(type === 'ERROR' ? { color: '#fca5a5' } : {})
                    }}
                  >
                    {item.text}
                  </span>
                </div>
              );
            })}
            <div ref={logEndRef} />
          </div>
        )}
      </div>
    </div>
  );
}

const styles = {
  container: {
    backgroundColor: 'var(--bg-card)',
    borderRadius: 'var(--radius-md)',
    border: '1px solid var(--border-color)',
    display: 'flex',
    flexDirection: 'column',
    height: '100%',
    overflow: 'hidden',
    boxShadow: 'var(--shadow-sm)',
  },
  header: {
    padding: '8px 12px',
    borderBottom: '1px solid var(--border-color)',
    backgroundColor: 'var(--bg-surface)',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  headerLeft: {
    display: 'flex',
    alignItems: 'center',
    gap: 8,
  },
  title: {
    fontSize: 13,
    fontWeight: 700,
    color: 'var(--text-main)',
  },
  headerRight: {
    display: 'flex',
    alignItems: 'center',
    gap: 6,
  },
  filterSelect: {
    padding: '3px 6px',
    fontSize: 11,
    backgroundColor: 'var(--bg-input)',
    border: '1px solid var(--border-color)',
    color: 'var(--text-main)',
    borderRadius: 'var(--radius-sm)',
  },
  stopBtn: {
    display: 'flex',
    alignItems: 'center',
    gap: 4,
    padding: '3px 8px',
    backgroundColor: 'rgba(239, 68, 68, 0.15)',
    color: 'var(--accent-red)',
    border: '1px solid rgba(239, 68, 68, 0.4)',
    borderRadius: 'var(--radius-sm)',
    fontSize: 11,
    fontWeight: 600,
  },
  iconBtn: {
    display: 'flex',
    alignItems: 'center',
    gap: 4,
    padding: '3px 8px',
    backgroundColor: 'var(--bg-input)',
    color: 'var(--text-muted)',
    border: '1px solid var(--border-color)',
    borderRadius: 'var(--radius-sm)',
    fontSize: 11,
  },
  body: {
    flex: 1,
    overflowY: 'auto',
    backgroundColor: 'var(--bg-card)',
    padding: '8px 10px',
  },
  emptyState: {
    height: '100%',
    display: 'flex',
    flexDirection: 'column',
    alignItems: 'center',
    justifyContent: 'center',
  },
  logList: {
    display: 'flex',
    flexDirection: 'column',
    gap: 4,
    fontFamily: 'monospace',
    fontSize: 11,
  },
  logRow: {
    display: 'flex',
    alignItems: 'flex-start',
    gap: 8,
    lineHeight: 1.4,
    wordBreak: 'break-word',
  },
  typeBadge: {
    fontSize: 9,
    fontWeight: 700,
    padding: '1px 5px',
    borderRadius: 3,
    flexShrink: 0,
    textTransform: 'uppercase',
  },
  badgeInfo: {
    backgroundColor: 'rgba(59, 130, 246, 0.2)',
    color: '#60a5fa',
  },
  badgeSuccess: {
    backgroundColor: 'rgba(16, 185, 129, 0.2)',
    color: '#34d399',
  },
  badgeError: {
    backgroundColor: 'rgba(239, 68, 68, 0.2)',
    color: '#f87171',
  },
  badgeWarn: {
    backgroundColor: 'rgba(245, 158, 11, 0.2)',
    color: '#fbbf24',
  },
  timestamp: {
    color: 'var(--text-dim)',
    fontSize: 10,
    flexShrink: 0,
  },
  logMessage: {
    color: 'var(--text-main)',
    flex: 1,
  }
};
