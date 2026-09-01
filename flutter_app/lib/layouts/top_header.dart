import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/app_colors.dart';
import '../core/providers.dart';
import '../core/engine_bridge.dart';
import 'dart:io';
import 'package:path/path.dart' as p;

class TopHeader extends ConsumerWidget {
  final int selectedNavIndex;
  final Function(int) onSelectNav;

  const TopHeader({
    super.key,
    required this.selectedNavIndex,
    required this.onSelectNav,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeProject = ref.watch(activeProjectProvider);
    final projectsDir = ref.watch(projectsDirProvider);
    final selectedVideo = ref.watch(selectedVideoProvider);
    final c = AppColors.of(context);

    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(
          bottom: BorderSide(color: c.border, width: 1),
        ),
      ),
      child: Row(
        children: [
          // 1. Logo & App Title
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.asset(
                  'assets/images/logo.png',
                  width: 28,
                  height: 28,
                  fit: BoxFit.cover,
                  errorBuilder: (ctx, err, stack) => Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: const Color(0xFF8B5CF6),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(Icons.bolt, color: Colors.white, size: 16),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                'Video Studio',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(width: 10),
              // ⚡ Engine Patch Version Chip
              Consumer(
                builder: (context, ref, _) {
                  final engineInfoAsync = ref.watch(activeEngineInfoProvider);
                  return engineInfoAsync.when(
                    data: (info) {
                      final isHotPatch = info.source == 'hot_patch';
                      return InkWell(
                        onTap: () => onSelectNav(4), // Jump to setup tab
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                          decoration: BoxDecoration(
                            color: isHotPatch
                                ? const Color(0xFF10B981).withOpacity(0.15)
                                : const Color(0xFF8B5CF6).withOpacity(0.15),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: isHotPatch
                                  ? const Color(0xFF10B981).withOpacity(0.4)
                                  : const Color(0xFF8B5CF6).withOpacity(0.4),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isHotPatch ? Icons.verified : Icons.bolt,
                                size: 11.5,
                                color: isHotPatch
                                    ? const Color(0xFF34D399)
                                    : const Color(0xFFA78BFA),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Patch ${info.version}',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: isHotPatch
                                      ? const Color(0xFF34D399)
                                      : const Color(0xFFA78BFA),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                    loading: () => const SizedBox.shrink(),
                    error: (_, __) => const SizedBox.shrink(),
                  );
                },
              ),
            ],
          ),

          const SizedBox(width: 16),

          // 2. Main Navigation Tabs (Flexible & Horizontal Scrollable)
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildNavTab(title: 'Video Editor', index: 0),
                  _buildNavTab(title: 'Cloud (GCS)', index: 3),
                  _buildNavTab(title: 'Logs', index: 5),
                  _buildNavTab(title: 'Cấu hình', index: 4),
                ],
              ),
            ),
          ),

          const SizedBox(width: 16),

          // 3. Quick Action Buttons
          // 💾 Save Config Button (Tự động chuyển Đã Lưu ✓ 2s rồi quay lại trạng thái sẵn sàng)
          Builder(
            builder: (context) {
              ref.watch(configProvider); // Watch state để tự re-render khi save/setField
              final notifier = ref.watch(configProvider.notifier);
              final hasUnsaved = notifier.hasUnsavedChanges;
              final isJustSaved = notifier.isJustSaved;
              final c = AppColors.of(context);

              Color bgColor;
              Color fgColor;
              String labelText;
              IconData iconData;

              if (isJustSaved) {
                bgColor = const Color(0xFF059669);
                fgColor = Colors.white;
                labelText = 'Đã Lưu ✓';
                iconData = Icons.check_circle;
              } else if (hasUnsaved) {
                bgColor = const Color(0xFF2563EB);
                fgColor = Colors.white;
                labelText = 'Lưu Cấu Hình';
                iconData = Icons.save;
              } else {
                bgColor = c.surfaceLight;
                fgColor = c.textSecondary;
                labelText = 'Lưu Cấu Hình';
                iconData = Icons.save_outlined;
              }

              return ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: bgColor,
                  foregroundColor: fgColor,
                  elevation: 0,
                  side: BorderSide(
                    color: isJustSaved
                        ? const Color(0xFF047857)
                        : (hasUnsaved ? const Color(0xFF1D4ED8) : c.border),
                    width: 1,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                ),
                icon: Icon(iconData, size: 14, color: fgColor),
                label: Text(
                  labelText,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fgColor),
                ),
                onPressed: () {
                  ref.read(configProvider.notifier).save();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('✅ Đã lưu cấu hình dự án thành công xuống file!'),
                      backgroundColor: AppColors.statusCompleted,
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
              );
            },
          ),

          const SizedBox(width: 8),

