import 'package:flutter/material.dart';
import '../../../../core/app_colors.dart';
import '../../../../models/video_file.dart';
import '../../../../widgets/app_kit.dart';
import '../controllers/movie_review_controller.dart';
import '../models/movie_review_model.dart';
import 'review_acts_structure_tab.dart';
import 'review_inpaint_and_logo_tab.dart';
import 'review_script_and_ai_tab.dart';
import 'review_subtitle_style_tab.dart';
import 'review_voice_audio_tab.dart';

class ReviewSidebarPanel extends StatefulWidget {
  final MovieReviewState state;
  final MovieReviewController controller;
  final String? activeProject;
  final List<VideoFile> videoFiles;
  final ValueChanged<int>? onTabChanged;

  const ReviewSidebarPanel({
    super.key,
    required this.state,
    required this.controller,
    this.activeProject,
    this.videoFiles = const [],
    this.onTabChanged,
  });

  @override
  State<ReviewSidebarPanel> createState() => _ReviewSidebarPanelState();
}

class _ReviewSidebarPanelState extends State<ReviewSidebarPanel> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late TextEditingController _apiKeyController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        widget.onTabChanged?.call(_tabController.index);
      }
    });
    _apiKeyController = TextEditingController(text: widget.state.apiKey);
  }

  @override
  void didUpdateWidget(covariant ReviewSidebarPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.state.apiKey != oldWidget.state.apiKey && widget.state.apiKey != _apiKeyController.text) {
      _apiKeyController.text = widget.state.apiKey;
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final state = widget.state;
    final controller = widget.controller;

    return Container(
      color: c.surface,
      child: Column(
        children: [
          // ── 1. SIDEBAR HEADER WITH PROJECT CHIP ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: c.border)),
            ),
            child: Row(
              children: [
                const Icon(Icons.auto_stories_outlined, size: 17, color: AppColors.primary),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Cấu Hình Review Phim',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ),
                if (widget.activeProject != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: AppColors.primary.withOpacity(0.4)),
                    ),
                    child: Text(
                      widget.activeProject!,
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.primaryHover),
                    ),
                  ),
              ],
            ),
          ),

          // ── 2. TABBAR HEADER (5 TABS) ──
          Container(
            height: 36,
            decoration: BoxDecoration(
              color: c.surfaceLight,
              border: Border(bottom: BorderSide(color: c.border)),
            ),
            child: TabBar(
              controller: _tabController,
              indicatorColor: AppColors.primary,
              indicatorWeight: 2.5,
              labelColor: AppColors.primary,
              unselectedLabelColor: c.textSecondary,
              labelStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
              unselectedLabelStyle: const TextStyle(fontSize: 10),
              labelPadding: const EdgeInsets.symmetric(horizontal: 4),
              onTap: (index) => widget.onTabChanged?.call(index),
              tabs: const [
                Tab(
                  iconMargin: EdgeInsets.zero,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.movie_creation_outlined, size: 12),
                      SizedBox(width: 3),
                      Text('Kịch Bản'),
                    ],
                  ),
                ),
                Tab(
                  iconMargin: EdgeInsets.zero,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.view_timeline_outlined, size: 12),
                      SizedBox(width: 3),
                      Text('Bố Cục'),
                    ],
                  ),
                ),
                Tab(
                  iconMargin: EdgeInsets.zero,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.subtitles_outlined, size: 12),
                      SizedBox(width: 3),
                      Text('Kiểu Sub'),
                    ],
                  ),
                ),
                Tab(
                  iconMargin: EdgeInsets.zero,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.brush_outlined, size: 12),
                      SizedBox(width: 3),
                      Text('Xóa Sub'),
                    ],
                  ),
                ),
                Tab(
                  iconMargin: EdgeInsets.zero,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.record_voice_over_outlined, size: 12),
                      SizedBox(width: 3),
                      Text('Âm Thanh'),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── 3. TABBARVIEW BODY (5 TABS) ──
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // Tab 1: Kịch bản, Phim nguồn & AI
                ReviewScriptAndAiTab(
                  state: state,
                  controller: controller,
                  activeProject: widget.activeProject,
                  videoFiles: widget.videoFiles,
                  apiKeyController: _apiKeyController,
                ),

                // Tab 2: Bố cục hồi & Tỷ lệ % (Hook, Story, Review, Outro)
                ReviewActsStructureTab(
                  state: state,
                  controller: controller,
                ),

                // Tab 3: Kiểu dáng phụ đề ASS (Sub Chính & Sub Phụ & SubBox)
                ReviewSubtitleStyleTab(
                  state: state,
                  controller: controller,
                ),

                // Tab 4: Xóa sub cũ (Inpaint Engine, Box Color) & Logo Watermark
                ReviewInpaintAndLogoTab(
                  state: state,
                  controller: controller,
                ),

                // Tab 5: Giọng đọc AI, Tốc độ, Ducking & 3 Luồng Âm Lượng
                ReviewVoiceAudioTab(
                  state: state,
                  controller: controller,
                ),
              ],
            ),
          ),

          // ── 4. BOTTOM ACTION BUTTONS (CỐ ĐỊNH Ở CHÂN) ──
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: c.surfaceLight,
              border: Border(top: BorderSide(color: c.border)),
            ),
            child: Column(
              children: [
                if (state.hasCachedData) ...[
                  SizedBox(
                    width: double.infinity,
                    height: 38,
                    child: AppButton.primary(
                      icon: Icons.movie_filter,
                      label: '🎬 DỰNG & XUẤT VIDEO NGAY',
                      isLoading: state.isRendering,
                      onPressed: state.isRendering ? null : () => controller.startRender(),
                    ),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    width: double.infinity,
                    height: 30,
                    child: AppButton.secondary(
                      icon: Icons.refresh,
                      label: 'Phân tích lại từ đầu (Gọi lại AI)',
                      isLoading: state.isAnalyzing,
                      onPressed: state.isAnalyzing ? null : () => controller.startAnalysis(),
                    ),
                  ),
                ] else ...[
                  SizedBox(
                    width: double.infinity,
                    height: 38,
                    child: AppButton.primary(
                      icon: Icons.rocket_launch,
                      label: '🚀 PHÂN TÍCH & TẠO KỊCH BẢN',
                      isLoading: state.isAnalyzing,
                      onPressed: state.videoPath == null || state.isAnalyzing
                          ? null
                          : () => controller.startAnalysis(),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
