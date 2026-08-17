import React, { createContext, useContext, useState, useCallback, useRef, useEffect } from 'react';
import { AlertTriangle, Info, HelpCircle, Trash2, CheckCircle2, X } from 'lucide-react';

const ModalContext = createContext(null);

export function ConfirmProvider({ children }) {
  const [modalState, setModalState] = useState({
    isOpen: false,
    mode: 'confirm', // 'confirm' | 'alert' | 'prompt'
    title: '',
    message: '',
    confirmText: 'Xác nhận',
    cancelText: 'Hủy bỏ',
    type: 'danger', // 'danger' | 'warning' | 'info' | 'success'
    defaultValue: '',
    placeholder: '',
    inputValue: '',
  });

  const resolverRef = useRef(null);
  const inputRef = useRef(null);

  // Focus input automatically when prompt opens
  useEffect(() => {
    if (modalState.isOpen && modalState.mode === 'prompt' && inputRef.current) {
      setTimeout(() => {
        if (inputRef.current) {
          inputRef.current.focus();
          inputRef.current.select();
        }
      }, 50);
    }
  }, [modalState.isOpen, modalState.mode]);

  // 1. Confirm: Returns Promise<boolean>
  const confirm = useCallback(({
    title = 'Xác nhận hành động',
    message = 'Bạn có chắc chắn muốn thực hiện hành động này?',
    confirmText = 'Xác nhận',
    cancelText = 'Hủy bỏ',
    type = 'danger'
  }) => {
    return new Promise((resolve) => {
      resolverRef.current = resolve;
      setModalState({
        isOpen: true,
        mode: 'confirm',
        title,
        message,
        confirmText,
        cancelText,
        type,
        defaultValue: '',
        placeholder: '',
        inputValue: '',
      });
    });
  }, []);

  // 2. Alert: Returns Promise<void>
  const showAlert = useCallback(({
    title = 'Thông báo',
    message = '',
    buttonText = 'Đã hiểu',
    type = 'info'
  }) => {
    return new Promise((resolve) => {
      resolverRef.current = resolve;
      setModalState({
        isOpen: true,
        mode: 'alert',
        title,
        message,
        confirmText: buttonText,
        cancelText: '',
        type,
        defaultValue: '',
        placeholder: '',
        inputValue: '',
      });
    });
  }, []);

  // 3. Prompt: Returns Promise<string | null>
  const showPrompt = useCallback(({
    title = 'Nhập thông tin',
    message = '',
    defaultValue = '',
    placeholder = 'Nhập nội dung...',
    confirmText = 'Xác nhận',
    cancelText = 'Hủy bỏ',
    type = 'info'
  }) => {
    return new Promise((resolve) => {
      resolverRef.current = resolve;
      setModalState({
        isOpen: true,
        mode: 'prompt',
        title,
        message,
        confirmText,
        cancelText,
        type,
        defaultValue,
        placeholder,
        inputValue: defaultValue,
      });
    });
  }, []);

  const handleConfirm = () => {
    const val = modalState.mode === 'prompt' ? modalState.inputValue : true;
    setModalState(prev => ({ ...prev, isOpen: false }));
    if (resolverRef.current) {
      resolverRef.current(val);
      resolverRef.current = null;
    }
  };

  const handleCancel = () => {
    const val = modalState.mode === 'prompt' ? null : false;
    setModalState(prev => ({ ...prev, isOpen: false }));
    if (resolverRef.current) {
      resolverRef.current(val);
      resolverRef.current = null;
    }
  };

  const getIcon = () => {
    switch (modalState.type) {
      case 'danger':
        return <Trash2 size={24} color="#ef4444" />;
      case 'warning':
        return <AlertTriangle size={24} color="#f59e0b" />;
      case 'success':
        return <CheckCircle2 size={24} color="#10b981" />;
      case 'info':
      default:
        return <Info size={24} color="#3b82f6" />;
    }
  };

  const getIconBg = () => {
    switch (modalState.type) {
      case 'danger':
        return 'rgba(239, 68, 68, 0.15)';
      case 'warning':
        return 'rgba(245, 158, 11, 0.15)';
      case 'success':
        return 'rgba(16, 185, 129, 0.15)';
      case 'info':
      default:
        return 'rgba(59, 130, 246, 0.15)';
    }
  };

  const getConfirmBtnStyle = () => {
    switch (modalState.type) {
      case 'danger':
        return { backgroundColor: '#ef4444', color: '#ffffff', boxShadow: '0 2px 8px rgba(239, 68, 68, 0.4)' };
      case 'warning':
        return { backgroundColor: '#f59e0b', color: '#ffffff', boxShadow: '0 2px 8px rgba(245, 158, 11, 0.4)' };
      case 'success':
        return { backgroundColor: '#10b981', color: '#ffffff', boxShadow: '0 2px 8px rgba(16, 185, 129, 0.4)' };
      case 'info':
      default:
        return { backgroundColor: '#3b82f6', color: '#ffffff', boxShadow: '0 2px 8px rgba(59, 130, 246, 0.4)' };
    }
  };

  // 4. Toast / Snackbar: Lightweight auto-dismissing banner (default 2s)
  const [toasts, setToasts] = useState([]);

  const showToast = useCallback((toastOrMessage) => {
    const toast = typeof toastOrMessage === 'string'
      ? { message: toastOrMessage, type: 'success', duration: 2000 }
      : {
          id: Date.now() + Math.random(),
          message: toastOrMessage.message || '',
          type: toastOrMessage.type || 'success',
          duration: toastOrMessage.duration || 2000
        };

    const id = toast.id || (Date.now() + Math.random());
    const newToast = { ...toast, id };

    setToasts(prev => [...prev, newToast]);

    setTimeout(() => {
      setToasts(prev => prev.filter(t => t.id !== id));
    }, newToast.duration);
  }, []);

  return (
    <ModalContext.Provider value={{ confirm, showAlert, showPrompt, showToast, showSnackbar: showToast, toast: showToast, alert: showAlert, prompt: showPrompt }}>
      {children}

      {/* Global Snackbar / Toast Floating Container */}
      {toasts.length > 0 && (
        <div style={styles.toastContainer}>
          {toasts.map(t => (
            <div
              key={t.id}
              style={{
                ...styles.toastItem,
                ...(t.type === 'success' ? styles.toastSuccess : {}),
                ...(t.type === 'danger' ? styles.toastDanger : {}),
                ...(t.type === 'warning' ? styles.toastWarning : {}),
                ...(t.type === 'info' ? styles.toastInfo : {})
              }}
            >
              {t.type === 'success' && <CheckCircle2 size={16} color="#10b981" style={{ flexShrink: 0 }} />}
              {t.type === 'danger' && <AlertTriangle size={16} color="#ef4444" style={{ flexShrink: 0 }} />}
              {t.type === 'warning' && <AlertTriangle size={16} color="#f59e0b" style={{ flexShrink: 0 }} />}
              {t.type === 'info' && <Info size={16} color="#3b82f6" style={{ flexShrink: 0 }} />}
              <span style={styles.toastText}>{t.message}</span>
            </div>
          ))}
        </div>
      )}

      {/* Global Centered Modal Dialog */}
      {modalState.isOpen && (
        <div 
          style={styles.overlay} 
          onClick={handleCancel}
          onKeyDown={(e) => {
            if (e.key === 'Escape') handleCancel();
            if (e.key === 'Enter' && modalState.mode !== 'prompt') handleConfirm();
          }}
          tabIndex={-1}
        >
          <div style={styles.dialogCard} onClick={e => e.stopPropagation()}>
            {/* Close Button Top Right */}
            <button style={styles.closeBtn} onClick={handleCancel} title="Đóng">
              <X size={16} />
            </button>

            {/* Header: Icon + Title + Message */}
            <div style={styles.dialogHeader}>
              <div style={{ ...styles.iconWrapper, backgroundColor: getIconBg() }}>
                {getIcon()}
              </div>
              <div style={styles.contentWrapper}>
                <h3 style={styles.dialogTitle}>{modalState.title}</h3>
                {modalState.message && (
                  <div style={styles.dialogMessage}>
                    {modalState.message}
                  </div>
                )}
              </div>
            </div>

            {/* Prompt Input Box */}
            {modalState.mode === 'prompt' && (
              <div style={styles.inputContainer}>
                <input
                  ref={inputRef}
                  type="text"
                  style={styles.inputField}
                  value={modalState.inputValue}
                  placeholder={modalState.placeholder}
                  onChange={(e) => setModalState(prev => ({ ...prev, inputValue: e.target.value }))}
                  onKeyDown={(e) => {
                    if (e.key === 'Enter') {
                      e.preventDefault();
                      handleConfirm();
                    }
                    if (e.key === 'Escape') {
                      e.preventDefault();
                      handleCancel();
                    }
                  }}
                />
              </div>
            )}

            {/* Footer Action Buttons */}
            <div style={styles.dialogActions}>
              {modalState.mode !== 'alert' && (
                <button 
                  style={styles.cancelBtn} 
                  onClick={handleCancel}
                >
                  {modalState.cancelText || 'Hủy bỏ'}
                </button>
              )}
              <button 
                style={{ ...styles.confirmBtn, ...getConfirmBtnStyle() }} 
                onClick={handleConfirm}
                autoFocus={modalState.mode !== 'prompt'}
              >
                {modalState.confirmText || 'Xác nhận'}
              </button>
            </div>
          </div>
        </div>
      )}
    </ModalContext.Provider>
  );
}