          // 🎙️ Voice Button (Xanh Ngọc #059669 - Chữ Trắng)
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF059669),
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            ),
            icon: const Icon(Icons.mic, size: 15, color: Colors.white),
            label: const Text('Voice', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Colors.white)),
            onPressed: () async {
              await ref.read(configProvider.notifier).save();
              if (selectedVideo != null) {
                _triggerPipeline(ref, selectedVideo.fullPath, ocrOnly: false);
              } else if (activeProject != null) {
                final srcDir = Directory(p.join(projectsDir, activeProject, 'src'));
                if (srcDir.existsSync()) {
                  final videos = srcDir.listSync().whereType<File>().where((f) => f.path.endsWith('.mp4')).toList();
                  if (videos.isNotEmpty) {
                    _triggerPipeline(ref, videos.first.path, ocrOnly: false);
                  }
                }
              }
            },
          ),

          const SizedBox(width: 8),

          // ⚡ Sub Button (Tím Indigo #7C3AED - Chữ Trắng)
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF7C3AED),
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            ),
            icon: const Icon(Icons.subtitles, size: 15, color: Colors.white),
            label: const Text('Sub', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Colors.white)),
            onPressed: () async {
              await ref.read(configProvider.notifier).save();
              if (selectedVideo != null) {
                _triggerPipeline(ref, selectedVideo.fullPath, ocrOnly: true);
              } else if (activeProject != null) {
                final srcDir = Directory(p.join(projectsDir, activeProject, 'src'));
                if (srcDir.existsSync()) {
                  final videos = srcDir.listSync().whereType<File>().where((f) => f.path.endsWith('.mp4')).toList();
                  if (videos.isNotEmpty) {
                    _triggerPipeline(ref, videos.first.path, ocrOnly: true);
                  }
                }
              }
            },
          ),

          const SizedBox(width: 8),

          // ▶️ Resume Button (Cam Hổ Phách #D97706 - Chữ Trắng)
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD97706),
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            ),
            icon: const Icon(Icons.play_arrow, size: 16, color: Colors.white),
            label: const Text('Resume', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Colors.white)),
            onPressed: () async {
              await ref.read(configProvider.notifier).save();
              if (selectedVideo != null && activeProject != null) {
                final jobId = 'resume_${selectedVideo.stem}';
                ref.read(runningPathsProvider.notifier).update((set) => {...set, selectedVideo.relPath, selectedVideo.stem, jobId});
                EngineBridge.resumeJob(
                  selectedVideo.fullPath,
                  projectId: activeProject,
                  jobId: jobId,
                ).then((_) {
                  ref.read(runningPathsProvider.notifier).update((set) => set.where((p) => !p.contains(selectedVideo.stem) && !p.contains(jobId)).toSet());
                });
              }
            },
          ),

          const SizedBox(width: 16),

          // 4. Utility Icons (Config, Notifications, Theme, User)
          // IconButton(
          //   icon: const Icon(Icons.tune, size: 18, color: AppColors.textSecondary),
          //   tooltip: 'Cấu hình nhanh',
          //   onPressed: () => onSelectNav(4),
          // ),
          // IconButton(
          //   icon: const Icon(Icons.notifications_none, size: 18, color: AppColors.textSecondary),
          //   tooltip: 'Thông báo',
          //   onPressed: () {},
          // ),
          // IconButton(
          //   icon: Icon(
          //     themeMode == ThemeMode.dark ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
          //     size: 18,
          //     color: AppColors.textSecondary,
          //   ),
          //   tooltip: 'Đổi chế độ Sáng / Tối',
          //   onPressed: () {
          //     ref.read(themeModeProvider.notifier).toggle();
          //   },
          // ),
          const SizedBox(width: 8),
          const CircleAvatar(
            radius: 14,
            backgroundColor: AppColors.primary,
            child: Text('A', style: TextStyle(color: AppColors.primaryText, fontSize: 12, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildNavTab({required String title, required int index}) {
    final isActive = selectedNavIndex == index;
    return InkWell(
      onTap: () => onSelectNav(index),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isActive ? AppColors.primary : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Text(
          title,
          style: TextStyle(
            color: isActive ? Colors.white : AppColors.textSecondary,
            fontSize: 13,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  void _triggerPipeline(WidgetRef ref, String videoPath, {required bool ocrOnly}) {
    final activeProject = ref.read(activeProjectProvider);
    if (activeProject == null) return;

    final stem = p.basenameWithoutExtension(videoPath);
    final jobId = 'job_$stem';

    ref.read(runningPathsProvider.notifier).state = {
      ...ref.read(runningPathsProvider),
      videoPath,
    };

    EngineBridge.translateVideo(
      videoPath,
      ocrOnly: ocrOnly,
      voice: !ocrOnly,
      jobId: jobId,
    ).then((_) {
      final current = Set<String>.from(ref.read(runningPathsProvider));
      current.remove(videoPath);
      ref.read(runningPathsProvider.notifier).state = current;
      ref.invalidate(projectVideosProvider);
    });
  }
}
