import 'package:flutter/material.dart';
import '../../../../core/app_colors.dart';
import '../../../../models/video_file.dart';
import '../controllers/movie_review_controller.dart';
import '../models/movie_review_model.dart';
import 'review_acts_structure_tab.dart';
import 'review_inpaint_and_logo_tab.dart';
import 'review_script_and_ai_tab.dart';
import 'review_storyboard_panel.dart';
import 'review_subtitle_style_tab.dart';
import 'review_voice_audio_tab.dart';

class ReviewInspectorCard extends StatefulWidget {
  final MovieReviewState state;
  final MovieReviewController controller;
  final String? activeProject;
  final List<VideoFile> videoFiles;
  final Function(double sec)? onSeekToTime;

  const ReviewInspectorCard({
    super.key,
    required this.state,
    required this.controller,
    this.activeProject,
    this.videoFiles = const [],
    this.onSeekToTime,
  });

  @override
  State<ReviewInspectorCard> createState() => _ReviewInspectorCardState();
}

class _ReviewInspectorCardState extends State<ReviewInspectorCard> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late TextEditingController _apiKeyController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
    _apiKeyController = TextEditingController(text: widget.state.apiKey);
  }

  @override
  void didUpdateWidget(covariant ReviewInspectorCard oldWidget) {
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
      decoration: BoxDecoration(
        color: c.surfaceDark,
      ),
      child: Column(
        children: [
          // ── TABBAR HEADER ──
          Container(
            height: 38,
            decoration: BoxDecoration(
              color: c.surfaceDark,
              border: Border(bottom: BorderSide(color: c.border)),
            ),
            child: TabBar(
              controller: _tabController,
              indicatorColor: c.primary,
              indicatorWeight: 2,
              labelColor: c.primary,
              unselectedLabelColor: c.textSecondary,
              labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [
                const Tab(text: '🍿 Kịch Bản & Cốt Truyện'),
                Tab(text: '🎬 Storyboard (${state.segments.length})'),
                const Tab(text: '📊 Cấu Trúc 3 Hồi & SOP'),
                const Tab(text: '📐 Kiểu Phụ Đề'),
                const Tab(text: '🛡️ Khiên Bản Quyền & Inpaint'),
                const Tab(text: '🎙️ Giọng Đọc & 3 Luồng Âm'),
              ],
            ),
          ),

          // ── TABBAR VIEWS ──
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // TAB 0: KỊCH BẢN & CỐT TRUYỆN AI
                ReviewScriptAndAiTab(
                  state: state,
                  controller: controller,
                  apiKeyController: _apiKeyController,
                  activeProject: widget.activeProject,
                  videoFiles: widget.videoFiles,
                ),

                // TAB 1: STORYBOARD PHÂN CẢNH
                ReviewStoryboardPanel(
                  state: state,
                  controller: controller,
                ),

                // TAB 2: CẤU TRÚC 3 HỒI & SOP
                ReviewActsStructureTab(
                  state: state,
                  controller: controller,
                ),

                // TAB 3: KIỂU PHỤ ĐỀ
                ReviewSubtitleStyleTab(
                  state: state,
                  controller: controller,
                ),

                // TAB 4: KHIÊN BẢN QUYỀN & INPAINT
                ReviewInpaintAndLogoTab(
                  state: state,
                  controller: controller,
                ),

                // TAB 5: GIỌNG ĐỌC & 3 LUỒNG ÂM THANH
                ReviewVoiceAudioTab(
                  state: state,
                  controller: controller,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
