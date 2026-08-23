class CloudItem {
  final String id;
  final String name;
  final String path;
  final String type; // 'folder' | 'video' | 'file' | 'image' | 'audio' | 'json'
  final String ext;
  final bool isFolder;
  final int sizeBytes;
  final String sizeStr;
  final int itemCount;
  final String modifiedStr;
  final String gcsUri;
  final String status; // 'synced' | 'cloud_only' | 'local_only' | 'modified'
  final String storageClass;

  const CloudItem({
    required this.id,
    required this.name,
    required this.path,
    required this.type,
    this.ext = '',
    required this.isFolder,
    this.sizeBytes = 0,
    required this.sizeStr,
    this.itemCount = 0,
    required this.modifiedStr,
    this.gcsUri = '',
    this.status = 'cloud_only',
    this.storageClass = 'STANDARD',
  });

  bool get isSynced => status == 'synced';
  bool get isLocalOnly => status == 'local_only';
  bool get isCloudOnly => status == 'cloud_only';
  bool get isModified => status == 'modified';
  bool get isVideo => type == 'video' || ext.toUpperCase() == 'MP4' || ext.toUpperCase() == 'MKV';

  factory CloudItem.fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String? ?? (json['is_dir'] == true || json['isFolder'] == true ? 'folder' : 'file');
    final isDir = type == 'folder' || json['is_dir'] == true || json['isFolder'] == true;
    final size = (json['size_bytes'] as num?)?.toInt() ?? (json['size'] as num?)?.toInt() ?? 0;
    final count = (json['itemsCount'] as num?)?.toInt() ?? (json['item_count'] as num?)?.toInt() ?? (json['count'] as num?)?.toInt() ?? 0;
    final name = json['name'] as String? ?? '';
    final path = json['path'] as String? ?? name;
    final mod = json['modified_str'] as String? ?? json['modified'] as String? ?? 'Chưa rõ';
    final gcs = json['gcsUri'] as String? ?? json['fullPath'] as String? ?? '';
    final status = json['status'] as String? ?? 'cloud_only';
    final ext = json['ext'] as String? ?? '';

    String sizeDisplay = '';
    if (isDir) {
      sizeDisplay = '$count mục';
    } else {
      if (size < 1024 * 1024) {
        sizeDisplay = '${(size / 1024.0).toStringAsFixed(1)} KB';
      } else if (size < 1024 * 1024 * 1024) {
        sizeDisplay = '${(size / (1024.0 * 1024.0)).toStringAsFixed(1)} MB';
      } else {
        sizeDisplay = '${(size / (1024.0 * 1024.0 * 1024.0)).toStringAsFixed(2)} GB';
      }
    }

    return CloudItem(
      id: json['id'] as String? ?? path,
      name: name,
      path: path,
      type: type,
      ext: ext,
      isFolder: isDir,
      sizeBytes: size,
      sizeStr: sizeDisplay,
      itemCount: count,
      modifiedStr: mod,
      gcsUri: gcs,
      status: status,
      storageClass: json['storageClass'] as String? ?? 'STANDARD',
    );
  }
}
