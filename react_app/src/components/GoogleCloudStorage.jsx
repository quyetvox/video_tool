import React, { useState, useEffect, useMemo, useCallback } from 'react';
import { 
  Cloud, 
  CloudUpload,
  Folder, 
  FileText, 
  Video, 
  Music, 
  Image as ImageIcon, 
  File, 
  Plus, 
  RefreshCw, 
  Search, 
  Filter, 
  ChevronRight, 
  ChevronLeft, 
  Share2, 
  Download, 
  MoreHorizontal, 
  Copy, 
  Trash2, 
  ArrowDownToLine, 
  ArrowUpFromLine, 
  HardDrive, 
  List, 
  Grid, 
  CheckSquare, 
  Square, 
  FolderPlus, 
  Upload, 
  Check, 
  Clock, 
  Database, 
  Sparkles, 
  Pause, 
  Play, 
  X, 
  AlertCircle,
  ExternalLink,
  ShieldCheck
} from 'lucide-react';
import { 
  fetchProjects,
  fetchStorageStatus, 
  fetchStorageBrowse,
  syncDownFromCloud, 
  syncUpToCloud, 
  offloadLocalFiles, 
  deleteCloudFiles,
  deleteLocalFile,
  refreshStorageCache 
} from '../services/api';
import { useModal } from './ConfirmModal';

// Helper format file sizes
const formatBytes = (bytes) => {
  if (!bytes || isNaN(bytes) || bytes === 0) return '0 B';
  const k = 1024;
  const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
  const i = Math.floor(Math.log(bytes) / Math.log(k));
  return `${parseFloat((bytes / Math.pow(k, i)).toFixed(1))} ${sizes[i]}`;
};

