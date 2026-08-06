import React, { useState, useEffect, useRef } from 'react';
import { Terminal, Trash2, ArrowDownCircle, CheckCircle2, AlertTriangle } from 'lucide-react';
import { subscribeLogs } from '../services/api';

export default function LogConsole({ activeJobId, logs: externalLogs, onClearLogs }) {
  const [internalLogs, setInternalLogs] = useState([]);
  const [autoScroll, setAutoScroll] = useState(true);
  const logEndRef = useRef(null);

  const logs = externalLogs !== undefined ? externalLogs : internalLogs;

  useEffect(() => {
    if (externalLogs !== undefined) return; // Managed externally

    const unsubscribe = subscribeLogs(
      activeJobId || 'default',
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
    if (autoScroll && logEndRef.current) {
      logEndRef.current.scrollIntoView({ behavior: 'smooth' });
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
    return { color: '#cbd5e1' }; // Light slate
  };

  return (
    <div style={styles.container}>
      <div style={styles.header}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
          <Terminal size={18} color="#818cf8" />
          <h2 style={styles.title}>Terminal Logs Realtime</h2>
          <span style={styles.badge}>{logs.length} dòng</span>
        </div>

        <div style={{ display: 'flex', gap: 10 }}>
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

      <div style={styles.terminalBody}>
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
        <div ref={logEndRef} />
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
    color: '#f8fafc'
  },
  badge: {
    fontSize: 11,
    backgroundColor: '#334155',
    color: '#94a3b8',
    padding: '2px 8px',
    borderRadius: 12
  },
  btnToggle: {
    backgroundColor: '#1e293b',
    color: '#94a3b8',
    border: '1px solid #334155',
    padding: '6px 12px',
    borderRadius: 6,
    fontSize: 12,
    cursor: 'pointer',
    display: 'flex',
    alignItems: 'center'
  },
  btnToggleActive: {
    backgroundColor: 'rgba(99, 102, 241, 0.2)',
    color: '#818cf8',
    borderColor: '#6366f1'
  },
  btnClear: {
    backgroundColor: '#1e293b',
    color: '#f87171',
    border: '1px solid rgba(248, 113, 113, 0.3)',
    padding: '6px 12px',
    borderRadius: 6,
    fontSize: 12,
    cursor: 'pointer',
    display: 'flex',
    alignItems: 'center'
  },
  terminalBody: {
    backgroundColor: '#090d16',
    border: '1px solid #1e293b',
    borderRadius: 12,
    padding: 16,
    flex: 1,
    overflowY: 'auto',
    fontFamily: '"Fira Code", "Source Code Pro", Menlo, Monaco, Consolas, monospace',
    fontSize: 12,
    lineHeight: 1.6,
    boxShadow: 'inset 0 2px 4px rgba(0,0,0,0.5)'
  },
  emptyTerminal: {
    height: '100%',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    color: '#475569',
    fontStyle: 'italic'
  },
  logLine: {
    whiteSpace: 'pre-wrap',
    wordBreak: 'break-word',
    marginBottom: 4
  },
  timeTag: {
    color: '#475569',
    marginRight: 8
  }
};
