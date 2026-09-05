import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/app_constants.dart';
import '../core/app_colors.dart';
import '../core/providers.dart';
import '../core/engine_bridge.dart';
import '../core/ai_environment_service.dart';
import '../widgets/ai_setup_dialog.dart';
import '../widgets/update_dialog.dart';
import '../widgets/paywall_dialog.dart';
import '../widgets/license_dialog.dart';
import '../core/license_service.dart';
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
                AppConstants.appName,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(width: 8),
              // 📱 App GUI Version Chip (Click to check for update)
              InkWell(
                onTap: () => UpdateDialog.show(context),
                borderRadius: BorderRadius.circular(5),
                child: Tooltip(
                  message: 'Kiểm tra Cập nhật (App & Core)',
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF3B82F6).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(
                        color: const Color(0xFF3B82F6).withOpacity(0.4),
                        width: 1,
                      ),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.system_update_alt, size: 10.5, color: Color(0xFF60A5FA)),
                        SizedBox(width: 3.5),
                        Text(
                          AppConstants.appVersion,
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF60A5FA),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
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
              const SizedBox(width: 6),
              // 🔑 License Status Chip (Trial / Pro / Unlicensed)
              Consumer(
                builder: (context, ref, _) {
                  final license = ref.watch(licenseInfoProvider);
                  final isValid = license.isValid;
                  final isTrial = license.isTrial;

                  Color bg;
                  Color border;
                  Color fg;
                  IconData icon;
                  String label;

                  if (!isValid) {
                    bg = const Color(0xFFEF4444).withOpacity(0.15);
                    border = const Color(0xFFEF4444).withOpacity(0.4);
                    fg = const Color(0xFFF87171);
                    icon = Icons.warning_amber_rounded;
                    label = 'Chưa Kích Hoạt';
                  } else if (isTrial) {
                    bg = const Color(0xFFF59E0B).withOpacity(0.15);
                    border = const Color(0xFFF59E0B).withOpacity(0.4);
                    fg = const Color(0xFFFBBF24);
                    icon = Icons.vpn_key_outlined;
                    label = 'Dùng thử: ${license.daysRemaining} ngày';
                  } else {
                    bg = const Color(0xFF10B981).withOpacity(0.15);
                    border = const Color(0xFF10B981).withOpacity(0.4);
                    fg = const Color(0xFF34D399);
                    icon = Icons.workspace_premium;
                    label = license.isStudio
                        ? 'Studio'
                        : license.isCreator
                            ? 'Creator'
                            : 'Pro License';
                  }

                  return InkWell(
                    onTap: () => LicenseDialog.show(context),
                    borderRadius: BorderRadius.circular(6),
                    child: Tooltip(
                      message: 'Thông tin bản quyền & Kích hoạt máy (Click để xem)',
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                        decoration: BoxDecoration(
                          color: bg,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: border, width: 1),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(icon, size: 11.5, color: fg),
                            const SizedBox(width: 4),
                            Text(
                              label,
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg),
                            ),
                          ],
                        ),
                      ),
                    ),
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
              if (!context.mounted) return;
              if (selectedVideo != null) {
                _triggerPipeline(ref, context, selectedVideo.fullPath, ocrOnly: false);
              } else if (activeProject != null) {
                final srcDir = Directory(p.join(projectsDir, activeProject, 'src'));
                if (srcDir.existsSync()) {
                  final videos = srcDir.listSync().whereType<File>().where((f) => f.path.endsWith('.mp4')).toList();
                  if (videos.isNotEmpty) {
                    _triggerPipeline(ref, context, videos.first.path, ocrOnly: false);
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
              if (!context.mounted) return;
              if (selectedVideo != null) {
                _triggerPipeline(ref, context, selectedVideo.fullPath, ocrOnly: true);
              } else if (activeProject != null) {
                final srcDir = Directory(p.join(projectsDir, activeProject, 'src'));
                if (srcDir.existsSync()) {
                  final videos = srcDir.listSync().whereType<File>().where((f) => f.path.endsWith('.mp4')).toList();
                  if (videos.isNotEmpty) {
                    _triggerPipeline(ref, context, videos.first.path, ocrOnly: true);
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
              final license = ref.read(licenseInfoProvider);
              if (!license.isValid) {
                if (context.mounted) {
                  LicenseDialog.show(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('⚠️ Vui lòng kích hoạt bản quyền hoặc đăng ký nhận 7 ngày dùng thử miễn phí để tiếp tục!'),
                      backgroundColor: Color(0xFFD97706),
                    ),
                  );
                }
                return;
              }

              // Gói Creator không có quyền Resume -> Hiện Paywall Dialog Pro Studio
              if (!license.canUseResume) {
                if (context.mounted) {
                  PaywallDialog.show(
                    context,
                    featureName: 'Cơ Chế Resume Thông Minh',
                    featureDescription: 'Tự động phát hiện và tiếp tục quy trình tại bước gián đoạn gần nhất',
                  );
                }
                return;
              }

              await ref.read(configProvider.notifier).save();
              if (!context.mounted) return;
              if (selectedVideo != null && activeProject != null) {
                final isReady = await AiEnvironmentService.isAiReady();
                if (!isReady && context.mounted) {
                  final installed = await AiSetupDialog.show(context);
                  if (!installed) return;
                }
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
          // 🔄 Check for Updates Button
          IconButton(
            icon: const Icon(Icons.sync, size: 18, color: AppColors.textSecondary),
            tooltip: 'Kiểm tra Cập nhật (App & Core)',
            splashRadius: 18,
            onPressed: () => UpdateDialog.show(context),
          ),
          const SizedBox(width: 8),
          InkWell(
            onTap: () async {
              // Gửi request lên server để check quyền của thiết bị này
              final prevValid = ref.read(licenseInfoProvider).isValid;
              final latest = await ref.read(licenseInfoProvider.notifier).refresh();
              if (prevValid && !latest.isValid && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('⚠️ Bản quyền trên thiết bị này đã bị thu hồi hoặc đổi sang thiết bị khác trên Web Portal!'),
                    backgroundColor: Color(0xFFEF4444),
                    duration: Duration(seconds: 4),
                  ),
                );
              }
              if (context.mounted) {
                LicenseDialog.show(context);
              }
            },
            borderRadius: BorderRadius.circular(14),
            child: const Tooltip(
              message: 'Quản lý Tài khoản & Bản quyền',
              child: CircleAvatar(
                radius: 14,
                backgroundColor: Color(0xFFD97706),
                child: Icon(Icons.workspace_premium, size: 16, color: Colors.white),
              ),
            ),
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

  void _triggerPipeline(WidgetRef ref, BuildContext context, String videoPath, {required bool ocrOnly}) async {
    final license = ref.read(licenseInfoProvider);
    if (!license.isValid) {
      if (context.mounted) {
        LicenseDialog.show(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⚠️ Vui lòng kích hoạt bản quyền hoặc đăng ký nhận 7 ngày dùng thử miễn phí để tiếp tục!'),
            backgroundColor: Color(0xFFD97706),
          ),
        );
      }
      return;
    }

    final activeProject = ref.read(activeProjectProvider);
    if (activeProject == null) return;

    if (!ocrOnly) {
      final isReady = await AiEnvironmentService.isAiReady();
      if (!isReady && context.mounted) {
        final installed = await AiSetupDialog.show(context);
        if (!installed) return;
      }
    }

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
