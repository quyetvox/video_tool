import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import '../models/project_info.dart';
import '../models/video_file.dart';
import 'python_bridge.dart';

class FileService {
  /// Scan projects folder (default: assets/) and return list of projects with file counts
  static List<ProjectInfo> listProjects(String projectsDir) {
    var targetDir = Directory(projectsDir);
    if (!targetDir.existsSync()) {
      // If rootDir was passed instead of assetsDir, check rootDir/assets
      final alt = Directory(p.join(projectsDir, 'assets'));
      if (alt.existsSync()) {
        targetDir = alt;
      } else {
        return [];
      }
    }

    final projects = <ProjectInfo>[];
    final entries = targetDir.listSync().whereType<Directory>();

    const ignoredNames = {'fonts', 'images', '.DS_Store', '.git', '.venv', '__pycache__'};

    for (final dir in entries) {
      final name = p.basename(dir.path);
      if (name.startsWith('.') || ignoredNames.contains(name)) continue;

      final srcDir = Directory(p.join(dir.path, 'src'));
      final cutDir = Directory(p.join(dir.path, 'cut'));
      final mergeDir = Directory(p.join(dir.path, 'merge'));
      final wsDir = Directory(p.join(dir.path, 'workspace'));
      final outDir = Directory(p.join(dir.path, 'output'));
      final hasConfig = File(p.join(dir.path, 'config.yaml')).existsSync();

      int countFiles(Directory d) {
        if (!d.existsSync()) return 0;
        try {
          return d.listSync().where((f) => !p.basename(f.path).startsWith('.')).length;
        } catch (_) {
          return 0;
        }
      }

      projects.add(ProjectInfo(
        name: name,
        hasConfig: hasConfig,
        srcCount: countFiles(srcDir),
        cutCount: countFiles(cutDir),
        mergeCount: countFiles(mergeDir),
        workspaceCount: countFiles(wsDir),
        outputCount: countFiles(outDir),
      ));
    }

    projects.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return projects;
  }

  /// Create a new project directory structure and copy default config.yaml
  static bool createProject(String projectsDir, String name, {String? rootDir}) {
    final cleanName = name.trim().replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
    if (cleanName.isEmpty) return false;

    var baseDir = Directory(projectsDir);
    if (!baseDir.existsSync()) {
      baseDir.createSync(recursive: true);
    }

    final projDir = Directory(p.join(baseDir.path, cleanName));
    if (projDir.existsSync()) return true;

    try {
      Directory(p.join(projDir.path, 'src')).createSync(recursive: true);
      Directory(p.join(projDir.path, 'cut')).createSync(recursive: true);
      Directory(p.join(projDir.path, 'merge')).createSync(recursive: true);
      Directory(p.join(projDir.path, 'workspace')).createSync(recursive: true);
      Directory(p.join(projDir.path, 'output')).createSync(recursive: true);

      final root = rootDir ?? PythonBridge.resolveRootDir();
      final rootConfig = File(p.join(root, 'config.yaml'));
      final projConfig = File(p.join(projDir.path, 'config.yaml'));
      if (rootConfig.existsSync() && !projConfig.existsSync()) {
        rootConfig.copySync(projConfig.path);
      }
      return true;
    } catch (e) {
      return false;
    }
  }

  /// List all files in project folders (src, cut, merge, output, workspace)
  static Map<String, List<VideoFile>> listProjectVideos(String projectsDir, String projectName) {
    var baseDir = Directory(projectsDir);
    var projDir = Directory(p.join(baseDir.path, projectName));

    if (!projDir.existsSync()) {
      final alt = Directory(p.join(projectsDir, 'assets', projectName));
      if (alt.existsSync()) {
        projDir = alt;
      } else {
        return {
          'srcFiles': [],
          'cutFiles': [],
          'mergeFiles': [],
          'outputFiles': [],
          'workspaceJobs': [],
        };
      }
    }

    List<VideoFile> scanSubDir(String subName, VideoCategory category) {
      final targetDir = Directory(p.join(projDir.path, subName));
      if (!targetDir.existsSync()) return [];

      final results = <VideoFile>[];
      try {
        final list = targetDir.listSync(recursive: true).whereType<File>();
        for (final file in list) {
          final base = p.basename(file.path);
          if (base.startsWith('.') || base == 'douyin-video-links.txt') continue;

          final ext = p.extension(file.path).toLowerCase();
          final isVideo = {'.mp4', '.mkv', '.mov', '.avi', '.flv', '.webm', '.ts', '.m4v'}.contains(ext);
          final isAudio = {'.wav', '.mp3', '.aac', '.m4a', '.flac'}.contains(ext);
          final isSub = {'.srt', '.ass', '.vtt'}.contains(ext);

          if (!isVideo && !isAudio && !isSub && category != VideoCategory.workspace) {
            continue;
          }

          final stat = file.statSync();

          results.add(VideoFile(
            name: base,
            basename: base,
            fullPath: file.path,
            relPath: p.relative(file.path, from: PythonBridge.resolveRootDir()),
            category: category,
            sizeBytes: stat.size,
            mtime: stat.modified.millisecondsSinceEpoch / 1000.0,
            isMedia: isVideo || isAudio,
            isAudio: isAudio,
            isSub: isSub,
          ));
        }
      } catch (_) {}

      results.sort((a, b) => b.mtime.compareTo(a.mtime));
      return results;
    }

    return {
      'srcFiles': scanSubDir('src', VideoCategory.src),
      'cutFiles': scanSubDir('cut', VideoCategory.cut),
      'mergeFiles': scanSubDir('merge', VideoCategory.merge),
      'outputFiles': scanSubDir('output', VideoCategory.output),
      'workspaceJobs': scanSubDir('workspace', VideoCategory.workspace),
    };
  }