// Aliases and Hooks
export const ModalProvider = ConfirmProvider;

export function useModal() {
  const context = useContext(ModalContext);
  if (!context) {
    throw new Error('useModal must be used within a ModalProvider / ConfirmProvider');
  }
  return context;
}

export function useConfirm() {
  return useModal();
}

export function useAlert() {
  const { showAlert } = useModal();
  return { showAlert, alert: showAlert };
}

export function usePrompt() {
  const { showPrompt } = useModal();
  return { showPrompt, prompt: showPrompt };
}

const styles = {
  overlay: {
    position: 'fixed',
    top: 0,
    left: 0,
    right: 0,
    bottom: 0,
    backgroundColor: 'rgba(5, 8, 15, 0.78)',
    backdropFilter: 'blur(8px)',
    WebkitBackdropFilter: 'blur(8px)',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    zIndex: 99999,
    padding: 16,
    animation: 'fadeIn 0.15s ease-out',
  },
  dialogCard: {
    backgroundColor: 'var(--bg-surface-elevated, #151D30)',
    border: '1px solid var(--border-color, #263554)',
    borderRadius: '12px',
    padding: '24px',
    maxWidth: '480px',
    width: '100%',
    boxShadow: '0 25px 50px -12px rgba(0, 0, 0, 0.8), 0 0 0 1px rgba(255, 255, 255, 0.06)',
    display: 'flex',
    flexDirection: 'column',
    gap: '18px',
    position: 'relative',
    animation: 'scaleUp 0.15s ease-out',
  },
  closeBtn: {
    position: 'absolute',
    top: 14,
    right: 14,
    background: 'none',
    border: 'none',
    color: 'var(--text-dim, #64748b)',
    cursor: 'pointer',
    padding: 6,
    borderRadius: 6,
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    transition: 'all 0.15s ease',
  },
  dialogHeader: {
    display: 'flex',
    gap: 16,
    alignItems: 'flex-start',
  },
  iconWrapper: {
    width: 44,
    height: 44,
    borderRadius: '50%',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    flexShrink: 0,
  },
  contentWrapper: {
    flex: 1,
    paddingRight: 16,
  },
  dialogTitle: {
    fontSize: 16,
    fontWeight: 700,
    color: '#ffffff',
    marginBottom: 6,
    lineHeight: 1.3,
  },
  dialogMessage: {
    fontSize: 13,
    color: 'var(--text-muted, #94a3b8)',
    lineHeight: 1.6,
    wordBreak: 'break-word',
    whiteSpace: 'pre-line',
  },
  inputContainer: {
    marginTop: 2,
  },
  inputField: {
    width: '100%',
    padding: '10px 14px',
    backgroundColor: 'var(--bg-input, #0b1120)',
    border: '1px solid var(--border-color, #263554)',
    borderRadius: '8px',
    color: '#f8fafc',
    fontSize: '13px',
    outline: 'none',
    boxSizing: 'border-box',
    transition: 'all 0.15s ease',
    boxShadow: 'inset 0 1px 2px rgba(0,0,0,0.4)',
  },
  dialogActions: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'flex-end',
    gap: 10,
    borderTop: '1px solid rgba(255, 255, 255, 0.06)',
    paddingTop: 16,
  },
  cancelBtn: {
    padding: '8px 16px',
    backgroundColor: 'var(--bg-input, #0f172a)',
    border: '1px solid var(--border-color, #263554)',
    color: 'var(--text-main, #e2e8f0)',
    borderRadius: '6px',
    fontSize: '13px',
    fontWeight: 600,
    cursor: 'pointer',
    transition: 'all 0.15s ease',
  },
  confirmBtn: {
    padding: '8px 18px',
    border: 'none',
    borderRadius: '6px',
    fontSize: '13px',
    fontWeight: 600,
    cursor: 'pointer',
    display: 'flex',
    alignItems: 'center',
    gap: 6,
    transition: 'all 0.15s ease',
  },
  toastContainer: {
    position: 'fixed',
    bottom: 28,
    left: '50%',
    transform: 'translateX(-50%)',
    display: 'flex',
    flexDirection: 'column',
    alignItems: 'center',
    gap: 8,
    zIndex: 999999,
    pointerEvents: 'none',
  },
  toastItem: {
    display: 'flex',
    alignItems: 'center',
    gap: 10,
    padding: '10px 18px',
    backgroundColor: 'rgba(15, 23, 42, 0.94)',
    backdropFilter: 'blur(16px)',
    WebkitBackdropFilter: 'blur(16px)',
    border: '1px solid rgba(255, 255, 255, 0.12)',
    borderRadius: 24,
    boxShadow: '0 10px 30px rgba(0, 0, 0, 0.6), 0 0 1px rgba(255, 255, 255, 0.2)',
    pointerEvents: 'auto',
    maxWidth: '90vw',
    transition: 'all 0.2s ease',
  },
  toastSuccess: {
    borderColor: 'rgba(16, 185, 129, 0.5)',
    boxShadow: '0 10px 30px rgba(0, 0, 0, 0.6), 0 0 16px rgba(16, 185, 129, 0.25)',
  },
  toastDanger: {
    borderColor: 'rgba(239, 68, 68, 0.5)',
    boxShadow: '0 10px 30px rgba(0, 0, 0, 0.6), 0 0 16px rgba(239, 68, 68, 0.25)',
  },
  toastWarning: {
    borderColor: 'rgba(245, 158, 11, 0.5)',
    boxShadow: '0 10px 30px rgba(0, 0, 0, 0.6), 0 0 16px rgba(245, 158, 11, 0.25)',
  },
  toastInfo: {
    borderColor: 'rgba(59, 130, 246, 0.5)',
    boxShadow: '0 10px 30px rgba(0, 0, 0, 0.6), 0 0 16px rgba(59, 130, 246, 0.25)',
  },
  toastText: {
    fontSize: 12.5,
    fontWeight: 600,
    color: '#f8fafc',
    letterSpacing: '0.2px',
  }
};
