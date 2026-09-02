import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/app_colors.dart';
import 'modern_sidebar.dart';
import 'top_header.dart';
import '../screens/video_editor_screen.dart';
import '../screens/video_studio_screen.dart';
import '../screens/douyin_downloader_screen.dart';
import '../screens/cloud_storage_screen.dart';
import '../screens/config_editor_screen.dart';
import '../screens/setup_screen.dart';
import '../widgets/log_console_widget.dart';

class MainLayout extends ConsumerStatefulWidget {
  const MainLayout({super.key});

  @override
  ConsumerState<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends ConsumerState<MainLayout> {
  int _selectedNavIndex = 0;
  String _activeLibraryFilter = 'all';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Row(
        children: [
          // 1. Left 250px Modern Sidebar
          ModernSidebar(
            selectedNavIndex: _selectedNavIndex,
            onSelectNav: (idx) => setState(() => _selectedNavIndex = idx),
            activeLibraryFilter: _activeLibraryFilter,
            onSelectLibraryFilter: (filter) {
              setState(() {
                _activeLibraryFilter = filter;
                _selectedNavIndex = 0; // Switch to Video Editor tab
              });
            },
          ),

          // 2. Right Main Work Area (TopHeader + Dynamic Screen)
          Expanded(
            child: Column(
              children: [
                // Top 52px Header
                TopHeader(
                  selectedNavIndex: _selectedNavIndex,
                  onSelectNav: (idx) => setState(() => _selectedNavIndex = idx),
                ),

                // Dynamic Body View
                Expanded(
                  child: IndexedStack(
                    index: _selectedNavIndex,
                    children: [
                      // 0: Video Editor Screen
                      VideoEditorScreen(libraryFilter: _activeLibraryFilter),
                      // 1: Ghép & Cắt Studio Screen
                      const VideoStudioScreen(),
                      // 2: Tải Video Screen
                      const DouyinDownloaderScreen(),
                      // 3: Cloud GCS Screen
                      const CloudStorageScreen(),
                      // 4: Cấu hình YAML Screen
                      const ConfigEditorScreen(),
                      // 5: Process Logs Screen
                      const Scaffold(
                        backgroundColor: AppColors.background,
                        body: LogConsoleWidget(),
                      ),
                      // 6: Cài Đặt (Setup & Paths) Screen
                      const SetupScreen(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
