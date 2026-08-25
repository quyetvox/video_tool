import 'dart:io';
import 'package:path/path.dart' as p;
import 'config_adapter.dart';

class ProjectPaths {
  final String projectName;
  final Directory projectDir;
  final Directory srcDir;
  final Directory cutDir;
  final Directory mergeDir;
  final Directory workspaceDir;
  final Directory outputDir;
  final File configPath;
  final File rootConfigPath;

  const ProjectPaths({
    required this.projectName,
    required this.projectDir,
    required this.srcDir,
    required this.cutDir,
    required this.mergeDir,
    required this.workspaceDir,
    required this.outputDir,
    required this.configPath,
    required this.rootConfigPath,
  });

  /// Loads configuration merged with root config.yaml fallback
  ConfigDict loadConfig([Map<String, dynamic>? overrides]) {
    ConfigDict config;
    if (configPath.existsSync()) {
      config = ConfigDict.fromYamlFile(configPath);
    } else if (rootConfigPath.existsSync()) {
      config = ConfigDict.fromYamlFile(rootConfigPath);
    } else {
      config = ConfigDict(<String, dynamic>{});
    }

    if (overrides != null && overrides.isNotEmpty) {
      config.deepMerge(overrides);
    }

    // Set standard runtime path overrides
    config['workspace_dir'] = workspaceDir.path;
    config['output_dir'] = outputDir.path;
    config['cut_dir'] = cutDir.path;
    config['merge_dir'] = mergeDir.path;

    return config;
  }
}

class ProjectManager {
  /// Robust root directory finder that works in macOS GUI sandboxes, CLI, and dev environments.
  static Directory findRootDir([String? startPath]) {
    Directory? curr;
    if (startPath != null && startPath.isNotEmpty) {
      final f = File(startPath);
      curr = f.existsSync() ? f.parent.absolute : Directory(startPath).absolute;
    } else {
      final envRoot = Platform.environment['SUB_VIDEO_ROOT'];
      if (envRoot != null && Directory(envRoot).existsSync()) {
        return Directory(envRoot).absolute;
      }
      curr = Directory.current.absolute;
    }

    // 1. Walk upwards looking for repository markers
    Directory checkDir = curr;
    for (int i = 0; i < 10; i++) {
      final hasResources = Directory(p.join(checkDir.path, 'resources')).existsSync() ||
          Directory(p.join(checkDir.path, 'assets')).existsSync();
      final hasConfig = File(p.join(checkDir.path, 'config.yaml')).existsSync();
      final hasPubspec = File(p.join(checkDir.path, 'pubspec.yaml')).existsSync();
      final hasVideoEngine = Directory(p.join(checkDir.path, 'video_engine')).existsSync();

      if (hasResources && (hasConfig || hasPubspec || hasVideoEngine)) {
        return checkDir;
      }

      final parent = checkDir.parent;
      if (parent.path == checkDir.path) break;
      checkDir = parent;
    }

    // 2. Standard Sub-Video workspace location fallback
    final standardHome = Platform.environment['HOME'];
    if (standardHome != null) {
      final standardWorkspace = Directory(p.join(standardHome, 'Documents', 'projects', 'video', 'Sub-Video'));
      if (standardWorkspace.existsSync()) {
        return standardWorkspace;
      }
    }

    return Directory.current.absolute;
  }

