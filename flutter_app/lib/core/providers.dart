import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/app_config.dart';
import '../models/job_info.dart';
import '../models/models_status.dart';
import '../models/project_info.dart';
import '../models/video_file.dart';
import 'config_notifier.dart';
import 'file_service.dart';
import 'python_bridge.dart';
import 'setup_service.dart';
import 'cloud_storage_state.dart';
import 'engine_update_service.dart';
import 'font_discovery_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/studio_asset.dart';
import 'asset_library_service.dart';

// ── Root Directory ───────────────────────────────────────────────
final projectRootProvider = StateProvider<String>((ref) {
  return PythonBridge.resolveRootDir();
});

// ── Native Engine vs Python Legacy Toggle Provider ───────────────
final useNativeEngineProvider = StateNotifierProvider<UseNativeEngineNotifier, bool>((ref) {
  return UseNativeEngineNotifier();
});

class UseNativeEngineNotifier extends StateNotifier<bool> {
  UseNativeEngineNotifier() : super(true) {
    _loadSaved();
  }

  Future<void> _loadSaved() async {
    final saved = await SetupService.getUseNativeEngine();
    state = saved;
  }

  Future<void> setUseNative(bool value) async {
    await SetupService.setUseNativeEngine(value);
    state = value;
  }
}

// ── Projects Parent Directory (resources/ or custom) ────────────────
final projectsDirProvider = StateNotifierProvider<ProjectsDirNotifier, String>((ref) {
  final rootDir = ref.watch(projectRootProvider);
  return ProjectsDirNotifier(rootDir);
});

class ProjectsDirNotifier extends StateNotifier<String> {
  ProjectsDirNotifier(String rootDir) : super(
    Directory('$rootDir/resources').existsSync() ? '$rootDir/resources' : '$rootDir/assets'
  ) {
    _loadSaved();
  }

  Future<void> _loadSaved() async {
    final saved = await SetupService.getProjectsDir();
    if (saved.isNotEmpty) {
      state = saved;
    }
  }

  Future<void> setDir(String newDir) async {
    await SetupService.setProjectsDir(newDir);
    state = newDir;
  }
}

// ── Models Directory ─────────────────────────────────────────────
final modelsDirProvider = StateNotifierProvider<ModelsDirNotifier, String>((ref) {
  final rootDir = ref.watch(projectRootProvider);
  return ModelsDirNotifier(rootDir);
});

class ModelsDirNotifier extends StateNotifier<String> {
  ModelsDirNotifier(String rootDir) : super('$rootDir/models') {
    _loadSaved();
  }

  Future<void> _loadSaved() async {
    final saved = await SetupService.getModelsDir();
    if (saved.isNotEmpty) {
      state = saved;
    }
  }

  Future<void> setDir(String newDir) async {
    await SetupService.setModelsDir(newDir);
    state = newDir;
  }
}

// ── Projects ─────────────────────────────────────────────────────
final projectsProvider = FutureProvider<List<ProjectInfo>>((ref) async {
  final projectsDir = ref.watch(projectsDirProvider);
  final list = FileService.listProjects(projectsDir);

  // Auto-select first project if activeProject is null
  final currentActive = ref.read(activeProjectProvider);
  if (currentActive == null && list.isNotEmpty) {
    Future.microtask(() {
      ref.read(activeProjectProvider.notifier).state = list.first.name;
    });
  }

  return list;
});

final activeProjectProvider = StateProvider<String?>((ref) => null);

// ── Active Navigation Tab ────────────────────────────────────────
final activeNavTabProvider = StateProvider<int>((ref) => 0);

// ── Videos for Active Project ────────────────────────────────────
final projectVideosProvider = FutureProvider<Map<String, List<VideoFile>>>((ref) async {
  final projectsDir = ref.watch(projectsDirProvider);
  final activeProj = ref.watch(activeProjectProvider);
  if (activeProj == null || activeProj.isEmpty) {
    return {
      'srcFiles': [],
      'cutFiles': [],
      'mergeFiles': [],
      'outputFiles': [],
      'workspaceJobs': [],
    };
  }
  return FileService.listProjectVideos(projectsDir, activeProj);
});

final projectVideosFamilyProvider = FutureProvider.family<Map<String, List<VideoFile>>, String>((ref, projectName) async {
  final projectsDir = ref.watch(projectsDirProvider);
  return FileService.listProjectVideos(projectsDir, projectName);
});