  /// Read project config.yaml string
  static String readProjectConfig(String projectsDir, String projectName, {String? rootDir}) {
    var baseDir = Directory(projectsDir);
    var projDir = Directory(p.join(baseDir.path, projectName));
    if (!projDir.existsSync()) {
      projDir = Directory(p.join(projectsDir, 'assets', projectName));
    }

    final projConfig = File(p.join(projDir.path, 'config.yaml'));
    if (projConfig.existsSync()) {
      return projConfig.readAsStringSync();
    }

    final root = rootDir ?? PythonBridge.resolveRootDir();
    final rootConfig = File(p.join(root, 'config.yaml'));
    if (rootConfig.existsSync()) {
      return rootConfig.readAsStringSync();
    }

    return '';
  }

  /// Write project config.yaml string
  static void writeProjectConfig(String projectsDir, String projectName, String yamlContent) {
    var baseDir = Directory(projectsDir);
    var projDir = Directory(p.join(baseDir.path, projectName));
    if (!projDir.existsSync()) {
      projDir = Directory(p.join(projectsDir, 'assets', projectName));
    }
    if (!projDir.existsSync()) {
      projDir.createSync(recursive: true);
    }
    final projConfig = File(p.join(projDir.path, 'config.yaml'));
    projConfig.writeAsStringSync(yamlContent);
  }

  /// Read JSON file safely
  static dynamic readJsonFile(String filePath) {
    final file = File(filePath);
    if (!file.existsSync()) return null;
    try {
      final text = file.readAsStringSync();
      return jsonDecode(text);
    } catch (_) {
      return null;
    }
  }

  /// Write JSON file safely
  static void writeJsonFile(String filePath, dynamic data) {
    final file = File(filePath);
    final parent = file.parent;
    if (!parent.existsSync()) {
      parent.createSync(recursive: true);
    }
    file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(data));
  }

  /// Read plain text file
  static String readTextFile(String filePath) {
    final file = File(filePath);
    if (!file.existsSync()) return '';
    try {
      return file.readAsStringSync();
    } catch (_) {
      return '';
    }
  }

  /// Write plain text file
  static void writeTextFile(String filePath, String content) {
    final file = File(filePath);
    final parent = file.parent;
    if (!parent.existsSync()) {
      parent.createSync(recursive: true);
    }
    file.writeAsStringSync(content);
  }

  /// List files in a specific job workspace
  static List<VideoFile> listWorkspaceJobFiles(String projectsDir, String projectName, String jobId) {
    var baseDir = Directory(projectsDir);
    var jobDir = Directory(p.join(baseDir.path, projectName, 'workspace', jobId));
    if (!jobDir.existsSync()) {
      jobDir = Directory(p.join(projectsDir, 'assets', projectName, 'workspace', jobId));
    }
    if (!jobDir.existsSync()) return [];

    final results = <VideoFile>[];
    try {
      final list = jobDir.listSync(recursive: true).whereType<File>();
      for (final file in list) {
        final base = p.basename(file.path);
        if (base.startsWith('.')) continue;

        final stat = file.statSync();

        results.add(VideoFile(
          name: base,
          basename: base,
          fullPath: file.path,
          relPath: p.relative(file.path, from: PythonBridge.resolveRootDir()),
          category: VideoCategory.workspace,
          sizeBytes: stat.size,
          mtime: stat.modified.millisecondsSinceEpoch / 1000.0,
        ));
      }
    } catch (_) {}

    results.sort((a, b) => a.basename.compareTo(b.basename));
    return results;
  }

  /// Delete a specific step cache file and invoke cascade invalidation via main.py delete-step
  static Future<bool> deleteStepCache(String projectsDirOrRoot, String projectName, String jobId, String stepId) async {
    final result = await PythonBridge.runScript(
      'main.py',
      ['delete-step', '$projectName:$jobId', stepId],
      jobId: 'del_step_${jobId}_$stepId',
    );
    return result.success;
  }

  /// Delete entire workspace job directory
  static bool deleteWorkspaceJob(String projectsDir, String projectName, String jobId) {
    return deleteJobWorkspace(projectsDir, projectName, jobId);
  }

  /// Delete entire workspace job directory
  static bool deleteJobWorkspace(String projectsDir, String projectName, String jobId) {
    var baseDir = Directory(projectsDir);
    var jobDir = Directory(p.join(baseDir.path, projectName, 'workspace', jobId));
    if (!jobDir.existsSync()) {
      jobDir = Directory(p.join(projectsDir, 'assets', projectName, 'workspace', jobId));
    }
    if (jobDir.existsSync()) {
      try {
        jobDir.deleteSync(recursive: true);
        return true;
      } catch (_) {
        return false;
      }
    }
    return false;
  }

  /// Rename a file in project
  static bool renameFile(String fullPath, String newName) => renameVideoFile(fullPath, newName);

  /// Rename a file in project
  static bool renameVideoFile(String fullPath, String newName) {
    final file = File(fullPath);
    if (!file.existsSync()) return false;
    try {
      final ext = p.extension(fullPath);
      final finalName = newName.endsWith(ext) ? newName : '$newName$ext';
      final newPath = p.join(file.parent.path, finalName);
      file.renameSync(newPath);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Delete a file
  static bool deleteFile(String fullPath) => deleteVideoFile(fullPath);

  /// Delete a file
  static bool deleteVideoFile(String fullPath) {
    final file = File(fullPath);
    if (!file.existsSync()) return false;
    try {
      file.deleteSync();
      return true;
    } catch (_) {
      return false;
    }
  }
}
