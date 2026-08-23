enum VideoCategory {
  src,
  cut,
  merge,
  output,
  workspace,
  cloudOnly,
}

class VideoFile {
  final String name;
  final String basename;
  final String relPath;
  final String fullPath;
  final int sizeBytes;
  final double mtime;
  final bool isMedia;
  final bool isAudio;
  final bool isImage;
  final bool isJson;
  final bool isSub;
  final bool isText;
  final VideoCategory category;
  final bool isCloudOnly;
  final bool isSynced;
  final String? cloudUrl;

  const VideoFile({
    required this.name,
    required this.basename,
    required this.relPath,
    required this.fullPath,
    required this.sizeBytes,
    required this.mtime,
    this.isMedia = true,
    this.isAudio = false,
    this.isImage = false,
    this.isJson = false,
    this.isSub = false,
    this.isText = false,
    required this.category,
    this.isCloudOnly = false,
    this.isSynced = false,
    this.cloudUrl,
  });

  String get stem {
    final clean = basename.replaceAll(RegExp(r'\.[^/.]+$'), '');
    return clean.replaceAll(RegExp(r'_vi$'), '');
  }

  String get jobId => 'job_$stem';

  factory VideoFile.fromJson(Map<String, dynamic> json, {String rootDir = ''}) {
    final rel = json['relPath'] as String? ?? json['name'] as String? ?? '';
    final base = json['basename'] as String? ?? (rel.split('/').isNotEmpty ? rel.split('/').last : rel);
    
    VideoCategory cat = VideoCategory.src;
    if (rel.contains('/src/') || rel.startsWith('src/')) {
      cat = VideoCategory.src;
    } else if (rel.contains('/cut/') || rel.startsWith('cut/')) {
      cat = VideoCategory.cut;
    } else if (rel.contains('/merge/') || rel.startsWith('merge/')) {
      cat = VideoCategory.merge;
    } else if (rel.contains('/output/') || rel.startsWith('output/')) {
      cat = VideoCategory.output;
    } else if (rel.contains('/workspace/') || rel.startsWith('workspace/')) {
      cat = VideoCategory.workspace;
    }

    return VideoFile(
      name: json['name'] as String? ?? base,
      basename: base,
      relPath: rel,
      fullPath: json['fullPath'] as String? ?? (rootDir.isNotEmpty ? '$rootDir/$rel' : rel),
      sizeBytes: json['sizeBytes'] as int? ?? (json['size'] as int? ?? 0),
      mtime: (json['mtime'] as num?)?.toDouble() ?? 0.0,
      isMedia: json['isMedia'] as bool? ?? true,
      isAudio: json['isAudio'] as bool? ?? false,
      isImage: json['isImage'] as bool? ?? false,
      isJson: json['isJson'] as bool? ?? false,
      isSub: json['isSub'] as bool? ?? false,
      isText: json['isText'] as bool? ?? false,
      category: cat,
      isCloudOnly: json['isCloudOnly'] as bool? ?? false,
      isSynced: json['isSynced'] as bool? ?? false,
      cloudUrl: json['cloudUrl'] as String?,
    );
  }
}
