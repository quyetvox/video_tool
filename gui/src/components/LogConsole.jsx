import React, { useState, useEffect, useRef } from 'react';
import { Terminal, Trash2, ArrowDownCircle, CheckCircle2, AlertTriangle, Square, OctagonX } from 'lucide-react';
import { subscribeLogs, stopProcess } from '../services/api';

export default function LogConsole({ activeJobId, logs: externalLogs, onClearLogs, isProcessRunning = false, compact = false }) {
  const [internalLogs, setInternalLogs] = useState([]);
  const [autoScroll, setAutoScroll] = useState(true);
  const [isStopping, setIsStopping] = useState(false);
  const terminalBodyRef = useRef(null);

  const logs = externalLogs !== undefined ? externalLogs : internalLogs;

  const handleStop = async () => {
    try {
      setIsStopping(true);
      await stopProcess(activeJobId);
    } catch (err) {
      console.error('Failed to stop process:', err);
    } finally {
      setTimeout(() => setIsStopping(false), 1000);
    }
  };

  useEffect(() => {
    if (externalLogs !== undefined) return; // Managed externally

    const unsubscribe = subscribeLogs(
      activeJobId || 'global',
      (logData) => {
        setInternalLogs(prev => [...prev, {
          id: Date.now() + Math.random(),
          type: logData.type,
          text: logData.text,
          time: new Date().toLocaleTimeString()
        }]);
      },
      (exitData) => {
        setInternalLogs(prev => [...prev, {
          id: Date.now() + Math.random(),
          type: exitData.success ? 'system-success' : 'system-error',
          text: exitData.success ? '🎉 Tiến trình hoàn thành thành công!' : `❌ Tiến trình kết thúc với mã lỗi ${exitData.code}`,
          time: new Date().toLocaleTimeString()
        }]);
      }
    );

    return () => {
      unsubscribe();
    };
  }, [activeJobId, externalLogs]);

  useEffect(() => {
    if (autoScroll && terminalBodyRef.current) {
      terminalBodyRef.current.scrollTop = terminalBodyRef.current.scrollHeight;
    }
  }, [logs, autoScroll]);

  const handleClear = () => {
    if (onClearLogs) {
      onClearLogs();
    } else {
      setInternalLogs([]);
    }
  };

  const getLogStyle = (type, text) => {
    if (type === 'system-success' || text.includes('[✓]') || text.includes('successfully')) {
      return { color: '#10b981' }; // Green
    }
    if (type === 'system-error' || text.includes('ERROR') || text.includes('Lỗi') || type === 'stderr') {
      return { color: '#f87171' }; // Red
    }
    if (text.includes('[↺]') || text.includes('WARNING') || text.includes('Invalidating')) {
      return { color: '#fbbf24' }; // Amber/Yellow
    }
    if (text.includes('[→]') || text.includes('Executing')) {
      return { color: '#818cf8' }; // Indigo
    }
    return { color: 'var(--text-main)' };
  };

  return (
    <div style={{ ...styles.container, ...(compact ? styles.compactContainer : {}) }}>
      <div style={styles.header}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
          <Terminal size={18} color="var(--primary-light)" />
          <h2 style={{ ...styles.title, ...(compact ? { fontSize: 15 } : {}) }}>Terminal Logs Realtime</h2>
          <span style={styles.badge}>{logs.length} dòng</span>
          {isProcessRunning && (
            <span style={styles.runningPulse}>⚡ Đang chạy...</span>
          )}
        </div>

        <div style={{ display: 'flex', gap: 10, alignItems: 'center' }}>
          {(isProcessRunning || isStopping) && (
            <button
              onClick={handleStop}
              disabled={isStopping}
              style={styles.btnStop}
              title="Dừng tiến trình đang chạy (Ctrl+C / SIGINT)"
            >
              <Square size={13} style={{ marginRight: 6 }} fill="#ffffff" />
              {isStopping ? 'Đang dừng...' : 'Ngừng Process'}
            </button>
          )}

          <button
            onClick={() => setAutoScroll(!autoScroll)}
            style={{ ...styles.btnToggle, ...(autoScroll ? styles.btnToggleActive : {}) }}
          >
            <ArrowDownCircle size={14} style={{ marginRight: 6 }} /> Auto-Scroll
          </button>

          <button style={styles.btnClear} onClick={handleClear}>
            <Trash2 size={14} style={{ marginRight: 6 }} /> Xóa Log
          </button>
        </div>
      </div>

      <div ref={terminalBodyRef} style={styles.terminalBody}>
        {logs.length === 0 ? (
          <div style={styles.emptyTerminal}>
            <span>Đang chờ log từ tiến trình Sub-Video Engine...</span>
          </div>
        ) : (
          logs.map(log => (
            <div key={log.id} style={{ ...styles.logLine, ...getLogStyle(log.type, log.text) }}>
              <span style={styles.timeTag}>[{log.time}]</span>
              <span>{log.text}</span>
            </div>
          ))
        )}
      </div>
    </div>
  );
}

