import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'package:path/path.dart' as p;
import '../core/providers.dart';
import '../core/file_service.dart';

class ModernSidebar extends ConsumerWidget {
  final int selectedNavIndex;
  final Function(int) onSelectNav;
  final String activeLibraryFilter;
  final Function(String) onSelectLibraryFilter;

  const ModernSidebar({
    super.key,
    required this.selectedNavIndex,
    required this.onSelectNav,
    required this.activeLibraryFilter,
    required this.onSelectLibraryFilter,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeProject = ref.watch(activeProjectProvider);
    final projectsAsync = ref.watch(projectsProvider);
    final projectsDir = ref.watch(projectsDirProvider);
    final projectVideos = ref.watch(projectVideosProvider).value ?? {};

    final srcCount = projectVideos['srcFiles']?.length ?? 0;
    final cutCount = projectVideos['cutFiles']?.length ?? 0;
    final mergeCount = projectVideos['mergeFiles']?.length ?? 0;
    final outCount = projectVideos['outputFiles']?.length ?? 0;
    final allCount = srcCount + cutCount + mergeCount + outCount;

    return Container(
      width: 250,
      decoration: const BoxDecoration(
        color: Color(0xFF0B1120),
        border: Border(
          right: BorderSide(color: Color(0xFF1E293B), width: 1),
        ),
      ),
      child: Column(
        children: [
          // 1. Upload Video Action Button
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            child: PopupMenuButton<String>(
              offset: const Offset(0, 48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: const BorderSide(color: Color(0xFF334155)),
              ),
              color: const Color(0xFF1E293B),
              onSelected: (val) async {
                if (val == 'upload') {
                  final result = await FilePicker.platform.pickFiles(
                    type: FileType.custom,
                    allowedExtensions: ['mp4', 'mov', 'mkv', 'avi', 'flv', 'webm', 'ts', 'm4v'],
                  );
                  if (result != null && result.files.single.path != null && activeProject != null) {
                    final srcDir = Directory(p.join(projectsDir, activeProject, 'src'));
                    if (!srcDir.existsSync()) srcDir.createSync(recursive: true);
                    final srcFile = File(result.files.single.path!);
                    final destPath = p.join(srcDir.path, p.basename(srcFile.path));
                    srcFile.copySync(destPath);
                    ref.invalidate(projectVideosProvider);
                  }
                } else if (val == 'douyin') {
                  onSelectNav(2); // Nav index 2: Douyin Downloader
                } else if (val == 'new_proj') {
                  _showCreateProjectDialog(context, ref);
                }
              },
              itemBuilder: (ctx) => [
                const PopupMenuItem(
                  value: 'upload',
                  child: Row(
                    children: [
                      Icon(Icons.folder_open, size: 18, color: Color(0xFF06B6D4)),
                      SizedBox(width: 10),
                      Text('Chọn file từ máy tính', style: TextStyle(color: Colors.white, fontSize: 13)),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'douyin',
                  child: Row(
                    children: [
                      Icon(Icons.download, size: 18, color: Color(0xFF10B981)),
                      SizedBox(width: 10),
                      Text('Tải từ link Douyin', style: TextStyle(color: Colors.white, fontSize: 13)),
                    ],
                  ),
                ),
                const PopupMenuDivider(height: 1),
                const PopupMenuItem(
                  value: 'new_proj',
                  child: Row(
                    children: [
                      Icon(Icons.create_new_folder, size: 18, color: Color(0xFF8B5CF6)),
                      SizedBox(width: 10),
                      Text('Tạo Dự Án Mới', style: TextStyle(color: Colors.white, fontSize: 13)),
                    ],
                  ),
                ),
              ],
              child: Container(
                height: 40,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF2563EB), Color(0xFF06B6D4)],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF2563EB).withOpacity(0.35),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    )
                  ],
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add, color: Colors.white, size: 18),
                    SizedBox(width: 8),
                    Text(
                      '+ Upload Video',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(width: 4),
                    Icon(Icons.arrow_drop_down, color: Colors.white70, size: 18),
                  ],
                ),
              ),
            ),
          ),

          // 2. PROJECT Selector
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: Row(
              children: [
                const Text(
                  'PROJECT',
                  style: TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                const Spacer(),
                InkWell(
                  onTap: () => _showCreateProjectDialog(context, ref),
                  borderRadius: BorderRadius.circular(4),
                  child: const Padding(
                    padding: EdgeInsets.all(2),
                    child: Icon(Icons.add, size: 16, color: Color(0xFF94A3B8)),
                  ),
                )
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: Container(
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFF334155)),
              ),
              child: projectsAsync.when(
                data: (projects) {
                  final items = projects.map((p) => p.name).toList();
                  final current = activeProject != null && items.contains(activeProject)
                      ? activeProject
                      : (items.isNotEmpty ? items.first : null);

                  return DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: current,
                      isExpanded: true,
                      dropdownColor: const Color(0xFF1E293B),
                      icon: const Icon(Icons.keyboard_arrow_down, size: 18, color: Color(0xFF94A3B8)),
                      items: projects.map((proj) {
                        return DropdownMenuItem<String>(
                          value: proj.name,
                          child: Row(
                            children: [
                              const Icon(Icons.folder, size: 16, color: Color(0xFF06B6D4)),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '${proj.name} (${proj.srcCount} src, ${proj.outputCount} out)',
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12.5, color: Colors.white),
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          ref.read(activeProjectProvider.notifier).state = val;
                        }
                      },
                    ),
                  );
                },
                loading: () => const Center(child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))),
                error: (_, __) => const Text('Lỗi tải', style: TextStyle(color: Colors.red, fontSize: 12)),
              ),
            ),
          ),

          const SizedBox(height: 10),

          // 3. Scrollable Middle Section: LIBRARY, CLOUD, TOOLS, SYSTEM
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              children: [
                // ── LIBRARY ──
                _buildSectionHeader('LIBRARY'),
                _buildNavItem(
                  icon: Icons.video_collection_outlined,
                  title: 'All Videos',
                  count: allCount,
                  isActive: selectedNavIndex == 0 && activeLibraryFilter == 'all',
                  onTap: () {
                    onSelectNav(0);
                    onSelectLibraryFilter('all');
                  },
                ),
                _buildNavItem(
                  icon: Icons.file_download_outlined,
                  title: 'Gốc (Src)',
                  count: srcCount,
                  isActive: selectedNavIndex == 0 && activeLibraryFilter == 'src',
                  onTap: () {
                    onSelectNav(0);
                    onSelectLibraryFilter('src');
                  },
                ),
                _buildNavItem(
                  icon: Icons.content_cut,
                  title: 'Đã Cắt (Cut)',
                  count: cutCount,
                  isActive: selectedNavIndex == 0 && activeLibraryFilter == 'cut',
                  onTap: () {
                    onSelectNav(0);
                    onSelectLibraryFilter('cut');
                  },
                ),
                _buildNavItem(
                  icon: Icons.merge_type,
                  title: 'Đã Ghép (Merge)',
                  count: mergeCount,
                  isActive: selectedNavIndex == 0 && activeLibraryFilter == 'merge',
                  onTap: () {
                    onSelectNav(0);
                    onSelectLibraryFilter('merge');
                  },
                ),
                _buildNavItem(
                  icon: Icons.star_border,
                  title: 'Đã Dịch (Output)',
                  count: outCount,
                  iconColor: const Color(0xFFF59E0B),
                  isActive: selectedNavIndex == 0 && activeLibraryFilter == 'output',
                  onTap: () {
                    onSelectNav(0);
                    onSelectLibraryFilter('output');
                  },
                ),

                const SizedBox(height: 14),

                // ── CLOUD STORAGE ──
                _buildSectionHeader('CLOUD STORAGE'),
                _buildNavItem(
                  icon: Icons.cloud_queue,
                  title: 'Google Cloud (GCS)',
                  statusDotColor: const Color(0xFF10B981),
                  isActive: selectedNavIndex == 3,
                  onTap: () => onSelectNav(3),
                ),
                _buildNavItem(
                  icon: Icons.cloud_done_outlined,
                  title: 'R2 Storage',
                  statusBadge: 'Ready',
                  isActive: false,
                  onTap: () {},
                ),
                _buildNavItem(
                  icon: Icons.cloud_circle_outlined,
                  title: 'OneDrive',
                  isActive: false,
                  onTap: () {},
                ),

                const SizedBox(height: 14),

                // ── TOOLS ──
                _buildSectionHeader('TOOLS'),
                _buildNavItem(
                  icon: Icons.ondemand_video,
                  title: 'Video Editor',
                  isActive: selectedNavIndex == 0,
                  onTap: () => onSelectNav(0),
                ),
                _buildNavItem(
                  icon: Icons.movie_edit,
                  title: 'Ghép & Cắt Studio',
                  isActive: selectedNavIndex == 1,
                  onTap: () => onSelectNav(1),
                ),
                _buildNavItem(
                  icon: Icons.download_for_offline_outlined,
                  title: 'Tải Video Douyin',
                  isActive: selectedNavIndex == 2,
                  onTap: () => onSelectNav(2),
                ),

                const SizedBox(height: 14),

                // ── SYSTEM ──
                _buildSectionHeader('SYSTEM'),
                _buildNavItem(
                  icon: Icons.tune,
                  title: 'Config (YAML)',
                  isActive: selectedNavIndex == 4,
                  onTap: () => onSelectNav(4),
                ),
                _buildNavItem(
                  icon: Icons.terminal,
                  title: 'Process Logs',
                  isActive: selectedNavIndex == 5,
                  onTap: () => onSelectNav(5),
                ),
                _buildNavItem(
                  icon: Icons.settings_suggest_outlined,
                  title: 'Cài Đặt (Setup)',
                  isActive: selectedNavIndex == 6,
                  onTap: () => onSelectNav(6),
                ),
              ],
            ),
          ),

          // 4. Bottom Footer: Storage Usage & Profile
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: const BoxDecoration(
              color: Color(0xFF0F172A),
              border: Border(
                top: BorderSide(color: Color(0xFF1E293B), width: 1),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Storage Usage', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
                    Text('1.2 GB / 500 GB', style: TextStyle(color: Color(0xFF06B6D4), fontSize: 11, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: const LinearProgressIndicator(
                    value: 0.257,
                    backgroundColor: Color(0xFF1E293B),
                    valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF2563EB)),
                    minHeight: 5,
                  ),
                ),
                const SizedBox(height: 12),
                const Row(
                  children: [
                    CircleAvatar(
                      radius: 14,
                      backgroundColor: Color(0xFF2563EB),
                      child: Text('A', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                    SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('admin', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                        Text('Administrator', style: TextStyle(color: Color(0xFF64748B), fontSize: 10)),
                      ],
                    ),
                    Spacer(),
                    Icon(Icons.check_circle, size: 14, color: Color(0xFF10B981)),
                  ],
                )
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 4, 6, 6),
      child: Text(
        title,
        style: const TextStyle(
          color: Color(0xFF64748B),
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required IconData icon,
    required String title,
    int? count,
    Color? iconColor,
    Color? statusDotColor,
    String? statusBadge,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 1.5),
      child: Material(
        color: isActive ? const Color(0xFF1E293B) : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          hoverColor: const Color(0xFF1E293B).withOpacity(0.5),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7.5),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: iconColor ?? (isActive ? const Color(0xFF06B6D4) : const Color(0xFF94A3B8)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: isActive ? Colors.white : const Color(0xFFCBD5E1),
                      fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ),
                if (statusDotColor != null)
                  Container(
                    width: 7,
                    height: 7,
                    margin: const EdgeInsets.only(right: 2),
                    decoration: BoxDecoration(
                      color: statusDotColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                if (statusBadge != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: const Color(0xFF334155)),
                    ),
                    child: Text(
                      statusBadge,
                      style: const TextStyle(fontSize: 9.5, color: Color(0xFF94A3B8)),
                    ),
                  ),
                if (count != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: isActive ? const Color(0xFF334155) : const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '$count',
                      style: TextStyle(
                        fontSize: 10.5,
                        color: isActive ? Colors.white : const Color(0xFF94A3B8),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showCreateProjectDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController();
    final projectsDir = ref.read(projectsDirProvider);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0F172A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: Color(0xFF334155)),
        ),
        title: const Row(
          children: [
            Icon(Icons.create_new_folder, color: Color(0xFF06B6D4)),
            SizedBox(width: 8),
            Text('Tạo Dự Án Mới', style: TextStyle(color: Colors.white, fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Nhập tên thư mục dự án (ví dụ: foods, review, decor):',
              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12.5),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: controller,
              autofocus: true,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Tên dự án...',
                hintStyle: const TextStyle(color: Color(0xFF64748B)),
                filled: true,
                fillColor: const Color(0xFF1E293B),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Color(0xFF334155))),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Color(0xFF06B6D4))),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Thư mục đích: $projectsDir/<tên_dự_án>',
              style: const TextStyle(color: Color(0xFF64748B), fontSize: 11),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy', style: TextStyle(color: Color(0xFF94A3B8))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                FileService.createProject(projectsDir, name);
                ref.invalidate(projectsProvider);
                ref.read(activeProjectProvider.notifier).state = name;
                Navigator.pop(ctx);
              }
            },
            child: const Text('Tạo Dự Án'),
          ),
        ],
      ),
    );
  }
}
