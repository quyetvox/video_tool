import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../../../../core/app_colors.dart';
import '../../../../models/video_file.dart';
import '../../../../widgets/app_kit.dart';
import '../../../../widgets/settings_section_card.dart';
import '../../../../widgets/video_thumbnail_widget.dart';
import '../controllers/movie_review_controller.dart';
import '../models/movie_review_model.dart';
import 'movie_video_picker_dialog.dart';

class ReviewScriptAndAiTab extends StatelessWidget {
  final MovieReviewState state;
  final MovieReviewController controller;
  final String? activeProject;
  final List<VideoFile> videoFiles;
  final TextEditingController apiKeyController;

  const ReviewScriptAndAiTab({
    super.key,
    required this.state,
    required this.controller,
    required this.apiKeyController,
    this.activeProject,
    this.videoFiles = const [],
  });

  void _openVideoPicker(BuildContext context) {
    final projectName = state.projectName ?? activeProject ?? 'default';
    showDialog(
      context: context,
      builder: (ctx) => MovieVideoPickerDialog(
        projectName: projectName,
        videoFiles: videoFiles,
        currentSelectedPath: state.videoPath,
        onVideoSelected: (file) {
          controller.selectVideoFromProject(
            projectName: projectName,
            videoPath: file.fullPath,
            videoName: file.name,
            apiKey: state.apiKey,
            aiModel: state.aiModel,
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final projectName = state.projectName ?? activeProject ?? 'default';

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // 1. CHỌN VIDEO TRONG PROJECT
        SettingsSectionCard(
          title: 'Video Phim Nguồn (src/)',
          icon: Icons.video_file_outlined,
          children: [
            if (state.videoPath != null) ...[
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: c.surfaceLight,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: c.border),
                ),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: VideoThumbnailWidget(
                        videoPath: state.videoPath!,
                        width: 72,
                        height: 44,
                        showDuration: true,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            state.videoName ?? '',
                            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Colors.white),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              const Icon(Icons.check_circle, size: 11, color: AppColors.statusCompleted),
                              const SizedBox(width: 4),
                              Text(
                                state.hasCachedData ? 'Đã có kịch bản lưu' : 'Đã chọn video',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: state.hasCachedData ? AppColors.statusCompleted : c.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.swap_horiz, size: 18, color: AppColors.primary),
                      tooltip: 'Đổi phim khác',
                      onPressed: () => _openVideoPicker(context),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ] else ...[
              SizedBox(
                width: double.infinity,
                height: 38,
                child: AppButton.primary(
                  icon: Icons.video_library,
                  label: 'Chọn phim từ project...',
                  onPressed: () => _openVideoPicker(context),
                ),
              ),
              const SizedBox(height: 8),
            ],

            SizedBox(
              width: double.infinity,
              child: AppButton.secondary(
                icon: Icons.folder_open,
                label: 'Chọn file từ máy tính...',
                onPressed: () async {
                  final result = await FilePicker.platform.pickFiles(
                    type: FileType.custom,
                    allowedExtensions: ['mp4', 'mkv', 'mov', 'avi', 'flv', 'webm', 'ts', 'm4v'],
                  );
                  if (result != null && result.files.single.path != null) {
                    final filePath = result.files.single.path!;
                    controller.selectVideoFromProject(
                      projectName: projectName,
                      videoPath: filePath,
                      videoName: p.basename(filePath),
                      apiKey: state.apiKey,
                      aiModel: state.aiModel,
                    );
                  }
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // 2. THỂ LOẠI & THỜI LƯỢNG MỤC TIÊU (SOP)
        SettingsSectionCard(
          title: 'Thể Loại & Thời Lượng SOP',
          icon: Icons.movie_outlined,
          children: [
            DropdownButtonFormField<MovieGenre>(
              value: state.genre,
              isExpanded: true,
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: c.surfaceLight,
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: c.border)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: c.border)),
              ),
              dropdownColor: c.surface,
              items: MovieGenre.values.map((g) {
                return DropdownMenuItem(
                  value: g,
                  child: Text('${g.label} (${g.recommendedRange})', style: const TextStyle(fontSize: 12, color: Colors.white)),
                );
              }).toList(),
              onChanged: (g) {
                if (g != null) controller.setGenre(g);
              },
            ),
            const SizedBox(height: 6),
            Text(
              state.genre.description,
              style: TextStyle(fontSize: 10, color: c.textMuted, fontStyle: FontStyle.italic),
            ),
            const SizedBox(height: 10),

            Row(
              children: [
                Icon(Icons.style_outlined, size: 14, color: c.textSecondary),
                const SizedBox(width: 6),
                Text('Phong cách kịch bản:', style: TextStyle(fontSize: 11.5, color: c.textSecondary, fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 6),
            DropdownButtonFormField<ReviewStyle>(
              value: state.reviewStyle,
              isExpanded: true,
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: c.surfaceLight,
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: c.border)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: c.border)),
              ),
              dropdownColor: c.surface,
              items: ReviewStyle.values.map((s) {
                return DropdownMenuItem(
                  value: s,
                  child: Text(s.label, style: const TextStyle(fontSize: 12, color: Colors.white)),
                );
              }).toList(),
              onChanged: (s) {
                if (s != null) controller.setReviewStyle(s);
              },
            ),
            const SizedBox(height: 6),
            Text(
              state.reviewStyle.description,
              style: TextStyle(fontSize: 10, color: c.textMuted, fontStyle: FontStyle.italic),
            ),
            const SizedBox(height: 10),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.auto_stories_outlined, size: 14, color: AppColors.primary),
                    const SizedBox(width: 6),
                    Text('Khai thác theo nội dung:', style: TextStyle(fontSize: 11.5, color: c.textSecondary, fontWeight: FontWeight.w600)),
                  ],
                ),
                Switch(
                  value: state.isContentDriven,
                  activeColor: AppColors.primary,
                  onChanged: (val) => controller.setContentDriven(val),
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (state.isContentDriven) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppColors.primary.withOpacity(0.25)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.auto_awesome, size: 14, color: AppColors.primary),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'AI tự động bám theo toàn bộ cốt truyện, lời thoại và mâu thuẫn để khai thác triệt để không giới hạn thời lượng (tự động mở rộng 70 – 110+ shot).',
                        style: TextStyle(fontSize: 10.5, color: AppColors.primary, height: 1.3),
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Thời lượng mục tiêu:', style: TextStyle(fontSize: 11.5, color: c.textSecondary)),
                  Text(
                    '${(state.targetDurationSec / 60).toStringAsFixed(1)} phút (${state.targetDurationSec}s)',
                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: AppColors.primary),
                  ),
                ],
              ),
              if (state.videoDuration > 0) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.auto_awesome, size: 11, color: AppColors.primary),
                    const SizedBox(width: 4),
                    Text(
                      'Khuyên dùng cho phim ${(state.videoDuration / 60).round()}p: ${(WordBudget.calculateOptimalDuration(state.videoDuration) / 60).round()} phút (${WordBudget.calculateOptimalDuration(state.videoDuration)}s)',
                      style: const TextStyle(fontSize: 10, color: AppColors.primary, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ],
              Slider(
                value: state.targetDurationSec.toDouble().clamp(60.0, 900.0),
                min: 60,
                max: 900,
                divisions: 14,
                activeColor: AppColors.primary,
                onChanged: (val) => controller.setTargetDuration(val.toInt()),
              ),
            ],
          ],
        ),
        const SizedBox(height: 10),

        // ── THÔNG ĐIỆP KỊCH BẢN (TÙY CHỌN) ──
        SettingsSectionCard(
          title: 'Thông Điệp Kịch Bản (Tùy Chọn)',
          icon: Icons.edit_note_rounded,
          subtitle: 'Gợi ý cốt truyện, góc nhìn hoặc plot twist cho AI',
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildPromptChip('🎬 Kịch tính & gay cấn', c),
                  const SizedBox(width: 6),
                  _buildPromptChip('🔍 Phân tích plot twist sâu', c),
                  const SizedBox(width: 6),
                  _buildPromptChip('😂 Hài hước & châm biếm duyên', c),
                  const SizedBox(width: 6),
                  _buildPromptChip('🎭 Đi sâu tâm lý nhân vật', c),
                ],
              ),
            ),
            const SizedBox(height: 8),
            TextFormField(
              key: ValueKey(state.customPrompt),
              initialValue: state.customPrompt,
              maxLines: 3,
              style: const TextStyle(fontSize: 12, color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Nhập gợi ý nội dung (VD: Nhấn mạnh vào bí mật gia đình của nhân vật chính, giọng điệu sâu lắng và kịch tính...)',
                hintStyle: TextStyle(fontSize: 11.5, color: c.textMuted.withOpacity(0.6)),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c.border)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c.border)),
                focusedBorder: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(8)), borderSide: BorderSide(color: AppColors.primary, width: 1.5)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                filled: true,
                fillColor: c.surfaceLight,
                suffixIcon: state.customPrompt.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 16),
                        tooltip: 'Xóa gợi ý',
                        onPressed: () => controller.setCustomPrompt(''),
                      )
                    : null,
              ),
              onChanged: (val) => controller.setCustomPrompt(val),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // 3. NGÔN NGỮ REVIEW & TỶ LỆ KHUNG HÌNH
        SettingsSectionCard(
          title: 'Ngôn Ngữ & Định Dạng Khung Hình',
          icon: Icons.aspect_ratio_outlined,
          children: [
            Row(
              children: [
                Text('Ngôn ngữ:', style: TextStyle(fontSize: 11.5, color: c.textSecondary)),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: state.targetLang,
                    isDense: true,
                    decoration: InputDecoration(
                      isDense: true,
                      filled: true,
                      fillColor: c.surfaceLight,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: c.border)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: c.border)),
                    ),
                    dropdownColor: c.surface,
                    items: const [
                      DropdownMenuItem(value: 'vi', child: Text('Tiếng Việt', style: TextStyle(fontSize: 11.5, color: Colors.white))),
                      DropdownMenuItem(value: 'en', child: Text('English', style: TextStyle(fontSize: 11.5, color: Colors.white))),
                      DropdownMenuItem(value: 'zh', child: Text('中文 (Trung)', style: TextStyle(fontSize: 11.5, color: Colors.white))),
                    ],
                    onChanged: (val) {
                      if (val != null) controller.setTargetLang(val);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _buildRatioOption(context, '16:9', '16:9 Ngang', Icons.crop_16_9, state.aspectRatio == '16:9'),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildRatioOption(context, '9:16', '9:16 Dọc', Icons.crop_portrait, state.aspectRatio == '9:16'),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 10),

        // 4. CẤU HÌNH AI GEMINI
        SettingsSectionCard(
          title: 'Cấu Hình AI Gemini',
          icon: Icons.psychology_outlined,
          children: [
            if (state.aiModel.isNotEmpty) ...[
              Row(
                children: [
                  Icon(Icons.smart_toy_outlined, size: 14, color: c.textSecondary),
                  const SizedBox(width: 6),
                  Text('Model:', style: TextStyle(fontSize: 11, color: c.textSecondary)),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: AppColors.primary.withOpacity(0.4)),
                    ),
                    child: Text(
                      state.aiModel,
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.primaryHover),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            TextFormField(
              controller: apiKeyController,
              obscureText: true,
              style: const TextStyle(fontSize: 12, color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Tự động đọc từ config.yaml...',
                hintStyle: TextStyle(fontSize: 11, color: c.textMuted),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                filled: true,
                fillColor: c.surfaceLight,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: c.border)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: c.border)),
              ),
              onChanged: (val) => controller.setApiKey(val),
            ),
            const SizedBox(height: 4),
            Text(
              'Đồng bộ với translator.api_key trong config.yaml',
              style: TextStyle(fontSize: 9.5, color: c.textMuted),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildRatioOption(BuildContext context, String ratio, String label, IconData icon, bool isSelected) {
    final c = AppColors.of(context);

    return InkWell(
      onTap: () => controller.setAspectRatio(ratio),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary.withOpacity(0.15) : c.surfaceLight,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected ? AppColors.primary : c.border,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: isSelected ? AppColors.primary : c.textSecondary),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? AppColors.primary : c.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPromptChip(String text, AppColorTokens c) {
    final isSelected = state.customPrompt == text;
    return InkWell(
      onTap: () {
        if (isSelected) {
          controller.setCustomPrompt('');
        } else {
          controller.setCustomPrompt(text);
        }
      },
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary.withOpacity(0.2) : c.surfaceLight,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected ? AppColors.primary : c.border.withOpacity(0.6),
            width: isSelected ? 1.2 : 0.8,
          ),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            color: isSelected ? AppColors.primary : c.textSecondary,
          ),
        ),
      ),
    );
  }
}
