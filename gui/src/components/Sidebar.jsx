import React, { useState } from 'react';
import { 
  FolderOpen, 
  Scissors, 
  Download, 
  Settings, 
  Terminal, 
  Plus, 
  Video, 
  Sparkles,
  Layers
} from 'lucide-react';

export default function Sidebar({ 
  projects, 
  activeProject, 
  onSelectProject, 
  onCreateProject,
  activeTab, 
  onSelectTab 
}) {
  const [showNewModal, setShowNewModal] = useState(false);
  const [newProjName, setNewProjName] = useState('');

  const handleCreate = (e) => {
    e.preventDefault();
    if (newProjName.trim()) {
      onCreateProject(newProjName.trim());
      setNewProjName('');
      setShowNewModal(false);
    }
  };

  const navItems = [
    { id: 'dashboard', label: 'Quản Lý Video & Job', icon: FolderOpen },
    { id: 'trimmer', label: 'Cắt Video (Trimmer)', icon: Scissors },
    { id: 'downloader', label: 'Tải Video Douyin', icon: Download },
    { id: 'config', label: 'Cấu Hình Config.yaml', icon: Settings },
    { id: 'logs', label: 'Terminal Logs Live', icon: Terminal },
  ];

  return (
    <div style={styles.sidebar}>
      {/* Brand Header */}
      <div style={styles.brand}>
        <div style={styles.brandLogo}>
          <Sparkles size={22} color="#6366f1" />
        </div>
        <div>
          <h1 style={styles.brandTitle}>Sub-Video AI</h1>
          <p style={styles.brandSubtitle}>Video Translator Studio</p>
        </div>
      </div>

      {/* Project Selector */}
      <div style={styles.section}>
        <div style={styles.sectionHeader}>
          <span style={styles.sectionTitle}>DỰ ÁN HIỆN TẠI</span>
          <button style={styles.iconBtn} onClick={() => setShowNewModal(true)} title="Tạo dự án mới">
            <Plus size={16} />
          </button>
        </div>

        <select 
          value={activeProject || ''} 
          onChange={(e) => onSelectProject(e.target.value)}
          style={styles.projectSelect}
        >
          {projects.map(p => (
            <option key={p.name} value={p.name}>
              📁 {p.name} ({p.srcCount} video, {p.outputCount} xong)
            </option>
          ))}
        </select>
      </div>

      {/* Navigation Tabs */}
      <div style={styles.section}>
        <span style={styles.sectionTitle}>CHỨC NĂNG CÔNG CỤ</span>
        <div style={styles.navList}>
          {navItems.map(item => {
            const Icon = item.icon;
            const isActive = activeTab === item.id;
            return (
              <button
                key={item.id}
                onClick={() => onSelectTab(item.id)}
                style={{
                  ...styles.navItem,
                  ...(isActive ? styles.navItemActive : {})
                }}
              >
                <Icon size={18} style={{ marginRight: 10, color: isActive ? '#818cf8' : '#94a3b8' }} />
                <span>{item.label}</span>
              </button>
            );
          })}
        </div>
      </div>

      {/* Footer Info */}
      <div style={styles.footer}>
        <Layers size={14} style={{ marginRight: 6 }} />
        <span>Sub-Video Engine v2.0 • Local</span>
      </div>

      {/* Modal create project */}
      {showNewModal && (
        <div style={styles.modalOverlay}>
          <div style={styles.modal}>
            <h3 style={{ margin: '0 0 12px 0', color: '#f8fafc' }}>Tạo Dự Án Mới</h3>
            <form onSubmit={handleCreate}>
              <input
                type="text"
                placeholder="Tên dự án (ví dụ: cooking, sports)..."
                value={newProjName}
                onChange={e => setNewProjName(e.target.value)}
                style={styles.modalInput}
                autoFocus
              />
              <div style={{ display: 'flex', gap: 8, justifyContent: 'flex-end', marginTop: 16 }}>
                <button type="button" onClick={() => setShowNewModal(false)} style={styles.btnSecondary}>
                  Hủy
                </button>
                <button type="submit" style={styles.btnPrimary}>
                  Tạo Mới
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
}

const styles = {
  sidebar: {
    width: 260,
    backgroundColor: '#0f172a',
    borderRight: '1px solid #1e293b',
    display: 'flex',
    flexDirection: 'column',
    height: '100vh',
    boxSizing: 'border-box',
    padding: 16,
    flexShrink: 0
  },
  brand: {
    display: 'flex',
    alignItems: 'center',
    gap: 12,
    paddingBottom: 20,
    borderBottom: '1px solid #1e293b'
  },
  brandLogo: {
    width: 40,
    height: 40,
    borderRadius: 10,
    backgroundColor: 'rgba(99, 102, 241, 0.15)',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    border: '1px solid rgba(99, 102, 241, 0.3)'
  },
  brandTitle: {
    fontSize: 16,
    fontWeight: 'bold',
    margin: 0,
    color: '#f8fafc'
  },
  brandSubtitle: {
    fontSize: 11,
    color: '#64748b',
    margin: 0
  },
  section: {
    marginTop: 20
  },
  sectionHeader: {
    display: 'flex',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: 8
  },
  sectionTitle: {
    fontSize: 10,
    fontWeight: 'bold',
    color: '#64748b',
    letterSpacing: 1
  },
  iconBtn: {
    background: 'none',
    border: 'none',
    color: '#94a3b8',
    cursor: 'pointer',
    padding: 2,
    borderRadius: 4
  },
  projectSelect: {
    width: '100%',
    padding: '8px 12px',
    borderRadius: 8,
    backgroundColor: '#1e293b',
    color: '#f8fafc',
    border: '1px solid #334155',
    fontSize: 13,
    outline: 'none',
    cursor: 'pointer'
  },
  navList: {
    display: 'flex',
    flexDirection: 'column',
    gap: 4
  },
  navItem: {
    display: 'flex',
    alignItems: 'center',
    padding: '10px 12px',
    borderRadius: 8,
    backgroundColor: 'transparent',
    border: 'none',
    color: '#94a3b8',
    fontSize: 13,
    cursor: 'pointer',
    textAlign: 'left',
    transition: 'all 0.15s ease'
  },
  navItemActive: {
    backgroundColor: 'rgba(99, 102, 241, 0.15)',
    color: '#818cf8',
    fontWeight: '600'
  },
  footer: {
    marginTop: 'auto',
    fontSize: 11,
    color: '#475569',
    display: 'flex',
    alignItems: 'center',
    paddingTop: 12,
    borderTop: '1px solid #1e293b'
  },
  modalOverlay: {
    position: 'fixed',
    top: 0, left: 0, right: 0, bottom: 0,
    backgroundColor: 'rgba(0,0,0,0.7)',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    zIndex: 1000
  },
  modal: {
    backgroundColor: '#1e293b',
    borderRadius: 12,
    padding: 24,
    width: 340,
    border: '1px solid #334155',
    boxShadow: '0 20px 25px -5px rgba(0, 0, 0, 0.5)'
  },
  modalInput: {
    width: '100%',
    padding: '10px 12px',
    borderRadius: 8,
    backgroundColor: '#0f172a',
    border: '1px solid #334155',
    color: '#f8fafc',
    boxSizing: 'border-box'
  },
  btnPrimary: {
    backgroundColor: '#6366f1',
    color: '#fff',
    border: 'none',
    padding: '8px 16px',
    borderRadius: 8,
    cursor: 'pointer',
    fontWeight: '600'
  },
  btnSecondary: {
    backgroundColor: '#334155',
    color: '#94a3b8',
    border: 'none',
    padding: '8px 16px',
    borderRadius: 8,
    cursor: 'pointer'
  }
};
