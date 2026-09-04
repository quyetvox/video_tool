import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

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
  Map<String, dynamic> loadConfig([Map<String, dynamic>? overrides]) {
    Map<String, dynamic> config = {};
    if (configPath.existsSync()) {
      final doc = loadYaml(configPath.readAsStringSync());
      if (doc is Map) {
        config = Map<String, dynamic>.from(doc);
      }
    } else if (rootConfigPath.existsSync()) {
      final doc = loadYaml(rootConfigPath.readAsStringSync());
      if (doc is Map) {
        config = Map<String, dynamic>.from(doc);
      }
    }

    if (overrides != null && overrides.isNotEmpty) {
      config.addAll(overrides);
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
      final hasPyEngine = Directory(p.join(checkDir.path, 'py_engine')).existsSync();

      if (hasResources && (hasConfig || hasPyEngine)) {
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
    final rootDir = (rootDirOverride ?? findRootDir(targetPath)).absolute;
    final resolvedTargetPath = p.isAbsolute(targetPath) ? targetPath : p.normalize(p.join(rootDir.path, targetPath));
    final isFile = File(resolvedTargetPath).existsSync() || p.extension(resolvedTargetPath).isNotEmpty;
    final target = isFile ? File(resolvedTargetPath).parent : Directory(resolvedTargetPath);

    String projectName;
    Directory projectDir;

    // Hierarchy Traversal: Search upwards up to 8 levels for project directory
    Directory? foundProjectDir;
    String? foundProjectName;

    Directory curr = target;
    for (int i = 0; i < 8; i++) {
      final hasConfig = File(p.join(curr.path, 'config.yaml')).existsSync();
      final hasSrc = Directory(p.join(curr.path, 'src')).existsSync();
      final hasWorkspace = Directory(p.join(curr.path, 'workspace')).existsSync();
      final hasOutput = Directory(p.join(curr.path, 'output')).existsSync();
      final dirName = p.basename(curr.path);

      if (curr.path == rootDir.path || dirName == 'resources' || dirName == 'assets') {
        final parent = curr.parent;
        if (parent.path == curr.path) break;
        curr = parent;
        continue;
      }

      if (hasConfig ||
          ((hasSrc || hasWorkspace || hasOutput) &&
              dirName != 'src' &&
              dirName != 'workspace' &&
              dirName != 'output' &&
              dirName != 'cut' &&
              dirName != 'merge')) {
        foundProjectDir = curr;
        foundProjectName = dirName;
        break;
      }

      final parent = curr.parent;
      if (parent.path == curr.path) break;
      curr = parent;
    }

    if (foundProjectDir != null && foundProjectName != null) {
      projectDir = foundProjectDir;
      projectName = foundProjectName;
    } else {
      final dname = p.basename(target.path);
      if (dname == 'src' || dname == 'workspace' || dname == 'output' || dname == 'cut' || dname == 'merge') {
        projectDir = target.parent;
        projectName = p.basename(projectDir.path);
      } else {
        projectDir = target;
        projectName = dname;
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
