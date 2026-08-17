import React, { useState } from 'react';
import { 
  Plus, 
  Film, 
  Star, 
  Trash2, 
  Cloud, 
  HardDrive, 
  Video, 
  Languages, 
  Layers, 
  Download, 
  Wand2, 
  Settings, 
  Terminal, 
  Users, 
  ChevronDown, 
  FolderOpen,
  FolderPlus,
  RefreshCw,
  Zap,
  CheckCircle,
  Database
} from 'lucide-react';

export default function ModernSidebar({
  projects = [],
  activeProject = '',
  onSelectProject,
  onCreateProject,
  activeTab = 'editor',
  onSelectTab,
  libraryFilter = 'all',
  onSelectLibraryFilter,
  videoCounts = { all: 0, output: 0, src: 0, favorites: 0 },
  storageInfo = { usedStr: '128.5 MB', totalStr: '500 GB', percentage: 25.7 },
  onOpenUploadModal,
  onOpenDouyinModal
}) {
  const [showNewProjModal, setShowNewProjModal] = useState(false);
  const [newProjName, setNewProjName] = useState('');
  const [showUploadDropdown, setShowUploadDropdown] = useState(false);

  const handleCreateProj = (e) => {
    e.preventDefault();
    if (newProjName.trim()) {
      onCreateProject && onCreateProject(newProjName.trim());
      setNewProjName('');
      setShowNewProjModal(false);
    }
  };

  return (
    <aside style={styles.sidebar}>
      {/* Upload Action Button */}
      <div style={styles.uploadContainer}>
        <button 
          style={styles.uploadBtn}
          onClick={() => setShowUploadDropdown(!showUploadDropdown)}
        >
          <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
            <Plus size={16} strokeWidth={2.5} />
            <span>+ Upload Video</span>
          </div>
          <ChevronDown size={14} />
        </button>

        {showUploadDropdown && (
          <div style={styles.uploadDropdown}>
            <div 
              style={styles.uploadDropdownItem}
              onClick={() => {
                setShowUploadDropdown(false);
                onOpenUploadModal && onOpenUploadModal();
              }}
            >
              <FolderOpen size={14} color="var(--primary)" />
              <span>Chọn file từ máy tính</span>
            </div>
            <div 
              style={styles.uploadDropdownItem}
              onClick={() => {
                setShowUploadDropdown(false);
                onOpenDouyinModal && onOpenDouyinModal();
              }}
            >
              <Download size={14} color="#06b6d4" />
              <span>Tải từ link Douyin</span>
            </div>
            <div 
              style={styles.uploadDropdownItem}
              onClick={() => {
                setShowUploadDropdown(false);
                setShowNewProjModal(true);
              }}
            >
              <FolderPlus size={14} color="var(--accent-green)" />
              <span>Tạo Dự Án Mới</span>
            </div>
          </div>
        )}
      </div>

      {/* Project Selector Mini Bar */}
      <div style={styles.projectSelectorBar}>
        <div style={styles.projectHeader}>
          <span style={styles.sectionHeading}>PROJECT</span>
          <button 
            style={styles.iconMiniBtn} 
            onClick={() => setShowNewProjModal(true)} 
            title="Tạo dự án mới"
          >
            <Plus size={13} />
          </button>
        </div>
        <select 
          value={activeProject || ''} 
          onChange={(e) => onSelectProject && onSelectProject(e.target.value)}
          style={styles.projectSelect}
        >
          {projects.map(p => (
            <option key={p.name} value={p.name}>
              📁 {p.name} ({p.srcCount || 0} src, {p.outputCount || 0} out)
            </option>
          ))}
        </select>
      </div>

      {/* Scrollable Navigation Groups */}
      <div style={styles.navScrollArea}>
        {/* Section: LIBRARY */}
        <div style={styles.navGroup}>
          <span style={styles.sectionHeading}>LIBRARY</span>
          
          <button
            style={{
              ...styles.navItem,
              ...(activeTab === 'editor' && libraryFilter === 'all' ? styles.navItemActive : {})
            }}
            onClick={() => {
              onSelectTab && onSelectTab('editor');
              onSelectLibraryFilter && onSelectLibraryFilter('all');
            }}
          >
            <div style={styles.navLabelWrapper}>
              <Film size={15} />
              <span>All Videos</span>
            </div>
            <span style={styles.countBadge}>{videoCounts.all || 0}</span>
          </button>

          <button
            style={{
              ...styles.navItem,
              ...(activeTab === 'editor' && libraryFilter === 'src' ? styles.navItemActive : {})
            }}
            onClick={() => {
              onSelectTab && onSelectTab('editor');
              onSelectLibraryFilter && onSelectLibraryFilter('src');
            }}
          >
            <div style={styles.navLabelWrapper}>
              <FolderOpen size={15} color="#38bdf8" />
              <span>Gốc (Src)</span>
            </div>
            <span style={styles.countBadge}>{videoCounts.src || 0}</span>
          </button>

          <button
            style={{
              ...styles.navItem,
              ...(activeTab === 'editor' && libraryFilter === 'cut' ? styles.navItemActive : {})
            }}
            onClick={() => {
              onSelectTab && onSelectTab('editor');
              onSelectLibraryFilter && onSelectLibraryFilter('cut');
            }}
          >
            <div style={styles.navLabelWrapper}>
              <Layers size={15} color="#06b6d4" />
              <span>Đã Cắt (Cut)</span>
            </div>
            <span style={styles.countBadge}>{videoCounts.cut || 0}</span>
          </button>

          <button
            style={{
              ...styles.navItem,
              ...(activeTab === 'editor' && libraryFilter === 'merge' ? styles.navItemActive : {})
            }}
            onClick={() => {
              onSelectTab && onSelectTab('editor');
              onSelectLibraryFilter && onSelectLibraryFilter('merge');
            }}
          >
            <div style={styles.navLabelWrapper}>
              <Layers size={15} color="#c084fc" />
              <span>Đã Ghép (Merge)</span>
            </div>
            <span style={styles.countBadge}>{videoCounts.merge || 0}</span>
          </button>

          <button
            style={{
              ...styles.navItem,
              ...(activeTab === 'editor' && libraryFilter === 'output' ? styles.navItemActive : {})
            }}
            onClick={() => {
              onSelectTab && onSelectTab('editor');
              onSelectLibraryFilter && onSelectLibraryFilter('output');
            }}
          >
            <div style={styles.navLabelWrapper}>
              <Star size={15} color="#facc15" />
              <span>Đã Dịch (Output)</span>
            </div>
            <span style={styles.countBadge}>{videoCounts.output || 0}</span>
          </button>
        </div>

        {/* Section: CLOUD */}
        <div style={styles.navGroup}>
          <span style={styles.sectionHeading}>CLOUD STORAGE</span>
          
          <button
            style={{
              ...styles.navItem,
              ...(activeTab === 'cloud' ? styles.navItemActive : {})
            }}
            onClick={() => onSelectTab && onSelectTab('cloud')}
          >
            <div style={styles.navLabelWrapper}>
              <Cloud size={15} color="#3b82f6" />
              <span>Google Cloud (GCS)</span>
            </div>
            <span style={{ ...styles.statusDot, backgroundColor: 'var(--accent-green)' }} />
          </button>

          <div style={{ ...styles.navItem, opacity: 0.5, cursor: 'not-allowed' }}>
            <div style={styles.navLabelWrapper}>
              <Database size={15} color="#c084fc" />
              <span>R2 Storage</span>
            </div>
            <span style={{ fontSize: 10, color: 'var(--text-dim)' }}>Ready</span>
          </div>

          <div style={{ ...styles.navItem, opacity: 0.5, cursor: 'not-allowed' }}>
            <div style={styles.navLabelWrapper}>
              <HardDrive size={15} color="#38bdf8" />
              <span>OneDrive</span>
            </div>
          </div>
        </div>

        {/* Section: TOOLS */}
        <div style={styles.navGroup}>
          <span style={styles.sectionHeading}>TOOLS</span>
          
          <button
            style={{
              ...styles.navItem,
              ...(activeTab === 'editor' ? styles.navItemActive : {})
            }}
            onClick={() => onSelectTab && onSelectTab('editor')}
          >
            <div style={styles.navLabelWrapper}>
              <Video size={15} color="#60a5fa" />
              <span>Video Editor</span>
            </div>
          </button>

          <button
            style={{
              ...styles.navItem,
              ...(activeTab === 'studio' ? styles.navItemActive : {})
            }}
            onClick={() => onSelectTab && onSelectTab('studio')}
          >
            <div style={styles.navLabelWrapper}>
              <Layers size={15} color="#a855f7" />
              <span>Ghép & Cắt Studio</span>
            </div>
          </button>

          <button
            style={{
              ...styles.navItem,
              ...(activeTab === 'downloader' ? styles.navItemActive : {})
            }}
            onClick={() => onSelectTab && onSelectTab('downloader')}
          >
            <div style={styles.navLabelWrapper}>
              <Download size={15} color="#06b6d4" />
              <span>Tải Video Douyin</span>
            </div>
          </button>
        </div>

        {/* Section: SYSTEM */}
        <div style={styles.navGroup}>
          <span style={styles.sectionHeading}>SYSTEM</span>
          
          <button
            style={{
              ...styles.navItem,
              ...(activeTab === 'config' ? styles.navItemActive : {})
            }}
            onClick={() => onSelectTab && onSelectTab('config')}
          >
            <div style={styles.navLabelWrapper}>
              <Settings size={15} />
              <span>Config (YAML)</span>
            </div>
          </button>

          <button
            style={{
              ...styles.navItem,
              ...(activeTab === 'logs' ? styles.navItemActive : {})
            }}
            onClick={() => onSelectTab && onSelectTab('logs')}
          >
            <div style={styles.navLabelWrapper}>
              <Terminal size={15} />
              <span>Process Logs</span>
            </div>
          </button>
        </div>
      </div>

      {/* Bottom Area: Storage Meter & User Profile */}
      <div style={styles.bottomSection}>
        {/* Storage Usage Widget */}
        <div style={styles.storageCard}>
          <div style={styles.storageHeader}>
            <span style={styles.storageTitle}>Storage Usage</span>
            <span style={styles.storageValue}>{storageInfo.percentage}%</span>
          </div>
          <div style={styles.progressBarBg}>
            <div 
              style={{ 
                ...styles.progressBarFill, 
                width: `${Math.min(100, storageInfo.percentage)}%` 
              }} 
            />
          </div>
          <div style={styles.storageDetail}>
            <span>{storageInfo.usedStr}</span>
            <span>/ {storageInfo.totalStr}</span>
          </div>
        </div>

        {/* User Card */}
        <div style={styles.userCard}>
          <div style={styles.userAvatar}>
            <span>A</span>
            <div style={styles.userOnlineDot} />
          </div>
          <div style={styles.userInfo}>
            <span style={styles.userName}>admin</span>
            <span style={styles.userRole}>Administrator</span>
          </div>
          <CheckCircle size={14} color="var(--accent-green)" />
        </div>
      </div>

      {/* Modal Tạo Dự Án Mới */}
      {showNewProjModal && (
        <div style={styles.modalOverlay} onClick={() => setShowNewProjModal(false)}>
          <div style={styles.modalCard} onClick={e => e.stopPropagation()}>
            <h3 style={{ fontSize: 16, fontWeight: 700, marginBottom: 12 }}>Tạo Dự Án Mới</h3>
            <form onSubmit={handleCreateProj}>
              <input
                type="text"
                placeholder="Tên dự án (vd: foods, fashions...)"
                value={newProjName}
                onChange={e => setNewProjName(e.target.value)}
                style={styles.modalInput}
                autoFocus
              />
              <div style={{ display: 'flex', justifyContent: 'flex-end', gap: 8, marginTop: 14 }}>
                <button 
                  type="button" 
                  style={styles.modalCancelBtn} 
                  onClick={() => setShowNewProjModal(false)}
                >
                  Hủy
                </button>
                <button type="submit" style={styles.modalSubmitBtn}>
                  Tạo Dự Án
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </aside>
  );
}

const styles = {
  sidebar: {
    width: '240px',
    backgroundColor: 'var(--bg-sidebar)',
    borderRight: '1px solid var(--border-color)',
    display: 'flex',
    flexDirection: 'column',
    height: '100vh',
    flexShrink: 0,
    userSelect: 'none',
  },
  uploadContainer: {
    padding: '14px 14px 8px 14px',
    position: 'relative',
  },
  uploadBtn: {
    width: '100%',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between',
    padding: '9px 14px',
    backgroundColor: 'var(--primary)',
    color: '#ffffff',
    borderRadius: 'var(--radius-sm)',
    fontSize: 13,
    fontWeight: 600,
    boxShadow: '0 2px 8px rgba(59, 130, 246, 0.35)',
    border: 'none',
  },
  uploadDropdown: {
    position: 'absolute',
    top: 'calc(100% + 4px)',
    left: 14,
    right: 14,
    backgroundColor: 'var(--bg-card)',
    border: '1px solid var(--border-color)',
    borderRadius: 'var(--radius-md)',
    boxShadow: 'var(--shadow-lg)',
    zIndex: 120,
    padding: 6,
    display: 'flex',
    flexDirection: 'column',
    gap: 2,
  },
  uploadDropdownItem: {
    display: 'flex',
    alignItems: 'center',
    gap: 8,
    padding: '8px 10px',
    borderRadius: 'var(--radius-sm)',
    fontSize: 12,
    color: 'var(--text-main)',
    cursor: 'pointer',
    backgroundColor: 'transparent',
    transition: 'background-color 0.15s ease',
  },
  projectSelectorBar: {
    padding: '6px 14px 10px 14px',
    borderBottom: '1px solid var(--border-subtle)',
  },
  projectHeader: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between',
    marginBottom: 4,
  },
  iconMiniBtn: {
    background: 'none',
    border: 'none',
    color: 'var(--text-muted)',
    padding: 2,
  },
  projectSelect: {
    width: '100%',
    padding: '5px 8px',
    backgroundColor: 'var(--bg-surface)',
    border: '1px solid var(--border-color)',
    color: 'var(--text-main)',
    borderRadius: 'var(--radius-sm)',
    fontSize: 12,
    cursor: 'pointer',
  },
  navScrollArea: {
    flex: 1,
    overflowY: 'auto',
    padding: '10px 12px',
    display: 'flex',
    flexDirection: 'column',
    gap: 16,
  },
  navGroup: {
    display: 'flex',
    flexDirection: 'column',
    gap: 2,
  },
  sectionHeading: {
    fontSize: 11,
    fontWeight: 700,
    letterSpacing: '0.6px',
    color: 'var(--text-dim)',
    padding: '0 8px 4px 8px',
  },
  navItem: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between',
    padding: '7px 10px',
    borderRadius: 'var(--radius-sm)',
    backgroundColor: 'transparent',
    color: 'var(--text-muted)',
    fontSize: 13,
    fontWeight: 500,
    borderTop: 'none',
    borderRight: 'none',
    borderBottom: 'none',
    borderLeft: '3px solid transparent',
    textAlign: 'left',
    transition: 'all 0.15s ease',
  },
  navItemActive: {
    backgroundColor: 'var(--primary-glow)',
    color: 'var(--primary)',
    fontWeight: 600,
    borderLeft: '3px solid var(--primary)',
    borderRadius: '0 var(--radius-sm) var(--radius-sm) 0',
  },
  navLabelWrapper: {
    display: 'flex',
    alignItems: 'center',
    gap: 10,
  },
  countBadge: {
    fontSize: 11,
    fontWeight: 600,
    padding: '1px 6px',
    borderRadius: 10,
    backgroundColor: 'rgba(255, 255, 255, 0.08)',
    color: 'var(--text-dim)',
  },
  statusDot: {
    width: 7,
    height: 7,
    borderRadius: '50%',
  },
  bottomSection: {
    padding: '12px 14px',
    borderTop: '1px solid var(--border-subtle)',
    display: 'flex',
    flexDirection: 'column',
    gap: 10,
    backgroundColor: 'var(--bg-sidebar)',
  },
  storageCard: {
    padding: '10px 12px',
    backgroundColor: 'var(--bg-surface)',
    borderRadius: 'var(--radius-sm)',
    border: '1px solid var(--border-color)',
    display: 'flex',
    flexDirection: 'column',
    gap: 6,
  },
  storageHeader: {
    display: 'flex',
    justifyContent: 'space-between',
    fontSize: 11,
    color: 'var(--text-dim)',
  },
  storageTitle: {
    fontWeight: 600,
  },
  storageValue: {
    color: 'var(--primary-light)',
    fontWeight: 600,
  },
  progressBarBg: {
    height: 5,
    backgroundColor: 'rgba(255, 255, 255, 0.08)',
    borderRadius: 3,
    overflow: 'hidden',
  },
  progressBarFill: {
    height: '100%',
    backgroundColor: 'var(--primary)',
    borderRadius: 3,
    transition: 'width 0.3s ease',
  },
  storageDetail: {
    display: 'flex',
    gap: 4,
    fontSize: 10,
    color: 'var(--text-dim)',
  },
  userCard: {
    display: 'flex',
    alignItems: 'center',
    gap: 10,
    padding: '6px 8px',
  },
  userAvatar: {
    width: 28,
    height: 28,
    borderRadius: '50%',
    backgroundColor: 'var(--primary)',
    color: '#ffffff',
    fontWeight: 700,
    fontSize: 12,
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    position: 'relative',
  },
  userOnlineDot: {
    position: 'absolute',
    bottom: -1,
    right: -1,
    width: 8,
    height: 8,
    borderRadius: '50%',
    backgroundColor: 'var(--accent-green)',
    border: '1.5px solid var(--bg-sidebar)',
  },
  userInfo: {
    flex: 1,
    display: 'flex',
    flexDirection: 'column',
  },
  userName: {
    fontSize: 12,
    fontWeight: 600,
    color: 'var(--text-main)',
  },
  userRole: {
    fontSize: 10,
    color: 'var(--text-dim)',
  },
  modalOverlay: {
    position: 'fixed',
    top: 0,
    left: 0,
    right: 0,
    bottom: 0,
    backgroundColor: 'rgba(0, 0, 0, 0.65)',
    backdropFilter: 'blur(4px)',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    zIndex: 1000,
  },
  modalCard: {
    width: 360,
    backgroundColor: 'var(--bg-card)',
    borderRadius: 'var(--radius-md)',
    border: '1px solid var(--border-color)',
    padding: '20px',
    boxShadow: 'var(--shadow-lg)',
  },
  modalInput: {
    width: '100%',
    padding: '8px 12px',
    fontSize: 13,
    borderRadius: 'var(--radius-sm)',
    border: '1px solid var(--border-color)',
    backgroundColor: 'var(--bg-input)',
    color: '#ffffff',
  },
  modalCancelBtn: {
    padding: '6px 12px',
    backgroundColor: 'transparent',
    color: 'var(--text-muted)',
    borderRadius: 'var(--radius-sm)',
    fontSize: 12,
    border: '1px solid var(--border-color)',
  },
  modalSubmitBtn: {
    padding: '6px 14px',
    backgroundColor: 'var(--primary)',
    color: '#ffffff',
    borderRadius: 'var(--radius-sm)',
    fontSize: 12,
    fontWeight: 600,
    border: 'none',
  }
};
