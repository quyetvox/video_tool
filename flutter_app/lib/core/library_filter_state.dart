import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/video_file.dart';
import 'providers.dart';

/// Phân loại bộ lọc video trong mục LIBRARY của Sidebar
enum LibraryFilter {
  all,
  src,
  cut,
  merge,
  output,
}

extension LibraryFilterX on LibraryFilter {
  /// Mã định danh chuỗi chuẩn hóa dùng cho router / persistence
  String get id {
    switch (this) {
      case LibraryFilter.src:
        return 'src';
      case LibraryFilter.cut:
        return 'cut';
      case LibraryFilter.merge:
        return 'merge';
      case LibraryFilter.output:
        return 'output';
      case LibraryFilter.all:
      default:
        return 'all';
    }
  }

  /// Tên hiển thị người dùng (Tiếng Việt)
  String get label {
    switch (this) {
      case LibraryFilter.src:
        return 'Gốc (Src)';
      case LibraryFilter.cut:
        return 'Đã Cắt (Cut)';
      case LibraryFilter.merge:
        return 'Đã Ghép (Merge)';
      case LibraryFilter.output:
        return 'Đã Dịch (Output)';
      case LibraryFilter.all:
      default:
        return 'Tất cả (All)';
    }
  }

  /// Parse an toàn từ chuỗi id sang LibraryFilter enum
  static LibraryFilter fromId(String? id) {
    switch (id?.toLowerCase()) {
      case 'src':
        return LibraryFilter.src;
      case 'cut':
        return LibraryFilter.cut;
      case 'merge':
        return LibraryFilter.merge;
      case 'output':
        return LibraryFilter.output;
      case 'all':
      default:
        return LibraryFilter.all;
    }
  }

  /// Hàm thuần túy lọc danh sách video từ map projectVideos (srcFiles, cutFiles, mergeFiles, outputFiles)
  List<VideoFile> filterVideos(Map<String, List<VideoFile>>? videosMap) {
    if (videosMap == null) return const [];
    switch (this) {
      case LibraryFilter.src:
        return List.unmodifiable(videosMap['srcFiles'] ?? const []);
      case LibraryFilter.cut:
        return List.unmodifiable(videosMap['cutFiles'] ?? const []);
      case LibraryFilter.merge:
        return List.unmodifiable(videosMap['mergeFiles'] ?? const []);
      case LibraryFilter.output:
        return List.unmodifiable(videosMap['outputFiles'] ?? const []);
      case LibraryFilter.all:
      default:
        return List.unmodifiable([
          ...videosMap['srcFiles'] ?? const [],
          ...videosMap['cutFiles'] ?? const [],
          ...videosMap['mergeFiles'] ?? const [],
          ...videosMap['outputFiles'] ?? const [],
        ]);
    }
  }
}

/// Tập hợp các chỉ số tab Tool có hiển thị danh sách video và khu vực làm việc:
/// - 0: Video Editor Screen
/// - 1: Video Studio (Ghép & Cắt)
/// - 7: AI Review Phim
/// - 8: AI Kể Chuyện Vlog
const Set<int> videoToolNavIndices = {0, 1, 7, 8};

/// Kiểm tra một chỉ số tab có thuộc nhóm Tool video hay không
bool isVideoToolTab(int index) => videoToolNavIndices.contains(index);

/// Provider lưu trữ bộ lọc Library hiện hành
final libraryFilterProvider = StateProvider<LibraryFilter>((ref) => LibraryFilter.all);

/// Derived Provider tự động phản ứng và trả về danh sách video đã được lọc tương ứng
final filteredProjectVideosProvider = Provider<List<VideoFile>>((ref) {
  final videosMap = ref.watch(projectVideosProvider).value;
  final filter = ref.watch(libraryFilterProvider);
  return filter.filterVideos(videosMap);
});
