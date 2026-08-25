import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import '../models/studio_draft.dart';

class StudioDraftService {
  /// Lấy thư mục gốc chứa các bản nháp của dự án
  static Directory getProjectDraftsRoot(String projectDir) {
    return Directory(p.join(projectDir, 'workspace', 'drafts'));
  }

  /// Lấy thư mục chứa các bản nháp của 1 video cụ thể trong project
  static Directory getDraftsDirectory(String projectDir, String videoStem) {
    return Directory(p.join(projectDir, 'workspace', 'drafts', videoStem));
  }

  /// Quét và lấy danh sách tất cả các bản nháp trong toàn bộ dự án (sắp xếp theo thời gian mới nhất)
  static Future<List<StudioDraft>> listProjectDrafts(String projectDir) async {
    if (projectDir.isEmpty) return [];
    final rootDir = getProjectDraftsRoot(projectDir);
    if (!await rootDir.exists()) return [];

    final drafts = <StudioDraft>[];
    try {
      final entities = await rootDir.list(recursive: true).toList();
      for (final entity in entities) {
        if (entity is File && entity.path.endsWith('.json')) {
          try {
            final content = await entity.readAsString();
            final json = jsonDecode(content) as Map<String, dynamic>;
            drafts.add(StudioDraft.fromJson(json));
          } catch (e) {
            debugPrint('[StudioDraftService] Error parsing draft ${entity.path}: $e');
          }
        }
      }
      drafts.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    } catch (e) {
      debugPrint('[StudioDraftService] Error listing project drafts: $e');
    }
    return drafts;
  }

  /// Quét và lấy danh sách tất cả các bản nháp của video (sắp xếp theo thời gian mới nhất)
  static Future<List<StudioDraft>> listDrafts(String projectDir, String videoStem) async {
    if (projectDir.isEmpty) return [];
    final allDrafts = await listProjectDrafts(projectDir);
    if (videoStem.isEmpty) return allDrafts;
    return allDrafts.where((d) => d.videoStem == videoStem || d.videoPath.contains(videoStem)).toList();
  }

  /// Lưu hoặc ghi đè một bản nháp vào workspace/drafts/<videoStem>/
  static Future<bool> saveDraft(String projectDir, StudioDraft draft) async {
    try {
      final dir = getDraftsDirectory(projectDir, draft.videoStem);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      final file = File(p.join(dir.path, '${draft.id}.json'));
      await file.writeAsString(jsonEncode(draft.toJson()));
      return true;
    } catch (e) {
      debugPrint('[StudioDraftService] Error saving draft: $e');
      return false;
    }
  }

  /// Xoá một bản nháp
  static Future<bool> deleteDraft(String projectDir, String videoStem, String draftId) async {
    try {
      final rootDir = getProjectDraftsRoot(projectDir);
      if (!await rootDir.exists()) return false;

      final entities = await rootDir.list(recursive: true).toList();
      for (final entity in entities) {
        if (entity is File && entity.path.endsWith('$draftId.json')) {
          await entity.delete();
          return true;
        }
      }
    } catch (e) {
      debugPrint('[StudioDraftService] Error deleting draft: $e');
    }
    return false;
  }
}
