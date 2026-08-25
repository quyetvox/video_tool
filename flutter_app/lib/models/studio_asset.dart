import 'dart:io';
import 'package:path/path.dart' as p;

enum AssetType {
  music,
  sfx,
  overlay,
}

class StudioAsset {
  final String id;
  final String name;
  final String path;
  final AssetType type;
  final int sizeBytes;
  final DateTime addedAt;
  final Duration? duration;
  final String? thumbnailPath;

  const StudioAsset({
    required this.id,
    required this.name,
    required this.path,
    required this.type,
    required this.sizeBytes,
    required this.addedAt,
    this.duration,
    this.thumbnailPath,
  });

  factory StudioAsset.fromFile(File file, AssetType type) {
    final stat = file.statSync();
    final name = p.basename(file.path);
    final id = '${type.name}_${file.path.hashCode.abs()}';

    return StudioAsset(
      id: id,
      name: name,
      path: file.path,
      type: type,
      sizeBytes: stat.size,
      addedAt: stat.modified,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'path': path,
        'type': type.name,
        'sizeBytes': sizeBytes,
        'addedAt': addedAt.toIso8601String(),
        'durationMs': duration?.inMilliseconds,
        'thumbnailPath': thumbnailPath,
      };

  factory StudioAsset.fromJson(Map<String, dynamic> json) => StudioAsset(
        id: json['id'] as String,
        name: json['name'] as String,
        path: json['path'] as String,
        type: AssetType.values.firstWhere(
          (t) => t.name == json['type'],
          orElse: () => AssetType.overlay,
        ),
        sizeBytes: json['sizeBytes'] as int? ?? 0,
        addedAt: json['addedAt'] != null
            ? DateTime.tryParse(json['addedAt'] as String) ?? DateTime.now()
            : DateTime.now(),
        duration: json['durationMs'] != null
            ? Duration(milliseconds: json['durationMs'] as int)
            : null,
        thumbnailPath: json['thumbnailPath'] as String?,
      );
}