  /// Resolves all paths for a project given a project directory or path inside the project.
  static ProjectPaths resolveProjectPaths(String targetPath, {Directory? rootDirOverride}) {
    final rootDir = rootDirOverride ?? findRootDir(targetPath);
    final target = File(targetPath).existsSync() ? File(targetPath).parent : Directory(targetPath);

    String projectName;
    Directory projectDir;

    if (target.path.contains('/resources/') || target.path.contains('\\resources\\')) {
      final parts = p.split(p.normalize(target.absolute.path));
      final resIndex = parts.lastIndexOf('resources');
      if (resIndex != -1 && resIndex + 1 < parts.length) {
        projectName = parts[resIndex + 1];
        projectDir = Directory(p.join(rootDir.path, 'resources', projectName));
      } else {
        projectName = p.basename(target.path);
        projectDir = target;
      }
    } else if (target.path.contains('/assets/') || target.path.contains('\\assets\\')) {
      final parts = p.split(p.normalize(target.absolute.path));
      final assetsIndex = parts.lastIndexOf('assets');
      if (assetsIndex != -1 && assetsIndex + 1 < parts.length) {
        projectName = parts[assetsIndex + 1];
        projectDir = Directory(p.join(rootDir.path, 'resources', projectName)).existsSync()
            ? Directory(p.join(rootDir.path, 'resources', projectName))
            : Directory(p.join(rootDir.path, 'assets', projectName));
      } else {
        projectName = p.basename(target.path);
        projectDir = target;
      }
    } else if (p.basename(target.parent.path) == 'resources' || p.basename(target.parent.path) == 'assets') {
      projectName = p.basename(target.path);
      projectDir = target;
    } else {
      projectName = p.basename(target.path);
      final resCandidate = Directory(p.join(rootDir.path, 'resources', projectName));
      final assetCandidate = Directory(p.join(rootDir.path, 'assets', projectName));
      if (resCandidate.existsSync()) {
        projectDir = resCandidate;
      } else if (assetCandidate.existsSync()) {
        projectDir = assetCandidate;
      } else {
        projectDir = target;
      }
    }

    final defaultRootConfig = File(p.join(rootDir.path, 'config.yaml'));
    final srcDir = Directory(p.join(projectDir.path, 'src'));
    final cutDir = Directory(p.join(projectDir.path, 'cut'));
    final mergeDir = Directory(p.join(projectDir.path, 'merge'));
    final workspaceDir = Directory(p.join(projectDir.path, 'workspace'));
    final outputDir = Directory(p.join(projectDir.path, 'output'));
    final configPath = File(p.join(projectDir.path, 'config.yaml'));

    srcDir.createSync(recursive: true);
    cutDir.createSync(recursive: true);
    mergeDir.createSync(recursive: true);
    workspaceDir.createSync(recursive: true);
    outputDir.createSync(recursive: true);

    // Copy default root config if project config does not exist
    if (!configPath.existsSync() && defaultRootConfig.existsSync()) {
      defaultRootConfig.copySync(configPath.path);
    }

    return ProjectPaths(
      projectName: projectName,
      projectDir: projectDir,
      srcDir: srcDir,
      cutDir: cutDir,
      mergeDir: mergeDir,
      workspaceDir: workspaceDir,
      outputDir: outputDir,
      configPath: configPath,
      rootConfigPath: defaultRootConfig,
    );
  }

  /// Extracts the base stem of a video, stripping common output suffixes like _vi, _narrated, _translated.
  static String extractCleanStem(String videoPath) {
    var stem = p.basenameWithoutExtension(videoPath);
    stem = stem.replaceAll(RegExp(r'(_vi|_narrated|_translated|_trans|_sub|_voice)$', caseSensitive: false), '');
    return stem;
  }

  /// Generates a clean, deterministic job ID based on the video filename.
  /// Example: 'video_001.mp4' -> 'job_video_001', 'output/video_001_vi.mp4' -> 'job_video_001'
  static String getJobId(String videoPath) {
    final stem = extractCleanStem(videoPath);
    final sanitized = stem.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
    return 'job_$sanitized';
  }

  /// Resolves the true source video file from either src/ or output/ paths.
  static File resolveSourceVideo(String videoPath, {Directory? projectDir}) {
    final file = File(videoPath);
    if (!file.existsSync()) return file;

    final parentDir = file.parent.path;
    final isOutput = parentDir.endsWith('/output') || parentDir.endsWith('\\output') || p.basename(parentDir) == 'output';

    if (isOutput) {
      final cleanStem = extractCleanStem(videoPath);
      final proj = projectDir ?? file.parent.parent;
      final srcDir = Directory(p.join(proj.path, 'src'));
      if (srcDir.existsSync()) {
        final supportedExtensions = ['.mp4', '.mov', '.mkv', '.avi', '.webm', '.flv', '.ts'];
        for (final ext in supportedExtensions) {
          final candidate = File(p.join(srcDir.path, '$cleanStem$ext'));
          if (candidate.existsSync()) {
            return candidate;
          }
        }
      }
    }

    return file;
  }
}
