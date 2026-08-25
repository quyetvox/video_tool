import React, { useState } from 'react';
import { 
  Save, 
  Share2, 
  Download, 
  CloudUpload, 
  Trash2, 
  MoreHorizontal, 
  Settings, 
  Bell, 
  Moon, 
  Sun, 
  User, 
  Sparkles, 
  Layers, 
  Play, 
  CheckCircle2, 
  ChevronRight,
  HardDrive,
  RefreshCw,
  Zap,
  Scissors,
  Mic
} from 'lucide-react';

export default function TopHeader({
  activeProject,
  activeVideo,
  activeTab = 'editor',
  onSelectTab,
  isBusy = false,
  runningCount = 0,
  studioToolMode = 'cut',
  onSetStudioToolMode,
  onStudioExport,
  onSave,
  onExport,
  onExportOcrOnly,
  onResume,
  onDownload,
  onUploadCloud,
  onDelete,
  onOpenConfig,
  onOpenStudio,
  onOpenDownloader,
  onRefresh,
  theme = 'dark',
  onToggleTheme
}) {
  const [showExportMenu, setShowExportMenu] = useState(false);
  const [showMoreMenu, setShowMoreMenu] = useState(false);

  const videoName = activeVideo ? activeVideo.name : 'Chưa chọn video';

  return (
    <header style={styles.header}>
      {/* Left: Brand & Breadcrumb */}
      <div style={styles.leftGroup}>
        <div style={styles.brand}>
          <img 
            src="/favicon.svg" 
            alt="Sub-Video AI Logo" 
            style={{ width: 22, height: 22, display: 'block', objectFit: 'contain' }} 
          />
          <span style={styles.brandText}>Video Studio</span>
        </div>

        {/* Top Header Navigation Tabs matching Design */}
        <div style={styles.topTabsGroup}>
          <button 
            style={{
              ...styles.topTabBtn,
              ...(activeTab === 'editor' ? styles.topTabBtnActive : {})
            }}
            onClick={() => onSelectTab && onSelectTab('editor')}
          >
            <span>Video Editor</span>
            {activeTab === 'editor' && <div style={styles.topTabIndicator} />}
          </button>

          <button 
            style={{
              ...styles.topTabBtn,
              ...(activeTab === 'cloud' ? styles.topTabBtnActive : {})
            }}
            onClick={() => onSelectTab && onSelectTab('cloud')}
          >
            <span>Cloud (GCS)</span>
            {activeTab === 'cloud' && <div style={styles.topTabIndicator} />}
          </button>

          <button 
            style={{
              ...styles.topTabBtn,
              ...(activeTab === 'logs' ? styles.topTabBtnActive : {})
            }}
            onClick={() => onSelectTab && onSelectTab('logs')}
          >
            <span>Logs</span>
            {activeTab === 'logs' && <div style={styles.topTabIndicator} />}
          </button>

          <button 
            style={{
              ...styles.topTabBtn,
              ...(activeTab === 'config' ? styles.topTabBtnActive : {})
            }}
            onClick={() => onSelectTab && onSelectTab('config')}
          >
            <span>Cấu hình</span>
            {activeTab === 'config' && <div style={styles.topTabIndicator} />}
          </button>
        </div>
      </div>

      {/* Center/Right: Action Toolbar */}
      <div style={styles.centerActions}>
        {activeTab === 'studio' ? (
          <>
            {/* Studio Action 1: Xuất video */}
            <button 
              style={{ ...styles.actionBtn, ...styles.studioExportBtn }}
              onClick={onStudioExport || onExport}
              title="Xuất video thành phẩm từ Studio"
              disabled={isBusy}
            >
              <Download size={13} />
              <span>Xuất video</span>
            </button>

            {/* Studio Action 2: 3 Chế Độ Cắt / Chia / Ghép */}
            <div style={styles.translateSegmentGroup}>
              <button 
                style={{ 
                  ...styles.segmentBtn, 
                  ...(studioToolMode === 'cut' ? styles.studioCutActiveBtn : styles.studioSegmentInactiveBtn) 
                }}
                onClick={() => onSetStudioToolMode && onSetStudioToolMode('cut')}
                title="Chế độ Cắt bỏ đoạn rác"
              >
                <Scissors size={13} />
                <span>Cắt bỏ rác</span>
              </button>
              <div style={styles.segmentDivider} />
              <button 
                style={{ 
                  ...styles.segmentBtn, 
                  ...(studioToolMode === 'split' ? styles.studioSplitActiveBtn : styles.studioSegmentInactiveBtn) 
                }}
                onClick={() => onSetStudioToolMode && onSetStudioToolMode('split')}
                title="Chế độ Chia clip tại chỗ (Phím S)"
              >
                <Layers size={13} style={{ transform: 'rotate(90deg)' }} />
                <span>Chia clip</span>
              </button>
              <div style={styles.segmentDivider} />
              <button 
                style={{ 
                  ...styles.segmentBtn, 
                  ...(studioToolMode === 'merge' ? styles.studioMergeActiveBtn : styles.studioSegmentInactiveBtn) 
                }}
                onClick={() => onSetStudioToolMode && onSetStudioToolMode('merge')}
                title="Chế độ Ghép nhiều video"
              >
                <Layers size={13} />
                <span>Ghép video</span>
              </button>
            </div>
          </>
        ) : (
          <>
            {/* Group 1: Save Config */}
            <button 
              style={{ ...styles.actionBtn, ...styles.saveBtn }}
              onClick={onSave}
              title="Lưu cấu hình dự án (config.yaml)"
              disabled={isBusy}
            >
              <Save size={13} />
              <span>Save Config</span>
            </button>

            {/* Group 2: Primary AI Translate & Resume Segmented Group */}
            <div style={styles.translateSegmentGroup}>
              <button 
                style={{ ...styles.segmentBtn, ...styles.voiceSegmentBtn }}
                onClick={onExport}
                disabled={!activeVideo || isBusy}
                title="Dịch Full Giọng Nói (Whisper ASR + Demucs + TTS AI)"
              >
                {isBusy ? <RefreshCw size={13} className="spin-icon" /> : <Mic size={13} />}
                <span>Voice</span>
              </button>
              <div style={styles.segmentDivider} />
              <button 
                style={{ ...styles.segmentBtn, ...styles.subSegmentBtn }}
                onClick={onExportOcrOnly}
                disabled={!activeVideo || isBusy}
                title="Dịch Sub Cứng Siêu Tốc (Fast OCR + Inpaint BoxBlur ~0s TTS)"
              >
                <Zap size={13} />
                <span>Sub</span>
              </button>
              <div style={styles.segmentDivider} />
              <button 
                style={{ ...styles.segmentBtn, ...styles.resumeSegmentBtn }}
                onClick={onResume}
                disabled={!activeVideo || isBusy}
                title="Chạy tiếp tục / Áp dụng thay đổi sub sửa tay (~2s)"
              >
                <Play size={12} fill="currentColor" />
                <span>Resume</span>
              </button>
            </div>
          </>
        )}

        {/* Group 3: Utility Icon Toolbar */}
        <div style={styles.toolIconGroup}>
          <button 
            style={styles.toolIconBtn}
            onClick={onDownload}
            title="Tải video thành phẩm về máy"
            disabled={!activeVideo}
          >
            <Download size={14} />
          </button>

          <button 
            style={styles.toolIconBtn}
            onClick={onUploadCloud}
            title="Đẩy video lên Google Cloud Storage"
            disabled={!activeVideo || isBusy}
          >
            <CloudUpload size={14} />
          </button>

          <button 
            style={{ ...styles.toolIconBtn, ...styles.deleteToolBtn }}
            onClick={onDelete}
            title="Xóa video hoặc workspace cache"
            disabled={!activeVideo || isBusy}
          >
            <Trash2 size={14} />
          </button>

          <div style={{ position: 'relative' }}>
            <button 
              style={styles.toolIconBtn}
              onClick={() => setShowMoreMenu(!showMoreMenu)}
              title="Thao tác nâng cao"
            >
              <MoreHorizontal size={15} />
            </button>

            {showMoreMenu && (
              <div style={{ ...styles.dropdownMenu, right: 0, width: 220 }}>
                <div 
                  style={styles.dropdownItem}
                  onClick={() => { setShowMoreMenu(false); onOpenStudio && onOpenStudio(); }}
                >
                  <Scissors size={14} color="#a855f7" />
                  <span>Ghép & Cắt Video Studio</span>
                </div>
                <div 
                  style={styles.dropdownItem}
                  onClick={() => { setShowMoreMenu(false); onOpenDownloader && onOpenDownloader(); }}
                >
                  <Download size={14} color="#06b6d4" />
                  <span>Tải Video Douyin</span>
                </div>
                <div 
                  style={styles.dropdownItem}
                  onClick={() => { setShowMoreMenu(false); onRefresh && onRefresh(); }}
                >
                  <RefreshCw size={14} color="#10b981" />
                  <span>Làm mới danh sách</span>
                </div>
              </div>
            )}
          </div>
        </div>
      </div>

      {/* Right: Config & Profile Controls */}
      <div style={styles.rightGroup}>
        <button 
          style={styles.utilityBtn}
          onClick={onOpenConfig}
          title="Cài đặt cấu hình (config.yaml)"
        >
          <Settings size={16} />
          <span style={{ fontSize: 13, fontWeight: 500 }}>Config</span>
        </button>

        <div style={styles.notificationWrapper} title={isBusy ? `Đang chạy ${runningCount} tiến trình` : 'Hệ thống sẵn sàng'}>
          <Bell size={18} style={{ color: 'var(--text-muted)' }} />
          {runningCount > 0 && (
            <span style={styles.badgeCount}>{runningCount}</span>
          )}
        </div>

        <button 
          style={styles.themeBtn} 
          onClick={onToggleTheme}
          title={theme === 'dark' ? 'Chuyển sang giao diện Sáng (Light Mode)' : 'Chuyển sang giao diện Tối (Dark Mode)'}
        >
          {theme === 'dark' ? (
            <Moon size={16} />
          ) : (
            <Sun size={16} color="#eab308" />
          )}
        </button>

        <div style={styles.profileBadge} title="Tài khoản Quản Trị">
          <div style={styles.avatar}>
            <User size={15} color="#ffffff" />
          </div>
          <div style={styles.profileInfo}>
            <span style={styles.profileName}>admin</span>
            <span style={styles.profileRole}>Admin</span>
          </div>
        </div>
      </div>
    </header>
  );
}

