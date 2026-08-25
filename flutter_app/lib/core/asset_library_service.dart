import 'dart:io';
import 'package:path/path.dart' as p;
import '../models/studio_asset.dart';

class AssetLibraryService {
  static const String assetsFolderName = '_assets';

  static String getAssetsRoot(String resourcesDir) {
    return p.join(resourcesDir, assetsFolderName);
  }

  static String getCategoryDir(String resourcesDir, AssetType type) {
    String sub;
    switch (type) {
      case AssetType.music:
        sub = 'music';
        break;
      case AssetType.sfx:
        sub = 'sfx';
        break;
      case AssetType.overlay:
        sub = 'overlays';
        break;
    }
    return p.join(getAssetsRoot(resourcesDir), sub);
  }

  static Future<void> ensureDirsExist(String resourcesDir) async {
    for (final type in AssetType.values) {
      final dir = Directory(getCategoryDir(resourcesDir, type));
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
    }
  }

  static Future<List<StudioAsset>> scanAll(String resourcesDir) async {
    await ensureDirsExist(resourcesDir);
    final results = <StudioAsset>[];

    for (final type in AssetType.values) {
      final dir = Directory(getCategoryDir(resourcesDir, type));
      if (await dir.exists()) {
        final list = dir.listSync();
        for (final entity in list) {
          if (entity is File && !p.basename(entity.path).startsWith('.')) {
            try {
              results.add(StudioAsset.fromFile(entity, type));
            } catch (_) {}
          }
        }
      }
    }

    results.sort((a, b) => b.addedAt.compareTo(a.addedAt));
    return results;
  }

  static Future<StudioAsset> importFile({
    required String sourcePath,
    required AssetType type,
    required String resourcesDir,
  }) async {
    await ensureDirsExist(resourcesDir);
    final targetDir = getCategoryDir(resourcesDir, type);
    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) {
      throw Exception('Source file does not exist: $sourcePath');
    }

    final filename = p.basename(sourcePath);
    var targetPath = p.join(targetDir, filename);

    // If duplicate file exists, append timestamp
    if (await File(targetPath).exists()) {
      final ext = p.extension(filename);
      final stem = p.basenameWithoutExtension(filename);
      targetPath = p.join(targetDir, '${stem}_${DateTime.now().millisecondsSinceEpoch}$ext');
    }

    final copiedFile = await sourceFile.copy(targetPath);
    return StudioAsset.fromFile(copiedFile, type);
  }

  static Future<void> deleteAsset(StudioAsset asset) async {
    final file = File(asset.path);
    if (await file.exists()) {
      await file.delete();
    }
  }
}
