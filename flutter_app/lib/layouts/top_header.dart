import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/app_constants.dart';
import '../core/app_colors.dart';
import '../core/providers.dart';
import '../widgets/update_dialog.dart';
import '../widgets/license_dialog.dart';
import '../core/license_service.dart';

class TopHeader extends ConsumerWidget {
  final int selectedNavIndex;
  final Function(int) onSelectNav;
  final VoidCallback? onToggleSidebar;
  final bool isSidebarCollapsed;

  const TopHeader({
    super.key,
    required this.selectedNavIndex,
    required this.onSelectNav,
    this.onToggleSidebar,
    this.isSidebarCollapsed = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
          // 0. Toggle Drawer Button
          if (onToggleSidebar != null) ...[
            Tooltip(
              message: isSidebarCollapsed ? 'Mở thanh bên (Sidebar)' : 'Thu gọn thanh bên (Sidebar)',
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onToggleSidebar,
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: isSidebarCollapsed ? c.primary.withOpacity(0.12) : Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: isSidebarCollapsed ? c.primary.withOpacity(0.3) : Colors.transparent,
                        width: 0.8,
                      ),
                    ),
                    child: Icon(
                      isSidebarCollapsed ? Icons.view_sidebar_outlined : Icons.view_sidebar,
                      size: 18,
                      color: isSidebarCollapsed ? c.primary : c.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],

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
                        onTap: () => onSelectNav(6), // Jump to setup tab (index 6)
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

          const Spacer(),

          // 2. Quick Action Buttons
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

          const SizedBox(width: 12),

          // 3. Utility Icons (Check Updates, License Dialog)
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
}