final selectedVideoProvider = StateProvider<VideoFile?>((ref) => null);

// ── Config State (Single Source of Truth) ────────────────────────
final configProvider = StateNotifierProvider<ConfigNotifier, AppConfig>((ref) {
  final projectsDir = ref.watch(projectsDirProvider);
  final activeProj = ref.watch(activeProjectProvider);
  return ConfigNotifier(project: activeProj, rootDir: projectsDir);
});

// ── Jobs & Running Paths ─────────────────────────────────────────
final activeJobsProvider = StateProvider<Map<String, JobInfo>>((ref) => {});
final runningPathsProvider = StateProvider<Set<String>>((ref) => {});

// ── Cloud Storage State ──────────────────────────────────────────
final cloudStorageProvider = StateNotifierProvider<CloudStorageNotifier, CloudStorageState>((ref) {
  return CloudStorageNotifier();
});


// ── Log Streams & Log Buffer ─────────────────────────────────────
final globalLogsStreamProvider = StreamProvider<LogEntry>((ref) {
  return PythonBridge.globalLogStream;
});

final jobLogsStreamProvider = StreamProvider.family<LogEntry, String>((ref, jobId) {
  return PythonBridge.streamLogs(jobId);
});

final logBufferProvider = StateNotifierProvider<LogBufferNotifier, List<LogEntry>>((ref) {
  return LogBufferNotifier();
});

class LogBufferNotifier extends StateNotifier<List<LogEntry>> {
  LogBufferNotifier() : super([]) {
    PythonBridge.globalLogStream.listen((entry) {
      state = [...state.takeLast(999), entry];
    });
  }

  void clear() {
    state = [];
  }
}

extension _TakeLast<T> on List<T> {
  Iterable<T> takeLast(int n) {
    if (length <= n) return this;
    return skip(length - n);
  }
}

// ── Models Setup ─────────────────────────────────────────────────
final modelsStatusProvider = FutureProvider<ModelsStatus>((ref) async {
  ref.watch(modelsDirProvider);
  return SetupService.checkModels();
});

// ── Theme Mode ───────────────────────────────────────────────────
class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  static const _prefKey = 'app_theme_mode';

  ThemeModeNotifier() : super(ThemeMode.dark) {
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final modeStr = prefs.getString(_prefKey);
      if (modeStr == 'light') {
        state = ThemeMode.light;
      } else if (modeStr == 'dark') {
        state = ThemeMode.dark;
      }
    } catch (_) {}
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = mode;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, mode == ThemeMode.light ? 'light' : 'dark');
    } catch (_) {}
  }

  Future<void> toggle() async {
    final next = state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    await setThemeMode(next);
  }
}

final appThemeModeProvider = StateNotifierProvider<ThemeModeNotifier, ThemeMode>((ref) => ThemeModeNotifier());
final themeModeProvider = appThemeModeProvider;

// ── Visual Gizmo Overlay State ───────────────────────────────────
enum FrameLayerType {
  inpaint,
  primarySub,
  secondarySub,
  watermark,
}

final isGizmoActiveProvider = StateProvider<bool>((ref) => false);
final activeGizmoLayerProvider = StateProvider<FrameLayerType>((ref) => FrameLayerType.inpaint);

// ── Active Native Engine Info & Version Provider ─────────────────
final activeEngineRefreshProvider = StateProvider<int>((ref) => 0);

final activeEngineInfoProvider = FutureProvider.autoDispose<ActiveEngineInfo>((ref) async {
  ref.watch(activeEngineRefreshProvider);
  return EngineUpdateService.getActiveEngineInfo();
});

// ── Dynamic Font Discovery Provider ──────────────────────────────
final availableFontsProvider = Provider<List<FontOption>>((ref) {
  final config = ref.watch(configProvider);
  return FontDiscoveryService.getAvailableFonts(fontsDir: config.fontsDir);
});

// ── Assets Library Provider (Music, SFX, Overlays) ───────────────
final assetsRefreshProvider = StateProvider<int>((ref) => 0);

final assetsLibraryProvider = FutureProvider.autoDispose<List<StudioAsset>>((ref) async {
  ref.watch(assetsRefreshProvider);
  final projectsDir = ref.watch(projectsDirProvider);
  return AssetLibraryService.scanAll(projectsDir);
});