export default function GoogleCloudStorage({
  project = 'default',
  projects = [],
  onSelectProject,
  onRefresh
}) {
  const { confirm, showAlert, showToast } = useModal();

  const [selectedBucket, setSelectedBucket] = useState('service-qa-beta');
  const [basePrefix, setBasePrefix] = useState('video-tiktok-volumn');
  
  // Navigation path array e.g. [] (root) or ['chu-truc-tu'] or ['chu-truc-tu', 'output']
  const [currentPath, setCurrentPath] = useState([]);
  
  // View mode: 'list' | 'grid'
  const [viewMode, setViewMode] = useState('list');
  
  // Selection and Search states
  const [searchQuery, setSearchQuery] = useState('');
  const [selectedItemIds, setSelectedItemIds] = useState(new Set());
  const [activeItem, setActiveItem] = useState(null);

  // Filter dropdown states
  const [filterType, setFilterType] = useState('all'); // all | video | audio | subtitle | image | folder
  const [filterSize, setFilterSize] = useState('all'); // all | small | medium | large
  const [filterDate, setFilterDate] = useState('all'); // all | today | 7days | 30days

  // Pagination states
  const [itemsPerPage, setItemsPerPage] = useState(20);
  const [currentPage, setCurrentPage] = useState(1);

  // Real backend storage states
  const [cloudItems, setCloudItems] = useState([]);
  const [isLoading, setIsLoading] = useState(false);
  const [isConnected, setIsConnected] = useState(true);
  const [isRefreshing, setIsRefreshing] = useState(false);
  const [totalCloudBytes, setTotalCloudBytes] = useState(0);

  // Live Sync Progress Widget state
  const [showSyncCard, setShowSyncCard] = useState(false);
  const [syncProgress, setSyncProgress] = useState(0);
  const [syncTitle, setSyncTitle] = useState('');
  const [syncSpeed, setSyncSpeed] = useState('24.5 MB/s');
  const [syncEta, setSyncEta] = useState('00:00:45');
  const [isSyncPaused, setIsSyncPaused] = useState(false);

  // Modals
  const [showNewFolderModal, setShowNewFolderModal] = useState(false);
  const [newFolderName, setNewFolderName] = useState('');

  // Delete Selection Modal states: 'cloud_only' | 'local_only' | 'both'
  const [showDeleteModal, setShowDeleteModal] = useState(false);
  const [deleteTargetFiles, setDeleteTargetFiles] = useState([]);
  const [deleteScope, setDeleteScope] = useState('cloud_only');
  const [isDeleting, setIsDeleting] = useState(false);

  // Path string for API
  const currentPathStr = currentPath.join('/');

  // Load cloud data on path change or refresh
  const loadDirectoryData = useCallback(async () => {
    setIsLoading(true);
    
    // CASE 1: ROOT LEVEL (currentPath is empty) -> List all projects in video-tiktok-volumn
    if (currentPath.length === 0) {
      try {
        let projList = projects;
        if (!projList || projList.length === 0) {
          const pRes = await fetchProjects();
          if (pRes && pRes.projects) {
            projList = pRes.projects;
          }
        }

        // Include known cloud projects
        const knownCloudProjs = ['chu-truc-tu', 'edamame'];
        const allProjMap = new Map();

        (projList || []).forEach(p => {
          allProjMap.set(p.name, {
            id: `proj_${p.name}`,
            name: p.name,
            type: 'folder',
            ext: 'PROJECT',
            size: 0,
            itemsCount: (p.srcCount || 0) + (p.outputCount || 0) + (p.cutCount || 0) + (p.mergeCount || 0),
            modified: '14/08/2026 16:56',
            parent: '',
            path: p.name
          });
        });

        knownCloudProjs.forEach(name => {
          if (!allProjMap.has(name)) {
            allProjMap.set(name, {
              id: `proj_${name}`,
              name: name,
              type: 'folder',
              ext: 'PROJECT',
              size: 0,
              itemsCount: 45,
              modified: '14/08/2026 16:56',
              parent: '',
              path: name
            });
          }
        });

        const rootItems = Array.from(allProjMap.values()).sort((a, b) => a.name.localeCompare(b.name));
        setCloudItems(rootItems);
        setTotalCloudBytes(rootItems.length * 100 * 1024 * 1024);
      } catch (err) {
        console.warn('Load projects error:', err);
      } finally {
        setIsLoading(false);
      }
      return;
    }

    // CASE 2: INSIDE A PROJECT (currentPath.length >= 1)
    try {
      const activeProj = currentPath[0];
      const statusRes = await fetchStorageStatus(activeProj);
      
      if (statusRes && (statusRes.connected !== undefined || statusRes.files)) {
        setIsConnected(statusRes.connected !== false);
        if (statusRes.bucket) setSelectedBucket(statusRes.bucket);
        
        const rawFiles = statusRes.files || [];
        const items = [];
        const subfolderMap = new Map();

        if (currentPath.length === 1) {
          // Inside project root: show subfolders (src, output, cut, merge) + config.yaml
          rawFiles.forEach(f => {
            const parts = f.relPath.split('/');
            if (parts.length > 1) {
              const folderName = parts[0];
              if (!subfolderMap.has(folderName)) {
                subfolderMap.set(folderName, { count: 0, size: 0, mtime: f.cloud?.mtime || f.local?.mtime || 0 });
              }
              const fold = subfolderMap.get(folderName);
              fold.count += 1;
              fold.size += f.sizeBytes || 0;
            } else {
              // Direct file in project root
              items.push({
                id: `f_${f.relPath}`,
                name: f.name,
                type: f.isMedia ? 'video' : (f.name.endsWith('.yaml') ? 'file' : 'file'),
                ext: f.name.split('.').pop().toUpperCase(),
                size: f.sizeBytes,
                modified: f.cloud?.mtime ? new Date(f.cloud.mtime).toLocaleString('vi-VN') : (f.local?.mtime ? new Date(f.local.mtime).toLocaleString('vi-VN') : '-'),
                parent: activeProj,
                path: `${activeProj}/${f.relPath}`,
                gcsUri: f.cloud?.fullPath || `gs://${selectedBucket}/${basePrefix}/${activeProj}/${f.relPath}`,
                status: f.status || (f.cloud && f.local ? 'synced' : (f.cloud ? 'cloud_only' : 'local_only')),
                hasLocal: !!f.local,
                hasCloud: !!f.cloud
              });
            }
          });

          // Ensure standard subfolders src & output exist even if empty
          ['src', 'output', 'cut', 'merge'].forEach(sFolder => {
            if (!subfolderMap.has(sFolder)) {
              subfolderMap.set(sFolder, { count: 0, size: 0, mtime: 0 });
            }
          });

          // Add subfolders
          subfolderMap.forEach((meta, folderName) => {
            items.unshift({
              id: `fold_${folderName}`,
              name: folderName,
              type: 'folder',
              ext: 'FOLDER',
              size: meta.size,
              itemsCount: meta.count,
              modified: meta.mtime ? new Date(meta.mtime).toLocaleString('vi-VN') : '14/08/2026 16:56',
              parent: activeProj,
              path: `${activeProj}/${folderName}`
            });
          });
        } else {
          // Inside a subfolder e.g. ['chu-truc-tu', 'output']
          const targetSubfolder = currentPath.slice(1).join('/');
          rawFiles.forEach(f => {
            if (f.relPath.startsWith(targetSubfolder + '/')) {
              const fileName = f.name;
              items.push({
                id: `f_${f.relPath}`,
                name: fileName,
                type: f.isMedia ? 'video' : 'file',
                ext: fileName.split('.').pop().toUpperCase(),
                size: f.sizeBytes,
                modified: f.cloud?.mtime ? new Date(f.cloud.mtime).toLocaleString('vi-VN') : (f.local?.mtime ? new Date(f.local.mtime).toLocaleString('vi-VN') : '-'),
                parent: targetSubfolder,
                path: `${activeProj}/${f.relPath}`,
                gcsUri: f.cloud?.fullPath || `gs://${selectedBucket}/${basePrefix}/${activeProj}/${f.relPath}`,
                status: f.status || (f.cloud && f.local ? 'synced' : (f.cloud ? 'cloud_only' : 'local_only')),
                hasLocal: !!f.local,
                hasCloud: !!f.cloud
              });
            }
          });
        }

        setCloudItems(items);
        setTotalCloudBytes(statusRes.bytes?.cloud || statusRes.bytes?.local || 0);
      }
    } catch (err) {
      console.warn('Status fetch error:', err);
    } finally {
      setIsLoading(false);
    }
  }, [currentPath, project, projects, selectedBucket, basePrefix]);

  useEffect(() => {
    loadDirectoryData();
  }, [loadDirectoryData]);

  // Handle Refresh from GCS Cache
  const handleRefreshData = async () => {
    const ok = await confirm({
      title: 'Làm Mới Danh Mục Từ Google Cloud Storage?',
      message: `Hệ thống sẽ kết nối trực tiếp đến GCS để quét và cập nhật lại toàn bộ danh sách tệp, dung lượng và trạng thái đồng bộ mới nhất cho dự án "${currentProjectName}".`,
      confirmText: 'Làm Mới Ngay',
      type: 'info'
    });
    if (!ok) return;

    setIsRefreshing(true);
    try {
      await refreshStorageCache(currentPath[0] || project || 'default');
      await loadDirectoryData();
      showToast({ message: 'Đã cập nhật danh mục từ Google Cloud Storage!', type: 'success' });
      onRefresh && onRefresh();
    } catch (e) {
      showToast({ message: 'Lỗi làm mới: ' + e.message, type: 'danger' });
    } finally {
      setIsRefreshing(false);
    }
  };

  // Current folder display name and full GCS URI
  const currentFolderName = currentPath.length === 0 
    ? 'Root (video-tiktok-volumn)' 
    : currentPath[currentPath.length - 1];
    
  const fullPathStr = currentPath.length === 0
    ? `${selectedBucket}/${basePrefix}`
    : `${selectedBucket}/${basePrefix}/${currentPathStr}`;

  const currentProjectName = currentPath[0] || project || 'default';

  // Default active item to the current folder if nothing is selected
  const activeInspectorItem = activeItem || {
    id: 'current_view',
    name: currentFolderName,
    type: 'folder',
    path: fullPathStr,
    sizeStr: formatBytes(totalCloudBytes),
    itemsCount: cloudItems.length,
    created: '10/05/2024 09:15',
    modified: '14/08/2026 16:56',
    storageClass: 'Standard',
    location: 'asia-southeast1 (Singapore)',
    gcsUri: `gs://${fullPathStr}`
  };

  // Filtered Files & Folders
  const filteredItems = useMemo(() => {
    return cloudItems.filter(item => {
      // 1. Search query match
      if (searchQuery.trim()) {
        const q = searchQuery.toLowerCase();
        if (!item.name.toLowerCase().includes(q)) return false;
      }

      // 2. Type filter
      if (filterType !== 'all') {
        if (filterType === 'folder' && item.type !== 'folder') return false;
        if (filterType === 'video' && item.type !== 'video') return false;
        if (filterType === 'audio' && item.type !== 'audio') return false;
        if (filterType === 'subtitle' && item.type !== 'subtitle') return false;
        if (filterType === 'image' && item.type !== 'image') return false;
      }

      // 3. Size filter
      if (filterSize !== 'all' && item.size) {
        if (filterSize === 'small' && item.size > 10 * 1024 * 1024) return false;
        if (filterSize === 'medium' && (item.size <= 10 * 1024 * 1024 || item.size > 100 * 1024 * 1024)) return false;
        if (filterSize === 'large' && item.size <= 100 * 1024 * 1024) return false;
      }

      return true;
    });
  }, [cloudItems, searchQuery, filterType, filterSize, filterDate]);

  // Pagination calculation
  const totalPages = Math.max(1, Math.ceil(filteredItems.length / itemsPerPage));
  const paginatedItems = useMemo(() => {
    const start = (currentPage - 1) * itemsPerPage;
    return filteredItems.slice(start, start + itemsPerPage);
  }, [filteredItems, currentPage, itemsPerPage]);

  // Multi-selection handlers
  const handleToggleSelectAll = () => {
    if (selectedItemIds.size === paginatedItems.length) {
      setSelectedItemIds(new Set());
    } else {
      setSelectedItemIds(new Set(paginatedItems.map(i => i.id)));
    }
  };

  const handleToggleSelectItem = (id, e) => {
    e.stopPropagation();
    const next = new Set(selectedItemIds);
    if (next.has(id)) {
      next.delete(id);
    } else {
      next.add(id);
    }
    setSelectedItemIds(next);
  };

  const handleItemClick = (item) => {
    setActiveItem(item);
  };

  const handleItemDoubleClick = (item) => {
    if (item.type === 'folder') {
      const nextPath = [...currentPath, item.name];
      setCurrentPath(nextPath);
      setActiveItem(null);
      setSelectedItemIds(new Set());
      setCurrentPage(1);
      if (currentPath.length === 0 && onSelectProject) {
        onSelectProject(item.name);
      }
    }
  };

  const handleNavigateToBreadcrumb = (index) => {
    if (index < 0) {
      setCurrentPath([]);
    } else {
      setCurrentPath(prev => prev.slice(0, index + 1));
    }
    setActiveItem(null);
    setSelectedItemIds(new Set());
    setCurrentPage(1);
  };

  const handleNavigateUp = () => {
    if (currentPath.length > 0) {
      setCurrentPath(prev => prev.slice(0, -1));
      setActiveItem(null);
      setSelectedItemIds(new Set());
      setCurrentPage(1);
    }
  };

  const handleCopyPath = (text) => {
    navigator.clipboard.writeText(text);
    showToast({ message: `Đã sao chép: ${text}`, type: 'info' });
  };

  // Sync Down (Download from Cloud)
  const handleSyncDown = async (item = null) => {
    let targetFiles = null;

    if (item) {
      // 1. Clicked on single row / inspector item
      const ok = await confirm({
        title: `Tải tệp "${item.name}" về máy tính?`,
        message: `Hệ thống sẽ tải tệp này từ Google Cloud Storage về thư mục máy tính (assets/${currentProjectName}/...). Các tệp đã có sẵn cùng kích thước sẽ tự động được bỏ qua.`,
        confirmText: 'Tải Về Local',
        type: 'info'
      });
      if (!ok) return;
      targetFiles = [item.name];
    } else if (selectedItemIds.size > 0) {
      // 2. Clicked top button with checkboxes selected
      targetFiles = Array.from(selectedItemIds).map(id => {
        const it = cloudItems.find(x => x.id === id);
        return it ? it.name : id;
      });
      const ok = await confirm({
        title: `Tải ${selectedItemIds.size} mục đã chọn về máy tính?`,
        message: `Hệ thống sẽ tải các tệp đã tick chọn (${targetFiles.slice(0, 3).join(', ')}${targetFiles.length > 3 ? ` và ${targetFiles.length - 3} tệp khác` : ''}) từ Cloud GCS về thư mục assets/${currentProjectName}/...`,
        confirmText: 'Tải Về Ngay',
        type: 'info'
      });
      if (!ok) return;
    } else {
      // 3. No items ticked -> Confirm sync entire folder / project
      const ok = await confirm({
        title: `Kéo toàn bộ thư mục "${currentFolderName}" về máy tính?`,
        message: `Hệ thống sẽ tải TOÀN BỘ dữ liệu của "${currentFolderName}" từ Google Cloud Storage về thư mục máy tính (assets/${currentProjectName}/).\n\n💡 Các tệp đã có sẵn trên máy và cùng kích thước sẽ được bỏ qua để tiết kiệm thời gian và băng thông.`,
        confirmText: 'Tải Về Toàn Bộ',
        type: 'info'
      });
      if (!ok) return;
      targetFiles = null; // Sync all
    }

    setShowSyncCard(true);
    setSyncProgress(25);
    setSyncTitle(`Đang tải về ${targetFiles ? targetFiles.join(', ') : `toàn bộ ${currentFolderName}`}`);
    
    showToast({ message: `Bắt đầu đồng bộ từ GCS về assets/${currentProjectName}/...`, type: 'info' });
    try {
      await syncDownFromCloud(currentProjectName, targetFiles);
      setSyncProgress(100);
      setTimeout(() => setShowSyncCard(false), 3000);
      loadDirectoryData();
    } catch (e) {
      showToast({ message: 'Lỗi tải về: ' + e.message, type: 'danger' });
      setShowSyncCard(false);
    }
  };

  // Sync Up (Upload to Cloud)
  const handleSyncUp = async (item = null) => {
    let targetFiles = null;

    if (item) {
      // 1. Clicked on single row / inspector item
      const ok = await confirm({
        title: `Đẩy tệp "${item.name}" lên Cloud GCS?`,
        message: `Hệ thống sẽ tải tệp này từ máy tính lên Google Cloud Storage (gs://${fullPathStr}/${item.name}). Tệp đã có và cùng kích thước sẽ được tự động bỏ qua.`,
        confirmText: 'Đẩy Lên Cloud',
        type: 'info'
      });
      if (!ok) return;
      targetFiles = [item.name];
    } else if (selectedItemIds.size > 0) {
      // 2. Clicked top button with checkboxes selected
      targetFiles = Array.from(selectedItemIds).map(id => {
        const it = cloudItems.find(x => x.id === id);
        return it ? it.name : id;
      });
      const ok = await confirm({
        title: `Đẩy ${selectedItemIds.size} mục đã chọn lên Cloud GCS?`,
        message: `Hệ thống sẽ tải các tệp đã tick chọn (${targetFiles.slice(0, 3).join(', ')}${targetFiles.length > 3 ? ` và ${targetFiles.length - 3} tệp khác` : ''}) từ máy tính lên Google Cloud Storage.`,
        confirmText: 'Đẩy Lên Cloud',
        type: 'info'
      });
      if (!ok) return;
    } else {
      // 3. No items ticked -> Confirm sync entire folder / project
      const ok = await confirm({
        title: `Đẩy toàn bộ dữ liệu "${currentFolderName}" lên Cloud GCS?`,
        message: `Hệ thống sẽ đồng bộ TOÀN BỘ video, file dịch và cấu hình của "${currentFolderName}" từ máy tính lên Google Cloud Storage (gs://${fullPathStr}).\n\n💡 Các tệp đã có trên Cloud và cùng dung lượng sẽ tự động được bỏ qua.`,
        confirmText: 'Đẩy Lên Toàn Bộ',
        type: 'info'
      });
      if (!ok) return;
      targetFiles = null; // Sync all
    }

    setShowSyncCard(true);
    setSyncProgress(30);
    setSyncTitle(`Đang tải lên ${targetFiles ? targetFiles.join(', ') : `toàn bộ ${currentFolderName}`} lên GCS...`);
    showToast({ message: `Bắt đầu đẩy dữ liệu lên GCS...`, type: 'info' });
    
    try {
      await syncUpToCloud(currentProjectName, targetFiles);
      setSyncProgress(100);
      setTimeout(() => setShowSyncCard(false), 3000);
      loadDirectoryData();
    } catch (e) {
      showToast({ message: 'Lỗi tải lên: ' + e.message, type: 'danger' });
      setShowSyncCard(false);
    }
  };

  // Offload Local Storage
  const handleOffload = async (item) => {
    const fileName = item ? item.name : null;
    const ok = await confirm({
      title: fileName ? `Giải Phóng Bộ Nhớ SSD Cho "${fileName}"?` : `Giải Phóng Bộ Nhớ SSD Cho Toàn Bộ Dự Án "${currentProjectName}"?`,
      message: fileName 
        ? `Hệ thống sẽ xóa bản sao tệp "${fileName}" trên ổ cứng máy tính sau khi đã xác nhận tệp tồn tại an toàn 100% trên Cloud GCS.\n\n💡 Bạn có thể kéo lại tệp về bất kỳ lúc nào bằng Sync-Down.`
        : `Hệ thống sẽ xóa các bản sao video/file trên máy tính (assets/${currentProjectName}/) ĐIỀU KIỆN là các file này đã được lưu trữ 100% an toàn trên Cloud GCS.\n\n💡 Giúp giải phóng tối đa dung lượng ổ SSD mà không làm mất video trên Cloud.`,
      confirmText: 'Giải Phóng SSD',
      type: 'warning'
    });
    if (!ok) return;

    try {
      await offloadLocalFiles(currentProjectName, fileName ? [fileName] : null);
      showToast({ message: `Đã giải phóng bộ nhớ local thành công!`, type: 'success' });
      loadDirectoryData();
    } catch (e) {
      showToast({ message: 'Lỗi giải phóng: ' + e.message, type: 'danger' });
    }
  };

  // Open Delete Destination Dialog
  const handleOpenDeleteDialog = (item = null) => {
    let targets = [];
    if (item) {
      targets = [item];
    } else if (selectedItemIds.size > 0) {
      targets = Array.from(selectedItemIds).map(id => cloudItems.find(x => x.id === id)).filter(Boolean);
    } else if (activeItem) {
      targets = [activeItem];
    } else {
      showToast({ message: 'Vui lòng chọn ít nhất một tệp để xóa!', type: 'warning' });
      return;
    }

    setDeleteTargetFiles(targets);

    // Auto-select smart default scope
    if (targets.length === 1) {
      const st = targets[0].status;
      if (st === 'local_only') {
        setDeleteScope('local_only');
      } else if (st === 'cloud_only') {
        setDeleteScope('cloud_only');
      } else {
        setDeleteScope('both');
      }
    } else {
      setDeleteScope('both');
    }

    setShowDeleteModal(true);
  };

  // Execute Deletion based on selected scope: cloud_only | local_only | both
  const handleConfirmDelete = async () => {
    if (!deleteTargetFiles || deleteTargetFiles.length === 0) return;
    setIsDeleting(true);
    const fileNames = deleteTargetFiles.map(f => f.name);
    const fileRelPaths = deleteTargetFiles.map(f => f.path || f.relPath || f.name);

    try {
      if (deleteScope === 'cloud_only') {
        await deleteCloudFiles(currentProjectName, fileNames);
        showToast({ message: `Đã xóa ${fileNames.length} tệp trên Google Cloud Storage!`, type: 'success' });
      } else if (deleteScope === 'local_only') {
        for (const relP of fileRelPaths) {
          try { await deleteLocalFile(currentProjectName, relP); } catch (_) {}
        }
        showToast({ message: `Đã xóa ${fileNames.length} tệp ở thư mục Local (Giải phóng SSD)!`, type: 'success' });
      } else if (deleteScope === 'both') {
        await deleteCloudFiles(currentProjectName, fileNames);
        for (const relP of fileRelPaths) {
          try { await deleteLocalFile(currentProjectName, relP); } catch (_) {}
        }
        showToast({ message: `Đã xóa hoàn toàn ${fileNames.length} tệp trên cả Cloud và Local!`, type: 'success' });
      }

      setShowDeleteModal(false);
      setSelectedItemIds(new Set());
      setActiveItem(null);
      await loadDirectoryData();
    } catch (err) {
      showToast({ message: 'Lỗi xóa tệp: ' + err.message, type: 'danger' });
    } finally {
      setIsDeleting(false);
    }
  };

  // Create folder mock
  const handleCreateNewFolder = (e) => {
    e.preventDefault();
    if (!newFolderName.trim()) return;
    const newFolder = {
      id: `f_${Date.now()}`,
      name: newFolderName.trim(),
      type: 'folder',
      ext: 'FOLDER',
      size: 0,
      modified: new Date().toLocaleString('vi-VN'),
      parent: currentPathStr,
      itemsCount: 0
    };
    setCloudItems(prev => [newFolder, ...prev]);
    setNewFolderName('');
    setShowNewFolderModal(false);
    showToast({ message: `Đã tạo thư mục "${newFolder.name}" trên GCS!`, type: 'success' });
  };

  // Color & Icon Resolver
  const getItemIcon = (item) => {
    if (item.type === 'folder') {
      return <Folder size={18} color="#f59e0b" fill="#f59e0b" style={{ opacity: 0.9 }} />;
    }
    if (item.type === 'video') {
      return <Video size={18} color="#3b82f6" />;
    }
    if (item.type === 'audio') {
      return <Music size={18} color="#10b981" />;
    }
    if (item.type === 'subtitle') {
      return <FileText size={18} color="#a855f7" />;
    }
    if (item.type === 'image') {
      return <ImageIcon size={18} color="#ec4899" />;
    }
    return <File size={18} color="#94a3b8" />;
  };

  // Status Badge Resolver: Synced (Both) | Local only | Cloud only | Modified
  const renderStatusBadge = (item) => {
    if (item.type === 'folder') return null;
    const st = item.status || (item.hasCloud && item.hasLocal ? 'synced' : (item.hasCloud ? 'cloud_only' : 'local_only'));
    
    if (st === 'synced') {
      return (
        <span style={styles.syncedBadge} title="Tệp đã có trên CẢ HAI (Máy tính & Cloud GCS) khớp 100%">
          <span style={styles.badgeDotGreen} />
          <span>Đã đồng bộ</span>
        </span>
      );
    }
    if (st === 'local_only') {
      return (
        <span style={styles.localOnlyBadge} title="Tệp CHỈ CÓ TRÊN MÁY TÍNH (Chưa tải lên Cloud)">
          <span style={styles.badgeDotBlue} />
          <span>Chỉ ở Local</span>
        </span>
      );
    }
    if (st === 'cloud_only') {
      return (
        <span style={styles.cloudOnlyBadge} title="Tệp CHỈ CÓ TRÊN CLOUD GCS (Chưa tải về máy tính)">
          <span style={styles.badgeDotPurple} />
          <span>Chỉ trên Cloud</span>
        </span>
      );
    }
    if (st === 'modified') {
      return (
        <span style={styles.modifiedBadge} title="Tệp có sự khác biệt dung lượng giữa Local và Cloud">
          <span style={styles.badgeDotYellow} />
          <span>Cần đồng bộ</span>
        </span>
      );
    }
    return null;
  };

  return (
    <div style={styles.container}>
      {/* ─────────────────────────────────────────────────────────────
          COL 1: SUB-SIDEBAR (Buckets + Filters + Quick Actions)
         ───────────────────────────────────────────────────────────── */}
      <div style={styles.subSidebar}>
        {/* GCS Bucket Info Card */}
        <div style={styles.bucketSection}>
          <div style={styles.sectionHeader}>
            <span style={styles.sectionTitle}>CLOUD STORAGE</span>
            <button 
              style={styles.smallIconBtn} 
              onClick={handleRefreshData} 
              title="Làm mới kết nối GCS"
            >
              <RefreshCw size={12} className={isRefreshing ? 'spin-icon' : ''} />
            </button>
          </div>

          {/* Active GCS Bucket Card */}
          <div 
            style={{
              padding: '12px 14px',
              borderRadius: 'var(--radius-sm)',
              backgroundColor: 'rgba(99, 102, 241, 0.12)',
              border: '1px solid rgba(99, 102, 241, 0.3)',
              cursor: 'pointer',
              display: 'flex',
              flexDirection: 'column',
              gap: 6
            }}
            onClick={() => {
              setCurrentPath([]);
              setActiveItem(null);
            }}
            title="Bấm để quay về Thư mục Gốc của Bucket"
          >
            <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                <Database size={15} color="var(--primary-light)" />
                <span style={{ fontSize: 13, fontWeight: 700, color: '#ffffff' }}>
                  {selectedBucket}
                </span>
              </div>
              <div style={{ width: 7, height: 7, borderRadius: '50%', backgroundColor: '#10b981', boxShadow: '0 0 6px #10b981' }} />
            </div>

            <div style={{ display: 'flex', flexDirection: 'column', gap: 2, marginTop: 2 }}>
              <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', fontSize: 11, color: 'var(--text-dim)' }}>
                <span>Thư mục gốc:</span>
                <span style={{ color: 'var(--text-main)', fontWeight: 500 }}>{basePrefix}</span>
              </div>
              <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', fontSize: 11, color: 'var(--text-dim)' }}>
                <span>Vị trí:</span>
                <span style={{ color: 'var(--text-main)', fontWeight: 500 }}>asia-southeast1</span>
              </div>
            </div>
          </div>
        </div>

        {/* Section: BỘ LỌC */}
        <div style={styles.filterSection}>
          <span style={styles.sectionTitle}>BỘ LỌC</span>

          <div style={styles.filterGroup}>
            <label style={styles.filterLabel}>Loại tệp</label>
            <select 
              style={styles.filterSelect}
              value={filterType}
              onChange={(e) => setFilterType(e.target.value)}
            >
              <option value="all">Tất cả</option>
              <option value="folder">Thư mục (Folder)</option>
              <option value="video">Video (MP4 / MKV)</option>
              <option value="audio">Audio (WAV / MP3)</option>
              <option value="subtitle">Phụ đề (SRT / ASS)</option>
              <option value="image">Hình ảnh (JPG / PNG)</option>
            </select>
          </div>

          <div style={styles.filterGroup}>
            <label style={styles.filterLabel}>Kích thước</label>
            <select 
              style={styles.filterSelect}
              value={filterSize}
              onChange={(e) => setFilterSize(e.target.value)}
            >
              <option value="all">Tất cả</option>
              <option value="small">&lt; 10 MB</option>
              <option value="medium">10 MB - 100 MB</option>
              <option value="large">&gt; 100 MB</option>
            </select>
          </div>

          <div style={styles.filterGroup}>
            <label style={styles.filterLabel}>Ngày tải lên</label>
            <select 
              style={styles.filterSelect}
              value={filterDate}
              onChange={(e) => setFilterDate(e.target.value)}
            >
              <option value="all">Tất cả</option>
              <option value="today">Hôm nay</option>
              <option value="7days">7 ngày qua</option>
              <option value="30days">30 ngày qua</option>
            </select>
          </div>

          <button 
            style={styles.resetFilterBtn}
            onClick={() => {
              setFilterType('all');
              setFilterSize('all');
              setFilterDate('all');
              setSearchQuery('');
            }}
          >
            Đặt lại
          </button>
        </div>

        {/* Section: HÀNH ĐỘNG NHANH */}
        <div style={styles.quickActionsSection}>
          <span style={styles.sectionTitle}>HÀNH ĐỘNG NHANH</span>

          <div style={styles.actionList}>
            <button style={styles.actionRowBtn} onClick={() => setShowNewFolderModal(true)}>
              <FolderPlus size={15} color="#f59e0b" />
              <span>Tạo folder mới</span>
            </button>

            <button style={styles.actionRowBtn} onClick={() => handleSyncUp(null)}>
              <ArrowUpFromLine size={15} color="#3b82f6" />
              <span>Đẩy dự án lên GCS (Sync-Up)</span>
            </button>

            <button style={styles.actionRowBtn} onClick={() => handleSyncDown(null)}>
              <ArrowDownToLine size={15} color="#10b981" />
              <span>Kéo dự án về Local (Sync-Down)</span>
            </button>

            <button style={styles.actionRowBtn} onClick={() => handleOffload(null)}>
              <HardDrive size={15} color="#06b6d4" />
              <span>Giải phóng bộ nhớ SSD</span>
            </button>

            <button style={styles.actionRowBtn} onClick={handleRefreshData}>
              <RefreshCw size={15} color="#a855f7" className={isRefreshing ? 'spin-icon' : ''} />
              <span>Làm mới danh mục</span>
            </button>
          </div>
        </div>
      </div>

      {/* ─────────────────────────────────────────────────────────────
          COL 2: CENTER GCS FILE EXPLORER
         ───────────────────────────────────────────────────────────── */}
      <div style={styles.explorerCenter}>
        {/* Top Header Bar */}
        <div style={styles.topStatusHeader}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
            <h2 style={styles.mainTitle}>Google Cloud Storage (GCS)</h2>
            <div style={{ ...styles.connectionBadge, borderColor: isConnected ? 'rgba(16, 185, 129, 0.3)' : 'rgba(239, 68, 68, 0.3)' }}>
              <span style={{ ...styles.greenDot, backgroundColor: isConnected ? '#10b981' : '#ef4444', boxShadow: `0 0 6px ${isConnected ? '#10b981' : '#ef4444'}` }} />
              <span style={{ fontSize: 12, fontWeight: 600, color: isConnected ? '#10b981' : '#ef4444' }}>
                {isConnected ? `Đã kết nối (gs://${selectedBucket})` : 'Mất kết nối'}
              </span>
            </div>
          </div>

          <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
            <button 
              style={styles.primaryActionBtn}
              onClick={() => handleSyncUp(null)}
              title={selectedItemIds.size > 0 ? `Tải lên ${selectedItemIds.size} mục đã chọn lên GCS` : "Tải lên hoặc đồng bộ từ Local lên Cloud"}
            >
              <Upload size={14} />
              <span>{selectedItemIds.size > 0 ? `Tải lên (${selectedItemIds.size})` : 'Tải lên (Sync-Up)'}</span>
            </button>

            <button 
              style={styles.secondaryActionBtn}
              onClick={() => handleSyncDown(null)}
              title={selectedItemIds.size > 0 ? `Đồng bộ ${selectedItemIds.size} mục đã chọn về máy tính` : "Đồng bộ tất cả tệp về máy tính"}
            >
              <ArrowDownToLine size={14} />
              <span>{selectedItemIds.size > 0 ? `Đồng bộ về local (${selectedItemIds.size})` : 'Đồng bộ về local'}</span>
            </button>

            <button 
              style={styles.iconCircleBtn}
              onClick={() => handleCopyPath(`gs://${fullPathStr}`)}
              title="Sao chép URI gs://"
            >
              <Copy size={14} />
            </button>

            {/* View Switcher */}
            <div style={styles.viewToggleGroup}>
              <button 
                style={{ ...styles.viewToggleBtn, ...(viewMode === 'list' ? styles.viewToggleBtnActive : {}) }}
                onClick={() => setViewMode('list')}
                title="Dạng danh sách"
              >
                <List size={15} />
              </button>
              <button 
                style={{ ...styles.viewToggleBtn, ...(viewMode === 'grid' ? styles.viewToggleBtnActive : {}) }}
                onClick={() => setViewMode('grid')}
                title="Dạng lưới"
              >
                <Grid size={15} />
              </button>
            </div>
          </div>
        </div>

        {/* Breadcrumbs & Path Row */}
        <div style={styles.breadcrumbBar}>
          <div style={styles.breadcrumbPath}>
            {currentPath.length > 0 && (
              <button style={styles.backBtn} onClick={handleNavigateUp} title="Lên thư mục cha">
                <ChevronLeft size={16} />
              </button>
            )}
            <span 
              style={{ ...styles.bucketBreadcrumb, cursor: 'pointer' }}
              onClick={() => handleNavigateToBreadcrumb(-1)}
            >
              {selectedBucket}
            </span>
            <span style={{ color: 'var(--text-dim)', fontSize: 13 }}>/</span>
            <span 
              style={{ color: 'var(--text-dim)', fontSize: 13, cursor: 'pointer' }}
              onClick={() => handleNavigateToBreadcrumb(-1)}
            >
              {basePrefix}
            </span>
            {currentPath.map((p, idx) => (
              <React.Fragment key={idx}>
                <span style={{ color: 'var(--text-dim)', fontSize: 13 }}>/</span>
                <span 
                  style={{ 
                    fontSize: 13, 
                    fontWeight: idx === currentPath.length - 1 ? 600 : 400, 
                    color: idx === currentPath.length - 1 ? '#ffffff' : 'var(--text-muted)',
                    cursor: 'pointer'
                  }}
                  onClick={() => handleNavigateToBreadcrumb(idx)}
                >
                  {p}
                </span>
              </React.Fragment>
            ))}
            <button 
              style={styles.copyPathIconBtn} 
              onClick={() => handleCopyPath(`gs://${fullPathStr}`)}
              title="Sao chép URI gs://"
            >
              <Copy size={13} />
            </button>
          </div>

          {/* Search in Current Folder */}
          <div style={styles.folderSearchBox}>
            <Search size={14} style={{ color: 'var(--text-dim)' }} />
            <input
              type="text"
              placeholder="Tìm trong thư mục..."
              value={searchQuery}
              onChange={(e) => {
                setSearchQuery(e.target.value);
                setCurrentPage(1);
              }}
              style={styles.folderSearchInput}
            />
            <button style={styles.filterIconButton} title="Bộ lọc">
              <Filter size={13} />
            </button>
          </div>
        </div>

        {/* File & Folder Table View */}
        <div style={styles.fileListContainer}>
          {isLoading ? (
            <div style={styles.emptyState}>
              <RefreshCw size={28} className="spin-icon" color="var(--primary-light)" />
              <span style={{ fontSize: 13, color: 'var(--text-muted)' }}>Đang tải dữ liệu từ Google Cloud Storage...</span>
            </div>
          ) : viewMode === 'list' ? (
            <div style={styles.tableWrapper}>
              <table style={styles.table}>
                <thead>
                  <tr style={styles.theadRow}>
                    <th style={{ ...styles.th, width: 36, textAlign: 'center' }}>
                      <div 
                        style={styles.checkboxWrapper}
                        onClick={handleToggleSelectAll}
                      >
                        {selectedItemIds.size > 0 && selectedItemIds.size === paginatedItems.length ? (
                          <CheckSquare size={16} color="var(--primary-light)" />
                        ) : (
                          <Square size={16} color="var(--text-dim)" />
                        )}
                      </div>
                    </th>
                    <th style={styles.th}>Tên</th>
                    <th style={{ ...styles.th, width: 110 }}>Loại</th>
                    <th style={{ ...styles.th, width: 110 }}>Kích thước</th>
                    <th style={{ ...styles.th, width: 150 }}>Ngày sửa đổi</th>
                    <th style={{ ...styles.th, width: 150, textAlign: 'right' }}>Thao tác</th>
                  </tr>
                </thead>
                <tbody>
                  {paginatedItems.length === 0 ? (
                    <tr>
                      <td colSpan={6} style={styles.emptyTd}>
                        <div style={styles.emptyState}>
                          <Folder size={36} color="var(--text-dim)" style={{ opacity: 0.4 }} />
                          <span style={{ fontSize: 13, color: 'var(--text-dim)' }}>Không tìm thấy tệp hoặc thư mục nào</span>
                        </div>
                      </td>
                    </tr>
                  ) : (
                    paginatedItems.map(item => {
                      const isSelected = selectedItemIds.has(item.id);
                      const isActive = activeItem?.id === item.id;

                      return (
                        <tr
                          key={item.id}
                          style={{
                            ...styles.tr,
                            ...(isSelected ? styles.trSelected : {}),
                            ...(isActive ? styles.trActive : {})
                          }}
                          onClick={() => handleItemClick(item)}
                          onDoubleClick={() => handleItemDoubleClick(item)}
                        >
                          {/* Checkbox */}
                          <td style={{ ...styles.td, textAlign: 'center' }}>
                            <div 
                              style={styles.checkboxWrapper}
                              onClick={(e) => handleToggleSelectItem(item.id, e)}
                            >
                              {isSelected ? (
                                <CheckSquare size={16} color="var(--primary-light)" />
                              ) : (
                                <Square size={16} color="var(--text-dim)" />
                              )}
                            </div>
                          </td>

                          {/* Name & Icon */}
                          <td style={styles.td}>
                            <div style={styles.fileNameCell}>
                              {getItemIcon(item)}
                              <span style={styles.fileNameText} title={item.name}>
                                {item.name}
                              </span>
                              {renderStatusBadge(item)}
                            </div>
                          </td>

                          {/* Type */}
                          <td style={styles.td}>
                            <span style={styles.typeBadge}>
                              {item.type === 'folder' ? 'Folder' : (item.ext || item.type.toUpperCase())}
                            </span>
                          </td>

                          {/* Size */}
                          <td style={styles.td}>
                            <span style={styles.sizeText}>
                              {item.size ? formatBytes(item.size) : (item.itemsCount !== undefined ? `${item.itemsCount} mục` : '-')}
                            </span>
                          </td>

                          {/* Modified Date */}
                          <td style={styles.td}>
                            <span style={styles.dateText}>{item.modified || '-'}</span>
                          </td>

                          {/* Actions */}
                          <td style={{ ...styles.td, textAlign: 'right' }}>
                            <div style={styles.rowActionBtns} onClick={e => e.stopPropagation()}>
                              <button 
                                style={styles.rowIconBtn}
                                onClick={() => handleSyncUp(item)}
                                title="Đẩy tệp này lên Google Cloud Storage (Sync-Up)"
                              >
                                <CloudUpload size={14} color="#818cf8" />
                              </button>
                              <button 
                                style={styles.rowIconBtn}
                                onClick={() => handleSyncDown(item)}
                                title="Tải tệp này về máy tính (Sync-Down)"
                              >
                                <Download size={14} color="#10b981" />
                              </button>
                              <button 
                                style={styles.rowIconBtn}
                                onClick={() => handleCopyPath(item.gcsUri || `gs://${selectedBucket}/${basePrefix}/${item.path}`)}
                                title="Sao chép URI Cloud"
                              >
                                <Copy size={13} />
                              </button>
                              <button 
                                style={styles.rowIconBtn}
                                onClick={() => handleOpenDeleteDialog(item)}
                                title="Xóa tệp (Chọn xóa Cloud, Local hoặc Cả hai)"
                              >
                                <Trash2 size={13} color="var(--accent-red)" />
                              </button>
                            </div>
                          </td>
                        </tr>
                      );
                    })
                  )}
                </tbody>
              </table>
            </div>
          ) : (
            /* Grid View */
            <div style={styles.gridContainer}>
              {paginatedItems.map(item => {
                const isSelected = selectedItemIds.has(item.id);
                const isActive = activeItem?.id === item.id;

                return (
                  <div
                    key={item.id}
                    style={{
                      ...styles.gridCard,
                      ...(isSelected ? styles.gridCardSelected : {}),
                      ...(isActive ? styles.gridCardActive : {})
                    }}
                    onClick={() => handleItemClick(item)}
                    onDoubleClick={() => handleItemDoubleClick(item)}
                  >
                    {/* Top Bar: Checkbox & Row Actions */}
                    <div style={styles.gridCardTop}>
                      <div 
                        style={styles.checkboxWrapper}
                        onClick={(e) => handleToggleSelectItem(item.id, e)}
                      >
                        {isSelected ? (
                          <CheckSquare size={16} color="var(--primary-light)" />
                        ) : (
                          <Square size={16} color="var(--text-dim)" />
                        )}
                      </div>

                      <div style={styles.gridCardRowActions} onClick={e => e.stopPropagation()}>
                        <button 
                          style={styles.gridTinyBtn}
                          onClick={() => handleSyncUp(item)}
                          title="Đẩy tệp này lên Google Cloud Storage (Sync-Up)"
                        >
                          <CloudUpload size={13} color="#818cf8" />
                        </button>
                        <button 
                          style={styles.gridTinyBtn}
                          onClick={() => handleSyncDown(item)}
                          title="Tải tệp này về máy tính (Sync-Down)"
                        >
                          <Download size={13} color="#10b981" />
                        </button>
                        <button 
                          style={styles.gridTinyBtn}
                          onClick={() => handleOpenDeleteDialog(item)}
                          title="Xóa tệp"
                        >
                          <Trash2 size={12} color="var(--accent-red)" />
                        </button>
                      </div>
                    </div>

                    {/* Big Center Icon */}
                    <div style={styles.gridCardIconBox}>
                      {getItemIcon(item)}
                    </div>

                    {/* Card Body */}
                    <div style={styles.gridCardBody}>
                      <span style={styles.gridCardName} title={item.name}>
                        {item.name}
                      </span>
                      
                      <div style={{ marginTop: 2, marginBottom: 2 }}>
                        {renderStatusBadge(item)}
                      </div>

                      <div style={styles.gridCardMeta}>
                        <span style={styles.gridMetaSize}>
                          {item.type === 'folder' ? (item.itemsCount !== undefined ? `${item.itemsCount} mục` : 'Folder') : formatBytes(item.size)}
                        </span>
                        <span style={styles.gridMetaDate}>
                          {item.modified || '-'}
                        </span>
                      </div>
                    </div>
                  </div>
                );
              })}
            </div>
          )}
        </div>

        {/* Pagination & Counter */}
        <div style={styles.paginationBar}>
          <span style={styles.pageCountText}>
            Hiển thị 1 - {paginatedItems.length} trong {filteredItems.length} mục ({formatBytes(totalCloudBytes)})
          </span>

          <div style={styles.paginationControls}>
            <select
              style={styles.pageSelect}
              value={itemsPerPage}
              onChange={(e) => {
                setItemsPerPage(Number(e.target.value));
                setCurrentPage(1);
              }}
            >
              <option value={10}>10 / trang</option>
              <option value={20}>20 / trang</option>
              <option value={50}>50 / trang</option>
            </select>

            <button 
              style={styles.pageNavBtn} 
              disabled={currentPage <= 1}
              onClick={() => setCurrentPage(p => Math.max(1, p - 1))}
            >
              <ChevronLeft size={14} />
            </button>

            <span style={styles.activePageNum}>{currentPage}</span>
            {totalPages > 1 && <span style={styles.otherPageNum}>{totalPages}</span>}

            <button 
              style={styles.pageNavBtn} 
              disabled={currentPage >= totalPages}
              onClick={() => setCurrentPage(p => Math.min(totalPages, p + 1))}
            >
              <ChevronRight size={14} />
            </button>
          </div>
        </div>

        {/* Live Sync Progress Card */}
        {showSyncCard && (
          <div style={styles.syncProgressContainer}>
            <div style={styles.syncCard}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 12, flex: 1 }}>
                <div style={styles.syncIconBox}>
                  <RefreshCw size={18} className="spin-icon" color="#6366f1" />
                </div>
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div style={styles.syncSubtitleRow}>
                    <span style={styles.syncTitle}>{syncTitle}</span>
                    <span style={styles.syncPercent}>{syncProgress}%</span>
                  </div>
                  <div style={styles.progressBarBg}>
                    <div style={{ ...styles.progressBarFill, width: `${syncProgress}%` }} />
                  </div>
                </div>
              </div>

              <div style={styles.syncRightControls}>
                <div style={styles.syncStatsCol}>
                  <span style={styles.syncStatText}>Tốc độ: {syncSpeed}</span>
                  <span style={styles.syncStatText}>Còn lại: {syncEta}</span>
                </div>
                <button 
                  style={styles.syncPauseBtn}
                  onClick={() => setIsSyncPaused(!isSyncPaused)}
                >
                  {isSyncPaused ? <Play size={12} /> : <Pause size={12} />}
                  <span>{isSyncPaused ? 'Tiếp tục' : 'Tạm dừng'}</span>
                </button>
                <button 
                  style={styles.syncCancelBtn}
                  onClick={() => setShowSyncCard(false)}
                >
                  <X size={12} />
                  <span>Hủy</span>
                </button>
              </div>
            </div>
          </div>
        )}
      </div>

      {/* ─────────────────────────────────────────────────────────────
          COL 3: RIGHT DETAILS INSPECTOR
         ───────────────────────────────────────────────────────────── */}
      <div style={styles.detailsInspector}>
        <div style={styles.inspectorHeader}>
          <span style={styles.inspectorTitle}>CHI TIẾT</span>
        </div>

        {/* Item Preview */}
        <div style={styles.previewCard}>
          <div style={styles.previewIconBox}>
            {activeInspectorItem.type === 'folder' ? (
              <Folder size={48} color="#f59e0b" fill="#f59e0b" style={{ opacity: 0.9 }} />
            ) : activeInspectorItem.type === 'video' ? (
              <Video size={48} color="#3b82f6" />
            ) : (
              <File size={48} color="#94a3b8" />
            )}
          </div>
          <h3 style={styles.previewName} title={activeInspectorItem.name}>
            {activeInspectorItem.name}
          </h3>
          <span style={styles.previewType}>
            {activeInspectorItem.type === 'folder' ? 'Folder' : (activeInspectorItem.ext || 'File')}
          </span>
        </div>

        {/* Metadata Properties List */}
        <div style={styles.metaList}>
          <div style={styles.metaRow}>
            <span style={styles.metaLabel}>Trạng thái</span>
            <div style={{ display: 'flex', alignItems: 'center' }}>
              {renderStatusBadge(activeInspectorItem) || (
                <span style={{ fontSize: 11.5, color: 'var(--text-muted)' }}>Thư mục dự án</span>
              )}
            </div>
          </div>

          <div style={styles.metaRow}>
            <span style={styles.metaLabel}>Đường dẫn GCS</span>
            <div style={styles.metaValWithCopy}>
              <span style={styles.metaValPath} title={activeInspectorItem.gcsUri || `gs://${fullPathStr}`}>
                {activeInspectorItem.gcsUri || `gs://${fullPathStr}`}
              </span>
              <button 
                style={styles.copyTinyBtn} 
                onClick={() => handleCopyPath(activeInspectorItem.gcsUri || `gs://${fullPathStr}`)}
                title="Sao chép"
              >
                <Copy size={11} />
              </button>
            </div>
          </div>

          <div style={styles.metaRow}>
            <span style={styles.metaLabel}>Kích thước</span>
            <span style={styles.metaValue}>
              {activeInspectorItem.sizeStr || (activeInspectorItem.size ? formatBytes(activeInspectorItem.size) : '-')}
            </span>
          </div>

          <div style={styles.metaRow}>
            <span style={styles.metaLabel}>Số lượng mục</span>
            <span style={styles.metaValue}>
              {activeInspectorItem.itemsCount !== undefined ? activeInspectorItem.itemsCount : '-'}
            </span>
          </div>

          <div style={styles.metaRow}>
            <span style={styles.metaLabel}>Ngày tạo</span>
            <span style={styles.metaValue}>{activeInspectorItem.created || '10/05/2024 09:15'}</span>
          </div>

          <div style={styles.metaRow}>
            <span style={styles.metaLabel}>Cập nhật lần cuối</span>
            <span style={styles.metaValue}>{activeInspectorItem.modified || '14/08/2026 16:56'}</span>
          </div>

          <div style={styles.metaRow}>
            <span style={styles.metaLabel}>Lớp lưu trữ</span>
            <span style={styles.metaValue}>{activeInspectorItem.storageClass || 'Standard'}</span>
          </div>

          <div style={styles.metaRow}>
            <span style={styles.metaLabel}>Vị trí Bucket</span>
            <span style={styles.metaValue}>{activeInspectorItem.location || 'asia-southeast1 (Singapore)'}</span>
          </div>
        </div>

        {/* Section: THAO TÁC */}
        <div style={styles.inspectorActionsSection}>
          <span style={styles.inspectorSubTitle}>THAO TÁC</span>

          <div style={styles.inspectorBtnList}>
            <button 
              style={styles.inspectorActionBtn}
              onClick={() => handleCopyPath(activeInspectorItem.gcsUri || `gs://${fullPathStr}`)}
            >
              <Share2 size={14} color="#3b82f6" />
              <span>Chia sẻ liên kết</span>
            </button>

            <button 
              style={styles.inspectorActionBtn}
              onClick={() => handleCopyPath(activeInspectorItem.gcsUri || `gs://${fullPathStr}`)}
            >
              <Copy size={14} color="#8b5cf6" />
              <span>Sao chép URI (gs://)</span>
            </button>

            <button 
              style={styles.inspectorActionBtn}
              onClick={() => handleSyncDown(activeInspectorItem)}
            >
              <ArrowDownToLine size={14} color="#10b981" />
              <span>Đồng bộ về local (Sync-Down)</span>
            </button>

            <button 
              style={styles.inspectorActionBtn}
              onClick={() => handleOffload(activeInspectorItem)}
            >
              <HardDrive size={14} color="#06b6d4" />
              <span>Giải phóng SSD (Offload)</span>
            </button>

            <button 
              style={{ ...styles.inspectorActionBtn, color: 'var(--accent-red)' }}
              onClick={() => handleOpenDeleteDialog(activeInspectorItem)}
            >
              <Trash2 size={14} color="var(--accent-red)" />
              <span>Xóa tệp</span>
            </button>
          </div>
        </div>

        {/* Section: DUNG LƯỢNG BUCKET */}
        <div style={styles.quotaSection}>
          <span style={styles.inspectorSubTitle}>DUNG LƯỢNG BUCKET ({selectedBucket})</span>
          
          <div style={styles.quotaBarWrapper}>
            <div style={styles.quotaProgressBg}>
              <div style={{ ...styles.quotaProgressFill, width: '25.7%' }} />
            </div>
            <div style={styles.quotaTextRow}>
              <span>{formatBytes(totalCloudBytes || 128.5 * 1024 * 1024 * 1024)} / 500 GB</span>
              <span style={{ color: 'var(--text-dim)' }}>(25.7%)</span>
            </div>
          </div>

          <button 
            style={styles.manageBucketBtn}
            onClick={handleRefreshData}
          >
            Làm mới bộ nhớ Bucket
          </button>
        </div>
      </div>

      {/* ─────────────────────────────────────────────────────────────
          MODALS: NEW FOLDER & NEW BUCKET
         ───────────────────────────────────────────────────────────── */}
      {showNewFolderModal && (
        <div style={styles.modalOverlay} onClick={() => setShowNewFolderModal(false)}>
          <div style={styles.modalContent} onClick={e => e.stopPropagation()}>
            <h3 style={styles.modalTitle}>Tạo Thư Mục Mới Trên GCS</h3>
            <p style={styles.modalSubtitle}>Đường dẫn: gs://{fullPathStr}/</p>
            <form onSubmit={handleCreateNewFolder}>
              <input
                type="text"
                placeholder="Nhập tên thư mục (ví dụ: 06_Review)..."
                value={newFolderName}
                onChange={e => setNewFolderName(e.target.value)}
                style={styles.modalInput}
                autoFocus
              />
              <div style={styles.modalActionRow}>
                <button 
                  type="button" 
                  style={styles.modalCancelBtn} 
                  onClick={() => setShowNewFolderModal(false)}
                >
                  Hủy
                </button>
                <button 
                  type="submit" 
                  style={styles.modalSubmitBtn}
                  disabled={!newFolderName.trim()}
                >
                  Tạo Thư Mục
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      {/* ─────────────────────────────────────────────────────────────
          MODAL: DELETE DESTINATION SELECTION (Cloud, Local, Both)
         ───────────────────────────────────────────────────────────── */}
      {showDeleteModal && (
        <div style={styles.modalOverlay} onClick={() => !isDeleting && setShowDeleteModal(false)}>
          <div style={{ ...styles.modalContent, maxWidth: 500 }} onClick={e => e.stopPropagation()}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 12, marginBottom: 14 }}>
              <div style={{ width: 40, height: 40, borderRadius: '50%', backgroundColor: 'rgba(239, 68, 68, 0.15)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                <Trash2 size={20} color="var(--accent-red)" />
              </div>
              <div>
                <h3 style={{ ...styles.modalTitle, margin: 0 }}>Xác Nhận Xóa Tệp</h3>
                <p style={{ ...styles.modalSubtitle, margin: '2px 0 0 0' }}>
                  {deleteTargetFiles.length === 1 
                    ? `Tệp: ${deleteTargetFiles[0].name}` 
                    : `${deleteTargetFiles.length} tệp được chọn`}
                </p>
              </div>
            </div>

            <div style={{ marginBottom: 18 }}>
              <label style={{ fontSize: 12, fontWeight: 600, color: 'var(--text-main)', marginBottom: 10, display: 'block' }}>
                Bạn muốn thực hiện xóa ở đâu?
              </label>

              <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
                {/* Option 1: Cloud Only */}
                <div 
                  style={{
                    padding: '12px 14px',
                    borderRadius: 8,
                    border: `1.5px solid ${deleteScope === 'cloud_only' ? '#a855f7' : 'rgba(255, 255, 255, 0.08)'}`,
                    backgroundColor: deleteScope === 'cloud_only' ? 'rgba(168, 85, 247, 0.12)' : 'rgba(255, 255, 255, 0.03)',
                    cursor: 'pointer',
                    display: 'flex',
                    alignItems: 'flex-start',
                    gap: 12,
                    transition: 'all 0.15s ease'
                  }}
                  onClick={() => setDeleteScope('cloud_only')}
                >
                  <input 
                    type="radio" 
                    name="deleteScope" 
                    checked={deleteScope === 'cloud_only'} 
                    onChange={() => setDeleteScope('cloud_only')}
                    style={{ marginTop: 3, accentColor: '#a855f7', cursor: 'pointer' }}
                  />
                  <div style={{ flex: 1 }}>
                    <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                      <span style={{ fontSize: 13.5, fontWeight: 600, color: '#ffffff' }}>☁️ Chỉ xóa trên Cloud (GCS)</span>
                      <span style={styles.cloudOnlyBadge}>Giữ bản Local</span>
                    </div>
                    <p style={{ fontSize: 11.5, color: 'var(--text-muted)', margin: '4px 0 0 0', lineHeight: 1.45 }}>
                      Xóa vĩnh viễn tệp khỏi Google Cloud Storage. Bản sao trên máy tính vẫn được giữ nguyên an toàn.
                    </p>
                  </div>
                </div>

                {/* Option 2: Local Only */}
                <div 
                  style={{
                    padding: '12px 14px',
                    borderRadius: 8,
                    border: `1.5px solid ${deleteScope === 'local_only' ? '#38bdf8' : 'rgba(255, 255, 255, 0.08)'}`,
                    backgroundColor: deleteScope === 'local_only' ? 'rgba(56, 189, 248, 0.12)' : 'rgba(255, 255, 255, 0.03)',
                    cursor: 'pointer',
                    display: 'flex',
                    alignItems: 'flex-start',
                    gap: 12,
                    transition: 'all 0.15s ease'
                  }}
                  onClick={() => setDeleteScope('local_only')}
                >
                  <input 
                    type="radio" 
                    name="deleteScope" 
                    checked={deleteScope === 'local_only'} 
                    onChange={() => setDeleteScope('local_only')}
                    style={{ marginTop: 3, accentColor: '#38bdf8', cursor: 'pointer' }}
                  />
                  <div style={{ flex: 1 }}>
                    <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                      <span style={{ fontSize: 13.5, fontWeight: 600, color: '#ffffff' }}>💻 Chỉ xóa ở Local (Máy tính - Offload)</span>
                      <span style={styles.localOnlyBadge}>Giữ bản Cloud</span>
                    </div>
                    <p style={{ fontSize: 11.5, color: 'var(--text-muted)', margin: '4px 0 0 0', lineHeight: 1.45 }}>
                      Xóa bản sao trên ổ SSD để giải phóng dung lượng bộ nhớ. Bản gốc trên Cloud GCS vẫn an toàn.
                    </p>
                  </div>
                </div>

                {/* Option 3: Both */}
                <div 
                  style={{
                    padding: '12px 14px',
                    borderRadius: 8,
                    border: `1.5px solid ${deleteScope === 'both' ? 'var(--accent-red)' : 'rgba(255, 255, 255, 0.08)'}`,
                    backgroundColor: deleteScope === 'both' ? 'rgba(239, 68, 68, 0.15)' : 'rgba(255, 255, 255, 0.03)',
                    cursor: 'pointer',
                    display: 'flex',
                    alignItems: 'flex-start',
                    gap: 12,
                    transition: 'all 0.15s ease'
                  }}
                  onClick={() => setDeleteScope('both')}
                >
                  <input 
                    type="radio" 
                    name="deleteScope" 
                    checked={deleteScope === 'both'} 
                    onChange={() => setDeleteScope('both')}
                    style={{ marginTop: 3, accentColor: 'var(--accent-red)', cursor: 'pointer' }}
                  />
                  <div style={{ flex: 1 }}>
                    <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                      <span style={{ fontSize: 13.5, fontWeight: 600, color: '#f87171' }}>🔥 Xóa cả 2 nơi (Cloud & Local)</span>
                      <span style={{ fontSize: 10, color: '#f87171', backgroundColor: 'rgba(239, 68, 68, 0.25)', padding: '2px 6px', borderRadius: 3, fontWeight: 700 }}>
                        Vĩnh viễn
                      </span>
                    </div>
                    <p style={{ fontSize: 11.5, color: 'var(--text-muted)', margin: '4px 0 0 0', lineHeight: 1.45 }}>
                      Xóa hoàn toàn tệp trên cả Google Cloud và ổ cứng máy tính. Thao tác này <strong>không thể hoàn tác</strong>!
                    </p>
                  </div>
                </div>
              </div>
            </div>

            <div style={styles.modalActionRow}>
              <button 
                type="button" 
                style={styles.modalCancelBtn} 
                onClick={() => setShowDeleteModal(false)}
                disabled={isDeleting}
              >
                Hủy
              </button>
              <button 
                type="button" 
                style={{
                  ...styles.modalSubmitBtn,
                  backgroundColor: deleteScope === 'both' ? 'var(--accent-red)' : (deleteScope === 'local_only' ? '#0284c7' : '#9333ea')
                }}
                onClick={handleConfirmDelete}
                disabled={isDeleting}
              >
                {isDeleting ? 'Đang xóa...' : 'Xác Nhận Xóa'}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// STYLES (Studio Dark Theme matching App index.css)
// ─────────────────────────────────────────────────────────────
const styles = {
  container: {
    display: 'flex',
    width: '100%',
    height: '100%',
    backgroundColor: 'var(--bg-app)',
    color: 'var(--text-main)',
    overflow: 'hidden',
    userSelect: 'none',
  },

  // ── SUB-SIDEBAR (COLUMN 1) ──────────────────────────────────
  subSidebar: {
    width: '240px',
    backgroundColor: 'var(--bg-sidebar)',
    borderRight: '1px solid var(--border-color)',
    display: 'flex',
    flexDirection: 'column',
    overflowY: 'auto',
    flexShrink: 0,
    padding: '16px 12px',
    gap: 20,
  },
  bucketSection: {
    display: 'flex',
    flexDirection: 'column',
    gap: 10,
  },
  sectionHeader: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  sectionTitle: {
    fontSize: 11,
    fontWeight: 700,
    color: 'var(--text-dim)',
    letterSpacing: '0.06em',
    textTransform: 'uppercase',
  },
  iconBtnGroup: {
    display: 'flex',
    alignItems: 'center',
    gap: 4,
  },
  smallIconBtn: {
    background: 'rgba(255, 255, 255, 0.05)',
    border: '1px solid var(--border-color)',
    color: 'var(--text-muted)',
    width: 24,
    height: 24,
    borderRadius: 5,
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    cursor: 'pointer',
    transition: 'all 0.15s',
  },
  inputSearchWrapper: {
    display: 'flex',
    alignItems: 'center',
    gap: 6,
    padding: '6px 10px',
    backgroundColor: 'var(--bg-input)',
    border: '1px solid var(--border-color)',
    borderRadius: 'var(--radius-sm)',
  },
  searchInput: {
    background: 'transparent',
    border: 'none',
    color: 'var(--text-main)',
    fontSize: 12,
    width: '100%',
    outline: 'none',
  },
  bucketList: {
    display: 'flex',
    flexDirection: 'column',
    gap: 2,
  },
  bucketItem: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between',
    padding: '8px 10px',
    borderRadius: 'var(--radius-sm)',
    cursor: 'pointer',
    transition: 'background 0.15s',
    border: '1px solid transparent',
  },
  bucketItemActive: {
    backgroundColor: 'rgba(99, 102, 241, 0.15)',
    borderColor: 'rgba(99, 102, 241, 0.35)',
  },
  activeDot: {
    width: 6,
    height: 6,
    borderRadius: '50%',
    backgroundColor: 'var(--primary-light)',
  },
  filterSection: {
    display: 'flex',
    flexDirection: 'column',
    gap: 10,
    paddingTop: 12,
    borderTop: '1px solid var(--border-color)',
  },
  filterGroup: {
    display: 'flex',
    flexDirection: 'column',
    gap: 4,
  },
  filterLabel: {
    fontSize: 11,
    color: 'var(--text-dim)',
  },
  filterSelect: {
    backgroundColor: 'var(--bg-input)',
    border: '1px solid var(--border-color)',
    color: 'var(--text-main)',
    fontSize: 12,
    padding: '6px 8px',
    borderRadius: 'var(--radius-sm)',
    outline: 'none',
    cursor: 'pointer',
  },
  resetFilterBtn: {
    padding: '6px 10px',
    backgroundColor: 'rgba(255, 255, 255, 0.04)',
    border: '1px solid var(--border-color)',
    color: 'var(--text-muted)',
    borderRadius: 'var(--radius-sm)',
    fontSize: 12,
    fontWeight: 500,
    marginTop: 4,
    cursor: 'pointer',
  },
  quickActionsSection: {
    display: 'flex',
    flexDirection: 'column',
    gap: 10,
    paddingTop: 12,
    borderTop: '1px solid var(--border-color)',
  },
  actionList: {
    display: 'flex',
    flexDirection: 'column',
    gap: 4,
  },
  actionRowBtn: {
    display: 'flex',
    alignItems: 'center',
    gap: 10,
    padding: '8px 10px',
    background: 'transparent',
    border: 'none',
    borderRadius: 'var(--radius-sm)',
    color: 'var(--text-muted)',
    fontSize: 12.5,
    cursor: 'pointer',
    textAlign: 'left',
    transition: 'all 0.15s',
  },

  // ── CENTER GCS FILE EXPLORER (COLUMN 2) ─────────────────────
  explorerCenter: {
    flex: 1,
    display: 'flex',
    flexDirection: 'column',
    backgroundColor: 'var(--bg-app)',
    overflow: 'hidden',
    position: 'relative',
  },
  topStatusHeader: {
    height: 52,
    borderBottom: '1px solid var(--border-color)',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between',
    padding: '0 20px',
    backgroundColor: 'var(--bg-card)',
    flexShrink: 0,
  },
  mainTitle: {
    fontSize: 15,
    fontWeight: 700,
    color: 'var(--text-main)',
    margin: 0,
  },
  connectionBadge: {
    display: 'flex',
    alignItems: 'center',
    gap: 6,
    padding: '3px 8px',
    borderRadius: 12,
    backgroundColor: 'rgba(16, 185, 129, 0.12)',
    border: '1px solid rgba(16, 185, 129, 0.25)',
  },
  greenDot: {
    width: 7,
    height: 7,
    borderRadius: '50%',
    backgroundColor: '#10b981',
    boxShadow: '0 0 6px #10b981',
  },
  primaryActionBtn: {
    display: 'flex',
    alignItems: 'center',
    gap: 6,
    padding: '6px 14px',
    borderRadius: 'var(--radius-sm)',
    background: 'linear-gradient(135deg, #6366f1 0%, #4f46e5 100%)',
    color: '#ffffff',
    fontSize: 12.5,
    fontWeight: 600,
    border: 'none',
    boxShadow: '0 2px 8px rgba(99, 102, 241, 0.35)',
    cursor: 'pointer',
  },
  secondaryActionBtn: {
    display: 'flex',
    alignItems: 'center',
    gap: 6,
    padding: '6px 12px',
    borderRadius: 'var(--radius-sm)',
    backgroundColor: 'var(--bg-surface)',
    border: '1px solid var(--border-color)',
    color: 'var(--text-main)',
    fontSize: 12.5,
    fontWeight: 500,
    cursor: 'pointer',
  },
  iconCircleBtn: {
    width: 30,
    height: 30,
    borderRadius: 'var(--radius-sm)',
    backgroundColor: 'var(--bg-surface)',
    border: '1px solid var(--border-color)',
    color: 'var(--text-muted)',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    cursor: 'pointer',
  },
  viewToggleGroup: {
    display: 'flex',
    alignItems: 'center',
    backgroundColor: 'var(--bg-input)',
    border: '1px solid var(--border-color)',
    borderRadius: 'var(--radius-sm)',
    padding: 2,
  },
  viewToggleBtn: {
    width: 26,
    height: 26,
    borderRadius: 4,
    background: 'transparent',
    border: 'none',
    color: 'var(--text-dim)',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    cursor: 'pointer',
  },
  viewToggleBtnActive: {
    backgroundColor: 'var(--bg-card)',
    color: 'var(--primary)',
    boxShadow: 'var(--shadow-sm)',
  },
  breadcrumbBar: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between',
    padding: '10px 20px',
    borderBottom: '1px solid var(--border-color)',
    backgroundColor: 'var(--bg-surface)',
    flexShrink: 0,
    gap: 16,
  },
  breadcrumbPath: {
    display: 'flex',
    alignItems: 'center',
    gap: 6,
    overflow: 'hidden',
  },
  backBtn: {
    background: 'var(--bg-surface)',
    border: '1px solid var(--border-color)',
    borderRadius: 4,
    width: 22,
    height: 22,
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    color: 'var(--text-main)',
    cursor: 'pointer',
  },
  bucketBreadcrumb: {
    fontSize: 13,
    fontWeight: 600,
    color: 'var(--primary)',
  },
  copyPathIconBtn: {
    background: 'transparent',
    border: 'none',
    color: 'var(--text-dim)',
    cursor: 'pointer',
    padding: 2,
    display: 'flex',
    alignItems: 'center',
  },
  folderSearchBox: {
    display: 'flex',
    alignItems: 'center',
    gap: 8,
    padding: '5px 10px',
    backgroundColor: 'var(--bg-input)',
    border: '1px solid var(--border-color)',
    borderRadius: 'var(--radius-sm)',
    width: '240px',
  },
  folderSearchInput: {
    background: 'transparent',
    border: 'none',
    color: 'var(--text-main)',
    fontSize: 12,
    outline: 'none',
    width: '100%',
  },
  filterIconButton: {
    background: 'transparent',
    border: 'none',
    color: 'var(--text-dim)',
    cursor: 'pointer',
    display: 'flex',
    alignItems: 'center',
  },
  fileListContainer: {
    flex: 1,
    overflowY: 'auto',
    display: 'flex',
    flexDirection: 'column',
  },
  tableWrapper: {
    width: '100%',
  },
  table: {
    width: '100%',
    borderCollapse: 'collapse',
    textAlign: 'left',
  },
  theadRow: {
    borderBottom: '1px solid var(--border-color)',
    backgroundColor: 'var(--bg-surface)',
  },
  th: {
    padding: '10px 14px',
    fontSize: 11,
    fontWeight: 600,
    color: 'var(--text-dim)',
    textTransform: 'uppercase',
    letterSpacing: '0.04em',
  },
  tr: {
    borderBottom: '1px solid var(--border-subtle)',
    cursor: 'pointer',
    transition: 'background 0.12s',
  },
  trSelected: {
    backgroundColor: 'rgba(99, 102, 241, 0.12)',
  },
  trActive: {
    backgroundColor: 'rgba(99, 102, 241, 0.2)',
  },
  td: {
    padding: '10px 14px',
    fontSize: 12.5,
    color: 'var(--text-main)',
    verticalAlign: 'middle',
  },
  checkboxWrapper: {
    display: 'inline-flex',
    cursor: 'pointer',
  },
  fileNameCell: {
    display: 'flex',
    alignItems: 'center',
    gap: 10,
  },
  fileNameText: {
    fontWeight: 500,
    color: 'var(--text-main)',
  },
  syncedBadge: {
    fontSize: 10.5,
    fontWeight: 600,
    color: '#34d399',
    backgroundColor: 'rgba(16, 185, 129, 0.14)',
    border: '1px solid rgba(16, 185, 129, 0.35)',
    padding: '2px 7px',
    borderRadius: 4,
    display: 'inline-flex',
    alignItems: 'center',
    gap: 4,
  },
  localOnlyBadge: {
    fontSize: 10.5,
    fontWeight: 600,
    color: '#38bdf8',
    backgroundColor: 'rgba(56, 189, 248, 0.14)',
    border: '1px solid rgba(56, 189, 248, 0.35)',
    padding: '2px 7px',
    borderRadius: 4,
    display: 'inline-flex',
    alignItems: 'center',
    gap: 4,
  },
  cloudOnlyBadge: {
    fontSize: 10.5,
    fontWeight: 600,
    color: '#c084fc',
    backgroundColor: 'rgba(168, 85, 247, 0.14)',
    border: '1px solid rgba(168, 85, 247, 0.35)',
    padding: '2px 7px',
    borderRadius: 4,
    display: 'inline-flex',
    alignItems: 'center',
    gap: 4,
  },
  modifiedBadge: {
    fontSize: 10.5,
    fontWeight: 600,
    color: '#fbbf24',
    backgroundColor: 'rgba(245, 158, 11, 0.14)',
    border: '1px solid rgba(245, 158, 11, 0.35)',
    padding: '2px 7px',
    borderRadius: 4,
    display: 'inline-flex',
    alignItems: 'center',
    gap: 4,
  },
  badgeDotGreen: {
    width: 6,
    height: 6,
    borderRadius: '50%',
    backgroundColor: '#10b981',
    boxShadow: '0 0 5px #10b981',
  },
  badgeDotBlue: {
    width: 6,
    height: 6,
    borderRadius: '50%',
    backgroundColor: '#38bdf8',
    boxShadow: '0 0 5px #38bdf8',
  },
  badgeDotPurple: {
    width: 6,
    height: 6,
    borderRadius: '50%',
    backgroundColor: '#a855f7',
    boxShadow: '0 0 5px #a855f7',
  },
  badgeDotYellow: {
    width: 6,
    height: 6,
    borderRadius: '50%',
    backgroundColor: '#f59e0b',
    boxShadow: '0 0 5px #f59e0b',
  },
  typeBadge: {
    fontSize: 11,
    color: 'var(--text-muted)',
    fontWeight: 500,
  },
  sizeText: {
    fontSize: 12,
    color: 'var(--text-muted)',
    fontVariantNumeric: 'tabular-nums',
  },
  dateText: {
    fontSize: 12,
    color: 'var(--text-dim)',
    fontVariantNumeric: 'tabular-nums',
  },
  rowActionBtns: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'flex-end',
    gap: 6,
  },
  rowIconBtn: {
    background: 'transparent',
    border: 'none',
    color: 'var(--text-dim)',
    cursor: 'pointer',
    padding: 4,
    borderRadius: 4,
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    transition: 'color 0.15s',
  },
  emptyTd: {
    padding: '60px 0',
    textAlign: 'center',
  },
  emptyState: {
    display: 'flex',
    flexDirection: 'column',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 10,
    padding: '60px 0',
  },
  gridContainer: {
    display: 'grid',
    gridTemplateColumns: 'repeat(auto-fill, minmax(200px, 1fr))',
    gap: 16,
    padding: 20,
  },
  gridCard: {
    display: 'flex',
    flexDirection: 'column',
    alignItems: 'center',
    padding: '12px 14px',
    borderRadius: 'var(--radius-md)',
    backgroundColor: 'var(--bg-card)',
    border: '1px solid var(--border-color)',
    boxShadow: 'var(--shadow-sm)',
    cursor: 'pointer',
    textAlign: 'center',
    transition: 'all 0.2s ease',
    gap: 8,
  },
  gridCardSelected: {
    borderColor: 'var(--primary-light)',
    backgroundColor: 'rgba(99, 102, 241, 0.15)',
    boxShadow: '0 0 12px rgba(99, 102, 241, 0.2)',
  },
  gridCardActive: {
    borderColor: 'var(--primary)',
    backgroundColor: 'rgba(99, 102, 241, 0.25)',
  },
  gridCardTop: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between',
    width: '100%',
  },
  gridCardRowActions: {
    display: 'flex',
    alignItems: 'center',
    gap: 4,
  },
  gridTinyBtn: {
    background: 'var(--bg-surface)',
    border: '1px solid var(--border-color)',
    borderRadius: 4,
    width: 22,
    height: 22,
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    cursor: 'pointer',
    transition: 'background 0.15s',
  },
  gridCardIconBox: {
    width: 48,
    height: 48,
    borderRadius: 10,
    backgroundColor: 'var(--bg-surface)',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    margin: '2px 0',
  },
  gridCardBody: {
    display: 'flex',
    flexDirection: 'column',
    alignItems: 'center',
    width: '100%',
    gap: 4,
  },
  gridCardName: {
    fontSize: 12.5,
    fontWeight: 600,
    color: 'var(--text-main)',
    width: '100%',
    overflow: 'hidden',
    textOverflow: 'ellipsis',
    whiteSpace: 'nowrap',
  },
  gridCardMeta: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between',
    width: '100%',
    fontSize: 11,
    color: 'var(--text-dim)',
    marginTop: 6,
    paddingTop: 6,
    borderTop: '1px solid var(--border-subtle)',
  },
  gridMetaSize: {
    fontWeight: 500,
    color: 'var(--text-muted)',
  },
  gridMetaDate: {
    fontSize: 10.5,
    color: 'var(--text-dim)',
  },
  paginationBar: {
    height: 44,
    borderTop: '1px solid var(--border-color)',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between',
    padding: '0 20px',
    backgroundColor: 'var(--bg-surface)',
    flexShrink: 0,
  },
  pageCountText: {
    fontSize: 12,
    color: 'var(--text-dim)',
  },
  paginationControls: {
    display: 'flex',
    alignItems: 'center',
    gap: 8,
  },
  pageSelect: {
    backgroundColor: 'var(--bg-input)',
    border: '1px solid var(--border-color)',
    color: 'var(--text-main)',
    fontSize: 11.5,
    padding: '3px 6px',
    borderRadius: 'var(--radius-sm)',
    outline: 'none',
  },
  pageNavBtn: {
    background: 'var(--bg-surface)',
    border: '1px solid var(--border-color)',
    borderRadius: 4,
    width: 24,
    height: 24,
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    color: 'var(--text-main)',
    cursor: 'pointer',
  },
  activePageNum: {
    width: 24,
    height: 24,
    borderRadius: 4,
    backgroundColor: 'var(--primary)',
    color: '#ffffff',
    fontSize: 11.5,
    fontWeight: 600,
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
  },
  otherPageNum: {
    width: 24,
    height: 24,
    borderRadius: 4,
    color: 'var(--text-dim)',
    fontSize: 11.5,
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    cursor: 'pointer',
  },

  // ── LIVE SYNC PROGRESS (BOTTOM CENTER) ──────────────────────
  syncProgressContainer: {
    padding: '0 20px 14px 20px',
    backgroundColor: 'transparent',
    flexShrink: 0,
  },
  syncCard: {
    backgroundColor: 'var(--bg-card)',
    border: '1px solid var(--border-color)',
    backdropFilter: 'blur(12px)',
    borderRadius: 'var(--radius-md)',
    padding: '12px 18px',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between',
    boxShadow: 'var(--shadow-md)',
    gap: 20,
  },
  syncIconBox: {
    width: 36,
    height: 36,
    borderRadius: 8,
    backgroundColor: 'var(--primary-glow)',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    flexShrink: 0,
  },
  syncTitle: {
    fontSize: 10,
    fontWeight: 700,
    color: 'var(--text-dim)',
    letterSpacing: '0.05em',
  },
  syncPercent: {
    fontSize: 12,
    fontWeight: 700,
    color: 'var(--primary)',
  },
  syncSubtitleRow: {
    display: 'flex',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
  progressBarBg: {
    width: '100%',
    height: 5,
    borderRadius: 3,
    backgroundColor: 'var(--bg-input)',
    overflow: 'hidden',
    marginTop: 3,
  },
  progressBarFill: {
    height: '100%',
    borderRadius: 3,
    background: 'linear-gradient(90deg, var(--primary) 0%, #a855f7 100%)',
    transition: 'width 0.3s ease',
  },
  syncRightControls: {
    display: 'flex',
    alignItems: 'center',
    gap: 12,
  },
  syncStatsCol: {
    display: 'flex',
    flexDirection: 'column',
    gap: 2,
    textAlign: 'right',
  },
  syncStatText: {
    fontSize: 11,
    color: 'var(--text-dim)',
    fontVariantNumeric: 'tabular-nums',
  },
  syncPauseBtn: {
    padding: '5px 12px',
    borderRadius: 'var(--radius-sm)',
    backgroundColor: 'var(--bg-surface)',
    border: '1px solid var(--border-color)',
    color: 'var(--text-main)',
    fontSize: 12,
    fontWeight: 500,
    cursor: 'pointer',
  },
  syncCancelBtn: {
    padding: '5px 12px',
    borderRadius: 'var(--radius-sm)',
    backgroundColor: 'rgba(239, 68, 68, 0.12)',
    border: '1px solid rgba(239, 68, 68, 0.3)',
    color: '#f87171',
    fontSize: 12,
    fontWeight: 500,
    cursor: 'pointer',
  },

  // ── RIGHT DETAILS INSPECTOR (COLUMN 3) ──────────────────────
  detailsInspector: {
    width: '260px',
    backgroundColor: 'var(--bg-sidebar)',
    borderLeft: '1px solid var(--border-color)',
    display: 'flex',
    flexDirection: 'column',
    overflowY: 'auto',
    flexShrink: 0,
    padding: '16px 14px',
    gap: 18,
  },
  inspectorHeader: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  inspectorTitle: {
    fontSize: 11,
    fontWeight: 700,
    color: 'var(--text-dim)',
    letterSpacing: '0.06em',
    textTransform: 'uppercase',
  },
  previewBox: {
    display: 'flex',
    flexDirection: 'column',
    alignItems: 'center',
    padding: '16px 10px',
    backgroundColor: 'var(--bg-card)',
    border: '1px solid var(--border-color)',
    borderRadius: 'var(--radius-md)',
    textAlign: 'center',
  },
  previewLargeIcon: {
    marginBottom: 8,
  },
  previewName: {
    fontSize: 13.5,
    fontWeight: 600,
    color: 'var(--text-main)',
    margin: '0 0 2px 0',
    maxWidth: '100%',
    overflow: 'hidden',
    textOverflow: 'ellipsis',
    whiteSpace: 'nowrap',
  },
  previewType: {
    fontSize: 11,
    color: 'var(--text-dim)',
  },
  metaList: {
    display: 'flex',
    flexDirection: 'column',
    gap: 8,
    borderBottom: '1px solid var(--border-color)',
    paddingBottom: 14,
  },
  metaRow: {
    display: 'flex',
    justifyContent: 'space-between',
    alignItems: 'flex-start',
    gap: 8,
  },
  metaLabel: {
    fontSize: 11,
    color: 'var(--text-dim)',
    flexShrink: 0,
  },
  metaValue: {
    fontSize: 11.5,
    color: 'var(--text-main)',
    textAlign: 'right',
    wordBreak: 'break-all',
  },
  metaValWithCopy: {
    display: 'flex',
    alignItems: 'center',
    gap: 4,
    maxWidth: '140px',
  },
  metaValPath: {
    fontSize: 11,
    color: 'var(--text-main)',
    textOverflow: 'ellipsis',
    overflow: 'hidden',
    whiteSpace: 'nowrap',
  },
  copyTinyBtn: {
    background: 'transparent',
    border: 'none',
    color: 'var(--text-dim)',
    cursor: 'pointer',
    padding: 1,
    display: 'flex',
    alignItems: 'center',
  },
  inspectorActionsSection: {
    display: 'flex',
    flexDirection: 'column',
    gap: 10,
    borderBottom: '1px solid var(--border-color)',
    paddingBottom: 14,
  },
  inspectorSubTitle: {
    fontSize: 10.5,
    fontWeight: 700,
    color: 'var(--text-dim)',
    letterSpacing: '0.05em',
    textTransform: 'uppercase',
  },
  inspectorBtnList: {
    display: 'flex',
    flexDirection: 'column',
    gap: 4,
  },
  inspectorActionBtn: {
    display: 'flex',
    alignItems: 'center',
    gap: 10,
    padding: '7px 10px',
    borderRadius: 'var(--radius-sm)',
    backgroundColor: 'var(--bg-surface)',
    border: '1px solid var(--border-color)',
    color: 'var(--text-main)',
    fontSize: 12,
    fontWeight: 500,
    cursor: 'pointer',
    textAlign: 'left',
    transition: 'all 0.12s',
  },
  quotaSection: {
    display: 'flex',
    flexDirection: 'column',
    gap: 10,
  },
  quotaBarWrapper: {
    display: 'flex',
    flexDirection: 'column',
    gap: 4,
  },
  quotaProgressBg: {
    width: '100%',
    height: 5,
    borderRadius: 3,
    backgroundColor: 'var(--bg-input)',
    overflow: 'hidden',
  },
  quotaProgressFill: {
    height: '100%',
    borderRadius: 3,
    backgroundColor: 'var(--primary)',
  },
  quotaTextRow: {
    display: 'flex',
    justifyContent: 'space-between',
    fontSize: 11,
    color: 'var(--text-main)',
    fontVariantNumeric: 'tabular-nums',
  },
  manageBucketBtn: {
    width: '100%',
    padding: '7px 0',
    borderRadius: 'var(--radius-sm)',
    backgroundColor: 'var(--bg-surface)',
    border: '1px solid var(--border-color)',
    color: 'var(--text-main)',
    fontSize: 12,
    fontWeight: 500,
    cursor: 'pointer',
    textAlign: 'center',
  },

  // ── MODAL STYLES ────────────────────────────────────────────
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
  modalContent: {
    width: '420px',
    backgroundColor: 'var(--bg-card)',
    border: '1px solid var(--border-color)',
    borderRadius: 'var(--radius-md)',
    padding: 24,
    boxShadow: 'var(--shadow-lg)',
  },
  modalTitle: {
    fontSize: 15,
    fontWeight: 700,
    color: 'var(--text-main)',
    margin: '0 0 4px 0',
  },
  modalSubtitle: {
    fontSize: 12,
    color: 'var(--text-dim)',
    margin: '0 0 16px 0',
  },
  modalInput: {
    width: '100%',
    backgroundColor: 'var(--bg-input)',
    border: '1px solid var(--border-color)',
    color: 'var(--text-main)',
    fontSize: 13,
    padding: '9px 12px',
    borderRadius: 'var(--radius-sm)',
    outline: 'none',
    boxSizing: 'border-box',
    marginBottom: 18,
  },
  modalActionRow: {
    display: 'flex',
    justifyContent: 'flex-end',
    gap: 8,
  },
  modalCancelBtn: {
    padding: '7px 14px',
    backgroundColor: 'var(--bg-surface)',
    border: '1px solid var(--border-color)',
    color: 'var(--text-main)',
    fontSize: 12.5,
    borderRadius: 'var(--radius-sm)',
    cursor: 'pointer',
  },
  modalSubmitBtn: {
    padding: '7px 16px',
    background: 'linear-gradient(135deg, #6366f1 0%, #4f46e5 100%)',
    border: 'none',
    color: '#ffffff',
    fontSize: 12.5,
    fontWeight: 600,
    borderRadius: 'var(--radius-sm)',
    cursor: 'pointer',
  }
};
