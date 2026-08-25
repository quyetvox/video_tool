import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
    final themeMode = ref.watch(themeModeProvider);

    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A),
        border: Border(
          bottom: BorderSide(color: Color(0xFF1E293B), width: 1),
        ),
      ),
      child: Row(
        children: [
          // 1. Logo & App Title
          Row(
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

          const SizedBox(width: 24),

          // 2. Main Navigation Tabs
          _buildNavTab(title: 'Video Editor', index: 0),
          _buildNavTab(title: 'Cloud (GCS)', index: 3),
          _buildNavTab(title: 'Logs', index: 5),
          _buildNavTab(title: 'Cấu hình', index: 4),

          const Spacer(),

          // 3. Quick Action Buttons
          // 💾 Save Config Button
          Builder(
            builder: (context) {
              final hasUnsaved = ref.watch(configProvider.notifier).hasUnsavedChanges;
              return ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: hasUnsaved ? const Color(0xFFF59E0B) : const Color(0xFF1E293B),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  side: BorderSide(color: hasUnsaved ? const Color(0xFFF59E0B) : const Color(0xFF334155), width: 1),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                ),
                icon: Icon(hasUnsaved ? Icons.save : Icons.check_circle_outline, size: 14),
                label: Text(
                  hasUnsaved ? '💾 Lưu Cấu Hình' : 'Đã Lưu',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
                onPressed: () {
                  ref.read(configProvider.notifier).save();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('✅ Đã lưu cấu hình dự án thành công xuống file!'),
                      backgroundColor: Color(0xFF10B981),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
              );
            },
          ),

          const SizedBox(width: 8),

          // 🎙️ Voice Button
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981).withOpacity(0.12),
              foregroundColor: const Color(0xFF10B981),
              elevation: 0,
              side: const BorderSide(color: Color(0xFF10B981), width: 1.5),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            icon: const Icon(Icons.mic, size: 15),
            label: const Text('Voice', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
            onPressed: () {
              ref.read(configProvider.notifier).save();
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

          // ⚡ Sub Button
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF59E0B).withOpacity(0.12),
              foregroundColor: const Color(0xFFF59E0B),
              elevation: 0,
              side: const BorderSide(color: Color(0xFFF59E0B), width: 1.5),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            icon: const Icon(Icons.subtitles, size: 15),
            label: const Text('Sub', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
            onPressed: () {
              if (selectedVideo != null) {
                _triggerPipeline(ref, selectedVideo.fullPath, ocrOnly: true);
              }
            },
          ),

          const SizedBox(width: 8),

          // ▶️ Resume Button
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF8B5CF6),
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            icon: const Icon(Icons.play_arrow, size: 16),
            label: const Text('Resume', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
            onPressed: () {
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
          IconButton(
            icon: const Icon(Icons.tune, size: 18, color: Color(0xFF94A3B8)),
            tooltip: 'Cấu hình nhanh',
            onPressed: () => onSelectNav(4),
          ),
          IconButton(
            icon: const Icon(Icons.notifications_none, size: 18, color: Color(0xFF94A3B8)),
            tooltip: 'Thông báo',
            onPressed: () {},
          ),
          IconButton(
            icon: Icon(
              themeMode == ThemeMode.dark ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
              size: 18,
              color: const Color(0xFF94A3B8),
            ),
            tooltip: 'Đổi chế độ Sáng / Tối',
            onPressed: () {
              ref.read(themeModeProvider.notifier).state =
                  themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
            },
          ),
          const SizedBox(width: 8),
          const CircleAvatar(
            radius: 14,
            backgroundColor: Color(0xFF2563EB),
            child: Text('A', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
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
              color: isActive ? const Color(0xFF06B6D4) : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Text(
          title,
          style: TextStyle(
            color: isActive ? Colors.white : const Color(0xFF94A3B8),
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