const styles = {
  header: {
    height: '56px',
    backgroundColor: 'var(--bg-header)',
    borderBottom: '1px solid var(--border-color)',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between',
    padding: '0 16px',
    zIndex: 50,
    flexShrink: 0,
  },
  leftGroup: {
    display: 'flex',
    alignItems: 'center',
    gap: 20,
  },
  topTabsGroup: {
    display: 'flex',
    alignItems: 'center',
    gap: 4,
    marginLeft: 8,
  },
  topTabBtn: {
    position: 'relative',
    background: 'transparent',
    border: 'none',
    color: 'var(--text-muted)',
    fontSize: 13,
    fontWeight: 500,
    padding: '8px 12px',
    cursor: 'pointer',
    borderRadius: 'var(--radius-sm)',
    transition: 'all 0.15s ease',
  },
  topTabBtnActive: {
    color: 'var(--primary-light)',
    fontWeight: 600,
  },
  topTabIndicator: {
    position: 'absolute',
    bottom: -10,
    left: '12px',
    right: '12px',
    height: '2px',
    backgroundColor: 'var(--primary-light)',
    borderRadius: '2px 2px 0 0',
  },
  brand: {
    display: 'flex',
    alignItems: 'center',
    gap: 8,
  },
  brandIcon: {
    width: 28,
    height: 28,
    borderRadius: 8,
    background: 'linear-gradient(135deg, #ef4444 0%, #dc2626 100%)',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    boxShadow: '0 2px 8px rgba(239, 68, 68, 0.4)',
  },
  brandText: {
    fontSize: 15,
    fontWeight: 700,
    color: 'var(--text-main)',
    letterSpacing: '-0.3px',
  },
  versionBadge: {
    fontSize: 10,
    fontWeight: 600,
    padding: '1px 6px',
    borderRadius: 10,
    backgroundColor: 'var(--bg-surface)',
    color: 'var(--text-dim)',
  },
  divider: {
    width: 1,
    height: 20,
    backgroundColor: 'var(--border-color)',
  },
  breadcrumb: {
    display: 'flex',
    alignItems: 'center',
    gap: 6,
    fontSize: 13,
  },
  breadcrumbItem: {
    color: 'var(--text-dim)',
  },
  breadcrumbProject: {
    color: 'var(--text-muted)',
    fontWeight: 500,
  },
  breadcrumbActive: {
    color: 'var(--primary-light)',
    fontWeight: 600,
  },
  centerActions: {
    display: 'flex',
    alignItems: 'center',
    gap: 8,
  },
  actionBtn: {
    display: 'flex',
    alignItems: 'center',
    gap: 6,
    height: 32,
    padding: '0 12px',
    borderRadius: 6,
    backgroundColor: 'var(--bg-surface)',
    border: '1px solid var(--border-color)',
    color: 'var(--text-main)',
    fontSize: 12,
    fontWeight: 600,
    whiteSpace: 'nowrap',
    cursor: 'pointer',
    transition: 'all 0.15s ease',
    boxSizing: 'border-box',
  },
  saveBtn: {
    backgroundColor: 'var(--primary)',
    borderColor: 'var(--primary-hover)',
    color: '#ffffff',
    boxShadow: '0 2px 6px var(--primary-glow)',
  },
  studioExportBtn: {
    backgroundColor: 'var(--accent-purple)',
    borderColor: '#6d28d9',
    color: '#ffffff',
    boxShadow: '0 2px 8px rgba(124, 58, 237, 0.4)',
  },
  studioCutActiveBtn: {
    backgroundColor: 'var(--accent-red-bg)',
    color: 'var(--accent-red)',
    boxShadow: 'inset 0 0 6px var(--accent-red-bg)',
  },
  studioSplitActiveBtn: {
    backgroundColor: 'var(--primary-glow)',
    color: 'var(--primary-light)',
    boxShadow: 'inset 0 0 6px var(--primary-glow)',
  },
  studioMergeActiveBtn: {
    backgroundColor: 'var(--accent-green-bg)',
    color: 'var(--accent-green)',
    boxShadow: 'inset 0 0 6px var(--accent-green-bg)',
  },
  studioSegmentInactiveBtn: {
    backgroundColor: 'transparent',
    color: 'var(--text-dim)',
  },
  translateSegmentGroup: {
    display: 'flex',
    alignItems: 'center',
    height: 32,
    backgroundColor: 'var(--bg-surface)',
    border: '1px solid var(--border-color)',
    borderRadius: 6,
    overflow: 'hidden',
    boxSizing: 'border-box',
  },
  segmentBtn: {
    display: 'flex',
    alignItems: 'center',
    gap: 5,
    height: '100%',
    padding: '0 11px',
    border: 'none',
    fontSize: 12,
    fontWeight: 700,
    whiteSpace: 'nowrap',
    cursor: 'pointer',
    transition: 'all 0.15s ease',
  },
  voiceSegmentBtn: {
    backgroundColor: 'var(--accent-green-bg)',
    color: 'var(--accent-green)',
  },
  subSegmentBtn: {
    backgroundColor: 'var(--accent-amber-bg)',
    color: 'var(--accent-amber)',
  },
  resumeSegmentBtn: {
    backgroundColor: 'rgba(139, 92, 246, 0.15)',
    color: 'var(--accent-purple)',
  },
  segmentDivider: {
    width: 1,
    height: 18,
    backgroundColor: 'var(--border-color)',
  },
  toolIconGroup: {
    display: 'flex',
    alignItems: 'center',
    gap: 3,
    backgroundColor: 'var(--bg-surface)',
    padding: '2px 4px',
    borderRadius: 6,
    border: '1px solid var(--border-color)',
    height: 32,
    boxSizing: 'border-box',
  },
  toolIconBtn: {
    width: 26,
    height: 26,
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    borderRadius: 4,
    backgroundColor: 'transparent',
    border: 'none',
    color: 'var(--text-muted)',
    cursor: 'pointer',
    transition: 'all 0.15s ease',
  },
  deleteToolBtn: {
    color: '#f87171',
  },
  rightGroup: {
    display: 'flex',
    alignItems: 'center',
    gap: 14,
  },
  utilityBtn: {
    display: 'flex',
    alignItems: 'center',
    gap: 6,
    padding: '5px 10px',
    backgroundColor: 'transparent',
    color: 'var(--text-muted)',
    border: 'none',
  },
  notificationWrapper: {
    position: 'relative',
    cursor: 'pointer',
    display: 'flex',
    alignItems: 'center',
  },
  badgeCount: {
    position: 'absolute',
    top: -5,
    right: -6,
    width: 16,
    height: 16,
    borderRadius: '50%',
    backgroundColor: 'var(--primary)',
    color: '#ffffff',
    fontSize: 10,
    fontWeight: 700,
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
  },
  themeBtn: {
    background: 'var(--bg-surface)',
    border: '1px solid var(--border-color)',
    borderRadius: 'var(--radius-sm)',
    color: 'var(--text-muted)',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    width: 32,
    height: 32,
    cursor: 'pointer',
    transition: 'all 0.15s ease',
  },
  profileBadge: {
    display: 'flex',
    alignItems: 'center',
    gap: 8,
    padding: '3px 8px 3px 4px',
    borderRadius: 20,
    backgroundColor: 'var(--bg-surface)',
    border: '1px solid var(--border-color)',
  },
  avatar: {
    width: 24,
    height: 24,
    borderRadius: '50%',
    backgroundColor: '#3b82f6',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
  },
  profileInfo: {
    display: 'flex',
    flexDirection: 'column',
    lineHeight: 1.1,
  },
  profileName: {
    fontSize: 12,
    fontWeight: 600,
    color: 'var(--text-main)',
  },
  profileRole: {
    fontSize: 10,
    color: 'var(--text-dim)',
  },
  dropdownMenu: {
    position: 'absolute',
    top: 'calc(100% + 6px)',
    left: 0,
    backgroundColor: 'var(--bg-card)',
    border: '1px solid var(--border-color)',
    borderRadius: 'var(--radius-md)',
    boxShadow: 'var(--shadow-lg)',
    width: 280,
    padding: '6px',
    zIndex: 100,
    display: 'flex',
    flexDirection: 'column',
    gap: 4,
  },
  dropdownItem: {
    display: 'flex',
    alignItems: 'flex-start',
    gap: 10,
    padding: '8px 10px',
    borderRadius: 'var(--radius-sm)',
    cursor: 'pointer',
    backgroundColor: 'transparent',
    transition: 'background-color 0.15s ease',
  },
  menuTitle: {
    fontSize: 12,
    fontWeight: 600,
    color: 'var(--text-main)',
  },
  menuSub: {
    fontSize: 11,
    color: 'var(--text-dim)',
    marginTop: 2,
  },
  modalOverlay: {
    position: 'fixed',
    top: 0,
    left: 0,
    right: 0,
    bottom: 0,
    backgroundColor: 'rgba(0, 0, 0, 0.75)',
    backdropFilter: 'blur(4px)',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    zIndex: 9999,
    padding: 16,
  },
  modalCard: {
    backgroundColor: 'var(--bg-surface-elevated)',
    border: '1px solid var(--border-color)',
    borderRadius: 'var(--radius-md)',
    padding: '20px',
    maxWidth: 440,
    width: '100%',
    boxShadow: '0 12px 30px rgba(0, 0, 0, 0.6)',
    display: 'flex',
    flexDirection: 'column',
    gap: 16,
  },
  modalHeader: {
    display: 'flex',
    gap: 12,
    alignItems: 'flex-start',
  },
  modalWarningIcon: {
    padding: 8,
    borderRadius: '50%',
    backgroundColor: 'rgba(239, 68, 68, 0.15)',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    flexShrink: 0,
  },
  modalTitle: {
    fontSize: 14,
    fontWeight: 700,
    color: 'var(--text-main)',
    marginBottom: 4,
  },
  modalDesc: {
    fontSize: 12,
    color: 'var(--text-muted)',
    lineHeight: 1.4,
  },
  modalSubDesc: {
    fontSize: 11,
    color: 'var(--text-dim)',
    marginTop: 4,
  },
  modalActions: {
    display: 'flex',
    justifyContent: 'flex-end',
    gap: 8,
  },
  modalCancelBtn: {
    padding: '6px 12px',
    backgroundColor: 'var(--bg-input)',
    border: '1px solid var(--border-color)',
    color: 'var(--text-muted)',
    borderRadius: 'var(--radius-sm)',
    fontSize: 12,
    fontWeight: 600,
  },
  modalConfirmBtn: {
    padding: '6px 14px',
    backgroundColor: 'var(--accent-red)',
    border: 'none',
    color: '#ffffff',
    borderRadius: 'var(--radius-sm)',
    fontSize: 12,
    fontWeight: 600,
    display: 'flex',
    alignItems: 'center',
    gap: 6,
    boxShadow: '0 2px 6px rgba(239, 68, 68, 0.4)',
  }
};