const styles = {
  container: {
    padding: 24,
    display: 'flex',
    flexDirection: 'column',
    height: '100%',
    boxSizing: 'border-box',
    flex: 1
  },
  header: {
    display: 'flex',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: 16
  },
  title: {
    fontSize: 20,
    fontWeight: 'bold',
    margin: 0,
    color: 'var(--text-main)'
  },
  badge: {
    fontSize: 11,
    backgroundColor: 'var(--bg-surface)',
    color: 'var(--text-muted)',
    border: '1px solid var(--border-color)',
    padding: '2px 8px',
    borderRadius: 12
  },
  compactContainer: {
    padding: 12,
    height: '100%',
    minHeight: 220
  },
  runningPulse: {
    fontSize: 11,
    color: '#ef4444',
    fontWeight: 'bold',
    backgroundColor: 'rgba(239, 68, 68, 0.15)',
    padding: '2px 8px',
    borderRadius: 12,
    border: '1px solid rgba(239, 68, 68, 0.4)'
  },
  btnStop: {
    backgroundColor: '#dc2626',
    color: '#ffffff',
    border: '1px solid #ef4444',
    padding: '6px 14px',
    borderRadius: 6,
    fontSize: 12,
    fontWeight: 'bold',
    cursor: 'pointer',
    display: 'flex',
    alignItems: 'center',
    boxShadow: '0 0 10px rgba(220, 38, 38, 0.5)',
    transition: 'all 0.15s ease'
  },
  btnToggle: {
    backgroundColor: 'var(--bg-surface)',
    color: 'var(--text-main)',
    border: '1px solid var(--border-color)',
    padding: '6px 12px',
    borderRadius: 6,
    fontSize: 12,
    cursor: 'pointer',
    display: 'flex',
    alignItems: 'center'
  },
  btnToggleActive: {
    backgroundColor: 'var(--primary-glow)',
    color: 'var(--primary)',
    borderColor: 'var(--primary)'
  },
  btnClear: {
    backgroundColor: 'var(--bg-surface)',
    color: 'var(--accent-red)',
    border: '1px solid var(--border-color)',
    padding: '6px 12px',
    borderRadius: 6,
    fontSize: 12,
    cursor: 'pointer',
    display: 'flex',
    alignItems: 'center'
  },
  terminalBody: {
    backgroundColor: 'var(--bg-card)',
    border: '1px solid var(--border-color)',
    borderRadius: 12,
    padding: 16,
    flex: 1,
    overflowY: 'auto',
    fontFamily: '"Fira Code", "Source Code Pro", Menlo, Monaco, Consolas, monospace',
    fontSize: 12,
    lineHeight: 1.6,
    boxShadow: 'var(--shadow-sm)'
  },
  emptyTerminal: {
    height: '100%',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    color: 'var(--text-dim)',
    fontStyle: 'italic'
  },
  logLine: {
    whiteSpace: 'pre-wrap',
    wordBreak: 'break-word',
    marginBottom: 4
  },
  timeTag: {
    color: 'var(--text-dim)',
    marginRight: 8
  }
};
