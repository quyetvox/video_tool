import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/cloud_item.dart';
import 'python_bridge.dart';

class CloudStorageState {
  final String currentPath;
  final Map<String, List<CloudItem>> cache;
  final List<CloudItem> items;
  final CloudItem? selectedItem;
  final Set<String> selectedPaths;
  final bool isConnected;
  final String bucketName;
  final String basePrefix;
  final bool isLoading;
  final String searchQuery;
  final bool isGridView;
  final Map<String, DateTime> lastFetched;

  // Filter criteria
  final String filterType; // 'all' | 'video' | 'audio' | 'subtitle' | 'document' | 'folder'
  final String filterStatus; // 'all' | 'synced' | 'cloud_only' | 'local_only' | 'modified'
  final String filterSize; // 'all' | '<10mb' | '10mb-100mb' | '100mb-1gb' | '>1gb'
  final String filterDate; // 'all' | 'today' | '7days' | '30days'

  const CloudStorageState({
    this.currentPath = '',
    this.cache = const {},
    this.items = const [],
    this.selectedItem,
    this.selectedPaths = const {},
    this.isConnected = false,
    this.bucketName = 'service-qa-beta',
    this.basePrefix = 'video-tiktok-volumn',
    this.isLoading = false,
    this.searchQuery = '',
    this.isGridView = false,
    this.lastFetched = const {},
    this.filterType = 'all',
    this.filterStatus = 'all',
    this.filterSize = 'all',
    this.filterDate = 'all',
  });

  List<CloudItem> get filteredItems {
    return items.where((it) {
      // 1. Search Query
      if (searchQuery.trim().isNotEmpty) {
        if (!it.name.toLowerCase().contains(searchQuery.toLowerCase().trim())) {
          return false;
        }
      }

      // 2. Type Filter
      if (filterType != 'all') {
        if (filterType == 'folder' && !it.isFolder) return false;
        if (filterType == 'video' && it.type != 'video') return false;
        if (filterType == 'audio' && it.type != 'audio') return false;
        if (filterType == 'subtitle' && it.type != 'subtitle') return false;
        if (filterType == 'document' && !['file', 'json', 'txt', 'yaml', 'md'].contains(it.ext.toLowerCase()) && it.type != 'file') {
          return false;
        }
      }

      // 3. Status Filter
      if (filterStatus != 'all') {
        if (it.status != filterStatus) return false;
      }

      // 4. Size Filter
      if (filterSize != 'all' && !it.isFolder) {
        final mb = it.sizeBytes / (1024.0 * 1024.0);
        if (filterSize == '<10mb' && mb >= 10.0) return false;
        if (filterSize == '10mb-100mb' && (mb < 10.0 || mb > 100.0)) return false;
        if (filterSize == '100mb-1gb' && (mb < 100.0 || mb > 1024.0)) return false;
        if (filterSize == '>1gb' && mb <= 1024.0) return false;
      }

      return true;
    }).toList();
  }

  CloudStorageState copyWith({
    String? currentPath,
    Map<String, List<CloudItem>>? cache,
    List<CloudItem>? items,
    CloudItem? Function()? selectedItem,
    Set<String>? selectedPaths,
    bool? isConnected,
    String? bucketName,
    String? basePrefix,
    bool? isLoading,
    String? searchQuery,
    bool? isGridView,
    Map<String, DateTime>? lastFetched,
    String? filterType,
    String? filterStatus,
    String? filterSize,
    String? filterDate,
  }) {
    return CloudStorageState(
      currentPath: currentPath ?? this.currentPath,
      cache: cache ?? this.cache,
      items: items ?? this.items,
      selectedItem: selectedItem != null ? selectedItem() : this.selectedItem,
      selectedPaths: selectedPaths ?? this.selectedPaths,
      isConnected: isConnected ?? this.isConnected,
      bucketName: bucketName ?? this.bucketName,
      basePrefix: basePrefix ?? this.basePrefix,
      isLoading: isLoading ?? this.isLoading,
      searchQuery: searchQuery ?? this.searchQuery,
      isGridView: isGridView ?? this.isGridView,
      lastFetched: lastFetched ?? this.lastFetched,
      filterType: filterType ?? this.filterType,
      filterStatus: filterStatus ?? this.filterStatus,
      filterSize: filterSize ?? this.filterSize,
      filterDate: filterDate ?? this.filterDate,
    );
  }
}

class CloudStorageNotifier extends StateNotifier<CloudStorageState> {
  CloudStorageNotifier() : super(const CloudStorageState()) {
    loadBrowse('', forceRefresh: false);
  }

