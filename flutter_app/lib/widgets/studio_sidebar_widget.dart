import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import '../core/app_colors.dart';
import '../core/providers.dart';
import '../core/asset_library_service.dart';
import '../core/studio_state_notifier.dart';
import '../core/thumbnail_service.dart';
import '../models/studio_asset.dart';
import '../models/studio_state.dart';
import '../models/video_file.dart';
import '../utils/time_format_utils.dart';
import 'video_thumbnail_widget.dart';

enum VideoFilter { all, src, cut, merge, output }

class StudioSidebarWidget extends ConsumerStatefulWidget {
  final double width;
  final VoidCallback? onCollapse;

  const StudioSidebarWidget({
    super.key,
    this.width = 240,
    this.onCollapse,
  });

  @override
  ConsumerState<StudioSidebarWidget> createState() => _StudioSidebarWidgetState();
}

class _StudioSidebarWidgetState extends ConsumerState<StudioSidebarWidget> {
  int _activeTab = 0; // 0: Videos, 1: Nhạc, 2: SFX, 3: Lớp phủ
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  VideoFilter _videoFilter = VideoFilter.all;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final toolMode = ref.watch(studioToolModeProvider);
    final isMergeMode = toolMode == StudioToolMode.merge;
    final c = AppColors.of(context);

