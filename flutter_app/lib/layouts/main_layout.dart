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
import '../screens/movie_review/movie_review_screen.dart';
import '../screens/vlog_story/vlog_story_screen.dart';
import '../widgets/log_console_widget.dart';
import '../widgets/resizable_collapsible_panel.dart';
import '../core/library_filter_state.dart';

class MainLayout extends ConsumerStatefulWidget {
  const MainLayout({super.key});

  @override
  ConsumerState<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends ConsumerState<MainLayout> {
  int _selectedNavIndex = 0;
  final GlobalKey<ResizableCollapsiblePanelState> _sidebarPanelKey = GlobalKey<ResizableCollapsiblePanelState>();
  bool _isSidebarCollapsed = false;

  @override
  Widget build(BuildContext context) {
    final activeFilter = ref.watch(libraryFilterProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: ResizableCollapsiblePanel(
        key: _sidebarPanelKey,
        side: PanelSide.left,
        initialWidth: 250.0,
        minWidth: 180.0,
        maxWidth: 380.0,
        collapseTooltip: 'Thu gọn thanh điều hướng',
        expandTooltip: 'Mở rộng thanh điều hướng',
        onCollapseChanged: (collapsed) => setState(() => _isSidebarCollapsed = collapsed),
        panel: ModernSidebar(
          selectedNavIndex: _selectedNavIndex,
          onSelectNav: (idx) => setState(() => _selectedNavIndex = idx),
          activeLibraryFilter: activeFilter.id,
          onSelectLibraryFilter: (filterId) {
            final filter = LibraryFilterX.fromId(filterId);
            ref.read(libraryFilterProvider.notifier).state = filter;
            // Chỉ chuyển về tab Video Editor (0) nếu tab hiện tại không phải là tab Tool có video
            if (!isVideoToolTab(_selectedNavIndex)) {
              setState(() => _selectedNavIndex = 0);
            }
          },
        ),
        child: Column(
          children: [
            // Top 52px Header
            TopHeader(
              selectedNavIndex: _selectedNavIndex,
              onSelectNav: (idx) => setState(() => _selectedNavIndex = idx),
              onToggleSidebar: () => _sidebarPanelKey.currentState?.toggleCollapse(),
              isSidebarCollapsed: _isSidebarCollapsed,
            ),

            // Dynamic Body View
            Expanded(
              child: IndexedStack(
                index: _selectedNavIndex,
                children: [
                  // 0: Video Editor Screen
                  VideoEditorScreen(libraryFilter: activeFilter.id),
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
                  // 7: AI Review Phim Screen
                  const MovieReviewScreen(),
                  // 8: AI Kể Chuyện Vlog Screen
                  const VlogStoryScreen(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