  /// Loads hierarchical browse data for [path].
  /// If data already exists in memory [cache] and [forceRefresh] is false,
  /// returns instantly in 0ms without executing Python or network requests.
  Future<void> loadBrowse(String path, {bool forceRefresh = false}) async {
    final cleanPath = path.trim().replaceAll(r'\', '/');

    // 1. Check in-memory cache hit
    if (!forceRefresh && state.cache.containsKey(cleanPath)) {
      final cachedItems = state.cache[cleanPath]!;
      state = state.copyWith(
        currentPath: cleanPath,
        items: cachedItems,
        selectedItem: () => cachedItems.isNotEmpty ? cachedItems.first : null,
        selectedPaths: {},
        isLoading: false,
      );
      return;
    }

    // 2. Cache miss or explicit refresh -> Query GCS via Python
    state = state.copyWith(
      currentPath: cleanPath,
      isLoading: true,
    );

    final res = await PythonBridge.runCode('''
import json, sys
from lib.utils.storage_manager import StorageManager

path_arg = sys.argv[1] if len(sys.argv) > 1 else ""
mgr = StorageManager()
data = mgr.browse(path_arg)
print(json.dumps(data, ensure_ascii=False))
''', extraArgs: [cleanPath]);

    if (res.exitCode == 0) {
      try {
        final data = jsonDecode(res.stdout.toString().trim());
        final isConn = data['connected'] == true;
        final rawItems = data['items'] as List<dynamic>? ?? [];
        final parsedItems = rawItems.map((it) => CloudItem.fromJson(it as Map<String, dynamic>)).toList();

        final updatedCache = Map<String, List<CloudItem>>.from(state.cache);
        updatedCache[cleanPath] = parsedItems;

        final updatedTimestamps = Map<String, DateTime>.from(state.lastFetched);
        updatedTimestamps[cleanPath] = DateTime.now();

        state = state.copyWith(
          currentPath: cleanPath,
          cache: updatedCache,
          items: parsedItems,
          selectedItem: () => parsedItems.isNotEmpty ? parsedItems.first : null,
          selectedPaths: {},
          isConnected: isConn,
          bucketName: data['bucket'] ?? state.bucketName,
          basePrefix: data['basePrefix'] ?? state.basePrefix,
          isLoading: false,
          lastFetched: updatedTimestamps,
        );
      } catch (e) {
        state = state.copyWith(isLoading: false);
      }
    } else {
      state = state.copyWith(isLoading: false);
    }
  }

  void navigateInto(CloudItem item) {
    if (item.isFolder) {
      loadBrowse(item.path, forceRefresh: false);
    }
  }

  void navigateUp() {
    if (state.currentPath.isEmpty) return;
    final parts = state.currentPath.split('/');
    if (parts.length <= 1) {
      loadBrowse('', forceRefresh: false);
    } else {
      parts.removeLast();
      loadBrowse(parts.join('/'), forceRefresh: false);
    }
  }

  /// Explicit user refresh via [🔄 Làm Mới] button
  Future<void> refreshCurrent() async {
    await loadBrowse(state.currentPath, forceRefresh: true);
  }

  /// Invalidates cache for a specific path and its parent (e.g. after sync-down, sync-up, offload, delete)
  Future<void> invalidatePath(String path) async {
    final cleanPath = path.trim().replaceAll(r'\', '/');
    final updatedCache = Map<String, List<CloudItem>>.from(state.cache);
    updatedCache.remove(cleanPath);

    // Also remove parent folder cache if any
    if (cleanPath.contains('/')) {
      final parts = cleanPath.split('/');
      parts.removeLast();
      updatedCache.remove(parts.join('/'));
    }
    updatedCache.remove(''); // Invalidate root folder counts as well

    state = state.copyWith(cache: updatedCache);
    await loadBrowse(state.currentPath, forceRefresh: true);
  }

  /// Invalidates entire cache (e.g. when changing gcs-key.json or bucket config)
  Future<void> invalidateAll() async {
    state = state.copyWith(
      cache: {},
      lastFetched: {},
      selectedPaths: {},
    );
    await loadBrowse('', forceRefresh: true);
  }

  void selectItem(CloudItem? item) {
    state = state.copyWith(selectedItem: () => item);
  }

  void toggleSelectPath(String path) {
    final current = Set<String>.from(state.selectedPaths);
    if (current.contains(path)) {
      current.remove(path);
    } else {
      current.add(path);
    }
    state = state.copyWith(selectedPaths: current);
  }

  void selectAllPaths(bool select) {
    if (select) {
      final all = state.filteredItems.map((e) => e.path).toSet();
      state = state.copyWith(selectedPaths: all);
    } else {
      state = state.copyWith(selectedPaths: {});
    }
  }

  void setSearchQuery(String query) {
    state = state.copyWith(searchQuery: query);
  }

  void toggleViewMode() {
    state = state.copyWith(isGridView: !state.isGridView);
  }

  void setFilterType(String val) => state = state.copyWith(filterType: val);
  void setFilterStatus(String val) => state = state.copyWith(filterStatus: val);
  void setFilterSize(String val) => state = state.copyWith(filterSize: val);
  void setFilterDate(String val) => state = state.copyWith(filterDate: val);

  void resetFilters() {
    state = state.copyWith(
      filterType: 'all',
      filterStatus: 'all',
      filterSize: 'all',
      filterDate: 'all',
      searchQuery: '',
    );
  }
}