    return Container(
      width: widget.width,
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(
          right: BorderSide(color: c.border, width: 1),
        ),
      ),
      child: Column(
        children: [
          // 1. Sidebar Header with 4 Tab Icons
          Container(
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: BoxDecoration(
              color: c.surfaceDark,
              border: Border(bottom: BorderSide(color: c.border)),
            ),
            child: Row(
              children: [
                _buildTabBtn(0, Icons.video_library_outlined, 'Videos'),
                _buildTabBtn(1, Icons.music_note_outlined, 'Nhạc'),
                _buildTabBtn(2, Icons.mic_none_outlined, 'SFX'),
                _buildTabBtn(3, Icons.image_outlined, 'Lớp phủ'),
                if (widget.onCollapse != null) ...[
                  const Spacer(),
                  IconButton(
                    icon: Icon(Icons.chevron_left, size: 16, color: c.textSecondary),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    tooltip: 'Thu gọn sidebar',
                    onPressed: widget.onCollapse,
                  ),
                ],
              ],
            ),
          ),

          // 2. Search Box
          Container(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
            child: Container(
              height: 28,
              decoration: BoxDecoration(
                color: c.surfaceDark,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: c.border),
              ),
              child: TextField(
                controller: _searchController,
                style: TextStyle(color: c.textPrimary, fontSize: 11.5),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: _getSearchHint(),
                  hintStyle: TextStyle(color: c.textMuted, fontSize: 11),
                  prefixIcon: Icon(Icons.search, size: 14, color: c.textMuted),
                  prefixIconConstraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: Icon(Icons.close, size: 12, color: c.textMuted),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                          padding: EdgeInsets.zero,
                        )
                      : null,
                  suffixIconConstraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 6),
                ),
                onChanged: (val) => setState(() => _searchQuery = val.trim().toLowerCase()),
              ),
            ),
          ),

          // 3. Filter chips (Tab 0 only)
          if (_activeTab == 0) _buildVideoFilterChips(),

          // 4. Main Content List
          Expanded(
            child: _activeTab == 0
                ? _buildVideosList(isMergeMode)
                : _buildAssetsList(_getAssetTypeForTab(_activeTab)),
          ),

          // 5. Import Button Footer (Tab 1, 2, 3)
          if (_activeTab > 0)
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: c.surfaceDark,
                border: Border(top: BorderSide(color: c.border)),
              ),
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: c.surfaceLight,
                  foregroundColor: c.primary,
                  side: BorderSide(color: c.primary.withOpacity(0.5), width: 0.8),
                  minimumSize: const Size(double.infinity, 28),
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                ),
                icon: const Icon(Icons.add_circle_outline, size: 13),
                label: Text(
                  '+ Thêm ${_getTabName(_activeTab)} từ máy',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                ),
                onPressed: () => _handleImportAsset(_getAssetTypeForTab(_activeTab)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTabBtn(int tabIndex, IconData icon, String label) {
    final c = AppColors.of(context);
    final isSelected = _activeTab == tabIndex;
    return InkWell(
      onTap: () => setState(() {
        _activeTab = tabIndex;
        _searchController.clear();
        _searchQuery = '';
      }),
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        margin: const EdgeInsets.only(right: 2),
        decoration: BoxDecoration(
          color: isSelected ? c.surfaceLight : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: isSelected ? Border.all(color: c.primary, width: 0.8) : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 13,
              color: isSelected ? c.primary : c.textSecondary,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                color: isSelected ? c.textPrimary : c.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoFilterChips() {
    return Container(
      height: 24,
      margin: const EdgeInsets.fromLTRB(8, 2, 8, 4),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _buildFilterChip('Tất cả', VideoFilter.all),
          _buildFilterChip('📹 Gốc', VideoFilter.src),
          _buildFilterChip('✂️ Đã cắt', VideoFilter.cut),
          _buildFilterChip('🥞 Đã ghép', VideoFilter.merge),
          _buildFilterChip('✨ Đã dịch', VideoFilter.output),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, VideoFilter filter) {
    final isSelected = _videoFilter == filter;
    return GestureDetector(
      onTap: () => setState(() => _videoFilter = filter),
      child: Container(
        margin: const EdgeInsets.only(right: 4),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary.withOpacity(0.18) : AppColors.surfaceDark,
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.border,
            width: 0.8,
          ),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? AppColors.primary : AppColors.textSecondary,
            fontSize: 10,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildVideosList(bool isMergeMode) {
    final videosAsync = ref.watch(projectVideosProvider);
    final selectedVideo = ref.watch(selectedVideoProvider);

    return videosAsync.when(
      loading: () => const Center(
        child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary)),
      ),
      error: (e, _) => Center(child: Text('Lỗi: $e', style: const TextStyle(color: AppColors.statusFailed, fontSize: 11))),
      data: (map) {
        var all = <VideoFile>[];
        if (_videoFilter == VideoFilter.all || _videoFilter == VideoFilter.src) {
          all.addAll(map['srcFiles'] ?? []);
        }
        if (_videoFilter == VideoFilter.all || _videoFilter == VideoFilter.cut) {
          all.addAll(map['cutFiles'] ?? []);
        }
        if (_videoFilter == VideoFilter.all || _videoFilter == VideoFilter.merge) {
          all.addAll(map['mergeFiles'] ?? []);
        }
        if (_videoFilter == VideoFilter.all || _videoFilter == VideoFilter.output) {
          all.addAll(map['outputFiles'] ?? []);
        }

        if (_searchQuery.isNotEmpty) {
          all = all.where((v) => v.basename.toLowerCase().contains(_searchQuery)).toList();
        }

        if (all.isEmpty) {
          return const Center(
            child: Text('Không có video phù hợp', style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          itemCount: all.length,
          itemBuilder: (ctx, idx) {
            final video = all[idx];
            final isCurrent = selectedVideo?.fullPath == video.fullPath;

            return Container(
              margin: const EdgeInsets.only(bottom: 4),
              decoration: BoxDecoration(
                color: isCurrent ? AppColors.primary.withOpacity(0.12) : AppColors.surfaceDark,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: isCurrent ? AppColors.primary : AppColors.border,
                  width: isCurrent ? 1.0 : 0.6,
                ),
              ),
              child: ListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                leading: SizedBox(
                  width: 54,
                  height: 34,
                  child: VideoThumbnailWidget(
                    videoPath: video.fullPath,
                    width: 54,
                    height: 34,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                title: Text(
                  video.basename,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isCurrent ? AppColors.primary : Colors.white,
                    fontSize: 11,
                    fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
                subtitle: Text(
                  '${video.category.name.toUpperCase()} • ${TimeFormatUtils.formatFileSize(video.sizeBytes)}',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 10),
                ),
                trailing: isMergeMode
                    ? IconButton(
                        icon: const Icon(Icons.add_circle, size: 16, color: AppColors.statusCompleted),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        tooltip: 'Thêm vào danh sách ghép',
                        onPressed: () => _addVideoToMerge(video),
                      )
                    : (isCurrent
                        ? const Icon(Icons.check_circle, size: 14, color: AppColors.primary)
                        : null),
                onTap: () {
                  if (isMergeMode) {
                    _addVideoToMerge(video);
                  } else {
                    ref.read(selectedVideoProvider.notifier).state = video;
                  }
                },
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildAssetsList(AssetType type) {
    final assetsAsync = ref.watch(assetsLibraryProvider);

    return assetsAsync.when(
      loading: () => const Center(
        child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      error: (e, _) => Center(child: Text('Lỗi: $e', style: const TextStyle(color: Colors.red, fontSize: 11))),
      data: (allAssets) {
        var filtered = allAssets.where((a) => a.type == type).toList();
        if (_searchQuery.isNotEmpty) {
          filtered = filtered.where((a) => a.name.toLowerCase().contains(_searchQuery)).toList();
        }

        if (filtered.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  type == AssetType.overlay ? Icons.image_not_supported_outlined : Icons.audio_file_outlined,
                  size: 24,
                  color: const Color(0xFF64748B),
                ),
                const SizedBox(height: 6),
                Text(
                  'Chưa có ${_getTabName(_activeTab)}',
                  style: const TextStyle(color: Color(0xFF64748B), fontSize: 11),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Bấm nút bên dưới để thêm file',
                  style: TextStyle(color: Color(0xFF475569), fontSize: 9.5),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          itemCount: filtered.length,
          itemBuilder: (ctx, idx) {
            final asset = filtered[idx];
            return Container(
              margin: const EdgeInsets.only(bottom: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF0B1120),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFF1E293B), width: 0.8),
              ),
              child: ListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
                leading: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Icon(
                    type == AssetType.overlay
                        ? Icons.image
                        : (type == AssetType.music ? Icons.music_note : Icons.mic),
                    size: 13,
                    color: type == AssetType.music
                        ? const Color(0xFF34D399)
                        : (type == AssetType.sfx ? const Color(0xFF60A5FA) : const Color(0xFF38BDF8)),
                  ),
                ),
                title: Text(
                  asset.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 11),
                ),
                subtitle: Text(
                  TimeFormatUtils.formatFileSize(asset.sizeBytes),
                  style: const TextStyle(color: Color(0xFF64748B), fontSize: 9.5),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline, size: 15, color: Color(0xFF38BDF8)),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      tooltip: 'Chèn vào Timeline',
                      onPressed: () => _useAssetInTimeline(asset),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 15, color: Color(0xFFEF4444)),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      tooltip: 'Xoá khỏi kho',
                      onPressed: () => _confirmDeleteAsset(asset),
                    ),
                  ],
                ),
                onTap: () => _useAssetInTimeline(asset),
              ),
            );
          },
        );
      },
    );
  }

  void _confirmDeleteAsset(StudioAsset asset) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0F172A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: Color(0xFF334155)),
        ),
        title: const Text('Xác nhận xoá tệp', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
        content: Text(
          'Bạn có chắc muốn xoá "${asset.name}" khỏi kho tài nguyên không?',
          style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Huỷ', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              await AssetLibraryService.deleteAsset(asset);
              ref.read(assetsRefreshProvider.notifier).state++;
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Đã xoá "${asset.name}" khỏi kho tài nguyên')),
                );
              }
            },
            child: const Text('Xoá tệp', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _addVideoToMerge(VideoFile video) async {
    final dur = await ThumbnailService.instance.probeVideoDuration(video.fullPath);
    final item = MergeItem(
      id: 'merge_${video.stem}_${DateTime.now().millisecondsSinceEpoch}',
      name: video.basename,
      fullPath: video.fullPath,
      sizeBytes: video.sizeBytes,
      duration: dur > 0 ? dur : 10.0,
    );
    ref.read(studioStateProvider.notifier).addMergeItem(item);
  }

  void _useAssetInTimeline(StudioAsset asset) {
    final notifier = ref.read(studioStateProvider.notifier);
    if (asset.type == AssetType.music) {
      notifier.addAudioClip(AudioClip(
        id: 'aud_${DateTime.now().millisecondsSinceEpoch}',
        trackId: 'music',
        name: asset.name,
        fullPath: asset.path,
        start: 0,
        end: 30, // Default duration placeholder
        volume: 80,
      ));
    } else if (asset.type == AssetType.sfx) {
      notifier.addAudioClip(AudioClip(
        id: 'sfx_${DateTime.now().millisecondsSinceEpoch}',
        trackId: 'sfx',
        name: asset.name,
        fullPath: asset.path,
        start: 0,
        end: 5,
        volume: 60,
      ));
    } else if (asset.type == AssetType.overlay) {
      final tracks = ref.read(studioStateProvider).overlayTracks;
      final targetTrackId = tracks.isNotEmpty ? tracks.first.id : 'track-ov-1';
      notifier.addOverlayClip(OverlayClip(
        id: 'ov_${DateTime.now().millisecondsSinceEpoch}',
        trackId: targetTrackId,
        name: asset.name,
        imagePath: asset.path,
        start: 0,
        end: 10,
        x: 10,
        y: 10,
        width: 25,
        height: 25,
        opacity: 1.0,
      ));
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Đã chèn "${asset.name}" vào Timeline'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  Future<void> _handleImportAsset(AssetType type) async {
    List<String> allowedExts;
    FileType fileType;
    if (type == AssetType.overlay) {
      fileType = FileType.custom;
      allowedExts = ['png', 'jpg', 'jpeg', 'webp'];
    } else {
      fileType = FileType.custom;
      allowedExts = ['mp3', 'wav', 'm4a', 'aac', 'ogg', 'flac'];
    }

    final result = await FilePicker.platform.pickFiles(
      type: fileType,
      allowedExtensions: allowedExts,
      allowMultiple: false,
    );

    if (result != null && result.files.single.path != null) {
      final sourcePath = result.files.single.path!;
      final projectsDir = ref.read(projectsDirProvider);
      try {
        final imported = await AssetLibraryService.importFile(
          sourcePath: sourcePath,
          type: type,
          resourcesDir: projectsDir,
        );
        ref.read(assetsRefreshProvider.notifier).state++;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Đã thêm "${imported.name}" vào thư viện ${imported.type.name}')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Lỗi import: $e')),
          );
        }
      }
    }
  }

  AssetType _getAssetTypeForTab(int tab) {
    switch (tab) {
      case 1:
        return AssetType.music;
      case 2:
        return AssetType.sfx;
      case 3:
      default:
        return AssetType.overlay;
    }
  }

  String _getTabName(int tab) {
    switch (tab) {
      case 0:
        return 'Video';
      case 1:
        return 'Nhạc nền';
      case 2:
        return 'Hiệu ứng';
      case 3:
        return 'Lớp phủ';
      default:
        return '';
    }
  }

  String _getSearchHint() {
    switch (_activeTab) {
      case 0:
        return 'Tìm video trong dự án...';
      case 1:
        return 'Tìm nhạc nền...';
      case 2:
        return 'Tìm hiệu ứng SFX...';
      case 3:
        return 'Tìm ảnh lớp phủ...';
      default:
        return 'Tìm kiếm...';
    }
  }
}
